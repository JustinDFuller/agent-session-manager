import Foundation
import SQLite3

struct StatusProviderContext {
    let paneID: UUID
    let paneName: String
    let tabID: UUID
    let tabName: String
    let workingDirectory: String
    let harness: Harness
    let processStartTime: Date
    let launchArgs: [String]
    let environment: [String: String]
    let codexShell: String?
    let detectedHarnessVersion: String?
    let codexHookRecordPath: String?
    let codexHookQueuePath: String?
    let codexHookDiagnosticPath: String?
    let codexLaunchGeneration: String?
    let codexAdapter: CodexCompatibilityAdapter?
    let opencodePort: Int?
    let opencodeSessionID: String?
    let opencodeEnvironment: [String: String]

    init(
        paneID: UUID,
        paneName: String,
        tabID: UUID,
        tabName: String,
        workingDirectory: String,
        harness: Harness,
        processStartTime: Date,
        launchArgs: [String],
        environment: [String: String],
        codexShell: String? = nil,
        detectedHarnessVersion: String?,
        codexHookRecordPath: String?,
        opencodePort: Int?,
        opencodeSessionID: String?,
        codexHookQueuePath: String? = nil,
        codexHookDiagnosticPath: String? = nil,
        codexLaunchGeneration: String? = nil,
        codexAdapter: CodexCompatibilityAdapter? = nil,
        opencodeEnvironment: [String: String] = [:]
    ) {
        self.paneID = paneID
        self.paneName = paneName
        self.tabID = tabID
        self.tabName = tabName
        self.workingDirectory = workingDirectory
        self.harness = harness
        self.processStartTime = processStartTime
        self.launchArgs = launchArgs
        self.environment = environment
        self.codexShell = codexShell
        self.detectedHarnessVersion = detectedHarnessVersion
        self.codexHookRecordPath = codexHookRecordPath
        self.codexHookQueuePath = codexHookQueuePath
        self.codexHookDiagnosticPath = codexHookDiagnosticPath
        self.codexLaunchGeneration = codexLaunchGeneration
        self.codexAdapter = codexAdapter
        self.opencodePort = opencodePort
        self.opencodeSessionID = opencodeSessionID
        self.opencodeEnvironment = opencodeEnvironment
    }
}

struct CodexHookSessionRecord: Codable, Equatable {
    let paneID: String
    let tabID: String
    let sessionID: String
    let cwd: String
    let model: String?
    let transcriptPath: String?
    let hookEventName: String
    let timestamp: Double

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case tabID = "tab_id"
        case sessionID = "session_id"
        case cwd
        case model
        case transcriptPath = "transcript_path"
        case hookEventName = "hook_event_name"
        case timestamp
    }
}

struct CodexThreadState: Equatable {
    let id: String
    let cwd: String?
    let rolloutPath: String?
    let model: String?
    let cliVersion: String?
    let tokensUsed: Int?
    let gitBranch: String?
    let createdAtMs: Int64?
    let updatedAtMs: Int64?
    let isArchived: Bool
    let candidateCount: Int
}

struct CodexThreadSelection: Equatable {
    let thread: CodexThreadState?
    let candidateCount: Int
    let freshCandidateCount: Int
}

enum CodexTranscriptAttentionEvent: Equatable {
    case questionRequested(callID: String)
    case questionResolved(callID: String)

    static func parseLine(_ data: Data) -> CodexTranscriptAttentionEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["type"] as? String == "response_item",
            let payload = object["payload"] as? [String: Any],
            let type = payload["type"] as? String,
            let callID = payload["call_id"] as? String,
            !callID.isEmpty
        else { return nil }
        if type == "function_call",
            ["request_user_input", "functions.request_user_input"].contains(payload["name"] as? String ?? "")
        {
            return .questionRequested(callID: callID)
        }
        if type == "function_call_output" {
            return .questionResolved(callID: callID)
        }
        return nil
    }
}

private struct CodexThreadRank {
    let row: CodexThreadState
    let distance: Int64
    let beforeStart: Bool
    let updated: Int64
}

enum CodexVersionAdapter {
    static func normalize(_ version: String?) -> String? {
        CodexCompatibilityAdapter.normalize(version)
    }

    static func supports(_ version: String?) -> Bool {
        CodexCompatibilityAdapter.select(version).supportsRichStatus
    }
}

final class CodexStateStore {
    let databaseURL: URL

    init(databaseURL: URL = CodexHomeResolver.databaseURL(shell: ShellResolver.detectedLoginShell())) {
        self.databaseURL = databaseURL
    }

    convenience init(context: StatusProviderContext) {
        self.init(
            databaseURL: CodexHomeResolver.databaseURL(
                shell: context.codexShell ?? ShellResolver.detectedLoginShell(),
                workingDirectory: context.workingDirectory,
                environment: context.environment))
    }

    func selectThread(sessionID: String, rolloutPath: String?) throws -> CodexThreadState? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            defer { if db != nil { sqlite3_close(db) } }
            throw CodexStateStoreError.openFailed(message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "nil db")
        }
        defer { sqlite3_close(db) }

        var columnsStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &columnsStatement, nil) == SQLITE_OK,
            let columnsStatement
        else {
            throw CodexStateStoreError.schemaUnavailable
        }
        defer { sqlite3_finalize(columnsStatement) }
        var columns = Set<String>()
        while sqlite3_step(columnsStatement) == SQLITE_ROW {
            if let name = text(columnsStatement, 1) {
                columns.insert(name)
            }
        }
        guard !columns.isEmpty else { throw CodexStateStoreError.schemaUnavailable }
        let required = Set(["id", "cwd"])
        guard required.isSubset(of: columns) else {
            throw CodexStateStoreError.schemaUnavailable
        }

        let selectedColumns = [
            "id",
            "cwd",
            columns.contains("rollout_path") ? "rollout_path" : "NULL AS rollout_path",
            columns.contains("model") ? "model" : "NULL AS model",
            columns.contains("cli_version") ? "cli_version" : "NULL AS cli_version",
            columns.contains("tokens_used") ? "tokens_used" : "NULL AS tokens_used",
            columns.contains("git_branch") ? "git_branch" : "NULL AS git_branch",
            columns.contains("created_at_ms") ? "created_at_ms" : "NULL AS created_at_ms",
            columns.contains("updated_at_ms") ? "updated_at_ms" : "NULL AS updated_at_ms",
            columns.contains("is_archived")
                ? "is_archived" : columns.contains("archived") ? "archived" : "0 AS archived",
            columns.contains("archived_at_ms") ? "archived_at_ms" : "NULL AS archived_at_ms",
            columns.contains("archived_at") ? "archived_at" : "NULL AS archived_at",
        ].joined(separator: ", ")
        let hasRolloutPathColumn = columns.contains("rollout_path")
        let sql = """
            SELECT \(selectedColumns)
            FROM threads
            WHERE id = ?1 \(hasRolloutPathColumn && rolloutPath != nil ? "OR rollout_path = ?2" : "")
            ORDER BY updated_at_ms DESC, created_at_ms DESC
            LIMIT 1
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CodexStateStoreError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if hasRolloutPathColumn, let rolloutPath {
            sqlite3_bind_text(statement, 2, rolloutPath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let archivedValue = optionalInt(statement, 9) ?? 0
        let archivedText = text(statement, 9)?.lowercased()
        let archivedAtMs = optionalInt64(statement, 10)
        let archivedAt = text(statement, 11)
        let isArchived =
            archivedValue != 0
            || archivedText == "true"
            || archivedText == "yes"
            || (archivedAtMs ?? 0) > 0
            || archivedAt != nil
        return CodexThreadState(
            id: text(statement, 0) ?? "",
            cwd: text(statement, 1),
            rolloutPath: text(statement, 2),
            model: text(statement, 3),
            cliVersion: CodexVersionAdapter.normalize(text(statement, 4)),
            tokensUsed: optionalInt(statement, 5),
            gitBranch: text(statement, 6),
            createdAtMs: optionalInt64(statement, 7),
            updatedAtMs: optionalInt64(statement, 8),
            isArchived: isArchived,
            candidateCount: 1
        )
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        let value = String(cString: raw)
        return value.isEmpty ? nil : value
    }

    private func optionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }

    private func optionalInt64(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }
}

enum CodexStateStoreError: Error, Equatable {
    case openFailed(message: String)
    case schemaUnavailable
    case queryFailed(message: String)
    case ambiguousSession
}

struct CodexRolloutParser {
    private static let baselineTokenCount = 12_000

    static func parseLine(
        _ data: Data,
        expectedCWD: String,
        adapter: CodexCompatibilityAdapter = .legacy(version: "0.136.0")
    ) -> StatusLineData? {
        guard adapter.supportsRichStatus else { return nil }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else { return nil }

        if type == "session_meta" {
            let payload = object["payload"] as? [String: Any]
            let cwd = payload?["cwd"] as? String ?? object["cwd"] as? String ?? object["workspace"] as? String
            guard cwd == nil || cwd == expectedCWD else { return nil }
            let model = payload?["model"] as? String ?? object["model"] as? String
            return StatusLineData(
                model: model.map { StatusLineData.Model(id: $0, displayName: $0) },
                cost: nil,
                contextWindow: nil,
                rateLimits: nil,
                worktree: nil,
                workspace: nil,
                effort: nil,
                thinking: nil,
                agent: nil,
                outputStyle: nil,
                vim: nil,
                sessionName: nil,
                version: CodexVersionAdapter.normalize(
                    payload?["cli_version"] as? String ?? object["cli_version"] as? String),
                exceeds200kTokens: nil,
                pr: nil,
                sessionStatus: nil
            )
        }

        if type == "turn_context", case .current = adapter,
            let payload = object["payload"] as? [String: Any],
            let model = payload["model"] as? String
        {
            return StatusLineData(
                model: StatusLineData.Model(id: model, displayName: model),
                cost: nil,
                contextWindow: nil,
                rateLimits: nil,
                worktree: nil,
                workspace: nil,
                effort: nil,
                thinking: nil,
                agent: nil,
                outputStyle: nil,
                vim: nil,
                sessionName: nil,
                version: nil,
                exceeds200kTokens: nil,
                pr: nil,
                sessionStatus: nil
            )
        }

        guard type == "event_msg",
            let payload = object["payload"] as? [String: Any],
            let payloadType = payload["type"] as? String
        else { return nil }

        if payloadType == "turn_context" {
            let model =
                payload["model"] as? String
                ?? (payload["turn_context"] as? [String: Any])?["model"] as? String
                ?? (payload["info"] as? [String: Any])?["model"] as? String
            return model.map {
                StatusLineData(
                    model: StatusLineData.Model(id: $0, displayName: $0),
                    cost: nil,
                    contextWindow: nil,
                    rateLimits: nil,
                    worktree: nil,
                    workspace: nil,
                    effort: nil,
                    thinking: nil,
                    agent: nil,
                    outputStyle: nil,
                    vim: nil,
                    sessionName: nil,
                    version: nil,
                    exceeds200kTokens: nil,
                    pr: nil,
                    sessionStatus: nil
                )
            }
        }

        guard payloadType == "token_count" else { return nil }

        let info = payload["info"] as? [String: Any]
        let totalUsage = info?["total_token_usage"] as? [String: Any] ?? payload["total_token_usage"] as? [String: Any]
        let lastUsage = info?["last_token_usage"] as? [String: Any] ?? payload["last_token_usage"] as? [String: Any]
        let input = int(totalUsage?["input_tokens"]) ?? int(totalUsage?["total_input_tokens"])
        let output = int(totalUsage?["output_tokens"]) ?? int(totalUsage?["total_output_tokens"])
        let contextWindow =
            int(info?["model_context_window"]) ?? int(payload["model_context_window"])
            ?? int(totalUsage?["model_context_window"])
        let contextTokens =
            int(lastUsage?["total_tokens"])
            ?? (int(lastUsage?["input_tokens"]) ?? int(lastUsage?["total_input_tokens"])).flatMap { lastInput in
                (int(lastUsage?["output_tokens"]) ?? int(lastUsage?["total_output_tokens"])).map { lastInput + $0 }
            }
        let remainingPct = contextWindow.flatMap { window -> Int? in
            guard let contextTokens else { return nil }
            guard window > baselineTokenCount else { return 0 }
            let effectiveWindow = window - baselineTokenCount
            let used = contextTokens > baselineTokenCount ? contextTokens - baselineTokenCount : 0
            let remaining = effectiveWindow > used ? effectiveWindow - used : 0
            return Int((Double(remaining) / Double(effectiveWindow) * 100).rounded(.toNearestOrAwayFromZero))
        }
        let usedPct = remainingPct.map { 100 - $0 }
        let model = payload["model"] as? String ?? info?["model"] as? String

        let rawRateLimits = payload["rate_limits"] as? [String: Any]
        let rateLimits = rawRateLimits.map {
            StatusLineData.RateLimits(
                fiveHour: rate($0["primary"] as? [String: Any], expectedWindowMinutes: 300),
                sevenDay: rate($0["secondary"] as? [String: Any], expectedWindowMinutes: 10_080),
                bucketID: $0["limit_id"] as? String ?? "codex")
        }

        return StatusLineData(
            model: model.map { StatusLineData.Model(id: $0, displayName: $0) },
            cost: nil,
            contextWindow: StatusLineData.ContextWindow(
                usedPercentage: usedPct,
                remainingPercentage: remainingPct,
                totalInputTokens: input,
                totalOutputTokens: output
            ),
            rateLimits: rateLimits,
            worktree: nil,
            workspace: nil,
            effort: nil,
            thinking: nil,
            agent: nil,
            outputStyle: nil,
            vim: nil,
            sessionName: nil,
            version: nil,
            exceeds200kTokens: nil,
            pr: nil,
            sessionStatus: nil
        )
    }

    private static func rate(_ raw: [String: Any]?, expectedWindowMinutes: Int) -> StatusLineData.RateLimit? {
        guard let raw, int(raw["window_minutes"]) == expectedWindowMinutes else { return nil }
        return StatusLineData.RateLimit(
            usedPercentage: double(raw["used_percentage"]) ?? double(raw["used_percent"]),
            resetsAt: int(raw["resets_at"])
        )
    }

    private static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

@MainActor
final class CodexRolloutTailer {
    let rolloutPath: String
    let expectedCWD: String
    let adapter: CodexCompatibilityAdapter
    var onUpdate: ((StatusLineData) -> Void)?
    var onAttention: ((CodexTranscriptAttentionEvent) -> Void)?
    var onUnavailable: (() -> Void)?
    var onTrace: ((String, [String: String]) -> Void)?
    private var watcher: FileSystemEventWatcher?
    private var offset: UInt64 = 0
    private var pendingLineBuffer = Data()

    init(
        rolloutPath: String,
        expectedCWD: String,
        adapter: CodexCompatibilityAdapter = .legacy(version: "0.136.0")
    ) {
        self.rolloutPath = rolloutPath
        self.expectedCWD = expectedCWD
        self.adapter = adapter
    }

    func start() {
        stop()
        offset = 0
        pendingLineBuffer = Data()
        readNewLines(catchUp: true)
        watcher = FileSystemEventWatcher(
            url: URL(filePath: rolloutPath),
            followsReplacement: true,
            onEvent: { [weak self] event in
                guard let self else { return }
                if event != .contentChanged {
                    offset = 0
                    pendingLineBuffer = Data()
                }
                readNewLines(catchUp: event != .contentChanged)
            },
            onStateChange: { [weak self] state in
                guard let self else { return }
                switch state {
                case .started:
                    onTrace?("statusline.codex.tailer_started", ["result": "started"])
                case .waitingForFile(let openError):
                    onTrace?(
                        "statusline.codex.tailer_attachment",
                        ["result": "waiting", "errno": String(openError)])
                    onUnavailable?()
                case .recovered:
                    onTrace?("statusline.codex.tailer_attachment", ["result": "recovered"])
                case .stopped:
                    onTrace?("statusline.codex.tailer_stopped", ["result": "stopped"])
                }
            }
        )
        watcher?.start()
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
    }

    private func readNewLines(catchUp: Bool) {
        guard let handle = FileHandle(forReadingAtPath: rolloutPath) else {
            onTrace?("statusline.codex.tailer_read", ["result": "unreadable"])
            onUnavailable?()
            return
        }
        defer { try? handle.close() }
        do {
            let fileSize = try handle.seekToEnd()
            if fileSize < offset {
                offset = 0
                pendingLineBuffer = Data()
            }
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            offset += UInt64(data.count)
            guard !data.isEmpty || !pendingLineBuffer.isEmpty else {
                onTrace?(
                    "statusline.codex.tailer_read",
                    ["line_count": "0", "update_count": "0", "catch_up": catchUp ? "true" : "false"])
                return
            }

            pendingLineBuffer.append(data)
            guard let lastNewline = pendingLineBuffer.lastIndex(of: UInt8(ascii: "\n")) else { return }

            let completeData = pendingLineBuffer[..<lastNewline]
            let afterNewline = pendingLineBuffer.index(after: lastNewline)
            pendingLineBuffer = Data(pendingLineBuffer[afterNewline...])

            var lines = completeData.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            if catchUp, lines.count > 200 {
                lines = lines.suffix(200)
            }

            var lineCount = 0
            var updateCount = 0
            for line in lines {
                lineCount += 1
                guard line.count <= 64 * 1024 else { continue }
                guard (try? JSONSerialization.jsonObject(with: Data(line))) != nil else {
                    onTrace?("statusline.codex.tailer_read", ["result": "malformed_record"])
                    onUnavailable?()
                    continue
                }
                if let update = CodexRolloutParser.parseLine(
                    Data(line), expectedCWD: expectedCWD, adapter: adapter)
                {
                    updateCount += 1
                    onUpdate?(update)
                }
                if let attention = CodexTranscriptAttentionEvent.parseLine(Data(line)) {
                    onAttention?(attention)
                }
            }
            onTrace?(
                "statusline.codex.tailer_read",
                [
                    "line_count": "\(lineCount)",
                    "update_count": "\(updateCount)",
                    "catch_up": catchUp ? "true" : "false",
                ])
        } catch {
            onTrace?("statusline.codex.tailer_read", ["result": "unreadable"])
            onUnavailable?()
        }
    }
}

@MainActor
final class CodexStatusProvider: StatusLineDataProvider {
    var onUpdate: ((StatusLineData) -> Void)?
    var onAttention: ((PaneAttentionEvent) -> Void)?
    var onAttentionResolved: ((NotificationKind) -> Void)?
    var onHookRecords: (([CodexHookQueueRecord]) -> Void)?
    var onHookFailure: (() -> Void)?
    var onActivityChanged: ((Bool) -> Void)?
    var onSessionBound: ((String, String?) -> Void)?
    private(set) var pendingHookRecords: [CodexHookQueueRecord] = []

    private let context: StatusProviderContext
    private let adapter: CodexCompatibilityAdapter
    var supportsForegroundLifecycle: Bool {
        adapter.hookEvents.contains("UserPromptSubmit") && adapter.hookEvents.contains("Stop")
    }
    private let stateStore: CodexStateStore
    private let startupRetryInterval: TimeInterval
    private let startupTimeout: TimeInterval
    private let baseline: ToolAgnosticDataProvider
    private var tailer: CodexRolloutTailer?
    private var tailerSessionID: String?
    private var stateTask: Task<Void, Never>?
    private var enrichmentTask: Task<Void, Never>?
    private var hookDiagnosticTask: Task<Void, Never>?
    private var latestHarnessData: StatusLineData?
    private var latestBaselineData: StatusLineData?
    private var quotaSnapshotsByBucket: [String: StatusLineData.RateLimits] = [:]
    private var boundSessionID: String?
    private var boundTranscriptPath: String?
    private var hasTranscriptUpdateForBoundSession = false
    private var foregroundTurnIsWorking: Bool?
    private var pendingQuestionCallIDs = Set<String>()

    init(
        context: StatusProviderContext,
        stateStore: CodexStateStore? = nil,
        startupRetryInterval: TimeInterval = 0.5,
        startupTimeout: TimeInterval = 15
    ) {
        self.context = context
        self.adapter = context.codexAdapter ?? CodexCompatibilityAdapter.select(context.detectedHarnessVersion)
        self.stateStore = stateStore ?? CodexStateStore(context: context)
        self.startupRetryInterval = startupRetryInterval
        self.startupTimeout = startupTimeout
        self.baseline = ToolAgnosticDataProvider(
            workingDirectory: context.workingDirectory,
            toolCommand: context.harness.commandDescription,
            processStartTime: context.processStartTime
        )
    }

    func start() {
        baseline.onUpdate = { [weak self] data in
            guard let self else { return }
            self.latestBaselineData = data
            self.emitMerged()
        }
        baseline.start()
        if context.codexHookDiagnosticPath != nil {
            hookDiagnosticTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.readAndRecordHookWriterDiagnostic()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        stateTask = Task { [weak self] in
            guard let self else { return }
            guard adapter.supportsRichStatus else {
                trace(
                    "statusline.codex.compatibility.selected",
                    attributes: [
                        "adapter": adapter.identifier,
                        "version": adapter.version ?? "unknown",
                        "result": "baseline_only",
                    ])
                return
            }
            trace(
                "statusline.codex.compatibility.selected",
                attributes: [
                    "adapter": adapter.identifier,
                    "version": adapter.version ?? "unknown",
                    "result": "enabled",
                    "hook_count": "\(adapter.hookEvents.count)",
                ])
            guard context.codexHookQueuePath != nil || context.codexHookRecordPath != nil else {
                traceRetryableSelectionFailure(
                    reason: "missing_hook_path", retryReason: "missing_hook_path", attempt: 1)
                return
            }
            let queue = context.codexHookQueuePath.map { CodexHookQueue(fileURL: URL(filePath: $0)) }
            let deadline = Date().addingTimeInterval(startupTimeout)
            var attempt = 0
            var didTraceLateWaiting = false

            while !Task.isCancelled {
                attempt += 1
                let lateBound = Date() > deadline
                readAndRecordHookWriterDiagnostic()
                var candidateRecords: [CodexHookQueueRecord] = []
                if let queue {
                    do {
                        let drain = try queue.drain()
                        candidateRecords = drain.records
                        if !drain.records.isEmpty || drain.malformedRecordCount > 0 || drain.partialRecordRetained
                            || attempt == 1 || attempt.isMultiple(of: 20)
                        {
                            trace(
                                "statusline.codex.hook_queue.drained",
                                attributes: [
                                    "record_count": "\(drain.records.count)",
                                    "malformed_count": "\(drain.malformedRecordCount)",
                                    "partial_retained": String(drain.partialRecordRetained),
                                    "retry_attempt": "\(attempt)",
                                ])
                        }
                    } catch {
                        let failureCode: String
                        switch error as? CodexHookQueueError {
                        case .openFailed: failureCode = "open_failed"
                        case .lockUnavailable: failureCode = "lock_unavailable"
                        case .readFailed: failureCode = "read_failed"
                        case .writeFailed: failureCode = "compaction_failed"
                        case .fileTooLarge: failureCode = "queue_too_large"
                        case nil: failureCode = "unknown"
                        }
                        trace(
                            "statusline.codex.hook_queue.read_failed",
                            attributes: [
                                "result": failureCode,
                                "retry_attempt": "\(attempt)",
                            ])
                    }
                }
                let validRecords = candidateRecords.filter {
                    $0.paneID == context.paneID.uuidString
                        && $0.tabID == context.tabID.uuidString
                        && (context.codexLaunchGeneration == nil
                            || $0.launchGeneration == context.codexLaunchGeneration)
                        && !$0.isDelegated
                        && adapter.hookEvents.contains($0.hookEventName)
                }
                if !validRecords.isEmpty {
                    pendingHookRecords.append(contentsOf: validRecords)
                    onHookRecords?(validRecords)
                    for record in validRecords {
                        if record.hookEventName == "UserPromptSubmit" {
                            pendingQuestionCallIDs.removeAll()
                        }
                        let nextWorkingState: Bool?
                        switch record.hookEventName {
                        case "UserPromptSubmit": nextWorkingState = true
                        case "Stop", "Interrupt": nextWorkingState = false
                        default: nextWorkingState = nil
                        }
                        if let nextWorkingState, foregroundTurnIsWorking != nextWorkingState {
                            foregroundTurnIsWorking = nextWorkingState
                            trace(
                                "statusline.codex.activity.changed",
                                attributes: [
                                    "pane.id": context.paneID.uuidString,
                                    "pane.name": context.paneName,
                                    "tab.id": context.tabID.uuidString,
                                    "tab.name": context.tabName,
                                    "state": nextWorkingState ? "working" : "stopped",
                                    "hook_event_name": record.hookEventName,
                                ])
                            onActivityChanged?(nextWorkingState)
                        }
                    }
                }
                for queuedRecord in candidateRecords where !validRecords.contains(queuedRecord) {
                    trace(
                        "statusline.codex.hook_queue.record_ignored",
                        attributes: [
                            "reason": queuedRecord.paneID != context.paneID.uuidString
                                || queuedRecord.tabID != context.tabID.uuidString
                                ? "pane_tab_mismatch"
                                : queuedRecord.isDelegated
                                    ? "delegated_source" : "generation_or_event_mismatch",
                            "hook_event_name": queuedRecord.hookEventName,
                        ])
                }
                if let queuedRecord = validRecords.last(where: {
                    ["SessionStart", "UserPromptSubmit"].contains($0.hookEventName)
                        && !($0.sessionID ?? "").isEmpty
                }), let sessionID = queuedRecord.sessionID {
                    let record = CodexHookSessionRecord(
                        paneID: queuedRecord.paneID,
                        tabID: queuedRecord.tabID,
                        sessionID: sessionID,
                        cwd: context.workingDirectory,
                        model: queuedRecord.model,
                        transcriptPath: queuedRecord.transcriptPath,
                        hookEventName: queuedRecord.hookEventName,
                        timestamp: queuedRecord.timestamp)
                    bind(record: record, attempt: attempt, lateBound: lateBound)
                } else if let hookRecordPath = context.codexHookRecordPath,
                    let record = readHookRecord(path: hookRecordPath)
                {
                    guard record.paneID == context.paneID.uuidString, record.tabID == context.tabID.uuidString else {
                        if attempt == 1 || attempt.isMultiple(of: 20) {
                            trace(
                                "statusline.codex.hook_record_ignored",
                                attributes: [
                                    "reason": "hook_context_mismatch",
                                    "retry_attempt": "\(attempt)",
                                    "late_bound": lateBound ? "true" : "false",
                                    "record_pane_id": record.paneID,
                                    "record_tab_id": record.tabID,
                                    "hook_event_name": record.hookEventName,
                                ])
                        }
                        if !lateBound {
                            traceRetryableSelectionFailure(
                                reason: "hook_context_mismatch",
                                retryReason: "hook_context_mismatch",
                                attempt: attempt,
                                extraAttributes: [
                                    "hook_record_available": "true",
                                    "hook_event_name": record.hookEventName,
                                ])
                        }
                        _ = await sleepUntilNextRetry(deadline: nil)
                        continue
                    }
                    bind(record: record, attempt: attempt, lateBound: lateBound)
                }

                for record in validRecords where record.hookEventName == "PermissionRequest" {
                    guard record.sessionID == boundSessionID else {
                        trace("statusline.codex.permission.ignored", attributes: ["reason": "session_mismatch"])
                        continue
                    }
                    onAttention?(.codexPermissionRequest)
                    trace("statusline.codex.permission.attention", attributes: ["result": "requested"])
                }

                if attempt == 1 || attempt.isMultiple(of: 20) || (lateBound && !didTraceLateWaiting) {
                    trace(
                        "statusline.codex.hook_waiting",
                        attributes: [
                            "retry_attempt": "\(attempt)",
                            "late_bound": lateBound ? "true" : "false",
                            "hook_record_available": "false",
                        ])
                    if lateBound {
                        didTraceLateWaiting = true
                    }
                }
                if !lateBound {
                    traceRetryableSelectionFailure(
                        reason: "hook_record_unavailable",
                        retryReason: "waiting_for_hook_record",
                        attempt: attempt,
                        extraAttributes: ["hook_record_available": "false"])
                }
                _ = await sleepUntilNextRetry(deadline: nil)
            }
        }
    }

    func stop() {
        stateTask?.cancel()
        stateTask = nil
        enrichmentTask?.cancel()
        enrichmentTask = nil
        hookDiagnosticTask?.cancel()
        hookDiagnosticTask = nil
        baseline.stop()
        tailer?.stop()
        tailer = nil
        tailerSessionID = nil
    }

    private func readAndRecordHookWriterDiagnostic() {
        guard let path = context.codexHookDiagnosticPath else { return }
        do {
            let records = try CodexHookDiagnosticQueue(fileURL: URL(filePath: path)).drain()
            for record in records {
                if record.kind == "invoked" {
                    trace(
                        "statusline.codex.hook.invoked",
                        attributes: ["hook_event_name": record.eventName, "result": record.result])
                } else {
                    trace(
                        "statusline.codex.hook_queue.write_failed",
                        attributes: ["hook_event_name": record.eventName, "result": record.result])
                    onHookFailure?()
                }
            }
        } catch {
            let reason: String
            switch error as? CodexHookQueueError {
            case .openFailed: reason = "open_failed"
            case .lockUnavailable: reason = "lock_unavailable"
            case .readFailed: reason = "read_failed"
            case .writeFailed: reason = "truncate_failed"
            case .fileTooLarge: reason = "file_too_large"
            case nil: reason = "unknown"
            }
            trace("statusline.codex.hook_diagnostic.read_failed", attributes: ["reason": reason])
        }
    }

    private func bind(record: CodexHookSessionRecord, attempt: Int, lateBound: Bool) {
        let sessionChanged = boundSessionID != record.sessionID
        let nextTranscriptPath = record.transcriptPath ?? boundTranscriptPath
        let transcriptChanged = boundTranscriptPath != nextTranscriptPath
        if !sessionChanged && !transcriptChanged {
            if !hasTranscriptUpdateForBoundSession,
                let model = record.model,
                latestHarnessData?.model?.id != model
            {
                latestHarnessData = mergeHarnessData(
                    StatusLineData(
                        model: StatusLineData.Model(id: model, displayName: model),
                        cost: nil,
                        contextWindow: nil,
                        rateLimits: nil,
                        worktree: nil,
                        workspace: nil,
                        effort: nil,
                        thinking: nil,
                        agent: nil,
                        outputStyle: nil,
                        vim: nil,
                        sessionName: nil,
                        version: nil,
                        exceeds200kTokens: nil,
                        pr: nil,
                        sessionStatus: nil))
                emitMerged()
            }
            if attempt == 1 || attempt.isMultiple(of: 20) {
                trace(
                    "statusline.codex.binding.unchanged",
                    attributes: [
                        "hook_event_name": record.hookEventName,
                        "session_id_prefix": String(record.sessionID.prefix(12)),
                        "retry_attempt": "\(attempt)",
                    ])
            }
            return
        }

        if sessionChanged {
            enrichmentTask?.cancel()
            enrichmentTask = nil
            if tailer != nil {
                tailer?.stop()
                tailer = nil
                tailerSessionID = nil
                trace("statusline.codex.tailer_detached", attributes: ["reason": "session_changed"])
            }
            boundSessionID = record.sessionID
            boundTranscriptPath = record.transcriptPath
            hasTranscriptUpdateForBoundSession = false
            latestHarnessData = nil
            quotaSnapshotsByBucket = [:]
            trace(
                "statusline.codex.binding.facts_cleared",
                attributes: [
                    "session_id_prefix": String(record.sessionID.prefix(12)),
                    "reason": "session_changed",
                ])
            onSessionBound?(record.sessionID, record.transcriptPath)
            trace(
                "statusline.codex.binding.callback",
                attributes: [
                    "session_id_prefix": String(record.sessionID.prefix(12))
                ])
        } else {
            let previousTranscriptPath = boundTranscriptPath
            boundTranscriptPath = nextTranscriptPath
            if previousTranscriptPath != nextTranscriptPath, let nextTranscriptPath {
                onSessionBound?(record.sessionID, nextTranscriptPath)
            }
        }

        if let model = record.model {
            latestHarnessData = mergeHarnessData(
                StatusLineData(
                    model: StatusLineData.Model(id: model, displayName: model),
                    cost: nil,
                    contextWindow: nil,
                    rateLimits: nil,
                    worktree: nil,
                    workspace: nil,
                    effort: nil,
                    thinking: nil,
                    agent: nil,
                    outputStyle: nil,
                    vim: nil,
                    sessionName: nil,
                    version: nil,
                    exceeds200kTokens: nil,
                    pr: nil,
                    sessionStatus: nil))
        }
        latestHarnessData = mergeHarnessData(
            StatusLineData(
                model: nil,
                cost: nil,
                contextWindow: nil,
                rateLimits: nil,
                worktree: nil,
                workspace: nil,
                effort: nil,
                thinking: nil,
                agent: nil,
                outputStyle: nil,
                vim: nil,
                sessionName: nil,
                version: adapter.version,
                exceeds200kTokens: nil,
                pr: nil,
                sessionStatus: nil))
        trace(
            sessionChanged ? "statusline.codex.binding.changed" : "statusline.codex.binding.transcript_updated",
            attributes: [
                "hook_event_name": record.hookEventName,
                "retry_attempt": "\(attempt)",
                "late_bound": String(lateBound),
                "session_id_prefix": String(record.sessionID.prefix(12)),
                "transcript_available": boundTranscriptPath.map {
                    FileManager.default.fileExists(atPath: $0) ? "true" : "false"
                } ?? "false",
            ])
        emitMerged()

        if let path = boundTranscriptPath,
            tailerSessionID != record.sessionID || tailer?.rolloutPath != path
        {
            startTailer(path: path, sessionID: record.sessionID)
        }

        enrichmentTask?.cancel()
        enrichmentTask = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(startupTimeout)
            var attempt = 0
            while !Task.isCancelled {
                attempt += 1
                do {
                    let thread = try stateStore.selectThread(
                        sessionID: record.sessionID, rolloutPath: record.transcriptPath)
                    trace(
                        "statusline.codex.sqlite_enrichment",
                        attributes: [
                            "result": thread == nil ? "no_match" : "matched",
                            "retry_attempt": "\(attempt)",
                            "session_id_prefix": String(record.sessionID.prefix(12)),
                            "rollout_path_matched": thread?.rolloutPath == record.transcriptPath ? "true" : "false",
                        ])
                    guard boundSessionID == record.sessionID else { return }
                    if let thread {
                        latestHarnessData = mergeHarnessData(
                            StatusLineData(
                                model: hasTranscriptUpdateForBoundSession
                                    ? nil : thread.model.map { StatusLineData.Model(id: $0, displayName: $0) },
                                cost: nil,
                                contextWindow: nil,
                                rateLimits: nil,
                                worktree: nil,
                                workspace: nil,
                                effort: nil,
                                thinking: nil,
                                agent: nil,
                                outputStyle: nil,
                                vim: nil,
                                sessionName: nil,
                                version: thread.cliVersion,
                                exceeds200kTokens: nil,
                                pr: nil,
                                sessionStatus: nil))
                        emitMerged()
                        if boundTranscriptPath == nil, let tailerPath = thread.rolloutPath {
                            boundTranscriptPath = tailerPath
                            startTailer(path: tailerPath, sessionID: record.sessionID)
                        }
                        return
                    }
                } catch let error as CodexStateStoreError {
                    trace(
                        "statusline.codex.sqlite_enrichment",
                        attributes: ["result": sqliteResult(for: error), "retry_attempt": "\(attempt)"])
                } catch {
                    trace(
                        "statusline.codex.sqlite_enrichment",
                        attributes: ["result": "unknown", "retry_attempt": "\(attempt)"])
                }
                if await sleepUntilNextRetry(deadline: deadline) { continue }
                return
            }
        }
    }

    private func readHookRecord(path: String) -> CodexHookSessionRecord? {
        guard let data = try? Data(contentsOf: URL(filePath: path)), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(CodexHookSessionRecord.self, from: data)
    }

    private func sqliteResult(for error: CodexStateStoreError) -> String {
        switch error {
        case .schemaUnavailable:
            return "schema_unavailable"
        case .openFailed:
            return "open_failed"
        case .queryFailed:
            return "query_failed"
        case .ambiguousSession:
            return "ambiguous_session"
        }
    }

    private func traceRetryableSelectionFailure(
        reason: String,
        retryReason: String,
        attempt: Int,
        extraAttributes: [String: String] = [:]
    ) {
        var attributes = [
            "reason": reason,
            "retry_reason": retryReason,
            "retry_attempt": "\(attempt)",
        ]
        for (key, value) in extraAttributes {
            attributes[key] = value
        }
        trace("statusline.codex.selection_failed", attributes: attributes)
    }

    private func sleepUntilNextRetry(deadline: Date?) async -> Bool {
        guard startupRetryInterval > 0 else { return false }
        let sleepSeconds: TimeInterval
        if let deadline {
            guard Date() < deadline else { return false }
            sleepSeconds = min(startupRetryInterval, max(0, deadline.timeIntervalSinceNow))
        } else {
            sleepSeconds = startupRetryInterval
        }
        guard sleepSeconds > 0 else { return false }
        try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
        guard !Task.isCancelled else { return false }
        if let deadline {
            return Date() <= deadline
        }
        return true
    }

    private func startTailer(path: String, sessionID: String) {
        tailer?.stop()
        let next = CodexRolloutTailer(
            rolloutPath: path, expectedCWD: context.workingDirectory, adapter: adapter)
        next.onTrace = { [weak self] name, attributes in
            self?.trace(name, attributes: attributes)
        }
        next.onAttention = { [weak self] event in
            guard let self, self.boundSessionID == sessionID,
                self.boundTranscriptPath == path, self.tailerSessionID == sessionID,
                self.tailer?.rolloutPath == path
            else { return }
            switch event {
            case .questionRequested(let callID):
                guard pendingQuestionCallIDs.insert(callID).inserted else { return }
                onAttention?(.codexQuestion)
                trace("statusline.codex.question.attention", attributes: ["result": "requested"])
            case .questionResolved(let callID):
                guard pendingQuestionCallIDs.remove(callID) != nil else { return }
                onAttentionResolved?(.codexQuestion)
                trace("statusline.codex.question.attention", attributes: ["result": "resolved"])
            }
        }
        next.onUnavailable = { [weak self] in
            guard let self, self.boundSessionID == sessionID,
                self.boundTranscriptPath == path, self.tailerSessionID == sessionID,
                self.tailer?.rolloutPath == path
            else { return }
            self.latestHarnessData?.model = nil
            self.latestHarnessData?.contextWindow = nil
            self.latestHarnessData?.rateLimits = nil
            self.quotaSnapshotsByBucket = [:]
            self.emitMerged()
        }
        next.onUpdate = { [weak self] data in
            guard let self, self.boundSessionID == sessionID,
                self.boundTranscriptPath == path, self.tailerSessionID == sessionID,
                self.tailer?.rolloutPath == path
            else { return }
            self.trace(
                "statusline.codex.parsed_update",
                attributes: [
                    "has_model": data.model == nil ? "false" : "true",
                    "has_tokens": data.contextWindow?.totalInputTokens == nil
                        && data.contextWindow?.totalOutputTokens == nil ? "false" : "true",
                    "has_context": data.contextWindow?.usedPercentage == nil ? "false" : "true",
                    "has_rate_limits": data.rateLimits == nil ? "false" : "true",
                ])
            self.hasTranscriptUpdateForBoundSession = true
            self.latestHarnessData = self.mergeHarnessData(data)
            self.emitMerged()
        }
        tailer = next
        tailerSessionID = sessionID
        next.start()
    }

    private func mergeHarnessData(_ update: StatusLineData) -> StatusLineData {
        var merged = latestHarnessData ?? update
        if let model = update.model { merged.model = model }
        if let contextWindow = update.contextWindow { merged.contextWindow = contextWindow }
        if let rateLimits = update.rateLimits {
            let bucketID = rateLimits.bucketID ?? "codex"
            let previous = quotaSnapshotsByBucket[bucketID]
            let fiveHour =
                rateLimits.fiveHour.map {
                    StatusLineData.RateLimit(
                        usedPercentage: $0.usedPercentage ?? previous?.fiveHour?.usedPercentage,
                        resetsAt: $0.resetsAt ?? previous?.fiveHour?.resetsAt)
                } ?? previous?.fiveHour
            let sevenDay =
                rateLimits.sevenDay.map {
                    StatusLineData.RateLimit(
                        usedPercentage: $0.usedPercentage ?? previous?.sevenDay?.usedPercentage,
                        resetsAt: $0.resetsAt ?? previous?.sevenDay?.resetsAt)
                } ?? previous?.sevenDay
            quotaSnapshotsByBucket[bucketID] = StatusLineData.RateLimits(
                fiveHour: fiveHour,
                sevenDay: sevenDay,
                bucketID: bucketID)
            if bucketID == "codex" {
                merged.rateLimits = quotaSnapshotsByBucket[bucketID]
            }
        }
        if let version = update.version { merged.version = version }
        return merged
    }

    private func emitMerged() {
        guard var data = latestBaselineData else { return }
        if let harness = latestHarnessData {
            if harness.model != nil { data.model = harness.model }
            if let contextWindow = harness.contextWindow { data.contextWindow = contextWindow }
            if let rateLimits = harness.rateLimits { data.rateLimits = rateLimits }
            if let version = harness.version { data.version = version }
        }
        onUpdate?(data)
    }

    private func trace(_ name: String, attributes extraAttributes: [String: String] = [:]) {
        var attributes = [
            "provider": "codex",
            "pane.name": context.paneName,
            "pane.id": context.paneID.uuidString,
            "tab.id": context.tabID.uuidString,
            "tab.name": context.tabName,
        ]
        for (key, value) in extraAttributes {
            attributes[key] = value
        }
        TracingService.shared.record(name, attributes: attributes)
    }
}
