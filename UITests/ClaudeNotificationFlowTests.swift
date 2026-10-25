import AppKit
import Foundation
import XCTest

final class ClaudeNotificationFlowTests: BaseTestCase {
    private var hookLogURL: URL!

    override var appLaunchArguments: [String] { ["--uitesting-skip-restore"] + additionalLaunchArguments }

    private func createRealTab(named name: String) {
        app.typeKey("t", modifierFlags: .command)
        let nameField = app.textFields["new-tab-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText(name)
        app.buttons["new-tab-choose-dir-button"].click()
        let picker = app.dialogs["open-panel"]
        let selectDirectory = picker.buttons["OKButton"]
        waitFor(selectDirectory)
        let pickerInitiallyReady = expectation(
            for: NSPredicate(format: "hittable == true"), evaluatedWith: selectDirectory)
        wait(for: [pickerInitiallyReady], timeout: 15)
        picker.typeKey("g", modifierFlags: [.command, .shift])
        let folderEntryReady = expectation(
            for: NSPredicate(format: "hittable == false"), evaluatedWith: selectDirectory)
        wait(for: [folderEntryReady], timeout: 15)
        picker.typeKey("a", modifierFlags: .command)
        picker.typeText(GitUITestWorkspace.directoryURL.path)
        picker.typeKey(.enter, modifierFlags: [])
        let pickerReady = expectation(
            for: NSPredicate(format: "hittable == true"), evaluatedWith: selectDirectory)
        wait(for: [pickerReady], timeout: 15)
        selectDirectory.click()
        let directoryLabel = app.staticTexts["new-tab-directory-label"]
        waitFor(directoryLabel)
        XCTAssertEqual(
            (directoryLabel.value as? String).map { URL(filePath: $0).resolvingSymlinksInPath().path },
            GitUITestWorkspace.directoryURL.resolvingSymlinksInPath().path)
        let createButton = app.buttons["new-tab-create-button"]
        XCTAssertTrue(createButton.isEnabled)
        createButton.click()
        waitFor(app.buttons["tab-button-\(name)"].firstMatch)
    }

    func testRealWorkspacePickerCreatesTab() {
        let onboardingSkipButton = app.buttons["onboarding-skip-button"]
        waitFor(onboardingSkipButton)
        onboardingSkipButton.click()
        createRealTab(named: "ClaudePicker")
        XCTAssertFalse(app.textFields["new-tab-name-field"].exists)
    }

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

        let onboardingSkipButton = app.buttons["onboarding-skip-button"]
        waitFor(onboardingSkipButton)
        onboardingSkipButton.click()

        app.typeKey(",", modifierFlags: .command)
        app.buttons["Debug"].click()
        let debugToggle = app.checkBoxes["settings-debug-mode-toggle"]
        waitFor(debugToggle)
        if debugToggle.value as? Int != 1 { debugToggle.click() }
        app.typeKey("w", modifierFlags: .command)
        createRealTab(named: "ClaudeAlerts")
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

        let claudeTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-\(name)").firstMatch
        waitFor(claudeTerminal)
        claudeTerminal.click()
        let worktreeURL = GitUITestWorkspace.directoryURL
            .appending(path: ".agent-session-manager/worktrees/\(name)")
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let expectedWorktreePath = worktreeURL.path.filter { !$0.isWhitespace }
        typealias PasteboardRepresentation = (type: NSPasteboard.PasteboardType, data: Data)
        let priorPasteboardItems: [[PasteboardRepresentation]] = {
            var snapshots: [[PasteboardRepresentation]] = []
            for pasteboardItem in NSPasteboard.general.pasteboardItems ?? [] {
                var representations: [PasteboardRepresentation] = []
                for type in pasteboardItem.types {
                    if let data = pasteboardItem.data(forType: type) {
                        representations.append((type: type, data: data))
                    }
                }
                snapshots.append(representations)
            }
            return snapshots
        }()
        defer {
            NSPasteboard.general.clearContents()
            var restoredItems: [NSPasteboardItem] = []
            for representations in priorPasteboardItems {
                let item = NSPasteboardItem()
                for representation in representations {
                    item.setData(representation.data, forType: representation.type)
                }
                restoredItems.append(item)
            }
            if !restoredItems.isEmpty {
                _ = NSPasteboard.general.writeObjects(restoredItems)
            }
        }
        var trustAccepted = false
        var startupReady = false
        let startupDeadline = Date().addingTimeInterval(60)
        while Date() < startupDeadline && !startupReady {
            claudeTerminal.typeKey("a", modifierFlags: .command)
            claudeTerminal.typeKey("c", modifierFlags: .command)
            let terminalOutput = NSPasteboard.general.string(forType: .string) ?? ""
            let normalizedOutput = terminalOutput.filter { !$0.isWhitespace }
            let trustPromptIsVisible =
                normalizedOutput.contains("Accessingworkspace:")
                && normalizedOutput.contains("Quicksafetycheck:")
                && normalizedOutput.contains("No,exit")
                && normalizedOutput.contains("Yes,Itrustthisfolder")

            if trustPromptIsVisible && !trustAccepted {
                guard normalizedOutput.contains(expectedWorktreePath) else {
                    XCTFail("Claude Code showed a trust prompt for a different workspace")
                    break
                }
                let exitOptionIsSelected =
                    normalizedOutput.contains("›No,exit")
                    || normalizedOutput.contains("❯No,exit")
                    || normalizedOutput.contains(">No,exit")
                let trustOptionIsSelected =
                    normalizedOutput.contains("›Yes,Itrustthisfolder")
                    || normalizedOutput.contains("❯Yes,Itrustthisfolder")
                    || normalizedOutput.contains(">Yes,Itrustthisfolder")
                if exitOptionIsSelected {
                    claudeTerminal.typeKey(.downArrow, modifierFlags: [])
                } else if !trustOptionIsSelected {
                    XCTFail("Claude Code showed an unexpected workspace trust selection")
                    break
                }
                claudeTerminal.typeKey(.enter, modifierFlags: [])
                trustAccepted = true
            }

            startupReady =
                !trustPromptIsVisible
                && normalizedOutput.contains("ClaudeCodev")
                && normalizedOutput.contains("UITestWorkspace/.agent-session-manager/worktrees/\(name)")
            if !startupReady {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }
        _ = try XCTUnwrap(
            startupReady ? true : nil,
            "Claude Code did not reach its interactive workspace prompt within 60 seconds")

        let sessionURL = UITestAppSupport.directory.appending(path: "sessions.json")
        let sessions = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sessionURL)) as? [String: Any])
        let tabs = try XCTUnwrap(sessions["tabs"] as? [[String: Any]])
        let panes = try XCTUnwrap(tabs.first?["panes"] as? [[String: Any]])
        let paneID = try XCTUnwrap(panes.first?["id"] as? String)
        hookLogURL = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-claude-hooklog-\(paneID).jsonl")
    }

    private func waitForLiveRecord(
        at url: URL,
        timeout: TimeInterval = 90,
        notBeforeTimeInterval: TimeInterval? = nil,
        matching predicate: @escaping ([String: Any]) -> Bool
    ) throws -> [String: Any] {
        var found: [String: Any]?
        let fractionalTimestampFormatter = ISO8601DateFormatter()
        fractionalTimestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeTimestampFormatter = ISO8601DateFormatter()
        wholeTimestampFormatter.formatOptions = [.withInternetDateTime]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let data = try? Data(contentsOf: url),
                    let text = String(data: data.suffix(262_144), encoding: .utf8)
                else { return false }
                found = text.split(separator: "\n").suffix(100).compactMap { line in
                    try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                }.last { record in
                    if let notBeforeTimeInterval {
                        let recordTime: TimeInterval?
                        if let numericTimestamp = record["timestamp"] as? TimeInterval {
                            recordTime = numericTimestamp
                        } else if let timestamp = record["timestamp"] as? String {
                            recordTime =
                                fractionalTimestampFormatter.date(from: timestamp)?.timeIntervalSince1970
                                ?? wholeTimestampFormatter.date(from: timestamp)?.timeIntervalSince1970
                        } else {
                            recordTime = nil
                        }
                        guard let recordTime, recordTime >= notBeforeTimeInterval else { return false }
                    }
                    return predicate(record)
                }
                return found != nil
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, "Expected real Claude event")
        return try XCTUnwrap(found)
    }

    private func assertNotificationReason(
        in row: XCUIElement, since timestamp: TimeInterval, canonicalReason: String
    ) {
        var observedReason: String?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && observedReason == nil {
            if let data = try? Data(contentsOf: hookLogURL),
                let text = String(data: data.suffix(262_144), encoding: .utf8)
            {
                let records = text.split(separator: "\n").suffix(100).compactMap { line in
                    try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                }
                observedReason = records.last { record in
                    guard record["hook_event_name"] as? String == "Notification",
                        let eventTimestamp = record["timestamp"] as? TimeInterval,
                        eventTimestamp >= timestamp
                    else { return false }
                    return (record["message"] as? String).map { !$0.isEmpty } == true
                        || (record["title"] as? String).map { !$0.isEmpty } == true
                }.flatMap { record in
                    let message = record["message"] as? String
                    let rawReason = message.flatMap { $0.isEmpty ? nil : $0 } ?? record["title"] as? String
                    let normalizedReason = rawReason?
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    return normalizedReason.flatMap { $0.isEmpty ? nil : $0 }
                }
            }
            if observedReason == nil {
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
        }
        let reasonSource = observedReason == nil ? "canonical" : "Notification hook"
        let expectedReason = observedReason ?? canonicalReason
        let reasonVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", expectedReason), object: row)
        let result = XCTWaiter.wait(for: [reasonVisible], timeout: 10)
        XCTAssertEqual(
            result, .completed,
            "Expected the notification row to show its canonical reason or latest live Claude Notification reason: "
                + expectedReason)
        let evidence = XCTAttachment(
            string: "reason_source=\(reasonSource)\nexpected_reason=\(expectedReason)"
                + "\nnotification_row_label=\(row.label)")
        evidence.name = "Claude notification reason evidence"
        evidence.lifetime = .keepAlways
        add(evidence)
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
        let unexpectedCompletion = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: app.buttons["notification-row-background-alert"])
        unexpectedCompletion.isInverted = true
        XCTAssertEqual(
            XCTWaiter.wait(for: [unexpectedCompletion], timeout: 3), .completed,
            "Pending work must keep notifications absent beyond the 1.8-second completion grace")
        screenshot("claude-background-work")
        _ = try waitForLiveRecord(at: hookLogURL, timeout: 120) { record in
            record["hook_event_name"] as? String == "Stop"
                && (record["background_tasks"] as? [[String: Any]])?.isEmpty == true
                && (record["session_crons"] as? [[String: Any]])?.isEmpty == true
        }
        let notificationRow = app.buttons["notification-row-background-alert"]
        waitFor(notificationRow, timeout: 10)
        let completionReasonVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Claude finished responding"),
            object: notificationRow)
        XCTAssertEqual(
            XCTWaiter.wait(for: [completionReasonVisible], timeout: 10), .completed,
            "Expected the completed background-work row to show the canonical Claude stop reason")
    }

    func testQuestionProducesRealAttention() throws {
        try openClaudePane(named: "question-alert")
        try launchBackgroundSleep()
        let promptTimestamp = Date().timeIntervalSince1970
        typeTerminalCommand(
            "Use AskUserQuestion now to ask me to choose Red or Blue. You must call the tool, not ask in prose.")
        let prompt = try waitForLiveRecord(at: hookLogURL) { record in
            record["hook_event_name"] as? String == "UserPromptSubmit"
                && (record["timestamp"] as? TimeInterval ?? 0) >= promptTimestamp
        }
        let transcript = URL(filePath: try XCTUnwrap(prompt["transcript_path"] as? String))
        _ = try waitForLiveRecord(at: transcript, notBeforeTimeInterval: promptTimestamp) { record in
            guard let message = record["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            else { return false }
            return content.contains {
                $0["type"] as? String == "tool_use" && $0["name"] as? String == "AskUserQuestion"
            }
        }
        let notificationRow = app.buttons["notification-row-question-alert"]
        waitFor(notificationRow, timeout: 90)
        assertNotificationReason(
            in: notificationRow, since: promptTimestamp, canonicalReason: "Claude has a question")
        screenshot("claude-question-attention")
    }

    func testPlanApprovalProducesRealAttention() throws {
        try openClaudePane(named: "plan-alert")
        try launchBackgroundSleep()
        typeTerminalCommand("/plan")
        let promptTimestamp = Date().timeIntervalSince1970
        typeTerminalCommand(
            "Plan one small change: create hello.txt containing hello. Do not implement or inspect files. Present the plan and call ExitPlanMode to request approval now."
        )
        let prompt = try waitForLiveRecord(at: hookLogURL) { record in
            record["hook_event_name"] as? String == "UserPromptSubmit"
                && (record["timestamp"] as? TimeInterval ?? 0) >= promptTimestamp
        }
        let transcript = URL(filePath: try XCTUnwrap(prompt["transcript_path"] as? String))
        _ = try waitForLiveRecord(at: transcript, notBeforeTimeInterval: promptTimestamp) { record in
            guard let message = record["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            else { return false }
            return content.contains {
                $0["type"] as? String == "tool_use" && $0["name"] as? String == "ExitPlanMode"
            }
        }
        let notificationRow = app.buttons["notification-row-plan-alert"]
        waitFor(notificationRow, timeout: 90)
        assertNotificationReason(
            in: notificationRow, since: promptTimestamp, canonicalReason: "Claude needs plan approval")
        screenshot("claude-plan-approval-attention")
    }

    func testEscRecoversOnRealIdleWithoutFinishedAlert() throws {
        try openClaudePane(named: "interrupt-alert")
        typeTerminalCommand(
            "Run exactly sleep 90 using Bash in the foreground. Do not background it and do not use another tool.")
        let prompt = try waitForLiveRecord(at: hookLogURL) { $0["hook_event_name"] as? String == "UserPromptSubmit" }
        let transcript = URL(filePath: try XCTUnwrap(prompt["transcript_path"] as? String))
        let sleepCall = try waitForLiveRecord(at: transcript) { record in
            guard let message = record["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            else { return false }
            return content.contains { item in
                item["type"] as? String == "tool_use" && item["name"] as? String == "Bash"
                    && (item["input"] as? [String: Any])?["command"] as? String == "sleep 90"
            }
        }
        let sleepMessage = try XCTUnwrap(sleepCall["message"] as? [String: Any])
        let sleepContent = try XCTUnwrap(sleepMessage["content"] as? [[String: Any]])
        let sleepToolUse = try XCTUnwrap(
            sleepContent.first { item in
                item["type"] as? String == "tool_use" && item["name"] as? String == "Bash"
                    && (item["input"] as? [String: Any])?["command"] as? String == "sleep 90"
            })
        let sleepToolUseID = try XCTUnwrap(sleepToolUse["id"] as? String)
        let blockedSleepResult = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let data = try? Data(contentsOf: transcript),
                    let text = String(data: data.suffix(262_144), encoding: .utf8)
                else { return false }
                let records = text.split(separator: "\n").suffix(100).compactMap { line in
                    try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                }
                return records.contains { record in
                    guard let message = record["message"] as? [String: Any],
                        let content = message["content"] as? [[String: Any]]
                    else { return false }
                    return content.contains { item in
                        guard item["type"] as? String == "tool_result",
                            item["tool_use_id"] as? String == sleepToolUseID,
                            item["is_error"] as? Bool == true
                        else { return false }
                        let resultText: String
                        if let text = item["content"] as? String {
                            resultText = text
                        } else if let blocks = item["content"] as? [[String: Any]] {
                            resultText = blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
                        } else {
                            return false
                        }
                        return resultText.contains("Blocked: standalone sleep 90")
                    }
                }
            }, object: nil)
        if XCTWaiter.wait(for: [blockedSleepResult], timeout: 8) == .completed {
            throw XCTSkip(
                "Claude Code blocked the standalone sleep 90 fixture; the real interrupt scenario was not exercised")
        }
        app.typeKey(.escape, modifierFlags: [])
        _ = try waitForLiveRecord(at: hookLogURL, timeout: 100) { $0["notification_type"] as? String == "idle_prompt" }
        let notificationRow = app.buttons["notification-row-interrupt-alert"]
        waitFor(notificationRow, timeout: 10)
        XCTAssertFalse(notificationRow.label.contains("Claude finished responding"))
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
