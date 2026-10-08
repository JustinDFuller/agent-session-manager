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

    private func runScript(stdin: String, attention: Bool = false, expectedLines: Int? = 1) throws -> [String: Any] {
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

        guard let expectedLines else { return [:] }
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
        _ = try runScript(
            stdin: #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#, attention: true,
            expectedLines: nil)
        _ = try runScript(
            stdin: #"{"hook_event_name":"Notification","notification_type":"idle_prompt"}"#, attention: true,
            expectedLines: nil)
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
        _ = try runScript(
            stdin: #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#, attention: true,
            expectedLines: nil)
        _ = try runScript(
            stdin: #"{"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode"}"#, attention: true, expectedLines: nil)
        wait(for: [delivered], timeout: 3)
        XCTAssertEqual(sources, [.claudeQuestion, .claudePlanApproval])
    }

    func testAttentionQueueDeduplicatesRepeatedInputAndDoesNotReplayConsumedLines() throws {
        let input = #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#
        let first = try runScript(stdin: input, attention: true)
        let second = try runScript(stdin: input, attention: true, expectedLines: 2)
        XCTAssertEqual(first["payload_fingerprint"] as? String, second["payload_fingerprint"] as? String)
        XCTAssertNil(first["timestamp"])
        monitor.start()
        let delivered = expectation(description: "one event delivered")
        delivered.assertForOverFulfill = true
        var count = 0
        monitor.onClaudeHookAttention = { _ in
            count += 1
            delivered.fulfill()
        }
        _ = try runScript(stdin: input, attention: true, expectedLines: nil)
        _ = try runScript(stdin: input, attention: true, expectedLines: nil)
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
        _ = try runScript(
            stdin: #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#, attention: true,
            expectedLines: nil)
        let handle = try FileHandle(forWritingTo: URL(filePath: monitor.attentionSignalFilePath))
        try handle.seekToEnd()
        let finished = expectation(description: "all later writes completed")
        let idle = Data((#"{"hook_event_name":"Notification","notification_type":"idle_prompt"}"# + "\n").utf8)
        for index in 1...20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: idle)
                if index == 20 { finished.fulfill() }
            }
        }
        wait(for: [delivered], timeout: 0.7)
        wait(for: [finished], timeout: 2)
        try handle.close()
    }
    func testAttentionCompactionPreservesPartialSuffixAndFutureAppends() throws {
        monitor.start()
        let delivered = expectation(description: "complete records delivered once")
        delivered.expectedFulfillmentCount = 3
        delivered.assertForOverFulfill = true
        var sources: [PaneAttentionEvent.Source] = []
        monitor.onClaudeHookAttention = { event in
            sources.append(event.source)
            delivered.fulfill()
        }
        let first = Data((#"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"# + "\n").utf8)
        let partial = Data(#"{"hook_event_name":"PreToolUse","tool_name":"Exit"#.utf8)
        let handle = try FileHandle(forWritingTo: URL(filePath: monitor.attentionSignalFilePath))
        defer { try? handle.close() }
        try handle.write(contentsOf: first + partial)
        let compacted = expectation(description: "first record compacted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { compacted.fulfill() }
        wait(for: [compacted], timeout: 2)
        XCTAssertEqual(sources, [.claudeQuestion])
        XCTAssertEqual(try Data(contentsOf: URL(filePath: monitor.attentionSignalFilePath)), partial)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("PlanMode\"}\n".utf8) + first)
        wait(for: [delivered], timeout: 3)
        let drained = expectation(description: "all consumed history removed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(sources, [.claudeQuestion, .claudePlanApproval, .claudeQuestion])
        XCTAssertTrue(try Data(contentsOf: URL(filePath: monitor.attentionSignalFilePath)).isEmpty)
    }

    func testConcurrentHookAppendsSurviveReaderCompaction() throws {
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }
        monitor.start()
        let delivered = expectation(description: "all locked appends delivered")
        delivered.expectedFulfillmentCount = 30
        delivered.assertForOverFulfill = true
        var messages: [String] = []
        monitor.onClaudeHookAttention = { event in
            messages.append(event.reason)
            delivered.fulfill()
        }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            """
            import json, subprocess, sys, time
            for index in range(30):
                payload = json.dumps({"hook_event_name": "Notification", "notification_type": "permission_prompt", "message": str(index)})
                subprocess.run([sys.argv[1], "--attention", sys.argv[2]], input=payload.encode(), check=True)
                time.sleep(0.02)
            """,
            monitor.hookLogScriptFilePath, monitor.attentionSignalFilePath,
        ]
        try process.run()
        wait(for: [delivered], timeout: 10)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(messages, (0..<30).map(String.init))
        for failure in TracingService.shared.recordedEventsForTesting.filter({
            $0.name == "statusline.attention.read_failed"
        }) {
            XCTAssertTrue((100...1000).contains(Int(failure.attributes["retry_delay_ms"] ?? "0") ?? 0))
            XCTAssertGreaterThanOrEqual(Int(failure.attributes["retry_attempt"] ?? "0") ?? 0, 1)
        }
        let drained = expectation(description: "queue compacted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertTrue(try Data(contentsOf: URL(filePath: monitor.attentionSignalFilePath)).isEmpty)
    }

    func testAttentionOpenFailureRecordsDiagnosticWithContext() throws {
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }
        monitor.start()
        let path = monitor.attentionSignalFilePath
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
        let delivered = expectation(description: "permission-recovered event delivered without another append")
        delivered.assertForOverFulfill = true
        monitor.onClaudeHookAttention = { event in
            XCTAssertEqual(event.source, .claudeQuestion)
            delivered.fulfill()
        }
        _ = try runScript(
            stdin: #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#, attention: true,
            expectedLines: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        let read = expectation(description: "failed open observed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { read.fulfill() }
        wait(for: [read], timeout: 2)
        let event = try XCTUnwrap(
            TracingService.shared.recordedEventsForTesting.last {
                $0.name == "statusline.attention.read_failed"
            })
        for key in ["pane.id", "pane.name", "tab.id", "tab.name", "error_code"] {
            XCTAssertNotNil(event.attributes[key])
        }
        XCTAssertGreaterThanOrEqual(Int(event.attributes["retry_attempt"] ?? "0") ?? 0, 1)
        XCTAssertTrue((100...1000).contains(Int(event.attributes["retry_delay_ms"] ?? "0") ?? 0))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        wait(for: [delivered], timeout: 3)
    }

    func testAttentionRetryIsCanceledWhenWatcherRestarts() throws {
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }
        monitor.start()
        let path = monitor.attentionSignalFilePath
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
        let delivered = expectation(description: "event from restarted watcher")
        var events: [PaneAttentionEvent.Source] = []
        monitor.onClaudeHookAttention = { event in
            events.append(event.source)
            delivered.fulfill()
        }
        _ = try runScript(
            stdin: #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#, attention: true,
            expectedLines: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        let failedRead = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                TracingService.shared.recordedEventsForTesting.contains {
                    $0.name == "statusline.attention.read_failed"
                }
            }, object: nil)
        wait(for: [failedRead], timeout: 2)
        let failureCountBeforeStop = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.attention.read_failed"
        }.count
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        monitor.stop()
        monitor.start()
        let quiet = expectation(description: "canceled retry stays inactive after restart")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { quiet.fulfill() }
        wait(for: [quiet], timeout: 1)
        XCTAssertEqual(
            TracingService.shared.recordedEventsForTesting.filter { $0.name == "statusline.attention.read_failed" }
                .count, failureCountBeforeStop)
        _ = try runScript(
            stdin: #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#, attention: true,
            expectedLines: nil)
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(events, [.claudeQuestion])
    }

    func testAttentionQueueRetriesAfterLockContentionWithoutNewFileEvent() throws {
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }
        monitor.start()
        let delivered = expectation(description: "locked queue record delivered once")
        delivered.assertForOverFulfill = true
        var events: [PaneAttentionEvent.Source] = []
        monitor.onClaudeHookAttention = { event in
            events.append(event.source)
            delivered.fulfill()
        }
        let readyURL = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-attention-lock-ready-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: readyURL) }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            """
            import fcntl, os, sys, time
            fd = os.open(sys.argv[1], os.O_WRONLY | os.O_APPEND)
            fcntl.flock(fd, fcntl.LOCK_EX)
            os.write(fd, sys.stdin.buffer.read())
            open(sys.argv[2], "wb").close()
            time.sleep(2.8)
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)
            """,
            monitor.attentionSignalFilePath,
            readyURL.path,
        ]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(
            Data((#"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"# + "\n").utf8))
        try input.fileHandleForWriting.close()
        let writerHoldingLock = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: readyURL.path) }, object: nil)
        wait(for: [writerHoldingLock], timeout: 2)
        let failedRead = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                TracingService.shared.recordedEventsForTesting.contains {
                    $0.name == "statusline.attention.read_failed"
                }
            }, object: nil)
        wait(for: [failedRead], timeout: 2)
        let failure = try XCTUnwrap(
            TracingService.shared.recordedEventsForTesting.first {
                $0.name == "statusline.attention.read_failed"
            })
        XCTAssertGreaterThanOrEqual(Int(failure.attributes["retry_attempt"] ?? "0") ?? 0, 1)
        XCTAssertTrue((100...1000).contains(Int(failure.attributes["retry_delay_ms"] ?? "0") ?? 0))
        wait(for: [delivered], timeout: 6)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let failures = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.attention.read_failed"
        }
        let delays = failures.compactMap { Int($0.attributes["retry_delay_ms"] ?? "") }
        XCTAssertTrue(delays.contains(1000))
        XCTAssertTrue(delays.allSatisfy { (100...1000).contains($0) })
        XCTAssertEqual(failures.compactMap { Int($0.attributes["retry_attempt"] ?? "") }, Array(1...failures.count))
        let quiet = expectation(description: "retry does not redeliver the event")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { quiet.fulfill() }
        wait(for: [quiet], timeout: 1)
        XCTAssertEqual(events, [.claudeQuestion])
        XCTAssertTrue(try Data(contentsOf: URL(filePath: monitor.attentionSignalFilePath)).isEmpty)
    }
    func testAttentionRetryBackoffResetsAfterSuccessfulDrain() throws {
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }
        monitor.start()
        let path = monitor.attentionSignalFilePath
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
        let firstDelivered = expectation(description: "first blocked event recovered")
        let secondDelivered = expectation(description: "second blocked event recovered")
        firstDelivered.assertForOverFulfill = true
        secondDelivered.assertForOverFulfill = true
        monitor.onClaudeHookAttention = { event in
            if event.source == .claudeQuestion {
                firstDelivered.fulfill()
            } else {
                XCTAssertEqual(event.source, .claudePermissionRequest)
                secondDelivered.fulfill()
            }
        }
        _ = try runScript(
            stdin: #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#, attention: true,
            expectedLines: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        let capped = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                TracingService.shared.recordedEventsForTesting.contains {
                    $0.name == "statusline.attention.read_failed" && $0.attributes["retry_delay_ms"] == "1000"
                }
            }, object: nil)
        wait(for: [capped], timeout: 6)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        wait(for: [firstDelivered], timeout: 3)
        let compacted = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (try? Data(contentsOf: URL(filePath: path)).isEmpty) == true
            }, object: nil)
        wait(for: [compacted], timeout: 3)
        let failureCount = TracingService.shared.recordedEventsForTesting.filter {
            $0.name == "statusline.attention.read_failed"
        }.count
        _ = try runScript(
            stdin: #"{"hook_event_name":"PermissionRequest","tool_name":"Bash"}"#,
            attention: true, expectedLines: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        let failedAgain = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                TracingService.shared.recordedEventsForTesting.filter {
                    $0.name == "statusline.attention.read_failed"
                }.count > failureCount
            }, object: nil)
        wait(for: [failedAgain], timeout: 3)
        let nextFailure = try XCTUnwrap(
            TracingService.shared.recordedEventsForTesting.filter {
                $0.name == "statusline.attention.read_failed"
            }.dropFirst(failureCount).first)
        XCTAssertEqual(nextFailure.attributes["retry_attempt"], "1")
        XCTAssertEqual(nextFailure.attributes["retry_delay_ms"], "100")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        wait(for: [secondDelivered], timeout: 3)
    }
}
