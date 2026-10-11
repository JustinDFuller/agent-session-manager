import XCTest

final class SectionResizingSettingsFlowTests: BaseTestCase {
    override var appLaunchArguments: [String] { ["--uitesting-skip-restore"] + additionalLaunchArguments }

    override func setUp() {
        super.setUp()
        let onboardingSkipButton = app.buttons["onboarding-skip-button"]
        if onboardingSkipButton.waitForExistence(timeout: 2) {
            onboardingSkipButton.click()
        }
    }

    func testLayoutSettingsEditResetAndRestoreAfterRelaunch() {
        app.typeKey(",", modifierFlags: .command)
        let shortcutsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-shortcuts").firstMatch
        waitFor(shortcutsTab)
        shortcutsTab.click()
        let leftCapture = app.buttons["settings-resize-shortcut-capture-left"]
        waitFor(leftCapture)
        leftCapture.click()
        app.typeKey("x", modifierFlags: [.command, .option])
        XCTAssertEqual(leftCapture.label, "⌘⌥X")

        let panesTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-panes").firstMatch
        waitFor(panesTab)
        panesTab.click()

        let tabBarStepper = app.steppers["settings-layout-tab-bar-height"]
        let sidebarStepper = app.steppers["settings-layout-sidebar-width"]
        waitFor(tabBarStepper)
        waitFor(sidebarStepper)
        tabBarStepper.incrementArrows.firstMatch.click()
        sidebarStepper.incrementArrows.firstMatch.click()
        waitFor(app.staticTexts["48 points"])
        waitFor(app.staticTexts["256 points"])

        let reset = app.buttons["settings-layout-reset-sections"]
        waitFor(reset)
        reset.click()
        waitFor(app.staticTexts["44 points"])
        waitFor(app.staticTexts["240 points"])

        tabBarStepper.incrementArrows.firstMatch.click()
        waitFor(app.staticTexts["48 points"])
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        app.typeKey(",", modifierFlags: .command)
        waitFor(panesTab)
        panesTab.click()
        waitFor(app.staticTexts["48 points"])
        waitFor(app.staticTexts["240 points"])
        app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-shortcuts").firstMatch.click()
        let restoredCapture = app.buttons["settings-resize-shortcut-capture-left"]
        waitFor(restoredCapture)
        XCTAssertEqual(restoredCapture.label, "⌘⌥X")
    }

    func testResizeShortcutCaptureValidationDisableAndPersistence() {
        app.typeKey(",", modifierFlags: .command)
        let shortcutsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-shortcuts").firstMatch
        waitFor(shortcutsTab)
        shortcutsTab.click()

        let capture = app.buttons["settings-resize-shortcut-capture-left"]
        let inlineError = app.descendants(matching: .any)
            .matching(identifier: "settings-resize-shortcut-error-left").firstMatch
        let configuredNewTabKey = app.textFields["settings-shortcut-key-new-tab"].value as? String ?? ""
        XCTAssertFalse(configuredNewTabKey.isEmpty)
        waitFor(capture)
        XCTAssertEqual(capture.label, "⌘⌥←")
        capture.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(inlineError.exists)
        XCTAssertEqual(capture.label, "⌘⌥←")

        capture.click()
        app.typeKey("x", modifierFlags: [])
        waitFor(inlineError)
        XCTAssertEqual(capture.label, "⌘⌥←")

        capture.click()
        app.typeKey(configuredNewTabKey, modifierFlags: .command)
        waitFor(inlineError)
        XCTAssertEqual(capture.label, "⌘⌥←")

        capture.click()
        app.typeKey("x", modifierFlags: [.command, .option])
        waitForDisappear(inlineError)
        XCTAssertEqual(capture.label, "⌘⌥X")

        let disable = app.buttons["settings-resize-shortcut-disable-left"]
        waitFor(disable)
        disable.click()
        XCTAssertEqual(capture.label, "Disabled")

        capture.click()
        app.typeKey("x", modifierFlags: [.command, .option])
        XCTAssertEqual(capture.label, "⌘⌥X")
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        app.typeKey(",", modifierFlags: .command)
        waitFor(shortcutsTab)
        shortcutsTab.click()
        let restoredCapture = app.buttons["settings-resize-shortcut-capture-left"]
        waitFor(restoredCapture)
        XCTAssertEqual(restoredCapture.label, "⌘⌥X")
    }

    func testAppShortcutEditorRejectsExistingResizeBinding() {
        app.typeKey(",", modifierFlags: .command)
        let shortcutsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-shortcuts").firstMatch
        waitFor(shortcutsTab)
        shortcutsTab.click()

        let newTabKey = app.textFields["settings-shortcut-key-new-tab"]
        waitFor(newTabKey)
        newTabKey.click()
        newTabKey.typeKey("a", modifierFlags: .command)
        newTabKey.typeText("y")
        newTabKey.typeKey(.tab, modifierFlags: [])
        XCTAssertEqual(newTabKey.value as? String, "y")

        let capture = app.buttons["settings-resize-shortcut-capture-left"]
        waitFor(capture)
        capture.click()
        app.typeKey("t", modifierFlags: .command)
        XCTAssertEqual(capture.label, "⌘T")

        newTabKey.click()
        newTabKey.typeKey("a", modifierFlags: .command)
        newTabKey.typeText("t")
        newTabKey.typeKey(.tab, modifierFlags: [])

        XCTAssertEqual(newTabKey.value as? String, "y")
        waitFor(app.staticTexts["settings-shortcut-error-new-tab"])
    }
}
