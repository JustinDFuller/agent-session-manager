import Foundation

struct PersistedPaneNotification: Codable, Equatable {
    var notificationID: UUID
    var paneID: UUID
    var paneName: String
    var tabID: UUID
    var tabName: String
    var isPriority: Bool
    var timestamp: Date
    var kind: NotificationKind
    var reason: String?
    var prNumber: Int?
    var prTitle: String?

    enum CodingKeys: String, CodingKey {
        case notificationID, paneID, paneName, tabID, tabName, isPriority, timestamp
        case kind, reason, prNumber, prTitle
    }

    init(
        notificationID: UUID,
        paneID: UUID,
        paneName: String,
        tabID: UUID,
        tabName: String,
        isPriority: Bool,
        timestamp: Date,
        kind: NotificationKind = .terminalBell,
        reason: String? = nil,
        prNumber: Int? = nil,
        prTitle: String? = nil
    ) {
        self.notificationID = notificationID
        self.paneID = paneID
        self.paneName = paneName
        self.tabID = tabID
        self.tabName = tabName
        self.isPriority = isPriority
        self.timestamp = timestamp
        self.kind = kind
        self.reason = reason
        self.prNumber = prNumber
        self.prTitle = prTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notificationID = try container.decode(UUID.self, forKey: .notificationID)
        paneID = try container.decode(UUID.self, forKey: .paneID)
        paneName = try container.decode(String.self, forKey: .paneName)
        tabID = try container.decode(UUID.self, forKey: .tabID)
        tabName = try container.decode(String.self, forKey: .tabName)
        isPriority = try container.decode(Bool.self, forKey: .isPriority)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        kind = (try? container.decodeIfPresent(NotificationKind.self, forKey: .kind)) ?? .terminalBell
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        prNumber = try container.decodeIfPresent(Int.self, forKey: .prNumber)
        prTitle = try container.decodeIfPresent(String.self, forKey: .prTitle)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notificationID, forKey: .notificationID)
        try container.encode(paneID, forKey: .paneID)
        try container.encode(paneName, forKey: .paneName)
        try container.encode(tabID, forKey: .tabID)
        try container.encode(tabName, forKey: .tabName)
        try container.encode(isPriority, forKey: .isPriority)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(prNumber, forKey: .prNumber)
        try container.encodeIfPresent(prTitle, forKey: .prTitle)
    }
}

struct PersistedSession: Codable {
    var tabs: [PersistedTab]
    var activeTabIndex: Int?
    var pendingNotifications: [PersistedPaneNotification]

    enum CodingKeys: String, CodingKey {
        case tabs
        case activeTabIndex
        case pendingNotifications
    }

    init(tabs: [PersistedTab], activeTabIndex: Int?, pendingNotifications: [PersistedPaneNotification] = []) {
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
        self.pendingNotifications = pendingNotifications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decode([PersistedTab].self, forKey: .tabs)
        activeTabIndex = try container.decodeIfPresent(Int.self, forKey: .activeTabIndex)
        pendingNotifications =
            try container.decodeIfPresent([PersistedPaneNotification].self, forKey: .pendingNotifications) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tabs, forKey: .tabs)
        try container.encodeIfPresent(activeTabIndex, forKey: .activeTabIndex)
        try container.encode(pendingNotifications, forKey: .pendingNotifications)
    }
}

struct PersistedTab: Codable {
    var id: UUID
    var name: String
    var directory: String
    var baseBranchOverride: String?
    var gridSizePreferences: PaneGridSizePreferences?
    var panes: [PersistedPane]

    enum CodingKeys: String, CodingKey { case id, name, directory, baseBranchOverride, gridSizePreferences, panes }

    init(
        id: UUID,
        name: String,
        directory: String,
        baseBranchOverride: String? = nil,
        gridSizePreferences: PaneGridSizePreferences? = nil,
        panes: [PersistedPane]
    ) {
        self.id = id
        self.name = name
        self.directory = directory
        self.baseBranchOverride = baseBranchOverride
        self.gridSizePreferences = gridSizePreferences
        self.panes = panes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        directory = try container.decode(String.self, forKey: .directory)
        baseBranchOverride = try? container.decodeIfPresent(String.self, forKey: .baseBranchOverride)
        gridSizePreferences = try? container.decodeIfPresent(PaneGridSizePreferences.self, forKey: .gridSizePreferences)
        panes = try container.decode([PersistedPane].self, forKey: .panes)
    }
}

struct PersistedPane: Codable {
    var id: UUID
    var name: String
    var harness: Harness
    var isPriority: Bool
    var isMerged: Bool
    var isClosed: Bool
    var worktreeDirectory: String?
    var worktreeIsManaged: Bool
    var profileID: UUID?
    var scrollbackOverride: ScrollbackLimit?
    var extraArgs: [String]
    var opencodeSessionID: String?
    var codexSessionID: String?
    var codexTranscriptPath: String?
    var agentControlInjectionEnabled: Bool?
    var statusLineHeight: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, harness, isPriority, isMerged, isClosed, worktreeDirectory, worktreeIsManaged
        case claudeProcessDirectory
        case profileID
        case scrollbackOverride
        case extraArgs
        case opencodeSessionID
        case codexSessionID, codexTranscriptPath
        case agentControlInjectionEnabled
        case statusLineHeight
    }

    init(
        id: UUID, name: String, harness: Harness, isPriority: Bool = false, isMerged: Bool = false,
        isClosed: Bool = false,
        worktreeDirectory: String? = nil, worktreeIsManaged: Bool = false, profileID: UUID? = nil,
        scrollbackOverride: ScrollbackLimit? = nil, extraArgs: [String] = [], opencodeSessionID: String? = nil,
        codexSessionID: String? = nil, codexTranscriptPath: String? = nil,
        agentControlInjectionEnabled: Bool? = nil, statusLineHeight: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.harness = harness
        self.isPriority = isPriority
        self.isMerged = isMerged
        self.isClosed = isClosed
        self.worktreeDirectory = worktreeDirectory
        self.worktreeIsManaged = worktreeIsManaged
        self.profileID = profileID
        self.scrollbackOverride = scrollbackOverride
        self.extraArgs = extraArgs
        self.opencodeSessionID = opencodeSessionID
        self.codexSessionID = codexSessionID
        self.codexTranscriptPath = codexTranscriptPath
        self.agentControlInjectionEnabled = agentControlInjectionEnabled
        self.statusLineHeight = Self.validStatusLineHeight(statusLineHeight)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        harness = (try? container.decodeIfPresent(Harness.self, forKey: .harness)) ?? .claude
        isPriority = (try? container.decodeIfPresent(Bool.self, forKey: .isPriority)) ?? false
        isMerged = (try? container.decodeIfPresent(Bool.self, forKey: .isMerged)) ?? false
        isClosed = (try? container.decodeIfPresent(Bool.self, forKey: .isClosed)) ?? false
        worktreeDirectory =
            try container.decodeIfPresent(String.self, forKey: .worktreeDirectory)
            ?? container.decodeIfPresent(String.self, forKey: .claudeProcessDirectory)
        worktreeIsManaged = (try? container.decodeIfPresent(Bool.self, forKey: .worktreeIsManaged)) ?? false
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
        scrollbackOverride =
            try? container.decodeIfPresent(ScrollbackLimit.self, forKey: .scrollbackOverride)
        extraArgs = (try? container.decodeIfPresent([String].self, forKey: .extraArgs)) ?? []
        opencodeSessionID = try container.decodeIfPresent(String.self, forKey: .opencodeSessionID)
        codexSessionID = try container.decodeIfPresent(String.self, forKey: .codexSessionID)
        codexTranscriptPath = try container.decodeIfPresent(String.self, forKey: .codexTranscriptPath)
        agentControlInjectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .agentControlInjectionEnabled)
        let decodedHeight = try? container.decode(Double.self, forKey: .statusLineHeight)
        statusLineHeight = Self.validStatusLineHeight(decodedHeight)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(harness, forKey: .harness)
        try container.encode(isPriority, forKey: .isPriority)
        try container.encode(isMerged, forKey: .isMerged)
        try container.encode(isClosed, forKey: .isClosed)
        try container.encode(worktreeDirectory, forKey: .worktreeDirectory)
        try container.encode(worktreeIsManaged, forKey: .worktreeIsManaged)
        try container.encodeIfPresent(profileID, forKey: .profileID)
        try container.encodeIfPresent(scrollbackOverride, forKey: .scrollbackOverride)
        try container.encode(extraArgs, forKey: .extraArgs)
        try container.encodeIfPresent(opencodeSessionID, forKey: .opencodeSessionID)
        try container.encodeIfPresent(codexSessionID, forKey: .codexSessionID)
        try container.encodeIfPresent(codexTranscriptPath, forKey: .codexTranscriptPath)
        try container.encodeIfPresent(agentControlInjectionEnabled, forKey: .agentControlInjectionEnabled)
        try container.encodeIfPresent(statusLineHeight, forKey: .statusLineHeight)
    }

    private static func validStatusLineHeight(_ height: Double?) -> Double? {
        guard let height, height.isFinite, (24...256).contains(height) else { return nil }
        return height
    }
}

@MainActor
struct SessionPersistence {
    private static var sessionURL: URL {
        let config = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = config.appending(path: PersistenceHelpers.appSupportSubdirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "sessions.json")
    }

    static func makePersistedSession(appState: AppState) -> PersistedSession {
        let tabs = appState.tabs.map { tab in
            PersistedTab(
                id: tab.id,
                name: tab.name,
                directory: tab.directory.path,
                baseBranchOverride: tab.baseBranchOverride,
                gridSizePreferences: tab.gridSizePreferences,
                panes: tab.panes.compactMap { pane -> PersistedPane? in
                    guard pane.harness != .shell else { return nil }
                    return PersistedPane(
                        id: pane.id,
                        name: pane.name,
                        harness: pane.harness,
                        isPriority: pane.isPriority,
                        isMerged: pane.isMerged,
                        isClosed: pane.isClosed,
                        worktreeDirectory: pane.worktreeDirectory?.path,
                        worktreeIsManaged: pane.worktreeIsManaged,
                        profileID: pane.profileID,
                        scrollbackOverride: pane.scrollbackOverride,
                        extraArgs: pane.extraArgs,
                        opencodeSessionID: pane.opencodeSessionID,
                        codexSessionID: pane.codexSessionID,
                        codexTranscriptPath: pane.codexTranscriptPath,
                        agentControlInjectionEnabled: pane.agentControlInjectionEnabled,
                        statusLineHeight: pane.statusLineHeight
                    )
                }
            )
        }
        let activeTabIndex = appState.tabs.firstIndex { $0.id == appState.activeTabID }
        let pendingNotifications = appState.notifications.map {
            PersistedPaneNotification(
                notificationID: $0.id,
                paneID: $0.paneID,
                paneName: $0.paneName,
                tabID: $0.tabID,
                tabName: $0.tabName,
                isPriority: $0.isPriority,
                timestamp: $0.timestamp,
                kind: $0.kind,
                reason: $0.reason,
                prNumber: $0.prNumber,
                prTitle: $0.prTitle
            )
        }
        return PersistedSession(
            tabs: tabs, activeTabIndex: activeTabIndex, pendingNotifications: pendingNotifications)
    }

    @discardableResult
    static func save(appState: AppState) -> Bool {
        let session = makePersistedSession(appState: appState)
        guard let data = try? JSONEncoder().encode(session) else { return false }
        do {
            try data.write(to: sessionURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func persistedDirectoryURL(for path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        return URL(filePath: path)
    }

    static func restore(into appState: AppState, appSettings: AppSettings) {
        guard
            let data = try? Data(contentsOf: sessionURL),
            let session = try? JSONDecoder().decode(PersistedSession.self, from: data)
        else { return }

        var didMigrateAgentControlDecisions = false
        for persistedTab in session.tabs {
            guard let dir = persistedDirectoryURL(for: persistedTab.directory) else { continue }
            let tab = Tab(
                id: persistedTab.id,
                name: persistedTab.name,
                directory: dir,
                baseBranchOverride: persistedTab.baseBranchOverride
            )
            for persistedPane in persistedTab.panes {
                let worktreeDir: URL?
                if let pathStr = persistedPane.worktreeDirectory, !pathStr.isEmpty {
                    let url = URL(fileURLWithPath: pathStr).standardizedFileURL
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    worktreeDir = url
                } else if persistedPane.harness == .claude {
                    let managed = Tab.worktreeDirectoryURL(repoRoot: dir, name: persistedPane.name)
                    let legacy = dir.appending(path: ".tree/\(persistedPane.name)", directoryHint: .notDirectory)
                    if FileManager.default.fileExists(atPath: managed.path) {
                        worktreeDir = managed
                    } else if FileManager.default.fileExists(atPath: legacy.path) {
                        worktreeDir = legacy
                    } else {
                        continue
                    }
                } else {
                    continue
                }
                var extraArgs = persistedPane.extraArgs
                var resumeOpencodeSessionID: String?
                var cursorContinuationResult: String?
                if persistedPane.harness == .claude || persistedPane.harness == .cursor,
                    appSettings.continueOnRestart
                {
                    let originalExtraArgs = extraArgs
                    extraArgs = Tab.injectContinueFlagIntoArgs(extraArgs)
                    if persistedPane.harness == .cursor {
                        cursorContinuationResult =
                            extraArgs == originalExtraArgs ? "already_configured" : "injected"
                    }
                } else if persistedPane.harness == .cursor {
                    cursorContinuationResult = "disabled"
                }
                if let cursorContinuationResult {
                    TracingService.shared.record(
                        "session.pane.restore.continuation",
                        attributes: [
                            "pane.id": persistedPane.id.uuidString,
                            "pane.name": persistedPane.name,
                            "tab.id": persistedTab.id.uuidString,
                            "tab.name": persistedTab.name,
                            "harness": persistedPane.harness.rawValue,
                            "continue_on_restart": String(appSettings.continueOnRestart),
                            "result": cursorContinuationResult,
                        ])
                }
                if persistedPane.harness == .opencode && appSettings.continueOnRestart {
                    if let id = persistedPane.opencodeSessionID, !extraArgs.contains("--session") {
                        resumeOpencodeSessionID = id
                    } else if !extraArgs.contains("--continue") {
                        extraArgs.append("--continue")
                    }
                }
                let agentControlInjectionEnabled = appSettings.resolvedAgentControlInjectionDecision(
                    persistedDecision: persistedPane.agentControlInjectionEnabled)
                didMigrateAgentControlDecisions =
                    didMigrateAgentControlDecisions || persistedPane.agentControlInjectionEnabled == nil
                let restoredEnvironment: [String: String] = {
                    guard let profileID = persistedPane.profileID,
                        let profile = appSettings.profiles.first(where: { $0.id == profileID })
                    else { return [:] }
                    return profile.envVars.reduce(into: [String: String]()) { result, envVar in
                        guard envVar.isEnabled, !envVar.value.isEmpty else { return }
                        result[envVar.id] = envVar.value
                    }
                }()
                let codexResumeSessionID = Tab.codexResumeSessionIDForRestore(
                    harness: persistedPane.harness,
                    savedSessionID: persistedPane.codexSessionID,
                    continueOnRestart: appSettings.continueOnRestart)
                let codexRecovery: CodexContinuationRecovery? = {
                    guard let codexResumeSessionID else { return nil }
                    let environment = ProcessEnvironment.dictionary(
                        from: ProcessEnvironment.sanitize(
                            Tab.hostEnvironmentForChildProcess()
                                + restoredEnvironment.map { "\($0.key)=\($0.value)" }))
                    let access = CodexContinuationVerifier.check(
                        sessionID: codexResumeSessionID,
                        transcriptPath: persistedPane.codexTranscriptPath,
                        shell: ShellResolver.resolved(appSettings),
                        workingDirectory: worktreeDir?.path ?? dir.path,
                        environment: environment)
                    TracingService.shared.record(
                        "statusline.codex.continuation.preflight",
                        attributes: [
                            "pane.id": persistedPane.id.uuidString,
                            "requested_session_id_prefix": String(codexResumeSessionID.prefix(12)),
                            "result": access.traceValue,
                            "source": "restore",
                        ])
                    return access == .available ? nil : .exactSessionUnavailable
                }()
                let pane = tab.addPane(
                    name: persistedPane.name,
                    extraArgs: extraArgs,
                    harness: persistedPane.harness,
                    worktreeDirectory: worktreeDir,
                    worktreeIsManaged: persistedPane.worktreeIsManaged,
                    id: persistedPane.id,
                    extraEnvVars: restoredEnvironment,
                    profileID: persistedPane.profileID,
                    scrollbackOverride: persistedPane.scrollbackOverride,
                    agentControlInjectionEnabled: agentControlInjectionEnabled,
                    resumeOpencodeSessionID: resumeOpencodeSessionID,
                    resumeCodexSessionID: codexRecovery == nil ? codexResumeSessionID : nil,
                    codexTranscriptPath: persistedPane.codexTranscriptPath,
                    codexContinuationRecovery: codexRecovery,
                    codexContinuationNotice: Tab.codexRestoreNotice(
                        harness: persistedPane.harness,
                        savedSessionID: persistedPane.codexSessionID,
                        continueOnRestart: appSettings.continueOnRestart),
                    appSettings: appSettings
                )
                pane.isMerged = persistedPane.isMerged
                pane.isClosed = persistedPane.isClosed
                pane.statusLineHeight = persistedPane.statusLineHeight
                if codexResumeSessionID != nil || codexRecovery != nil {
                    pane.codexSessionID = persistedPane.codexSessionID
                    pane.codexTranscriptPath = persistedPane.codexTranscriptPath
                }
                pane.bindNotifications(
                    appState: appState,
                    isPriority: persistedPane.isPriority
                )
            }
            tab.gridSizePreferences = persistedTab.gridSizePreferences ?? PaneGridSizePreferences()
            tab.gridSizePreferences.reconcile(layout: GridLayout.forPaneCount(tab.panes.count))
            appState.tabs.append(tab)
        }
        if let index = session.activeTabIndex, index < appState.tabs.count {
            appState.activeTabID = appState.tabs[index].id
        } else {
            appState.activeTabID = appState.tabs.first?.id
        }

        var restored: [PaneNotification] = []
        var seenPaneIDs = Set<UUID>()
        for pending in session.pendingNotifications {
            guard !seenPaneIDs.contains(pending.paneID) else { continue }
            guard let tab = appState.tabs.first(where: { $0.id == pending.tabID }),
                let pane = tab.panes.first(where: { $0.id == pending.paneID })
            else { continue }
            seenPaneIDs.insert(pending.paneID)
            restored.append(
                PaneNotification(
                    id: pending.notificationID,
                    paneID: pending.paneID,
                    paneName: pane.name,
                    tabID: pending.tabID,
                    tabName: tab.name,
                    isPriority: pending.isPriority,
                    timestamp: pending.timestamp,
                    kind: pending.kind,
                    reason: pending.reason,
                    prNumber: pending.prNumber,
                    prTitle: pending.prTitle
                )
            )
        }
        appState.notifications = restored

        for notification in restored where notification.kind == .prMerged || notification.kind == .prClosed {
            if let tab = appState.tabs.first(where: { $0.id == notification.tabID }),
                let pane = tab.panes.first(where: { $0.id == notification.paneID })
            {
                if notification.kind == .prMerged {
                    pane.isMerged = true
                } else {
                    pane.isClosed = true
                }
            }
        }
        if didMigrateAgentControlDecisions {
            save(appState: appState)
        }
    }

    static func checkForResolvedPRsAfterRestore(appState: AppState) async {
        guard SettingsPersistence.isPRTrackingEnabled() else { return }
        guard
            SettingsPersistence.isPRMergedNotificationsEnabled()
                || SettingsPersistence.isPRClosedNotificationsEnabled()
        else { return }

        let candidates: [(pane: Pane, tab: Tab)] = appState.tabs.flatMap { tab in
            tab.panes.compactMap { pane in
                guard !pane.isMerged, !pane.isClosed else { return nil }
                guard pane.worktreeDirectory != nil else { return nil }
                return (pane: pane, tab: tab)
            }
        }
        guard !candidates.isEmpty else { return }

        var branchInfos: [PRTrackingCoordinator.BranchInfo] = []
        await withTaskGroup(of: PRTrackingCoordinator.BranchInfo?.self) { group in
            for (pane, tab) in candidates {
                guard let cwd = pane.worktreeDirectory?.path else { continue }
                let paneID = pane.id
                let paneName = pane.name
                let tabID = tab.id
                let tabName = tab.name
                group.addTask {
                    async let branchResult = PRTrackingCoordinator.fetchBranch(workingDirectory: cwd)
                    async let ownerRepoResult: (owner: String, repo: String)? = withCheckedContinuation {
                        continuation in
                        let task = Process()
                        let outPipe = Pipe()
                        task.executableURL = URL(filePath: "/usr/bin/git")
                        task.arguments = ["-C", cwd, "remote", "get-url", "origin"]
                        task.standardOutput = outPipe
                        task.standardError = FileHandle.nullDevice
                        task.terminationHandler = { _ in
                            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                            guard
                                let raw = String(data: outData, encoding: .utf8)?
                                    .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
                            else {
                                continuation.resume(returning: nil)
                                return
                            }
                            continuation.resume(returning: PRTrackingCoordinator.parseOwnerRepo(from: raw))
                        }
                        do {
                            try task.run()
                        } catch {
                            continuation.resume(returning: nil)
                        }
                    }
                    guard let branch = await branchResult,
                        let (owner, repo) = await ownerRepoResult
                    else { return nil }
                    return PRTrackingCoordinator.BranchInfo(
                        paneID: paneID, owner: owner, repo: repo, branch: branch,
                        paneName: paneName, tabID: tabID, tabName: tabName)
                }
            }
            for await info in group {
                if let info { branchInfos.append(info) }
            }
        }

        guard !branchInfos.isEmpty else { return }

        let checkHandle = TracingService.shared.startSpan(
            "session.pr_check",
            attributes: ["panes_checked": String(candidates.count)])

        let results = await PRTrackingCoordinator.checkBranchesForResolvedPRs(
            branches: branchInfos, parent: checkHandle)

        var mergedCount = 0
        var closedCount = 0
        for (paneID, pr) in results {
            guard let (pane, tab) = candidates.first(where: { $0.pane.id == paneID }) else { continue }
            switch pr.state {
            case "merged":
                appState.addPRMergedNotification(
                    paneID: pane.id,
                    paneName: pane.name,
                    tabID: tab.id,
                    tabName: tab.name,
                    prNumber: pr.number,
                    prTitle: pr.title
                )
                mergedCount += 1
            case "closed":
                appState.addPRClosedNotification(
                    paneID: pane.id,
                    paneName: pane.name,
                    tabID: tab.id,
                    tabName: tab.name,
                    prNumber: pr.number,
                    prTitle: pr.title
                )
                closedCount += 1
            default:
                break
            }
        }

        TracingService.shared.end(
            handle: checkHandle,
            attributes: ["merged_count": String(mergedCount), "closed_count": String(closedCount)])
    }
}
