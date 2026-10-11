import XCTest

let mainWindowTitle = "Agent Session Manager (Dev)"

extension XCTestCase {
    func screenshot(_ name: String, app: XCUIApplication) {
        let captured = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: captured)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let outputPath = ProcessInfo.processInfo.environment["SCREENSHOTS_OUTPUT_PATH"] {
            let dir = URL(fileURLWithPath: outputPath)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? captured.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }
}

extension BaseTestCase {
    func createTab(named name: String) {
        if !appLaunchArguments.contains("--uitesting") {
            let onboardingSkipButton = app.buttons["onboarding-skip-button"]
            if onboardingSkipButton.waitForExistence(timeout: 2) {
                onboardingSkipButton.click()
            }
        }
        let fileMenu = app.menuBars.menuBarItems["File"]
        waitFor(fileMenu)
        fileMenu.click()
        let newTab = fileMenu.menuItems["New Tab"]
        waitFor(newTab)
        newTab.click()
        let field = app.textFields["new-tab-name-field"]
        waitFor(field)
        field.click()
        field.typeText(name)
        app.buttons["new-tab-choose-dir-button"].click()
        if !appLaunchArguments.contains("--uitesting") {
            let directoryPicker = app.dialogs["open-panel"]
            let selectDirectory = directoryPicker.buttons["OKButton"]
            waitFor(selectDirectory)
            let pickerInitiallyReady = expectation(
                for: NSPredicate(format: "hittable == true"), evaluatedWith: selectDirectory)
            wait(for: [pickerInitiallyReady], timeout: 15)
            directoryPicker.typeKey("g", modifierFlags: [.command, .shift])
            let folderEntryReady = expectation(
                for: NSPredicate(format: "hittable == false"), evaluatedWith: selectDirectory)
            wait(for: [folderEntryReady], timeout: 15)
            directoryPicker.typeKey("a", modifierFlags: .command)
            directoryPicker.typeText(GitUITestWorkspace.directoryURL.path)
            directoryPicker.typeKey(.enter, modifierFlags: [])
            let pickerReady = expectation(
                for: NSPredicate(format: "hittable == true"), evaluatedWith: selectDirectory)
            wait(for: [pickerReady], timeout: 15)
            selectDirectory.click()
            let directoryLabel = app.staticTexts["new-tab-directory-label"]
            waitFor(directoryLabel)
            XCTAssertEqual(
                (directoryLabel.value as? String).map {
                    URL(filePath: $0).resolvingSymlinksInPath().standardizedFileURL.path
                },
                GitUITestWorkspace.directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
            )
        }
        let createBtn = app.buttons["new-tab-create-button"]
        waitFor(createBtn)
        let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: createBtn)
        wait(for: [enabled], timeout: 15)
        XCTAssertTrue(createBtn.isEnabled, "Create button should be enabled after choosing directory")
        createBtn.click()
        waitFor(app.buttons["tab-button-\(name)"].firstMatch)
    }

    func createPane(named name: String) {
        app.typeKey("p", modifierFlags: .command)
        let field = app.textFields["new-pane-name-field"]
        waitFor(field)
        field.click()
        field.typeText(name)
        app.buttons["new-pane-open-button"].click()
        waitForDisappear(field, timeout: 25)
        waitFor(app.staticTexts.matching(identifier: "pane-name-\(name)").firstMatch, timeout: 10)
        waitFor(app.descendants(matching: .any).matching(identifier: "status-line-row").firstMatch, timeout: 10)
    }

    func openShellHere(from paneName: String) -> String {
        let sourceHeader = app.descendants(matching: .any)
            .matching(identifier: "pane-header-\(paneName)").firstMatch
        waitFor(sourceHeader)

        let baseName = "shell:\(paneName)"
        var shellName = baseName
        var suffix = 2
        while app.staticTexts["pane-name-\(shellName)"].exists {
            shellName = "\(baseName)-\(suffix)"
            suffix += 1
        }

        sourceHeader.rightClick()
        let menuItem = app.windows.firstMatch.menuItems["Open Shell Here"]
        waitFor(menuItem)
        menuItem.click()
        waitFor(app.staticTexts["pane-name-\(shellName)"].firstMatch, timeout: 10)
        return shellName
    }

    func typeTerminalCommand(_ command: String) {
        app.typeText(command)
        app.typeKey(.enter, modifierFlags: [])
    }
}
