import AppKit
import Foundation
import Observation

enum CustomFieldRunOutcome: Equatable {
    case started
    case coalesced
    case unsupported
}

enum SidebarSide: String, Codable, CaseIterable {
    case left, right

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

@Observable
@MainActor
final class StatusLineMonitor {
    enum ClaudeLifecycle { case unknown, working, stopped }
    enum CursorLifecycle { case unknown, working, stopped }

    private(set) var currentData: StatusLineData?
    private(set) var claudeLifecycle: ClaudeLifecycle = .unknown
    private(set) var cursorLifecycle: CursorLifecycle = .unknown
    var isClaudeWorking: Bool { claudeLifecycle == .working }
    var isClaudeStopped: Bool { claudeLifecycle == .stopped }
    var isCursorWorking: Bool { cursorLifecycle == .working }
    var isCursorStopped: Bool { cursorLifecycle == .stopped }
    private(set) var isOpenCodeWorking = false

    private let paneID: UUID
    private let paneName: String
    private let tabID: UUID
    private let tabName: String
    let filePath: String
    let settingsFilePath: String
    let attentionSignalFilePath: String
    let hookLogFilePath: String
    let hookLogScriptFilePath: String
    let codexHookRecordFilePath: String
    let codexHookScriptFilePath: String
    private let workingDirectory: String?
    let harness: Harness
    private let isClaude: Bool
    private let providerContext: StatusProviderContext?
    private var statusWatcher: FileSystemEventWatcher?
    private var attentionWatcher: FileSystemEventWatcher?
    private var hookLogWatcher: FileSystemEventWatcher?
    private var attentionOffset: UInt64 = 0
    private var attentionLineBuffer = Data()
    private var hookLogOffset: UInt64 = 0
    private var hookLogLineBuffer = Data()
    private var attentionDebounceWork: DispatchWorkItem?
    private var lastAttentionPayloadFingerprint: Int?
    private var pendingStopWork: DispatchWorkItem?
    private var hasConfirmedBackgroundWork = false
    var stopNotificationGracePeriod: TimeInterval = 1.8
    private var agnosticProvider: (any StatusLineDataProvider)?
    private var gitDiffTimer: Timer?
    private var cachedGitStats: (added: Int, removed: Int) = (0, 0)
    private var cachedRepoIdentity: StatusLineData.Repo?
    private var lastAppliedModificationDate: Date?
    var profileName: String?
    private let customFieldEnvironment: [String: String]
    private var cachedCustomFieldValues: [String: CustomFieldRenderValue] = [:]
    private var customFieldTimers: [String: Timer] = [:]
    private var scheduledCustomFields: [String: CustomStatusLineField] = [:]
    private var customFieldGenerations: [String: Int] = [:]
    private var customFieldInFlight: [String: Int] = [:]

    var onClaudeHookAttention: ((PaneAttentionEvent) -> Void)?
    var onClaudeStopped: (() -> Void)?
    var onOpencodeStopped: (() -> Void)?
    var onOpencodeActivityChanged: ((Bool) -> Void)?
    var onOpencodeSessionBound: ((String) -> Void)?
    var onOpencodePermissionReplied: (() -> Void)?
    var onOpencodePortRaceLost: (() -> Void)?
    var onPRMerged: ((_ prNumber: Int, _ prTitle: String) -> Void)?
    var onPRClosed: ((_ prNumber: Int, _ prTitle: String) -> Void)?
    var onPRReopened: (() -> Void)?

    private var lastKnownPRState: String?
    private var hasFiredResolutionNotification = false

    init(
        paneID: UUID,
        paneName: String = "",
        workingDirectory: String? = nil,
        harness: Harness,
        processStartTime: Date = Date(),
        tabID: UUID = UUID(),
        tabName: String = "",
        opencodePort: Int? = nil,
        opencodeSessionID: String? = nil,
        opencodeEnvironment: [String: String] = [:],
        customFieldEnvironment: [String: String] = [:]
    ) {
        self.paneID = paneID
        self.paneName = paneName.isEmpty ? String(paneID.uuidString.prefix(8)) : paneName
        self.tabID = tabID
        self.tabName = tabName
        self.workingDirectory = workingDirectory
        self.harness = harness
        self.isClaude = harness == .claude
        self.customFieldEnvironment = customFieldEnvironment
        filePath = NSTemporaryDirectory() + "agent-session-manager-status-\(paneID.uuidString).json"
        settingsFilePath = NSTemporaryDirectory() + "agent-session-manager-settings-\(paneID.uuidString).json"
        attentionSignalFilePath =
            NSTemporaryDirectory() + "agent-session-manager-claude-attention-\(paneID.uuidString).jsonl"
        hookLogFilePath =
            NSTemporaryDirectory() + "agent-session-manager-claude-hooklog-\(paneID.uuidString).jsonl"
        hookLogScriptFilePath =
            NSTemporaryDirectory() + "agent-session-manager-claude-hooklog-script-\(paneID.uuidString).py"
        codexHookRecordFilePath =
            NSTemporaryDirectory() + "agent-session-manager-codex-session-\(paneID.uuidString).json"
        codexHookScriptFilePath =
            NSTemporaryDirectory() + "agent-session-manager-codex-hook-\(paneID.uuidString).py"
        let resolvedPaneName = self.paneName
        let resolvedCodexHookRecordPath = codexHookRecordFilePath
        providerContext = workingDirectory.map { cwd in
            StatusProviderContext(
                paneID: paneID,
                paneName: resolvedPaneName,
                tabID: tabID,
                tabName: tabName,
                workingDirectory: cwd,
                harness: harness,
                processStartTime: processStartTime,
                launchArgs: [],
                environment: [:],
                detectedHarnessVersion: nil,
                codexHookRecordPath: harness == .codex ? resolvedCodexHookRecordPath : nil,
                opencodePort: opencodePort,
                opencodeSessionID: opencodeSessionID,
                opencodeEnvironment: opencodeEnvironment
            )
        }

        if !isClaude, let cwd = workingDirectory {
            let provider: any StatusLineDataProvider
            if harness == .cursor {
                provider = CursorDataProvider(
                    workingDirectory: cwd, paneID: paneID, processStartTime: processStartTime,
                    paneName: self.paneName, tabID: tabID, tabName: tabName)
            } else if harness == .codex, let providerContext {
                provider = CodexStatusProvider(context: providerContext)
            } else if harness == .opencode, let providerContext {
                let opencodeProvider = OpenCodeStatusProvider(context: providerContext)
                opencodeProvider.onActivityChanged = { [weak self] isWorking in
                    Task { @MainActor in
                        guard let self else { return }
                        self.isOpenCodeWorking = isWorking
                        self.onOpencodeActivityChanged?(isWorking)
                    }
                }
                opencodeProvider.onOpencodeStopped = { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        TracingService.shared.record(
                            "statusline.opencode.stop.received",
                            attributes: [
                                "pane.name": self.paneName, "pane.id": self.paneID.uuidString,
                                "tab.id": self.tabID.uuidString, "tab.name": self.tabName,
                            ])
                        self.onOpencodeStopped?()
                    }
                }
                opencodeProvider.onSessionBound = { [weak self] id in
                    Task { @MainActor in
                        guard let self else { return }
                        TracingService.shared.record(
                            "statusline.opencode.session.bound.received",
                            attributes: [
                                "pane.name": self.paneName, "pane.id": self.paneID.uuidString,
                                "tab.id": self.tabID.uuidString, "tab.name": self.tabName,
                                "session_id_prefix": String(id.prefix(12)),
                            ])
                        self.onOpencodeSessionBound?(id)
                    }
                }
                opencodeProvider.onPermissionReplied = { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        self.onOpencodePermissionReplied?()
                    }
                }
                opencodeProvider.onPortRaceLost = { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        self.onOpencodePortRaceLost?()
                    }
                }
                provider = opencodeProvider
            } else {
                let toolCmd = harness.commandDescription
                provider = ToolAgnosticDataProvider(
                    workingDirectory: cwd, toolCommand: toolCmd, processStartTime: processStartTime)
            }
            if let cursorProvider = provider as? CursorDataProvider {
                cursorProvider.onActivityChanged = { [weak self] isWorking in
                    guard let self else { return }
                    self.applyCursorActivity(isWorking: isWorking)
                }
            }
            agnosticProvider = provider
            agnosticProvider?.onUpdate = { [weak self] data in
                guard let self else { return }
                self.applyProviderSnapshot(data, providerName: self.harness.rawValue)
            }
            agnosticProvider?.onAttention = { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    TracingService.shared.record(
                        "statusline.attention.received",
                        attributes: [
                            "pane.name": self.paneName, "pane.id": self.paneID.uuidString,
                            "tab.id": self.tabID.uuidString, "tab.name": self.tabName,
                            "source": event.source.rawValue, "reason": event.reason,
                        ])
                    self.onClaudeHookAttention?(event)
                }
            }
        }
    }

    func start() {
        if isClaude {
            writeSettingsFile()
            TracingService.shared.record(
                "statusline.monitor.started",
                attributes: [
                    "pane.name": paneName,
                    "pane.id": paneID.uuidString,
                    "tab.id": tabID.uuidString,
                    "tab.name": tabName,
                ])
            FileManager.default.createFile(atPath: filePath, contents: nil)
            FileManager.default.createFile(
                atPath: hookLogFilePath, contents: nil, attributes: [.posixPermissions: 0o600])
            writeHookLogScript()

            statusWatcher = makeFileWatcher(
                path: filePath,
                role: "status_payload",
                followsReplacement: true
            ) { [weak self] event in
                self?.applyLatestPayload(
                    reason: event == .fileReplaced ? "vnode_reopen" : "vnode_write")
            }
            statusWatcher?.start()
            hookLogOffset = 0
            hookLogLineBuffer = Data()
            hookLogWatcher = makeFileWatcher(
                path: hookLogFilePath,
                role: "hook_log",
                followsReplacement: false
            ) { [weak self] _ in
                guard let self,
                    let handle = FileHandle(forReadingAtPath: hookLogFilePath)
                else { return }
                defer { try? handle.close() }
                do {
                    try handle.seek(toOffset: hookLogOffset)
                    while let data = try handle.read(upToCount: 65_536), !data.isEmpty {
                        hookLogOffset += UInt64(data.count)
                        hookLogLineBuffer.append(data)
                        while let newlineIndex = hookLogLineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                            let lineData = Data(hookLogLineBuffer[..<newlineIndex])
                            let afterNewline = hookLogLineBuffer.index(after: newlineIndex)
                            hookLogLineBuffer = Data(hookLogLineBuffer[afterNewline...])
                            guard !lineData.isEmpty else { continue }
                            applyClaudeActivityPayload(lineData)
                        }
                    }
                } catch {}
            }
            hookLogWatcher?.start()

            if let cwd = workingDirectory {
                Task { [weak self] in
                    guard let self else { return }
                    if let stats = await GitDiffStats.compute(in: cwd) {
                        await MainActor.run { self.cachedGitStats = stats }
                    }
                }
                startRepoIdentityFetch(cwd: cwd)
                gitDiffTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    Task { [weak self] in
                        guard let self else { return }
                        if let stats = await GitDiffStats.compute(in: cwd) {
                            await MainActor.run { self.cachedGitStats = stats }
                        }
                        await MainActor.run { self.checkPayloadFreshness() }
                    }
                }
            }

            stopAttentionWatcher()
            FileManager.default.createFile(
                atPath: attentionSignalFilePath, contents: nil, attributes: [.posixPermissions: 0o600])
            attentionWatcher = makeFileWatcher(
                path: attentionSignalFilePath,
                role: "attention",
                followsReplacement: false
            ) { [weak self] _ in
                guard let self else { return }
                guard attentionDebounceWork == nil else { return }
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    attentionDebounceWork = nil
                    guard let handle = FileHandle(forReadingAtPath: attentionSignalFilePath) else { return }
                    defer { try? handle.close() }
                    do {
                        try handle.seek(toOffset: attentionOffset)
                        while let data = try handle.read(upToCount: 65_536), !data.isEmpty {
                            attentionOffset += UInt64(data.count)
                            attentionLineBuffer.append(data)
                            while let newline = attentionLineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                                let line = Data(attentionLineBuffer[..<newline])
                                let next = attentionLineBuffer.index(after: newline)
                                attentionLineBuffer = Data(attentionLineBuffer[next...])
                                guard !line.isEmpty else { continue }
                                applyClaudeAttentionPayload(line)
                            }
                        }
                    } catch {
                        TracingService.shared.record(
                            "statusline.attention.read_failed",
                            attributes: [
                                "pane.name": paneName, "pane.id": paneID.uuidString,
                                "tab.id": tabID.uuidString, "tab.name": tabName,
                                "error_code": "\((error as NSError).code)",
                            ])
                    }
                }
                attentionDebounceWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
            attentionWatcher?.start()
        } else {
            TracingService.shared.record(
                "statusline.provider.started",
                attributes: providerTraceAttributes(providerName: harness.rawValue))
            agnosticProvider?.start()
        }

        if let cwd = workingDirectory {
            PRTrackingCoordinator.shared.subscribe(
                paneID: paneID,
                workingDirectory: cwd,
                isActive: true,
                paneName: paneName,
                tabID: tabID,
                tabName: tabName
            ) { [weak self] pr in
                guard let self else { return }
                if self.currentData == nil {
                    self.currentData = .empty(pr: pr)
                } else {
                    self.currentData?.pr = pr
                }
                self.checkForPRResolutionTransition(pr)
            }
        }
    }

    func stop() {
        statusWatcher?.cancel()
        statusWatcher = nil
        hookLogWatcher?.cancel()
        hookLogWatcher = nil
        gitDiffTimer?.invalidate()
        gitDiffTimer = nil
        for timer in customFieldTimers.values { timer.invalidate() }
        customFieldTimers = [:]
        scheduledCustomFields = [:]
        cachedCustomFieldValues = [:]
        customFieldGenerations = [:]
        customFieldInFlight = [:]
        TracingService.shared.record(
            "statusline.monitor.stopped",
            attributes: [
                "pane.name": paneName,
                "pane.id": paneID.uuidString,
                "tab.id": tabID.uuidString,
                "tab.name": tabName,
            ])
        stopAttentionWatcher()
        hasConfirmedBackgroundWork = false
        pendingStopWork?.cancel()
        pendingStopWork = nil
        agnosticProvider?.stop()
        if !isClaude {
            TracingService.shared.record(
                "statusline.provider.stopped",
                attributes: providerTraceAttributes(providerName: harness.rawValue))
        }
        agnosticProvider = nil
        cursorLifecycle = .unknown
        PRTrackingCoordinator.shared.unsubscribe(paneID: paneID)
        lastKnownPRState = nil
        onOpencodeStopped = nil
        onOpencodePermissionReplied = nil
        hasFiredResolutionNotification = false
        try? FileManager.default.removeItem(atPath: filePath)
        try? FileManager.default.removeItem(atPath: settingsFilePath)
        try? FileManager.default.removeItem(atPath: attentionSignalFilePath)
        try? FileManager.default.removeItem(atPath: hookLogFilePath)
        try? FileManager.default.removeItem(atPath: hookLogScriptFilePath)
        try? FileManager.default.removeItem(atPath: codexHookRecordFilePath)
        try? FileManager.default.removeItem(atPath: codexHookScriptFilePath)
    }

    func configureCursorAttentionWatcher(enabled: Bool) {
        guard let provider = agnosticProvider as? CursorDataProvider else { return }
        provider.configureAttentionWatcher(enabled: enabled)
    }

    var cursorHookEnvironmentVariables: [String: String] {
        guard let provider = agnosticProvider as? CursorDataProvider else { return [:] }
        return provider.hookEnvironmentVariables
    }

    private func applyCursorActivity(isWorking: Bool) {
        cursorLifecycle = isWorking ? .working : .stopped
    }

    private func makeFileWatcher(
        path: String,
        role: String,
        followsReplacement: Bool,
        onEvent: @escaping @MainActor (FileSystemEventWatcher.Event) -> Void
    ) -> FileSystemEventWatcher {
        FileSystemEventWatcher(
            url: URL(filePath: path),
            followsReplacement: followsReplacement,
            onEvent: onEvent,
            onStateChange: { [weak self] state in
                guard let self else { return }
                let result: String
                var attributes = [
                    "pane.name": paneName,
                    "pane.id": paneID.uuidString,
                    "tab.id": tabID.uuidString,
                    "tab.name": tabName,
                    "watcher.role": role,
                ]
                switch state {
                case .started:
                    result = "started"
                case .waitingForFile(let openError):
                    result = "waiting"
                    attributes["errno"] = String(openError)
                case .recovered:
                    result = "recovered"
                case .stopped:
                    result = "stopped"
                }
                attributes["result"] = result
                TracingService.shared.record("statusline.watcher.lifecycle", attributes: attributes)
            }
        )
    }

    @MainActor
    private func applyLatestPayload(reason: String) {
        let url = URL(filePath: filePath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
        let mtime = attrs?[.modificationDate] as? Date

        let rawData: Data
        do {
            rawData = try Data(contentsOf: url)
        } catch {
            TracingService.shared.record(
                "statusline.payload.decode_failed",
                attributes: [
                    "pane.name": paneName, "pane.id": paneID.uuidString,
                    "tab.id": tabID.uuidString, "tab.name": tabName,
                    "reason": reason,
                    "error": "read_failed:\(error.localizedDescription)", "byte_count": "0",
                ])
            return
        }

        guard !rawData.isEmpty else { return }

        let parsed: StatusLineData
        do {
            parsed = try JSONDecoder().decode(StatusLineData.self, from: rawData)
        } catch {
            let prefix = String(decoding: rawData.prefix(120), as: UTF8.self)
            var kind = "unknown"
            var codingPath = ""
            var missingKey = ""
            if let de = error as? DecodingError {
                switch de {
                case .keyNotFound(let key, let ctx):
                    kind = "key_not_found"
                    missingKey = key.stringValue
                    codingPath = (ctx.codingPath + [key]).map(\.stringValue).joined(separator: ".")
                case .typeMismatch(_, let ctx):
                    kind = "type_mismatch"
                    codingPath = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                case .valueNotFound(_, let ctx):
                    kind = "value_not_found"
                    codingPath = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                case .dataCorrupted(let ctx):
                    kind = "data_corrupted"
                    codingPath = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                @unknown default:
                    kind = "decoding_error"
                }
            }
            var attrs: [String: String] = [
                "pane.name": paneName, "pane.id": paneID.uuidString,
                "tab.id": tabID.uuidString, "tab.name": tabName,
                "reason": reason,
                "error": error.localizedDescription,
                "byte_count": "\(rawData.count)",
                "payload_prefix": prefix,
                "decoding_error_kind": kind,
            ]
            if !codingPath.isEmpty { attrs["coding_path"] = codingPath }
            if !missingKey.isEmpty { attrs["missing_key"] = missingKey }
            TracingService.shared.record("statusline.payload.decode_failed", attributes: attrs)
            return
        }

        var enforced = parsed
        if let existing = currentData?.pr {
            enforced.pr = existing
        }
        enforced.repo = cachedRepoIdentity
        enforced.customFields = cachedCustomFieldValues
        applyI1Enforcement(to: &enforced)
        applyI3Enforcement(to: &enforced)
        currentData = enforced
        lastAppliedModificationDate = mtime ?? Date()

        let inode = attrs?[.systemFileNumber] as? Int
        TracingService.shared.record(
            "statusline.payload.applied",
            attributes: [
                "pane.name": paneName, "pane.id": paneID.uuidString,
                "tab.id": tabID.uuidString, "tab.name": tabName,
                "reason": reason,
                "cost_usd": enforced.cost?.totalCostUsd.map { String(format: "%.4f", $0) } ?? "nil",
                "used_pct": enforced.contextWindow?.usedPercentage.map { "\($0)" } ?? "nil",
                "inode": inode.map { "\($0)" } ?? "unknown",
            ])
    }

    @MainActor
    private func checkPayloadFreshness() {
        guard let mtime = (try? FileManager.default.attributesOfItem(atPath: filePath))?[.modificationDate] as? Date
        else { return }
        guard let lastApplied = lastAppliedModificationDate else {
            applyLatestPayload(reason: "freshness_initial")
            return
        }
        guard mtime > lastApplied else { return }
        let staleAge = -mtime.timeIntervalSinceNow
        TracingService.shared.record(
            "statusline.payload.stale_recovered",
            attributes: [
                "pane.name": paneName, "pane.id": paneID.uuidString,
                "tab.id": tabID.uuidString, "tab.name": tabName,
                "file_mtime": String(format: "%.3f", mtime.timeIntervalSince1970),
                "stale_age_seconds": String(format: "%.1f", staleAge),
            ])
        applyLatestPayload(reason: "freshness_recovery")
    }

    private func applyI1Enforcement(to data: inout StatusLineData) {
        guard let cwd = workingDirectory else { return }
        let wantedName = URL(filePath: cwd).lastPathComponent

        if let reported = data.worktree?.name, reported != wantedName {
            InvariantReporter.shared.violated(
                .statusLineWorktreeName,
                context: [
                    "pane.name": paneName, "pane.id": paneID.uuidString,
                    "tab.id": tabID.uuidString, "tab.name": tabName,
                    "field": "worktree.name",
                    "computed": wantedName,
                    "reported": reported,
                ])
        }
        if let reported = data.workspace?.gitWorktree, reported != cwd,
            URL(filePath: reported).lastPathComponent != wantedName
        {
            InvariantReporter.shared.violated(
                .statusLineWorktreeName,
                context: [
                    "pane.name": paneName, "pane.id": paneID.uuidString,
                    "tab.id": tabID.uuidString, "tab.name": tabName,
                    "field": "workspace.git_worktree",
                    "computed": wantedName,
                    "reported": reported,
                ])
        }
        data.worktree = StatusLineData.Worktree(name: wantedName, branch: data.worktree?.branch)
    }

    private func applyI3Enforcement(to data: inout StatusLineData) {
        let computedAdded = cachedGitStats.added
        let computedRemoved = cachedGitStats.removed

        if let reportedAdded = data.cost?.totalLinesAdded,
            let reportedRemoved = data.cost?.totalLinesRemoved,
            reportedAdded != computedAdded || reportedRemoved != computedRemoved
        {
            InvariantReporter.shared.violated(
                .statusLineLinesSource,
                context: [
                    "pane.name": paneName, "pane.id": paneID.uuidString,
                    "tab.id": tabID.uuidString, "tab.name": tabName,
                    "computed_added": "\(computedAdded)",
                    "reported_added": "\(reportedAdded)",
                    "computed_removed": "\(computedRemoved)",
                    "reported_removed": "\(reportedRemoved)",
                ])
        }
        data.cost = StatusLineData.Cost(
            totalCostUsd: data.cost?.totalCostUsd,
            totalDurationMs: data.cost?.totalDurationMs,
            totalLinesAdded: computedAdded,
            totalLinesRemoved: computedRemoved,
            totalApiDurationMs: data.cost?.totalApiDurationMs
        )
    }

    private func applyProviderSnapshot(_ data: StatusLineData, providerName: String) {
        var merged = data
        if let existing = currentData?.pr {
            merged.pr = existing
        }
        merged.repo = cachedRepoIdentity
        merged.customFields = cachedCustomFieldValues
        currentData = merged
        TracingService.shared.record(
            "statusline.provider.update_applied",
            attributes: providerTraceAttributes(providerName: providerName))
    }

    private func providerTraceAttributes(providerName: String) -> [String: String] {
        [
            "provider": providerName,
            "pane.name": paneName,
            "pane.id": paneID.uuidString,
            "tab.id": tabID.uuidString,
            "tab.name": tabName,
        ]
    }

    func writeSettingsFile() {
        let prTrackingEnabled = SettingsPersistence.isPRTrackingEnabled()
        let settings = Self.makeClaudeSettingsDictionaryForTesting(
            statusOutputPath: filePath,
            attentionOutputPath: attentionSignalFilePath,
            hookLogScriptPath: hookLogScriptFilePath,
            hidePRStatus: prTrackingEnabled
        )
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) else { return }
        try? data.write(to: URL(filePath: settingsFilePath))
        TracingService.shared.record(
            "statusline.settings_file.written",
            attributes: [
                "path": settingsFilePath,
                "bytes": String(data.count),
            ])
    }

    private func applyClaudeActivityPayload(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(ClaudeActivityPayload.self, from: data) else { return }
        switch payload.hookEventName {
        case "UserPromptSubmit":
            lastAttentionPayloadFingerprint = nil
            pendingStopWork?.cancel()
            pendingStopWork = nil
            recordHookEventSpan(payload, decision: nil)
            guard claudeLifecycle != .working else { return }
            claudeLifecycle = .working
            TracingService.shared.record(
                "pane.activity.changed",
                attributes: [
                    "pane.name": paneName, "pane.id": paneID.uuidString,
                    "tab.id": tabID.uuidString, "tab.name": tabName,
                    "state": "working", "source": "claude_hook",
                    "hook_event": payload.hookEventName,
                ])
        case "Stop", "StopFailure":
            if payload.hookEventName == "Stop", payload.backgroundTasks == nil || payload.sessionCrons == nil {
                InvariantReporter.shared.violated(
                    .claudeStopBackgroundState,
                    context: [
                        "pane.name": paneName, "pane.id": paneID.uuidString,
                        "tab.id": tabID.uuidString, "tab.name": tabName,
                        "has_background_tasks": "\(payload.backgroundTasks != nil)",
                        "has_session_crons": "\(payload.sessionCrons != nil)",
                    ])
            }
            let backgroundTasks = payload.backgroundTasks ?? []
            let sessionCrons = payload.sessionCrons ?? []
            let taskCount = max(backgroundTasks.count, payload.backgroundTaskCount ?? 0)
            let cronCount = max(sessionCrons.count, payload.sessionCronCount ?? 0)
            hasConfirmedBackgroundWork =
                payload.hookEventName == "Stop"
                && payload.backgroundTasks != nil && payload.sessionCrons != nil
                && (taskCount > 0 || cronCount > 0)
            if hasConfirmedBackgroundWork {
                pendingStopWork?.cancel()
                pendingStopWork = nil
                if claudeLifecycle != .working {
                    claudeLifecycle = .working
                    TracingService.shared.record(
                        "pane.activity.changed",
                        attributes: [
                            "pane.name": paneName, "pane.id": paneID.uuidString,
                            "tab.id": tabID.uuidString, "tab.name": tabName,
                            "state": "working", "source": "claude_hook",
                            "hook_event": payload.hookEventName,
                        ])
                }
                recordHookEventSpan(
                    payload,
                    decision: "suppressed_background_work",
                    extraAttributes: [
                        "background_task_types": backgroundTasks.prefix(16).map {
                            var bytes = Array(($0.type ?? "unknown").utf8.prefix(64))
                            while String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
                            return String(decoding: bytes, as: UTF8.self)
                        }.joined(separator: ","),
                        "background_task_count": "\(taskCount)",
                        "session_cron_count": "\(cronCount)",
                    ])
                return
            }
            guard claudeLifecycle == .working else {
                recordHookEventSpan(payload, decision: "ignored_not_working")
                return
            }
            claudeLifecycle = .stopped
            TracingService.shared.record(
                "pane.activity.changed",
                attributes: [
                    "pane.name": paneName, "pane.id": paneID.uuidString,
                    "tab.id": tabID.uuidString, "tab.name": tabName,
                    "state": "stopped", "source": "claude_hook",
                    "hook_event": payload.hookEventName,
                ])
            recordHookEventSpan(payload, decision: "scheduled")
            scheduleClaudeStoppedNotification()
        case "Notification":
            recordHookEventSpan(payload, decision: nil)
        default:
            return
        }
    }

    private func applyClaudeAttentionPayload(_ data: Data) {
        if let payload = try? JSONDecoder().decode(ClaudeActivityPayload.self, from: data),
            payload.hookEventName == "Notification",
            payload.notificationType == "idle_prompt"
        {
            if hasConfirmedBackgroundWork {
                TracingService.shared.record(
                    "statusline.attention.suppressed",
                    attributes: [
                        "pane.name": paneName, "pane.id": paneID.uuidString,
                        "tab.id": tabID.uuidString, "tab.name": tabName,
                        "reason": "background_work_pending",
                    ])
                return
            }
            pendingStopWork?.cancel()
            pendingStopWork = nil
            if claudeLifecycle == .working {
                claudeLifecycle = .stopped
                TracingService.shared.record(
                    "pane.activity.changed",
                    attributes: [
                        "pane.name": paneName, "pane.id": paneID.uuidString,
                        "tab.id": tabID.uuidString, "tab.name": tabName,
                        "state": "stopped", "source": "claude_idle_prompt",
                    ])
                TracingService.shared.record(
                    "statusline.attention.recovered",
                    attributes: [
                        "pane.name": paneName, "pane.id": paneID.uuidString,
                        "tab.id": tabID.uuidString, "tab.name": tabName,
                        "reason": "idle_without_background_work",
                    ])
            }
        }
        var hasher = Hasher()
        hasher.combine(data)
        let fingerprint = hasher.finalize()
        guard fingerprint != lastAttentionPayloadFingerprint else { return }
        lastAttentionPayloadFingerprint = fingerprint
        guard let event = PaneAttentionEvent.claudeHook(data) else { return }
        TracingService.shared.record(
            "statusline.attention.received",
            attributes: [
                "pane.name": paneName, "pane.id": paneID.uuidString,
                "tab.id": tabID.uuidString, "tab.name": tabName,
                "source": event.source.rawValue, "reason": event.reason,
            ])
        onClaudeHookAttention?(event)
    }

    private func scheduleClaudeStoppedNotification() {
        pendingStopWork?.cancel()
        guard stopNotificationGracePeriod > 0 else {
            onClaudeStopped?()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.onClaudeStopped?()
        }
        pendingStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + stopNotificationGracePeriod, execute: work)
    }

    private func stopAttentionWatcher() {
        attentionDebounceWork?.cancel()
        attentionDebounceWork = nil
        attentionWatcher?.cancel()
        attentionWatcher = nil
        lastAttentionPayloadFingerprint = nil
        attentionOffset = 0
        attentionLineBuffer = Data()
    }

    @MainActor
    private func checkForPRResolutionTransition(_ pr: PullRequest?) {
        guard let pr else { return }
        let newState = pr.state.lowercased()
        let isResolved = newState == "merged" || newState == "closed"
        let wasResolved = lastKnownPRState == "merged" || lastKnownPRState == "closed"

        if isResolved, lastKnownPRState != nil, lastKnownPRState != newState {
            TracingService.shared.record(
                "statusline.pr_transition",
                attributes: [
                    "pane.name": paneName, "pane.id": paneID.uuidString,
                    "tab.id": tabID.uuidString, "tab.name": tabName,
                    "old_state": lastKnownPRState ?? "nil",
                    "new_state": newState,
                ])
        }
        if !isResolved, wasResolved {
            hasFiredResolutionNotification = false
            onPRReopened?()
        }
        if lastKnownPRState != newState {
            hasFiredResolutionNotification = false
        }
        defer { lastKnownPRState = newState }
        guard !hasFiredResolutionNotification else { return }
        guard isResolved else { return }
        guard lastKnownPRState != nil else { return }
        guard lastKnownPRState != newState else { return }
        hasFiredResolutionNotification = true
        if newState == "merged" {
            onPRMerged?(pr.number, pr.title)
        } else {
            onPRClosed?(pr.number, pr.title)
        }
    }
}

extension StatusLineMonitor {
    func setCustomFields(_ fields: [CustomStatusLineField]) {
        let eligibleFields = fields.filter { $0.supports(harness) }
        let nextByID = Dictionary(uniqueKeysWithValues: eligibleFields.map { ($0.id, $0) })

        for id in Set(scheduledCustomFields.keys).subtracting(nextByID.keys) {
            customFieldTimers[id]?.invalidate()
            customFieldTimers[id] = nil
            scheduledCustomFields[id] = nil
            cachedCustomFieldValues[id] = nil
            customFieldGenerations[id, default: 0] += 1
        }
        currentData?.customFields = cachedCustomFieldValues

        for (id, field) in nextByID {
            if let existing = scheduledCustomFields[id],
                existing.command == field.command,
                existing.effectiveRefreshIntervalSeconds == field.effectiveRefreshIntervalSeconds,
                existing.timeoutSeconds == field.timeoutSeconds
            {
                scheduledCustomFields[id] = field
                continue
            }
            scheduleCustomField(field)
        }
    }

    private func scheduleCustomField(
        _ field: CustomStatusLineField, trigger: String = "scheduled"
    ) {
        scheduledCustomFields[field.id] = field
        customFieldGenerations[field.id, default: 0] += 1
        customFieldTimers[field.id]?.invalidate()
        customFieldTimers[field.id] = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(field.effectiveRefreshIntervalSeconds), repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runCustomField(field, trigger: "scheduled")
            }
        }
        _ = runCustomField(field, trigger: trigger)
    }

    @discardableResult
    func runCustomFieldNow(_ field: CustomStatusLineField) -> CustomFieldRunOutcome {
        guard field.supports(harness) else { return .unsupported }
        if let scheduled = scheduledCustomFields[field.id],
            scheduled.command == field.command,
            scheduled.refreshIntervalSeconds == field.refreshIntervalSeconds,
            scheduled.timeoutSeconds == field.timeoutSeconds
        {
            return runCustomField(field, trigger: "manual")
        }
        scheduleCustomField(field, trigger: "manual")
        return .started
    }

    @discardableResult
    private func runCustomField(
        _ field: CustomStatusLineField, trigger: String
    ) -> CustomFieldRunOutcome {
        let generation = customFieldGenerations[field.id, default: 0]
        guard customFieldInFlight[field.id] != generation else { return .coalesced }
        customFieldInFlight[field.id] = generation
        let context = CustomFieldExecutionContext(
            currentData: currentData,
            paneID: paneID,
            paneName: paneName,
            tabID: tabID,
            tabName: tabName,
            harness: harness,
            workingDirectory: workingDirectory,
            profileName: profileName,
            extraEnvironment: customFieldEnvironment
        )
        let startedAt = Date()
        Task { [weak self] in
            guard let self else { return }
            TracingService.shared.record(
                "statusline.custom_field.exec_started",
                attributes: [
                    "pane.name": paneName, "pane.id": paneID.uuidString,
                    "tab.id": tabID.uuidString, "tab.name": tabName,
                    "field_id": field.id, "trigger": trigger,
                ])
            let result = await CustomFieldRunner.run(field: field, context: context)
            await MainActor.run {
                self.applyCustomFieldResult(
                    field: field,
                    result: result,
                    startedAt: startedAt,
                    trigger: trigger,
                    generation: generation
                )
            }
        }
        return .started
    }

    private func applyCustomFieldResult(
        field: CustomStatusLineField,
        result: CustomFieldExecutionResult,
        startedAt: Date,
        trigger: String = "scheduled",
        generation: Int? = nil
    ) {
        if let generation {
            let isCurrent =
                scheduledCustomFields[field.id]?.command == field.command
                && customFieldGenerations[field.id] == generation
            guard isCurrent else {
                if customFieldInFlight[field.id] == generation {
                    customFieldInFlight[field.id] = nil
                }
                TracingService.shared.record(
                    "statusline.custom_field.exec_stale",
                    attributes: [
                        "pane.name": paneName, "pane.id": paneID.uuidString,
                        "tab.id": tabID.uuidString, "tab.name": tabName,
                        "field_id": field.id, "trigger": trigger,
                    ])
                return
            }
            if customFieldInFlight[field.id] == generation {
                customFieldInFlight[field.id] = nil
            }
        }
        let durationMs = Date().timeIntervalSince(startedAt) * 1000
        var attrs: [String: String] = [
            "pane.name": paneName, "pane.id": paneID.uuidString,
            "tab.id": tabID.uuidString, "tab.name": tabName,
            "field_id": field.id,
            "trigger": trigger,
            "duration_ms": String(format: "%.1f", durationMs),
        ]
        switch result {
        case .success(let value, let outputKind):
            cachedCustomFieldValues[field.id] = value
            if currentData == nil {
                currentData = .empty()
            }
            currentData?.customFields = cachedCustomFieldValues
            attrs["output_kind"] = outputKind.rawValue
            TracingService.shared.record("statusline.custom_field.exec_succeeded", attributes: attrs)
        case .failure(let error):
            attrs["reason"] = error.reason.rawValue
            attrs["retained_prior_value"] = cachedCustomFieldValues[field.id] != nil ? "true" : "false"
            if let exitCode = error.exitCode {
                attrs["exit_code"] = String(exitCode)
            }
            if let inputFailure = error.inputFailure {
                attrs["input_failure_stage"] = inputFailure.stage.rawValue
                attrs["input_error_code"] = String(inputFailure.errorCode)
            }
            TracingService.shared.record("statusline.custom_field.exec_failed", attributes: attrs)
        }
    }

    @MainActor
    func testSetCachedCustomFieldValues(_ values: [String: CustomFieldRenderValue]) {
        cachedCustomFieldValues = values
    }

    var cachedCustomFieldValuesForTesting: [String: CustomFieldRenderValue] { cachedCustomFieldValues }

    @MainActor
    func testApplyCustomFieldResult(
        field: CustomStatusLineField,
        result: CustomFieldExecutionResult,
        trigger: String = "scheduled"
    ) {
        applyCustomFieldResult(field: field, result: result, startedAt: Date(), trigger: trigger)
    }

    @MainActor
    func testApplyProviderSnapshot(_ data: StatusLineData, providerName: String = "test") {
        applyProviderSnapshot(data, providerName: providerName)
    }
}

extension StatusLineMonitor {
    @MainActor
    func simulatePRUpdateForTesting(_ data: Data) {
        guard !data.isEmpty else { return }
        guard let pr = try? JSONDecoder().decode(PullRequest.self, from: data) else { return }
        if currentData == nil {
            currentData = .empty(pr: pr)
        } else {
            currentData?.pr = pr
        }
        checkForPRResolutionTransition(pr)
    }

    @MainActor
    func testApplyI1Enforcement(to data: inout StatusLineData) {
        applyI1Enforcement(to: &data)
    }

    @MainActor
    func testApplyI3Enforcement(to data: inout StatusLineData) {
        applyI3Enforcement(to: &data)
    }

    @MainActor
    func testSetCachedGitStats(_ stats: (added: Int, removed: Int)) {
        cachedGitStats = stats
    }

    private func startRepoIdentityFetch(cwd: String) {
        Task { [weak self] in
            guard let self else { return }
            if let identity = await Self.fetchRepoIdentity(workingDirectory: cwd) {
                await MainActor.run { self.cachedRepoIdentity = identity }
            }
        }
    }

    static func fetchRepoIdentity(workingDirectory: String) async -> StatusLineData.Repo? {
        await withCheckedContinuation { continuation in
            let task = Process()
            let outPipe = Pipe()
            task.executableURL = URL(filePath: "/usr/bin/git")
            task.arguments = ["-C", workingDirectory, "remote", "get-url", "origin"]
            task.standardOutput = outPipe
            task.standardError = FileHandle.nullDevice
            task.terminationHandler = { _ in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                guard
                    let remote = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    !remote.isEmpty,
                    let identity = PRTrackingCoordinator.parseRepoIdentity(from: remote)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: identity)
            }
            do {
                try task.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    @MainActor
    func testApplyLatestPayload(reason: String) {
        applyLatestPayload(reason: reason)
    }

    @MainActor
    func testCheckPayloadFreshness() {
        checkPayloadFreshness()
    }

    @MainActor
    func testSetCachedRepoIdentity(_ identity: StatusLineData.Repo?) {
        cachedRepoIdentity = identity
    }

    @MainActor
    func testApplyClaudeActivityPayload(_ data: Data) {
        applyClaudeActivityPayload(data)
    }

    @MainActor
    func testApplyClaudeAttentionPayload(_ data: Data) {
        applyClaudeAttentionPayload(data)
    }

    @MainActor
    func testApplyCursorActivity(isWorking: Bool) {
        applyCursorActivity(isWorking: isWorking)
    }

    nonisolated static func makeClaudeSettingsDictionaryForTesting(
        statusOutputPath: String,
        attentionOutputPath: String,
        hookLogScriptPath: String,
        hidePRStatus: Bool = false
    ) -> [String: Any] {
        var settings: [String: Any] = [
            "statusLine": [
                "type": "command",
                "command": "cat > '\(statusOutputPath)'",
            ]
        ]
        if hidePRStatus {
            settings["showPRStatus"] = false
            settings["prStatusFooterEnabled"] = false
        }
        let hookLogHook: [[String: Any]] = [["type": "command", "command": "'\(hookLogScriptPath)'"]]
        let attentionHook: [[String: Any]] = [
            ["type": "command", "command": "'\(hookLogScriptPath)' --attention '\(attentionOutputPath)'"]
        ]
        settings["hooks"] = [
            "UserPromptSubmit": [["hooks": hookLogHook]],
            "Stop": [["hooks": hookLogHook]],
            "StopFailure": [["hooks": hookLogHook]],
            "PreToolUse": [
                ["matcher": "AskUserQuestion|ExitPlanMode", "hooks": attentionHook]
            ],
            "PermissionRequest": [["hooks": attentionHook]],
            "Notification": [
                [
                    "matcher": "permission_prompt|elicitation_dialog|idle_prompt|agent_needs_input",
                    "hooks": attentionHook,
                ],
                ["hooks": hookLogHook],
            ],
            "Elicitation": [["hooks": attentionHook]],
        ]
        return settings
    }
}

extension StatusLineMonitor {
    func writeCodexHookScript() {
        let script = """
            #!/usr/bin/env python3
            import json
            import os
            import sys
            import time

            payload = json.load(sys.stdin)
            record = {
                "pane_id": os.environ.get("AGENT_SESSION_MANAGER_PANE_ID", ""),
                "tab_id": os.environ.get("AGENT_SESSION_MANAGER_TAB_ID", ""),
                "session_id": payload.get("session_id", ""),
                "cwd": payload.get("cwd", ""),
                "model": payload.get("model"),
                "transcript_path": payload.get("transcript_path"),
                "hook_event_name": payload.get("hook_event_name", ""),
                "timestamp": time.time()
            }
            path = os.environ["AGENT_SESSION_MANAGER_CODEX_HOOK_RECORD_PATH"]
            tmp_path = path + ".tmp"
            with open(tmp_path, "w", encoding="utf-8") as handle:
                json.dump(record, handle, separators=(",", ":"))
            os.replace(tmp_path, path)
            """
        try? script.write(to: URL(filePath: codexHookScriptFilePath), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: codexHookScriptFilePath)
        FileManager.default.createFile(atPath: codexHookRecordFilePath, contents: nil)
    }

    func writeHookLogScript() {
        let script = """
            #!/usr/bin/env python3
            import fcntl
            import hashlib
            import json
            import os
            import sys
            import time

            def bounded(value, limit=64):
                if not isinstance(value, str):
                    return None
                return value.encode("utf-8", errors="replace")[:limit].decode("utf-8", errors="ignore")

            raw = sys.stdin.buffer.read()
            payload = json.loads(raw)
            attention = len(sys.argv) > 1 and sys.argv[1] == "--attention"
            record = {
                "hook_event_name": bounded(payload.get("hook_event_name")) or "",
                "notification_type": bounded(payload.get("notification_type")),
                "tool_name": bounded(payload.get("tool_name")),
                "title": bounded(payload.get("title"), 1024),
                "message": bounded(payload.get("message"), 1024),
                "agent_id": bounded(payload.get("agent_id")),
                "agent_type": bounded(payload.get("agent_type")),
                "transcript_path": bounded(payload.get("transcript_path"), 1024),
                "session_id": bounded(payload.get("session_id"), 128)
            }
            if attention:
                record["payload_fingerprint"] = hashlib.sha256(raw).hexdigest()
            else:
                record["timestamp"] = time.time()
                tasks = payload.get("background_tasks")
                if isinstance(tasks, list):
                    record["background_tasks"] = [
                        {"id": bounded(t.get("id")), "type": bounded(t.get("type")), "status": bounded(t.get("status"), 32)}
                        for t in tasks[:32] if isinstance(t, dict)
                    ]
                    record["background_tasks_total_count"] = len(tasks)
                    record["background_tasks_omitted_count"] = len(tasks) - len(record["background_tasks"])
                crons = payload.get("session_crons")
                if isinstance(crons, list):
                    record["session_crons"] = [
                        {"id": bounded(c.get("id")), "recurring": c.get("recurring") if isinstance(c.get("recurring"), bool) else None}
                        for c in crons[:32] if isinstance(c, dict)
                    ]
                    record["session_crons_total_count"] = len(crons)
                    record["session_crons_omitted_count"] = len(crons) - len(record["session_crons"])
            line = (json.dumps(record, separators=(",", ":"), ensure_ascii=False) + "\\n").encode("utf-8")
            path = sys.argv[2] if attention else '\(hookLogFilePath)'
            fd = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX)
                offset = 0
                while offset < len(line):
                    offset += os.write(fd, line[offset:])
            finally:
                os.close(fd)
            """
        try? script.write(to: URL(filePath: hookLogScriptFilePath), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: hookLogScriptFilePath)
    }
}

extension StatusLineMonitor {
    private func recordHookEventSpan(
        _ payload: ClaudeActivityPayload, decision: String?, extraAttributes: [String: String] = [:]
    ) {
        let attributes: [String: String] = [
            "pane.name": paneName, "pane.id": paneID.uuidString,
            "tab.id": tabID.uuidString, "tab.name": tabName,
            "hook_event": payload.hookEventName,
            "notification_type": payload.notificationType ?? "nil",
            "agent_type": payload.agentType ?? "nil",
            "decision": decision ?? "n/a",
        ]
        TracingService.shared.record(
            "statusline.hook.event",
            attributes: attributes.merging(extraAttributes) { _, extra in extra })
    }
}

private struct ClaudeActivityPayload: Decodable {
    struct BackgroundTask: Decodable {
        let type: String?
    }

    struct SessionCron: Decodable {}

    let hookEventName: String
    let notificationType: String?
    let message: String?
    let agentID: String?
    let agentType: String?
    let transcriptPath: String?
    let sessionID: String?
    let backgroundTasks: [BackgroundTask]?
    let sessionCrons: [SessionCron]?
    let backgroundTaskCount: Int?
    let sessionCronCount: Int?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case notificationType = "notification_type"
        case message
        case agentID = "agent_id"
        case agentType = "agent_type"
        case transcriptPath = "transcript_path"
        case sessionID = "session_id"
        case backgroundTasks = "background_tasks"
        case sessionCrons = "session_crons"
        case backgroundTaskCount = "background_tasks_total_count"
        case sessionCronCount = "session_crons_total_count"
    }
}
