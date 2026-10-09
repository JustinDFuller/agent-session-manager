import XCTest

final class SessionPersistenceFlowTests: BaseTestCase {
    override var appLaunchArguments: [String] { ["--uitesting"] }

    func testSessionPersistenceFlow() {
        app.typeKey("t", modifierFlags: .command)
        let field = app.textFields["new-tab-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("PersistenceTab")
        app.buttons["new-tab-choose-dir-button"].click()
        let createBtn = app.buttons["new-tab-create-button"]
        XCTAssertTrue(createBtn.waitForExistence(timeout: 5))
        createBtn.click()
        XCTAssertTrue(app.buttons["tab-button-PersistenceTab"].waitForExistence(timeout: 5))

        let screenshotBefore = XCTAttachment(screenshot: app.screenshot())
        screenshotBefore.name = "13-before-quit"
        screenshotBefore.lifetime = .keepAlways
        add(screenshotBefore)

        app.terminate()
        app.launch()

        let restoredTab = app.buttons["tab-button-PersistenceTab"]
        XCTAssertTrue(restoredTab.waitForExistence(timeout: 10))

        let screenshotAfter = XCTAttachment(screenshot: app.screenshot())
        screenshotAfter.name = "14-after-relaunch"
        screenshotAfter.lifetime = .keepAlways
        add(screenshotAfter)
    }

    func testCursorSessionPersistenceUsesContinueOnRestart() throws {
        let shell = Process()
        let output = Pipe()
        shell.executableURL = URL(filePath: "/bin/zsh")
        shell.arguments = ["-i", "-c", "command -v agent"]
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice
        try shell.run()
        shell.waitUntilExit()
        guard shell.terminationStatus == 0,
            !output.fileHandleForReading.readDataToEndOfFile().isEmpty
        else {
            throw XCTSkip("Cursor agent is not installed in the UI-test shell PATH")
        }

        app.typeKey(",", modifierFlags: .command)
        let settingsWindow = app.windows["AgentSessionManager Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))

        let toolsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-tools").firstMatch
        XCTAssertTrue(toolsTab.waitForExistence(timeout: 5))
        toolsTab.click()
        let cursorTool = settingsWindow.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Cursor'"))
            .firstMatch
        XCTAssertTrue(cursorTool.waitForExistence(timeout: 5))
        cursorTool.click()
        let enableCursor = settingsWindow.checkBoxes["settings-tool-enable-toggle-cursor"]
        XCTAssertTrue(enableCursor.waitForExistence(timeout: 5))
        if enableCursor.value as? Int != 1 {
            enableCursor.click()
        }

        let panesTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-panes").firstMatch
        XCTAssertTrue(panesTab.waitForExistence(timeout: 5))
        panesTab.click()
        let continueToggle = settingsWindow.checkBoxes["settings-continue-on-restart-toggle"]
        XCTAssertTrue(continueToggle.waitForExistence(timeout: 5))
        if continueToggle.value as? Int != 1 {
            continueToggle.click()
        }

        let debugTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-debug").firstMatch
        XCTAssertTrue(debugTab.waitForExistence(timeout: 5))
        debugTab.click()
        let debugToggle = settingsWindow.checkBoxes["settings-debug-mode-toggle"]
        XCTAssertTrue(debugToggle.waitForExistence(timeout: 5))
        if debugToggle.value as? Int != 1 {
            debugToggle.click()
        }
        app.typeKey("w", modifierFlags: .command)
        XCTAssertFalse(settingsWindow.waitForExistence(timeout: 1))

        app.typeKey("t", modifierFlags: .command)
        let tabField = app.textFields["new-tab-name-field"]
        XCTAssertTrue(tabField.waitForExistence(timeout: 5))
        tabField.click()
        tabField.typeText("CursorPersistenceTab")
        app.buttons["new-tab-choose-dir-button"].click()
        let createTabButton = app.buttons["new-tab-create-button"]
        XCTAssertTrue(createTabButton.waitForExistence(timeout: 5))
        createTabButton.click()
        XCTAssertTrue(app.buttons["tab-button-CursorPersistenceTab"].waitForExistence(timeout: 5))

        app.typeKey("p", modifierFlags: .command)
        let paneField = app.textFields["new-pane-name-field"]
        XCTAssertTrue(paneField.waitForExistence(timeout: 5))
        let cursorHarness = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Cursor'"))
            .firstMatch
        XCTAssertTrue(cursorHarness.waitForExistence(timeout: 5))
        cursorHarness.click()
        paneField.click()
        paneField.typeText("cursor-restore")
        app.buttons["new-pane-open-button"].click()

        let pane = app.staticTexts["pane-name-cursor-restore"].firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 25))
        waitFor(app.descendants(matching: .any).matching(identifier: "pane-terminal-cursor-restore").firstMatch)

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.activate()

        let restoredPane = app.staticTexts["pane-name-cursor-restore"].firstMatch
        XCTAssertTrue(restoredPane.waitForExistence(timeout: 10))

        let tracesDirectory = UITestAppSupport.directory.appending(path: "traces")
        let continuationExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard
                    let files = FileManager.default.enumerator(
                        at: tracesDirectory,
                        includingPropertiesForKeys: [.isRegularFileKey])
                else {
                    return false
                }
                for case let file as URL in files where file.pathExtension == "jsonl" {
                    guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
                    if content.contains("session.pane.restore.continuation")
                        && content.contains("\"result\":\"injected\"")
                    {
                        return true
                    }
                }
                return false
            },
            object: tracesDirectory as NSURL)
        XCTAssertEqual(
            XCTWaiter.wait(for: [continuationExpectation], timeout: 10),
            .completed,
            "Cursor restore should record automatic continuation")
    }
}
