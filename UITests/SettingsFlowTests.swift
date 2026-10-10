import XCTest

final class SettingsFlowTests: BaseTestCase {
    override func setUp() {
        super.setUp()
        let file = UITestAppSupport.directory.appending(path: "default-branch.json")
        try? FileManager.default.removeItem(at: file)
    }

    override func tearDown() {
        let file = UITestAppSupport.directory.appending(path: "default-branch.json")
        try? FileManager.default.removeItem(at: file)
        super.tearDown()
    }

    func testSettingsDoesNotAutoOpen() {
        let sidebar = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-panes").firstMatch
        XCTAssertFalse(sidebar.waitForExistence(timeout: 2), "Settings must not appear at launch")

        app.typeKey(",", modifierFlags: .command)
        waitFor(sidebar)
        XCTAssertTrue(sidebar.exists, "Settings should appear after ⌘,")

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertFalse(sidebar.waitForExistence(timeout: 1), "Settings should dismiss after Escape")
    }

    func testScrollbackSettingsDefaultAndUnlimitedMode() {
        app.typeKey(",", modifierFlags: .command)
        let panesTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-panes").firstMatch
        waitFor(panesTab)
        panesTab.click()

        let picker = app.descendants(matching: .any)
            .matching(identifier: "settings-scrollback-mode-picker").firstMatch
        let linesField = app.textFields["settings-scrollback-lines-field"]
        waitFor(picker)
        waitFor(linesField)
        XCTAssertEqual(linesField.value as? String, "5000")

        picker.click()
        let unlimited = app.menuItems["Unlimited (50,000-line cap)"]
        waitFor(unlimited)
        unlimited.click()
        waitForDisappear(linesField)

        picker.click()
        let custom = app.menuItems["Custom Limit"]
        waitFor(custom)
        custom.click()
        let warning = app.sheets.containing(.button, identifier: "Reduce History").firstMatch
        waitFor(warning)
        warning.buttons["Reduce History"].click()

        waitFor(linesField)
        XCTAssertEqual(linesField.value as? String, "5000")
    }

    func testAuxiliaryWindowsCloseWithCommandWWithoutAffectingMainWindowState() {
        createTab(named: "Alpha")
        createPane(named: "alpha-pane")
        createTab(named: "Beta")
        createPane(named: "beta-pane")

        let betaTab = app.buttons["tab-button-Beta"].firstMatch
        waitFor(betaTab)
        betaTab.click()
        waitFor(app.staticTexts["pane-name-beta-pane"].firstMatch)
        XCTAssertFalse(app.staticTexts["pane-name-alpha-pane"].firstMatch.exists)

        closeAuxiliaryWindowAndAssertMainState(
            open: {
                self.app.typeKey(",", modifierFlags: .command)
                let settings = self.app.windows["AgentSessionManager Settings"]
                self.waitFor(settings)
                self.waitFor(
                    settings.descendants(matching: .any)
                        .matching(identifier: "settings-sidebar-panes").firstMatch
                )
                return settings
            },
            focus: { window in
                window.descendants(matching: .any)
                    .matching(identifier: "settings-sidebar-panes").firstMatch.click()
            }
        )

        closeAuxiliaryWindowAndAssertMainState(
            open: {
                self.app.typeKey("d", modifierFlags: [.command, .shift])
                let dashboard = self.app.windows["Trace Dashboard"]
                self.waitFor(dashboard)
                self.waitFor(dashboard.buttons["trace-dashboard-refresh-button"])
                return dashboard
            },
            focus: { window in
                window.buttons["trace-dashboard-refresh-button"].click()
            }
        )

        closeAuxiliaryWindowAndAssertMainState(
            open: {
                self.app.typeKey("i", modifierFlags: [.command, .shift])
                let dashboard = self.app.windows["Invariant Dashboard"]
                self.waitFor(dashboard)
                self.waitFor(dashboard.buttons["invariant-dashboard-refresh-button"])
                return dashboard
            },
            focus: { window in
                window.buttons["invariant-dashboard-refresh-button"].click()
            }
        )
    }

    func testSettingsFlow() {
        do {
            app.typeKey(",", modifierFlags: .command)
            let generalTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-panes").firstMatch
            waitFor(generalTab)
            generalTab.click()

            let branchField = app.textFields["settings-default-branch-field"]
            waitFor(branchField)
            XCTAssertTrue(branchField.exists)
            XCTAssertEqual(branchField.value as? String, "ui-root")

            branchField.click()
            branchField.typeKey("a", modifierFlags: .command)
            branchField.typeText("develop")
            XCTAssertEqual(branchField.value as? String, "develop")

            let branchToggle = app.checkBoxes["settings-default-branch-toggle"]
            waitFor(branchToggle)
            branchToggle.click()
            XCTAssertFalse(app.textFields["settings-default-branch-field"].waitForExistence(timeout: 0.5))
            branchToggle.click()
            waitFor(app.textFields["settings-default-branch-field"])

            let continueToggle = app.checkBoxes["settings-continue-on-restart-toggle"]
            waitFor(continueToggle)
            XCTAssertTrue(continueToggle.exists)
            XCTAssertEqual(continueToggle.value as? Int, 1)

            let autoSessionNameToggle = app.checkBoxes["settings-auto-session-name-toggle"]
            waitFor(autoSessionNameToggle)
            XCTAssertTrue(autoSessionNameToggle.exists)

            let shellPicker = app.descendants(matching: .any).matching(identifier: "settings-shell-picker").firstMatch
            waitFor(shellPicker)
            XCTAssertTrue(shellPicker.exists, "Shell picker should exist under General tab")

            let focusModePicker = app.descendants(matching: .any)
                .matching(identifier: "settings-focus-mode-tab-switch-picker").firstMatch
            waitFor(focusModePicker)
            let hideSidebarToggle = app.checkBoxes["settings-focus-mode-hide-sidebar-toggle"]
            waitFor(hideSidebarToggle)
            XCTAssertEqual(hideSidebarToggle.value as? Int, 1)
        }
        let settingsWindow = app.windows["AgentSessionManager Settings"]
        waitFor(settingsWindow)
        assertOnlySidebarShowsSelectedSectionTitle("Panes", in: settingsWindow)
        do {
            let notificationsTab = app.descendants(matching: .any).matching(
                identifier: "settings-sidebar-notifications"
            )
            .firstMatch
            waitFor(notificationsTab)
            notificationsTab.click()

            let bannerToggle = app.checkBoxes["settings-macos-banner-notifications-toggle"]
            waitFor(bannerToggle)

            let openNotifSettingsButton = app.descendants(matching: .any)
                .matching(identifier: "settings-open-notification-settings-button")
                .firstMatch
            waitFor(openNotifSettingsButton)
            XCTAssertTrue(openNotifSettingsButton.exists)

            let stickyToggle = app.checkBoxes["settings-sticky-notifications-toggle"]
            XCTAssertFalse(stickyToggle.exists)

            XCTAssertFalse(app.checkBoxes["settings-claude-notification-hook-toggle"].exists)

            let cursorHookToggle = app.checkBoxes["settings-cursor-notification-hook-toggle"]
            waitFor(cursorHookToggle)
            XCTAssertTrue(cursorHookToggle.exists)

            let alwaysShowToggle = app.checkBoxes["settings-always-show-notifications-bar-toggle"]
            waitFor(alwaysShowToggle)
            XCTAssertEqual(alwaysShowToggle.value as? Int, 1)

            let priorityToggle = app.checkBoxes["settings-priority-notifications-toggle"]
            waitFor(priorityToggle)
            XCTAssertTrue(priorityToggle.exists)

            let sidebarSide = app.descendants(matching: .any)
                .matching(identifier: "settings-sidebar-side")
                .firstMatch
            waitFor(sidebarSide)
        }
        assertOnlySidebarShowsSelectedSectionTitle("Notifications", in: settingsWindow)

        let shortcutsTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-shortcuts").firstMatch
        waitFor(shortcutsTab)
        shortcutsTab.click()
        assertOnlySidebarShowsSelectedSectionTitle("Shortcuts", in: settingsWindow)
        let closeTabTitle = app.staticTexts["settings-shortcut-title-close-tab"]
        waitFor(closeTabTitle)
        XCTAssertEqual(closeTabTitle.value as? String, "Close Active Tab")
        let closeTabDescription = app.staticTexts["settings-shortcut-description-close-tab"]
        waitFor(closeTabDescription)
        XCTAssertEqual(closeTabDescription.value as? String, "Close the current tab")
        let closeTabKeyField = app.textFields["settings-shortcut-key-close-tab"]
        waitFor(closeTabKeyField)

        XCTAssertGreaterThan(
            closeTabDescription.frame.minY,
            closeTabTitle.frame.maxY - 1,
            "Shortcut description should sit below the title"
        )
        XCTAssertLessThan(
            closeTabDescription.frame.minY - closeTabTitle.frame.maxY,
            20,
            "Shortcut description should stay close to the title"
        )

        let keyToTitleDistance = abs(closeTabKeyField.frame.midY - closeTabTitle.frame.midY)
        let keyToDescriptionDistance = abs(closeTabKeyField.frame.midY - closeTabDescription.frame.midY)
        XCTAssertLessThan(
            keyToTitleDistance,
            12,
            "Shortcut key editor should stay on the title baseline"
        )
        XCTAssertLessThan(
            keyToTitleDistance,
            keyToDescriptionDistance,
            "Shortcut key editor should align with the title row, not the description row"
        )
        XCTAssertGreaterThan(
            keyToDescriptionDistance - keyToTitleDistance,
            8,
            "Shortcut key editor should be visibly farther from the description than the title"
        )

        let statusLineTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-status-line")
            .firstMatch
        waitFor(statusLineTab)
        statusLineTab.click()
        assertOnlySidebarShowsSelectedSectionTitle("Status Line", in: settingsWindow)
        let prTrackingToggle = app.checkBoxes["settings-pr-tracking-toggle"]
        waitFor(prTrackingToggle)
        XCTAssertEqual(prTrackingToggle.value as? Int, 1)
        prTrackingToggle.click()
        XCTAssertEqual(prTrackingToggle.value as? Int, 0)
        prTrackingToggle.click()
        XCTAssertEqual(prTrackingToggle.value as? Int, 1)

        let worktreesTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-panes").firstMatch
        waitFor(worktreesTab)
        worktreesTab.click()
        let baseRefPicker = app.descendants(matching: .any).matching(identifier: "settings-worktree-base-ref-picker")
            .firstMatch
        waitFor(baseRefPicker)
        XCTAssertTrue(baseRefPicker.exists)
        let freshButton = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Fresh'")).firstMatch
        waitFor(freshButton)
        let headButton = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'HEAD'")).firstMatch
        waitFor(headButton)
        headButton.click()
        XCTAssertEqual(freshButton.value as? Int, 0)
        XCTAssertEqual(headButton.value as? Int, 1)

        let profilesTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(profilesTab)
        profilesTab.click()
        createProfile(named: "Alpha")
        createProfile(named: "Beta")
        let moveDownButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'profile-move-down-'")
        )
        XCTAssertGreaterThan(moveDownButtons.count, 0)
        let moveUpButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'profile-move-up-'")
        )
        XCTAssertGreaterThan(moveUpButtons.count, 0)
        let profileNames = app.staticTexts.matching(
            NSPredicate(format: "value == 'Alpha' OR value == 'Beta'")
        )
        let nameBefore = profileNames.firstMatch.value as? String
        moveDownButtons.firstMatch.click()
        let nameAfter = profileNames.firstMatch.value as? String
        XCTAssertNotEqual(nameBefore, nameAfter, "Profile order should swap after move-down")

        do {
            let debugTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-debug").firstMatch
            waitFor(debugTab)
            debugTab.click()
            let debugToggle = app.checkBoxes["settings-debug-mode-toggle"]
            waitFor(debugToggle)
            if debugToggle.value as? Int == 0 {
                debugToggle.click()
            }
            waitFor(app.buttons["settings-open-trace-dashboard-button"])
            waitFor(app.buttons["settings-open-invariant-dashboard-button"])
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            app.typeKey("d", modifierFlags: [.command, .shift])
            let dashboard = app.windows["Trace Dashboard"]
            waitFor(dashboard)
            let refreshButton = dashboard.buttons["trace-dashboard-refresh-button"]
            waitFor(refreshButton)
            XCTAssertTrue(refreshButton.exists)
            let traceSidebarList = dashboard.descendants(matching: .any)
                .matching(identifier: "trace-dashboard-sidebar-list").firstMatch
            let traceSidebarEmptyState = dashboard.descendants(matching: .any)
                .matching(identifier: "trace-dashboard-sidebar-empty-state").firstMatch
            XCTAssertTrue(traceSidebarList.exists || traceSidebarEmptyState.exists)
            app.typeKey("i", modifierFlags: [.command, .shift])
            waitFor(app.windows["Invariant Dashboard"])
        }
    }

    func testSettingsSidebarTrailingSpaceIsClickable() {
        app.typeKey(",", modifierFlags: .command)

        let sidebar = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-container").firstMatch
        waitFor(sidebar)

        let profilesTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(profilesTab)
        XCTAssertFalse(profilesTab.isSelected)

        let sidebarOrigin = sidebar.coordinate(withNormalizedOffset: .zero)
        let trailingClick = sidebarOrigin.withOffset(
            CGVector(
                dx: sidebar.frame.width - 24,
                dy: 12 + 8 + 22 + 48
            )
        )
        trailingClick.click()

        XCTAssertTrue(profilesTab.isSelected)
        waitFor(app.buttons["New Profile"])
    }

    private func closeAuxiliaryWindowAndAssertMainState(
        open: () -> XCUIElement,
        focus: (XCUIElement) -> Void
    ) {
        let window = open()
        focus(window)
        app.typeKey("w", modifierFlags: .command)
        waitForDisappear(window)

        let mainWindow = app.windows[mainWindowTitle]
        waitFor(mainWindow)
        XCTAssertTrue(mainWindow.exists)
        XCTAssertTrue(app.buttons["tab-button-Beta"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["pane-name-beta-pane"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["pane-name-alpha-pane"].firstMatch.exists)
    }

    private func assertOnlySidebarShowsSelectedSectionTitle(_ title: String, in window: XCUIElement) {
        let matchingButtons = window.buttons.matching(NSPredicate(format: "label == %@", title)).count
        let matchingStaticTexts =
            window.staticTexts.matching(NSPredicate(format: "label == %@", title)).count
        XCTAssertEqual(
            matchingButtons + matchingStaticTexts,
            1,
            "Settings should show '\(title)' only in the sidebar, not as a duplicate detail header"
        )
    }

    func testCLIToolsEnableRevealsOptions() {
        app.typeKey(",", modifierFlags: .command)

        let toolsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-tools").firstMatch
        waitFor(toolsTab)
        toolsTab.click()

        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "settings-shell-picker").firstMatch
                .waitForExistence(timeout: 1),
            "Shell picker should not exist under CLI Tools tab"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "settings-detect-tools-button").firstMatch
                .waitForExistence(timeout: 1),
            "Detect Installed Tools button should not exist anywhere in Settings"
        )

        let codexSegment = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Codex'")).firstMatch
        waitFor(codexSegment)
        codexSegment.click()

        let codexEnableToggle = app.checkBoxes["settings-tool-enable-toggle-codex"]
        waitFor(codexEnableToggle)
        XCTAssertEqual(codexEnableToggle.value as? Int, 0, "Codex enable toggle should be off by default")

        XCTAssertFalse(
            app.staticTexts["Not Enabled"].waitForExistence(timeout: 1),
            "Option sections should not appear while Codex is disabled"
        )

        codexEnableToggle.click()
        XCTAssertEqual(codexEnableToggle.value as? Int, 1, "Codex enable toggle should be on after click")

        let notEnabledSection = app.staticTexts["Not Enabled"]
        waitFor(notEnabledSection)
        XCTAssertTrue(notEnabledSection.exists, "Option sections should appear after enabling Codex")

        codexEnableToggle.click()
        XCTAssertEqual(codexEnableToggle.value as? Int, 0, "Codex enable toggle should be off after second click")

        XCTAssertFalse(
            app.staticTexts["Not Enabled"].waitForExistence(timeout: 1),
            "Option sections should disappear after disabling Codex"
        )
    }

    func testProfileEditorShowAllOptions() {
        app.typeKey(",", modifierFlags: .command)

        let profilesTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(profilesTab)
        profilesTab.click()

        let newProfileButton = app.buttons["New Profile"]
        waitFor(newProfileButton)
        newProfileButton.click()

        let nameField = app.textFields["profile-editor-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("Hidden Option Test")

        let showAllButton = app.buttons["profile-editor-show-hidden-options-button"]
        waitFor(showAllButton)
        showAllButton.click()

        let verboseToggle = app.checkBoxes.matching(
            NSPredicate(format: "label CONTAINS '--verbose'")
        ).firstMatch
        waitFor(verboseToggle)
        XCTAssertTrue(verboseToggle.exists, "Hidden option --verbose should appear after Show all options")
        let optionsScroll = app.scrollViews["profile-editor-hidden-options-scroll-view"]
        waitFor(optionsScroll)
        let editorScroll = app.sheets.firstMatch.scrollViews.firstMatch
        for _ in 0..<12 where !editorScroll.frame.contains(optionsScroll.frame) {
            editorScroll.scroll(byDeltaX: 0, deltaY: -100)
        }
        for _ in 0..<30 where !optionsScroll.frame.contains(verboseToggle.frame) {
            optionsScroll.scroll(byDeltaX: 0, deltaY: -80)
        }
        XCTAssertTrue(optionsScroll.frame.contains(verboseToggle.frame))
        XCTAssertTrue(verboseToggle.isHittable)
        verboseToggle.click()
        XCTAssertEqual(verboseToggle.value as? Int, 1)

        let showInAllProfilesButton = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Show in all profiles'")
        ).firstMatch
        waitFor(showInAllProfilesButton)
        XCTAssertTrue(
            showInAllProfilesButton.exists,
            "Show in all profiles button should appear when option is enabled"
        )

        let saveButton = app.buttons["Save"]
        waitFor(saveButton)
        saveButton.click()

        let alpha = app.staticTexts.matching(
            NSPredicate(format: "value == 'Hidden Option Test'")
        ).firstMatch
        waitFor(alpha)

        let ellipsisMenu = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'profile-'")
        ).firstMatch
        _ = ellipsisMenu

        let profileMenuButtons = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'profile-move-up-' OR identifier BEGINSWITH 'profile-move-down-'")
        )
        if profileMenuButtons.firstMatch.exists {
            let menuButton = app.buttons.matching(
                NSPredicate(format: "label == 'More'")
            ).firstMatch
            if menuButton.waitForExistence(timeout: 1) {
                menuButton.click()
                let editButton = app.menuItems["Edit"]
                if editButton.waitForExistence(timeout: 1) {
                    editButton.click()

                    let showHiddenAgain = app.buttons["profile-editor-show-hidden-options-button"]
                    if showHiddenAgain.waitForExistence(timeout: 2) {
                        let label = showHiddenAgain.label
                        XCTAssertEqual(
                            label, "Fewer options",
                            "Show all options button should auto-expand because profile has hidden-but-enabled option"
                        )
                    }

                    let cancelButton = app.buttons["Cancel"]
                    if cancelButton.waitForExistence(timeout: 1) {
                        cancelButton.click()
                    }
                }
            }
        }
    }

    func testNonClaudeProfileEditorRestoresSavedModelValue() {
        enableHarness(label: "Cursor", toggleIdentifier: "settings-tool-enable-toggle-cursor")
        enableHarness(label: "Codex", toggleIdentifier: "settings-tool-enable-toggle-codex")
        enableHarness(label: "OpenCode", toggleIdentifier: "settings-tool-enable-toggle-opencode")

        verifyProfileEditorRestoresModel(
            harnessLabel: "Cursor",
            profileName: "Cursor Model Profile",
            modelValue: "cursor-test-model"
        )
        verifyProfileEditorRestoresModel(
            harnessLabel: "Codex",
            profileName: "Codex Model Profile",
            modelValue: "codex-test-model"
        )
        verifyProfileEditorRestoresModel(
            harnessLabel: "OpenCode",
            profileName: "OpenCode Model Profile",
            modelValue: "opencode-test-model"
        )
    }

    private func enableHarness(label: String, toggleIdentifier: String) {
        if !app.windows["AgentSessionManager Settings"].exists {
            app.typeKey(",", modifierFlags: .command)
        }
        let settingsWindow = app.windows["AgentSessionManager Settings"]
        waitFor(settingsWindow)
        let toolsTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-tools").firstMatch
        waitFor(toolsTab)
        toolsTab.click()

        let harness = settingsWindow.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
        waitFor(harness)
        harness.click()

        let toggle = settingsWindow.checkBoxes[toggleIdentifier]
        waitFor(toggle)
        if toggle.value as? Int != 1 {
            toggle.click()
        }
        XCTAssertEqual(toggle.value as? Int, 1, "\(label) should be enabled")
    }

    private func verifyProfileEditorRestoresModel(
        harnessLabel: String,
        profileName: String,
        modelValue: String
    ) {
        let profilesTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(profilesTab)
        profilesTab.click()

        let newProfileButton = app.buttons["New Profile"]
        waitFor(newProfileButton)
        newProfileButton.click()

        let nameField = app.textFields["profile-editor-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText(profileName)

        let harness = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", harnessLabel)).firstMatch
        waitFor(harness)
        harness.click()

        let showAllButton = app.buttons["profile-editor-show-hidden-options-button"]
        waitFor(showAllButton)
        showAllButton.click()

        let modelToggle = app.checkBoxes.matching(
            NSPredicate(format: "label CONTAINS '--model'")
        ).firstMatch
        waitFor(modelToggle)
        let optionsScroll = app.scrollViews["profile-editor-hidden-options-scroll-view"]
        waitFor(optionsScroll)
        let editorScroll = app.sheets.firstMatch.scrollViews.firstMatch
        for _ in 0..<12 where !editorScroll.frame.contains(optionsScroll.frame) {
            editorScroll.scroll(byDeltaX: 0, deltaY: -100)
        }
        for _ in 0..<20 where !optionsScroll.frame.contains(modelToggle.frame) {
            optionsScroll.scroll(byDeltaX: 0, deltaY: -80)
        }
        XCTAssertTrue(optionsScroll.frame.contains(modelToggle.frame))
        modelToggle.click()
        XCTAssertEqual(modelToggle.value as? Int, 1)

        let modelField = app.textFields["cli-option-value-field---model"]
        waitFor(modelField)
        for _ in 0..<10 where !optionsScroll.frame.contains(modelField.frame) {
            optionsScroll.scroll(byDeltaX: 0, deltaY: -40)
        }
        modelField.click()
        modelField.typeText(modelValue)

        let saveButton = app.buttons["Save"]
        waitFor(saveButton)
        saveButton.click()
        waitFor(app.staticTexts.matching(NSPredicate(format: "value == %@", profileName)).firstMatch)

        let profileMenus = app.menuButtons.matching(identifier: "ellipsis.circle")
        let menuButton = profileMenus.element(boundBy: profileMenus.count - 1)
        waitFor(menuButton)
        menuButton.click()
        let editButton = app.menuItems["Edit"]
        waitFor(editButton)
        editButton.click()

        let showHiddenAgain = app.buttons["profile-editor-show-hidden-options-button"]
        waitFor(showHiddenAgain)
        XCTAssertEqual(
            showHiddenAgain.label,
            "Fewer options",
            "\(harnessLabel) should expand saved hidden options when reopened"
        )

        let restoredToggle = app.checkBoxes.matching(
            NSPredicate(format: "label CONTAINS '--model'")
        ).firstMatch
        waitFor(restoredToggle)
        XCTAssertEqual(restoredToggle.value as? Int, 1, "\(harnessLabel) model option should remain enabled")

        let restoredField = app.textFields["cli-option-value-field---model"]
        waitFor(restoredField)
        XCTAssertEqual(restoredField.value as? String, modelValue)

        let cancelButton = app.buttons["Cancel"]
        waitFor(cancelButton)
        cancelButton.click()
        waitForDisappear(showHiddenAgain)
    }

    private func createProfile(named name: String) {
        let newProfileButton = app.buttons["New Profile"]
        waitFor(newProfileButton)
        newProfileButton.click()

        let nameField = app.textFields.firstMatch
        waitFor(nameField)
        nameField.click()
        nameField.typeText(name)

        let saveButton = app.buttons["Save"]
        waitFor(saveButton)
        saveButton.click()
    }
}
