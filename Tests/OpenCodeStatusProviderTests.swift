import XCTest

@testable import AgentSessionManager

@MainActor
final class OpenCodeStatusProviderTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-opencode-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        InvariantReporter.shared.resetForTesting()
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        InvariantReporter.shared.resetForTesting()
        TracingService.shared.resetForTesting()
        super.tearDown()
    }

    private func makeContext(
        workingDirectory: String? = nil,
        processStartTime: Date = Date(),
        opencodePort: Int? = 41617,
        opencodeSessionID: String? = nil
    ) -> StatusProviderContext {
        StatusProviderContext(
            paneID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            paneName: "opencode-pane",
            tabID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            tabName: "repo",
            workingDirectory: workingDirectory ?? tempDir.path,
            harness: .opencode,
            processStartTime: processStartTime,
            launchArgs: [],
            environment: [:],
            detectedHarnessVersion: nil,
            codexHookRecordPath: nil,
            opencodePort: opencodePort,
            opencodeSessionID: opencodeSessionID
        )
    }

    private static func makeSession(
        id: String = "ses_test",
        directory: String? = nil,
        title: String? = nil,
        created: Int64,
        status: String? = nil,
        cost: Double? = 0.42,
        tokens: OpenCodeSessionTokens? = nil,
        model: OpenCodeSessionModel? = nil,
        version: String? = "1.17.20"
    ) -> OpenCodeSession {
        OpenCodeSession(
            id: id,
            title: title,
            directory: directory,
            parentID: nil,
            status: status,
            cost: cost,
            tokens: tokens ?? OpenCodeSessionTokens(input: 100, output: 50, reasoning: 10, cacheRead: 5, cacheWrite: 2),
            model: model ?? OpenCodeSessionModel(id: "k2.7", providerID: "openai", variant: nil),
            version: version,
            time: OpenCodeSessionTime(created: created, updated: created)
        )
    }

    private final class FakeClient: OpenCodeServerClient, @unchecked Sendable {
        nonisolated(unsafe) private let sessionsByIDLock = NSLock()
        nonisolated(unsafe) private var storedSessionsByID: [String: OpenCodeSession] = [:]
        nonisolated(unsafe) var healthResult: Result<(healthy: Bool, version: String?), Error> = .success(
            (true, "1.17.20"))
        nonisolated(unsafe) var sessions: [OpenCodeSession] = []
        nonisolated(unsafe) var sessionsByID: [String: OpenCodeSession] {
            get { sessionsByIDLock.withLock { storedSessionsByID } }
            set { sessionsByIDLock.withLock { storedSessionsByID = newValue } }
        }
        nonisolated(unsafe) var sessionRequestCount = 0
        nonisolated(unsafe) var renameRequests: [(id: String, title: String)] = []
        nonisolated(unsafe) var renamedSessions: [String: OpenCodeSession] = [:]
        nonisolated(unsafe) var eventStream: Result<AsyncThrowingStream<OpenCodeEvent, Error>, Error>?
        nonisolated(unsafe) var eventStreamRequests: [Void] = []

        func health() async throws -> (healthy: Bool, version: String?) {
            try healthResult.get()
        }

        func listSessions() async throws -> [OpenCodeSession] {
            sessions
        }

        func session(_ id: String) async throws -> OpenCodeSession {
            sessionRequestCount += 1
            guard let session = sessionsByID[id] else {
                throw OpenCodeServerClientError.unexpectedStatus(404)
            }
            return session
        }

        func rename(_ id: String, title: String) async throws -> OpenCodeSession {
            renameRequests.append((id, title))
            if let renamed = renamedSessions[id] {
                return renamed
            }
            let original = try await session(id)
            let updated = OpenCodeSession(
                id: original.id,
                title: title,
                directory: original.directory,
                parentID: original.parentID,
                status: original.status,
                cost: original.cost,
                tokens: original.tokens,
                model: original.model,
                version: original.version,
                time: original.time
            )
            renamedSessions[id] = updated
            sessionsByID[id] = updated
            return updated
        }

        func events() -> AsyncThrowingStream<OpenCodeEvent, Error> {
            eventStreamRequests.append(())
            guard let eventStream else {
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: OpenCodeServerClientError.unexpectedStatus(0))
                }
            }
            do {
                return try eventStream.get()
            } catch {
                return AsyncThrowingStream { continuation in
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func testVersionAdapterNormalizesOpenCodeVersion() {
        XCTAssertEqual(OpenCodeVersionAdapter.normalize("1.17.20"), "1.17.20")
        XCTAssertEqual(OpenCodeVersionAdapter.normalize("opencode 1.17.20"), "1.17.20")
        XCTAssertEqual(OpenCodeVersionAdapter.normalize("opencode1.17.20"), "1.17.20")
        XCTAssertNil(OpenCodeVersionAdapter.normalize(nil))
        XCTAssertNil(OpenCodeVersionAdapter.normalize("   "))
    }

    func testProviderEmitsMergedDataAfterBindingAndPoll() throws {
        let processStart = Date()
        let client = FakeClient()
        let session = Self.makeSession(
            id: "ses_one",
            directory: tempDir.path,
            created: Int64(processStart.timeIntervalSince1970 * 1000)
        )
        client.sessions = [session]
        client.sessionsByID[session.id] = session

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 0.05
        )

        let expectation = XCTestExpectation(description: "provider emits merged data")
        var observed: StatusLineData?
        provider.onUpdate = { data in
            if data.model != nil && data.cost != nil {
                observed = data
                expectation.fulfill()
            }
        }

        provider.start()
        wait(for: [expectation], timeout: 3)
        provider.stop()

        XCTAssertEqual(observed?.model?.id, "k2.7")
        XCTAssertEqual(observed?.model?.displayName, "openai/k2.7")
        XCTAssertEqual(observed?.cost?.totalCostUsd, 0.42)
        XCTAssertEqual(observed?.contextWindow?.totalInputTokens, 100)
        XCTAssertEqual(observed?.contextWindow?.totalOutputTokens, 50)
        XCTAssertEqual(observed?.version, "1.17.20")
        XCTAssertEqual(observed?.sessionName, "repo/opencode-pane")
        XCTAssertEqual(observed?.worktree?.name, tempDir.lastPathComponent)
    }

    func testProviderSelectsSessionClosestToProcessStart() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let older = Self.makeSession(id: "ses_older", directory: tempDir.path, created: processStartMs - 5000)
        let closer = Self.makeSession(id: "ses_closer", directory: tempDir.path, created: processStartMs - 500)
        client.sessions = [older, closer]
        client.sessionsByID = [older.id: older, closer.id: closer]

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 60
        )

        let expectation = XCTestExpectation(description: "provider binds to closest session")
        provider.onUpdate = { data in
            if data.model != nil {
                expectation.fulfill()
            }
        }

        provider.start()
        wait(for: [expectation], timeout: 3)
        provider.stop()

        XCTAssertEqual(client.renameRequests.first?.id, "ses_closer")
    }

    func testProviderResolvesSymlinkedWorkingDirectory() throws {
        let symlinkParent = tempDir.appending(path: "symlinked")
        let realDir = tempDir.appending(path: "real")
        try? FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(at: symlinkParent, withDestinationURL: realDir)

        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let session = Self.makeSession(id: "ses_symlink", directory: realDir.path, created: processStartMs)
        client.sessions = [session]
        client.sessionsByID[session.id] = session

        let provider = OpenCodeStatusProvider(
            context: makeContext(workingDirectory: symlinkParent.path, processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 60
        )

        let expectation = XCTestExpectation(description: "provider binds through symlink")
        provider.onUpdate = { data in
            if data.model != nil {
                expectation.fulfill()
            }
        }

        provider.start()
        wait(for: [expectation], timeout: 3)
        provider.stop()

        XCTAssertEqual(client.renameRequests.first?.id, "ses_symlink")
    }

    func testProviderWaitsForSessionToAppear() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        client.sessions = []

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.05,
            pollInterval: 60
        )

        let expectation = XCTestExpectation(description: "provider binds after session appears")
        provider.onUpdate = { data in
            if data.model != nil {
                expectation.fulfill()
            }
        }

        provider.start()

        let directory = tempDir.path
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
            let session = Self.makeSession(id: "ses_late", directory: directory, created: processStartMs)
            client.sessions = [session]
            client.sessionsByID[session.id] = session
        }

        wait(for: [expectation], timeout: 5)
        provider.stop()

        XCTAssertEqual(client.renameRequests.first?.id, "ses_late")
    }

    func testProviderRenamesSessionToTabPaneName() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let session = Self.makeSession(
            id: "ses_rename", directory: tempDir.path, title: "old-title", created: processStartMs)
        client.sessions = [session]
        client.sessionsByID[session.id] = session

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 60
        )

        let expectation = XCTestExpectation(description: "provider renames session")
        provider.onUpdate = { data in
            if data.sessionName == "repo/opencode-pane" {
                expectation.fulfill()
            }
        }

        provider.start()
        wait(for: [expectation], timeout: 3)
        provider.stop()

        XCTAssertEqual(client.renameRequests.first?.title, "repo/opencode-pane")
    }

    func testProviderDoesNotBindWhenNoSessionWithinTimeWindow() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let oldSession = Self.makeSession(id: "ses_old", directory: tempDir.path, created: processStartMs - 120_000)
        client.sessions = [oldSession]
        client.sessionsByID[oldSession.id] = oldSession

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            startupTimeout: 0.1,
            pollInterval: 60,
            timeWindowMs: 60_000
        )

        provider.start()
        let delay = XCTestExpectation(description: "provider retries without binding")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { delay.fulfill() }
        wait(for: [delay], timeout: 1)
        provider.stop()

        XCTAssertTrue(client.renameRequests.isEmpty)
        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(
            events.contains { event in
                event.name == "statusline.opencode.session.waiting_for_create"
                    && event.attributes["reason"] == "no_in_window"
                    && event.attributes["matching_count"] == "1"
                    && event.attributes["time_window_ms"] == "60000"
            })
        XCTAssertFalse(events.contains { $0.name == "statusline.opencode.session.fallback_to_newest" })
        XCTAssertFalse(events.contains { $0.name == "statusline.opencode.session.bound" })
    }

    func testSelectSessionExactMatchReturnedWhenExpectedIDPresent() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let expected = Self.makeSession(
            id: "ses_expected",
            directory: tempDir.path,
            created: processStartMs - 120_000
        )
        client.sessions = [expected]
        client.sessionsByID[expected.id] = expected

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart, opencodeSessionID: expected.id),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 60,
            timeWindowMs: 60_000
        )

        let expectation = XCTestExpectation(description: "provider binds exact expected session")
        var boundID: String?
        provider.onSessionBound = { id in
            boundID = id
            expectation.fulfill()
        }

        provider.start()
        wait(for: [expectation], timeout: 1)
        provider.stop()

        XCTAssertEqual(boundID, expected.id)
    }

    func testBrandNewPaneDoesNotBindStaleSessionEndToEnd() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let stale = Self.makeSession(
            id: "ses_stale",
            directory: tempDir.path,
            created: processStartMs - 30 * 60 * 60 * 1_000
        )
        client.sessions = [stale]
        client.sessionsByID[stale.id] = stale

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            startupTimeout: 0.1,
            pollInterval: 60,
            timeWindowMs: 60_000
        )

        var boundIDs: [String] = []
        provider.onSessionBound = { boundIDs.append($0) }

        provider.start()
        let delay = XCTestExpectation(description: "provider retries without binding restored session")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { delay.fulfill() }
        wait(for: [delay], timeout: 1)
        provider.stop()

        XCTAssertTrue(boundIDs.isEmpty)
        XCTAssertTrue(client.renameRequests.isEmpty)
        XCTAssertFalse(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "statusline.opencode.session.bound"
            })
    }

    func testRestoredPaneWithMissingExpectedSessionDoesNotFallbackToNewest() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let stale = Self.makeSession(
            id: "ses_unrelated",
            directory: tempDir.path,
            created: processStartMs - 30 * 60 * 60 * 1_000
        )
        client.sessions = [stale]
        client.sessionsByID[stale.id] = stale

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart, opencodeSessionID: "ses_old"),
            client: client,
            startupRetryInterval: 0.01,
            startupTimeout: 0.1,
            pollInterval: 60,
            timeWindowMs: 60_000
        )

        var boundIDs: [String] = []
        provider.onSessionBound = { boundIDs.append($0) }

        provider.start()
        let delay = XCTestExpectation(description: "provider retries without binding restored session")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { delay.fulfill() }
        wait(for: [delay], timeout: 1)
        provider.stop()

        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(boundIDs.isEmpty)
        XCTAssertTrue(client.renameRequests.isEmpty)
        XCTAssertTrue(events.contains { $0.name == "statusline.opencode.session.expected_missing" })
        XCTAssertFalse(events.contains { $0.name == "statusline.opencode.session.bound" })
    }

    func testProviderReportsPortMissingInvariant() {
        let provider = OpenCodeStatusProvider(
            context: makeContext(opencodePort: nil),
            client: FakeClient(),
            startupRetryInterval: 0.01,
            pollInterval: 60
        )

        InvariantReporter.shared.enableTestCapture()
        provider.start()

        let expectation = XCTestExpectation(description: "provider stops after reporting missing port")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
        provider.stop()

        let violation = InvariantReporter.shared.violationsForTesting.first
        XCTAssertEqual(violation?.invariantID, "opencode.port_missing")
    }

    func testProviderPollsSessionOnTimer() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let initial = Self.makeSession(
            id: "ses_poll",
            directory: tempDir.path,
            created: processStartMs,
            cost: 0.10,
            tokens: OpenCodeSessionTokens(input: 10, output: 5, reasoning: 0, cacheRead: 0, cacheWrite: 0)
        )
        client.sessions = [initial]
        client.sessionsByID[initial.id] = initial

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 0.05
        )

        let expectation = XCTestExpectation(description: "provider emits updated cost after poll")
        var sawInitial = false
        provider.onUpdate = { data in
            guard let cost = data.cost?.totalCostUsd else { return }
            if cost == 0.10 {
                sawInitial = true
            } else if cost == 0.99, sawInitial {
                expectation.fulfill()
            }
        }

        provider.start()

        let directory = tempDir.path
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15) {
            let updated = Self.makeSession(
                id: "ses_poll",
                directory: directory,
                created: processStartMs,
                cost: 0.99,
                tokens: OpenCodeSessionTokens(input: 10, output: 5, reasoning: 0, cacheRead: 0, cacheWrite: 0)
            )
            client.sessionsByID[updated.id] = updated
        }

        wait(for: [expectation], timeout: 5)
        provider.stop()

        XCTAssertGreaterThanOrEqual(client.sessionRequestCount, 2)
    }

    func testProviderFiresOnSessionBound() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let session = Self.makeSession(id: "ses_bound_callback", directory: tempDir.path, created: processStartMs)
        client.sessions = [session]
        client.sessionsByID[session.id] = session

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 60
        )

        let expectation = XCTestExpectation(description: "onSessionBound fires with session id")
        var boundID: String?
        provider.onSessionBound = { id in
            boundID = id
            expectation.fulfill()
        }

        provider.start()
        wait(for: [expectation], timeout: 3)
        provider.stop()

        XCTAssertEqual(boundID, "ses_bound_callback")
    }

    func testProviderEmitsTraceEvents() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let session = Self.makeSession(id: "ses_trace", directory: tempDir.path, created: processStartMs)
        client.sessions = [session]
        client.sessionsByID[session.id] = session

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 0.05
        )

        let expectation = XCTestExpectation(description: "provider emits data")
        provider.onUpdate = { data in
            if data.model != nil {
                expectation.fulfill()
            }
        }

        provider.start()
        wait(for: [expectation], timeout: 3)
        provider.stop()

        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(events.contains { $0.name == "statusline.opencode.server.bound" })
        XCTAssertTrue(events.contains { $0.name == "statusline.opencode.session.bound" })
        XCTAssertTrue(events.contains { $0.name == "statusline.opencode.session.named" })
        XCTAssertTrue(events.contains { $0.name == "statusline.opencode.poll.success" })
    }

    func testSSESessionIdleFiresOpencodeStopOnce() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let session = Self.makeSession(
            id: "ses_sse_stop",
            directory: tempDir.path,
            created: processStartMs,
            status: "busy"
        )
        client.sessions = [session]
        client.sessionsByID[session.id] = session
        client.eventStream = .success(
            AsyncThrowingStream { continuation in
                continuation.yield(.sessionIdle(sessionID: session.id))
                continuation.yield(.sessionIdle(sessionID: session.id))
                continuation.finish()
            })

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 60
        )

        let expectation = XCTestExpectation(description: "provider fires opencode stop once")
        var stopCount = 0
        provider.onOpencodeStopped = {
            stopCount += 1
            expectation.fulfill()
        }

        provider.start()
        wait(for: [expectation], timeout: 3)
        provider.stop()

        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(client.eventStreamRequests.count, 1)
    }

    func testSSESessionIdleIgnoresOtherSessions() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let session = Self.makeSession(
            id: "ses_bound",
            directory: tempDir.path,
            created: processStartMs,
            status: "busy"
        )
        client.sessions = [session]
        client.sessionsByID[session.id] = session
        client.eventStream = .success(
            AsyncThrowingStream { continuation in
                continuation.yield(.sessionIdle(sessionID: "ses_other"))
                continuation.finish()
            })

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 60
        )

        let expectation = XCTestExpectation(description: "provider emits data")
        provider.onUpdate = { data in
            if data.model != nil { expectation.fulfill() }
        }

        var stopCount = 0
        provider.onOpencodeStopped = { stopCount += 1 }

        provider.start()
        wait(for: [expectation], timeout: 3)
        provider.stop()

        XCTAssertEqual(stopCount, 0)
    }

    func testSSEPermissionAskedFiresOpencodePermissionRequest() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let session = Self.makeSession(
            id: "ses_permission",
            directory: tempDir.path,
            created: processStartMs
        )
        client.sessions = [session]
        client.sessionsByID[session.id] = session
        client.eventStream = .success(
            AsyncThrowingStream { continuation in
                continuation.yield(
                    .permissionAsked(
                        sessionID: session.id,
                        permission: "external_directory",
                        patterns: ["/etc/*"]
                    ))
                continuation.finish()
            })

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 60
        )

        let expectation = XCTestExpectation(description: "provider fires permission attention")
        var attentionEvent: PaneAttentionEvent?
        provider.onAttention = { event in
            attentionEvent = event
            expectation.fulfill()
        }

        provider.start()
        wait(for: [expectation], timeout: 3)
        provider.stop()

        XCTAssertEqual(attentionEvent?.source, .opencodePermissionRequest)
        XCTAssertEqual(attentionEvent?.reason, "Permission needed for external_directory (1 requested paths)")
    }

    func testPollingFallbackDetectsIdleTransition() throws {
        let processStart = Date()
        let processStartMs = Int64(processStart.timeIntervalSince1970 * 1000)
        let client = FakeClient()
        let busySession = Self.makeSession(
            id: "ses_poll_transition",
            directory: tempDir.path,
            created: processStartMs,
            status: "busy"
        )
        client.sessions = [busySession]
        client.sessionsByID[busySession.id] = busySession
        client.eventStream = .failure(OpenCodeServerClientError.unexpectedStatus(500))

        let provider = OpenCodeStatusProvider(
            context: makeContext(processStartTime: processStart),
            client: client,
            startupRetryInterval: 0.01,
            pollInterval: 0.05
        )

        let updateExpectation = XCTestExpectation(description: "provider emits initial data")
        let stopExpectation = XCTestExpectation(description: "provider fires stop via polling fallback")
        provider.onUpdate = { data in
            if data.model != nil { updateExpectation.fulfill() }
        }
        var stopCount = 0
        provider.onOpencodeStopped = {
            stopCount += 1
            stopExpectation.fulfill()
        }

        provider.start()
        wait(for: [updateExpectation], timeout: 3)

        let directory = tempDir.path
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) {
            let idleSession = Self.makeSession(
                id: "ses_poll_transition",
                directory: directory,
                created: processStartMs,
                status: "idle"
            )
            client.sessionsByID[idleSession.id] = idleSession
        }

        wait(for: [stopExpectation], timeout: 5)
        provider.stop()

        XCTAssertEqual(stopCount, 1)
    }

    func testRaceLossTelemetryEmittedWhenHealthFailsWithKnownPort() throws {
        let client = FakeClient()
        client.healthResult = .failure(OpenCodeServerClientError.unexpectedStatus(0))

        let provider = OpenCodeStatusProvider(
            context: makeContext(opencodePort: 12345),
            client: client,
            startupRetryInterval: 0.01,
            startupTimeout: 0.05
        )

        let raceLostExpectation = XCTestExpectation(description: "race lost callback fired")
        provider.onPortRaceLost = {
            raceLostExpectation.fulfill()
        }

        provider.start()
        wait(for: [raceLostExpectation], timeout: 3)
        provider.stop()

        let event = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "opencode.port_allocation.failed"
        }
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.attributes["reason"], "race_lost")
        XCTAssertEqual(event?.attributes["port"], "12345")
        XCTAssertEqual(event?.attributes["late_bound"], "true")
        XCTAssertEqual(event?.attributes["pane.id"], "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(event?.attributes["tab.id"], "22222222-2222-2222-2222-222222222222")
    }

    func testRaceLossCallbackNotFiredDuringStartupWindow() throws {
        let client = FakeClient()
        client.healthResult = .failure(OpenCodeServerClientError.unexpectedStatus(0))

        let provider = OpenCodeStatusProvider(
            context: makeContext(opencodePort: 12345),
            client: client,
            startupRetryInterval: 0.01,
            startupTimeout: 0.3
        )

        var callbackCount = 0
        provider.onPortRaceLost = { callbackCount += 1 }

        provider.start()
        let delay = XCTestExpectation(description: "startup window remains open")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { delay.fulfill() }
        wait(for: [delay], timeout: 1)

        XCTAssertEqual(callbackCount, 0)
        XCTAssertFalse(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "opencode.port_allocation.failed"
            })
        provider.stop()
    }

    func testRaceLossCallbackFiresAtStartupTimeout() throws {
        let client = FakeClient()
        client.healthResult = .failure(OpenCodeServerClientError.unexpectedStatus(0))

        let provider = OpenCodeStatusProvider(
            context: makeContext(opencodePort: 12345),
            client: client,
            startupRetryInterval: 0.01,
            startupTimeout: 0.05
        )

        let expectation = XCTestExpectation(description: "race lost callback fired at startup timeout")
        expectation.assertForOverFulfill = true
        var callbackCount = 0
        provider.onPortRaceLost = {
            callbackCount += 1
            expectation.fulfill()
        }

        provider.start()
        wait(for: [expectation], timeout: 1)
        wait(for: [], timeout: 0.1)
        provider.stop()

        let events = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "opencode.port_allocation.failed"
        }
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.attributes["late_bound"], "true")
    }

    func testRaceLossOneShotAfterLateBound() throws {
        let client = FakeClient()
        client.healthResult = .failure(OpenCodeServerClientError.unexpectedStatus(0))

        let provider = OpenCodeStatusProvider(
            context: makeContext(opencodePort: 12345),
            client: client,
            startupRetryInterval: 0.01,
            startupTimeout: 0.03
        )

        var callbackCount = 0
        provider.onPortRaceLost = { callbackCount += 1 }

        provider.start()
        let delay = XCTestExpectation(description: "provider exits after late-bound race loss")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { delay.fulfill() }
        wait(for: [delay], timeout: 1)
        provider.stop()

        let events = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "opencode.port_allocation.failed"
        }
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(events.count, 1)
    }

    func testRaceLossTelemetryNotEmittedWhenPortIsMissing() throws {
        let client = FakeClient()
        client.healthResult = .failure(OpenCodeServerClientError.unexpectedStatus(0))

        let provider = OpenCodeStatusProvider(
            context: makeContext(opencodePort: nil),
            client: client,
            startupRetryInterval: 0.01,
            startupTimeout: 0.05
        )

        let didCallRaceLost = false
        provider.onPortRaceLost = {}

        provider.start()
        wait(for: [], timeout: 0.15)
        provider.stop()

        let event = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "opencode.port_allocation.failed"
        }
        XCTAssertNil(event)
        XCTAssertFalse(didCallRaceLost)
    }
}
