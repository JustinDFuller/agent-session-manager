import XCTest

final class EmptyStateFlowTests: BaseTestCase {
    func testDashboardsRemainClosedAfterRelaunch() {
        app.typeKey("d", modifierFlags: [.command, .shift])
        waitFor(app.windows["Trace Dashboard"])
        app.terminate()
        app.launch()
        app.activate()
        waitFor(app.windows[mainWindowTitle])
        XCTAssertFalse(app.windows["Trace Dashboard"].exists)
        XCTAssertFalse(app.windows["Invariant Dashboard"].exists)
    }

    func testEmptyStateFlow() {
        waitFor(emptyStateHint)
        XCTAssertEqual(emptyStateHint.value as? String, "Press ⌘T to create a tab")
        screenshot("01-empty-state")

        let mainWindow = app.windows[mainWindowTitle]
        XCTAssertTrue(mainWindow.exists, "Expected the primary window after launch")
        XCTAssertFalse(app.windows["Trace Dashboard"].exists, "Trace Dashboard must not open at launch")
        XCTAssertFalse(app.windows["Invariant Dashboard"].exists, "Invariant Dashboard must not open at launch")
        let nonPanelWindows = app.windows.allElementsBoundByIndex.filter {
            $0.title != "Notification Center"
        }
        XCTAssertEqual(nonPanelWindows.count, 1, "Expected exactly one app window after launch")
        XCTAssertFalse(
            app.windows.allElementsBoundByIndex.contains { $0.title.contains("Settings") },
            "No Settings window should exist at launch"
        )

        let appMenu = app.menuBars.menuBarItems.element(boundBy: 1)
        appMenu.click()
        let settingsMenuItems = appMenu.menuItems.matching(
            NSPredicate(format: "title BEGINSWITH 'Settings'")
        )
        XCTAssertEqual(settingsMenuItems.count, 1, "Expected exactly one Settings… menu item")
        app.typeKey(.escape, modifierFlags: [])

        app.menuBars.menuBarItems["File"].click()
        let newPaneItem = app.menuBars.menuBarItems["File"].menuItems["New Pane in Current Tab"]
        waitFor(newPaneItem)
        XCTAssertFalse(newPaneItem.isEnabled)
        let closeTabItem = app.menuBars.menuBarItems["File"].menuItems["Close Tab"]
        XCTAssertFalse(closeTabItem.isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("t", modifierFlags: .command)
        let nameField = app.textFields["new-tab-name-field"]
        waitFor(nameField)
        XCTAssertTrue(nameField.isEnabled)
        screenshot("02-new-tab-sheet")

        let requiredHint = app.staticTexts["new-tab-required-hint"]
        XCTAssertTrue(requiredHint.exists)
        XCTAssertFalse(app.buttons["new-tab-create-button"].isEnabled)

        nameField.click()
        nameField.typeText("MyTab")
        app.buttons["new-tab-choose-dir-button"].click()
        let createButton = app.buttons["new-tab-create-button"]
        waitFor(createButton)
        XCTAssertTrue(createButton.isEnabled)
        XCTAssertFalse(app.staticTexts["new-tab-required-hint"].exists)
        screenshot("03-new-tab-filled")

        app.buttons["new-tab-cancel-button"].click()
        waitForDisappear(nameField)
    }
}
