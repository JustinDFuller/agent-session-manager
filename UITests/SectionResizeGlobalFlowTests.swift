import XCTest

final class SectionResizeGlobalFlowTests: BaseTestCase {
    override var appLaunchArguments: [String] { ["--uitesting-skip-restore"] + additionalLaunchArguments }

    func testTabBarResizeHandleSupportsPointerMenuKeyboardAndEscape() {
        createTab(named: "TabBarResize")
        createPane(named: "tab-bar-resize-pane")
        let paneRegion = app.descendants(matching: .any)
            .matching(identifier: "pane-tab-bar-resize-pane")
            .firstMatch
        waitFor(paneRegion)
        let handle = app.descendants(matching: .any)
            .matching(identifier: "tab-bar-resize-handle").firstMatch
        waitFor(handle)
        let initial = resizeValue(handle)
        let initialPaneHeight = paneRegion.frame.height

        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 20))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(resizeValue(handle), initial + 20, accuracy: 1)
        XCTAssertEqual(paneRegion.frame.height, initialPaneHeight - 20, accuracy: 2)

        handle.rightClick()
        let increase = app.menuItems["Increase Tab Bar Size"]
        waitFor(increase)
        increase.click()
        XCTAssertEqual(resizeValue(handle), initial + 36, accuracy: 1)

        handle.rightClick()
        let reset = app.menuItems["Reset Tab Bar Size"]
        waitFor(reset)
        reset.click()
        XCTAssertEqual(resizeValue(handle), initial, accuracy: 1)

        handle.click()
        handle.typeKey(.downArrow, modifierFlags: [])
        XCTAssertEqual(resizeValue(handle), initial + 4, accuracy: 1)
        handle.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(resizeValue(handle), initial + 4, accuracy: 1)
    }

    func testSidebarWidthSurvivesHideShowSideChangeAndRelaunch() {
        createTab(named: "SidebarResize")
        createPane(named: "sidebar-resize-pane")
        app.typeKey(",", modifierFlags: .command)
        let notificationsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-notifications").firstMatch
        waitFor(notificationsTab)
        notificationsTab.click()
        let alwaysShow = app.checkBoxes["settings-always-show-notifications-bar-toggle"]
        waitFor(alwaysShow)
        if alwaysShow.value as? Int != 1 {
            alwaysShow.click()
        }
        app.typeKey(.escape, modifierFlags: [])

        let sidebarHandle = app.descendants(matching: .any)
            .matching(identifier: "notification-sidebar-resize-handle").firstMatch
        waitFor(sidebarHandle)
        let paneRegion = app.descendants(matching: .any)
            .matching(identifier: "pane-sidebar-resize-pane")
            .firstMatch
        waitFor(paneRegion)
        let initialPaneWidth = paneRegion.frame.width
        let growFromLeft = sidebarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        growFromLeft.press(forDuration: 0.1, thenDragTo: growFromLeft.withOffset(CGVector(dx: 20, dy: 0)))
        XCTAssertEqual(resizeValue(sidebarHandle), 260, accuracy: 1)
        XCTAssertEqual(paneRegion.frame.width, initialPaneWidth - 20, accuracy: 2)

        let shrinkFromLeft = sidebarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        shrinkFromLeft.press(forDuration: 0.1, thenDragTo: shrinkFromLeft.withOffset(CGVector(dx: -20, dy: 0)))
        XCTAssertEqual(resizeValue(sidebarHandle), 240, accuracy: 1)
        XCTAssertEqual(paneRegion.frame.width, initialPaneWidth, accuracy: 2)

        sidebarHandle.rightClick()
        let increase = app.menuItems["Increase Notification Sidebar Size"]
        waitFor(increase)
        increase.click()
        XCTAssertEqual(resizeValue(sidebarHandle), 256, accuracy: 1)

        app.typeKey(",", modifierFlags: .command)
        waitFor(notificationsTab)
        notificationsTab.click()
        let sidebarPosition = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-side").firstMatch
        waitFor(alwaysShow)
        waitFor(sidebarPosition)
        alwaysShow.click()
        waitForDisappear(sidebarHandle)
        alwaysShow.click()
        waitFor(sidebarHandle)

        let right = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Right'")).firstMatch
        waitFor(right)
        right.click()
        alwaysShow.click()
        waitForDisappear(sidebarHandle)
        alwaysShow.click()
        waitFor(sidebarHandle)
        app.typeKey(.escape, modifierFlags: [])
        sidebarHandle.rightClick()
        let reset = app.menuItems["Reset Notification Sidebar Size"]
        waitFor(reset)
        reset.click()
        XCTAssertEqual(resizeValue(sidebarHandle), 240, accuracy: 1)
        let rightSidePaneWidth = paneRegion.frame.width
        let growFromRight = sidebarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        growFromRight.press(forDuration: 0.1, thenDragTo: growFromRight.withOffset(CGVector(dx: -20, dy: 0)))
        XCTAssertEqual(resizeValue(sidebarHandle), 260, accuracy: 1)
        XCTAssertEqual(paneRegion.frame.width, rightSidePaneWidth - 20, accuracy: 2)

        let shrinkFromRight = sidebarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        shrinkFromRight.press(forDuration: 0.1, thenDragTo: shrinkFromRight.withOffset(CGVector(dx: 20, dy: 0)))
        XCTAssertEqual(resizeValue(sidebarHandle), 240, accuracy: 1)
        XCTAssertEqual(paneRegion.frame.width, rightSidePaneWidth, accuracy: 2)
        sidebarHandle.rightClick()
        let increaseAgain = app.menuItems["Increase Notification Sidebar Size"]
        waitFor(increaseAgain)
        increaseAgain.click()
        XCTAssertEqual(resizeValue(sidebarHandle), 256, accuracy: 1)

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        let restoredHandle = app.descendants(matching: .any)
            .matching(identifier: "notification-sidebar-resize-handle").firstMatch
        waitFor(restoredHandle)
        XCTAssertEqual(resizeValue(restoredHandle), 256, accuracy: 1)
        XCTAssertGreaterThan(restoredHandle.frame.midX, app.windows.firstMatch.frame.midX)
    }

    func testSettingsResetRestoresGlobalHandleValuesAndRetainsResizeShortcut() {
        let onboardingSkipButton = app.buttons["onboarding-skip-button"]
        waitFor(onboardingSkipButton)
        onboardingSkipButton.click()

        app.typeKey(",", modifierFlags: .command)
        let notificationsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-notifications").firstMatch
        waitFor(notificationsTab)
        notificationsTab.click()
        let alwaysShow = app.checkBoxes["settings-always-show-notifications-bar-toggle"]
        waitFor(alwaysShow)
        if alwaysShow.value as? Int != 1 {
            alwaysShow.click()
        }
        app.typeKey(.escape, modifierFlags: [])

        let tabBarHandle = app.descendants(matching: .any)
            .matching(identifier: "tab-bar-resize-handle").firstMatch
        let sidebarHandle = app.descendants(matching: .any)
            .matching(identifier: "notification-sidebar-resize-handle").firstMatch
        waitFor(tabBarHandle)
        waitFor(sidebarHandle)
        tabBarHandle.rightClick()
        let increaseTabBar = app.menuItems["Increase Tab Bar Size"]
        waitFor(increaseTabBar)
        increaseTabBar.click()
        sidebarHandle.rightClick()
        let increaseSidebar = app.menuItems["Increase Notification Sidebar Size"]
        waitFor(increaseSidebar)
        increaseSidebar.click()
        XCTAssertEqual(resizeValue(tabBarHandle), 60, accuracy: 1)
        XCTAssertEqual(resizeValue(sidebarHandle), 256, accuracy: 1)

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
        let reset = app.buttons["settings-layout-reset-sections"]
        waitFor(reset)
        reset.click()
        shortcutsTab.click()
        XCTAssertEqual(leftCapture.label, "⌘⌥X")
        app.typeKey(.escape, modifierFlags: [])

        waitFor(tabBarHandle)
        waitFor(sidebarHandle)
        XCTAssertEqual(resizeValue(tabBarHandle), 44, accuracy: 1)
        XCTAssertEqual(resizeValue(sidebarHandle), 240, accuracy: 1)

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        let restoredTabBarHandle = app.descendants(matching: .any)
            .matching(identifier: "tab-bar-resize-handle").firstMatch
        let restoredSidebarHandle = app.descendants(matching: .any)
            .matching(identifier: "notification-sidebar-resize-handle").firstMatch
        waitFor(restoredTabBarHandle)
        waitFor(restoredSidebarHandle)
        XCTAssertEqual(resizeValue(restoredTabBarHandle), 44, accuracy: 1)
        XCTAssertEqual(resizeValue(restoredSidebarHandle), 240, accuracy: 1)

        app.typeKey(",", modifierFlags: .command)
        waitFor(shortcutsTab)
        shortcutsTab.click()
        waitFor(leftCapture)
        XCTAssertEqual(leftCapture.label, "⌘⌥X")
    }

    func testEmptyTabKeepsGlobalSectionPreferencesAcrossWindowResizing() {
        createTab(named: "EmptyTabSections")
        let emptyTabState = app.staticTexts["tab-empty-state-EmptyTabSections"]
        waitFor(emptyTabState)

        app.typeKey(",", modifierFlags: .command)
        let notificationsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-notifications").firstMatch
        waitFor(notificationsTab)
        notificationsTab.click()
        let alwaysShow = app.checkBoxes["settings-always-show-notifications-bar-toggle"]
        waitFor(alwaysShow)
        if alwaysShow.value as? Int != 1 {
            alwaysShow.click()
        }
        app.typeKey(.escape, modifierFlags: [])

        let tabBarHandle = app.descendants(matching: .any)
            .matching(identifier: "tab-bar-resize-handle").firstMatch
        let sidebarHandle = app.descendants(matching: .any)
            .matching(identifier: "notification-sidebar-resize-handle").firstMatch
        waitFor(tabBarHandle)
        waitFor(sidebarHandle)
        let initialTabBarHeight = resizeValue(tabBarHandle)
        let initialSidebarWidth = resizeValue(sidebarHandle)

        let tabBarStart = tabBarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        tabBarStart.press(forDuration: 0.1, thenDragTo: tabBarStart.withOffset(CGVector(dx: 0, dy: 16)))
        let sidebarStart = sidebarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        sidebarStart.press(forDuration: 0.1, thenDragTo: sidebarStart.withOffset(CGVector(dx: 40, dy: 0)))
        let preferredTabBarHeight = resizeValue(tabBarHandle)
        let preferredSidebarWidth = resizeValue(sidebarHandle)
        XCTAssertEqual(preferredTabBarHeight, initialTabBarHeight + 16, accuracy: 1)
        XCTAssertEqual(preferredSidebarWidth, initialSidebarWidth + 40, accuracy: 1)
        XCTAssertTrue(emptyTabState.isHittable)

        let tabBarBoundStart = tabBarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        tabBarBoundStart.press(
            forDuration: 0.1,
            thenDragTo: tabBarBoundStart.withOffset(CGVector(dx: 0, dy: 120))
        )
        let sidebarBoundStart = sidebarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        sidebarBoundStart.press(
            forDuration: 0.1,
            thenDragTo: sidebarBoundStart.withOffset(CGVector(dx: 240, dy: 0))
        )
        XCTAssertEqual(resizeValue(tabBarHandle), 96, accuracy: 1)
        XCTAssertEqual(resizeValue(sidebarHandle), 480, accuracy: 1)
        XCTAssertTrue(emptyTabState.isHittable)

        let tabBarLimitStart = tabBarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        tabBarLimitStart.press(
            forDuration: 0.1,
            thenDragTo: tabBarLimitStart.withOffset(CGVector(dx: 0, dy: 20))
        )
        let sidebarLimitStart = sidebarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        sidebarLimitStart.press(
            forDuration: 0.1,
            thenDragTo: sidebarLimitStart.withOffset(CGVector(dx: 20, dy: 0))
        )
        XCTAssertEqual(resizeValue(tabBarHandle), 96, accuracy: 1)
        XCTAssertEqual(resizeValue(sidebarHandle), 480, accuracy: 1)
        XCTAssertTrue(emptyTabState.isHittable)

        tabBarHandle.rightClick()
        let resetTabBar = app.menuItems["Reset Tab Bar Size"]
        waitFor(resetTabBar)
        resetTabBar.click()
        sidebarHandle.rightClick()
        let resetSidebar = app.menuItems["Reset Notification Sidebar Size"]
        waitFor(resetSidebar)
        resetSidebar.click()
        let resetTabBarHeight = resizeValue(tabBarHandle)
        let resetSidebarWidth = resizeValue(sidebarHandle)
        XCTAssertEqual(resetSidebarWidth, 240, accuracy: 1)
        XCTAssertTrue(emptyTabState.isHittable)

        let window = app.windows.firstMatch
        let resizeWindow = { (width: CGFloat, height: CGFloat) in
            let frame = window.frame
            let bottomRight = window.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.999))
            bottomRight.press(
                forDuration: 0.1,
                thenDragTo: bottomRight.withOffset(
                    CGVector(dx: width - frame.width, dy: height - frame.height)
                )
            )
        }
        resizeWindow(900, 600)
        let minimumFrame = window.frame
        XCTAssertGreaterThanOrEqual(minimumFrame.width, 900)
        XCTAssertGreaterThanOrEqual(minimumFrame.height, 600)
        XCTAssertEqual(resizeValue(tabBarHandle), resetTabBarHeight, accuracy: 1)
        XCTAssertEqual(resizeValue(sidebarHandle), resetSidebarWidth, accuracy: 1)
        XCTAssertTrue(tabBarHandle.isHittable)
        XCTAssertTrue(sidebarHandle.isHittable)
        XCTAssertTrue(emptyTabState.isHittable)
        let minimumObservation = XCTAttachment(
            string:
                "Window frame: \(minimumFrame); tab bar value: \(resizeValue(tabBarHandle)); sidebar value: \(resizeValue(sidebarHandle))"
        )
        minimumObservation.name = "section-resizing-empty-tab-minimum-window-measurements"
        minimumObservation.lifetime = .keepAlways
        add(minimumObservation)
        screenshot("section-resizing-empty-tab-minimum-window")

        resizeWindow(minimumFrame.width + 120, minimumFrame.height + 80)
        XCTAssertGreaterThan(window.frame.width, minimumFrame.width)
        XCTAssertGreaterThan(window.frame.height, minimumFrame.height)
        XCTAssertEqual(resizeValue(tabBarHandle), resetTabBarHeight, accuracy: 1)
        XCTAssertEqual(resizeValue(sidebarHandle), resetSidebarWidth, accuracy: 1)
        XCTAssertTrue(emptyTabState.isHittable)
        let largerObservation = XCTAttachment(
            string:
                "Window frame: \(window.frame); tab bar value: \(resizeValue(tabBarHandle)); sidebar value: \(resizeValue(sidebarHandle))"
        )
        largerObservation.name = "section-resizing-empty-tab-larger-window-measurements"
        largerObservation.lifetime = .keepAlways
        add(largerObservation)
        screenshot("section-resizing-empty-tab-larger-window")
    }

    private func resizeValue(_ element: XCUIElement) -> Double {
        (element.value as? NSNumber)?.doubleValue ?? -1
    }
}
