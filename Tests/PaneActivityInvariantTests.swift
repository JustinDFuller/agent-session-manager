import XCTest

@testable import AgentSessionManager

@MainActor
final class PaneActivityInvariantTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TracingService.shared.enableTestCapture()
    }

    override func tearDown() {
        super.tearDown()
        TracingService.shared.resetForTesting()
    }

    private static let emptyStop = Data(
        #"{"hook_event_name":"Stop","background_tasks":[],"session_crons":[]}"#.utf8)
    private static let userPromptSubmit = Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8)

    private static func stop(tasks: String = "[]", crons: String = "[]") -> Data {
        Data(
            #"{"hook_event_name":"Stop","background_tasks":\#(tasks),"session_crons":\#(crons)}"#.utf8)
    }

    private static func task(type: String) -> String {
        #"{"id":"task-001","type":"\#(type)","status":"running","description":"work"}"#
    }

    private static func cron(recurring: Bool) -> String {
        #"{"id":"cron-001","schedule":"*/5 * * * *","recurring":\#(recurring),"prompt":"check the build"}"#
    }

    private func assertStopKeepsPaneWorking(
        tasks: String = "[]", crons: String = "[]", file: StaticString = #filePath, line: UInt = #line
    ) {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        var callCount = 0
        monitor.onClaudeStopped = { callCount += 1 }

        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.stop(tasks: tasks, crons: crons))

        XCTAssertTrue(monitor.isClaudeWorking, file: file, line: line)
        XCTAssertEqual(callCount, 0, file: file, line: line)
    }

    func testWaitingWhenHasNotification() {
        let state = paneActivityState(
            processState: .running(pid: 1),
            isWorking: true,
            sessionState: "busy",
            hasNotification: true
        )
        XCTAssertEqual(state, .waiting)
    }

    func testWaitingBeatsBusyAndExplicitWorkingSignal() {
        XCTAssertEqual(
            paneActivityState(
                processState: .running(pid: 1),
                isWorking: true,
                sessionState: "busy",
                hasNotification: true
            ),
            .waiting
        )
    }

    func testWorkingWhenRunningAndExplicitlyWorking() {
        let state = paneActivityState(
            processState: .running(pid: 1),
            isWorking: true,
            sessionState: nil,
            hasNotification: false
        )
        XCTAssertEqual(state, .working)
    }

    func testWorkingWhenRunningAndSessionBusy() {
        let state = paneActivityState(
            processState: .running(pid: 1),
            isWorking: false,
            sessionState: "busy",
            hasNotification: false
        )
        XCTAssertEqual(state, .working)
    }

    func testWorkingWhenRunningAndSessionRetry() {
        let state = paneActivityState(
            processState: .running(pid: 1),
            isWorking: false,
            sessionState: "retry",
            hasNotification: false
        )
        XCTAssertEqual(state, .working)
    }

    func testIdleWhenRunningButQuiet() {
        let state = paneActivityState(
            processState: .running(pid: 1),
            isWorking: false,
            sessionState: nil,
            hasNotification: false
        )
        XCTAssertEqual(state, .idle)
    }

    func testStoppedWhenRunningAndStopped() {
        let state = paneActivityState(
            processState: .running(pid: 1),
            isWorking: false,
            isStopped: true,
            sessionState: nil,
            hasNotification: false
        )
        XCTAssertEqual(state, .stopped)
    }

    func testWaitingBeatsStoppedWhenHasNotification() {
        let state = paneActivityState(
            processState: .running(pid: 1),
            isWorking: false,
            isStopped: true,
            sessionState: nil,
            hasNotification: true
        )
        XCTAssertEqual(state, .waiting)
    }

    func testStoppedIsIdleWhenProcessExited() {
        let state = paneActivityState(
            processState: .exited(code: 0),
            isWorking: false,
            isStopped: true,
            sessionState: nil,
            hasNotification: false
        )
        XCTAssertEqual(state, .idle)
    }

    func testIdleWhenExited() {
        let state = paneActivityState(
            processState: .exited(code: 0),
            isWorking: false,
            sessionState: nil,
            hasNotification: false
        )
        XCTAssertEqual(state, .idle)
    }

    func testIdleWhenExitedRegardlessOfStaleWorkingSignal() {
        let state = paneActivityState(
            processState: .exited(code: 0),
            isWorking: true,
            sessionState: "busy",
            hasNotification: false
        )
        XCTAssertEqual(state, .idle)
    }

    func testIdleWhenProcessNil() {
        let state = paneActivityState(
            processState: nil,
            isWorking: false,
            sessionState: nil,
            hasNotification: false
        )
        XCTAssertEqual(state, .idle)
    }

    func testPRSignalsAbsentFromSignature() {
        let withNotification = paneActivityState(
            processState: .running(pid: 1),
            isWorking: false,
            sessionState: nil,
            hasNotification: true
        )
        let withoutNotification = paneActivityState(
            processState: .running(pid: 1),
            isWorking: false,
            sessionState: nil,
            hasNotification: false
        )
        XCTAssertEqual(withNotification, .waiting)
        XCTAssertEqual(withoutNotification, .idle)
    }

    func testNoNotificationNeverWaiting() {
        let states: [PaneActivityState] = [
            paneActivityState(
                processState: .running(pid: 1), isWorking: true, sessionState: "busy", hasNotification: false),
            paneActivityState(
                processState: .running(pid: 1), isWorking: false, sessionState: nil, hasNotification: false),
            paneActivityState(
                processState: .exited(code: 0), isWorking: false, sessionState: nil, hasNotification: false),
            paneActivityState(processState: nil, isWorking: false, sessionState: nil, hasNotification: false),
        ]
        for state in states {
            XCTAssertNotEqual(state, .waiting, "Expected non-waiting without notification, got \(state)")
        }
    }

    func testNotificationAlwaysWaiting() {
        let states: [PaneActivityState] = [
            paneActivityState(
                processState: .running(pid: 1), isWorking: true, sessionState: "busy", hasNotification: true),
            paneActivityState(
                processState: .running(pid: 1), isWorking: false, sessionState: nil, hasNotification: true),
            paneActivityState(
                processState: .exited(code: 0), isWorking: false, sessionState: nil, hasNotification: true),
            paneActivityState(processState: nil, isWorking: false, sessionState: nil, hasNotification: true),
        ]
        for state in states {
            XCTAssertEqual(state, .waiting, "Expected waiting with notification, got \(state)")
        }
    }

    func testTabWaitingIfAnyPaneWaiting() {
        let result = tabActivityState([.idle, .working, .waiting])
        XCTAssertEqual(result, .waiting)
    }

    func testTabWorkingIfAnyPaneWorkingNoWaiting() {
        let result = tabActivityState([.idle, .working])
        XCTAssertEqual(result, .working)
    }

    func testTabIdleIfAllIdle() {
        let result = tabActivityState([.idle, .idle])
        XCTAssertEqual(result, .idle)
    }

    func testTabIdleForEmptyPanes() {
        let result = tabActivityState([])
        XCTAssertEqual(result, .idle)
    }

    func testTabWaitingBeatsWorking() {
        XCTAssertEqual(tabActivityState([.working, .waiting]), .waiting)
    }

    func testTabStoppedIfAnyPaneStopped() {
        XCTAssertEqual(tabActivityState([.idle, .stopped]), .stopped)
    }

    func testTabWorkingBeatsStoped() {
        XCTAssertEqual(tabActivityState([.working, .stopped]), .working)
    }

    func testTabWaitingBeatsStopped() {
        XCTAssertEqual(tabActivityState([.waiting, .stopped]), .waiting)
    }

    func testWorkingAndWaitingUseDistinctCircularAppearances() {
        let working = activityIndicatorAppearance(for: .working)
        let waiting = activityIndicatorAppearance(for: .waiting)

        XCTAssertEqual(working.geometry, .circle)
        XCTAssertEqual(waiting.geometry, .circle)
        XCTAssertEqual(working.palette, .secondary)
        XCTAssertEqual(waiting.palette, .accent)
        XCTAssertLessThan(working.opacityRange.upperBound, waiting.opacityRange.upperBound)
        XCTAssertGreaterThan(working.blurRadius, 0)
        XCTAssertEqual(waiting.blurRadius, 0)
    }

    func testWaitingAppearanceIsSolidRegardlessOfPulse() {
        let waiting = activityIndicatorAppearance(for: .waiting)
        XCTAssertEqual(
            waiting.resolvedOpacity(pulsing: true, reduceMotion: false),
            waiting.resolvedOpacity(pulsing: false, reduceMotion: false)
        )
        XCTAssertEqual(waiting.resolvedOpacity(pulsing: true, reduceMotion: false), 1)
    }

    func testWaitingIndicatorColorReflectsPriority() {
        XCTAssertEqual(waitingIndicatorColor(isPriority: true), .orange)
        XCTAssertEqual(waitingIndicatorColor(isPriority: false), Theme.accent)
    }

    func testReduceMotionKeepsWorkingAndWaitingStaticallyDistinct() {
        let working = activityIndicatorAppearance(for: .working)
        let waiting = activityIndicatorAppearance(for: .waiting)

        XCTAssertEqual(working.resolvedOpacity(pulsing: true, reduceMotion: true), 0.85)
        XCTAssertEqual(waiting.resolvedOpacity(pulsing: true, reduceMotion: true), 1)
        XCTAssertNotEqual(
            working.resolvedOpacity(pulsing: true, reduceMotion: true),
            waiting.resolvedOpacity(pulsing: true, reduceMotion: true)
        )
    }

    func testStoppedAppearanceUsesOctagonGeometry() {
        let stopped = activityIndicatorAppearance(for: .stopped)
        XCTAssertEqual(stopped.geometry, .octagon)
        XCTAssertEqual(stopped.palette, .secondary)
        XCTAssertEqual(stopped.blurRadius, 0)
        XCTAssertEqual(stopped.opacityRange, 0.5...0.5)
    }

    func testClaudeLifecyclePayloadTransitionsWorkingAndIdle() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        XCTAssertTrue(monitor.isClaudeWorking)
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        XCTAssertFalse(monitor.isClaudeWorking)
    }

    func testClaudeStopFailureTransitionsIdle() {
        InvariantReporter.shared.enableTestCapture()
        addTeardownBlock { InvariantReporter.shared.resetForTesting() }
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"StopFailure"}"#.utf8))
        XCTAssertFalse(monitor.isClaudeWorking)
        XCTAssertTrue(InvariantReporter.shared.violationsForTesting.isEmpty)
    }

    func testClaudeActivityChangedTraceOnlyFiresOnEdges() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)

        let changed = TracingService.shared.recordedEventsForTesting.filter { $0.name == "pane.activity.changed" }
        XCTAssertEqual(changed.count, 2)
        XCTAssertEqual(changed.map { $0.attributes["state"] }, ["working", "stopped"])
        XCTAssertEqual(changed.map { $0.attributes["source"] }, ["claude_hook", "claude_hook"])
        XCTAssertEqual(changed.map { $0.attributes["hook_event"] }, ["UserPromptSubmit", "Stop"])
    }

    func testClaudeLifecycleIsStoppedAfterStop() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        XCTAssertTrue(monitor.isClaudeStopped)
        XCTAssertFalse(monitor.isClaudeWorking)
    }

    func testCursorLifecycleTransitionsWorkingAndStopped() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .cursor)
        monitor.testApplyCursorActivity(isWorking: true)
        XCTAssertTrue(monitor.isCursorWorking)
        XCTAssertFalse(monitor.isCursorStopped)
        monitor.testApplyCursorActivity(isWorking: false)
        XCTAssertFalse(monitor.isCursorWorking)
        XCTAssertTrue(monitor.isCursorStopped)
    }

    func testClaudeStopWithNoPriorWorkingIsIgnored() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        XCTAssertFalse(monitor.isClaudeWorking)
        XCTAssertFalse(monitor.isClaudeStopped)
        let events = TracingService.shared.recordedEventsForTesting
        XCTAssertTrue(events.allSatisfy { $0.name != "pane.activity.changed" })
        XCTAssertEqual(events.last?.attributes["decision"], "ignored_not_working")
    }

    func testOnClaudeStoppedCallbackFiresOncePerEdge() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        var callCount = 0
        monitor.onClaudeStopped = { callCount += 1 }

        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        XCTAssertEqual(callCount, 1)

        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(
            TracingService.shared.recordedEventsForTesting
                .filter { $0.name == "statusline.hook.event" && $0.attributes["hook_event"] == "Stop" }
                .map { $0.attributes["decision"] },
            ["scheduled", "ignored_not_working"])
    }

    func testOnClaudeStoppedCallbackNotFiredForLoneStop() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        var callCount = 0
        monitor.onClaudeStopped = { callCount += 1 }
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        XCTAssertEqual(callCount, 0)
    }

    func testGracePeriodZeroFiresImmediatelyOnStop() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        var callCount = 0
        monitor.onClaudeStopped = { callCount += 1 }

        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        XCTAssertEqual(callCount, 1)
    }

    func testForcedContinueWithinGraceCancelsSpuriousChime() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0.05
        var callCount = 0
        monitor.onClaudeStopped = { callCount += 1 }

        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        XCTAssertTrue(monitor.isClaudeStopped, "lifecycle flips to stopped immediately regardless of grace")

        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        XCTAssertEqual(callCount, 0)

        let expectation = XCTestExpectation(description: "grace period elapses without firing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(
            TracingService.shared.recordedEventsForTesting
                .filter { $0.name == "statusline.hook.event" && $0.attributes["hook_event"] == "Stop" }
                .map { $0.attributes["decision"] },
            ["scheduled"])

        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        let realStopExpectation = XCTestExpectation(description: "real stop fires after grace period")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { realStopExpectation.fulfill() }
        wait(for: [realStopExpectation], timeout: 1)
        XCTAssertEqual(callCount, 1)
    }

    func testClaudeActivityIgnoresMalformedAndUnrelatedPayloads() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"SomeUnknownHook"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(Data("not json".utf8))
        XCTAssertFalse(monitor.isClaudeWorking)
        XCTAssertTrue(TracingService.shared.recordedEventsForTesting.isEmpty)
    }

    func testStopWithRunningSubagentKeepsPaneWorking() {
        assertStopKeepsPaneWorking(tasks: "[\(Self.task(type: "subagent"))]")
    }

    func testStopWithRunningShellKeepsPaneWorking() {
        assertStopKeepsPaneWorking(tasks: "[\(Self.task(type: "shell"))]")
    }

    func testStopWithRunningMonitorKeepsPaneWorking() {
        assertStopKeepsPaneWorking(tasks: "[\(Self.task(type: "monitor"))]")
    }

    func testStopWithOneShotSessionCronKeepsPaneWorking() {
        assertStopKeepsPaneWorking(crons: "[\(Self.cron(recurring: false))]")
    }

    func testStopWithRecurringSessionCronKeepsPaneWorking() {
        assertStopKeepsPaneWorking(crons: "[\(Self.cron(recurring: true))]")
    }

    func testStopWithBothListsEmptyStopsPaneAndFiresOnce() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        var callCount = 0
        monitor.onClaudeStopped = { callCount += 1 }

        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.stop())

        XCTAssertTrue(monitor.isClaudeStopped)
        XCTAssertFalse(monitor.isClaudeWorking)
        XCTAssertEqual(callCount, 1)
    }

    func testStopFiresOnceAfterBackgroundWorkCompletesAndSessionResumes() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        var callCount = 0
        monitor.onClaudeStopped = { callCount += 1 }

        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.stop(tasks: "[\(Self.task(type: "subagent"))]"))
        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(monitor.isClaudeWorking)

        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        XCTAssertEqual(callCount, 0)

        monitor.testApplyClaudeActivityPayload(Self.stop())
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(monitor.isClaudeStopped)
    }

    func testBackToBackStopsWithSubagentThenEmptyListsStopsPaneAndFiresOnce() {
        assertBackToBackStopsEndWithEmptyLists(firstStop: Self.stop(tasks: "[\(Self.task(type: "subagent"))]"))
    }

    func testBackToBackStopsWithRecurringCronThenEmptyListsStopsPaneAndFiresOnce() {
        assertBackToBackStopsEndWithEmptyLists(firstStop: Self.stop(crons: "[\(Self.cron(recurring: true))]"))
    }

    private func assertBackToBackStopsEndWithEmptyLists(
        firstStop: Data, file: StaticString = #filePath, line: UInt = #line
    ) {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        var callCount = 0
        monitor.onClaudeStopped = { callCount += 1 }

        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(firstStop)
        XCTAssertTrue(monitor.isClaudeWorking, file: file, line: line)
        XCTAssertEqual(callCount, 0, file: file, line: line)

        monitor.testApplyClaudeActivityPayload(Self.stop())
        XCTAssertTrue(monitor.isClaudeStopped, file: file, line: line)
        XCTAssertFalse(monitor.isClaudeWorking, file: file, line: line)
        XCTAssertEqual(callCount, 1, file: file, line: line)
    }

    func testSuppressedStopTracesBackgroundTaskTypesAndCronCount() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(
            Self.stop(
                tasks: "[\(Self.task(type: "subagent")),\(Self.task(type: "shell"))]",
                crons: "[\(Self.cron(recurring: true))]"
            ))

        let event = TracingService.shared.recordedEventsForTesting.last { $0.name == "statusline.hook.event" }
        XCTAssertEqual(event?.attributes["decision"], "suppressed_background_work")
        let types = event?.attributes["background_task_types"] ?? ""
        XCTAssertTrue(types.contains("subagent"))
        XCTAssertTrue(types.contains("shell"))
        XCTAssertEqual(event?.attributes["session_cron_count"], "1")
        XCTAssertEqual(event?.attributes["background_task_count"], "2")
    }

    func testSuppressedStopBoundsTaskTypeTelemetryAndRecordsTotalCount() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        let tasks = (0..<100).map { index in
            Self.task(type: "type-\(index)-" + String(repeating: "e\u{301}", count: 300))
        }.joined(separator: ",")
        monitor.testApplyClaudeActivityPayload(Self.stop(tasks: "[\(tasks)]"))

        let event = TracingService.shared.recordedEventsForTesting.last { $0.name == "statusline.hook.event" }
        let types = (event?.attributes["background_task_types"] ?? "").split(separator: ",")
        XCTAssertEqual(types.count, 16)
        XCTAssertTrue(types.allSatisfy { $0.utf8.count <= 64 })
        XCTAssertTrue(types.allSatisfy { !$0.contains("\u{FFFD}") })
        XCTAssertEqual(event?.attributes["background_task_count"], "100")
        XCTAssertTrue(monitor.isClaudeWorking)
    }

    func testStopTraceDecisionsAcrossSuppressedThenScheduledSequence() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0

        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.stop(tasks: "[\(Self.task(type: "subagent"))]"))
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.stop())

        XCTAssertEqual(
            TracingService.shared.recordedEventsForTesting
                .filter { $0.name == "statusline.hook.event" && $0.attributes["hook_event"] == "Stop" }
                .map { $0.attributes["decision"] },
            ["suppressed_background_work", "scheduled"])
    }

    func testStopMissingBackgroundTasksReportsInvariantAndStillStops() {
        assertMissingListReportsInvariantAndStillStops(
            payload: #"{"hook_event_name":"Stop","session_crons":[]}"#)
    }

    func testStopMissingSessionCronsReportsInvariantAndStillStops() {
        assertMissingListReportsInvariantAndStillStops(
            payload: #"{"hook_event_name":"Stop","background_tasks":[]}"#)
    }

    func testStopMissingTasksWithPendingCronStillFinishes() {
        assertMissingListReportsInvariantAndStillStops(
            payload: #"{"hook_event_name":"Stop","session_crons":[{"id":"cron","recurring":true}]}"#)
    }

    func testStopMissingCronsWithRunningTaskStillFinishes() {
        assertMissingListReportsInvariantAndStillStops(
            payload: #"{"hook_event_name":"Stop","background_tasks":[{"id":"task","type":"shell","status":"running"}]}"#
        )
    }

    func testStopMissingBothListsStillFinishes() {
        assertMissingListReportsInvariantAndStillStops(payload: #"{"hook_event_name":"Stop"}"#)
    }

    func testStopNullListWithRunningTaskStillFinishes() {
        assertMissingListReportsInvariantAndStillStops(
            payload: #"{"hook_event_name":"Stop","background_tasks":[{"type":"subagent"}],"session_crons":null}"#)
    }

    private func assertMissingListReportsInvariantAndStillStops(
        payload: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        InvariantReporter.shared.enableTestCapture()
        addTeardownBlock { InvariantReporter.shared.resetForTesting() }
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        var callCount = 0
        monitor.onClaudeStopped = { callCount += 1 }

        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Data(payload.utf8))

        XCTAssertEqual(Invariant.claudeStopBackgroundState.id, "claude.stop.background_state", file: file, line: line)
        XCTAssertEqual(Invariant.claudeStopBackgroundState.severity, .warning, file: file, line: line)
        XCTAssertEqual(
            Invariant.claudeStopBackgroundState.traceEventName,
            "statusline.claude.stop_background_state_missing",
            file: file, line: line
        )
        XCTAssertEqual(
            InvariantReporter.shared.violationsForTesting.map(\.invariantID),
            ["claude.stop.background_state"],
            file: file, line: line
        )
        XCTAssertTrue(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "statusline.claude.stop_background_state_missing"
            }, file: file, line: line)
        XCTAssertTrue(monitor.isClaudeStopped, file: file, line: line)
        XCTAssertEqual(callCount, 1, file: file, line: line)
    }

    func testStopWithBothListsPresentDoesNotReportInvariant() {
        InvariantReporter.shared.enableTestCapture()
        addTeardownBlock { InvariantReporter.shared.resetForTesting() }
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.stop())
        XCTAssertTrue(InvariantReporter.shared.violationsForTesting.isEmpty)
    }

    private static let idlePromptNotification = Data(
        #"{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input"}"#
            .utf8)

    private func makeWorkingMonitorWithRunningSubagent() -> StatusLineMonitor {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.stop(tasks: "[\(Self.task(type: "subagent"))]"))
        return monitor
    }

    func testIdlePromptWhileWorkingProducesNoAttentionAndTracesSuppression() {
        let monitor = makeWorkingMonitorWithRunningSubagent()
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }

        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)

        XCTAssertTrue(events.isEmpty)
        let suppressed = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.attention.suppressed"
        }
        XCTAssertEqual(suppressed.count, 1)
        XCTAssertEqual(suppressed.first?.attributes["reason"], "background_work_pending")
    }

    func testIdlePromptAfterPaneStoppedProducesOneAttentionEvent() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.stop())
        XCTAssertTrue(monitor.isClaudeStopped)

        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .claudeNotification)
        XCTAssertTrue(
            TracingService.shared.recordedEventsForTesting.allSatisfy { $0.name != "statusline.attention.suppressed" })
    }

    func testIdlePromptDroppedWhileWorkingDoesNotSwallowIdenticalIdlePromptAfterStop() {
        let monitor = makeWorkingMonitorWithRunningSubagent()
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }

        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)
        XCTAssertTrue(events.isEmpty)

        monitor.testApplyClaudeActivityPayload(Self.stop())
        XCTAssertTrue(monitor.isClaudeStopped)
        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .claudeNotification)
    }

    func testIdenticalConsecutivePermissionPromptsProduceOneAttentionEvent() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }
        let payload = Data(
            #"{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission"}"#
                .utf8)

        monitor.testApplyClaudeAttentionPayload(payload)
        monitor.testApplyClaudeAttentionPayload(payload)

        XCTAssertEqual(events.count, 1)
    }

    func testPermissionPromptWhileWorkingStillProducesAttentionEvent() {
        let monitor = makeWorkingMonitorWithRunningSubagent()
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }

        monitor.testApplyClaudeAttentionPayload(
            Data(
                #"{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission"}"#
                    .utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.reason, "Claude needs your permission")
    }

    func testEveryOtherTaskTypeAndUnknownTypeKeepsPaneWorking() {
        for type in ["workflow", "teammate", "cloud session", "MCP task", "future_task"] {
            assertStopKeepsPaneWorking(tasks: "[\(Self.task(type: type))]")
        }
    }

    func testIdleRecoversInterruptedForegroundTurnWithoutFinishedAlert() {
        let paneID = UUID()
        let tabID = UUID()
        let monitor = StatusLineMonitor(
            paneID: paneID, paneName: "worker", harness: .claude, tabID: tabID, tabName: "project")
        var finishedCount = 0
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeStopped = { finishedCount += 1 }
        monitor.onClaudeHookAttention = { events.append($0) }
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)
        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)

        XCTAssertTrue(monitor.isClaudeStopped)
        XCTAssertEqual(finishedCount, 0)
        XCTAssertEqual(events.count, 1)
        let recovery = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.attention.recovered"
        }
        XCTAssertEqual(recovery.count, 1)
        XCTAssertEqual(recovery.first?.attributes["reason"], "idle_without_background_work")
        XCTAssertEqual(recovery.first?.attributes["pane.id"], paneID.uuidString)
        XCTAssertEqual(recovery.first?.attributes["tab.id"], tabID.uuidString)
        XCTAssertEqual(recovery.first?.attributes["pane.name"], "worker")
        XCTAssertEqual(recovery.first?.attributes["tab.name"], "project")
        let transition = TracingService.shared.recordedEventsForTesting.last { $0.name == "pane.activity.changed" }
        XCTAssertEqual(transition?.attributes["state"], "stopped")
        XCTAssertEqual(transition?.attributes["source"], "claude_idle_prompt")
    }

    func testSameIdlePayloadCanRecoverTwoDistinctInterruptedTurns() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }
        for _ in 0..<2 {
            monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
            monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)
            monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)
            XCTAssertTrue(monitor.isClaudeStopped)
        }
        XCTAssertEqual(events.count, 2)
    }

    func testIdleAttentionCancelsCompletionDuringGrace() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0.05
        var finishedCount = 0
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeStopped = { finishedCount += 1 }
        monitor.onClaudeHookAttention = { events.append($0) }
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)
        let elapsed = XCTestExpectation(description: "completion grace period elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 1)
        XCTAssertTrue(monitor.isClaudeStopped)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(finishedCount, 0)
    }

    func testPendingStopDuringCompletionGraceCancelsQueuedAlertAndReturnsToWorking() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0.05
        var finishedCount = 0
        monitor.onClaudeStopped = { finishedCount += 1 }
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        monitor.testApplyClaudeActivityPayload(Self.stop(tasks: "[\(Self.task(type: "shell"))]"))
        XCTAssertTrue(monitor.isClaudeWorking)
        let elapsed = XCTestExpectation(description: "superseded completion grace period elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 1)
        XCTAssertEqual(finishedCount, 0)
        monitor.testApplyClaudeActivityPayload(Self.emptyStop)
        let completion = XCTestExpectation(description: "final completion grace elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { completion.fulfill() }
        wait(for: [completion], timeout: 1)
        XCTAssertEqual(finishedCount, 1)
    }

    func testIdleRemainsSuppressedAcrossResumedPromptWithConfirmedPendingWork() {
        let monitor = makeWorkingMonitorWithRunningSubagent()
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)
        XCTAssertTrue(monitor.isClaudeWorking)
        XCTAssertTrue(events.isEmpty)
    }

    func testIncompleteReportClearsPriorBackgroundConfirmation() {
        InvariantReporter.shared.enableTestCapture()
        addTeardownBlock { InvariantReporter.shared.resetForTesting() }
        let monitor = makeWorkingMonitorWithRunningSubagent()
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }
        monitor.testApplyClaudeActivityPayload(
            Data(#"{"hook_event_name":"Stop","session_crons":[{"recurring":true}]}"#.utf8))
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)
        XCTAssertTrue(monitor.isClaudeStopped)
        XCTAssertEqual(events.count, 1)
    }

    func testStopFailureClearsBackgroundConfirmationEvenWithPendingFields() {
        let monitor = makeWorkingMonitorWithRunningSubagent()
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }
        monitor.testApplyClaudeActivityPayload(
            Data(#"{"hook_event_name":"StopFailure","background_tasks":[{"type":"shell"}],"session_crons":[]}"#.utf8))
        XCTAssertTrue(monitor.isClaudeStopped)
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)
        XCTAssertTrue(monitor.isClaudeStopped)
        XCTAssertEqual(events.count, 1)
    }

    func testMonitorTeardownClearsBackgroundConfirmation() {
        let monitor = makeWorkingMonitorWithRunningSubagent()
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }
        monitor.stop()
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeAttentionPayload(Self.idlePromptNotification)
        XCTAssertTrue(monitor.isClaudeStopped)
        XCTAssertEqual(events.count, 1)
    }

    func testQuestionAndPlanAttentionAcrossEveryLifecycleAndBackgroundState() {
        for tool in ["AskUserQuestion", "ExitPlanMode"] {
            for state in ["unknown", "working", "stopped", "background"] {
                let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
                monitor.stopNotificationGracePeriod = 0
                if state != "unknown" { monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit) }
                if state == "stopped" { monitor.testApplyClaudeActivityPayload(Self.emptyStop) }
                if state == "background" {
                    monitor.testApplyClaudeActivityPayload(Self.stop(tasks: "[\(Self.task(type: "shell"))]"))
                }
                var events: [PaneAttentionEvent] = []
                monitor.onClaudeHookAttention = { events.append($0) }
                let data = Data(#"{"hook_event_name":"PreToolUse","tool_name":"\#(tool)"}"#.utf8)
                monitor.testApplyClaudeAttentionPayload(data)
                monitor.testApplyClaudeAttentionPayload(data)
                XCTAssertEqual(events.count, 1, "\(tool) in \(state)")
                XCTAssertEqual(
                    events.first?.source.rawValue,
                    tool == "AskUserQuestion" ? "claude_question" : "claude_plan_approval")
                XCTAssertEqual(
                    events.first?.reason,
                    tool == "AskUserQuestion" ? "Claude has a question" : "Claude needs plan approval")
            }
        }
    }

    func testCodexLifecycleDrivesPaneAndTabActivityAcrossMonitorReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-codex-activity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let tab = Tab(name: "Codex Activity", directory: directory)
        let pane = Pane(name: "codex-activity", tab: tab, harness: .codex)
        tab.panes = [pane]
        let previous = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: directory.path,
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"))
        let replacement = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: directory.path,
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"))
        defer {
            pane.removeStatusLineMonitor()
            previous.stop()
            replacement.stop()
        }

        pane.installStatusLineMonitor(previous)
        try appendCodexActivityRecord(previous, event: "UserPromptSubmit", paneID: pane.id, tabID: tab.id)
        let previousBecameActive = await waitForCodexActivity(previous, working: true, stopped: false)
        XCTAssertTrue(previousBecameActive)
        XCTAssertEqual(paneState(pane), .working)
        XCTAssertEqual(tabActivityState([paneState(pane)]), .working)

        pane.installStatusLineMonitor(replacement)
        try appendCodexActivityRecord(previous, event: "Stop", paneID: pane.id, tabID: tab.id)
        try appendCodexActivityRecord(replacement, event: "UserPromptSubmit", paneID: pane.id, tabID: tab.id)
        let replacementBecameActive = await waitForCodexActivity(replacement, working: true, stopped: false)
        XCTAssertTrue(replacementBecameActive)
        XCTAssertEqual(paneState(pane), .working)
        XCTAssertEqual(tabActivityState([paneState(pane)]), .working)
        XCTAssertEqual(
            paneActivityState(
                processState: .running(pid: 1),
                isWorking: replacement.isCodexWorking,
                isStopped: replacement.isCodexStopped,
                sessionState: nil,
                hasNotification: true),
            .waiting)

        try appendCodexActivityRecord(replacement, event: "Stop", paneID: pane.id, tabID: tab.id)
        let replacementStopped = await waitForCodexActivity(replacement, working: false, stopped: true)
        XCTAssertTrue(replacementStopped)
        XCTAssertEqual(paneState(pane), .stopped)
        XCTAssertEqual(
            paneActivityState(
                processState: .exited(code: 0),
                isWorking: replacement.isCodexWorking,
                isStopped: replacement.isCodexStopped,
                sessionState: nil,
                hasNotification: false),
            .idle)
        XCTAssertEqual(tabActivityState([.stopped, .waiting]), .waiting)
    }

    private func appendCodexActivityRecord(
        _ monitor: StatusLineMonitor,
        event: String,
        paneID: UUID,
        tabID: UUID
    ) throws {
        let record = CodexHookQueueRecord(
            paneID: paneID.uuidString,
            tabID: tabID.uuidString,
            launchGeneration: monitor.codexLaunchGeneration,
            hookEventName: event,
            sessionID: "activity-test-session",
            turnID: nil,
            requestID: nil,
            timestamp: Date().timeIntervalSince1970,
            source: "hook",
            model: nil,
            transcriptPath: nil,
            result: nil)
        var data = try JSONEncoder().encode(record)
        data.append(UInt8(ascii: "\n"))
        let queueURL = URL(filePath: monitor.codexHookQueueFilePath)
        if FileManager.default.fileExists(atPath: queueURL.path) {
            let handle = try FileHandle(forWritingTo: queueURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: queueURL)
        }
    }

    private func waitForCodexActivity(
        _ monitor: StatusLineMonitor,
        working: Bool,
        stopped: Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if monitor.isCodexWorking == working, monitor.isCodexStopped == stopped { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    private func paneState(_ pane: Pane) -> PaneActivityState {
        paneActivityState(
            processState: .running(pid: 1),
            isWorking: pane.statusLineMonitor?.isCodexWorking ?? false,
            isStopped: pane.statusLineMonitor?.isCodexStopped ?? false,
            sessionState: nil,
            hasNotification: false)
    }

    func testCodexCompletionDeliversOnceAfterGraceWithPaneDiagnostics() async {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        let paneID = UUID()
        let monitor = StatusLineMonitor(paneID: paneID, paneName: "codex-pane", harness: .codex)
        monitor.stopNotificationGracePeriod = 0.05
        var delivered = 0
        monitor.onCodexStopped = { delivered += 1 }

        monitor.handleCodexHookRecords([codexLifecycleRecord("UserPromptSubmit", monitor: monitor)])
        monitor.handleCodexHookRecords([
            codexLifecycleRecord("Stop", monitor: monitor),
            codexLifecycleRecord("Stop", monitor: monitor),
        ])
        XCTAssertEqual(delivered, 0)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(delivered, 1)
        let phases = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.codex.completion"
        }
        XCTAssertEqual(phases.map { $0.attributes["phase"] }, ["scheduled", "delivered"])
        XCTAssertTrue(
            phases.allSatisfy {
                $0.attributes["pane.id"] == paneID.uuidString
                    && $0.attributes["tab.id"] != nil
                    && $0.attributes["pane.name"] == "codex-pane"
            })
        monitor.stop()
    }

    func testCodexCompletionCancelsForNewTurnRebindInterruptionAndTeardown() async {
        let cancelCases: [(String, (StatusLineMonitor) -> Void)] = [
            ("new_turn", { $0.handleCodexHookRecords([self.codexLifecycleRecord("UserPromptSubmit", monitor: $0)]) }),
            ("conversation_changed", { $0.bindCodexSession("next-session") }),
            ("interrupted", { $0.handleCodexHookRecords([self.codexLifecycleRecord("Interrupt", monitor: $0)]) }),
            ("teardown", { $0.stop() }),
        ]

        for (expectedReason, cancel) in cancelCases {
            TracingService.shared.resetForTesting()
            TracingService.shared.enableTestCapture()
            let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
            monitor.stopNotificationGracePeriod = 0.05
            var delivered = 0
            monitor.onCodexStopped = { delivered += 1 }
            monitor.bindCodexSession("current-session")
            monitor.handleCodexHookRecords([codexLifecycleRecord("UserPromptSubmit", monitor: monitor)])
            monitor.handleCodexHookRecords([codexLifecycleRecord("Stop", monitor: monitor)])

            cancel(monitor)
            try? await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertEqual(delivered, 0, expectedReason)
            let phases = TracingService.shared.recordedEventsForTesting.filter {
                $0.name == "statusline.codex.completion"
            }
            XCTAssertEqual(phases.last?.attributes["phase"], "canceled", expectedReason)
            XCTAssertEqual(phases.last?.attributes["reason"], expectedReason, expectedReason)
            monitor.stop()
        }
    }

    func testCodexHookWriterFailureCancelsPendingCompletion() async throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        let monitor = StatusLineMonitor(
            paneID: UUID(),
            workingDirectory: NSTemporaryDirectory(),
            harness: .codex,
            codexAdapter: .current(version: "0.162.1"))
        monitor.stopNotificationGracePeriod = 1.5
        var delivered = 0
        monitor.onCodexStopped = { delivered += 1 }
        monitor.start()
        monitor.handleCodexHookRecords([codexLifecycleRecord("UserPromptSubmit", monitor: monitor)])
        monitor.handleCodexHookRecords([codexLifecycleRecord("Stop", monitor: monitor)])
        try Data("failed|unknown|hook_write_failed\n".utf8)
            .write(to: URL(filePath: monitor.codexHookDiagnosticFilePath))
        try? await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(delivered, 0)
        var completion = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.codex.completion"
        }
        XCTAssertEqual(completion.last?.attributes["phase"], "canceled")
        XCTAssertEqual(completion.last?.attributes["reason"], "hook_failure")

        monitor.handleCodexHookRecords([codexLifecycleRecord("UserPromptSubmit", turnID: "next-turn", monitor: monitor)]
        )
        monitor.handleCodexHookRecords([codexLifecycleRecord("Stop", turnID: "next-turn", monitor: monitor)])
        try Data("failed|unknown|hook_write_failed\n".utf8)
            .write(to: URL(filePath: monitor.codexHookDiagnosticFilePath))
        try? await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(delivered, 0)
        completion = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.codex.completion"
        }
        XCTAssertEqual(completion.last?.attributes["phase"], "canceled")
        XCTAssertEqual(completion.last?.attributes["reason"], "hook_failure")
        monitor.stop()
    }

    func testCodexDelegatedCompletionDoesNotScheduleForegroundAlert() {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
        monitor.stopNotificationGracePeriod = 0.01
        var delivered = 0
        monitor.onCodexStopped = { delivered += 1 }
        monitor.handleCodexHookRecords([codexLifecycleRecord("UserPromptSubmit", monitor: monitor)])

        monitor.handleCodexHookRecords([codexLifecycleRecord("SubagentStop", monitor: monitor)])

        XCTAssertEqual(delivered, 0)
        XCTAssertFalse(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "statusline.codex.completion"
            })
        monitor.stop()
    }

    func testDelegatedTurnHooksDoNotClearAttentionOrScheduleForegroundAlert() {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
        var delivered = 0
        var clearedKinds: [NotificationKind] = []
        monitor.onCodexStopped = { delivered += 1 }
        monitor.onCodexAttentionResolved = { clearedKinds.append($0) }

        monitor.handleCodexHookRecords([
            codexLifecycleRecord("UserPromptSubmit", source: "subagent", monitor: monitor),
            codexLifecycleRecord("Stop", source: "subagent", monitor: monitor),
        ])

        XCTAssertEqual(delivered, 0)
        XCTAssertTrue(clearedKinds.isEmpty)
        XCTAssertFalse(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "statusline.codex.completion"
            })
        monitor.stop()
    }

    func testCodexCompletionRequiresCurrentForegroundTurnIdentity() async {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
        monitor.stopNotificationGracePeriod = 0.02
        var delivered = 0
        monitor.onCodexStopped = { delivered += 1 }
        monitor.handleCodexHookRecords([codexLifecycleRecord("UserPromptSubmit", turnID: "current", monitor: monitor)])
        monitor.handleCodexHookRecords([codexLifecycleRecord("Stop", turnID: "stale", monitor: monitor)])
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(delivered, 0)

        monitor.handleCodexHookRecords([codexLifecycleRecord("Stop", turnID: "current", monitor: monitor)])
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(delivered, 1)
        monitor.stop()
    }

    func testCodexCompletionSupportsLegacyHooksWithoutTurnID() async {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
        monitor.stopNotificationGracePeriod = 0.02
        var delivered = 0
        monitor.onCodexStopped = { delivered += 1 }
        monitor.handleCodexHookRecords([codexLifecycleRecord("UserPromptSubmit", turnID: nil, monitor: monitor)])
        monitor.handleCodexHookRecords([codexLifecycleRecord("Stop", turnID: nil, monitor: monitor)])
        try? await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(delivered, 1)
        monitor.stop()
    }

    func testNewCodexForegroundTurnClearsPermissionAndQuestionAttention() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
        var clearedKinds: [NotificationKind] = []
        monitor.onCodexAttentionResolved = { kind in clearedKinds.append(kind) }

        monitor.handleCodexHookRecords([codexLifecycleRecord("UserPromptSubmit", monitor: monitor)])

        XCTAssertEqual(clearedKinds, [.codexPermissionRequest, .codexQuestion])
        monitor.stop()
    }

    private func codexLifecycleRecord(
        _ event: String,
        turnID: String? = "test-turn",
        source: String = "hook",
        monitor: StatusLineMonitor
    ) -> CodexHookQueueRecord {
        CodexHookQueueRecord(
            paneID: UUID().uuidString,
            tabID: UUID().uuidString,
            launchGeneration: monitor.codexLaunchGeneration,
            hookEventName: event,
            sessionID: "test-session",
            turnID: turnID,
            requestID: nil,
            timestamp: Date().timeIntervalSince1970,
            source: source,
            model: nil,
            transcriptPath: nil,
            result: nil)
    }

    func testUnrelatedPreToolUseDoesNotProduceAttention() {
        let monitor = makeWorkingMonitorWithRunningSubagent()
        var events: [PaneAttentionEvent] = []
        monitor.onClaudeHookAttention = { events.append($0) }
        for tool in ["Bash", "Agent", "Task", "Read", ""] {
            monitor.testApplyClaudeAttentionPayload(
                Data(#"{"hook_event_name":"PreToolUse","tool_name":"\#(tool)"}"#.utf8))
        }
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(monitor.isClaudeWorking)
    }

    func testClearNotificationEmitsTrace() {
        let appState = AppState()
        let paneID = UUID()
        let tabID = UUID()
        appState.notifications.append(
            PaneNotification(
                paneID: paneID,
                paneName: "test-pane",
                tabID: tabID,
                tabName: "TestTab",
                isPriority: false
            ))
        appState.clearNotification(paneID: paneID)
        let events = TracingService.shared.recordedEventsForTesting
        let cleared = events.first { $0.name == "pane.notification.cleared" }
        XCTAssertNotNil(cleared)
        XCTAssertEqual(cleared?.attributes["reason"], "cleared")
        XCTAssertEqual(cleared?.attributes["pane.name"], "test-pane")
    }
    func testFullCountsKeepPendingEvenWhenSamplesAreEmpty() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(
            Data(
                #"{"hook_event_name":"Stop","background_tasks":[],"session_crons":[],"background_tasks_total_count":100,"session_crons_total_count":80}"#
                    .utf8))
        XCTAssertTrue(monitor.isClaudeWorking)
        let event = TracingService.shared.recordedEventsForTesting.last { $0.name == "statusline.hook.event" }
        XCTAssertEqual(event?.attributes["background_task_count"], "100")
        XCTAssertEqual(event?.attributes["session_cron_count"], "80")
    }

    func testFullCountsDoNotOverrideIncompleteReportFallback() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0
        var count = 0
        monitor.onClaudeStopped = { count += 1 }
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(
            Data(
                #"{"hook_event_name":"Stop","background_tasks":[],"background_tasks_total_count":100,"session_crons_total_count":80}"#
                    .utf8))
        XCTAssertTrue(monitor.isClaudeStopped)
        XCTAssertEqual(count, 1)
    }
}
