import Foundation
import XCTest

final class ClaudeNotificationFlowTests: BaseTestCase {
    private var hookLogURL: URL!

    private func openClaudePane(named name: String) throws {
        let status = Process()
        let output = Pipe()
        status.executableURL = URL(filePath: "/bin/zsh")
        status.arguments = ["-i", "-c", "claude auth status --json"]
        status.standardOutput = output
        status.standardError = FileHandle.nullDevice
        try status.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        status.waitUntilExit()
        guard status.terminationStatus == 0,
            let authentication = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            authentication["loggedIn"] as? Bool == true
        else {
            throw XCTSkip("Real Claude notification flows require an installed, authenticated Claude Code")
        }

        app.typeKey(",", modifierFlags: .command)
        app.buttons["Debug"].click()
        let debugToggle = app.checkBoxes["settings-debug-mode-toggle"]
        waitFor(debugToggle)
        if debugToggle.value as? Int != 1 { debugToggle.click() }
        app.typeKey("w", modifierFlags: .command)
        createTab(named: "ClaudeAlerts")
        app.typeKey("p", modifierFlags: .command)
        let nameField = app.textFields["new-pane-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText(name)
        app.buttons["new-pane-cli-options-button"].click()
        app.buttons["new-pane-show-hidden-options-button"].click()
        let allowTools = app.checkBoxes.matching(NSPredicate(format: "label == %@", "--allowedTools")).firstMatch
        let options = app.scrollViews["new-pane-cli-options-content-scroll-view"]
        for _ in 0..<20 where !allowTools.isHittable { options.scroll(byDeltaX: 0, deltaY: -160) }
        waitFor(allowTools)
        if allowTools.value as? Int != 1 { allowTools.click() }
        let allowedValue = app.textFields["cli-option-value-field---allowedTools"]
        waitFor(allowedValue)
        allowedValue.click()
        allowedValue.typeText("Bash(sleep 90),AskUserQuestion")
        app.buttons["new-pane-cli-options-done-button"].click()
        app.buttons["new-pane-open-button"].click()
        waitForDisappear(nameField, timeout: 30)
        waitFor(app.staticTexts["pane-name-\(name)"].firstMatch, timeout: 20)

        let sessionURL = UITestAppSupport.directory.appending(path: "sessions.json")
        let sessions = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sessionURL)) as? [String: Any])
        let tabs = try XCTUnwrap(sessions["tabs"] as? [[String: Any]])
        let panes = try XCTUnwrap(tabs.first?["panes"] as? [[String: Any]])
        let paneID = try XCTUnwrap(panes.first?["id"] as? String)
        hookLogURL = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-claude-hooklog-\(paneID).jsonl")
    }

    private func waitForLiveRecord(
        at url: URL, timeout: TimeInterval = 90, matching predicate: @escaping ([String: Any]) -> Bool
    ) throws -> [String: Any] {
        var found: [String: Any]?
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let data = try? Data(contentsOf: url),
                    let text = String(data: data.suffix(262_144), encoding: .utf8)
                else { return false }
                found = text.split(separator: "\n").suffix(100).compactMap { line in
                    try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                }.last(where: predicate)
                return found != nil
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, "Expected real Claude event")
        return try XCTUnwrap(found)
    }

    private func launchBackgroundSleep() throws {
        typeTerminalCommand(
            "Use Bash with run_in_background=true to run exactly sleep 90. Immediately reply Background sleep launched. Do not wait or poll and do not use another tool."
        )
        _ = try waitForLiveRecord(at: hookLogURL) { record in
            record["hook_event_name"] as? String == "Stop"
                && (record["background_tasks"] as? [[String: Any]])?.contains { $0["type"] as? String == "shell" }
                    == true
                && record["session_crons"] is [[String: Any]]
        }
    }

    func testBackgroundShellKeepsWorkingUntilRealCompletion() throws {
        try openClaudePane(named: "background-alert")
        try launchBackgroundSleep()
        waitFor(
            app.descendants(matching: .any).matching(identifier: "pane-activity-working-background-alert").firstMatch)
        XCTAssertFalse(app.buttons["notification-row-background-alert"].exists)
        screenshot("claude-background-work")
        _ = try waitForLiveRecord(at: hookLogURL, timeout: 120) { record in
            record["hook_event_name"] as? String == "Stop"
                && (record["background_tasks"] as? [[String: Any]])?.isEmpty == true
                && (record["session_crons"] as? [[String: Any]])?.isEmpty == true
        }
        waitFor(app.buttons["notification-row-background-alert"], timeout: 10)
        waitFor(app.staticTexts["Claude finished responding"].firstMatch)
    }

    func testQuestionProducesRealAttention() throws {
        try openClaudePane(named: "question-alert")
        try launchBackgroundSleep()
        typeTerminalCommand(
            "Use AskUserQuestion now to ask me to choose Red or Blue. You must call the tool, not ask in prose.")
        waitFor(app.buttons["notification-row-question-alert"], timeout: 90)
        waitFor(app.staticTexts["Claude has a question"].firstMatch)
        screenshot("claude-question-attention")
    }

    func testPlanApprovalProducesRealAttention() throws {
        try openClaudePane(named: "plan-alert")
        try launchBackgroundSleep()
        typeTerminalCommand("/plan")
        typeTerminalCommand(
            "Plan one small change: create hello.txt containing hello. Do not implement or inspect files. Present the plan and call ExitPlanMode to request approval now."
        )
        waitFor(app.buttons["notification-row-plan-alert"], timeout: 90)
        waitFor(app.staticTexts["Claude needs plan approval"].firstMatch)
        screenshot("claude-plan-approval-attention")
    }

    func testEscRecoversOnRealIdleWithoutFinishedAlert() throws {
        try openClaudePane(named: "interrupt-alert")
        typeTerminalCommand(
            "Run exactly sleep 90 using Bash in the foreground. Do not background it and do not use another tool.")
        let prompt = try waitForLiveRecord(at: hookLogURL) { $0["hook_event_name"] as? String == "UserPromptSubmit" }
        let transcript = URL(filePath: try XCTUnwrap(prompt["transcript_path"] as? String))
        _ = try waitForLiveRecord(at: transcript) { record in
            guard let message = record["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            else { return false }
            return content.contains { item in
                item["type"] as? String == "tool_use" && item["name"] as? String == "Bash"
                    && (item["input"] as? [String: Any])?["command"] as? String == "sleep 90"
            }
        }
        app.typeKey(.escape, modifierFlags: [])
        _ = try waitForLiveRecord(at: hookLogURL, timeout: 100) { $0["notification_type"] as? String == "idle_prompt" }
        waitFor(app.buttons["notification-row-interrupt-alert"], timeout: 10)
        XCTAssertFalse(app.staticTexts["Claude finished responding"].exists)
        let working = app.descendants(matching: .any).matching(identifier: "pane-activity-working-interrupt-alert")
            .firstMatch
        waitForDisappear(working)
        let log = try String(contentsOf: hookLogURL, encoding: .utf8)
        XCTAssertFalse(
            log.split(separator: "\n").contains { line in
                guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                    return false
                }
                return record["hook_event_name"] as? String == "Stop"
            })
        screenshot("claude-interrupted-idle-recovery")
    }
}
