import XCTest

@testable import AgentSessionManager

@MainActor
final class CodexActivityTests: XCTestCase {
    func testForegroundCompletionWaitsForGraceAndNewTurnCancelsIt() async throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
        monitor.stopNotificationGracePeriod = 0.08
        var stoppedCount = 0
        monitor.onCodexStopped = { stoppedCount += 1 }

        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-one", isForeground: true))
        monitor.applyCodexEvent(.foregroundCompletionCandidate(turnID: "foreign-turn"))
        XCTAssertTrue(monitor.isCodexWorking)
        monitor.applyCodexEvent(
            .foregroundTurnCompleted(turnID: "turn-one", isForeground: true, succeeded: true))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(stoppedCount, 0)
        monitor.applyCodexEvent(.foregroundCompletionCandidate(turnID: "turn-one"))
        XCTAssertTrue(monitor.isCodexStopped)
        try await Task.sleep(for: .milliseconds(30))
        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-two", isForeground: true))
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(stoppedCount, 0)
        XCTAssertTrue(monitor.isCodexWorking)

        let delivered = expectation(description: "foreground completion alert delivered after grace")
        monitor.onCodexStopped = {
            stoppedCount += 1
            delivered.fulfill()
        }
        monitor.applyCodexEvent(
            .foregroundTurnCompleted(turnID: "turn-two", isForeground: true, succeeded: true))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(stoppedCount, 0)
        monitor.applyCodexEvent(.foregroundCompletionCandidate(turnID: "turn-two"))
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(stoppedCount, 1)
        let activityEvents = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.codex.activity.changed"
        }
        XCTAssertTrue(activityEvents.contains { $0.attributes["state"] == "completion_scheduled" })
        XCTAssertTrue(
            activityEvents.contains {
                $0.attributes["state"] == "completion_canceled"
                    && $0.attributes["reason"] == "new_foreground_turn"
            })
        XCTAssertTrue(activityEvents.contains { $0.attributes["state"] == "completion_ready" })
        XCTAssertTrue(
            activityEvents.allSatisfy {
                $0.attributes["pane.id"] != nil && $0.attributes["tab.id"] != nil
                    && $0.attributes["pane.name"] != nil && $0.attributes["tab.name"] != nil
            })
        monitor.stop()
    }

    func testFailureInterruptionExitAndTeardownDoNotDeliverCompletion() async throws {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
        monitor.stopNotificationGracePeriod = 0.04
        var stoppedCount = 0
        monitor.onCodexStopped = { stoppedCount += 1 }

        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-fail", isForeground: true))
        monitor.applyCodexEvent(.foregroundCompletionCandidate(turnID: "turn-fail"))
        monitor.applyCodexEvent(
            .foregroundTurnCompleted(turnID: "turn-fail", isForeground: true, succeeded: false))
        XCTAssertTrue(monitor.isCodexStopped)
        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-fail-before-stop", isForeground: true))
        monitor.applyCodexEvent(
            .foregroundTurnCompleted(turnID: "turn-fail-before-stop", isForeground: true, succeeded: false))
        monitor.applyCodexEvent(.foregroundCompletionCandidate(turnID: "turn-fail-before-stop"))
        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-interrupt", isForeground: true))
        monitor.applyCodexEvent(.foregroundCompletionCandidate(turnID: "turn-interrupt"))
        monitor.applyCodexEvent(.foregroundTurnInterrupted(turnID: "turn-interrupt", isForeground: true))
        XCTAssertTrue(monitor.isCodexStopped)
        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-rebind", isForeground: true))
        monitor.applyCodexEvent(.foregroundCompletionCandidate(turnID: "turn-rebind"))
        monitor.applyCodexEvent(.foregroundTurnInterrupted(turnID: nil, isForeground: true))
        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-exit", isForeground: true))
        monitor.applyCodexEvent(.foregroundCompletionCandidate(turnID: "turn-exit"))
        monitor.codexProcessExited()
        XCTAssertFalse(monitor.isCodexWorking)
        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-catchup", isForeground: true))
        monitor.applyCodexEvent(.foregroundCompletionCandidate(turnID: "turn-catchup"), isCatchUp: true)
        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-teardown", isForeground: true))
        monitor.applyCodexEvent(.foregroundCompletionCandidate(turnID: "turn-teardown"))
        monitor.stop()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(stoppedCount, 0)
    }

    func testFailedRolloutCancelsAnExactSessionHookCompletion() async throws {
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
        monitor.stopNotificationGracePeriod = 0.05
        var stoppedCount = 0
        monitor.onCodexStopped = { stoppedCount += 1 }
        let prompt = CodexHookQueueRecord(
            paneID: "pane",
            tabID: "tab",
            launchGeneration: "generation",
            hookEventName: "UserPromptSubmit",
            sessionID: "session-current",
            turnID: "turn-current",
            requestID: nil,
            timestamp: 1,
            source: "hook",
            model: nil,
            transcriptPath: nil,
            result: nil)
        let stop = CodexHookQueueRecord(
            paneID: "pane",
            tabID: "tab",
            launchGeneration: "generation",
            hookEventName: "Stop",
            sessionID: "session-current",
            turnID: "turn-current",
            requestID: nil,
            timestamp: 2,
            source: "hook",
            model: nil,
            transcriptPath: nil,
            result: nil)

        monitor.handleCodexHookRecords([prompt])
        monitor.handleCodexHookRecords([stop])
        monitor.applyCodexEvent(
            .foregroundTurnCompleted(turnID: "turn-current", isForeground: true, succeeded: false))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(stoppedCount, 0)
        XCTAssertTrue(
            TracingService.shared.recordedEventsForTesting.contains {
                $0.name == "statusline.codex.completion"
                    && $0.attributes["phase"] == "canceled"
                    && $0.attributes["reason"] == "turn_failed"
            })
        monitor.stop()
    }

    func testPermissionAndQuestionAttentionUseFixedCopyAndExactQuestionCallIdentity() {
        let monitor = StatusLineMonitor(paneID: UUID(), harness: .codex)
        var attentions: [PaneAttentionEvent] = []
        var attentionClears = 0
        var questionClears = 0
        monitor.onCodexAttention = { attentions.append($0) }
        monitor.onCodexAttentionCleared = { attentionClears += 1 }
        monitor.onCodexQuestionCleared = { questionClears += 1 }

        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-a", isForeground: true))
        XCTAssertEqual(attentionClears, 0)
        monitor.applyCodexEvent(.permissionRequested(turnID: "turn-a"))
        monitor.applyCodexEvent(.permissionRequested(turnID: "turn-a"))
        monitor.applyCodexEvent(.questionRequested(callID: "question-a"))
        monitor.applyCodexEvent(.questionRequested(callID: "question-a"))
        XCTAssertEqual(attentions.map(\.reason), ["Codex needs your approval", "Codex is waiting for your answer"])

        monitor.applyCodexEvent(.questionResolved(callID: "other-question"))
        XCTAssertEqual(questionClears, 0)
        XCTAssertEqual(attentionClears, 0)
        monitor.applyCodexEvent(.questionResolved(callID: "question-a"))
        XCTAssertEqual(questionClears, 1)
        monitor.applyCodexEvent(.questionResolved(callID: "question-a"))
        XCTAssertEqual(questionClears, 1)

        monitor.applyCodexEvent(.foregroundTurnStarted(turnID: "turn-b", isForeground: true))
        XCTAssertEqual(attentionClears, 1)
        monitor.applyCodexEvent(.permissionRequested(turnID: "turn-b"))
        XCTAssertEqual(attentions.last?.reason, "Codex needs your approval")
        monitor.acknowledgeCodexAttention(kind: .codexQuestion)
        monitor.applyCodexEvent(.permissionRequested(turnID: "turn-b"))
        XCTAssertEqual(attentions.count, 3)
        monitor.acknowledgeCodexAttention()
        monitor.applyCodexEvent(.permissionRequested(turnID: "turn-b"))
        XCTAssertEqual(attentions.count, 4)
        monitor.stop()
    }

    func testCodexActivityUsesExistingPaneAndTabPriority() {
        XCTAssertEqual(
            paneActivityState(
                processState: .running(pid: 1), isWorking: true, sessionState: nil, hasNotification: false),
            .working)
        XCTAssertEqual(
            paneActivityState(
                processState: .running(pid: 1), isWorking: false, isStopped: true,
                sessionState: nil, hasNotification: false),
            .stopped)
        XCTAssertEqual(
            paneActivityState(
                processState: .running(pid: 1), isWorking: true, sessionState: nil, hasNotification: true),
            .waiting)
        XCTAssertEqual(tabActivityState([.stopped, .working]), .working)
        XCTAssertEqual(tabActivityState([.stopped, .waiting]), .waiting)
    }
}
