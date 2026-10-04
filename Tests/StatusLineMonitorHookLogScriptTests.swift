import XCTest

@testable import AgentSessionManager

@MainActor
final class StatusLineMonitorHookLogScriptTests: XCTestCase {
    private var monitor: StatusLineMonitor!

    override func setUp() {
        super.setUp()
        monitor = StatusLineMonitor(paneID: UUID(), harness: .claude)
        monitor.writeHookLogScript()
        try? FileManager.default.removeItem(atPath: monitor.hookLogFilePath)
    }

    override func tearDown() {
        monitor.stop()
        super.tearDown()
    }

    private func runScript(stdin: String, attention: Bool = false, expectedLines: Int = 1) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(filePath: monitor.hookLogScriptFilePath)
        if attention { process.arguments = ["--attention", monitor.attentionSignalFilePath] }
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let log = try String(
            contentsOfFile: attention ? monitor.attentionSignalFilePath : monitor.hookLogFilePath, encoding: .utf8)
        let lines = log.split(separator: "\n")
        XCTAssertEqual(lines.count, expectedLines)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(try XCTUnwrap(lines.last).utf8)) as? [String: Any])
    }

    func testStopRecordsOnlyTaskAndCronFieldsNeededForTracing() throws {
        let record = try runScript(
            stdin: """
                {
                  "session_id": "abc123",
                  "transcript_path": "/tmp/transcript.jsonl",
                  "cwd": "/tmp/project",
                  "permission_mode": "default",
                  "hook_event_name": "Stop",
                  "stop_hook_active": false,
                  "last_assistant_message": "Done.",
                  "background_tasks": [
                    {
                      "id": "task-001",
                      "type": "shell",
                      "status": "running",
                      "description": "tail logs",
                      "command": "tail -f /var/log/syslog"
                    },
                    {
                      "id": "task-002",
                      "type": "subagent",
                      "status": "running",
                      "description": "review the diff",
                      "agent_type": "general-purpose"
                    }
                  ],
                  "session_crons": [
                    {
                      "id": "cron-001",
                      "schedule": "0 9 * * 1-5",
                      "recurring": true,
                      "prompt": "check the build"
                    }
                  ]
                }
                """)

        XCTAssertEqual(record["hook_event_name"] as? String, "Stop")
        let tasks = try XCTUnwrap(record["background_tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(
            tasks[0] as NSDictionary, ["id": "task-001", "type": "shell", "status": "running"] as NSDictionary)
        XCTAssertEqual(
            tasks[1] as NSDictionary, ["id": "task-002", "type": "subagent", "status": "running"] as NSDictionary)
        let crons = try XCTUnwrap(record["session_crons"] as? [[String: Any]])
        XCTAssertEqual(crons.count, 1)
        XCTAssertEqual(crons[0] as NSDictionary, ["id": "cron-001", "recurring": true] as NSDictionary)
    }

    func testStopWithEmptyListsRecordsEmptyLists() throws {
        let record = try runScript(
            stdin: #"{"hook_event_name":"Stop","background_tasks":[],"session_crons":[]}"#)

        XCTAssertEqual((record["background_tasks"] as? [Any])?.count, 0)
        XCTAssertEqual((record["session_crons"] as? [Any])?.count, 0)
    }

    func testStopWithoutListsRecordsNoLists() throws {
        let record = try runScript(stdin: #"{"hook_event_name":"Stop"}"#)

        XCTAssertNil(record["background_tasks"] as? [Any])
        XCTAssertNil(record["session_crons"] as? [Any])
    }

    func testNotificationRecordsNotificationType() throws {
        let record = try runScript(
            stdin: """
                {
                  "session_id": "abc123",
                  "hook_event_name": "Notification",
                  "message": "Claude is waiting for your input",
                  "notification_type": "idle_prompt"
                }
                """)

        XCTAssertEqual(record["hook_event_name"] as? String, "Notification")
        XCTAssertEqual(record["notification_type"] as? String, "idle_prompt")
        XCTAssertEqual(record["message"] as? String, "Claude is waiting for your input")
    }
    func testLargeStopRecordsBoundedSamplesAndFullCounts() throws {
        let large = String(repeating: "\u{0001}", count: 1024)
        let payload: [String: Any] = [
            "hook_event_name": "Stop", "message": large,
            "background_tasks": Array(
                repeating: ["id": large, "type": large, "status": large, "command": large], count: 100),
            "session_crons": Array(
                repeating: ["id": large, "recurring": true, "prompt": large] as [String: Any], count: 100),
        ]
        let input = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let record = try runScript(stdin: input)
        let tasks = try XCTUnwrap(record["background_tasks"] as? [[String: Any]])
        let crons = try XCTUnwrap(record["session_crons"] as? [[String: Any]])
        XCTAssertEqual(tasks.count, 32)
        XCTAssertEqual(crons.count, 32)
        XCTAssertEqual(record["background_tasks_total_count"] as? Int, 100)
        XCTAssertEqual(record["session_crons_total_count"] as? Int, 100)
        XCTAssertEqual(record["background_tasks_omitted_count"] as? Int, 68)
        XCTAssertEqual(record["session_crons_omitted_count"] as? Int, 68)
        XCTAssertTrue(
            tasks.allSatisfy {
                ($0["id"] as? String)?.utf8.count == 64 && ($0["type"] as? String)?.utf8.count == 64
                    && ($0["status"] as? String)?.utf8.count == 32 && $0["command"] == nil
            })
        XCTAssertTrue(crons.allSatisfy { ($0["id"] as? String)?.utf8.count == 64 && $0["prompt"] == nil })
        XCTAssertLessThan(try Data(contentsOf: URL(filePath: monitor.hookLogFilePath)).count, 65_536)
        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(try JSONSerialization.data(withJSONObject: record))
        XCTAssertTrue(monitor.isClaudeWorking)
    }

    func testAttentionBurstRetainsQuestionWhenLaterIdleIsSuppressed() throws {
        monitor.start()
        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(
            Data(#"{"hook_event_name":"Stop","background_tasks":[{"type":"shell"}],"session_crons":[]}"#.utf8))
        let delivered = expectation(description: "question retained")
        delivered.assertForOverFulfill = true
        var sources: [PaneAttentionEvent.Source] = []
        monitor.onClaudeHookAttention = { event in
            sources.append(event.source)
            delivered.fulfill()
        }
        _ = try runScript(stdin: #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#, attention: true)
        _ = try runScript(
            stdin: #"{"hook_event_name":"Notification","notification_type":"idle_prompt"}"#, attention: true,
            expectedLines: 2)
        wait(for: [delivered], timeout: 3)
        let drained = expectation(description: "burst drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(sources, [.claudeQuestion])
        XCTAssertTrue(monitor.isClaudeWorking)
    }

    func testAttentionBurstDeliversQuestionAndPlanInOrder() throws {
        monitor.start()
        let delivered = expectation(description: "both events retained")
        delivered.expectedFulfillmentCount = 2
        delivered.assertForOverFulfill = true
        var sources: [PaneAttentionEvent.Source] = []
        monitor.onClaudeHookAttention = { event in
            sources.append(event.source)
            delivered.fulfill()
        }
        _ = try runScript(stdin: #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#, attention: true)
        _ = try runScript(
            stdin: #"{"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode"}"#, attention: true, expectedLines: 2)
        wait(for: [delivered], timeout: 3)
        XCTAssertEqual(sources, [.claudeQuestion, .claudePlanApproval])
    }

    func testAttentionQueueDeduplicatesRepeatedInputAndDoesNotReplayConsumedLines() throws {
        monitor.start()
        let delivered = expectation(description: "one event delivered")
        delivered.assertForOverFulfill = true
        var count = 0
        monitor.onClaudeHookAttention = { _ in
            count += 1
            delivered.fulfill()
        }
        let input = #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#
        let first = try runScript(stdin: input, attention: true)
        let second = try runScript(stdin: input, attention: true, expectedLines: 2)
        XCTAssertEqual(first["payload_fingerprint"] as? String, second["payload_fingerprint"] as? String)
        XCTAssertNil(first["timestamp"])
        wait(for: [delivered], timeout: 3)
        let handle = try FileHandle(forWritingTo: URL(filePath: monitor.attentionSignalFilePath))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
        let drained = expectation(description: "duplicate drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(count, 1)
    }

    func testAttentionQueueRetainsIncompleteLineUntilNextAppend() throws {
        monitor.start()
        let delivered = expectation(description: "completed record delivered")
        delivered.assertForOverFulfill = true
        var count = 0
        monitor.onClaudeHookAttention = { _ in
            count += 1
            delivered.fulfill()
        }
        let handle = try FileHandle(forWritingTo: URL(filePath: monitor.attentionSignalFilePath))
        try handle.write(contentsOf: Data(#"{"hook_event_name":"PreToolUse","tool_name":"Ask"#.utf8))
        let incomplete = expectation(description: "partial read completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { incomplete.fulfill() }
        wait(for: [incomplete], timeout: 1)
        XCTAssertEqual(count, 0)
        try handle.write(contentsOf: Data("UserQuestion\"}\n".utf8))
        try handle.close()
        wait(for: [delivered], timeout: 3)
        XCTAssertEqual(count, 1)
    }

    func testAttentionQueueDrainsWhileMoreEventsContinueArriving() throws {
        monitor.start()
        monitor.testApplyClaudeActivityPayload(Data(#"{"hook_event_name":"UserPromptSubmit"}"#.utf8))
        monitor.testApplyClaudeActivityPayload(
            Data(#"{"hook_event_name":"Stop","background_tasks":[{"type":"shell"}],"session_crons":[]}"#.utf8))
        let delivered = expectation(description: "question delivered before stream ends")
        delivered.assertForOverFulfill = true
        monitor.onClaudeHookAttention = { event in
            XCTAssertEqual(event.source, .claudeQuestion)
            delivered.fulfill()
        }
        _ = try runScript(stdin: #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#, attention: true)
        let handle = try FileHandle(forWritingTo: URL(filePath: monitor.attentionSignalFilePath))
        try handle.seekToEnd()
        let finished = expectation(description: "all later writes completed")
        let idle = Data((#"{"hook_event_name":"Notification","notification_type":"idle_prompt"}"# + "\n").utf8)
        for index in 1...20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                try? handle.write(contentsOf: idle)
                if index == 20 { finished.fulfill() }
            }
        }
        wait(for: [delivered], timeout: 0.7)
        wait(for: [finished], timeout: 2)
        try handle.close()
    }
}
