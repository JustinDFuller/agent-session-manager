import Darwin
import XCTest

@testable import AgentSessionManager

@MainActor
final class StatusLineMonitorInvariantTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TracingService.shared.enableTestCapture()
        InvariantReporter.shared.enableTestCapture()
    }

    override func tearDown() {
        super.tearDown()
        TracingService.shared.resetForTesting()
        InvariantReporter.shared.resetForTesting()
    }

    func testMigrationDropsWorktreeBranchWhenWorktreePresent() throws {
        let json = Data(
            """
            {
                "rows": [
                    {
                        "id": "33333333-3333-3333-3333-333333333333",
                        "items": [
                            {"id": "worktree", "label": "Worktree", "sfSymbol": "folder.badge.gearshape"},
                            {"id": "worktreeBranch", "label": "Worktree Branch", "sfSymbol": "arrow.branch"}
                        ]
                    }
                ],
                "factLabelStyle": "labelOnly",
                "rowAlignment": "leading"
            }
            """.utf8)
        let config = try JSONDecoder().decode(StatusLineConfig.self, from: json)
        XCTAssertFalse(config.usedItemIDs.contains("worktreeBranch"), "worktreeBranch must be migrated out")
        XCTAssertTrue(config.usedItemIDs.contains("worktree"))
        let events = TracingService.shared.recordedEventsForTesting
        let event = events.first { $0.name == "statusline.migration.worktreebranch_merged" }
        XCTAssertNotNil(event, "Expected migration trace event")
        XCTAssertEqual(event?.attributes["substituted"], "false")
        XCTAssertEqual(event?.attributes["row_index"], "0")
    }

    func testMigrationSubstitutesWorktreeBranchWhenWorktreeAbsent() throws {
        let json = Data(
            """
            {
                "rows": [
                    {
                        "id": "44444444-4444-4444-4444-444444444444",
                        "items": [
                            {"id": "model", "label": "Model", "sfSymbol": "cpu"},
                            {"id": "worktreeBranch", "label": "Worktree Branch", "sfSymbol": "arrow.branch"}
                        ]
                    }
                ],
                "factLabelStyle": "labelOnly",
                "rowAlignment": "leading"
            }
            """.utf8)
        let config = try JSONDecoder().decode(StatusLineConfig.self, from: json)
        XCTAssertFalse(config.usedItemIDs.contains("worktreeBranch"), "worktreeBranch must be migrated out")
        XCTAssertTrue(config.usedItemIDs.contains("worktree"), "worktree must be substituted in")
        XCTAssertTrue(config.usedItemIDs.contains("model"))
        let events = TracingService.shared.recordedEventsForTesting
        let event = events.first { $0.name == "statusline.migration.worktreebranch_merged" }
        XCTAssertNotNil(event, "Expected migration trace event")
        XCTAssertEqual(event?.attributes["substituted"], "true")
        XCTAssertEqual(event?.attributes["row_index"], "0")
        XCTAssertEqual(event?.attributes["position"], "1")
    }

    func testCodexFactsRemainInCurrentDataAfterProviderRefreshAndTraceOnlyPresence() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
        var codexSnapshot = StatusLineData.empty()
        codexSnapshot.model = StatusLineData.Model(id: "private-model-name", displayName: "private-model-name")
        codexSnapshot.contextWindow = StatusLineData.ContextWindow(
            usedPercentage: 8,
            remainingPercentage: 92,
            totalInputTokens: 92_892,
            totalOutputTokens: 28,
            contextWindowSize: 1_000_000
        )
        codexSnapshot.rateLimits = StatusLineData.RateLimits(
            fiveHour: StatusLineData.RateLimit(usedPercentage: 7, resetsAt: 2_000_000_000),
            sevenDay: nil,
            bucketID: "codex"
        )

        monitor.testApplyProviderSnapshot(codexSnapshot, providerName: "codex")

        var refreshedSnapshot = codexSnapshot
        refreshedSnapshot.version = "0.162.1"
        refreshedSnapshot.worktree = StatusLineData.Worktree(name: "worktree", branch: "main")
        monitor.testApplyProviderSnapshot(refreshedSnapshot, providerName: "codex")

        XCTAssertEqual(monitor.currentData?.model?.id, "private-model-name")
        XCTAssertEqual(monitor.currentData?.contextWindow?.usedPercentage, 8)
        XCTAssertEqual(monitor.currentData?.contextWindow?.totalInputTokens, 92_892)
        XCTAssertEqual(monitor.currentData?.contextWindow?.totalOutputTokens, 28)
        let update = TracingService.shared.recordedEventsForTesting.last {
            $0.name == "statusline.provider.update_applied"
        }
        XCTAssertEqual(update?.attributes["has_model"], "true")
        XCTAssertEqual(update?.attributes["has_context"], "true")
        XCTAssertEqual(update?.attributes["has_input_tokens"], "true")
        XCTAssertEqual(update?.attributes["has_output_tokens"], "true")
        XCTAssertEqual(update?.attributes["has_rate_limits"], "true")
        XCTAssertNil(update?.attributes["model"])
        XCTAssertNil(update?.attributes["input_tokens"])
    }

    func testMigrationDropsGitWorktreeAndTraces() throws {
        let json = Data(
            """
            {
                "rows": [
                    {
                        "id": "22222222-2222-2222-2222-222222222222",
                        "items": [
                            {"id": "model", "label": "Model", "sfSymbol": "cpu"},
                            {"id": "gitWorktree", "label": "Git Worktree", "sfSymbol": "internaldrive"}
                        ]
                    }
                ],
                "factLabelStyle": "labelOnly",
                "rowAlignment": "leading"
            }
            """.utf8)
        let config = try JSONDecoder().decode(StatusLineConfig.self, from: json)
        XCTAssertFalse(config.usedItemIDs.contains("gitWorktree"))
        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(events.contains { $0.name == "statusline.migration.gitworktree_dropped" })
    }

    func testI1WorktreeNameMismatchIsLogged() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("right-name")
            .path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let paneID = UUID()
        let monitor = StatusLineMonitor(
            paneID: paneID,
            workingDirectory: workDir,
            harness: .claude
        )

        let json = Data(
            """
            {"worktree": {"name": "wrong-name", "branch": "main"}}
            """.utf8)
        let parsed = try JSONDecoder().decode(StatusLineData.self, from: json)
        var enforced = parsed

        monitor.testApplyI1Enforcement(to: &enforced)

        XCTAssertEqual(enforced.worktree?.name, "right-name")
        let events = TracingService.shared.recordedEventsForTesting
        let mismatch = events.first { $0.name == "statusline.worktree.name_mismatch" }
        XCTAssertNotNil(mismatch, "Expected worktree.name_mismatch trace event")
        XCTAssertEqual(mismatch?.attributes["field"], "worktree.name")
        XCTAssertEqual(mismatch?.attributes["computed"], "right-name")
        XCTAssertEqual(mismatch?.attributes["reported"], "wrong-name")
        XCTAssertEqual(mismatch?.attributes["invariant.id"], "statusline.worktree.name")
    }

    func testI1WorktreeNameMatchDoesNotLog() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("right-name")
            .path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(
            paneID: UUID(),
            workingDirectory: workDir,
            harness: .claude
        )

        let json = Data(
            """
            {"worktree": {"name": "right-name", "branch": "main"}}
            """.utf8)
        let parsed = try JSONDecoder().decode(StatusLineData.self, from: json)
        var enforced = parsed

        monitor.testApplyI1Enforcement(to: &enforced)

        XCTAssertEqual(enforced.worktree?.name, "right-name")
        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertFalse(events.contains { $0.name == "statusline.worktree.name_mismatch" })
    }

    func testI1WorkspaceGitWorktreeMismatchIsLogged() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("right-name")
            .path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(
            paneID: UUID(),
            workingDirectory: workDir,
            harness: .claude
        )

        let json = Data(
            """
            {"workspace": {"git_worktree": "/some/completely/different-name"}}
            """.utf8)
        let parsed = try JSONDecoder().decode(StatusLineData.self, from: json)
        var enforced = parsed

        monitor.testApplyI1Enforcement(to: &enforced)

        let events = TracingService.shared.recordedEventsForTesting
        let mismatch = events.first {
            $0.name == "statusline.worktree.name_mismatch" && $0.attributes["field"] == "workspace.git_worktree"
        }
        XCTAssertNotNil(mismatch, "Expected workspace.git_worktree mismatch event")
        XCTAssertEqual(mismatch?.attributes["computed"], "right-name")
        XCTAssertEqual(mismatch?.attributes["invariant.id"], "statusline.worktree.name")
    }

    func testI3LinesMismatchIsLoggedAndOverwritten() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(
            paneID: UUID(),
            workingDirectory: workDir,
            harness: .claude
        )
        monitor.testSetCachedGitStats((added: 5, removed: 0))

        let json = Data(
            """
            {"cost": {"total_cost_usd": 0.01, "total_duration_ms": 1000, "total_lines_added": 999, "total_lines_removed": 0}}
            """.utf8)
        let parsed = try JSONDecoder().decode(StatusLineData.self, from: json)
        var enforced = parsed

        monitor.testApplyI3Enforcement(to: &enforced)

        XCTAssertEqual(enforced.cost?.totalLinesAdded, 5)
        XCTAssertEqual(enforced.cost?.totalLinesRemoved, 0)

        let events = TracingService.shared.recordedEventsForTesting
        let mismatch = events.first { $0.name == "statusline.lines.source_mismatch" }
        XCTAssertNotNil(mismatch, "Expected lines.source_mismatch trace event")
        XCTAssertEqual(mismatch?.attributes["invariant.id"], "statusline.lines.source")
        XCTAssertEqual(mismatch?.attributes["computed_added"], "5")
        XCTAssertEqual(mismatch?.attributes["reported_added"], "999")
        XCTAssertEqual(mismatch?.attributes["computed_removed"], "0")
        XCTAssertEqual(mismatch?.attributes["reported_removed"], "0")
    }

    func testI6StatusWatcherAppliesWritesAndAtomicReplacements() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)
        monitor.start()
        defer { monitor.stop() }

        try Data(#"{"worktree":{"name":"wrong-name","branch":"main"}}"#.utf8)
            .write(to: URL(filePath: monitor.filePath))
        let firstDeadline = Date().addingTimeInterval(2)
        while monitor.currentData == nil, Date() < firstDeadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(monitor.currentData?.worktree?.branch, "main")
        XCTAssertTrue(
            InvariantReporter.shared.violationsForTesting.contains {
                $0.invariantID == "statusline.worktree.name"
            }
        )

        try Data(#"{"worktree":{"name":"right-name","branch":"develop"}}"#.utf8)
            .write(to: URL(filePath: monitor.filePath), options: .atomic)
        let replacementDeadline = Date().addingTimeInterval(2)
        while monitor.currentData?.worktree?.branch != "develop", Date() < replacementDeadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(monitor.currentData?.worktree?.branch, "develop")
        XCTAssertTrue(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "statusline.watcher.lifecycle"
                    && $0.attributes["watcher.role"] == "status_payload"
                    && $0.attributes["result"] == "started"
            }
        )
    }

    func testI6FreshnessRecoveryAppliesLatestPayload() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)

        let earlyPayload = Data(
            """
            {"cost": {"total_cost_usd": 0.0}}
            """.utf8)
        try earlyPayload.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "initial")
        XCTAssertEqual(monitor.currentData?.cost?.totalCostUsd, 0.0)

        let laterPayload = Data(
            """
            {"cost": {"total_cost_usd": 5.28}, "context_window": {"used_percentage": 8}}
            """.utf8)
        try laterPayload.write(to: URL(filePath: monitor.filePath))
        let future = Date().addingTimeInterval(1)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: monitor.filePath)

        monitor.testCheckPayloadFreshness()

        XCTAssertEqual(monitor.currentData?.cost?.totalCostUsd, 5.28)
        XCTAssertEqual(monitor.currentData?.contextWindow?.usedPercentage, 8)

        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(
            events.contains { $0.name == "statusline.payload.stale_recovered" },
            "Expected stale_recovered trace event")
        XCTAssertTrue(
            events.contains {
                $0.name == "statusline.payload.applied" && $0.attributes["reason"] == "freshness_recovery"
            },
            "Expected applied event with reason freshness_recovery")
    }

    func testI6FreshnessNoRecoveryWhenUpToDate() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)

        let payload = Data(
            """
            {"cost": {"total_cost_usd": 1.23}}
            """.utf8)
        try payload.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "initial")
        TracingService.shared.resetForTesting()

        monitor.testCheckPayloadFreshness()

        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertFalse(
            events.contains { $0.name == "statusline.payload.stale_recovered" },
            "stale_recovered must not fire when already up to date")
    }

    func testI7ValidPayloadRecordsApplied() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)

        let payload = Data(
            """
            {"cost": {"total_cost_usd": 2.50}, "context_window": {"used_percentage": 15}}
            """.utf8)
        try payload.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "test")

        XCTAssertNotNil(monitor.currentData)
        XCTAssertEqual(monitor.currentData?.cost?.totalCostUsd, 2.50)

        let events = TracingService.shared.recordedEventsForTesting
        let applied = events.first { $0.name == "statusline.payload.applied" }
        XCTAssertNotNil(applied, "Expected payload.applied trace event")
        XCTAssertEqual(applied?.attributes["reason"], "test")
        XCTAssertEqual(applied?.attributes["cost_usd"], "2.5000")
        XCTAssertEqual(applied?.attributes["used_pct"], "15")
        XCTAssertFalse(events.contains { $0.name == "statusline.payload.decode_failed" })
    }

    func testI7MalformedPayloadRecordsDecodeFailedAndPreservesState() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)

        let good = Data(
            """
            {"cost": {"total_cost_usd": 1.00}}
            """.utf8)
        try good.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "initial")
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()

        let bad = Data("NOT JSON AT ALL !!!".utf8)
        try bad.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "test")

        XCTAssertEqual(monitor.currentData?.cost?.totalCostUsd, 1.00)

        let events = TracingService.shared.recordedEventsForTesting
        let failed = events.first { $0.name == "statusline.payload.decode_failed" }
        XCTAssertNotNil(failed, "Expected payload.decode_failed trace event")
        XCTAssertEqual(failed?.attributes["reason"], "test")
        XCTAssertEqual(failed?.attributes["decoding_error_kind"], "data_corrupted")
        XCTAssertFalse(events.contains { $0.name == "statusline.payload.applied" })
    }

    func testI7DecodingErrorNamesField() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)

        let payload = Data(#"{"repo": {"host": "github.com"}}"#.utf8)
        try payload.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "test")

        let events = TracingService.shared.recordedEventsForTesting
        let failed = events.first { $0.name == "statusline.payload.decode_failed" }
        XCTAssertNotNil(failed, "Expected decode_failed event")
        XCTAssertEqual(failed?.attributes["decoding_error_kind"], "key_not_found")
        XCTAssertNotNil(failed?.attributes["coding_path"])
        XCTAssertNotNil(failed?.attributes["missing_key"])
    }

    func testI7PayloadWithClaudePrBlockAppliesSuccessfully() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)

        let payload = Data(
            """
            {"model": {"id": "claude-sonnet-4-6"}, "pr": {"number": 42, "url": "https://github.com/org/repo/pull/42", "review_state": "draft"}}
            """.utf8)
        try payload.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "test")

        XCTAssertEqual(monitor.currentData?.model?.id, "claude-sonnet-4-6")
        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(events.contains { $0.name == "statusline.payload.applied" })
        XCTAssertFalse(events.contains { $0.name == "statusline.payload.decode_failed" })
    }

    func testI7GhPrDataPreservedWhenClaudeSendsPrBlock() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)

        let ghPR = Data(
            """
            {"number": 7, "title": "My feature", "state": "open", "url": "https://github.com/org/repo/pull/7"}
            """.utf8)
        monitor.simulatePRUpdateForTesting(ghPR)

        let claudePayload = Data(
            """
            {"model": {"id": "claude-sonnet-4-6"}, "pr": {"number": 7, "url": "https://github.com/org/repo/pull/7", "review_state": "approved"}}
            """.utf8)
        try claudePayload.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "test")

        XCTAssertEqual(monitor.currentData?.pr?.title, "My feature")
        XCTAssertEqual(monitor.currentData?.pr?.state, "open")
        XCTAssertEqual(monitor.currentData?.model?.id, "claude-sonnet-4-6")
    }

    func testI7EmptyFileSkippedWithoutClobbering() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)

        let good = Data(
            """
            {"cost": {"total_cost_usd": 3.75}}
            """.utf8)
        try good.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "initial")
        TracingService.shared.resetForTesting()

        try Data().write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "empty")

        XCTAssertEqual(monitor.currentData?.cost?.totalCostUsd, 3.75, "empty write must not clobber currentData")
        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertFalse(events.contains { $0.name == "statusline.payload.decode_failed" })
        XCTAssertFalse(events.contains { $0.name == "statusline.payload.applied" })
    }

    func testI7ContextWindowToleratesDoublePercentage() throws {
        let json = Data(
            """
            {"context_window": {"used_percentage": 14.000000000000002, "remaining_percentage": 85.999999999999998, "total_input_tokens": 140000, "total_output_tokens": 5}}
            """.utf8)
        let parsed = try JSONDecoder().decode(StatusLineData.self, from: json)
        XCTAssertEqual(parsed.contextWindow?.usedPercentage, 14)
        XCTAssertEqual(parsed.contextWindow?.remainingPercentage, 86)
        XCTAssertEqual(parsed.contextWindow?.totalInputTokens, 140000)
        XCTAssertEqual(parsed.contextWindow?.totalOutputTokens, 5)
    }

    func testI3LinesMatchDoesNotLog() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(
            paneID: UUID(),
            workingDirectory: workDir,
            harness: .claude
        )
        monitor.testSetCachedGitStats((added: 3, removed: 1))

        let json = Data(
            """
            {"cost": {"total_cost_usd": 0.01, "total_duration_ms": 1000, "total_lines_added": 3, "total_lines_removed": 1}}
            """.utf8)
        let parsed = try JSONDecoder().decode(StatusLineData.self, from: json)
        var enforced = parsed

        monitor.testApplyI3Enforcement(to: &enforced)

        XCTAssertEqual(enforced.cost?.totalLinesAdded, 3)
        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertFalse(events.contains { $0.name == "statusline.lines.source_mismatch" })
    }

    func testI3PreservesTotalApiDurationMs() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)
        monitor.testSetCachedGitStats((added: 0, removed: 0))

        let json = Data(
            """
            {"cost": {"total_cost_usd": 0.05, "total_duration_ms": 2000, "total_api_duration_ms": 1234.5}}
            """.utf8)
        let parsed = try JSONDecoder().decode(StatusLineData.self, from: json)
        var enforced = parsed

        monitor.testApplyI3Enforcement(to: &enforced)

        XCTAssertEqual(enforced.cost?.totalApiDurationMs, 1234.5, "totalApiDurationMs must survive I3 enforcement")
        XCTAssertEqual(enforced.cost?.totalCostUsd, 0.05)
    }

    func testRepoIdentityInjectedOnPayloadApply() throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)
        let repo = StatusLineData.Repo(host: "github.com", owner: "acme", name: "widget")
        monitor.testSetCachedRepoIdentity(repo)

        let payload = Data(#"{"cost": {"total_cost_usd": 0.0}}"#.utf8)
        try payload.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "test")

        XCTAssertEqual(monitor.currentData?.repo?.owner, "acme")
        XCTAssertEqual(monitor.currentData?.repo?.name, "widget")
        XCTAssertEqual(monitor.currentData?.repo?.host, "github.com")
    }

    func testRepoIdentityNilWhenNotCached() throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)

        let payload = Data(#"{"cost": {"total_cost_usd": 0.0}}"#.utf8)
        try payload.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "test")

        XCTAssertNil(monitor.currentData?.repo)
    }

    func testRepoIdentityUsesHTTPSAndSSHRemotesWithoutAuthentication() async throws {
        let repository = try GitTestRepository.make(withRemote: false)
        defer { repository.cleanUp() }
        let missingIdentity = await StatusLineMonitor.fetchRepoIdentity(workingDirectory: repository.root.path)
        XCTAssertNil(missingIdentity)
        try repository.git(["remote", "add", "origin", "https://github.com/acme/widget.git"])

        let httpsIdentity = await StatusLineMonitor.fetchRepoIdentity(workingDirectory: repository.root.path)
        XCTAssertEqual(httpsIdentity?.host, "github.com")
        XCTAssertEqual(httpsIdentity?.owner, "acme")
        XCTAssertEqual(httpsIdentity?.name, "widget")

        try repository.git(["remote", "set-url", "origin", "git@github.com:acme/widget.git"])
        let sshIdentity = await StatusLineMonitor.fetchRepoIdentity(workingDirectory: repository.root.path)
        XCTAssertEqual(sshIdentity?.host, "github.com")
        XCTAssertEqual(sshIdentity?.owner, "acme")
        XCTAssertEqual(sshIdentity?.name, "widget")

        try repository.git(["remote", "set-url", "origin", "file:///tmp/widget.git"])
        let unsupportedIdentity = await StatusLineMonitor.fetchRepoIdentity(workingDirectory: repository.root.path)
        XCTAssertNil(unsupportedIdentity)
    }

    func testRepositoryAndGitFactsMergeIntoSharedProviderSnapshots() throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let snapshot = try JSONDecoder().decode(
            StatusLineData.self,
            from: Data(
                """
                {"model":{"id":"gpt-5.1","display_name":"GPT-5.1"},"context_window":{"used_percentage":48,"remaining_percentage":52},"cost":{"total_cost_usd":0.01,"total_lines_added":1,"total_lines_removed":0}}
                """.utf8)
        )
        let identity = StatusLineData.Repo(host: "github.com", owner: "acme", name: "widget")

        for harness in [Harness.codex, .cursor, .opencode, .shell] {
            let monitor = StatusLineMonitor(
                paneID: UUID(),
                workingDirectory: workingDirectory.path,
                harness: harness
            )
            monitor.testSetCachedRepoIdentity(identity)
            monitor.testSetCachedGitStats((added: 7, removed: 2))

            monitor.testApplyProviderSnapshot(snapshot)

            XCTAssertEqual(monitor.currentData?.repo?.owner, "acme")
            XCTAssertEqual(monitor.currentData?.repo?.name, "widget")
            XCTAssertEqual(monitor.currentData?.model?.id, "gpt-5.1")
            XCTAssertEqual(monitor.currentData?.contextWindow?.usedPercentage, 48)
            XCTAssertEqual(monitor.currentData?.worktree?.name, workingDirectory.lastPathComponent)
            XCTAssertEqual(monitor.currentData?.cost?.totalLinesAdded, 7)
            XCTAssertEqual(monitor.currentData?.cost?.totalLinesRemoved, 2)
        }
    }

    func testCustomFieldsMergedIntoCurrentDataOnClaudePayloadApply() throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)
        monitor.testSetCachedCustomFieldValues([
            "custom:abc": CustomFieldRenderValue(text: "hello", percent: nil, tint: nil, icon: nil)
        ])

        let payload = Data(#"{"cost": {"total_cost_usd": 1.0}}"#.utf8)
        try payload.write(to: URL(filePath: monitor.filePath))
        monitor.testApplyLatestPayload(reason: "test")

        XCTAssertEqual(monitor.currentData?.customFields?["custom:abc"]?.text, "hello")
    }

    func testCustomFieldsMergedIntoCurrentDataOnProviderSnapshot() throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .cursor)
        monitor.testSetCachedCustomFieldValues([
            "custom:xyz": CustomFieldRenderValue(text: nil, percent: 42, tint: .warning, icon: nil)
        ])

        monitor.testApplyProviderSnapshot(.empty())

        XCTAssertEqual(monitor.currentData?.customFields?["custom:xyz"]?.percent, 42)
        XCTAssertEqual(monitor.currentData?.customFields?["custom:xyz"]?.tint, .warning)
    }

    func testCustomFieldSuccessInitializesCurrentDataWhenProviderHasNotPublished() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        let field = CustomStatusLineField(id: "custom:first", label: "First", command: "echo first")

        monitor.testApplyCustomFieldResult(
            field: field,
            result: .success(
                CustomFieldRenderValue(text: "first", percent: nil, tint: nil, icon: nil),
                outputKind: .text
            )
        )

        XCTAssertEqual(monitor.currentData?.customFields?["custom:first"]?.text, "first")
    }

    func testUnsupportedHarnessDoesNotScheduleCustomField() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        let field = CustomStatusLineField(
            id: "custom:cursor-only",
            label: "Cursor only",
            command: "echo cursor",
            supportedHarnesses: [.cursor]
        )

        monitor.setCustomFields([field])

        XCTAssertNil(monitor.cachedCustomFieldValuesForTesting[field.id])
    }

    func testCustomFieldFailureRetainsPriorValueAndRecordsExecFailed() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        let field = CustomStatusLineField(id: "custom:b", label: "B", command: "exit 1")

        monitor.testApplyCustomFieldResult(
            field: field,
            result: .success(
                CustomFieldRenderValue(text: "good", percent: nil, tint: nil, icon: nil), outputKind: .text)
        )
        XCTAssertEqual(monitor.cachedCustomFieldValuesForTesting["custom:b"]?.text, "good")

        monitor.testApplyCustomFieldResult(
            field: field,
            result: .failure(
                CustomFieldExecutionError(
                    reason: .nonzeroExit,
                    exitCode: 1,
                    inputFailure: nil)))

        XCTAssertEqual(
            monitor.cachedCustomFieldValuesForTesting["custom:b"]?.text, "good",
            "a failed execution must never revert a previously-good value")

        let events = TracingService.shared.recordedEventsForTesting
        let failed = events.first { $0.name == "statusline.custom_field.exec_failed" }
        XCTAssertNotNil(failed)
        XCTAssertEqual(failed?.attributes["reason"], "nonzero_exit")
        XCTAssertEqual(failed?.attributes["retained_prior_value"], "true")
        XCTAssertEqual(failed?.attributes["exit_code"], "1")
        XCTAssertEqual(failed?.attributes["trigger"], "scheduled")
    }

    func testCustomFieldSuccessRecordsExecSucceeded() {
        let paneID = UUID()
        let tabID = UUID()
        let monitor = StatusLineMonitor(
            paneID: paneID,
            paneName: "test-pane",
            harness: .claude,
            tabID: tabID,
            tabName: "test-tab"
        )
        let field = CustomStatusLineField(id: "custom:c", label: "C", command: "echo hi")

        monitor.testApplyCustomFieldResult(
            field: field,
            result: .success(CustomFieldRenderValue(text: "hi", percent: nil, tint: nil, icon: nil), outputKind: .text)
        )

        let events = TracingService.shared.recordedEventsForTesting
        let succeeded = events.first { $0.name == "statusline.custom_field.exec_succeeded" }
        XCTAssertNotNil(succeeded)
        XCTAssertEqual(succeeded?.attributes["output_kind"], "text")
        XCTAssertEqual(succeeded?.attributes["field_id"], "custom:c")
        XCTAssertEqual(succeeded?.attributes["trigger"], "scheduled")
        XCTAssertEqual(succeeded?.attributes["pane.id"], paneID.uuidString)
        XCTAssertEqual(succeeded?.attributes["pane.name"], "test-pane")
        XCTAssertEqual(succeeded?.attributes["tab.id"], tabID.uuidString)
        XCTAssertEqual(succeeded?.attributes["tab.name"], "test-tab")
    }

    func testManualCustomFieldRunUpdatesCacheAndRecordsManualTrigger() async {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try? FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(
            paneID: UUID(), workingDirectory: workDir, harness: .claude)
        let field = CustomStatusLineField(
            id: "custom:manual", label: "Manual", command: "sleep 0.2; echo manual")

        XCTAssertEqual(monitor.runCustomFieldNow(field), .started)
        XCTAssertEqual(monitor.runCustomFieldNow(field), .coalesced)
        let resolved = await Self.pollUntilTrue {
            monitor.cachedCustomFieldValuesForTesting[field.id]?.text == "manual"
        }

        XCTAssertTrue(resolved, "expected manual custom field run to resolve")
        let event = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "statusline.custom_field.exec_succeeded"
                && $0.attributes["field_id"] == field.id
        }
        XCTAssertEqual(event?.attributes["trigger"], "manual")
        monitor.stop()
    }

    func testAppStateRunNowUsesSavedGlobalFieldAndRealPaneMonitor() async {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let settings = AppSettings()
        let field = CustomStatusLineField(
            id: "custom:global-run",
            label: "Global",
            command: "echo global",
            supportedHarnesses: [.claude]
        )
        settings.statusLineConfig.customFields = [field]

        let tab = Tab(name: "Run Now", directory: workDir)
        let pane = Pane(
            name: "global-pane",
            tab: tab,
            harness: .claude,
            worktreeDirectory: workDir,
            appSettings: settings
        )
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: workDir.path,
            harness: .claude,
            tabID: tab.id,
            tabName: tab.name
        )
        pane.installStatusLineMonitor(monitor)
        tab.panes = [pane]

        let appState = AppState()
        appState.tabs = [tab]
        let summary = appState.runSavedStatusLineFieldNow(
            fieldID: field.id, profileID: nil, appSettings: settings)
        let resolved = await Self.pollUntilTrue {
            monitor.cachedCustomFieldValuesForTesting[field.id]?.text == "global"
        }

        XCTAssertEqual(summary, "Started in 1 pane.")
        XCTAssertTrue(resolved, "expected the saved global field to run in the real pane monitor")
        let runNow = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "statusline.custom_field.run_now"
        }
        XCTAssertEqual(runNow?.attributes["target_count"], "1")
        XCTAssertEqual(runNow?.attributes["scope"], "global")
        XCTAssertEqual(runNow?.attributes["started_count"], "1")
        XCTAssertEqual(runNow?.attributes["coalesced_count"], "0")
        XCTAssertEqual(runNow?.attributes["result"], "started")
        monitor.stop()
    }

    func testStaleCustomFieldResultCannotOverwriteNewCommand() async {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try? FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(
            paneID: UUID(), workingDirectory: workDir, harness: .claude)
        let oldField = CustomStatusLineField(
            id: "custom:stale",
            label: "Stale",
            command: "sleep 0.2; printf old",
            timeoutSeconds: 2
        )
        let newField = CustomStatusLineField(
            id: oldField.id,
            label: oldField.label,
            command: "printf new",
            timeoutSeconds: 2
        )

        monitor.setCustomFields([oldField])
        monitor.setCustomFields([newField])
        let resolved = await Self.pollUntilTrue {
            monitor.cachedCustomFieldValuesForTesting[newField.id]?.text == "new"
        }
        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertTrue(resolved, "expected the replacement command to resolve")
        XCTAssertEqual(monitor.cachedCustomFieldValuesForTesting[newField.id]?.text, "new")
        let stale = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "statusline.custom_field.exec_stale"
        }
        XCTAssertNotNil(stale)
        XCTAssertEqual(stale?.attributes["trigger"], "scheduled")
        monitor.stop()
    }

    func testProfileRunNowThreadsResolvedProfileNameIntoCommandContext() async {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let settings = AppSettings()
        let field = CustomStatusLineField(
            id: "custom:profile-context",
            label: "Profile",
            command: "echo $AGENT_SESSION_MANAGER_PROFILE_NAME",
            supportedHarnesses: [.claude]
        )
        var profileConfig = StatusLineConfig()
        profileConfig.customFields = [field]
        let profile = Profile(
            name: "Profile Context",
            harness: .claude,
            statusLineConfig: profileConfig
        )
        settings.profiles = [profile]

        let tab = Tab(name: "Profile Run Now", directory: workDir)
        let pane = Pane(
            name: "profile-pane",
            tab: tab,
            harness: .claude,
            worktreeDirectory: workDir,
            profileID: profile.id,
            appSettings: settings
        )
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: workDir.path,
            harness: .claude,
            tabID: tab.id,
            tabName: tab.name
        )
        pane.installStatusLineMonitor(monitor)
        tab.panes = [pane]

        let appState = AppState()
        appState.tabs = [tab]
        let summary = appState.runSavedStatusLineFieldNow(
            fieldID: field.id, profileID: profile.id, appSettings: settings)
        let resolved = await Self.pollUntilTrue {
            monitor.cachedCustomFieldValuesForTesting[field.id]?.text == "Profile Context"
        }

        XCTAssertEqual(summary, "Started in 1 pane.")
        XCTAssertTrue(resolved, "expected the profile name to reach the saved command")
        monitor.stop()
    }

    func testCustomFieldInputFailureRecordsBoundedPipeDetails() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        let field = CustomStatusLineField(id: "custom:pipe", label: "Pipe", command: "true")

        monitor.testApplyCustomFieldResult(
            field: field,
            result: .failure(
                CustomFieldExecutionError(
                    reason: .stdinWrite,
                    exitCode: nil,
                    inputFailure: ChildProcessInputWriteFailure(
                        stage: .write,
                        errorCode: EPIPE))))

        let failed = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "statusline.custom_field.exec_failed"
        }
        XCTAssertEqual(failed?.attributes["reason"], "stdin_write")
        XCTAssertEqual(failed?.attributes["input_failure_stage"], "write")
        XCTAssertEqual(failed?.attributes["input_error_code"], String(EPIPE))
    }

    func testManualCustomFieldFailureRecordsManualTriggerAndBoundedPipeDetails() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        let field = CustomStatusLineField(id: "custom:manual-pipe", label: "Manual pipe", command: "true")

        monitor.testApplyCustomFieldResult(
            field: field,
            result: .failure(
                CustomFieldExecutionError(
                    reason: .stdinWrite,
                    exitCode: nil,
                    inputFailure: ChildProcessInputWriteFailure(
                        stage: .write,
                        errorCode: EPIPE))),
            trigger: "manual")

        let failed = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "statusline.custom_field.exec_failed"
        }
        XCTAssertEqual(failed?.attributes["trigger"], "manual")
        XCTAssertEqual(failed?.attributes["input_failure_stage"], "write")
        XCTAssertEqual(failed?.attributes["input_error_code"], String(EPIPE))
    }

    func testSetCustomFieldsRemovesCachedValueWhenFieldRemoved() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        let field = CustomStatusLineField(id: "custom:a", label: "A", command: "echo hi")

        monitor.setCustomFields([field])
        monitor.testApplyCustomFieldResult(
            field: field,
            result: .success(CustomFieldRenderValue(text: "hi", percent: nil, tint: nil, icon: nil), outputKind: .text)
        )
        XCTAssertEqual(monitor.cachedCustomFieldValuesForTesting["custom:a"]?.text, "hi")

        monitor.setCustomFields([])

        XCTAssertNil(
            monitor.cachedCustomFieldValuesForTesting["custom:a"], "removing a field must drop its cached value")
        XCTAssertNil(monitor.currentData?.customFields?["custom:a"])
    }

    func testProfileNameThreadedIntoCustomFieldEnvironment() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(paneID: UUID(), workingDirectory: workDir, harness: .claude)
        monitor.profileName = "Backend"
        let field = CustomStatusLineField(
            id: "custom:profile", label: "Profile",
            command: "echo $AGENT_SESSION_MANAGER_PROFILE_NAME",
            refreshIntervalSeconds: 5, timeoutSeconds: 5)
        monitor.setCustomFields([field])

        let resolved = await Self.pollUntilTrue {
            monitor.cachedCustomFieldValuesForTesting["custom:profile"] != nil
        }
        let resolvedText = monitor.cachedCustomFieldValuesForTesting["custom:profile"]?.text
        monitor.stop()

        XCTAssertTrue(resolved, "expected the custom field to resolve within the timeout")
        XCTAssertEqual(resolvedText, "Backend")
        let started = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "statusline.custom_field.exec_started"
        }
        XCTAssertEqual(started?.attributes["field_id"], "custom:profile")
        XCTAssertEqual(started?.attributes["trigger"], "scheduled")
    }

    func testPaneEnvironmentThreadedIntoCustomFieldEnvironment() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: workDir) }

        let monitor = StatusLineMonitor(
            paneID: UUID(),
            workingDirectory: workDir,
            harness: .claude,
            customFieldEnvironment: ["CUSTOM_FIELD_TEST_VALUE": "from-pane"]
        )
        let field = CustomStatusLineField(
            id: "custom:pane-environment",
            label: "Pane environment",
            command: "printf '%s' \"$CUSTOM_FIELD_TEST_VALUE\"",
            refreshIntervalSeconds: 5,
            timeoutSeconds: 5
        )
        monitor.setCustomFields([field])

        let resolved = await Self.pollUntilTrue {
            monitor.cachedCustomFieldValuesForTesting[field.id]?.text == "from-pane"
        }
        monitor.stop()

        XCTAssertTrue(resolved, "expected the pane environment to reach the custom field")
    }

    private static func pollUntilTrue(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
}
