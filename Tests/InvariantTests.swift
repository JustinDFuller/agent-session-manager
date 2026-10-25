import XCTest

@testable import AgentSessionManager

@MainActor
final class InvariantTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appending(path: "invariant-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        InvariantReporter.shared.resetForTesting()
        TracingService.shared.resetForTesting()
    }

    override func tearDown() {
        InvariantReporter.shared.resetForTesting()
        TracingService.shared.resetForTesting()
        try? FileManager.default.removeItem(at: directory)
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        super.tearDown()
    }

    func testReporterCapturesRepeatedViolationsWithDistinctOccurrences() {
        InvariantReporter.shared.enableTestCapture()
        InvariantReporter.shared.violated(.statusLineWorktreeName)
        InvariantReporter.shared.violated(.statusLineWorktreeName)

        let violations = InvariantReporter.shared.violationsForTesting
        XCTAssertEqual(violations.map(\.invariantID), ["statusline.worktree.name", "statusline.worktree.name"])
        XCTAssertNotEqual(violations[0].id, violations[1].id)
    }

    func testReporterRoutesLegacyTraceEventWhenFileOutputDisabled() {
        TracingService.shared.enableTestCapture()
        InvariantReporter.shared.violated(
            .statusLineWorktreeName,
            context: ["invariant.id": "caller-value", "field": "worktree.name"]
        )

        let event = TracingService.shared.recordedEventsForTesting.first
        XCTAssertEqual(event?.name, "statusline.worktree.name_mismatch")
        XCTAssertEqual(event?.attributes["invariant.id"], "statusline.worktree.name")
        XCTAssertEqual(event?.attributes["field"], "worktree.name")
    }

    func testCodexContinuationIdentityInvariantHasExpectedCatalogValues() {
        XCTAssertEqual(Invariant.codexContinuationIdentity.id, "codex.continuation.identity")
        XCTAssertEqual(Invariant.codexContinuationIdentity.integration, "Codex")
        XCTAssertEqual(Invariant.codexContinuationIdentity.severity, .warning)
        XCTAssertEqual(
            Invariant.codexContinuationIdentity.traceEventName,
            "session.pane.codex_identity.mismatch")
    }

    func testCodexContinuationIdentityInvariantEmitsBoundedMismatchContext() {
        InvariantReporter.shared.enableTestCapture()
        InvariantReporter.shared.violated(
            .codexContinuationIdentity,
            context: [
                "requested_session_id_prefix": "requested-123",
                "bound_session_id_prefix": "bound-456",
            ])

        let violation = InvariantReporter.shared.violationsForTesting.first
        XCTAssertEqual(violation?.invariantID, "codex.continuation.identity")
        XCTAssertEqual(violation?.context["requested_session_id_prefix"], "requested-123")
        XCTAssertEqual(violation?.context["bound_session_id_prefix"], "bound-456")
    }

    func testOpenCodePortPolicyInvariantHasExpectedCatalogValues() {
        XCTAssertEqual(Invariant.opencodePortPolicy.id, "opencode.port.policy")
        XCTAssertEqual(Invariant.opencodePortPolicy.integration, "OpenCode")
        XCTAssertEqual(Invariant.opencodePortPolicy.severity, .error)
        XCTAssertEqual(Invariant.opencodePortPolicy.traceEventName, "opencode.port.policy_violated")
    }

    func testOpenCodeSessionRebindableInvariantHasExpectedCatalogValues() {
        XCTAssertEqual(Invariant.opencodeSessionRebindable.id, "opencode.session.rebindable")
        XCTAssertEqual(Invariant.opencodeSessionRebindable.integration, "OpenCode")
        XCTAssertEqual(Invariant.opencodeSessionRebindable.severity, .warning)
        XCTAssertEqual(Invariant.opencodeSessionRebindable.traceEventName, "opencode.session.rebindable_violated")
    }

    func testOpenCodeTUIEndpointsUnusedInvariantHasExpectedCatalogValues() {
        XCTAssertEqual(Invariant.opencodeTUIEndpointsUnused.id, "opencode.tui.endpoints_unused")
        XCTAssertEqual(Invariant.opencodeTUIEndpointsUnused.integration, "OpenCode")
        XCTAssertEqual(Invariant.opencodeTUIEndpointsUnused.severity, .error)
        XCTAssertEqual(Invariant.opencodeTUIEndpointsUnused.traceEventName, "opencode.tui.endpoint_forbidden")
    }

    func testOpenCodeTUIEndpointInvariantEmitsTraceEvent() {
        TracingService.shared.enableTestCapture()
        InvariantReporter.shared.violated(
            .opencodeTUIEndpointsUnused,
            context: ["path": "/tui/submit-prompt", "method": "POST"]
        )

        let event = TracingService.shared.recordedEventsForTesting.first
        XCTAssertEqual(event?.name, "opencode.tui.endpoint_forbidden")
        XCTAssertEqual(event?.attributes["invariant.id"], "opencode.tui.endpoints_unused")
        XCTAssertEqual(event?.attributes["path"], "/tui/submit-prompt")
    }

    func testCursorAgentControlBridgeAvailableInvariantHasExpectedCatalogValues() {
        XCTAssertEqual(Invariant.cursorAgentControlBridgeAvailable.id, "cursor.agent_control.bridge_available")
        XCTAssertEqual(Invariant.cursorAgentControlBridgeAvailable.integration, "Cursor")
        XCTAssertEqual(Invariant.cursorAgentControlBridgeAvailable.severity, .error)
        XCTAssertEqual(
            Invariant.cursorAgentControlBridgeAvailable.traceEventName, "cursor.agent_control.bridge_missing")
    }

    func testCursorAgentControlBridgeAvailableCheckPassesWithoutViolationWhenExecutable() {
        InvariantReporter.shared.enableTestCapture()

        XCTAssertTrue(
            InvariantReporter.shared.check(.cursorAgentControlBridgeAvailable, true, context: ["path": "/tmp/bridge"]))
        XCTAssertTrue(InvariantReporter.shared.violationsForTesting.isEmpty)
    }

    func testCursorAgentControlBridgeAvailableCheckReportsViolationWhenMissing() {
        InvariantReporter.shared.enableTestCapture()

        XCTAssertFalse(
            InvariantReporter.shared.check(
                .cursorAgentControlBridgeAvailable, false, context: ["pane_id": "abc", "path": "/tmp/bridge"]))
        let violation = InvariantReporter.shared.violationsForTesting.first
        XCTAssertEqual(violation?.invariantID, "cursor.agent_control.bridge_available")
        XCTAssertEqual(violation?.context["pane_id"], "abc")
        XCTAssertNil(violation?.context["token"])
        XCTAssertNil(violation?.context["endpoint"])
    }

    func testBundleIdentityPreferredURLMatchingPathPassesWithoutViolation() {
        InvariantReporter.shared.enableTestCapture()
        let runningURL = URL(filePath: "/tmp/AgentSessionManager.app")

        XCTAssertTrue(
            BundleIdentityVerifier.checkPreferredURL(
                runningURL: runningURL,
                preferredURL: runningURL,
                bundleIdentifier: "com.justinfuller.agent-session-manager"))
        XCTAssertTrue(InvariantReporter.shared.violationsForTesting.isEmpty)
    }

    func testBundleIdentityPreferredURLMismatchReportsInvariant() {
        InvariantReporter.shared.enableTestCapture()

        XCTAssertFalse(
            BundleIdentityVerifier.checkPreferredURL(
                runningURL: URL(filePath: "/tmp/current/AgentSessionManager.app"),
                preferredURL: URL(filePath: "/tmp/stale/AgentSessionManager.app"),
                bundleIdentifier: "com.justinfuller.agent-session-manager"))
        let violation = InvariantReporter.shared.violationsForTesting.first
        XCTAssertEqual(violation?.invariantID, "app.bundle_identity.preferred_url")
        XCTAssertEqual(violation?.context["preferred.url"], "/tmp/stale/AgentSessionManager.app")
    }

    func testWriterSynchronouslyAppendsMetadataAndViolation() throws {
        let writer = InvariantLogWriter(directory: directory, maxBytes: 10_000)
        try writer.append(InvariantViolation(invariant: .statusLineLinesSource, context: ["key": "value"]))

        let content = try String(contentsOf: writer.fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("\"_type\":\"metadata\""))
        XCTAssertTrue(content.contains("\"invariantID\":\"statusline.lines.source\""))
    }

    func testWriterTrimsWithInvariantMarker() throws {
        let writer = InvariantLogWriter(directory: directory, maxBytes: 500)
        for index in 0..<20 {
            try writer.append(
                InvariantViolation(
                    invariant: .statusLineLinesSource,
                    context: ["payload": String(repeating: "\(index)", count: 80)]
                )
            )
        }
        let content = try String(contentsOf: writer.fileURL, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix(InvariantLogWriter.truncationMarker))
    }

    func testReporterStoresWriteError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocked = directory.appending(path: "blocked")
        try Data("file".utf8).write(to: blocked)
        InvariantReporter.shared.writer = InvariantLogWriter(directory: blocked, maxBytes: 10_000)

        InvariantReporter.shared.violated(.statusLineWorktreeName)

        XCTAssertNotNil(InvariantReporter.shared.latestWriterError)
    }

    func testRepositoryParsingSkipsMetadataMarkerAndMalformedLines() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let older = InvariantViolation(
            invariant: .statusLineWorktreeName, context: [:], timestamp: Date(timeIntervalSince1970: 1))
        let newer = InvariantViolation(
            invariant: .statusLineWorktreeName, context: [:], timestamp: Date(timeIntervalSince1970: 2))
        let content = [
            "{\"_type\":\"metadata\",\"schemaVersion\":1}",
            InvariantLogWriter.truncationMarker,
            "bad-json",
            String(decoding: try encoder.encode(older), as: UTF8.self),
            String(decoding: try encoder.encode(newer), as: UTF8.self),
        ].joined(separator: "\n")

        let parsed = InvariantRepository.parse(content)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(Set(parsed.map(\.invariantID)), ["statusline.worktree.name"])
        XCTAssertNotEqual(parsed[0].id, parsed[1].id)
    }

    func testRepositoryAttachesWhenFileAppearsAndFollowsReplacement() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = InvariantRepository(directory: directory)
        repository.start()
        XCTAssertNotNil(repository.watcherError)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let first = InvariantViolation(
            invariant: .statusLineWorktreeName,
            context: [:],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let file = directory.appending(path: "invariants.jsonl")
        try encoder.encode(first).write(to: file, options: .atomic)
        let firstDeadline = Date().addingTimeInterval(2)
        while repository.violations.first?.id != first.id, Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(repository.violations.first?.id, first.id)
        XCTAssertNil(repository.watcherError)

        let second = InvariantViolation(
            invariant: .statusLineLinesSource,
            context: [:],
            timestamp: Date(timeIntervalSince1970: 2)
        )
        try encoder.encode(second).write(to: file, options: .atomic)
        let secondDeadline = Date().addingTimeInterval(2)
        while repository.violations.first?.id != second.id, Date() < secondDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(repository.violations.first?.id, second.id)

        try FileManager.default.removeItem(at: file)
        let deletionDeadline = Date().addingTimeInterval(2)
        while !repository.violations.isEmpty, Date() < deletionDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(repository.violations.isEmpty)
        XCTAssertNotNil(repository.watcherError)
    }

    func testDebugSettingsPersistenceUsesVersionedSchemaAndRejectsLegacySchema() throws {
        let subdirectory = "debug-settings-tests-\(UUID().uuidString)"
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: subdirectory)
        defer { try? FileManager.default.removeItem(at: support) }

        let settings = AppSettings()
        settings.debugModeEnabled = true
        SettingsPersistence.save(
            SettingsPersistence.DebugSettings(schemaVersion: 1, enabled: settings.debugModeEnabled),
            to: "debug-settings.json")
        settings.debugModeEnabled = false
        if let saved = SettingsPersistence.load(SettingsPersistence.DebugSettings.self, from: "debug-settings.json"),
            saved.schemaVersion == 1
        {
            settings.debugModeEnabled = saved.enabled
        }
        XCTAssertTrue(settings.debugModeEnabled)

        try Data("{\"enabled\":false}".utf8).write(to: support.appending(path: "debug-settings.json"))
        settings.debugModeEnabled = true
        if let saved = SettingsPersistence.load(SettingsPersistence.DebugSettings.self, from: "debug-settings.json"),
            saved.schemaVersion == 1
        {
            settings.debugModeEnabled = saved.enabled
        }
        XCTAssertTrue(settings.debugModeEnabled, "Legacy schema must be ignored")
    }
}
