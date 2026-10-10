import Foundation
import XCTest

final class AgentControlFlowTests: BaseTestCase {
    func testClaudePaneWithAgentControlInjectionStaysRunning() throws {
        let shell = Process()
        let output = Pipe()
        shell.executableURL = URL(filePath: "/bin/zsh")
        shell.arguments = ["-i", "-c", "command -v claude"]
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice
        try shell.run()
        shell.waitUntilExit()
        guard shell.terminationStatus == 0,
            !output.fileHandleForReading.readDataToEndOfFile().isEmpty
        else {
            throw XCTSkip("Claude Code is not installed in the UI-test shell PATH")
        }

        createTab(named: "ClaudeControlTab")
        app.typeKey("p", modifierFlags: .command)
        let paneField = app.textFields["new-pane-name-field"]
        waitFor(paneField)
        app.buttons["new-pane-more-settings-button"].click()
        let controlToggle = app.checkBoxes["new-pane-agent-control-toggle"]
        waitFor(controlToggle)
        if controlToggle.value as? Int != 1 {
            controlToggle.click()
        }
        app.buttons["new-pane-advanced-settings-done-button"].click()
        paneField.click()
        paneField.typeText("claude-control")
        app.buttons["new-pane-open-button"].click()

        waitForDisappear(paneField, timeout: 25)
        waitFor(app.staticTexts["pane-name-claude-control"].firstMatch, timeout: 15)
        let exitPrompt = app.descendants(matching: .any)
            .matching(identifier: "pane-exit-prompt-claude-control").firstMatch
        XCTAssertFalse(
            exitPrompt.waitForExistence(timeout: 5),
            "Claude Code exited during startup with Agent Control enabled")
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "pane-error-overlay-claude-control").firstMatch.exists,
            "Agent Control setup should complete before launching Claude Code")

        app.typeKey("i", modifierFlags: .command)
        let settingsSheet = app.descendants(matching: .any)
            .matching(identifier: "pane-settings-sheet").firstMatch
        waitFor(settingsSheet)
        let runningStatus = settingsSheet.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH 'Running (pid '")
        ).firstMatch
        waitFor(runningStatus)
        app.buttons["pane-settings-close-button"].click()
        waitForDisappear(settingsSheet)
        app.typeKey("i", modifierFlags: .command)
        waitFor(settingsSheet)
        waitFor(runningStatus)
    }

    func testAgentControlSettingsAndNewPaneDecisionFlow() throws {
        app.typeKey(",", modifierFlags: .command)

        let policyPicker = app.descendants(matching: .any)
            .matching(identifier: "settings-agent-control-injection-policy-picker").firstMatch
        let scopePicker = app.descendants(matching: .any)
            .matching(identifier: "settings-agent-control-scope-picker").firstMatch
        waitFor(policyPicker)
        waitFor(scopePicker)

        let globalScope = app.descendants(matching: .any)
            .matching(identifier: "settings-agent-control-scope-option-global").firstMatch
        waitFor(globalScope)

        let tabScope = app.descendants(matching: .any)
            .matching(identifier: "settings-agent-control-scope-option-tab").firstMatch
        waitFor(tabScope)
        tabScope.click()

        policyPicker.click()
        let askOff = policyPicker.menuItems["Ask (off by default)"]
        waitFor(askOff)
        askOff.click()
        app.typeKey("w", modifierFlags: .command)

        createTab(named: "ControlTab")
        app.typeKey("p", modifierFlags: .command)
        let paneField = app.textFields["new-pane-name-field"]
        waitFor(paneField)
        app.buttons["new-pane-more-settings-button"].click()
        let controlToggle = app.checkBoxes["new-pane-agent-control-toggle"]
        waitFor(controlToggle)
        XCTAssertEqual(controlToggle.value as? Int, 0)
        controlToggle.click()
        XCTAssertEqual(controlToggle.value as? Int, 1)
        app.buttons["new-pane-advanced-settings-done-button"].click()
        paneField.click()
        paneField.typeText("controlled-pane")
        app.buttons["new-pane-open-button"].click()
        waitForDisappear(paneField, timeout: 25)
        waitFor(app.staticTexts["pane-name-controlled-pane"].firstMatch, timeout: 10)

        let sessionURL = UITestAppSupport.directory.appending(path: "sessions.json")
        let sessionData = try Data(contentsOf: sessionURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: sessionData) as? [String: Any])
        let tabs = try XCTUnwrap(object["tabs"] as? [[String: Any]])
        let panes = try XCTUnwrap(tabs.first?["panes"] as? [[String: Any]])
        XCTAssertEqual(panes.first?["agentControlInjectionEnabled"] as? Bool, true)
    }

    func testAlwaysAndNeverPoliciesExposeForcedPaneState() {
        app.typeKey(",", modifierFlags: .command)
        let policyPicker = app.descendants(matching: .any)
            .matching(identifier: "settings-agent-control-injection-policy-picker").firstMatch
        waitFor(policyPicker)

        policyPicker.click()
        let always = policyPicker.menuItems["Always"]
        waitFor(always)
        always.click()
        app.typeKey("w", modifierFlags: .command)

        createTab(named: "AlwaysTab")
        app.typeKey("p", modifierFlags: .command)
        let alwaysField = app.textFields["new-pane-name-field"]
        waitFor(alwaysField)
        XCTAssertFalse(app.checkBoxes["new-pane-agent-control-toggle"].exists)
        app.buttons["new-pane-more-settings-button"].click()
        XCTAssertTrue(app.staticTexts["Agent Session Manager control will be enabled."].exists)
        app.buttons["new-pane-advanced-settings-done-button"].click()
        XCTAssertTrue(alwaysField.exists, "Closing More Settings should return to New Pane")
        app.buttons["new-pane-cancel-button"].click()
        waitForDisappear(alwaysField)
    }
}
