import XCTest

final class CursorFlowTests: BaseTestCase {
    func testCursorPaneWithAgentControlInjection() throws {
        let shell = Process()
        let output = Pipe()
        shell.executableURL = URL(filePath: "/bin/zsh")
        shell.arguments = ["-i", "-c", "agent status"]
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice
        try shell.run()
        let status = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        shell.waitUntilExit()
        guard shell.terminationStatus == 0,
            status.contains("Logged in"),
            !status.contains("unable to fetch user details"),
            !status.contains("user details not available")
        else {
            throw XCTSkip("The real Cursor MCP flow requires an installed Cursor agent with a validated account login")
        }

        app.typeKey(",", modifierFlags: .command)
        let settingsWindow = app.windows["AgentSessionManager Settings"]
        waitFor(settingsWindow)
        let toolsTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-tools").firstMatch
        waitFor(toolsTab)
        toolsTab.click()

        let cursorTool = settingsWindow.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Cursor'"))
            .firstMatch
        waitFor(cursorTool)
        cursorTool.click()

        let enableCursor = settingsWindow.checkBoxes["settings-tool-enable-toggle-cursor"]
        waitFor(enableCursor)
        if enableCursor.value as? Int != 1 {
            enableCursor.click()
        }

        let debugTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-debug").firstMatch
        waitFor(debugTab)
        debugTab.click()
        let debugToggle = settingsWindow.checkBoxes["settings-debug-mode-toggle"]
        waitFor(debugToggle)
        if debugToggle.value as? Int != 1 {
            debugToggle.click()
        }
        app.typeKey("w", modifierFlags: .command)
        waitForDisappear(settingsWindow)

        createTab(named: "CursorControlTab")
        app.typeKey("p", modifierFlags: .command)
        let paneField = app.textFields["new-pane-name-field"]
        waitFor(paneField)
        let cursorHarness = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Cursor'"))
            .firstMatch
        waitFor(cursorHarness)
        cursorHarness.click()
        app.buttons["new-pane-more-settings-button"].click()
        let controlToggle = app.checkBoxes["new-pane-agent-control-toggle"]
        waitFor(controlToggle)
        if controlToggle.value as? Int != 1 {
            controlToggle.click()
        }
        app.buttons["new-pane-advanced-settings-done-button"].click()
        app.buttons["new-pane-cli-options-button"].click()
        let showAllOptions = app.buttons["new-pane-show-hidden-options-button"]
        waitFor(showAllOptions)
        showAllOptions.click()
        let approveMCPs = app.checkBoxes["--approve-mcps"].firstMatch
        waitFor(approveMCPs)
        if approveMCPs.value as? Int != 1 {
            approveMCPs.click()
        }
        XCTAssertEqual(approveMCPs.value as? Int, 1, "The real Cursor MCP approval option should be enabled")
        let trustWorkspace = app.checkBoxes["--trust"].firstMatch
        waitFor(trustWorkspace)
        let optionsScroll = app.scrollViews["new-pane-cli-options-content-scroll-view"]
        for _ in 0..<20 where !optionsScroll.frame.contains(trustWorkspace.frame) {
            optionsScroll.scroll(byDeltaX: 0, deltaY: -100)
        }
        XCTAssertTrue(optionsScroll.frame.contains(trustWorkspace.frame))
        if trustWorkspace.value as? Int != 1 {
            trustWorkspace.click()
        }
        XCTAssertEqual(trustWorkspace.value as? Int, 1)
        app.buttons["new-pane-cli-options-done-button"].click()
        paneField.click()
        paneField.typeText("cursor-control")
        app.buttons["new-pane-open-button"].click()

        waitForDisappear(paneField, timeout: 25)
        let pane = app.staticTexts["pane-name-cursor-control"].firstMatch
        waitFor(pane, timeout: 15)
        let errorOverlay = app.descendants(matching: .any)
            .matching(identifier: "pane-error-overlay-cursor-control").firstMatch
        if errorOverlay.exists {
            XCTFail(
                "Cursor setup failed: "
                    + app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | "))
        }

        let tracesDirectory = UITestAppSupport.directory.appending(path: "traces")
        let traceContains: (String) -> Bool = { eventName in
            guard
                let files = FileManager.default.enumerator(
                    at: tracesDirectory,
                    includingPropertiesForKeys: [.isRegularFileKey])
            else {
                return false
            }
            for case let file as URL in files where file.pathExtension == "jsonl" {
                if (try? String(contentsOf: file, encoding: .utf8))?.contains(eventName) == true {
                    return true
                }
            }
            return false
        }
        let boundExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in traceContains("agent_control.session.bound") },
            object: tracesDirectory as NSURL)
        XCTAssertEqual(
            XCTWaiter.wait(for: [boundExpectation], timeout: 45),
            .completed,
            "Cursor should bind a real Agent Control MCP session through the stdio bridge")

        app.descendants(matching: .any).matching(identifier: "pane-close-cursor-control").firstMatch.click()
        let keepWorktree = app.buttons["Keep Worktree"].firstMatch
        waitFor(keepWorktree)
        keepWorktree.click()
        waitForDisappear(pane, timeout: 10)

        let revokedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in traceContains("agent_control.credential.revoked") },
            object: tracesDirectory as NSURL)
        XCTAssertEqual(
            XCTWaiter.wait(for: [revokedExpectation], timeout: 10),
            .completed,
            "Closing the Cursor pane should revoke its Agent Control credential")

        waitFor(app.staticTexts["tab-empty-state-CursorControlTab"], timeout: 10)
        XCTAssertEqual(app.state, .runningForeground)
        let keptWorktree = GitUITestWorkspace.directoryURL
            .appending(path: ".agent-session-manager/worktrees/cursor-control", directoryHint: .isDirectory)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: keptWorktree.path),
            "Keep Worktree should leave the managed checkout on disk"
        )

        app.typeKey("p", modifierFlags: .command)
        let followUpPaneField = app.textFields["new-pane-name-field"]
        waitFor(followUpPaneField)
        app.buttons["new-pane-cancel-button"].click()
        waitForDisappear(followUpPaneField)
    }
}
