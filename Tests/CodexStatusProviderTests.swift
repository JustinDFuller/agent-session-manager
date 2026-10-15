import SQLite3
import XCTest

@testable import AgentSessionManager

private struct ContextPercentageScenario {
    let window: Int
    let current: Int
    let used: Int
    let remaining: Int
}

final class CodexStatusProviderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-codex-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testStateStoreSelectsThreadByExactSessionID() throws {
        let dbURL = tempDir.appending(path: "state_5.sqlite")
        try executeSQL(
            """
            CREATE TABLE threads (
              id TEXT,
              cwd TEXT,
              rollout_path TEXT,
              model TEXT,
              cli_version TEXT,
              tokens_used INTEGER,
              git_branch TEXT,
              created_at_ms INTEGER,
              updated_at_ms INTEGER,
              is_archived INTEGER
            );
            INSERT INTO threads VALUES ('old', '/repo', '/old.jsonl', 'gpt-old', '0.136.0', 3, 'main', 1000, 1000, 0);
            INSERT INTO threads VALUES ('new', '/repo', '/new.jsonl', 'gpt-5.1-codex', '0.136.2', 42, 'feature', 2300, 4000, 0);
            INSERT INTO threads VALUES ('other', '/other', '/other.jsonl', 'gpt-other', '0.136.2', 1, 'main', 5000, 5000, 0);
            """,
            at: dbURL
        )

        let selection = try CodexStateStore(databaseURL: dbURL)
            .selectThread(sessionID: "new", rolloutPath: nil)
        let selected = selection

        XCTAssertEqual(selected?.id, "new")
        XCTAssertEqual(selected?.rolloutPath, "/new.jsonl")
        XCTAssertEqual(selected?.model, "gpt-5.1-codex")
        XCTAssertEqual(selected?.cliVersion, "0.136.2")
        XCTAssertEqual(selected?.tokensUsed, 42)
        XCTAssertEqual(selected?.gitBranch, "feature")
        XCTAssertEqual(selected?.createdAtMs, 2300)
        XCTAssertEqual(selected?.updatedAtMs, 4000)
    }

    func testContinuationVerifierRequiresExactAccessibleSessionInEffectiveCodexHome() throws {
        let codexHome = tempDir.appending(path: "custom-codex-home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let rollout = tempDir.appending(path: "exact-session.jsonl")
        try Data("{}\n".utf8).write(to: rollout)
        let database = codexHome.appending(path: "state_5.sqlite")
        try createThreadDatabase(
            at: database,
            rolloutPath: rollout.path,
            model: "gpt-6-luna",
            createdAtMs: 1)
        let environment = ["CODEX_HOME": codexHome.path]

        XCTAssertEqual(
            CodexContinuationVerifier.check(
                sessionID: "thread-abcdef1234567890",
                transcriptPath: rollout.path,
                shell: "/bin/sh",
                workingDirectory: tempDir.path,
                environment: environment),
            .available)
        XCTAssertEqual(
            CodexContinuationVerifier.check(
                sessionID: "different-session",
                transcriptPath: rollout.path,
                shell: "/bin/sh",
                workingDirectory: tempDir.path,
                environment: environment),
            .missing)
        XCTAssertEqual(
            CodexContinuationVerifier.check(
                sessionID: "thread-abcdef1234567890",
                transcriptPath: "/tmp/stale-transcript.jsonl",
                shell: "/bin/sh",
                workingDirectory: tempDir.path,
                environment: environment),
            .missing)
        XCTAssertEqual(
            CodexContinuationVerifier.check(
                sessionID: "thread-abcdef1234567890",
                transcriptPath: rollout.path,
                shell: "/bin/sh",
                workingDirectory: "/tmp/another-checkout",
                environment: environment),
            .missing)
    }

    func testCodexHomeResolverUsesExplicitNondefaultHome() {
        let customHome = tempDir.appending(path: "custom-codex-home", directoryHint: .isDirectory)
        let resolved = CodexHomeResolver.resolve(
            shell: "/bin/sh", environment: ["CODEX_HOME": customHome.path])

        XCTAssertEqual(resolved.path, customHome.path)
        XCTAssertEqual(
            CodexHomeResolver.databaseURL(shell: "/bin/sh", environment: ["CODEX_HOME": customHome.path]).path,
            customHome.appending(path: "state_5.sqlite").path)
    }

    func testCodexHomeResolverUsesInteractiveShellExport() throws {
        let shell = "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else {
            throw XCTSkip("zsh is unavailable")
        }
        let shellDirectory = tempDir.appending(path: "shell", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shellDirectory, withIntermediateDirectories: true)
        let customHome = tempDir.appending(path: "shell-codex-home", directoryHint: .isDirectory)
        try "export CODEX_HOME='\(customHome.path)'\n".write(
            to: shellDirectory.appending(path: ".zshenv"), atomically: true, encoding: .utf8)

        let resolved = CodexHomeResolver.resolve(
            shell: shell, environment: ["ZDOTDIR": shellDirectory.path])

        XCTAssertEqual(resolved.path, customHome.path)
    }

    func testStateStoreUsesConfiguredShellAndEffectiveLaunchEnvironment() throws {
        let shellDirectory = tempDir.appending(path: "configured-shell", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shellDirectory, withIntermediateDirectories: true)
        let customHome = tempDir.appending(path: "configured-shell-codex-home", directoryHint: .isDirectory)
        try "export CODEX_HOME='\(customHome.path)'\n".write(
            to: shellDirectory.appending(path: ".zshenv"), atomically: true, encoding: .utf8)
        let context = makeContext(
            processStartTime: Date(),
            codexShell: "/bin/zsh",
            environment: ["ZDOTDIR": shellDirectory.path])

        XCTAssertEqual(
            CodexStateStore(context: context).databaseURL.path,
            customHome.appending(path: "state_5.sqlite").path)
    }

    func testCodexHomeResolverFallsBackWhenHomeAndStateDatabaseAreMissing() {
        let customHome = tempDir.appending(path: "missing-codex-home", directoryHint: .isDirectory)
        let databaseURL = CodexHomeResolver.databaseURL(
            shell: "/bin/sh", environment: ["CODEX_HOME": customHome.path])

        XCTAssertEqual(databaseURL.path, customHome.appending(path: "state_5.sqlite").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertThrowsError(
            try CodexStateStore(databaseURL: databaseURL)
                .selectThread(sessionID: "exact-session", rolloutPath: nil))
    }

    func testTranscriptAttentionAcceptsOnlyNativeQuestionCallsAndMatchingResults() {
        let request = Data(
            #"{"type":"response_item","payload":{"type":"function_call","name":"functions.request_user_input","call_id":"call-private","arguments":"PRIVATE PROMPT CONTENT"}}"#
                .utf8)
        let unrelated = Data(
            #"{"type":"response_item","payload":{"type":"function_call","name":"functions.exec_command","call_id":"call-other","arguments":"PRIVATE COMMAND"}}"#
                .utf8)
        let result = Data(
            #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"call-private","output":"PRIVATE ANSWER"}}"#
                .utf8)

        XCTAssertEqual(
            CodexTranscriptAttentionEvent.parseLine(request),
            .questionRequested(callID: "call-private"))
        XCTAssertNil(CodexTranscriptAttentionEvent.parseLine(unrelated))
        XCTAssertEqual(
            CodexTranscriptAttentionEvent.parseLine(result),
            .questionResolved(callID: "call-private"))
    }

    @MainActor
    func testProviderDeduplicatesNativeQuestionAndClearsOnlyMatchingCall() throws {
        let rolloutURL = tempDir.appending(path: "question-session.jsonl")
        let lines =
            [
                #"{"type":"response_item","payload":{"type":"function_call","name":"functions.request_user_input","call_id":"question-call","arguments":"PRIVATE QUESTION"}}"#,
                #"{"type":"response_item","payload":{"type":"function_call","name":"functions.request_user_input","call_id":"question-call","arguments":"PRIVATE QUESTION"}}"#,
                #"{"type":"response_item","payload":{"type":"function_call","name":"functions.exec_command","call_id":"other-call","arguments":"PRIVATE COMMAND"}}"#,
                #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"other-call","output":"PRIVATE RESULT"}}"#,
                #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"question-call","output":"PRIVATE ANSWER"}}"#,
            ].joined(separator: "\n") + "\n"
        try lines.write(to: rolloutURL, atomically: true, encoding: .utf8)
        let hookRecordURL = tempDir.appending(path: "question-hook-record.json")
        try writeHookRecord(to: hookRecordURL, sessionID: "question-session", transcriptPath: rolloutURL.path)
        let dbURL = tempDir.appending(path: "question-session.sqlite")
        try createThreadDatabase(
            at: dbURL,
            rolloutPath: rolloutURL.path,
            model: "question-model",
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000))
        let provider = CodexStatusProvider(
            context: makeContext(
                processStartTime: Date(),
                hookRecordPath: hookRecordURL.path,
                adapter: .current(version: "0.162.1")),
            stateStore: CodexStateStore(databaseURL: dbURL),
            startupRetryInterval: 0.01,
            startupTimeout: 0.5)
        let requested = expectation(description: "one native question requests attention")
        let resolved = expectation(description: "matching question result clears attention")
        var attentionEvents: [PaneAttentionEvent] = []
        var resolvedKinds: [NotificationKind] = []
        provider.onAttention = { event in
            attentionEvents.append(event)
            requested.fulfill()
        }
        provider.onAttentionResolved = { kind in
            resolvedKinds.append(kind)
            resolved.fulfill()
        }

        provider.start()
        wait(for: [requested, resolved], timeout: 2)
        provider.stop()

        XCTAssertEqual(attentionEvents, [.codexQuestion])
        XCTAssertEqual(resolvedKinds, [.codexQuestion])
    }

    @MainActor
    func testProviderRoutesBoundPermissionHooksWithFixedCopyAndNoRequestData() throws {
        let context = makeContext(
            processStartTime: Date(),
            queuePath: tempDir.appending(path: "permission-queue.jsonl").path,
            launchGeneration: "permission-generation",
            adapter: .current(version: "0.162.1"))
        let records = ["SessionStart", "PermissionRequest", "PermissionRequest"].map { event in
            CodexHookQueueRecord(
                paneID: context.paneID.uuidString,
                tabID: context.tabID.uuidString,
                launchGeneration: "permission-generation",
                hookEventName: event,
                sessionID: "permission-session",
                turnID: nil,
                requestID: "private-request-id",
                timestamp: Date().timeIntervalSince1970,
                source: "hook",
                model: nil,
                transcriptPath: nil,
                result: nil)
        }
        let queueData = try records.reduce(into: Data()) { data, record in
            data.append(try JSONEncoder().encode(record))
            data.append(UInt8(ascii: "\n"))
        }
        try queueData.write(to: URL(filePath: context.codexHookQueuePath!))
        let provider = CodexStatusProvider(
            context: context,
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-state.sqlite")),
            startupRetryInterval: 0.01,
            startupTimeout: 0.5)
        let attention = expectation(description: "duplicate permission hook deliveries remain fixed copy")
        attention.expectedFulfillmentCount = 2
        var events: [PaneAttentionEvent] = []
        provider.onAttention = { event in
            events.append(event)
            attention.fulfill()
        }

        provider.start()
        wait(for: [attention], timeout: 2)
        provider.stop()

        XCTAssertEqual(events, [.codexPermissionRequest, .codexPermissionRequest])
        XCTAssertFalse(String(describing: events).contains("private-request-id"))
    }

    func testStateStoreSelectsThreadByExactRolloutPath() throws {
        let dbURL = tempDir.appending(path: "state_5.sqlite")
        try executeSQL(
            """
            CREATE TABLE threads (
              id TEXT,
              cwd TEXT,
              rollout_path TEXT,
              model TEXT,
              cli_version TEXT,
              created_at_ms INTEGER,
              updated_at_ms INTEGER,
              is_archived INTEGER
            );
            INSERT INTO threads VALUES ('near-archived', '/repo', '/archived.jsonl', 'gpt-archived', '0.136.0', 2020, 2020, 1);
            INSERT INTO threads VALUES ('near-active', '/repo', '/near.jsonl', 'gpt-near', '0.136.0', 2100, 2100, 0);
            INSERT INTO threads VALUES ('later-active', '/repo', '/later.jsonl', 'gpt-later', '0.136.0', 900000, 900000, 0);
            """,
            at: dbURL
        )

        let selection = try CodexStateStore(databaseURL: dbURL)
            .selectThread(sessionID: "missing", rolloutPath: "/near.jsonl")

        XCTAssertEqual(selection?.id, "near-active")
        XCTAssertFalse(selection?.isArchived ?? true)
    }

    func testStateStoreIgnoresSameCwdRowsWithoutExactMatch() throws {
        let dbURL = tempDir.appending(path: "state_5.sqlite")
        try executeSQL(
            """
            CREATE TABLE threads (
              id TEXT,
              cwd TEXT,
              rollout_path TEXT,
              model TEXT,
              cli_version TEXT,
              created_at_ms INTEGER,
              updated_at_ms INTEGER,
              is_archived INTEGER
            );
            INSERT INTO threads VALUES ('stale', '/repo', '/stale.jsonl', 'gpt-stale', '0.136.0', 1000, 1000, 0);
            """,
            at: dbURL
        )

        let selection = try CodexStateStore(databaseURL: dbURL)
            .selectThread(sessionID: "other-session", rolloutPath: "/other.jsonl")

        XCTAssertNil(selection)
    }

    func testStateStoreReturnsNoMatch() throws {
        let dbURL = tempDir.appending(path: "state_5.sqlite")
        try executeSQL(
            """
            CREATE TABLE threads (id TEXT, cwd TEXT, created_at_ms INTEGER, updated_at_ms INTEGER);
            INSERT INTO threads VALUES ('other', '/other', 1000, 1000);
            """,
            at: dbURL
        )

        let selection = try CodexStateStore(databaseURL: dbURL)
            .selectThread(sessionID: "missing", rolloutPath: nil)

        XCTAssertNil(selection)
    }

    func testStateStoreReportsMissingSchema() throws {
        let dbURL = tempDir.appending(path: "missing.sqlite")
        try executeSQL("CREATE TABLE other (id TEXT);", at: dbURL)

        XCTAssertThrowsError(
            try CodexStateStore(databaseURL: dbURL)
                .selectThread(sessionID: "missing", rolloutPath: nil)
        ) { error in
            XCTAssertEqual(error as? CodexStateStoreError, .schemaUnavailable)
        }
    }

    func testRolloutParserRecognizesForegroundLifecycleAndExcludesDelegatedTurns() {
        let started = CodexRolloutParser.parseActivityEvent(
            Data(
                #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-a","root_turn_id":"turn-a"}}"#
                    .utf8))
        XCTAssertEqual(started, .foregroundTurnStarted(turnID: "turn-a", isForeground: true))

        let delegated = CodexRolloutParser.parseActivityEvent(
            Data(
                #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"subagent-turn","root_turn_id":"turn-a"}}"#
                    .utf8))
        XCTAssertNil(delegated)

        let completed = CodexRolloutParser.parseActivityEvent(
            Data(
                #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-a","root_turn_id":"turn-a","error":null,"last_agent_message":"private answer"}}"#
                    .utf8))
        XCTAssertEqual(completed, .foregroundTurnCompleted(turnID: "turn-a", isForeground: true, succeeded: true))
        XCTAssertFalse(String(describing: completed).contains("private answer"))

        let failed = CodexRolloutParser.parseActivityEvent(
            Data(
                #"{"type":"event_msg","payload":{"type":"turn_complete","turn_id":"turn-a","root_turn_id":"turn-a","error":{"message":"private failure"}}}"#
                    .utf8))
        XCTAssertEqual(failed, .foregroundTurnCompleted(turnID: "turn-a", isForeground: true, succeeded: false))

        let interrupted = CodexRolloutParser.parseActivityEvent(
            Data(
                #"{"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-a","root_turn_id":"turn-a","reason":"interrupted"}}"#
                    .utf8))
        XCTAssertEqual(interrupted, .foregroundTurnInterrupted(turnID: "turn-a", isForeground: true))
    }

    func testRolloutParserKeepsQuestionCallIdentityWithoutContent() {
        let request = CodexRolloutParser.parseActivityEvent(
            Data(
                #"{"type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"question-42","arguments":"private question text"}}"#
                    .utf8))
        XCTAssertEqual(request, .questionRequested(callID: "question-42"))
        XCTAssertFalse(String(describing: request).contains("private question text"))

        let output = CodexRolloutParser.parseActivityEvent(
            Data(
                #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"question-42","output":"private answer"}}"#
                    .utf8))
        XCTAssertEqual(output, .questionResolved(callID: "question-42"))
        XCTAssertFalse(String(describing: output).contains("private answer"))
    }

    func testRolloutParserMapsTokenCountAndRateLimits() throws {
        let line = Data(CodexCompatibilityFixtures.currentTokenCount.utf8)

        let data = CodexRolloutParser.parseLine(
            line, expectedCWD: "/repo", adapter: .current(version: "0.162.1"))

        XCTAssertEqual(data?.contextWindow?.totalInputTokens, 900)
        XCTAssertEqual(data?.contextWindow?.totalOutputTokens, 100)
        XCTAssertEqual(data?.contextWindow?.usedPercentage, 25)
        XCTAssertEqual(data?.contextWindow?.remainingPercentage, 75)
        XCTAssertEqual(data?.rateLimits?.fiveHour?.usedPercentage, 25)
        XCTAssertEqual(data?.rateLimits?.fiveHour?.resetsAt, 2_000_000_000)
        XCTAssertEqual(data?.rateLimits?.sevenDay?.usedPercentage, 50)
        XCTAssertEqual(data?.rateLimits?.sevenDay?.resetsAt, 2_000_003_600)
    }

    func testRolloutParserKeepsQuotaBucketAndUsesOnlyUsedPercentageFields() {
        let premium =
            #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"premium","primary":{"window_minutes":300,"remaining":12},"secondary":{"window_minutes":10080,"used_percent":65,"resets_at":2000003600}}}}"#
        let data = CodexRolloutParser.parseLine(
            Data(premium.utf8), expectedCWD: "/repo", adapter: .current(version: "0.162.1"))

        XCTAssertEqual(data?.rateLimits?.bucketID, "premium")
        XCTAssertNil(data?.rateLimits?.fiveHour?.usedPercentage)
        XCTAssertEqual(data?.rateLimits?.sevenDay?.usedPercentage, 65)
        XCTAssertEqual(data?.rateLimits?.sevenDay?.resetsAt, 2_000_003_600)
    }

    func testCurrentAdapterRejectsQuotaUpdateWithoutBucketID() {
        let line = Data(
            #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"window_minutes":300,"used_percent":15,"resets_at":2000007200},"secondary":{"window_minutes":10080,"used_percent":65,"resets_at":2000003600}}}}"#
                .utf8)

        let data = CodexRolloutParser.parseLine(
            line, expectedCWD: "/repo", adapter: .current(version: "0.162.1"))

        XCTAssertNil(data?.rateLimits)
    }

    func testRolloutParserIgnoresOutOfRangeNumericValues() {
        let line = Data(
            CodexCompatibilityFixtures.currentTokenCount
                .replacingOccurrences(of: "\"input_tokens\":900", with: "\"input_tokens\":1e100")
                .replacingOccurrences(of: "\"model_context_window\":100000", with: "\"model_context_window\":1e100")
                .utf8)

        let data = CodexRolloutParser.parseLine(
            line, expectedCWD: "/repo", adapter: .current(version: "0.162.1"))

        XCTAssertNotNil(data)
        XCTAssertNil(data?.contextWindow?.totalInputTokens)
        XCTAssertEqual(data?.contextWindow?.totalOutputTokens, 100)
        XCTAssertNil(data?.contextWindow?.usedPercentage)
        XCTAssertNil(data?.contextWindow?.remainingPercentage)
    }

    @MainActor
    func testProviderRetainsStandardQuotaAcrossPremiumAndPartialUpdatesThenClearsOnRebind() throws {
        let queueURL = tempDir.appending(path: "quota-hooks.jsonl")
        let firstTranscript = tempDir.appending(path: "quota-first.jsonl")
        let secondTranscript = tempDir.appending(path: "quota-second.jsonl")
        let standard =
            #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"window_minutes":300,"used_percent":20,"resets_at":2000000000},"secondary":{"window_minutes":10080,"used_percent":70,"resets_at":2000003600}}}}"#
        let premium =
            #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"premium","primary":null,"secondary":null}}}"#
        let partialStandard =
            #"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"window_minutes":300,"used_percent":15,"resets_at":2000007200}}}}"#
        try (standard + "\n").write(to: firstTranscript, atomically: true, encoding: .utf8)
        try Data().write(to: secondTranscript)
        let context = makeContext(
            processStartTime: Date(), queuePath: queueURL.path, launchGeneration: "quota-generation")
        try appendQueueRecord(
            to: queueURL,
            paneID: context.paneID,
            tabID: context.tabID,
            generation: "quota-generation",
            sessionID: "quota-session-one",
            transcriptPath: firstTranscript.path)
        let provider = CodexStatusProvider(
            context: context,
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-quota-state.sqlite")),
            startupRetryInterval: 0.02,
            startupTimeout: 0.2)
        let initialQuota = expectation(description: "standard quotas are available")
        let premiumRetained = expectation(description: "premium update leaves standard quotas available")
        let partialRetained = expectation(description: "partial standard update retains weekly quota")
        let reboundCleared = expectation(description: "new conversation clears quota values")
        var stage = "initial"
        provider.onUpdate = { data in
            guard let rates = data.rateLimits else {
                if stage == "rebound" { reboundCleared.fulfill() }
                return
            }
            if stage == "initial", rates.fiveHour?.usedPercentage == 20,
                rates.sevenDay?.usedPercentage == 70
            {
                initialQuota.fulfill()
            }
            if stage == "premium", rates.fiveHour?.usedPercentage == 20,
                rates.sevenDay?.usedPercentage == 70
            {
                premiumRetained.fulfill()
            }
            if stage == "partial", rates.fiveHour?.usedPercentage == 15,
                rates.fiveHour?.resetsAt == 2_000_007_200,
                rates.sevenDay?.usedPercentage == 70, rates.sevenDay?.resetsAt == 2_000_003_600
            {
                partialRetained.fulfill()
            }
        }

        provider.start()
        wait(for: [initialQuota], timeout: 2)
        stage = "premium"
        let handle = try FileHandle(forWritingTo: firstTranscript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((premium + "\n").utf8))
        try handle.close()
        wait(for: [premiumRetained], timeout: 2)
        stage = "partial"
        let partialHandle = try FileHandle(forWritingTo: firstTranscript)
        try partialHandle.seekToEnd()
        try partialHandle.write(contentsOf: Data((partialStandard + "\n").utf8))
        try partialHandle.close()
        wait(for: [partialRetained], timeout: 2)
        stage = "rebound"
        try appendQueueRecord(
            to: queueURL,
            paneID: context.paneID,
            tabID: context.tabID,
            generation: "quota-generation",
            sessionID: "quota-session-two",
            transcriptPath: secondTranscript.path)
        wait(for: [reboundCleared], timeout: 2)
        provider.stop()
    }

    func testCurrentRolloutParserReadsTurnContextModelChanges() {
        let adapter = CodexCompatibilityAdapter.current(version: "0.162.1")
        let initial = CodexRolloutParser.parseLine(
            Data(CodexCompatibilityFixtures.currentTurnContext.utf8),
            expectedCWD: "/repo",
            adapter: adapter)
        let changed = CodexRolloutParser.parseLine(
            Data(#"{"type":"turn_context","payload":{"model":"updated-model"}}"#.utf8),
            expectedCWD: "/repo",
            adapter: adapter)

        XCTAssertEqual(initial?.model?.id, "current-model")
        XCTAssertEqual(changed?.model?.id, "updated-model")
        XCTAssertNil(initial?.contextWindow)
        XCTAssertNil(
            CodexRolloutParser.parseLine(
                Data(CodexCompatibilityFixtures.currentTurnContext.utf8), expectedCWD: "/repo"))
    }

    func testCurrentTokenCountSeparatesCumulativeTotalsFromCurrentOccupancy() {
        let data = CodexRolloutParser.parseLine(
            Data(CodexCompatibilityFixtures.currentTokenCount.utf8),
            expectedCWD: "/repo",
            adapter: .current(version: "0.162.1"))

        XCTAssertEqual(data?.contextWindow?.totalInputTokens, 900)
        XCTAssertEqual(data?.contextWindow?.totalOutputTokens, 100)
        XCTAssertEqual(data?.contextWindow?.usedPercentage, 25)
        XCTAssertEqual(data?.contextWindow?.remainingPercentage, 75)
        XCTAssertNil(data?.model)
    }

    func testCurrentContextPercentageMatchesBaselineRoundingAndClamping() {
        let scenarios: [ContextPercentageScenario] = [
            ContextPercentageScenario(window: 475_000, current: 236_085, used: 48, remaining: 52),
            ContextPercentageScenario(window: 11_999, current: 0, used: 100, remaining: 0),
            ContextPercentageScenario(window: 12_000, current: 12_000, used: 100, remaining: 0),
            ContextPercentageScenario(window: 100_000, current: 12_000, used: 0, remaining: 100),
            ContextPercentageScenario(window: 12_200, current: 12_095, used: 47, remaining: 53),
            ContextPercentageScenario(window: 12_200, current: 12_097, used: 48, remaining: 52),
            ContextPercentageScenario(window: 100_000, current: 130_000, used: 100, remaining: 0),
        ]

        for scenario in scenarios {
            let line = Data(
                #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{},"last_token_usage":{"total_tokens":\#(scenario.current)},"model_context_window":\#(scenario.window)}}}"#
                    .utf8)
            let data = CodexRolloutParser.parseLine(
                line,
                expectedCWD: "/repo",
                adapter: .current(version: "0.162.1"))

            XCTAssertEqual(data?.contextWindow?.usedPercentage, scenario.used)
            XCTAssertEqual(data?.contextWindow?.remainingPercentage, scenario.remaining)
        }
    }

    func testCurrentTokenCountLeavesAbsentFieldsUnavailable() {
        let line = Data(
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":250}}}}"#
                .utf8)
        let data = CodexRolloutParser.parseLine(
            line,
            expectedCWD: "/repo",
            adapter: .current(version: "0.162.1"))

        XCTAssertNil(data?.contextWindow?.usedPercentage)
        XCTAssertNil(data?.contextWindow?.totalInputTokens)
        XCTAssertNil(data?.contextWindow?.totalOutputTokens)
        XCTAssertNil(data?.rateLimits)
    }

    @MainActor
    func testCurrentModelChangesAbsentFieldsAndUnreadableTranscriptRecover() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }
        let rolloutURL = tempDir.appending(path: "current-rollout.jsonl")
        let initialLine = CodexCompatibilityFixtures.currentTokenCount
        let initialModelLine = CodexCompatibilityFixtures.currentTurnContext
        try (initialModelLine + "\n" + initialLine + "\n")
            .write(to: rolloutURL, atomically: true, encoding: .utf8)
        let hookRecordURL = tempDir.appending(path: "current-hook-record.json")
        try writeHookRecord(
            to: hookRecordURL,
            sessionID: "thread-abcdef1234567890",
            transcriptPath: rolloutURL.path)
        let provider = CodexStatusProvider(
            context: makeContext(
                processStartTime: Date(),
                hookRecordPath: hookRecordURL.path,
                adapter: .current(version: "0.162.1")),
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-current.sqlite")),
            startupRetryInterval: 0.02,
            startupTimeout: 0.5)
        let initial = expectation(description: "current model and token snapshot")
        let changedModel = expectation(description: "current model metadata change")
        let absentFields = expectation(description: "absent token fields clear the snapshot")
        let unreadable = expectation(description: "unreadable transcript clears rich facts")
        let recovered = expectation(description: "valid transcript restores rich facts")
        var fulfilledInitial = false
        var fulfilledChangedModel = false
        var fulfilledAbsentFields = false
        var fulfilledUnreadable = false
        var fulfilledRecovered = false
        var hasObservedInitialFacts = false
        provider.onUpdate = { data in
            if !fulfilledInitial, data.model?.id == "current-model", data.contextWindow?.usedPercentage == 25 {
                fulfilledInitial = true
                hasObservedInitialFacts = true
                initial.fulfill()
            }
            if !fulfilledChangedModel, data.model?.id == "updated-model" {
                fulfilledChangedModel = true
                changedModel.fulfill()
            }
            if !fulfilledAbsentFields, data.model?.id == "updated-model",
                data.contextWindow?.usedPercentage == nil,
                data.contextWindow?.totalInputTokens == nil,
                data.contextWindow?.totalOutputTokens == nil
            {
                fulfilledAbsentFields = true
                absentFields.fulfill()
            }
            if hasObservedInitialFacts, !fulfilledUnreadable,
                data.model == nil, data.contextWindow == nil
            {
                fulfilledUnreadable = true
                unreadable.fulfill()
            }
            if !fulfilledRecovered, data.model?.id == "recovered-model",
                data.contextWindow?.usedPercentage == 25
            {
                fulfilledRecovered = true
                recovered.fulfill()
            }
        }

        provider.start()
        wait(for: [initial], timeout: 2)
        let updateHandle = try FileHandle(forWritingTo: rolloutURL)
        try updateHandle.seekToEnd()
        try updateHandle.write(
            contentsOf: Data(
                #"{"type":"turn_context","payload":{"model":"updated-model"}}"#.appending("\n").utf8))
        try updateHandle.write(
            contentsOf: Data(
                #"{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":250}}}}"#
                    .appending("\n").utf8))
        try updateHandle.close()
        wait(for: [changedModel, absentFields], timeout: 2)

        try FileManager.default.removeItem(at: rolloutURL)
        wait(for: [unreadable], timeout: 2)
        try
            (#"{"type":"turn_context","payload":{"model":"recovered-model"}}"# + "\n"
            + initialLine + "\n")
            .write(to: rolloutURL, atomically: true, encoding: .utf8)
        wait(for: [recovered], timeout: 2)
        provider.stop()
        XCTAssertTrue(
            TracingService.shared.recordedEventsForTesting.contains {
                let isUnreadableRead =
                    $0.name == "statusline.codex.tailer_read"
                    && $0.attributes["result"] == "unreadable"
                let isWaitingForTranscript =
                    $0.name == "statusline.codex.tailer_attachment"
                    && $0.attributes["result"] == "waiting"
                let hasPaneContext = $0.attributes["pane.id"] != nil && $0.attributes["tab.id"] != nil
                return (isUnreadableRead || isWaitingForTranscript) && hasPaneContext
            }, "Missing pane-scoped unreadable-source diagnostic")
    }

    func testRolloutParserMapsCodex136SessionMetaPayload() throws {
        let line = Data(
            """
            {"type":"session_meta","payload":{"cwd":"/repo","cli_version":"codex-cli 0.136.0","model":"gpt-5.1-codex"}}
            """.utf8)

        let data = CodexRolloutParser.parseLine(line, expectedCWD: "/repo")

        XCTAssertEqual(data?.model?.id, "gpt-5.1-codex")
        XCTAssertEqual(data?.version, "0.136.0")
    }

    func testRolloutParserMapsCodex136NestedTokenCountShape() throws {
        let line = Data(CodexCompatibilityFixtures.legacyTokenCount.utf8)

        let data = CodexRolloutParser.parseLine(line, expectedCWD: "/repo")

        XCTAssertEqual(data?.contextWindow?.totalInputTokens, 20)
        XCTAssertEqual(data?.contextWindow?.totalOutputTokens, 5)
        XCTAssertEqual(data?.contextWindow?.usedPercentage, 31)
        XCTAssertEqual(data?.contextWindow?.remainingPercentage, 69)
        XCTAssertEqual(data?.rateLimits?.fiveHour?.usedPercentage, 12.5)
        XCTAssertEqual(data?.rateLimits?.sevenDay?.usedPercentage, 44)
        XCTAssertEqual(data?.rateLimits?.bucketID, "codex")
    }

    func testRolloutParserUsesLastTokenUsageForContextAndTotalUsageForTokenTotals() throws {
        let line = Data(
            """
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"output_tokens":100},"last_token_usage":{"total_tokens":12250},"model_context_window":13000}}}
            """.utf8)

        let data = CodexRolloutParser.parseLine(line, expectedCWD: "/repo")

        XCTAssertEqual(data?.contextWindow?.totalInputTokens, 900)
        XCTAssertEqual(data?.contextWindow?.totalOutputTokens, 100)
        XCTAssertEqual(data?.contextWindow?.usedPercentage, 25)
        XCTAssertEqual(data?.contextWindow?.remainingPercentage, 75)
    }

    func testRolloutParserClampsContextPercentageAtOneHundred() throws {
        let line = Data(
            """
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"output_tokens":300},"last_token_usage":{"total_tokens":1500},"model_context_window":1000}}}
            """.utf8)

        let data = CodexRolloutParser.parseLine(line, expectedCWD: "/repo")

        XCTAssertEqual(data?.contextWindow?.usedPercentage, 100)
        XCTAssertEqual(data?.contextWindow?.remainingPercentage, 0)
        XCTAssertEqual(data?.contextWindow?.totalInputTokens, 1200)
        XCTAssertEqual(data?.contextWindow?.totalOutputTokens, 300)
    }

    func testRolloutParserIgnoresContentRecords() {
        let line = Data(#"{"type":"event_msg","payload":{"type":"agent_message","message":"secret"}}"#.utf8)
        XCTAssertNil(CodexRolloutParser.parseLine(line, expectedCWD: "/repo"))
    }

    func testVersionAdapterRejectsUnknownCodexVersions() {
        XCTAssertTrue(CodexVersionAdapter.supports("codex 0.136.2"))
        XCTAssertEqual(CodexVersionAdapter.normalize("codex-cli 0.136.0"), "0.136.0")
        XCTAssertFalse(CodexVersionAdapter.supports("codex 0.137.0"))
        XCTAssertFalse(CodexVersionAdapter.supports(nil))
    }

    @MainActor
    func testTailerStartupUsesLatestTwoHundredCompleteLines() throws {
        let rolloutURL = tempDir.appending(path: "rollout.jsonl")
        let lines =
            (1...250).map {
                codexTokenLine(model: "model-\($0)", input: $0, output: 1, contextTokens: $0, window: 1000)
            }.joined(separator: "\n") + "\n"
        try lines.write(to: rolloutURL, atomically: true, encoding: .utf8)

        let tailer = CodexRolloutTailer(rolloutPath: rolloutURL.path, expectedCWD: tempDir.path)
        var models: [String] = []
        var traces: [(String, [String: String])] = []
        tailer.onUpdate = { data in
            if let model = data.model?.id {
                models.append(model)
            }
        }
        tailer.onTrace = { name, attributes in
            traces.append((name, attributes))
        }

        tailer.start()
        tailer.stop()

        XCTAssertEqual(models.count, 200)
        XCTAssertEqual(models.first, "model-51")
        XCTAssertEqual(models.last, "model-250")
        XCTAssertTrue(
            traces.contains {
                $0.0 == "statusline.codex.tailer_read"
                    && $0.1["catch_up"] == "true"
                    && $0.1["line_count"] == "200"
            })
    }

    @MainActor
    func testTailerBuffersPartialJsonlUntilNewlineArrives() throws {
        let rolloutURL = tempDir.appending(path: "rollout.jsonl")
        let partial =
            #"{"type":"event_msg","payload":{"type":"token_count","model":"partial","total_token_usage":{"input_tokens":10,"output_tokens":2},"last_token_usage":{"total_tokens":12006},"model_context_window":12100}}"#
        try partial.write(to: rolloutURL, atomically: true, encoding: .utf8)

        let tailer = CodexRolloutTailer(rolloutPath: rolloutURL.path, expectedCWD: tempDir.path)
        let expectation = XCTestExpectation(description: "tailer parses partial line after newline")
        var observed: StatusLineData?
        tailer.onUpdate = { data in
            observed = data
            expectation.fulfill()
        }

        tailer.start()
        XCTAssertNil(observed)
        let handle = try FileHandle(forWritingTo: rolloutURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
        wait(for: [expectation], timeout: 2)
        tailer.stop()

        XCTAssertEqual(observed?.model?.id, "partial")
        XCTAssertEqual(observed?.contextWindow?.usedPercentage, 6)
    }

    @MainActor
    func testTailerFollowsAtomicReplacementAndLaterAppend() throws {
        let rolloutURL = tempDir.appending(path: "replaceable-rollout.jsonl")
        try (codexTokenLine(model: "initial", input: 1, output: 1, contextTokens: 1, window: 100) + "\n")
            .write(to: rolloutURL, atomically: true, encoding: .utf8)
        let replacement = expectation(description: "replacement parsed")
        let appended = expectation(description: "append after replacement parsed")
        let tailer = CodexRolloutTailer(rolloutPath: rolloutURL.path, expectedCWD: tempDir.path)
        tailer.onUpdate = { data in
            if data.model?.id == "replacement" {
                replacement.fulfill()
            }
            if data.model?.id == "appended" {
                appended.fulfill()
            }
        }
        tailer.start()

        try (codexTokenLine(model: "replacement", input: 2, output: 1, contextTokens: 2, window: 100) + "\n")
            .write(to: rolloutURL, atomically: true, encoding: .utf8)
        wait(for: [replacement], timeout: 2)

        let handle = try FileHandle(forWritingTo: rolloutURL)
        try handle.seekToEnd()
        try handle.write(
            contentsOf: Data(
                (codexTokenLine(model: "appended", input: 3, output: 1, contextTokens: 3, window: 100)
                    + "\n").utf8))
        try handle.close()
        wait(for: [appended], timeout: 2)
        tailer.stop()
    }

    @MainActor
    func testTailerReadsFileThatAppearsAfterStartAndTracesRecovery() throws {
        let rolloutURL = tempDir.appending(path: "created-later-rollout.jsonl")
        let available = expectation(description: "newly available rollout parsed")
        var traces: [(String, [String: String])] = []
        let tailer = CodexRolloutTailer(rolloutPath: rolloutURL.path, expectedCWD: tempDir.path)
        tailer.onUpdate = { data in
            if data.model?.id == "available" {
                available.fulfill()
            }
        }
        tailer.onTrace = { name, attributes in
            traces.append((name, attributes))
        }
        tailer.start()

        try (codexTokenLine(model: "available", input: 4, output: 1, contextTokens: 4, window: 100) + "\n")
            .write(to: rolloutURL, atomically: true, encoding: .utf8)
        wait(for: [available], timeout: 2)
        tailer.stop()

        XCTAssertTrue(
            traces.contains {
                $0.0 == "statusline.codex.tailer_attachment"
                    && $0.1["result"] == "waiting"
            })
        XCTAssertTrue(
            traces.contains {
                $0.0 == "statusline.codex.tailer_attachment"
                    && $0.1["result"] == "recovered"
            })
        XCTAssertTrue(
            traces.contains {
                $0.0 == "statusline.codex.tailer_stopped"
                    && $0.1["result"] == "stopped"
            })
    }

    func testCapabilityFilteringSupportsCodexTokensButNotCost() {
        let cost = StatusLineItem(id: "cost", label: "Cost", sfSymbol: "dollarsign.circle")
        let input = StatusLineItem(id: "inputTokens", label: "Input Tokens", sfSymbol: "arrow.down.circle")
        let context = StatusLineItem(id: "context", label: "Context Used", sfSymbol: "gauge.with.needle")

        XCTAssertFalse(cost.supportedBy(.codex))
        XCTAssertTrue(input.supportedBy(.codex))
        XCTAssertTrue(context.supportedBy(.codex))
    }

    @MainActor
    func testProviderMergesBaselineAndCodexRichFactsAndTracesSelection() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        try run(["git", "init"], in: tempDir)
        try "one\n".write(to: tempDir.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
        try run(["git", "add", "tracked.txt"], in: tempDir)
        try run(
            ["git", "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "init"], in: tempDir)
        try "one\ntwo\n".write(to: tempDir.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)

        let rolloutURL = tempDir.appending(path: "rollout.jsonl")
        try """
        {"type":"session_meta","payload":{"cwd":"\(tempDir.path)","cli_version":"0.136.0","model":"gpt-5.1-codex"}}
            {"type":"event_msg","payload":{"type":"token_count","info":{"model":"gpt-5.1-codex","total_token_usage":{"input_tokens":320,"output_tokens":80},"last_token_usage":{"total_tokens":12400},"model_context_window":14000},"rate_limits":{"primary":{"window_minutes":300,"used_percent":12.5,"resets_at":2000000000},"secondary":{"window_minutes":10080,"used_percent":44,"resets_at":2000003600}}}}
        """
        .appending("\n")
        .write(to: rolloutURL, atomically: true, encoding: .utf8)

        let dbURL = tempDir.appending(path: "state_5.sqlite")
        try executeSQL(
            """
            CREATE TABLE threads (
              id TEXT,
              cwd TEXT,
              rollout_path TEXT,
              model TEXT,
              cli_version TEXT,
              tokens_used INTEGER,
              git_branch TEXT,
              created_at_ms INTEGER,
              updated_at_ms INTEGER
            );
            INSERT INTO threads VALUES ('thread-abcdef1234567890', '\(tempDir.path)', '\(rolloutURL.path)', 'gpt-5.1-codex', '0.136.0', 320, 'main', 1000, 1000);
            """,
            at: dbURL
        )

        let hookRecordURL = tempDir.appending(path: "hook-record.json")
        try writeHookRecord(to: hookRecordURL, sessionID: "thread-abcdef1234567890", transcriptPath: rolloutURL.path)
        let provider = CodexStatusProvider(
            context: StatusProviderContext(
                paneID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                paneName: "codex-pane",
                tabID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                tabName: "repo",
                workingDirectory: tempDir.path,
                harness: .codex,
                processStartTime: Date(timeIntervalSince1970: 1),
                launchArgs: [],
                environment: [:],
                detectedHarnessVersion: "0.136.0",
                codexHookRecordPath: hookRecordURL.path,
                opencodePort: nil,
                opencodeSessionID: nil
            ),
            stateStore: CodexStateStore(databaseURL: dbURL)
        )
        let expectation = XCTestExpectation(description: "provider emits merged Codex status")
        var observed: StatusLineData?
        provider.onUpdate = { (data: StatusLineData) in
            if data.model?.id == "gpt-5.1-codex",
                data.contextWindow?.totalInputTokens == 320,
                data.rateLimits?.fiveHour?.usedPercentage == 12.5,
                data.worktree?.name == self.tempDir.lastPathComponent
            {
                observed = data
                expectation.fulfill()
            }
        }

        provider.start()
        wait(for: [expectation], timeout: 5)
        provider.stop()

        XCTAssertEqual(observed?.contextWindow?.totalOutputTokens, 80)
        XCTAssertEqual(observed?.contextWindow?.usedPercentage, 20)
        XCTAssertEqual(observed?.contextWindow?.remainingPercentage, 80)
        XCTAssertEqual(observed?.rateLimits?.sevenDay?.usedPercentage, 44)
        XCTAssertEqual(observed?.version, "0.136.0")
        XCTAssertEqual(observed?.worktree?.name, tempDir.lastPathComponent)
        XCTAssertNotNil(observed?.cost?.totalDurationMs)
        XCTAssertEqual(observed?.cost?.totalLinesAdded, 1)
        XCTAssertNil(observed?.cost?.totalCostUsd)

        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(events.contains { $0.name == "statusline.codex.binding.changed" })
        XCTAssertTrue(events.contains { $0.name == "statusline.codex.sqlite_enrichment" })
        XCTAssertTrue(events.contains { $0.name == "statusline.codex.tailer_started" })
        XCTAssertTrue(events.contains { $0.name == "statusline.codex.tailer_read" })
        XCTAssertTrue(
            events.contains {
                $0.name == "statusline.codex.parsed_update"
                    && $0.attributes["has_model"] == "true"
                    && $0.attributes["has_tokens"] == "true"
                    && $0.attributes["has_context"] == "true"
                    && $0.attributes["has_rate_limits"] == "true"
            })
    }

    @MainActor
    func testProviderStartupRetrySucceedsWhenSQLiteRowAppearsAfterStart() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let rolloutURL = tempDir.appending(path: "rollout.jsonl")
        try codexTokenLine(model: "late-row", input: 30, output: 5, contextTokens: 10, window: 100)
            .write(to: rolloutURL, atomically: true, encoding: .utf8)
        let dbURL = tempDir.appending(path: "state_5.sqlite")
        let hookRecordURL = tempDir.appending(path: "late-hook-record.json")
        try writeHookRecord(
            to: hookRecordURL, sessionID: "thread-abcdef1234567890", transcriptPath: nil, model: "late-row")
        let provider = CodexStatusProvider(
            context: makeContext(processStartTime: Date(), hookRecordPath: hookRecordURL.path),
            stateStore: CodexStateStore(databaseURL: dbURL),
            startupRetryInterval: 0.05,
            startupTimeout: 1
        )
        let expectation = XCTestExpectation(description: "provider retries until SQLite row exists")
        provider.onUpdate = { data in
            if data.model?.id == "late-row", data.contextWindow?.usedPercentage == 10 {
                expectation.fulfill()
            }
        }

        provider.start()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.12) {
            try? self.createThreadDatabase(
                at: dbURL,
                rolloutPath: rolloutURL.path,
                model: "late-row",
                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
            )
        }
        wait(for: [expectation], timeout: 2)
        provider.stop()

        let stateReads = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.codex.sqlite_enrichment"
        }
        XCTAssertGreaterThanOrEqual(stateReads.count, 1)
        XCTAssertTrue(stateReads.contains { $0.attributes["retry_attempt"] != nil })
    }

    @MainActor
    func testProviderFollowsForegroundNewAndResumeBindingsAndDelayedTranscript() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let queueURL = tempDir.appending(path: "foreground-hooks.jsonl")
        let firstTranscript = tempDir.appending(path: "first-rollout.jsonl")
        let resumedTranscript = tempDir.appending(path: "resumed-rollout.jsonl")
        try codexTokenLine(model: "first-model", input: 40, output: 10, contextTokens: 20, window: 100)
            .appending("\n")
            .write(to: firstTranscript, atomically: true, encoding: .utf8)
        let paneID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let tabID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let generation = "generation-foreground"
        let provider = CodexStatusProvider(
            context: makeContext(
                processStartTime: Date(), queuePath: queueURL.path, launchGeneration: generation),
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-state.sqlite")),
            startupRetryInterval: 0.05,
            startupTimeout: 0.3)
        let firstBound = expectation(description: "first foreground conversation binds")
        let firstFacts = expectation(description: "first transcript facts arrive")
        let resumedBound = expectation(description: "resumed foreground conversation binds")
        let resumedTranscriptParsed = expectation(description: "delayed resumed transcript is parsed")
        var boundIDs: [String] = []
        var boundTranscriptPaths: [String?] = []
        var awaitingClearedFactsFor: String?
        var sawClearedFacts = false
        var sawStalePriorSessionFacts = false
        provider.onSessionBound = { id, transcriptPath in
            boundIDs.append(id)
            boundTranscriptPaths.append(transcriptPath)
            if id == "session-first" { firstBound.fulfill() }
            if id == "session-resumed" {
                awaitingClearedFactsFor = id
                resumedBound.fulfill()
            }
        }
        provider.onUpdate = { data in
            if data.model?.id == "first-model", data.contextWindow?.usedPercentage == 20 {
                firstFacts.fulfill()
            }
            if awaitingClearedFactsFor == "session-resumed", data.contextWindow == nil {
                sawClearedFacts = true
            }
            if awaitingClearedFactsFor == "session-resumed", data.contextWindow?.usedPercentage == 90 {
                sawStalePriorSessionFacts = true
            }
            if data.model?.id == "resumed-model", data.contextWindow?.usedPercentage == 30 {
                resumedTranscriptParsed.fulfill()
            }
        }

        try appendQueueRecord(
            to: queueURL,
            paneID: paneID,
            tabID: tabID,
            generation: generation,
            sessionID: "session-first",
            transcriptPath: firstTranscript.path)
        provider.start()
        wait(for: [firstBound], timeout: 2)
        wait(for: [firstFacts], timeout: 2)

        try appendQueueRecord(
            to: queueURL,
            paneID: paneID,
            tabID: tabID,
            generation: generation,
            sessionID: "session-resumed",
            transcriptPath: resumedTranscript.path,
            hookEventName: "UserPromptSubmit")
        wait(for: [resumedBound], timeout: 2)
        XCTAssertTrue(sawClearedFacts)

        let priorTranscriptContent = try String(contentsOf: firstTranscript, encoding: .utf8)
        try
            (priorTranscriptContent
            + codexTokenLine(model: "first-model", input: 100, output: 50, contextTokens: 90, window: 100)
            + "\n")
            .write(to: firstTranscript, atomically: true, encoding: .utf8)
        try appendQueueRecord(
            to: queueURL,
            paneID: paneID,
            tabID: tabID,
            generation: generation,
            sessionID: "session-resumed",
            transcriptPath: resumedTranscript.path,
            hookEventName: "UserPromptSubmit")
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertEqual(boundIDs, ["session-first", "session-resumed"])
        XCTAssertEqual(boundTranscriptPaths, [firstTranscript.path, resumedTranscript.path])
        XCTAssertFalse(sawStalePriorSessionFacts)

        try codexTokenLine(model: "resumed-model", input: 60, output: 15, contextTokens: 30, window: 100)
            .appending("\n")
            .write(to: resumedTranscript, atomically: true, encoding: .utf8)
        wait(for: [resumedTranscriptParsed], timeout: 2)
        provider.stop()

        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(events.contains { $0.name == "statusline.codex.binding.facts_cleared" })
        XCTAssertTrue(events.contains { $0.name == "statusline.codex.binding.callback" })
        XCTAssertTrue(events.contains { $0.name == "statusline.codex.tailer_detached" })
        XCTAssertTrue(
            events.contains {
                $0.name == "statusline.codex.binding.changed"
                    && $0.attributes["pane.id"] == paneID.uuidString
                    && $0.attributes["tab.id"] == tabID.uuidString
            })
    }

    @MainActor
    func testProvidersOnDistinctCheckoutsRejectEachOthersForegroundBindings() throws {
        let paneA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let paneB = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let tabA = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let tabB = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let generationA = "generation-a"
        let generationB = "generation-b"
        let queueA = tempDir.appending(path: "pane-a-hooks.jsonl")
        let queueB = tempDir.appending(path: "pane-b-hooks.jsonl")
        let checkoutA = tempDir.appending(path: ".agent-session-manager/worktrees/pane-a", directoryHint: .isDirectory)
        let checkoutB = tempDir.appending(path: ".agent-session-manager/worktrees/pane-b", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: checkoutA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkoutB, withIntermediateDirectories: true)
        let providerA = CodexStatusProvider(
            context: makeContext(
                processStartTime: Date(), queuePath: queueA.path, launchGeneration: generationA,
                workingDirectory: checkoutA.path, paneID: paneA, tabID: tabA),
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-a.sqlite")),
            startupRetryInterval: 0.05,
            startupTimeout: 0.2)
        let providerB = CodexStatusProvider(
            context: makeContext(
                processStartTime: Date(), queuePath: queueB.path, launchGeneration: generationB,
                workingDirectory: checkoutB.path, paneID: paneB, tabID: tabB),
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-b.sqlite")),
            startupRetryInterval: 0.05,
            startupTimeout: 0.2)
        let boundA = expectation(description: "pane A binds its session")
        let boundB = expectation(description: "pane B binds its session")
        var idsA: [String] = []
        var idsB: [String] = []
        providerA.onSessionBound = { id, _ in
            idsA.append(id)
            boundA.fulfill()
        }
        providerB.onSessionBound = { id, _ in
            idsB.append(id)
            boundB.fulfill()
        }

        try appendQueueRecord(
            to: queueA, paneID: paneB, tabID: tabB, generation: generationB, sessionID: "session-b")
        try appendQueueRecord(
            to: queueA, paneID: paneA, tabID: tabA, generation: generationA, sessionID: "session-a")
        try appendQueueRecord(
            to: queueB, paneID: paneA, tabID: tabA, generation: generationA, sessionID: "session-a")
        try appendQueueRecord(
            to: queueB, paneID: paneB, tabID: tabB, generation: generationB, sessionID: "session-b")
        providerA.start()
        providerB.start()
        wait(for: [boundA, boundB], timeout: 2)
        providerA.stop()
        providerB.stop()

        XCTAssertEqual(idsA, ["session-a"])
        XCTAssertEqual(idsB, ["session-b"])
    }

    @MainActor
    func testProviderIgnoresCallbacksFromPreviousAndStoppedTailerGenerations() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let queueURL = tempDir.appending(path: "tailer-generation-queue.jsonl")
        let firstTranscript = tempDir.appending(path: "tailer-generation-first.jsonl")
        let secondTranscript = tempDir.appending(path: "tailer-generation-second.jsonl")
        try codexTokenLine(model: "first-model", input: 10, output: 1, contextTokens: 11, window: 100)
            .write(to: firstTranscript, atomically: true, encoding: .utf8)
        try codexTokenLine(model: "second-model", input: 20, output: 2, contextTokens: 22, window: 100)
            .write(to: secondTranscript, atomically: true, encoding: .utf8)
        let context = makeContext(
            processStartTime: Date(), queuePath: queueURL.path, launchGeneration: "tailer-generation",
            adapter: .current(version: "0.162.1"))
        let provider = CodexStatusProvider(
            context: context,
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "tailer-generation-absent.sqlite")),
            startupRetryInterval: 0.05,
            startupTimeout: 0.5)
        var snapshots: [StatusLineData] = []
        let firstUpdate = expectation(description: "first tailer emits its metrics")
        let secondUpdate = expectation(description: "rebound tailer emits its metrics")
        var didObserveFirstUpdate = false
        var didObserveSecondUpdate = false
        provider.onUpdate = { data in
            snapshots.append(data)
            if data.model?.id == "first-model", !didObserveFirstUpdate {
                didObserveFirstUpdate = true
                firstUpdate.fulfill()
            }
            if data.model?.id == "second-model", !didObserveSecondUpdate {
                didObserveSecondUpdate = true
                secondUpdate.fulfill()
            }
        }
        try appendQueueRecord(
            to: queueURL,
            paneID: context.paneID,
            tabID: context.tabID,
            generation: "tailer-generation",
            sessionID: "first-session",
            transcriptPath: firstTranscript.path,
            model: "first-hook-model",
            hookEventName: "SessionStart")

        provider.start()
        wait(for: [firstUpdate], timeout: 2)
        let previousTailer = try XCTUnwrap(provider.tailer)
        let previousSnapshot = try XCTUnwrap(snapshots.last)
        try appendQueueRecord(
            to: queueURL,
            paneID: context.paneID,
            tabID: context.tabID,
            generation: "tailer-generation",
            sessionID: "second-session",
            transcriptPath: secondTranscript.path,
            model: "second-hook-model",
            hookEventName: "UserPromptSubmit")
        wait(for: [secondUpdate], timeout: 2)
        let activeTailer = try XCTUnwrap(provider.tailer)
        let secondSnapshot = try XCTUnwrap(snapshots.last)
        let snapshotCountAfterRebind = snapshots.count

        previousTailer.onUnavailable?()
        previousTailer.onUpdate?(previousSnapshot)

        XCTAssertEqual(snapshots.count, snapshotCountAfterRebind)
        XCTAssertEqual(snapshots.last?.model?.id, "second-model")
        XCTAssertEqual(snapshots.last?.contextWindow?.totalInputTokens, 20)

        provider.stop()
        let snapshotCountAfterStop = snapshots.count
        activeTailer.onUnavailable?()
        activeTailer.onUpdate?(secondSnapshot)

        XCTAssertEqual(snapshots.count, snapshotCountAfterStop)
        XCTAssertEqual(snapshots.last?.model?.id, "second-model")
        let ignoredEvents = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.codex.tailer_update_ignored"
        }
        XCTAssertEqual(ignoredEvents.count, 4)
        XCTAssertTrue(
            ignoredEvents.allSatisfy {
                $0.attributes["result"] == "stale_generation"
                    && $0.attributes["pane.id"] == context.paneID.uuidString
                    && $0.attributes["pane.name"] == context.paneName
                    && $0.attributes["tab.id"] == context.tabID.uuidString
                    && $0.attributes["tab.name"] == context.tabName
            })
    }

    @MainActor
    func testProviderStartupRetrySucceedsWhenHookRecordAppearsAfterStart() throws {
        let rolloutURL = tempDir.appending(path: "rollout.jsonl")
        try codexTokenLine(model: "late-hook", input: 9, output: 3, contextTokens: 6, window: 100)
            .write(to: rolloutURL, atomically: true, encoding: .utf8)
        let hookRecordURL = tempDir.appending(path: "late-hook-record.json")
        let provider = CodexStatusProvider(
            context: makeContext(processStartTime: Date(), hookRecordPath: hookRecordURL.path),
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing.sqlite")),
            startupRetryInterval: 0.05,
            startupTimeout: 1
        )
        let expectation = XCTestExpectation(description: "provider retries until hook record exists")
        provider.onUpdate = { data in
            if data.model?.id == "late-hook", data.contextWindow?.usedPercentage == 6 {
                expectation.fulfill()
            }
        }

        provider.start()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.12) {
            try? self.writeHookRecord(
                to: hookRecordURL,
                sessionID: "thread-abcdef1234567890",
                transcriptPath: rolloutURL.path,
                model: "late-hook")
        }
        wait(for: [expectation], timeout: 2)
        provider.stop()
    }

    @MainActor
    func testProviderStartupRetrySucceedsWhenRolloutFileAppearsAfterSQLiteRow() throws {
        let rolloutURL = tempDir.appending(path: "late-rollout.jsonl")
        let dbURL = tempDir.appending(path: "state_5.sqlite")
        let hookRecordURL = tempDir.appending(path: "late-rollout-hook-record.json")
        try writeHookRecord(
            to: hookRecordURL,
            sessionID: "thread-abcdef1234567890",
            transcriptPath: rolloutURL.path,
            model: "late-rollout")
        try createThreadDatabase(
            at: dbURL,
            rolloutPath: rolloutURL.path,
            model: "late-rollout",
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        let provider = CodexStatusProvider(
            context: makeContext(processStartTime: Date(), hookRecordPath: hookRecordURL.path),
            stateStore: CodexStateStore(databaseURL: dbURL),
            startupRetryInterval: 0.05,
            startupTimeout: 1
        )
        let expectation = XCTestExpectation(description: "provider retries until rollout exists")
        provider.onUpdate = { data in
            if data.model?.id == "late-rollout", data.contextWindow?.usedPercentage == 15 {
                expectation.fulfill()
            }
        }

        provider.start()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.12) {
            try? self.codexTokenLine(model: "late-rollout", input: 20, output: 4, contextTokens: 15, window: 100)
                .write(to: rolloutURL, atomically: true, encoding: .utf8)
        }
        wait(for: [expectation], timeout: 2)
        provider.stop()
    }

    @MainActor
    func testProviderIgnoresStaleRowsWhileWaitingForFreshThread() throws {
        let staleRolloutURL = tempDir.appending(path: "stale.jsonl")
        let freshRolloutURL = tempDir.appending(path: "fresh.jsonl")
        try codexTokenLine(model: "stale-model", input: 1, output: 1, contextTokens: 1, window: 100)
            .write(to: staleRolloutURL, atomically: true, encoding: .utf8)
        let dbURL = tempDir.appending(path: "state_5.sqlite")
        try executeSQL(
            """
            CREATE TABLE threads (
              id TEXT,
              cwd TEXT,
              rollout_path TEXT,
              model TEXT,
              cli_version TEXT,
              tokens_used INTEGER,
              git_branch TEXT,
              created_at_ms INTEGER,
              updated_at_ms INTEGER,
              is_archived INTEGER
            );
            INSERT INTO threads VALUES ('stale-thread', '\(tempDir.path)', '\(staleRolloutURL.path)', 'stale-model', '0.136.0', 1, 'main', 1000, 1000, 0);
            """,
            at: dbURL
        )
        try writeHookRecord(
            to: tempDir.appending(path: "fresh-hook-record.json"),
            sessionID: "fresh-thread",
            transcriptPath: freshRolloutURL.path,
            model: "fresh-model")

        let provider = CodexStatusProvider(
            context: makeContext(
                processStartTime: Date(timeIntervalSince1970: 100),
                hookRecordPath: tempDir.appending(path: "fresh-hook-record.json").path),
            stateStore: CodexStateStore(databaseURL: dbURL),
            startupRetryInterval: 0.05,
            startupTimeout: 1
        )
        let expectation = XCTestExpectation(description: "provider waits for fresh thread")
        var observedModels: [String] = []
        provider.onUpdate = { data in
            if let model = data.model?.id {
                observedModels.append(model)
            }
            if data.model?.id == "fresh-model", data.contextWindow?.usedPercentage == 22 {
                expectation.fulfill()
            }
        }

        provider.start()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.12) {
            try? self.codexTokenLine(model: "fresh-model", input: 12, output: 3, contextTokens: 22, window: 100)
                .write(to: freshRolloutURL, atomically: true, encoding: .utf8)
            let nowMs = Int64(Date(timeIntervalSince1970: 100).timeIntervalSince1970 * 1000)
            try? self.executeSQL(
                """
                INSERT INTO threads VALUES ('fresh-thread', '\(self.tempDir.path)', '\(freshRolloutURL.path)', 'fresh-model', '0.136.0', 12, 'main', \(nowMs), \(nowMs), 0);
                """,
                at: dbURL
            )
        }
        wait(for: [expectation], timeout: 2)
        provider.stop()

        XCTAssertFalse(observedModels.contains("stale-model"))
    }

    @MainActor
    func testProviderDoesNotDuplicateGenericProviderSpansAndCodexTracesIncludePaneContext() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let rolloutURL = tempDir.appending(path: "rollout.jsonl")
        let tokenLine = codexTokenLine(model: "trace-model", input: 5, output: 2, contextTokens: 7, window: 100)
        XCTAssertEqual(
            CodexRolloutParser.parseLine(Data(tokenLine.utf8), expectedCWD: tempDir.path)?.model?.id,
            "trace-model")
        try tokenLine
            .write(to: rolloutURL, atomically: true, encoding: .utf8)
        let dbURL = tempDir.appending(path: "state_5.sqlite")
        let hookRecordURL = tempDir.appending(path: "trace-hook-record.json")
        try writeHookRecord(to: hookRecordURL, sessionID: "thread-abcdef1234567890", transcriptPath: rolloutURL.path)
        try createThreadDatabase(
            at: dbURL,
            rolloutPath: rolloutURL.path,
            model: "trace-model",
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        let provider = CodexStatusProvider(
            context: makeContext(processStartTime: Date(), hookRecordPath: hookRecordURL.path),
            stateStore: CodexStateStore(databaseURL: dbURL),
            startupRetryInterval: 0.01,
            startupTimeout: 0.5
        )
        let expectation = XCTestExpectation(description: "provider emits trace-model update")
        var observedCodexUpdates: [(String?, Int?)] = []
        provider.onUpdate = { data in
            observedCodexUpdates.append((data.model?.id, data.contextWindow?.usedPercentage))
            if data.model?.id == "trace-model", data.contextWindow?.usedPercentage == 7 {
                expectation.fulfill()
            }
        }

        provider.start()
        wait(for: [expectation], timeout: 2)
        provider.stop()
        XCTAssertTrue(
            observedCodexUpdates.contains { $0.0 == "trace-model" && $0.1 == 7 },
            "Observed Codex snapshots: \(observedCodexUpdates)")

        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertFalse(events.contains { $0.name == "statusline.provider.started" })
        XCTAssertFalse(events.contains { $0.name == "statusline.provider.stopped" })
        XCTAssertFalse(events.contains { $0.name == "statusline.provider.update_applied" })
        let codexEvents = events.filter { $0.name.hasPrefix("statusline.codex.") }
        XCTAssertFalse(codexEvents.isEmpty)
        XCTAssertTrue(
            codexEvents.contains { $0.name == "statusline.codex.tailer_started" },
            codexEvents.map(\.name).joined(separator: ","))
        XCTAssertTrue(
            codexEvents.contains { $0.name == "statusline.codex.parsed_update" },
            codexEvents.map(\.name).joined(separator: ","))
        XCTAssertTrue(
            codexEvents.allSatisfy {
                $0.attributes["pane.name"] == "codex-pane"
                    && $0.attributes["tab.name"] == "repo"
                    && $0.attributes["pane.id"] == "11111111-1111-1111-1111-111111111111"
                    && $0.attributes["tab.id"] == "22222222-2222-2222-2222-222222222222"
            },
            "Captured Codex contexts: \(codexEvents.prefix(20).map { "\($0.name): \($0.attributes["pane.name"] ?? "missing") / \($0.attributes["pane.id"] ?? "missing") / \($0.attributes["tab.name"] ?? "missing") / \($0.attributes["tab.id"] ?? "missing")" })"
        )
    }

    func testBuildCodexCommandRegistersOnlyAdapterSupportedHooks() {
        let current = Tab.buildCodexCommand(
            hookScriptPath: "/tmp/hook path.py",
            adapter: .current(version: "0.162.1"),
            extraArgs: ["--model", "gpt-5.1"])
        let legacy = Tab.buildCodexCommand(
            hookScriptPath: "/tmp/hook path.py",
            adapter: .legacy(version: "0.136.0"),
            extraArgs: [])
        let unknown = Tab.buildCodexCommand(
            hookScriptPath: "/tmp/hook path.py",
            adapter: .unsupported(version: "0.163.0"),
            extraArgs: ["--model", "custom"])

        XCTAssertTrue(current.contains("codex"))
        XCTAssertFalse(current.contains("--dangerously-bypass-hook-trust"))
        XCTAssertTrue(current.contains("features.hooks=true"))
        XCTAssertTrue(current.contains(where: { $0.hasPrefix("hooks.SessionStart=") }))
        XCTAssertTrue(current.contains(where: { $0.hasPrefix("hooks.UserPromptSubmit=") }))
        XCTAssertTrue(current.contains(where: { $0.hasPrefix("hooks.Stop=") }))
        XCTAssertTrue(current.contains(where: { $0.hasPrefix("hooks.Interrupt=") }))
        XCTAssertFalse(current.contains(where: { $0.hasPrefix("hooks.StopFailure=") }))
        XCTAssertTrue(current.contains(where: { $0.contains("/tmp/hook path.py") }))
        XCTAssertTrue(current.contains("--model"))
        XCTAssertTrue(current.contains("gpt-5.1"))
        XCTAssertFalse(legacy.contains(where: { $0.hasPrefix("hooks.Interrupt=") }))
        XCTAssertEqual(unknown, ["codex", "--model", "custom"])
    }
}

extension CodexStatusProviderTests {
    @MainActor
    func testContinuationDiagnosticsMatchRequestedAndBoundSessionIdentity() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let codexHome = tempDir.appending(path: "codex-home", directoryHint: .isDirectory)
        let bin = tempDir.appending(path: "bin", directoryHint: .isDirectory)
        let transcript = tempDir.appending(path: "requested-session.jsonl")
        let database = codexHome.appending(path: "state_5.sqlite")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try Data().write(to: transcript)
        try createThreadDatabase(
            at: database,
            rolloutPath: transcript.path,
            model: "requested-model",
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000))
        let codex = bin.appending(path: "codex")
        try "#!/bin/sh\nprintf '%s\\n' 'codex-cli 0.162.1'\n"
            .write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codex.path)

        let settings = AppSettings()
        settings.preferredShell = "/bin/sh"
        settings.agentControlInjectionPolicy = .never
        let tab = Tab(name: "repo", directory: tempDir)
        let pane = Pane(name: "codex-pane", tab: tab, harness: .codex, appSettings: settings)
        let requestedSessionID = "thread-abcdef1234567890"
        pane.codexSessionID = requestedSessionID
        pane.codexTranscriptPath = transcript.path
        pane.extraEnvVars = [
            "CODEX_HOME": codexHome.path,
            "PATH": "\(bin.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")",
        ]
        let originalController = TerminalController()
        originalController.pendingCommandArgs = ["codex"]
        pane.installTerminalController(originalController)
        tab.panes.append(pane)
        defer {
            pane.terminalController?.terminate()
            pane.removeStatusLineMonitor()
        }

        tab.refreshPane(pane, appSettings: settings)

        let monitor = try XCTUnwrap(pane.statusLineMonitor)
        XCTAssertEqual(monitor.codexAdapter, .current(version: "0.162.1"))
        let boundSessionID = "thread-9876543210fedcba"
        let bound = expectation(description: "provider records the bound exact session")
        let previousCallback = monitor.onCodexSessionBound
        monitor.onCodexSessionBound = { id, path in
            previousCallback?(id, path)
            bound.fulfill()
        }
        try appendQueueRecord(
            to: URL(filePath: monitor.codexHookQueueFilePath),
            paneID: pane.id,
            tabID: tab.id,
            generation: monitor.codexLaunchGeneration,
            sessionID: boundSessionID,
            transcriptPath: transcript.path)
        wait(for: [bound], timeout: 2)

        let events = TracingService.shared.recordedEventsForTesting
        let requested = try XCTUnwrap(
            events.first { $0.name == "statusline.codex.continuation.preflight" })
        let boundSession = try XCTUnwrap(
            events.first { $0.name == "statusline.codex.binding.changed" })
        XCTAssertEqual(requested.attributes["requested_session_id_prefix"], String(requestedSessionID.prefix(12)))
        XCTAssertEqual(requested.attributes["result"], "available")
        XCTAssertEqual(boundSession.attributes["session_id_prefix"], String(boundSessionID.prefix(12)))
        XCTAssertNotEqual(
            requested.attributes["requested_session_id_prefix"],
            boundSession.attributes["session_id_prefix"])
        XCTAssertFalse(
            events.contains { event in
                event.attributes.values.contains { $0.contains(requestedSessionID) || $0.contains(boundSessionID) }
            })
    }

    @MainActor
    func testProviderBindsWhenHookRecordAppearsAfterStartupTimeout() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let rolloutURL = tempDir.appending(path: "late-timeout-rollout.jsonl")
        try codexTokenLine(model: "late-timeout", input: 15, output: 5, contextTokens: 25, window: 100)
            .write(to: rolloutURL, atomically: true, encoding: .utf8)
        let hookRecordURL = tempDir.appending(path: "late-timeout-hook-record.json")
        let provider = CodexStatusProvider(
            context: makeContext(processStartTime: Date(), hookRecordPath: hookRecordURL.path),
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing.sqlite")),
            startupRetryInterval: 0.02,
            startupTimeout: 0.1
        )
        let expectation = XCTestExpectation(description: "provider binds after startup timeout")
        provider.onUpdate = { data in
            if data.model?.id == "late-timeout",
                data.contextWindow?.totalInputTokens == 15,
                data.contextWindow?.usedPercentage == 25
            {
                expectation.fulfill()
            }
        }

        provider.start()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
            try? self.writeHookRecord(
                to: hookRecordURL,
                sessionID: "thread-abcdef1234567890",
                transcriptPath: rolloutURL.path,
                model: "late-timeout",
                hookEventName: "UserPromptSubmit")
        }
        wait(for: [expectation], timeout: 2)
        provider.stop()

        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(events.contains { $0.name == "statusline.codex.hook_waiting" })
        XCTAssertTrue(
            events.contains {
                $0.name == "statusline.codex.binding.changed"
                    && $0.attributes["late_bound"] == "true"
                    && $0.attributes["hook_event_name"] == "UserPromptSubmit"
            })
    }

    @MainActor
    func testProviderIgnoresMismatchedHookRecordThenBindsCorrectRecord() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let rolloutURL = tempDir.appending(path: "correct-rollout.jsonl")
        try codexTokenLine(model: "correct-hook", input: 11, output: 4, contextTokens: 18, window: 100)
            .write(to: rolloutURL, atomically: true, encoding: .utf8)
        let hookRecordURL = tempDir.appending(path: "mismatch-hook-record.json")
        try writeHookRecord(
            to: hookRecordURL,
            sessionID: "wrong-thread",
            transcriptPath: rolloutURL.path,
            model: "wrong-hook",
            paneID: "33333333-3333-3333-3333-333333333333")
        let provider = CodexStatusProvider(
            context: makeContext(processStartTime: Date(), hookRecordPath: hookRecordURL.path),
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing.sqlite")),
            startupRetryInterval: 0.02,
            startupTimeout: 0.5
        )
        let expectation = XCTestExpectation(description: "provider waits for correct hook record")
        var observedModels: [String] = []
        provider.onUpdate = { data in
            if let model = data.model?.id {
                observedModels.append(model)
            }
            if data.model?.id == "correct-hook", data.contextWindow?.usedPercentage == 18 {
                expectation.fulfill()
            }
        }

        provider.start()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.12) {
            try? self.writeHookRecord(
                to: hookRecordURL,
                sessionID: "thread-abcdef1234567890",
                transcriptPath: rolloutURL.path,
                model: "correct-hook",
                hookEventName: "Stop")
        }
        wait(for: [expectation], timeout: 2)
        provider.stop()

        XCTAssertFalse(observedModels.contains("wrong-hook"))
        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(
            events.contains {
                $0.name == "statusline.codex.hook_record_ignored"
                    && $0.attributes["reason"] == "hook_context_mismatch"
                    && $0.attributes["hook_event_name"] == "SessionStart"
            })
        XCTAssertTrue(
            events.contains {
                $0.name == "statusline.codex.binding.changed"
                    && $0.attributes["hook_event_name"] == "Stop"
            })
    }
}

extension CodexStatusProviderTests {
    @MainActor
    func testCurrentProviderEmitsValidatedTurnEventsForCompletionCandidate() throws {
        let queueURL = tempDir.appending(path: "turn-events.jsonl")
        let context = makeContext(
            processStartTime: Date(),
            queuePath: queueURL.path,
            launchGeneration: "turn-events-generation",
            adapter: .current(version: "0.162.1"))
        let records = [
            ("SessionStart", Optional<String>.none),
            ("UserPromptSubmit", Optional("turn-current")),
            ("Stop", Optional("turn-current")),
        ].map { event, turnID in
            CodexHookQueueRecord(
                paneID: context.paneID.uuidString,
                tabID: context.tabID.uuidString,
                launchGeneration: context.codexLaunchGeneration ?? "",
                hookEventName: event,
                sessionID: "session-current",
                turnID: turnID,
                requestID: nil,
                timestamp: Date().timeIntervalSince1970,
                source: "hook",
                model: nil,
                transcriptPath: nil,
                result: nil)
        }
        let queueData = try records.reduce(into: Data()) { data, record in
            data.append(try JSONEncoder().encode(record))
            data.append(0x0A)
        }
        try queueData.write(to: queueURL)

        let provider = CodexStatusProvider(
            context: context,
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-turn-events.sqlite")),
            startupRetryInterval: 0.01,
            startupTimeout: 0.2)
        let candidateReceived = expectation(description: "completion candidate follows the bound foreground start")
        var events: [CodexProviderEvent] = []
        provider.onCodexEvent = { event, _ in
            events.append(event)
            if event == .foregroundCompletionCandidate(turnID: "turn-current") {
                candidateReceived.fulfill()
            }
        }

        provider.start()
        wait(for: [candidateReceived], timeout: 2)
        provider.stop()

        XCTAssertTrue(events.contains(.foregroundTurnStarted(turnID: "turn-current", isForeground: true)))
        XCTAssertEqual(events.filter { $0 == .foregroundCompletionCandidate(turnID: "turn-current") }.count, 1)
    }

    @MainActor
    func testCurrentAdapterReportsForegroundWorkingAndStoppedTransitions() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let queueURL = tempDir.appending(path: "activity-queue.jsonl")
        let context = makeContext(
            processStartTime: Date(),
            queuePath: queueURL.path,
            launchGeneration: "activity-generation",
            adapter: .current(version: "0.162.1"))
        try appendQueueRecord(
            to: queueURL,
            paneID: context.paneID,
            tabID: context.tabID,
            generation: "activity-generation",
            sessionID: "activity-session",
            hookEventName: "UserPromptSubmit")
        try appendQueueRecord(
            to: queueURL,
            paneID: context.paneID,
            tabID: context.tabID,
            generation: "activity-generation",
            sessionID: "activity-session",
            hookEventName: "Stop")

        let provider = CodexStatusProvider(
            context: context,
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-activity.sqlite")),
            startupRetryInterval: 0.01,
            startupTimeout: 0.2)
        let transitionsObserved = expectation(description: "foreground start and stop are reported")
        transitionsObserved.expectedFulfillmentCount = 2
        let stateLock = NSLock()
        var states: [Bool] = []
        provider.onActivityChanged = { isWorking in
            stateLock.withLock { states.append(isWorking) }
            transitionsObserved.fulfill()
        }

        provider.start()
        wait(for: [transitionsObserved], timeout: 2)
        provider.stop()

        XCTAssertEqual(stateLock.withLock { states }, [true, false])
        let events = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.codex.activity.changed"
        }
        XCTAssertEqual(events.map(\.attributes["state"]), ["working", "stopped"])
        XCTAssertTrue(events.allSatisfy { $0.attributes["pane.id"] == context.paneID.uuidString })
        XCTAssertTrue(events.allSatisfy { $0.attributes["tab.id"] == context.tabID.uuidString })
    }

    @MainActor
    func testDelegatedHookRecordsDoNotBindForegroundSessionOrActivity() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }
        let queueURL = tempDir.appending(path: "delegated-hooks.jsonl")
        let context = makeContext(
            processStartTime: Date(),
            queuePath: queueURL.path,
            launchGeneration: "delegated-generation",
            adapter: .current(version: "0.162.1"))
        for event in ["SessionStart", "UserPromptSubmit", "Stop"] {
            try appendQueueRecord(
                to: queueURL,
                paneID: context.paneID,
                tabID: context.tabID,
                generation: "delegated-generation",
                sessionID: "delegated-session",
                hookEventName: event,
                source: "subagent")
        }
        let provider = CodexStatusProvider(
            context: context,
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-delegated.sqlite")),
            startupRetryInterval: 0.01,
            startupTimeout: 0.2)
        var boundSessions: [String] = []
        var activityChanges: [Bool] = []
        provider.onSessionBound = { sessionID, _ in boundSessions.append(sessionID) }
        provider.onActivityChanged = { activityChanges.append($0) }

        provider.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        provider.stop()

        XCTAssertTrue(boundSessions.isEmpty)
        XCTAssertTrue(activityChanges.isEmpty)
        XCTAssertTrue(provider.pendingHookRecords.isEmpty)
        XCTAssertTrue(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "statusline.codex.hook_queue.record_ignored"
                    && $0.attributes["reason"] == "delegated_source"
            })
    }

    @MainActor
    func testInterruptStopsCurrentAdapterAndLegacyAdapterIgnoresIt() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let currentQueue = tempDir.appending(path: "current-interrupt-queue.jsonl")
        let legacyQueue = tempDir.appending(path: "legacy-interrupt-queue.jsonl")
        let currentContext = makeContext(
            processStartTime: Date(),
            queuePath: currentQueue.path,
            launchGeneration: "current-interrupt-generation",
            adapter: .current(version: "0.162.1"))
        let legacyContext = makeContext(
            processStartTime: Date(),
            queuePath: legacyQueue.path,
            launchGeneration: "legacy-interrupt-generation",
            adapter: .legacy(version: "0.136.4"))
        try appendQueueRecord(
            to: currentQueue,
            paneID: currentContext.paneID,
            tabID: currentContext.tabID,
            generation: "current-interrupt-generation",
            sessionID: "current-session",
            hookEventName: "Interrupt")
        try appendQueueRecord(
            to: legacyQueue,
            paneID: legacyContext.paneID,
            tabID: legacyContext.tabID,
            generation: "legacy-interrupt-generation",
            sessionID: "legacy-session",
            hookEventName: "Interrupt")

        let currentProvider = CodexStatusProvider(
            context: currentContext,
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-current.sqlite")),
            startupRetryInterval: 0.01,
            startupTimeout: 0.2)
        let legacyProvider = CodexStatusProvider(
            context: legacyContext,
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-legacy.sqlite")),
            startupRetryInterval: 0.01,
            startupTimeout: 0.2)
        let currentInterrupted = expectation(description: "current adapter reports interruption as stopped")
        let legacyIgnoredInterrupt = expectation(description: "legacy adapter has no interruption lifecycle event")
        legacyIgnoredInterrupt.isInverted = true
        currentProvider.onActivityChanged = { isWorking in
            XCTAssertFalse(isWorking)
            currentInterrupted.fulfill()
        }
        legacyProvider.onActivityChanged = { _ in legacyIgnoredInterrupt.fulfill() }

        currentProvider.start()
        legacyProvider.start()
        wait(for: [currentInterrupted, legacyIgnoredInterrupt], timeout: 0.4)
        currentProvider.stop()
        legacyProvider.stop()

        XCTAssertTrue(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "statusline.codex.hook_queue.record_ignored"
                    && $0.attributes["hook_event_name"] == "Interrupt"
            })
    }

    @MainActor
    func testHookWriterFailureIsReportedWithOnlyBoundedCode() throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }
        let diagnosticURL = tempDir.appending(path: "hook-writer-diagnostic.txt")
        let queueURL = tempDir.appending(path: "diagnostic-queue.jsonl")
        let context = makeContext(
            processStartTime: Date(),
            queuePath: queueURL.path,
            diagnosticPath: diagnosticURL.path,
            launchGeneration: "diagnostic-generation",
            adapter: .current(version: "0.162.1"))
        let record = CodexHookQueueRecord(
            paneID: context.paneID.uuidString,
            tabID: context.tabID.uuidString,
            launchGeneration: "diagnostic-generation",
            hookEventName: "SessionStart",
            sessionID: "diagnostic-session",
            turnID: nil,
            requestID: nil,
            timestamp: 1,
            source: "hook",
            model: nil,
            transcriptPath: nil,
            result: nil)
        var queueData = try JSONEncoder().encode(record)
        queueData.append(UInt8(ascii: "\n"))
        try queueData.write(to: queueURL)
        let provider = CodexStatusProvider(
            context: context,
            stateStore: CodexStateStore(databaseURL: tempDir.appending(path: "missing-diagnostic.sqlite")),
            startupRetryInterval: 0.01,
            startupTimeout: 0.2)
        let hookObserved = expectation(description: "session start is delivered before the failure")
        let traceCheck = expectation(description: "post-bind writer failure becomes a bounded provider diagnostic")
        provider.onHookRecords = { _ in
            try? "failed|unknown|queue_lock_timeout\n".write(to: diagnosticURL, atomically: true, encoding: .utf8)
            hookObserved.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { traceCheck.fulfill() }

        provider.start()
        wait(for: [hookObserved, traceCheck], timeout: 2)
        provider.stop()

        let failure = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "statusline.codex.hook_queue.write_failed"
        }
        XCTAssertEqual(failure?.attributes["result"], "queue_lock_timeout")
        XCTAssertFalse(String(describing: failure?.attributes ?? [:]).contains("SENSITIVE"))
    }

    @MainActor
    func testProviderBindsLatestForegroundRecordFromStartupBurst() throws {
        let rolloutA = tempDir.appending(path: "session-a.jsonl")
        let rolloutB = tempDir.appending(path: "session-b.jsonl")
        try (codexTokenLine(model: "session-a-model", input: 10, output: 2, contextTokens: 12, window: 100) + "\n")
            .write(to: rolloutA, atomically: true, encoding: .utf8)
        try (codexTokenLine(model: "session-b-model", input: 20, output: 3, contextTokens: 23, window: 100) + "\n")
            .write(to: rolloutB, atomically: true, encoding: .utf8)
        let processStartMs = Int64(Date().timeIntervalSince1970 * 1000)
        let dbURL = tempDir.appending(path: "startup-burst.sqlite")
        try executeSQL(
            """
            CREATE TABLE threads (
              id TEXT, cwd TEXT, rollout_path TEXT, model TEXT, cli_version TEXT,
              tokens_used INTEGER, git_branch TEXT, created_at_ms INTEGER,
              updated_at_ms INTEGER, is_archived INTEGER
            );
            INSERT INTO threads VALUES ('session-a', '\(tempDir.path)', '\(rolloutA.path)', 'session-a-model', '0.162.1', 12, 'main', \(processStartMs), \(processStartMs), 0);
            INSERT INTO threads VALUES ('session-b', '\(tempDir.path)', '\(rolloutB.path)', 'session-b-model', '0.162.1', 23, 'main', \(processStartMs), \(processStartMs), 0);
            """,
            at: dbURL)

        let context = makeContext(
            processStartTime: Date(),
            queuePath: tempDir.appending(path: "startup-burst.jsonl").path,
            launchGeneration: "generation-one",
            adapter: .current(version: "0.162.1"))
        let records = [
            CodexHookQueueRecord(
                paneID: context.paneID.uuidString,
                tabID: context.tabID.uuidString,
                launchGeneration: "generation-one",
                hookEventName: "SessionStart",
                sessionID: "session-a",
                turnID: nil,
                requestID: nil,
                timestamp: 1,
                source: "hook",
                model: "session-a-model",
                transcriptPath: rolloutA.path,
                result: nil),
            CodexHookQueueRecord(
                paneID: context.paneID.uuidString,
                tabID: context.tabID.uuidString,
                launchGeneration: "generation-one",
                hookEventName: "UserPromptSubmit",
                sessionID: "session-b",
                turnID: "turn-b",
                requestID: nil,
                timestamp: 2,
                source: "hook",
                model: "session-b-model",
                transcriptPath: rolloutB.path,
                result: nil),
        ]
        let supersededGenerationRecord = CodexHookQueueRecord(
            paneID: context.paneID.uuidString,
            tabID: context.tabID.uuidString,
            launchGeneration: "superseded-generation",
            hookEventName: "UserPromptSubmit",
            sessionID: "stale-session",
            turnID: nil,
            requestID: nil,
            timestamp: 0,
            source: "hook",
            model: "stale-model",
            transcriptPath: nil,
            result: nil)
        let queueRecords = [supersededGenerationRecord] + records
        let queueData = try queueRecords.reduce(into: Data()) { data, record in
            data.append(try JSONEncoder().encode(record))
            data.append(0x0A)
        }
        try queueData.write(to: URL(filePath: context.codexHookQueuePath!))

        let provider = CodexStatusProvider(
            context: context,
            stateStore: CodexStateStore(databaseURL: dbURL),
            startupRetryInterval: 0.01,
            startupTimeout: 0.5)
        let expectation = XCTestExpectation(description: "latest startup burst session binds")
        provider.onUpdate = { data in
            if data.model?.id == "session-b-model", data.contextWindow?.totalInputTokens == 20 {
                expectation.fulfill()
            }
        }

        provider.start()
        wait(for: [expectation], timeout: 2)
        provider.stop()

        XCTAssertEqual(provider.pendingHookRecords, records)
        XCTAssertEqual(provider.pendingHookRecords.last?.sessionID, "session-b")
    }

    @MainActor
    func testCodexLaunchPreflightUsesPaneResolvedExportedCodexHome() throws {
        let codexHome = tempDir.appending(path: "codex-home-exported", directoryHint: .isDirectory)
        let decoyHome = tempDir.appending(path: "codex-home-controller", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: decoyHome, withIntermediateDirectories: true)
        try executeSQL(
            """
            CREATE TABLE threads (id TEXT, cwd TEXT, rollout_path TEXT, model TEXT);
            INSERT INTO threads VALUES ('session-exact', '/repo', '/repo/exact.jsonl', 'gpt-5.1');
            INSERT INTO threads VALUES ('session-newest', '/repo', '/repo/newest.jsonl', 'gpt-5.2');
            """,
            at: codexHome.appending(path: "state_5.sqlite"))
        try executeSQL(
            """
            CREATE TABLE threads (id TEXT, cwd TEXT, rollout_path TEXT, model TEXT);
            INSERT INTO threads VALUES ('session-decoy', '/repo', '/repo/exact.jsonl', 'gpt-decoy');
            """,
            at: decoyHome.appending(path: "state_5.sqlite"))
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        let pane = Pane(name: "codex", tab: tab, harness: .codex)
        pane.codexHomeResolution = .resolved(codexHome.path)
        pane.codexTranscriptPath = "/repo/exact.jsonl"
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: "/repo",
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"),
            codexLaunchEnvironment: ["CODEX_HOME": codexHome.path],
            codexHomeResolution: pane.codexHomeResolution)
        let controller = TerminalController()
        controller.pendingEnvironment = ["CODEX_HOME=\(decoyHome.path)"]
        let selected = tab.configureCodexLaunch(
            for: pane,
            monitor: monitor,
            controller: controller,
            extraArgs: ["--model", "gpt-5.1"],
            appSettings: nil,
            resumeSessionID: "session-exact")

        XCTAssertTrue(selected)
        XCTAssertEqual(
            Array(controller.pendingCommandArgs?.suffix(4) ?? []), ["--model", "gpt-5.1", "resume", "session-exact"])
        XCTAssertFalse(controller.pendingCommandArgs?.contains("--last") ?? true)
    }

    @MainActor
    func testCodexContinuationPreflightUsesExportedHomeWhenCodexHomeIsUnset() throws {
        let shellHome = tempDir.appending(path: "codex-shell-home", directoryHint: .isDirectory)
        let codexHome = shellHome.appending(path: ".codex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try executeSQL(
            """
            CREATE TABLE threads (id TEXT, cwd TEXT, rollout_path TEXT);
            INSERT INTO threads VALUES ('home-session', '/repo', '/repo/home.jsonl');
            """,
            at: codexHome.appending(path: "state_5.sqlite"))
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        let pane = Pane(name: "codex", tab: tab, harness: .codex)
        pane.codexHomeResolution = .unset(shellHome: shellHome.path)
        pane.codexTranscriptPath = "/repo/home.jsonl"
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: "/repo",
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"),
            codexLaunchEnvironment: ["HOME": shellHome.path],
            codexHomeResolution: pane.codexHomeResolution)
        let controller = TerminalController()
        controller.pendingEnvironment = ["HOME=\(shellHome.path)"]

        let selected = tab.configureCodexLaunch(
            for: pane,
            monitor: monitor,
            controller: controller,
            extraArgs: [],
            appSettings: nil,
            resumeSessionID: "home-session")

        XCTAssertTrue(selected)
        XCTAssertTrue(controller.pendingEnvironment?.contains("HOME=\(shellHome.path)") == true)
        XCTAssertEqual(
            Array(controller.pendingCommandArgs?.suffix(2) ?? []), ["resume", "home-session"])
    }

    @MainActor
    func testUnavailableCodexHomePreflightPreservesExistingIdentityAndController() throws {
        let decoyHome = tempDir.appending(path: "codex-home-unavailable-decoy", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: decoyHome, withIntermediateDirectories: true)
        try executeSQL(
            """
            CREATE TABLE threads (id TEXT, cwd TEXT, rollout_path TEXT);
            INSERT INTO threads VALUES ('requested-session', '/repo', '/repo/requested.jsonl');
            """,
            at: decoyHome.appending(path: "state_5.sqlite"))
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        let pane = Pane(name: "codex", tab: tab, harness: .codex)
        pane.codexSessionID = "requested-session"
        pane.codexTranscriptPath = "/repo/requested.jsonl"
        pane.codexExpectedResumeSessionID = "requested-session"
        pane.codexHomeResolution = .unavailable
        let oldController = TerminalController()
        oldController.pendingCommandArgs = ["codex", "existing-conversation"]
        pane.installTerminalController(oldController)
        let oldMonitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: "/repo",
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"))
        pane.installStatusLineMonitor(oldMonitor)
        defer {
            pane.removeStatusLineMonitor()
            pane.terminalController?.terminate()
        }
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: "/repo",
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"))
        let controller = TerminalController()
        controller.pendingEnvironment = ["CODEX_HOME=\(decoyHome.path)"]

        let selected = tab.configureCodexLaunch(
            for: pane,
            monitor: monitor,
            controller: controller,
            extraArgs: [],
            appSettings: nil,
            resumeSessionID: pane.codexSessionID)

        XCTAssertFalse(selected)
        XCTAssertTrue(pane.terminalController === oldController)
        XCTAssertTrue(pane.statusLineMonitor === oldMonitor)
        XCTAssertEqual(pane.codexSessionID, "requested-session")
        XCTAssertEqual(pane.codexTranscriptPath, "/repo/requested.jsonl")
        XCTAssertEqual(pane.codexExpectedResumeSessionID, "requested-session")
        guard case .codexResumeUnavailable(let sessionID, _) = pane.setupState else {
            XCTFail("Expected unavailable Codex continuation recovery")
            return
        }
        XCTAssertEqual(sessionID, "requested-session")
    }

    @MainActor
    func testExactCodexRelaunchBuildsFreshHookGeneration() throws {
        let codexHome = tempDir.appending(path: "codex-home-generation", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try executeSQL(
            """
            CREATE TABLE threads (id TEXT, cwd TEXT, rollout_path TEXT);
            INSERT INTO threads VALUES ('session-exact', '/repo', '/repo/exact.jsonl');
            """,
            at: codexHome.appending(path: "state_5.sqlite"))
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        let pane = Pane(name: "codex", tab: tab, harness: .codex)
        pane.codexHomeResolution = .resolved(codexHome.path)
        pane.codexTranscriptPath = "/repo/exact.jsonl"
        let firstMonitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: "/repo",
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"),
            codexLaunchEnvironment: ["CODEX_HOME": codexHome.path])
        let secondMonitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: "/repo",
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"),
            codexLaunchEnvironment: ["CODEX_HOME": codexHome.path])
        let firstController = TerminalController()
        firstController.pendingEnvironment = ["CODEX_HOME=\(codexHome.path)"]
        let secondController = TerminalController()
        secondController.pendingEnvironment = ["CODEX_HOME=\(codexHome.path)"]

        XCTAssertTrue(
            tab.configureCodexLaunch(
                for: pane,
                monitor: firstMonitor,
                controller: firstController,
                extraArgs: ["--model", "gpt-5.1"],
                appSettings: nil,
                resumeSessionID: "session-exact"))
        XCTAssertTrue(
            tab.configureCodexLaunch(
                for: pane,
                monitor: secondMonitor,
                controller: secondController,
                extraArgs: ["--model", "gpt-5.1"],
                appSettings: nil,
                resumeSessionID: "session-exact"))

        XCTAssertNotEqual(firstMonitor.codexLaunchGeneration, secondMonitor.codexLaunchGeneration)
        XCTAssertEqual(
            Array(firstController.pendingCommandArgs?.suffix(4) ?? []),
            ["--model", "gpt-5.1", "resume", "session-exact"])
        XCTAssertEqual(firstController.pendingCommandArgs, secondController.pendingCommandArgs)
        XCTAssertTrue(
            firstController.pendingEnvironment?.contains(
                "AGENT_SESSION_MANAGER_CODEX_LAUNCH_GENERATION=\(firstMonitor.codexLaunchGeneration)") ?? false)
        XCTAssertTrue(
            secondController.pendingEnvironment?.contains(
                "AGENT_SESSION_MANAGER_CODEX_LAUNCH_GENERATION=\(secondMonitor.codexLaunchGeneration)") ?? false)
        XCTAssertNotEqual(firstMonitor.codexHookQueueFilePath, secondMonitor.codexHookQueueFilePath)
    }

    @MainActor
    func testCodexContinuationPreflightRejectsTranscriptPathForDifferentSession() throws {
        let codexHome = tempDir.appending(path: "codex-home-path-mismatch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try executeSQL(
            """
            CREATE TABLE threads (id TEXT, cwd TEXT, rollout_path TEXT);
            INSERT INTO threads VALUES ('different-session', '/repo', '/repo/requested.jsonl');
            """,
            at: codexHome.appending(path: "state_5.sqlite"))
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        let pane = Pane(name: "codex", tab: tab, harness: .codex)
        pane.codexHomeResolution = .resolved(codexHome.path)
        pane.codexSessionID = "requested-session"
        pane.codexTranscriptPath = "/repo/requested.jsonl"
        let oldController = TerminalController()
        oldController.pendingCommandArgs = ["codex", "existing-conversation"]
        pane.installTerminalController(oldController)
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: "/repo",
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"),
            codexLaunchEnvironment: ["CODEX_HOME": codexHome.path])
        let controller = TerminalController()
        controller.pendingEnvironment = ["CODEX_HOME=\(codexHome.path)"]
        let selected = tab.configureCodexLaunch(
            for: pane,
            monitor: monitor,
            controller: controller,
            extraArgs: [],
            appSettings: nil,
            resumeSessionID: pane.codexSessionID)

        XCTAssertFalse(selected)
        XCTAssertTrue(pane.terminalController === oldController)
        XCTAssertEqual(oldController.pendingCommandArgs, ["codex", "existing-conversation"])
        guard case .codexResumeUnavailable(let sessionID, let reason) = pane.setupState else {
            XCTFail("Expected app-level Codex continuation recovery")
            return
        }
        XCTAssertEqual(sessionID, "requested-session")
        XCTAssertTrue(reason.contains("Retry or start a new conversation"))
    }

    @MainActor
    func testCodexContinuationRetryPreservesRequestedIdentityAndExistingTerminal() {
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        let pane = Pane(name: "codex", tab: tab, harness: .codex, agentControlInjectionEnabled: false)
        pane.codexSessionID = "retry-session"
        pane.codexTranscriptPath = "/repo/retry.jsonl"
        pane.setupState = .codexResumeUnavailable(
            sessionID: "retry-session", reason: "The saved Codex conversation is unavailable.")
        let oldController = TerminalController()
        oldController.pendingDirectory = "/repo"
        oldController.pendingCommandArgs = ["codex", "existing-conversation"]
        pane.installTerminalController(oldController)
        tab.panes.append(pane)
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer {
            pane.removeStatusLineMonitor()
            pane.terminalController?.terminate()
            TracingService.shared.resetForTesting()
        }

        tab.retryCodexContinuation(pane, startNew: false)

        XCTAssertEqual(pane.codexSessionID, "retry-session")
        XCTAssertEqual(pane.codexTranscriptPath, "/repo/retry.jsonl")
        XCTAssertTrue(pane.terminalController === oldController)
        guard case .codexResumeUnavailable = pane.setupState else {
            XCTFail("Retry must preserve recovery when the exact conversation is still unavailable")
            return
        }
        XCTAssertTrue(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "session.pane.codex_continuation.recovery" && $0.attributes["action"] == "retry"
            })
    }

    @MainActor
    func testCodexStartNewRecoveryClearsIdentityAndBuildsFreshCommand() {
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        let pane = Pane(name: "codex", tab: tab, harness: .codex, agentControlInjectionEnabled: false)
        pane.extraArgs = ["--model", "gpt-5.1"]
        pane.codexSessionID = "unavailable-session"
        pane.codexTranscriptPath = "/repo/unavailable.jsonl"
        pane.codexExpectedResumeSessionID = "unavailable-session"
        pane.codexFreshStartNotice = true
        pane.setupState = .codexResumeUnavailable(
            sessionID: "unavailable-session", reason: "The saved Codex conversation is unavailable.")
        let oldController = TerminalController()
        oldController.pendingDirectory = "/repo"
        oldController.pendingCommandArgs = ["codex", "resume", "unavailable-session"]
        pane.installTerminalController(oldController)
        tab.panes.append(pane)
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer {
            pane.removeStatusLineMonitor()
            pane.terminalController?.terminate()
            TracingService.shared.resetForTesting()
        }

        tab.retryCodexContinuation(pane, startNew: true)

        XCTAssertNil(pane.codexSessionID)
        XCTAssertNil(pane.codexTranscriptPath)
        XCTAssertNil(pane.codexExpectedResumeSessionID)
        XCTAssertFalse(pane.codexFreshStartNotice)
        XCTAssertFalse(pane.terminalController === oldController)
        XCTAssertFalse(pane.terminalController?.pendingCommandArgs?.contains("resume") ?? true)
        XCTAssertEqual(pane.extraArgs, ["--model", "gpt-5.1"])
        XCTAssertTrue(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "session.pane.codex_continuation.recovery" && $0.attributes["action"] == "start_new"
            })
    }

    @MainActor
    func testStartNewSetupFailurePreservesControllerAndPersistedConversationIdentity() throws {
        let subdirectory = "codex-start-new-failure-\(UUID().uuidString)"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: subdirectory)
        let fakeBin = tempDir.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let fakeCodex = fakeBin.appending(path: "codex")
        try "#!/bin/sh\nprintf 'codex-cli 0.162.1\\n'\n".write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        let fakeShell = tempDir.appending(path: "shell")
        try "#!/bin/sh\nPATH='\(fakeBin.path)'\nexport PATH\nexec /bin/sh -c \"$3\"\n"
            .write(to: fakeShell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeShell.path)
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        let settings = AppSettings()
        settings.preferredShell = fakeShell.path
        let appState = AppState()
        let tab = Tab(name: "repo", directory: URL(filePath: tempDir.path))
        let pane = Pane(name: "codex", tab: tab, harness: .codex, agentControlInjectionEnabled: false)
        pane.extraArgs = ["--ask-for-approval", "untrusted", "--custom", "retained"]
        pane.codexSessionID = "saved-session"
        pane.codexTranscriptPath = tempDir.appending(path: "saved-rollout.jsonl").path
        pane.codexExpectedResumeSessionID = "saved-session"
        pane.codexFreshStartNotice = true
        let oldController = TerminalController()
        oldController.pendingDirectory = tempDir.path
        oldController.pendingCommandArgs = ["codex", "resume", "saved-session"]
        pane.installTerminalController(oldController)
        pane.bindNotifications(appState: appState, isPriority: false)
        tab.panes.append(pane)
        appState.tabs.append(tab)
        XCTAssertTrue(SessionPersistence.save(appState: appState))
        let sessionURL = appSupport.appending(path: "sessions.json")
        let savedData = try Data(contentsOf: sessionURL)
        defer {
            pane.terminalController?.terminate()
            pane.removeStatusLineMonitor()
            PersistenceHelpers.overrideAppSupportSubdirectory = nil
            try? FileManager.default.removeItem(at: appSupport)
        }

        tab.retryCodexContinuation(pane, startNew: true, appSettings: settings)

        XCTAssertTrue(pane.terminalController === oldController)
        XCTAssertEqual(pane.codexSessionID, "saved-session")
        XCTAssertEqual(pane.codexTranscriptPath, tempDir.appending(path: "saved-rollout.jsonl").path)
        XCTAssertEqual(pane.codexExpectedResumeSessionID, "saved-session")
        XCTAssertTrue(pane.codexFreshStartNotice)
        XCTAssertEqual(try Data(contentsOf: sessionURL), savedData)
        let persisted = try JSONDecoder().decode(PersistedSession.self, from: savedData)
        XCTAssertEqual(persisted.tabs.first?.panes.first?.codexSessionID, "saved-session")
        XCTAssertEqual(
            persisted.tabs.first?.panes.first?.codexTranscriptPath,
            tempDir.appending(path: "saved-rollout.jsonl").path)
        guard case .failed(let error) = pane.setupState else {
            XCTFail("Expected setup validation to reject the saved unsupported approval value")
            return
        }
        XCTAssertTrue(error.contains("untrusted"))
    }

    @MainActor
    func testMissingExactCodexConversationEntersRecoveryWithoutReplacingTerminal() throws {
        let codexHome = tempDir.appending(path: "codex-home-missing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try executeSQL(
            """
            CREATE TABLE threads (id TEXT, cwd TEXT, rollout_path TEXT);
            INSERT INTO threads VALUES ('newest-session', '/repo', '/repo/newest.jsonl');
            """,
            at: codexHome.appending(path: "state_5.sqlite"))
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        let pane = Pane(name: "codex", tab: tab, harness: .codex)
        pane.codexHomeResolution = .resolved(codexHome.path)
        pane.codexSessionID = "missing-foreground"
        pane.codexTranscriptPath = "/repo/missing.jsonl"
        let oldController = TerminalController()
        oldController.pendingCommandArgs = ["codex", "existing-conversation"]
        pane.installTerminalController(oldController)
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: "/repo",
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"),
            codexLaunchEnvironment: ["CODEX_HOME": codexHome.path])
        let controller = TerminalController()
        controller.pendingEnvironment = ["CODEX_HOME=\(codexHome.path)"]
        let selected = tab.configureCodexLaunch(
            for: pane,
            monitor: monitor,
            controller: controller,
            extraArgs: [],
            appSettings: nil,
            resumeSessionID: pane.codexSessionID)

        XCTAssertFalse(selected)
        XCTAssertTrue(pane.terminalController === oldController)
        XCTAssertEqual(oldController.pendingCommandArgs, ["codex", "existing-conversation"])
        guard case .codexResumeUnavailable(let sessionID, let reason) = pane.setupState else {
            XCTFail("Expected app-level Codex continuation recovery")
            return
        }
        XCTAssertEqual(sessionID, "missing-foreground")
        XCTAssertTrue(reason.contains("Retry or start a new conversation"))
    }

    fileprivate func executeSQL(_ sql: String, at url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw NSError(domain: "SQLiteTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    fileprivate func run(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
    }

    fileprivate func createThreadDatabase(
        at dbURL: URL,
        rolloutPath: String,
        model: String,
        createdAtMs: Int64
    ) throws {
        try executeSQL(
            """
            CREATE TABLE IF NOT EXISTS threads (
              id TEXT,
              cwd TEXT,
              rollout_path TEXT,
              model TEXT,
              cli_version TEXT,
              tokens_used INTEGER,
              git_branch TEXT,
              created_at_ms INTEGER,
              updated_at_ms INTEGER,
              is_archived INTEGER
            );
            DELETE FROM threads WHERE id = 'thread-abcdef1234567890';
            INSERT INTO threads VALUES ('thread-abcdef1234567890', '\(tempDir.path)', '\(rolloutPath)', '\(model)', 'codex-cli 0.136.0', 30, 'main', \(createdAtMs), \(createdAtMs), 0);
            """,
            at: dbURL
        )
    }

    fileprivate func makeContext(
        processStartTime: Date,
        hookRecordPath: String? = nil,
        queuePath: String? = nil,
        diagnosticPath: String? = nil,
        launchGeneration: String? = nil,
        adapter: CodexCompatibilityAdapter? = nil,
        codexShell: String? = nil,
        environment: [String: String] = [:],
        workingDirectory: String? = nil,
        paneID: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        tabID: UUID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    ) -> StatusProviderContext {
        StatusProviderContext(
            paneID: paneID,
            paneName: "codex-pane",
            tabID: tabID,
            tabName: "repo",
            workingDirectory: workingDirectory ?? tempDir.path,
            harness: .codex,
            processStartTime: processStartTime,
            launchArgs: [],
            environment: environment,
            codexShell: codexShell,
            detectedHarnessVersion: "codex-cli 0.136.0",
            codexHookRecordPath: hookRecordPath ?? tempDir.appending(path: "hook-record.json").path,
            opencodePort: nil,
            opencodeSessionID: nil,
            codexHookQueuePath: queuePath,
            codexHookDiagnosticPath: diagnosticPath,
            codexLaunchGeneration: launchGeneration,
            codexAdapter: adapter
        )
    }

    fileprivate func appendQueueRecord(
        to url: URL,
        paneID: UUID,
        tabID: UUID,
        generation: String,
        sessionID: String,
        transcriptPath: String? = nil,
        model: String? = nil,
        hookEventName: String = "SessionStart",
        source: String = "hook"
    ) throws {
        let record = CodexHookQueueRecord(
            paneID: paneID.uuidString,
            tabID: tabID.uuidString,
            launchGeneration: generation,
            hookEventName: hookEventName,
            sessionID: sessionID,
            turnID: nil,
            requestID: nil,
            timestamp: Date().timeIntervalSince1970,
            source: source,
            model: model,
            transcriptPath: transcriptPath,
            result: nil)
        var data = try JSONEncoder().encode(record)
        data.append(UInt8(ascii: "\n"))
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    fileprivate func writeHookRecord(
        to url: URL,
        sessionID: String,
        transcriptPath: String?,
        model: String = "gpt-5.1-codex",
        hookEventName: String = "SessionStart",
        paneID: String = "11111111-1111-1111-1111-111111111111",
        tabID: String = "22222222-2222-2222-2222-222222222222"
    ) throws {
        let record = CodexHookSessionRecord(
            paneID: paneID,
            tabID: tabID,
            sessionID: sessionID,
            cwd: tempDir.path,
            model: model,
            transcriptPath: transcriptPath,
            hookEventName: hookEventName,
            timestamp: Date().timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: .atomic)
    }

    fileprivate func codexTokenLine(
        model: String,
        input: Int,
        output: Int,
        contextTokens: Int,
        window: Int
    ) -> String {
        let currentContext = 12_000 + contextTokens
        let contextWindow = 12_000 + window
        return """
            {"type":"event_msg","payload":{"type":"token_count","model":"\(model)","total_token_usage":{"input_tokens":\(input),"output_tokens":\(output)},"last_token_usage":{"total_tokens":\(currentContext)},"model_context_window":\(contextWindow)}}
            """
            .appending("\n")
    }
}
