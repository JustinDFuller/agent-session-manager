import SQLite3
import XCTest

@testable import AgentSessionManager

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

    func testRolloutParserMapsTokenCountAndRateLimits() throws {
        let line = Data(
            """
            {"type":"event_msg","payload":{"type":"token_count","model":"gpt-5.1-codex","total_token_usage":{"input_tokens":300,"output_tokens":100},"last_token_usage":{"total_tokens":250},"model_context_window":1000,"rate_limits":{"primary":{"window_minutes":300,"used_percentage":25,"resets_at":2000000000},"secondary":{"window_minutes":10080,"used_percentage":50,"resets_at":2000003600}}}}
            """.utf8)

        let data = CodexRolloutParser.parseLine(line, expectedCWD: "/repo")

        XCTAssertEqual(data?.model?.id, "gpt-5.1-codex")
        XCTAssertEqual(data?.contextWindow?.totalInputTokens, 300)
        XCTAssertEqual(data?.contextWindow?.totalOutputTokens, 100)
        XCTAssertEqual(data?.contextWindow?.usedPercentage, 25)
        XCTAssertEqual(data?.contextWindow?.remainingPercentage, 75)
        XCTAssertEqual(data?.rateLimits?.fiveHour?.usedPercentage, 25)
        XCTAssertEqual(data?.rateLimits?.fiveHour?.resetsAt, 2_000_000_000)
        XCTAssertEqual(data?.rateLimits?.sevenDay?.usedPercentage, 50)
        XCTAssertEqual(data?.rateLimits?.sevenDay?.resetsAt, 2_000_003_600)
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
        let line = Data(
            """
            {"type":"event_msg","payload":{"type":"token_count","info":{"model":"gpt-5.1-codex","total_token_usage":{"input_tokens":320,"output_tokens":80},"last_token_usage":{"total_tokens":200},"model_context_window":2000},"rate_limits":{"primary":{"window_minutes":300,"used_percent":12.5,"resets_at":2000000000},"secondary":{"window_minutes":10080,"used_percent":44,"resets_at":2000003600}}}}
            """.utf8)

        let data = CodexRolloutParser.parseLine(line, expectedCWD: "/repo")

        XCTAssertEqual(data?.model?.id, "gpt-5.1-codex")
        XCTAssertEqual(data?.contextWindow?.totalInputTokens, 320)
        XCTAssertEqual(data?.contextWindow?.totalOutputTokens, 80)
        XCTAssertEqual(data?.contextWindow?.usedPercentage, 10)
        XCTAssertEqual(data?.contextWindow?.remainingPercentage, 90)
        XCTAssertEqual(data?.rateLimits?.fiveHour?.usedPercentage, 12.5)
        XCTAssertEqual(data?.rateLimits?.sevenDay?.usedPercentage, 44)
    }

    func testRolloutParserMapsTurnContextModelBeforeTokenUsage() throws {
        let line = Data(
            """
            {"type":"event_msg","payload":{"type":"turn_context","model":"gpt-5.1-codex"}}
            """.utf8)

        let data = CodexRolloutParser.parseLine(line, expectedCWD: "/repo")

        XCTAssertEqual(data?.model?.id, "gpt-5.1-codex")
        XCTAssertNil(data?.contextWindow)
    }

    func testRolloutParserUsesLastTokenUsageForContextAndTotalUsageForTokenTotals() throws {
        let line = Data(
            """
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"output_tokens":100},"last_token_usage":{"total_tokens":250},"model_context_window":1000}}}
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
            #"{"type":"event_msg","payload":{"type":"token_count","model":"partial","total_token_usage":{"input_tokens":10,"output_tokens":2},"last_token_usage":{"total_tokens":6},"model_context_window":100}}"#
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
            {"type":"event_msg","payload":{"type":"token_count","info":{"model":"gpt-5.1-codex","total_token_usage":{"input_tokens":320,"output_tokens":80},"last_token_usage":{"total_tokens":400},"model_context_window":2000},"rate_limits":{"primary":{"window_minutes":300,"used_percent":12.5,"resets_at":2000000000},"secondary":{"window_minutes":10080,"used_percent":44,"resets_at":2000003600}}}}
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
        XCTAssertTrue(events.contains { $0.name == "statusline.codex.hook_bound" })
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
        try codexTokenLine(model: "trace-model", input: 5, output: 2, contextTokens: 7, window: 100)
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
        provider.onUpdate = { data in
            if data.model?.id == "trace-model", data.contextWindow?.usedPercentage == 7 {
                expectation.fulfill()
            }
        }

        provider.start()
        wait(for: [expectation], timeout: 2)
        provider.stop()

        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertFalse(events.contains { $0.name == "statusline.provider.started" })
        XCTAssertFalse(events.contains { $0.name == "statusline.provider.stopped" })
        XCTAssertFalse(events.contains { $0.name == "statusline.provider.update_applied" })
        let codexEvents = events.filter { $0.name.hasPrefix("statusline.codex.") }
        XCTAssertFalse(codexEvents.isEmpty)
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

    func testBuildCodexCommandRegistersAppOwnedHooks() {
        let command = Tab.buildCodexCommand(hookScriptPath: "/tmp/hook path.py", extraArgs: ["--model", "gpt-5.1"])

        XCTAssertTrue(command.contains("codex"))
        XCTAssertTrue(command.contains("--dangerously-bypass-hook-trust"))
        XCTAssertTrue(command.contains("features.hooks=true"))
        XCTAssertTrue(command.contains(where: { $0.hasPrefix("hooks.SessionStart=") }))
        XCTAssertTrue(command.contains(where: { $0.hasPrefix("hooks.UserPromptSubmit=") }))
        XCTAssertTrue(command.contains(where: { $0.hasPrefix("hooks.Stop=") }))
        XCTAssertTrue(command.contains(where: { $0.contains("/tmp/hook path.py") }))
        XCTAssertTrue(command.contains("--model"))
        XCTAssertTrue(command.contains("gpt-5.1"))
    }
}

extension CodexStatusProviderTests {
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
                $0.name == "statusline.codex.hook_bound"
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
                $0.name == "statusline.codex.hook_bound"
                    && $0.attributes["hook_event_name"] == "Stop"
            })
    }
}

extension CodexStatusProviderTests {
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

    fileprivate func makeContext(processStartTime: Date, hookRecordPath: String? = nil) -> StatusProviderContext {
        StatusProviderContext(
            paneID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            paneName: "codex-pane",
            tabID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            tabName: "repo",
            workingDirectory: tempDir.path,
            harness: .codex,
            processStartTime: processStartTime,
            launchArgs: [],
            environment: [:],
            detectedHarnessVersion: "codex-cli 0.136.0",
            codexHookRecordPath: hookRecordPath ?? tempDir.appending(path: "hook-record.json").path,
            opencodePort: nil,
            opencodeSessionID: nil
        )
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
        """
        {"type":"event_msg","payload":{"type":"token_count","model":"\(model)","total_token_usage":{"input_tokens":\(input),"output_tokens":\(output)},"last_token_usage":{"total_tokens":\(contextTokens)},"model_context_window":\(window)}}
        """
        .appending("\n")
    }
}
