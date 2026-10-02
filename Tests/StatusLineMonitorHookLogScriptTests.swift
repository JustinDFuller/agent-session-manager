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
        try? FileManager.default.removeItem(atPath: monitor.hookLogFilePath)
        try? FileManager.default.removeItem(atPath: monitor.hookLogScriptFilePath)
        super.tearDown()
    }

    private func runScript(stdin: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(filePath: monitor.hookLogScriptFilePath)
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let log = try String(contentsOfFile: monitor.hookLogFilePath, encoding: .utf8)
        let lines = log.split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(try XCTUnwrap(lines.first).utf8)) as? [String: Any])
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
}
