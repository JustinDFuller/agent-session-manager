import XCTest

final class CLIOptionPresetFlowTests: BaseTestCase {
    private let profileName = "Preset Test"

    private func openToolsTab() {
        app.typeKey(",", modifierFlags: .command)
        let toolsTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-tools").firstMatch
        waitFor(toolsTab)
        toolsTab.click()
    }

    private func definePresets(forFlagID flagID: String, presets: [String]) {
        let showToggle = app.checkBoxes["settings-cli-option-show-\(flagID)"]
        waitFor(showToggle)
        if showToggle.value as? Int == 0 {
            showToggle.click()
        }
        for preset in presets {
            let addButton = app.buttons["settings-cli-option-preset-add-\(flagID)"]
            waitFor(addButton)
            addButton.click()
            let fields = app.textFields.matching(identifier: "settings-cli-option-preset-value-\(flagID)")
            let field = fields.element(boundBy: fields.count - 1)
            waitFor(field)
            field.click()
            field.typeText(preset)
        }
    }

    private func enableOptionRow(flagLabel: String) {
        let toggle = app.checkBoxes.matching(NSPredicate(format: "label CONTAINS %@", flagLabel)).firstMatch
        waitFor(toggle)
        if toggle.value as? Int == 0 {
            toggle.click()
        }
    }

    private func valueMenu(forFlagID flagID: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "cli-option-value-menu-\(flagID)").firstMatch
    }

    private func createPresetTestProfile() {
        openToolsTab()
        definePresets(forFlagID: "--mcp-config", presets: ["mcp-a", "mcp-b"])
        definePresets(forFlagID: "--effort", presets: ["low", "high"])

        let profilesTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(profilesTab)
        profilesTab.click()

        let newProfileButton = app.buttons["New Profile"]
        waitFor(newProfileButton)
        newProfileButton.click()

        let nameField = app.textFields["profile-editor-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText(profileName)

        enableOptionRow(flagLabel: "--effort")
        let effortMenu = valueMenu(forFlagID: "--effort")
        waitFor(effortMenu)
        effortMenu.click()
        let highItem = app.menuItems["high"]
        waitFor(highItem)
        highItem.click()

        enableOptionRow(flagLabel: "--mcp-config")
        let mcpMenu = valueMenu(forFlagID: "--mcp-config")
        waitFor(mcpMenu)
        mcpMenu.click()
        let mcpAItem = app.menuItems["mcp-a"]
        waitFor(mcpAItem)
        mcpAItem.click()
        mcpMenu.click()
        let mcpBItem = app.menuItems["mcp-b"]
        waitFor(mcpBItem)
        mcpBItem.click()

        app.descendants(matching: .any).matching(identifier: "profile-editor-show-on-pane---effort").firstMatch
            .click()
        app.descendants(matching: .any).matching(identifier: "profile-editor-show-on-pane---mcp-config").firstMatch
            .click()

        let saveButton = app.buttons["Save"]
        waitFor(saveButton)
        saveButton.click()

        waitFor(app.staticTexts.matching(NSPredicate(format: "value == %@", profileName)).firstMatch)
    }

    func testProfileEditorSingleAndMultiSelectPresetPickers() {
        createPresetTestProfile()
        app.menuButtons["ellipsis.circle"].firstMatch.click()
        app.menuItems["Edit"].click()

        let effortMenu = valueMenu(forFlagID: "--effort")
        waitFor(effortMenu)
        XCTAssertEqual(effortMenu.title, "high", effortMenu.debugDescription)

        let mcpMenu = valueMenu(forFlagID: "--mcp-config")
        XCTAssertEqual(mcpMenu.title, "2 selected", mcpMenu.debugDescription)
    }

    func testFlagWithoutPresetsStillShowsPlainTextFieldInProfileEditor() {
        openToolsTab()
        let modelShowToggle = app.checkBoxes["settings-cli-option-show---model"]
        waitFor(modelShowToggle)
        if modelShowToggle.value as? Int == 0 {
            modelShowToggle.click()
        }
        let profilesTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(profilesTab)
        profilesTab.click()

        let newProfileButton = app.buttons["New Profile"]
        waitFor(newProfileButton)
        newProfileButton.click()

        let nameField = app.textFields["profile-editor-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("No Presets")

        enableOptionRow(flagLabel: "--model")
        let modelField = app.textFields["cli-option-value-field---model"]
        waitFor(modelField)
        XCTAssertFalse(
            valueMenu(forFlagID: "--model").exists,
            "--model has no presets and should not show a picker menu"
        )
        modelField.click()
        modelField.typeText("claude-opus-4-7")
        XCTAssertEqual(modelField.value as? String, "claude-opus-4-7")
    }

    func testNewPaneSheetPrefillsAndAllowsAdjustingPresetSelections() {
        createPresetTestProfile()
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        createTab(named: "PresetPane")
        app.typeKey("p", modifierFlags: .command)

        let profilePicker = app.descendants(matching: .any).matching(identifier: "new-pane-profile-picker").firstMatch
        waitFor(profilePicker)
        profilePicker.click()
        let presetTestItem = profilePicker.menuItems[profileName]
        waitFor(presetTestItem)
        presetTestItem.click()
        app.buttons["new-pane-cli-options-button"].click()

        let effortMenu = valueMenu(forFlagID: "--effort")
        waitFor(effortMenu)
        XCTAssertEqual(effortMenu.title, "high", effortMenu.debugDescription)

        let mcpMenu = valueMenu(forFlagID: "--mcp-config")
        waitFor(mcpMenu)
        XCTAssertEqual(mcpMenu.title, "2 selected", mcpMenu.debugDescription)

        mcpMenu.click()
        let mcpBItem = app.menuItems["mcp-b"]
        waitFor(mcpBItem)
        mcpBItem.click()
        XCTAssertEqual(mcpMenu.title, "mcp-a", mcpMenu.debugDescription)

        app.buttons["new-pane-cli-options-done-button"].click()
        let nameField = app.textFields["new-pane-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("preset-pane")
        app.buttons["new-pane-open-button"].click()
        waitForDisappear(nameField, timeout: 25)
        waitFor(app.staticTexts.matching(identifier: "pane-name-preset-pane").firstMatch, timeout: 10)
    }

    func testNewPaneShowsEnabledProfileOptionWithoutShowOnPaneCreate() {
        openToolsTab()
        let modelShowToggle = app.checkBoxes["settings-cli-option-show---model"]
        waitFor(modelShowToggle)
        if modelShowToggle.value as? Int == 0 {
            modelShowToggle.click()
        }

        let profilesTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(profilesTab)
        profilesTab.click()

        let newProfileButton = app.buttons["New Profile"]
        waitFor(newProfileButton)
        newProfileButton.click()

        let nameField = app.textFields["profile-editor-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("Selected Option Profile")

        enableOptionRow(flagLabel: "--model")
        let modelField = app.textFields["cli-option-value-field---model"]
        waitFor(modelField)
        modelField.click()
        modelField.typeText("claude-opus-4-7")

        let showOnPaneToggle = app.descendants(matching: .any)
            .matching(identifier: "profile-editor-show-on-pane---model").firstMatch
        waitFor(showOnPaneToggle)
        XCTAssertEqual(
            showOnPaneToggle.value as? Int,
            0,
            "The profile option should be enabled without being marked Show on new pane"
        )

        let showAllProfileEnvVars = app.buttons["profile-editor-show-hidden-env-vars-button"]
        waitFor(showAllProfileEnvVars)
        showAllProfileEnvVars.click()
        let environmentModelToggle = app.checkBoxes.matching(
            NSPredicate(format: "label CONTAINS 'ANTHROPIC_MODEL'")
        ).firstMatch
        waitFor(environmentModelToggle)
        let profileScroll = app.sheets.firstMatch.scrollViews.firstMatch
        let environmentScroll = app.scrollViews["profile-editor-hidden-env-vars-scroll-view"]
        waitFor(environmentScroll)
        for _ in 0..<10 where !profileScroll.frame.contains(environmentScroll.frame) {
            profileScroll.scroll(byDeltaX: 0, deltaY: -120)
        }
        for _ in 0..<10 where !environmentScroll.frame.contains(environmentModelToggle.frame) {
            environmentScroll.scroll(byDeltaX: 0, deltaY: -80)
        }
        XCTAssertTrue(environmentScroll.frame.contains(environmentModelToggle.frame))
        XCTAssertTrue(environmentModelToggle.isHittable)
        if environmentModelToggle.value as? Int == 0 {
            environmentModelToggle.click()
        }
        XCTAssertEqual(environmentModelToggle.value as? Int, 1, environmentModelToggle.debugDescription)

        let saveButton = app.buttons["Save"]
        waitFor(saveButton)
        saveButton.click()
        waitFor(
            app.staticTexts.matching(NSPredicate(format: "value == %@", "Selected Option Profile")).firstMatch
        )

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        createTab(named: "SelectedOptionsPane")
        app.typeKey("p", modifierFlags: .command)

        let profilePicker = app.descendants(matching: .any).matching(identifier: "new-pane-profile-picker").firstMatch
        waitFor(profilePicker)
        profilePicker.click()
        let profileItem = profilePicker.menuItems["Selected Option Profile"]
        waitFor(profileItem)
        profileItem.click()
        app.buttons["new-pane-cli-options-button"].click()

        let modelToggle = app.checkBoxes.matching(NSPredicate(format: "label CONTAINS '--model'")).firstMatch
        waitFor(modelToggle)
        XCTAssertTrue(modelToggle.exists, "An enabled profile option should be visible before expansion")
        let newPaneModelField = app.textFields["cli-option-value-field---model"]
        waitFor(newPaneModelField)
        XCTAssertEqual(newPaneModelField.value as? String, "claude-opus-4-7")
        let newPaneEnvironmentModelToggle = app.checkBoxes.matching(
            NSPredicate(format: "label CONTAINS 'ANTHROPIC_MODEL'")
        ).firstMatch
        waitFor(newPaneEnvironmentModelToggle)
        XCTAssertTrue(
            newPaneEnvironmentModelToggle.exists,
            "An enabled profile environment variable should be visible before expansion"
        )

        let showAllOptions = app.buttons["new-pane-show-hidden-options-button"]
        waitFor(showAllOptions)
        XCTAssertEqual(showAllOptions.label, "Show all options")
        XCTAssertFalse(
            app.checkBoxes.matching(NSPredicate(format: "label CONTAINS '--continue'")).firstMatch.exists,
            "An unselected option should remain hidden until expansion"
        )

        showAllOptions.click()
        let continueToggle = app.checkBoxes.matching(NSPredicate(format: "label CONTAINS '--continue'")).firstMatch
        waitFor(continueToggle)
        XCTAssertTrue(continueToggle.exists, "Expanding should reveal unselected options")

        newPaneModelField.click()
        newPaneModelField.typeKey("a", modifierFlags: .command)
        newPaneModelField.typeText("claude-sonnet-4-6")
        XCTAssertEqual(newPaneModelField.value as? String, "claude-sonnet-4-6")
        modelToggle.click()
        XCTAssertEqual(modelToggle.value as? Int, 0, "The selected option should be unsettable")

        app.buttons["new-pane-cli-options-done-button"].click()
        app.buttons["new-pane-cancel-button"].click()
    }

    func testTogglingAllowMultipleSelectionsSwitchesFlagToMultiSelectMenu() {
        openToolsTab()
        let allowMultipleSelections = app.checkBoxes["settings-cli-option-allow-multi---model"]
        waitFor(allowMultipleSelections)
        allowMultipleSelections.click()
        definePresets(forFlagID: "--model", presets: ["model-a", "model-b"])

        let profilesTab = app.descendants(matching: .any).matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(profilesTab)
        profilesTab.click()

        let newProfileButton = app.buttons["New Profile"]
        waitFor(newProfileButton)
        newProfileButton.click()

        let nameField = app.textFields["profile-editor-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("Multi Model Profile")

        enableOptionRow(flagLabel: "--model")
        XCTAssertFalse(
            app.textFields["cli-option-value-field---model"].exists,
            "--model should no longer render as a plain text field once multi-select is enabled"
        )

        let modelMenu = valueMenu(forFlagID: "--model")
        waitFor(modelMenu)
        modelMenu.click()
        let modelAItem = app.menuItems["model-a"]
        waitFor(modelAItem)
        modelAItem.click()
        modelMenu.click()
        let modelBItem = app.menuItems["model-b"]
        waitFor(modelBItem)
        modelBItem.click()

        XCTAssertEqual(modelMenu.title, "2 selected", modelMenu.debugDescription)

        let saveButton = app.buttons["Save"]
        waitFor(saveButton)
        saveButton.click()
        waitFor(app.staticTexts.matching(NSPredicate(format: "value == %@", "Multi Model Profile")).firstMatch)

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        createTab(named: "MultiModelPane")
        app.typeKey("p", modifierFlags: .command)

        let profilePicker = app.descendants(matching: .any).matching(identifier: "new-pane-profile-picker").firstMatch
        waitFor(profilePicker)
        profilePicker.click()
        let multiModelProfileItem = profilePicker.menuItems["Multi Model Profile"]
        waitFor(multiModelProfileItem)
        multiModelProfileItem.click()
        app.buttons["new-pane-cli-options-button"].click()

        let newPaneModelMenu = valueMenu(forFlagID: "--model")
        waitFor(newPaneModelMenu)
        XCTAssertEqual(newPaneModelMenu.title, "2 selected", newPaneModelMenu.debugDescription)
    }
}
