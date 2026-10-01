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

    private func hookEventDecisions(for hookEvent: String) -> [String?] {
        TracingService.shared.recordedEventsForTesting
            .filter { $0.name == "statusline.hook.event" && $0.attributes["hook_event"] == hookEvent }
            .map { $0.attributes["decision"] }
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
    }

    func testStopTraceDecisionsAcrossSuppressedThenFiredSequence() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.stopNotificationGracePeriod = 0

        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.stop(tasks: "[\(Self.task(type: "subagent"))]"))
        monitor.testApplyClaudeActivityPayload(Self.userPromptSubmit)
        monitor.testApplyClaudeActivityPayload(Self.stop())

        XCTAssertEqual(hookEventDecisions(for: "Stop"), ["suppressed_background_work", "fired"])
    }

    func testStopMissingBackgroundTasksReportsInvariantAndStillStops() {
        assertMissingListReportsInvariantAndStillStops(
            payload: #"{"hook_event_name":"Stop","session_crons":[]}"#)
    }

    func testStopMissingSessionCronsReportsInvariantAndStillStops() {
        assertMissingListReportsInvariantAndStillStops(
            payload: #"{"hook_event_name":"Stop","background_tasks":[]}"#)
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
        XCTAssertEqual(suppressed.first?.attributes["reason"], "pane_working")
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
}
