import XCTest

final class SectionResizingStatusFlowTests: BaseTestCase {
    override var appLaunchArguments: [String] { ["--uitesting-skip-restore"] + additionalLaunchArguments }

    func testStatusViewportResizesWithPointerKeyboardAndMenuWithoutChangingPaneBounds() {
        createTab(named: "StatusResize")
        createPane(named: "status-resize-pane")
        openStatusSettings()
        let fourthRow = app.descendants(matching: .any)
            .matching(identifier: "settings-statusline-add-item-3").firstMatch
        waitFor(fourthRow)
        XCTAssertTrue(fourthRow.exists)
        app.typeKey(.escape, modifierFlags: [])

        let handle = statusHandle(for: "status-resize-pane")
        waitFor(handle)
        let viewport = statusViewport(for: handle)
        waitFor(viewport)
        let terminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-status-resize-pane").firstMatch
        let header = app.descendants(matching: .any)
            .matching(identifier: "pane-header-status-resize-pane").firstMatch
        waitFor(terminal)
        waitFor(header)
        let pane = app.descendants(matching: .any)
            .matching(identifier: "pane-status-resize-pane").firstMatch
        waitFor(pane)

        let originalWindowFrame = app.windows.firstMatch.frame
        let originalHeaderFrame = header.frame
        let originalPaneFrame = pane.frame
        let originalScrollViewportHeight = viewport.frame.height
        let originalHeight = resizeValue(handle)
        let originalTerminalHeight = terminal.frame.height
        let originalStatusAllocationHeight = (pane.frame.maxY - handle.frame.maxY)

        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -20)))
        let dimensions = XCTAttachment(
            string:
                "Status drag: handle \(originalHeight) -> \(resizeValue(handle)); allocation \(originalStatusAllocationHeight) -> \((pane.frame.maxY - handle.frame.maxY)); AX viewport \(originalScrollViewportHeight) -> \(viewport.frame.height); terminal \(originalTerminalHeight) -> \(terminal.frame.height)"
        )
        dimensions.lifetime = .keepAlways
        add(dimensions)
        XCTAssertEqual(resizeValue(handle), originalHeight + 20, accuracy: 1)
        XCTAssertEqual((pane.frame.maxY - handle.frame.maxY), originalStatusAllocationHeight + 20, accuracy: 2)
        XCTAssertEqual(terminal.frame.height, originalTerminalHeight - 20, accuracy: 3)
        XCTAssertEqual(header.frame, originalHeaderFrame)
        XCTAssertEqual(pane.frame, originalPaneFrame)
        XCTAssertEqual(app.windows.firstMatch.frame, originalWindowFrame)

        let terminalBeforeMenu = terminal.frame.height
        let statusAllocationBeforeMenu = (pane.frame.maxY - handle.frame.maxY)
        handle.rightClick()
        let increase = app.menuItems["Increase Resize status line for status-resize-pane Size"]
        waitFor(increase)
        increase.click()
        XCTAssertEqual(resizeValue(handle), originalHeight + 36, accuracy: 1)
        XCTAssertEqual((pane.frame.maxY - handle.frame.maxY), statusAllocationBeforeMenu + 16, accuracy: 2)
        XCTAssertEqual(terminal.frame.height, terminalBeforeMenu - 16, accuracy: 3)

        let terminalBeforeKeyboard = terminal.frame.height
        let statusAllocationBeforeKeyboard = (pane.frame.maxY - handle.frame.maxY)
        handle.click()
        handle.typeKey(.upArrow, modifierFlags: [])
        XCTAssertEqual(resizeValue(handle), originalHeight + 40, accuracy: 1)
        XCTAssertEqual((pane.frame.maxY - handle.frame.maxY), statusAllocationBeforeKeyboard + 4, accuracy: 2)
        XCTAssertEqual(terminal.frame.height, terminalBeforeKeyboard - 4, accuracy: 3)

        let terminalBeforeDecrease = terminal.frame.height
        let statusAllocationBeforeDecrease = pane.frame.maxY - handle.frame.maxY
        handle.typeKey(.downArrow, modifierFlags: [])
        XCTAssertEqual(resizeValue(handle), originalHeight + 36, accuracy: 1)
        XCTAssertEqual((pane.frame.maxY - handle.frame.maxY), statusAllocationBeforeDecrease - 4, accuracy: 2)
        XCTAssertEqual(terminal.frame.height, terminalBeforeDecrease + 4, accuracy: 3)

        let terminalBeforeLargerStep = terminal.frame.height
        let statusAllocationBeforeLargerStep = pane.frame.maxY - handle.frame.maxY
        handle.typeKey(.upArrow, modifierFlags: .shift)
        XCTAssertEqual(resizeValue(handle), originalHeight + 52, accuracy: 1)
        XCTAssertEqual((pane.frame.maxY - handle.frame.maxY), statusAllocationBeforeLargerStep + 16, accuracy: 2)
        XCTAssertEqual(terminal.frame.height, terminalBeforeLargerStep - 16, accuracy: 3)

        let terminalBeforeReset = terminal.frame.height
        let statusAllocationBeforeReset = (pane.frame.maxY - handle.frame.maxY)
        handle.rightClick()
        let reset = app.menuItems["Reset Resize status line for status-resize-pane Size"]
        waitFor(reset)
        reset.click()
        XCTAssertEqual(resizeValue(handle), originalHeight, accuracy: 2)
        XCTAssertEqual((pane.frame.maxY - handle.frame.maxY), originalStatusAllocationHeight, accuracy: 2)
        XCTAssertEqual(terminal.frame.height, originalTerminalHeight, accuracy: 3)
        XCTAssertNotEqual(terminalBeforeReset, terminal.frame.height)
        XCTAssertNotEqual(statusAllocationBeforeReset, (pane.frame.maxY - handle.frame.maxY))
    }

    func testStatusHeightIsPaneScopedAndRestoresForGlobalAndProfilePanes() {
        let onboardingSkipButton = app.buttons["onboarding-skip-button"]
        waitFor(onboardingSkipButton)
        onboardingSkipButton.click()

        app.typeKey(",", modifierFlags: .command)
        let profilesTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(profilesTab)
        profilesTab.click()

        let newProfile = app.buttons["New Profile"]
        waitFor(newProfile)
        newProfile.click()
        let nameField = app.textFields["profile-editor-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("Resize Profile")
        let customStatusLine = app.checkBoxes.matching(
            NSPredicate(format: "label CONTAINS 'Custom Status Line'")
        )
        .firstMatch
        waitFor(customStatusLine)
        for _ in 0..<20 where !customStatusLine.isHittable {
            app.sheets.firstMatch.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -80)
        }
        customStatusLine.click()
        let saveProfile = app.buttons["Save"]
        waitFor(saveProfile)
        saveProfile.click()
        waitFor(app.staticTexts["Resize Profile"])
        app.typeKey(.escape, modifierFlags: [])

        createTab(named: "StatusScope")
        createPane(named: "global-status-pane", profileName: nil)
        createPane(named: "profile-status-pane", profileName: "Resize Profile")

        let globalHandle = statusHandle(for: "global-status-pane")
        let profileHandle = statusHandle(for: "profile-status-pane")
        waitFor(globalHandle)
        waitFor(profileHandle)
        let globalInitial = resizeValue(globalHandle)
        let profileInitial = resizeValue(profileHandle)

        let profileHeader = app.descendants(matching: .any)
            .matching(identifier: "pane-header-profile-status-pane").firstMatch
        waitFor(profileHeader)
        profileHeader.doubleClick()
        waitForDisappear(globalHandle)
        let showAllPanes = app.buttons["pane-show-all-profile-status-pane"]
        waitFor(showAllPanes)

        profileHandle.rightClick()
        let increase = app.menuItems["Increase Resize status line for profile-status-pane Size"]
        waitFor(increase)
        increase.click()
        XCTAssertEqual(resizeValue(profileHandle), profileInitial + 16, accuracy: 1)
        showAllPanes.click()
        waitFor(globalHandle)
        XCTAssertEqual(resizeValue(globalHandle), globalInitial, accuracy: 1)

        profileHandle.rightClick()
        let reset = app.menuItems["Reset Resize status line for profile-status-pane Size"]
        waitFor(reset)
        reset.click()
        XCTAssertEqual(resizeValue(profileHandle), profileInitial, accuracy: 2)
        XCTAssertEqual(resizeValue(globalHandle), globalInitial, accuracy: 1)

        profileHandle.rightClick()
        let increaseAgain = app.menuItems["Increase Resize status line for profile-status-pane Size"]
        waitFor(increaseAgain)
        increaseAgain.click()
        XCTAssertEqual(resizeValue(profileHandle), profileInitial + 16, accuracy: 1)

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        let restoredGlobal = statusHandle(for: "global-status-pane")
        let restoredProfile = statusHandle(for: "profile-status-pane")
        waitFor(restoredGlobal)
        waitFor(restoredProfile)
        XCTAssertEqual(resizeValue(restoredGlobal), globalInitial, accuracy: 1)
        XCTAssertEqual(resizeValue(restoredProfile), profileInitial + 16, accuracy: 1)
    }

    func testStatusViewportScrollsBothAxesAndRetainsHeightWhenRowsDisappear() {
        createTab(named: "StatusViewport")
        createPane(named: "status-viewport-one")
        createPane(named: "status-viewport-two")
        createPane(named: "status-viewport-three")
        openStatusSettings()
        let fourthRow = app.descendants(matching: .any)
            .matching(identifier: "settings-statusline-add-item-3").firstMatch
        waitFor(fourthRow)
        app.typeKey(.escape, modifierFlags: [])

        let handle = statusHandle(for: "status-viewport-three")
        waitFor(handle)
        let viewport = statusViewport(for: handle)
        waitFor(viewport)
        for _ in 0..<8 where resizeValue(handle) > 24 {
            handle.rightClick()
            let decrease = app.menuItems["Decrease Resize status line for status-viewport-three Size"]
            waitFor(decrease)
            decrease.click()
        }
        XCTAssertEqual(resizeValue(handle), 24, accuracy: 1)

        let lastStatusItem = viewport.staticTexts["Lines Removed"]
        waitFor(lastStatusItem)
        viewport.scroll(byDeltaX: 240, deltaY: -320)
        XCTAssertTrue(viewport.exists)
        XCTAssertTrue(lastStatusItem.isHittable)

        openStatusSettings()
        let contentScroll = app.scrollViews.containing(
            .button, identifier: "settings-statusline-add-custom-field-button"
        ).firstMatch
        waitFor(contentScroll)
        let removeButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'settings-statusline-remove-item-'"))
        for _ in 0..<120 where !removeButtons.allElementsBoundByIndex.isEmpty {
            let visibleRemoveButton = (0..<removeButtons.count)
                .map { removeButtons.element(boundBy: $0) }
                .first(where: { $0.isHittable })
            if let visibleRemoveButton {
                visibleRemoveButton.click()
            } else {
                contentScroll.scroll(byDeltaX: 0, deltaY: -160)
            }
        }
        XCTAssertEqual(removeButtons.count, 0)
        waitForDisappear(handle)

        let addRow = app.buttons["settings-statusline-add-row-button"]
        waitFor(addRow)
        for _ in 0..<40 where !addRow.isHittable {
            contentScroll.scroll(byDeltaX: 0, deltaY: 120)
        }
        XCTAssertTrue(addRow.isHittable)
        addRow.click()
        let addItem = app.descendants(matching: .any)
            .matching(identifier: "settings-statusline-add-item-4").firstMatch
        waitFor(addItem)
        for _ in 0..<40 where !addItem.isHittable {
            contentScroll.scroll(byDeltaX: 0, deltaY: 120)
        }
        XCTAssertTrue(addItem.isHittable)
        addItem.click()
        let worktreeItem = app.menuItems["Worktree"]
        waitFor(worktreeItem)
        worktreeItem.click()
        app.typeKey(.escape, modifierFlags: [])

        let restoredHandle = statusHandle(for: "status-viewport-three")
        waitFor(restoredHandle)
        XCTAssertEqual(resizeValue(restoredHandle), 24, accuracy: 1)
    }

    private func openStatusSettings() {
        app.typeKey(",", modifierFlags: .command)
        let settingsWindow = app.windows["AgentSessionManager Settings"]
        waitFor(settingsWindow)
        let statusLineTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-status-line").firstMatch
        waitFor(statusLineTab)
        statusLineTab.click()
    }

    private func statusHandle(for paneName: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Resize status line for \(paneName)"))
            .firstMatch
    }

    private func statusViewport(for handle: XCUIElement) -> XCUIElement {
        let paneID = String(handle.identifier.dropFirst("pane-status-resize-".count))
        return app.scrollViews["status-line-viewport-\(paneID)"]
    }

    private func resizeValue(_ element: XCUIElement) -> Double {
        (element.value as? NSNumber)?.doubleValue ?? -1
    }

    private func createPane(named name: String, profileName: String?) {
        app.typeKey("p", modifierFlags: .command)
        if let profileName {
            let profilePicker = app.descendants(matching: .any)
                .matching(identifier: "new-pane-profile-picker").firstMatch
            waitFor(profilePicker)
            profilePicker.click()
            let profileItem = profilePicker.menuItems[profileName]
            waitFor(profileItem)
            profileItem.click()
        }
        let field = app.textFields["new-pane-name-field"]
        waitFor(field)
        field.click()
        field.typeText(name)
        app.buttons["new-pane-open-button"].click()
        waitForDisappear(field, timeout: 25)
        waitFor(app.staticTexts.matching(identifier: "pane-name-\(name)").firstMatch, timeout: 10)
    }
}
