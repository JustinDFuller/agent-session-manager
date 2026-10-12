import XCTest

final class CodexCompatibilityFlowTests: BaseTestCase {
    func testSavedUnsupportedApprovalValueShowsCorrectionAndPreservesProfileOptions() throws {
        let versionProbe = Process()
        versionProbe.executableURL = URL(filePath: "/bin/zsh")
        versionProbe.arguments = ["-i", "-c", "codex --version"]
        let versionOutput = Pipe()
        versionProbe.standardOutput = versionOutput
        versionProbe.standardError = FileHandle.nullDevice
        let completed = DispatchSemaphore(value: 0)
        versionProbe.terminationHandler = { _ in completed.signal() }
        do {
            try versionProbe.run()
        } catch {
            throw XCTSkip("Codex compatibility flow requires the installed Codex CLI")
        }
        guard completed.wait(timeout: .now() + 8) == .success else {
            versionProbe.terminate()
            versionProbe.waitUntilExit()
            throw XCTSkip("Codex version probe exceeded 8 seconds")
        }
        let version =
            String(
                data: versionOutput.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        let versionLine = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard versionProbe.terminationStatus == 0, versionLine == "codex-cli 0.162.1" else {
            throw XCTSkip(
                "Codex compatibility flow requires Codex 0.162.1; detected a different installed version"
            )
        }

        app.typeKey(",", modifierFlags: .command)
        let settingsWindow = app.windows["AgentSessionManager Settings"]
        waitFor(settingsWindow)
        let toolsTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-tools").firstMatch
        waitFor(toolsTab)
        toolsTab.click()
        let codexSegment = settingsWindow.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Codex")).firstMatch
        waitFor(codexSegment)
        codexSegment.click()
        let codexToggle = settingsWindow.checkBoxes["settings-tool-enable-toggle-codex"]
        waitFor(codexToggle)
        if codexToggle.value as? Int != 1 { codexToggle.click() }
        XCTAssertEqual(codexToggle.value as? Int, 1)

        let approvalDescription = settingsWindow.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "approval timing")
        ).firstMatch
        waitFor(approvalDescription)
        XCTAssertTrue(approvalDescription.label.contains("on-request"))
        XCTAssertTrue(approvalDescription.label.contains("never"))
        XCTAssertFalse(approvalDescription.label.contains("untrusted"))

        let addCustomFlag = settingsWindow.buttons["Add Custom Flag"]
        waitFor(addCustomFlag)
        addCustomFlag.click()
        let customFlagName = app.textFields["--my-flag"]
        waitFor(customFlagName)
        customFlagName.click()
        customFlagName.typeText("--preserved-custom-option")
        let textType = app.radioButtons["Text"]
        waitFor(textType)
        textType.click()
        app.buttons["Add"].click()

        let profilesTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(profilesTab)
        profilesTab.click()
        let newProfile = settingsWindow.buttons["New Profile"]
        waitFor(newProfile)
        newProfile.click()
        let profileName = "Codex Compatibility Recovery"
        let profileNameField = app.textFields["profile-editor-name-field"]
        waitFor(profileNameField)
        profileNameField.click()
        profileNameField.typeText(profileName)
        let profileCodex = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Codex")).firstMatch
        waitFor(profileCodex)
        profileCodex.click()

        let showAllOptions = app.buttons["profile-editor-show-hidden-options-button"]
        waitFor(showAllOptions)
        showAllOptions.click()
        let hiddenOptions = app.scrollViews["profile-editor-hidden-options-scroll-view"]
        waitFor(hiddenOptions)
        let editorScroll = app.sheets.firstMatch.scrollViews.firstMatch
        for _ in 0..<12 where !editorScroll.frame.contains(hiddenOptions.frame) {
            editorScroll.scroll(byDeltaX: 0, deltaY: -100)
        }

        let approvalToggle = app.checkBoxes.matching(
            NSPredicate(format: "label CONTAINS %@", "--ask-for-approval")
        ).firstMatch
        waitFor(approvalToggle)
        for _ in 0..<30 where !hiddenOptions.frame.contains(approvalToggle.frame) {
            hiddenOptions.scroll(byDeltaX: 0, deltaY: -80)
        }
        XCTAssertTrue(approvalToggle.isHittable)
        approvalToggle.click()
        let approvalValue = app.textFields["cli-option-value-field---ask-for-approval"]
        waitFor(approvalValue)
        approvalValue.click()
        approvalValue.typeText("untrusted")

        let customToggle = app.checkBoxes.matching(
            NSPredicate(format: "label CONTAINS %@", "--preserved-custom-option")
        ).firstMatch
        waitFor(customToggle)
        for _ in 0..<30 where !hiddenOptions.frame.contains(customToggle.frame) {
            hiddenOptions.scroll(byDeltaX: 0, deltaY: -80)
        }
        XCTAssertTrue(customToggle.isHittable)
        customToggle.click()
        let customValue = app.textFields["cli-option-value-field---preserved-custom-option"]
        waitFor(customValue)
        customValue.click()
        customValue.typeText("keep-custom-value")

        let saveProfile = app.buttons["Save"]
        waitFor(saveProfile)
        saveProfile.click()
        waitFor(settingsWindow.staticTexts.matching(NSPredicate(format: "value == %@", profileName)).firstMatch)

        let unsupportedProfileName = "Codex Compatibility Unsupported Profile"
        settingsWindow.buttons["New Profile"].click()
        let unsupportedProfileNameField = app.textFields["profile-editor-name-field"]
        waitFor(unsupportedProfileNameField)
        unsupportedProfileNameField.click()
        unsupportedProfileNameField.typeText(unsupportedProfileName)
        let unsupportedProfileEditor = app.sheets.firstMatch
        let unsupportedProfileCodex = unsupportedProfileEditor.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Codex")).firstMatch
        waitFor(unsupportedProfileCodex)
        unsupportedProfileCodex.click()
        app.buttons["profile-editor-show-hidden-options-button"].click()
        let unsupportedOptionsScroll = app.scrollViews["profile-editor-hidden-options-scroll-view"]
        waitFor(unsupportedOptionsScroll)
        let unsupportedEditorScroll = app.sheets.firstMatch.scrollViews.firstMatch
        for _ in 0..<12 where !unsupportedEditorScroll.frame.contains(unsupportedOptionsScroll.frame) {
            unsupportedEditorScroll.scroll(byDeltaX: 0, deltaY: -100)
        }
        let unsupportedApprovalToggle = app.checkBoxes.matching(
            NSPredicate(format: "label CONTAINS %@", "--ask-for-approval")
        ).firstMatch
        waitFor(unsupportedApprovalToggle)
        for _ in 0..<30 where !unsupportedOptionsScroll.frame.contains(unsupportedApprovalToggle.frame) {
            unsupportedOptionsScroll.scroll(byDeltaX: 0, deltaY: -80)
        }
        XCTAssertTrue(unsupportedApprovalToggle.isHittable)
        unsupportedApprovalToggle.click()
        let unsupportedApprovalValue = app.textFields["cli-option-value-field---ask-for-approval"]
        waitFor(unsupportedApprovalValue)
        unsupportedApprovalValue.click()
        unsupportedApprovalValue.typeText("untrusted")
        app.buttons["Save"].click()
        waitFor(
            settingsWindow.staticTexts.matching(
                NSPredicate(format: "value == %@", unsupportedProfileName)
            ).firstMatch)
        app.typeKey("w", modifierFlags: .command)

        createTab(named: "Codex Compatibility")
        app.typeKey("p", modifierFlags: .command)
        let paneName = "codex-invalid-approval"
        let paneNameField = app.textFields["new-pane-name-field"]
        waitFor(paneNameField)
        paneNameField.click()
        paneNameField.typeText(paneName)
        let profilePicker = app.descendants(matching: .any)
            .matching(identifier: "new-pane-profile-picker").firstMatch
        waitFor(profilePicker)
        profilePicker.click()
        let savedProfile = app.menuItems[profileName]
        waitFor(savedProfile)
        savedProfile.click()
        app.buttons["new-pane-open-button"].click()

        let paneError = app.descendants(matching: .any)
            .matching(identifier: "pane-error-overlay-\(paneName)").firstMatch
        waitFor(paneError, timeout: 30)
        let unsupportedValueError = paneError.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "does not support the saved value 'untrusted'")
        ).firstMatch
        waitFor(unsupportedValueError)
        XCTAssertTrue(unsupportedValueError.label.contains("on-request"))
        XCTAssertTrue(unsupportedValueError.label.contains("never"))
        XCTAssertTrue(unsupportedValueError.label.contains("edit the affected profile"))
        XCTAssertTrue(unsupportedValueError.label.contains("Refresh Pane"))
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "pane-terminal-\(paneName)").firstMatch.exists)
        XCTAssertFalse(paneError.buttons["Retry"].exists)
        let rejectionAttachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        rejectionAttachment.name = "codex-unsupported-approval"
        rejectionAttachment.lifetime = .keepAlways
        add(rejectionAttachment)

        app.typeKey(",", modifierFlags: .command)
        let reopenedSettings = app.windows["AgentSessionManager Settings"]
        waitFor(reopenedSettings)
        let reopenedProfiles = reopenedSettings.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-profiles").firstMatch
        waitFor(reopenedProfiles)
        reopenedProfiles.click()
        let profileMenu = reopenedSettings.menuButtons.matching(identifier: "ellipsis.circle").firstMatch
        waitFor(profileMenu)
        profileMenu.click()
        app.menuItems["Edit"].click()
        let savedApprovalValue = app.textFields["cli-option-value-field---ask-for-approval"]
        waitFor(savedApprovalValue)
        XCTAssertEqual(savedApprovalValue.value as? String, "untrusted")
        let savedCustomValue = app.textFields["cli-option-value-field---preserved-custom-option"]
        waitFor(savedCustomValue)
        XCTAssertEqual(savedCustomValue.value as? String, "keep-custom-value")
        let savedCustomToggle = app.checkBoxes.matching(
            NSPredicate(format: "label CONTAINS %@", "--preserved-custom-option")
        ).firstMatch
        waitFor(savedCustomToggle)
        if savedCustomToggle.value as? Int == 1 { savedCustomToggle.click() }
        savedApprovalValue.click()
        savedApprovalValue.typeKey("a", modifierFlags: .command)
        savedApprovalValue.typeText("on-request")
        app.buttons["Save"].click()
        app.typeKey("w", modifierFlags: .command)

        paneError.rightClick()
        let refreshPane = app.menuItems["Refresh Pane…"]
        waitFor(refreshPane)
        refreshPane.click()
        let refreshSettings = app.buttons["refresh-pane-settings"]
        waitFor(refreshSettings)
        refreshSettings.click()
        let refreshButton = app.buttons["Refresh"]
        waitFor(refreshButton)
        refreshButton.click()
        let recoveredTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-\(paneName)").firstMatch
        waitFor(recoveredTerminal, timeout: 30)
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "pane-exit-prompt-\(paneName)").firstMatch.exists)
        let recoveryAttachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        recoveryAttachment.name = "codex-corrected-approval"
        recoveryAttachment.lifetime = .keepAlways
        add(recoveryAttachment)

        recoveredTerminal.rightClick()
        let secondRefreshPane = app.menuItems["Refresh Pane…"]
        waitFor(secondRefreshPane)
        secondRefreshPane.click()
        let secondRefreshSettings = app.buttons["refresh-pane-settings"]
        waitFor(secondRefreshSettings)
        secondRefreshSettings.click()
        let refreshSheet = app.sheets.firstMatch
        let refreshProfilePicker = refreshSheet.descendants(matching: .any)
            .matching(identifier: "new-pane-profile-picker").firstMatch
        waitFor(refreshProfilePicker)
        refreshProfilePicker.click()
        let unsupportedProfileOption = app.menuItems[unsupportedProfileName]
        waitFor(unsupportedProfileOption)
        unsupportedProfileOption.click()
        app.buttons["Refresh"].click()
        waitFor(paneError, timeout: 30)
        let crossProfileError = paneError.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "does not support the saved value 'untrusted'")
        ).firstMatch
        waitFor(crossProfileError)
        XCTAssertTrue(crossProfileError.label.contains("edit the affected profile"))
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "pane-terminal-\(paneName)").firstMatch.exists)
        let crossProfileAttachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        crossProfileAttachment.name = "codex-cross-profile-rejection"
        crossProfileAttachment.lifetime = .keepAlways
        add(crossProfileAttachment)
    }
}
