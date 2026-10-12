import XCTest

final class SectionResizingGridFlowTests: BaseTestCase {
    override var appLaunchArguments: [String] { ["--uitesting-skip-restore"] + additionalLaunchArguments }

    func testGridTracksFollowTopologyAndPanePositionsThroughFocusAndReorder() {
        createTab(named: "GridTopology")
        XCTAssertFalse(gridDivider(axis: "column", index: 0).exists)
        XCTAssertFalse(gridDivider(axis: "row", index: 0).exists)

        createPane(named: "grid-topology-one")
        XCTAssertFalse(gridDivider(axis: "column", index: 0).exists)
        XCTAssertFalse(gridDivider(axis: "row", index: 0).exists)

        createPane(named: "grid-topology-two")
        let columnZero = gridDivider(axis: "column", index: 0)
        waitFor(columnZero)
        XCTAssertFalse(gridDivider(axis: "row", index: 0).exists)
        let initialColumn = resizeValue(columnZero)
        columnZero.rightClick()
        let increaseColumn = app.menuItems["Increase Resize column divider 1 Size"]
        waitFor(increaseColumn)
        increaseColumn.click()
        XCTAssertEqual(resizeValue(columnZero), initialColumn + 16, accuracy: 1)

        createPane(named: "grid-topology-three")
        let rowZero = gridDivider(axis: "row", index: 0)
        waitFor(rowZero)
        XCTAssertEqual(resizeValue(columnZero), initialColumn + 16, accuracy: 1)
        XCTAssertFalse(app.staticTexts["pane-name-grid-topology-four"].exists)
        let initialRow = resizeValue(rowZero)
        rowZero.rightClick()
        let increaseRow = app.menuItems["Increase Resize row divider 1 Size"]
        waitFor(increaseRow)
        increaseRow.click()
        XCTAssertEqual(resizeValue(rowZero), initialRow + 16, accuracy: 1)

        createPane(named: "grid-topology-four")
        XCTAssertEqual(resizeValue(columnZero), initialColumn + 16, accuracy: 1)
        XCTAssertEqual(resizeValue(rowZero), initialRow + 16, accuracy: 1)

        let firstHeader = app.descendants(matching: .any)
            .matching(identifier: "pane-header-grid-topology-one").firstMatch
        let secondHeader = app.descendants(matching: .any)
            .matching(identifier: "pane-header-grid-topology-two").firstMatch
        waitFor(firstHeader)
        waitFor(secondHeader)
        let firstPosition = firstHeader.frame.midX
        let secondPosition = secondHeader.frame.midX
        firstHeader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.5,
                thenDragTo: secondHeader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            )
        XCTAssertEqual(firstHeader.frame.midX, secondPosition, accuracy: 4)
        XCTAssertEqual(secondHeader.frame.midX, firstPosition, accuracy: 4)
        XCTAssertEqual(resizeValue(columnZero), initialColumn + 16, accuracy: 1)
        XCTAssertEqual(resizeValue(rowZero), initialRow + 16, accuracy: 1)

        firstHeader.doubleClick()
        let showAll = app.buttons["pane-show-all-grid-topology-one"]
        waitFor(showAll)
        waitForDisappear(columnZero)
        waitForDisappear(rowZero)
        showAll.click()
        waitFor(columnZero)
        waitFor(rowZero)
        XCTAssertEqual(resizeValue(columnZero), initialColumn + 16, accuracy: 1)
        XCTAssertEqual(resizeValue(rowZero), initialRow + 16, accuracy: 1)

        createPane(named: "grid-topology-five")
        let columnOne = gridDivider(axis: "column", index: 1)
        waitFor(columnOne)
        XCTAssertGreaterThan(abs(resizeValue(columnZero) - (initialColumn + 16)), 30)
        XCTAssertEqual(resizeValue(rowZero), initialRow + 16, accuracy: 1)
        let threeColumnFirst = resizeValue(columnZero)
        let threeColumnSecond = resizeValue(columnOne)

        createPane(named: "grid-topology-six")
        XCTAssertEqual(resizeValue(columnZero), threeColumnFirst, accuracy: 1)
        XCTAssertEqual(resizeValue(columnOne), threeColumnSecond, accuracy: 1)
        XCTAssertEqual(resizeValue(rowZero), initialRow + 16, accuracy: 1)

        createPane(named: "grid-topology-seven")
        let rowOne = gridDivider(axis: "row", index: 1)
        waitFor(rowOne)
        XCTAssertEqual(resizeValue(columnZero), threeColumnFirst, accuracy: 1)
        XCTAssertEqual(resizeValue(columnOne), threeColumnSecond, accuracy: 1)
        XCTAssertGreaterThan(abs(resizeValue(rowZero) - (initialRow + 16)), 20)
    }

    func testDirectionalResizeHonorsAxesStepsLimitsAndWindowScope() {
        createTab(named: "GridShortcuts")
        createPane(named: "grid-shortcuts-one")
        createPane(named: "grid-shortcuts-two")

        let columnZero = gridDivider(axis: "column", index: 0)
        waitFor(columnZero)
        XCTAssertFalse(gridDivider(axis: "row", index: 0).exists)
        let twoPaneWidth = resizeValue(columnZero)
        app.descendants(matching: .any).matching(identifier: "pane-terminal-grid-shortcuts-two").firstMatch.click()
        app.typeKey(.downArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(columnZero), twoPaneWidth, accuracy: 1)

        app.typeKey(",", modifierFlags: .command)
        let shortcutsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-shortcuts").firstMatch
        waitFor(shortcutsTab)
        shortcutsTab.click()
        app.typeKey(.leftArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(columnZero), twoPaneWidth, accuracy: 1)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("p", modifierFlags: .command)
        waitFor(app.textFields["new-pane-name-field"])
        app.typeKey(.leftArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(columnZero), twoPaneWidth, accuracy: 1)
        app.typeKey(.escape, modifierFlags: [])
        waitForDisappear(app.textFields["new-pane-name-field"])

        createPane(named: "grid-shortcuts-three")
        createPane(named: "grid-shortcuts-four")
        createPane(named: "grid-shortcuts-five")
        let columnOne = gridDivider(axis: "column", index: 1)
        waitFor(columnOne)
        let firstPaneTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-grid-shortcuts-one").firstMatch
        waitFor(firstPaneTerminal)
        firstPaneTerminal.click()
        let firstBeforeLargerStep = resizeValue(columnZero)
        let secondBeforeLargerStep = resizeValue(columnOne)
        app.typeKey(.leftArrow, modifierFlags: [.command, .option, .shift])
        XCTAssertEqual(resizeValue(columnZero), firstBeforeLargerStep - 16, accuracy: 1)
        XCTAssertEqual(resizeValue(columnOne), secondBeforeLargerStep + 16, accuracy: 1)

        let firstBeforeRepeatedSteps = resizeValue(columnZero)
        for _ in 0..<3 {
            app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        }
        XCTAssertEqual(resizeValue(columnZero), firstBeforeRepeatedSteps + 12, accuracy: 1)

        let secondTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-grid-shortcuts-two").firstMatch
        waitFor(secondTerminal)
        secondTerminal.click()
        let firstBeforeMiddleBoundary = resizeValue(columnZero)
        let secondBeforeMiddleBoundary = resizeValue(columnOne)
        app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(columnZero), firstBeforeMiddleBoundary, accuracy: 1)
        XCTAssertEqual(resizeValue(columnOne), secondBeforeMiddleBoundary + 4, accuracy: 1)

        let rightEdgeTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-grid-shortcuts-three").firstMatch
        waitFor(rightEdgeTerminal)
        rightEdgeTerminal.click()
        let firstBeforeRightEdge = resizeValue(columnZero)
        let secondBeforeRightEdge = resizeValue(columnOne)
        app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(columnZero), firstBeforeRightEdge, accuracy: 1)
        XCTAssertEqual(resizeValue(columnOne), secondBeforeRightEdge + 4, accuracy: 1)

        let rowZero = gridDivider(axis: "row", index: 0)
        waitFor(rowZero)
        firstPaneTerminal.click()
        let rowBeforeTopUp = resizeValue(rowZero)
        app.typeKey(.upArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(rowZero), rowBeforeTopUp - 4, accuracy: 1)
        let rowBeforeTopLargerUp = resizeValue(rowZero)
        app.typeKey(.upArrow, modifierFlags: [.command, .option, .shift])
        XCTAssertEqual(resizeValue(rowZero), rowBeforeTopLargerUp - 16, accuracy: 1)
        let rowBeforeDown = resizeValue(rowZero)
        app.typeKey(.downArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(rowZero), rowBeforeDown + 4, accuracy: 1)
        let bottomMiddleTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-grid-shortcuts-four").firstMatch
        waitFor(bottomMiddleTerminal)
        bottomMiddleTerminal.click()
        let rowBeforeBottomEdge = resizeValue(rowZero)
        app.typeKey(.downArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(rowZero), rowBeforeBottomEdge + 4, accuracy: 1)
        let rowBeforeBottomUp = resizeValue(rowZero)
        app.typeKey(.upArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(rowZero), rowBeforeBottomUp - 4, accuracy: 1)
        let rowBeforeBottomLargerUp = resizeValue(rowZero)
        app.typeKey(.upArrow, modifierFlags: [.command, .option, .shift])
        XCTAssertEqual(resizeValue(rowZero), rowBeforeBottomLargerUp - 16, accuracy: 1)

        let leftCapture = app.buttons["settings-resize-shortcut-capture-left"]
        app.typeKey(",", modifierFlags: .command)
        waitFor(shortcutsTab)
        shortcutsTab.click()
        let rightLargerCapture = app.buttons["settings-resize-shortcut-capture-right-larger"]
        waitFor(rightLargerCapture)
        rightLargerCapture.click()
        app.typeKey("y", modifierFlags: [.command, .option, .shift])
        XCTAssertEqual(rightLargerCapture.label, "⌘⌥⇧Y")
        let disableLeft = app.buttons["settings-resize-shortcut-disable-left"]
        waitFor(disableLeft)
        disableLeft.click()
        XCTAssertEqual(leftCapture.label, "Disabled")
        app.typeKey(.escape, modifierFlags: [])

        firstPaneTerminal.click()
        let beforeCustomLarge = resizeValue(columnZero)
        app.typeKey("y", modifierFlags: [.command, .option, .shift])
        XCTAssertEqual(resizeValue(columnZero), beforeCustomLarge + 16, accuracy: 1)
        let beforeDisabled = resizeValue(columnZero)
        app.typeKey(.leftArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(columnZero), beforeDisabled, accuracy: 1)
        app.typeKey("z", modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(columnZero), beforeDisabled, accuracy: 1)

        let secondTrackBeforeLimit = resizeValue(columnOne)
        for _ in 0..<40 {
            app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        }
        XCTAssertEqual(resizeValue(columnOne), 160, accuracy: 2)
        let firstAtLimit = resizeValue(columnZero)
        let secondDividerAtLimit = resizeValue(columnOne)
        for _ in 0..<4 {
            app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        }
        XCTAssertEqual(resizeValue(columnZero), firstAtLimit, accuracy: 1)
        XCTAssertEqual(resizeValue(columnOne), secondDividerAtLimit, accuracy: 1)
        XCTAssertNotEqual(secondTrackBeforeLimit, secondDividerAtLimit)
    }

    func testResizeShortcutEditorsPersistBindingsAndIgnoreFocusPaneCommands() {
        createTab(named: "Grid Shortcut Persistence")
        createPane(named: "grid-shortcut-persist-one")
        createPane(named: "grid-shortcut-persist-two")

        let columnZero = gridDivider(axis: "column", index: 0)
        waitFor(columnZero)
        let shortcutsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-shortcuts").firstMatch
        app.typeKey(",", modifierFlags: .command)
        waitFor(shortcutsTab)
        shortcutsTab.click()

        let leftCapture = app.buttons["settings-resize-shortcut-capture-left"]
        let leftError = app.staticTexts["settings-resize-shortcut-error-left"]
        let rightCapture = app.buttons["settings-resize-shortcut-capture-right"]
        let rightError = app.staticTexts["settings-resize-shortcut-error-right"]
        waitFor(leftCapture)
        XCTAssertEqual(leftCapture.label, "⌘⌥←")

        leftCapture.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(leftCapture.label, "⌘⌥←")

        leftCapture.click()
        app.typeKey("x", modifierFlags: [])
        waitFor(leftError)
        XCTAssertEqual(leftCapture.label, "⌘⌥←")

        leftCapture.click()
        app.typeKey(.leftArrow, modifierFlags: [.command, .option])
        waitForDisappear(leftError)
        XCTAssertEqual(leftCapture.label, "⌘⌥←")

        leftCapture.click()
        app.typeKey("t", modifierFlags: .command)
        waitFor(leftError)
        XCTAssertEqual(leftCapture.label, "⌘⌥←")

        leftCapture.click()
        app.typeKey("y", modifierFlags: .command)
        waitForDisappear(leftError)
        XCTAssertEqual(leftCapture.label, "⌘Y")

        rightCapture.click()
        app.typeKey("y", modifierFlags: .command)
        waitFor(rightError)
        XCTAssertEqual(rightCapture.label, "⌘⌥→")
        XCTAssertEqual(leftCapture.label, "⌘Y")

        let newTabKey = app.textFields["settings-shortcut-key-new-tab"]
        waitFor(newTabKey)
        newTabKey.click()
        newTabKey.typeKey("a", modifierFlags: .command)
        newTabKey.typeText("y")
        newTabKey.typeKey(.tab, modifierFlags: [])
        XCTAssertEqual(newTabKey.value as? String, "t")
        waitFor(app.staticTexts["settings-shortcut-error-new-tab"])

        let disableLeft = app.buttons["settings-resize-shortcut-disable-left"]
        waitFor(disableLeft)
        disableLeft.click()
        XCTAssertEqual(leftCapture.label, "Disabled")

        rightCapture.click()
        app.typeKey("y", modifierFlags: [.command, .option])
        waitForDisappear(rightError)
        XCTAssertEqual(rightCapture.label, "⌘⌥Y")

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        app.typeKey(",", modifierFlags: .command)
        waitFor(shortcutsTab)
        shortcutsTab.click()
        let restoredLeftCapture = app.buttons["settings-resize-shortcut-capture-left"]
        let restoredRightCapture = app.buttons["settings-resize-shortcut-capture-right"]
        waitFor(restoredLeftCapture)
        waitFor(restoredRightCapture)
        XCTAssertEqual(restoredLeftCapture.label, "Disabled")
        XCTAssertEqual(restoredRightCapture.label, "⌘⌥Y")

        app.typeKey(.escape, modifierFlags: [])
        createTab(named: "Grid Shortcut Restore")
        createPane(named: "grid-shortcut-restore-one")
        createPane(named: "grid-shortcut-restore-two")
        let restoredColumn = gridDivider(axis: "column", index: 0)
        waitFor(restoredColumn)
        let activeTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-grid-shortcut-restore-two").firstMatch
        waitFor(activeTerminal)
        activeTerminal.click()

        let beforeDisabledDefault = resizeValue(restoredColumn)
        app.typeKey(.leftArrow, modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(restoredColumn), beforeDisabledDefault, accuracy: 1)

        let beforeCustom = resizeValue(restoredColumn)
        app.typeKey("y", modifierFlags: [.command, .option])
        XCTAssertEqual(resizeValue(restoredColumn), beforeCustom + 4, accuracy: 1)

        let focusedHeader = app.descendants(matching: .any)
            .matching(identifier: "pane-header-grid-shortcut-restore-two").firstMatch
        waitFor(focusedHeader)
        focusedHeader.doubleClick()
        let showAll = app.buttons["pane-show-all-grid-shortcut-restore-two"]
        waitFor(showAll)
        waitForDisappear(restoredColumn)
        let focusedTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-grid-shortcut-restore-two").firstMatch
        waitFor(focusedTerminal)
        focusedTerminal.click()
        app.typeKey("y", modifierFlags: [.command, .option])
        XCTAssertFalse(restoredColumn.exists)
        showAll.click()
        waitFor(restoredColumn)
        XCTAssertEqual(resizeValue(restoredColumn), beforeCustom + 4, accuracy: 1)
    }

    private func gridDivider(axis: String, index: Int) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS '-\(axis)-divider-\(index)'")).firstMatch
    }

    private func resizeValue(_ element: XCUIElement) -> Double {
        (element.value as? NSNumber)?.doubleValue ?? -1
    }
}
