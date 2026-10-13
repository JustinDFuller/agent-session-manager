import AppKit
import XCTest

final class CodexContinuationFlowTests: BaseTestCase {
    override var appLaunchArguments: [String] { ["--uitesting"] }
    override var additionalLaunchEnvironment: [String: String] { ["TERM": "xterm-256color"] }

    func testRealCodexContinuesConversationAfterRefreshAndRelaunch() throws {
        let loginStatus = Process()
        loginStatus.executableURL = URL(filePath: "/bin/zsh")
        loginStatus.arguments = ["-i", "-c", "codex login status"]
        loginStatus.standardOutput = FileHandle.nullDevice
        loginStatus.standardError = FileHandle.nullDevice
        do {
            try loginStatus.run()
        } catch {
            throw XCTSkip("Real Codex continuation requires an installed, authenticated Codex CLI")
        }
        loginStatus.waitUntilExit()
        guard loginStatus.terminationStatus == 0 else {
            throw XCTSkip("Real Codex continuation requires an installed, authenticated Codex CLI")
        }

        let previousPasteboardItems: [[(NSPasteboard.PasteboardType, Data)]] = {
            (NSPasteboard.general.pasteboardItems ?? []).map { item in
                item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
            }
        }()
        defer {
            NSPasteboard.general.clearContents()
            let items = previousPasteboardItems.map { representations -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in representations { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { _ = NSPasteboard.general.writeObjects(items) }
        }

        app.typeKey(",", modifierFlags: .command)
        let settingsWindow = app.windows["AgentSessionManager Settings"]
        waitFor(settingsWindow)
        let toolsTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-tools").firstMatch
        waitFor(toolsTab)
        toolsTab.click()
        let codexTool = settingsWindow.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Codex")).firstMatch
        waitFor(codexTool)
        codexTool.click()
        let codexToggle = settingsWindow.checkBoxes["settings-tool-enable-toggle-codex"]
        waitFor(codexToggle)
        if codexToggle.value as? Int != 1 { codexToggle.click() }
        app.typeKey("w", modifierFlags: .command)

        createTab(named: "Codex Continuation")
        app.typeKey("p", modifierFlags: .command)
        let paneName = "codex-continuation-source"
        let paneNameField = app.textFields["new-pane-name-field"]
        waitFor(paneNameField)
        paneNameField.click()
        paneNameField.typeText(paneName)
        let harnessPicker = app.descendants(matching: .any)
            .matching(identifier: "new-pane-cli-picker").firstMatch
        waitFor(harnessPicker)
        let codexChoice = harnessPicker.radioButtons
            .matching(NSPredicate(format: "label == %@", "Codex")).firstMatch
        waitFor(codexChoice)
        codexChoice.click()
        app.buttons["new-pane-open-button"].click()
        waitForDisappear(paneNameField, timeout: 30)
        let terminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-\(paneName)").firstMatch
        waitFor(terminal, timeout: 30)

        let panePath = GitUITestWorkspace.directoryURL
            .appending(path: ".agent-session-manager/worktrees/\(paneName)")
            .resolvingSymlinksInPath()
        let repositoryPath = GitUITestWorkspace.directoryURL.resolvingSymlinksInPath()
        waitForCodexReady(terminal, panePath: panePath, repositoryPath: repositoryPath)
        let rememberedPhrase = "remember-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        sendPrompt(
            "Remember this exact phrase for our next turn: \(rememberedPhrase). Reply only READY.",
            expecting: "READY", terminal: terminal, paneName: paneName)
        waitForCompletionNotification(paneName)

        let header = app.descendants(matching: .any)
            .matching(identifier: "pane-header-\(paneName)").firstMatch
        waitFor(header)
        header.rightClick()
        let refreshMenu = app.windows.firstMatch.menuItems["Refresh Pane…"]
        waitFor(refreshMenu)
        refreshMenu.click()
        let quickRefresh = app.buttons["refresh-pane-quick"]
        waitFor(quickRefresh)
        XCTAssertTrue(quickRefresh.isEnabled)
        quickRefresh.click()
        waitFor(terminal, timeout: 30)
        waitForCodexReady(terminal, panePath: panePath, repositoryPath: repositoryPath)
        sendPrompt(
            "What exact phrase did I ask you to remember? Reply with only that phrase.",
            expecting: rememberedPhrase, terminal: terminal, paneName: paneName)
        waitForCompletionNotification(paneName)
        let refreshAttachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        refreshAttachment.name = "codex-exact-continuation-after-refresh"
        refreshAttachment.lifetime = .keepAlways
        add(refreshAttachment)

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchArguments = appLaunchArguments
        app.launchEnvironment = additionalLaunchEnvironment.merging(["DISABLE_AUTO_UPDATE": "true"]) { _, value in value
        }
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let restoredTab = app.buttons["tab-button-Codex Continuation"]
        waitFor(restoredTab, timeout: 15)
        let restoredTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-\(paneName)").firstMatch
        waitFor(restoredTerminal, timeout: 30)
        waitForCodexReady(restoredTerminal, panePath: panePath, repositoryPath: repositoryPath)
        let nextPhrase = "after-relaunch-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        sendPrompt(
            "Recall the phrase I asked you to remember, then append the exact suffix -\(nextPhrase). Reply with both.",
            expecting: "\(rememberedPhrase)-\(nextPhrase)", terminal: restoredTerminal, paneName: paneName)
        waitForCompletionNotification(paneName)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "codex-exact-continuation-after-relaunch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForCodexReady(_ terminal: XCUIElement, panePath: URL, repositoryPath: URL) {
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            let output = normalizeTerminalOutput(copiedOutput(from: terminal))
            if output.contains("Trustthisfolder?") {
                XCTAssertTrue(output.contains(panePath.path.filter { !$0.isWhitespace }))
                XCTAssertTrue(output.contains(repositoryPath.path.filter { !$0.isWhitespace }))
                XCTAssertTrue(output.contains("›1.Trustandcontinue"))
                terminal.click()
                terminal.typeKey(.enter, modifierFlags: [])
            } else if output.contains("AskCodextodoanything") {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("Codex did not reach its interactive prompt")
    }

    private func sendPrompt(
        _ prompt: String,
        expecting expected: String,
        terminal: XCUIElement,
        paneName: String
    ) {
        terminal.click()
        app.typeText(prompt)
        terminal.typeKey(.enter, modifierFlags: [])
        let working = app.descendants(matching: .any)
            .matching(identifier: "pane-activity-working-\(paneName)").firstMatch
        waitFor(working, timeout: 20)
        let deadline = Date().addingTimeInterval(120)
        var responseReceived = false
        while Date() < deadline && !responseReceived {
            responseReceived = normalizeTerminalOutput(copiedOutput(from: terminal)).contains(expected)
            if !responseReceived { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        }
        XCTAssertTrue(responseReceived, "Expected the real Codex response to include the requested phrase")
        let stopped = app.descendants(matching: .any)
            .matching(identifier: "pane-activity-stopped-\(paneName)").firstMatch
        waitFor(stopped, timeout: 30)
    }

    private func copiedOutput(from terminal: XCUIElement) -> String {
        terminal.click()
        terminal.typeKey("a", modifierFlags: .command)
        terminal.typeKey("c", modifierFlags: .command)
        return NSPasteboard.general.string(forType: .string) ?? ""
    }

    private func normalizeTerminalOutput(_ output: String) -> String {
        output.filter { !$0.isWhitespace }
    }

    private func waitForCompletionNotification(_ paneName: String) {
        let row = app.descendants(matching: .any)
            .matching(identifier: "notification-row-\(paneName)").firstMatch
        waitFor(row, timeout: 20)
        XCTAssertTrue(row.label.contains("Codex finished responding"))
    }
}
