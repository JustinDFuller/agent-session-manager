import AppKit
import XCTest

final class SectionResizingCodexFlowTests: BaseTestCase {
    private enum CodexStartupState {
        case trustPrompt
        case ready
    }

    override var appLaunchArguments: [String] { ["--uitesting-skip-restore"] + additionalLaunchArguments }
    override var additionalLaunchEnvironment: [String: String] { ["TERM": "xterm-256color"] }

    func testRealCodexRespondsAfterPointerAndKeyboardResizing() throws {
        let loginStatus = Process()
        loginStatus.executableURL = URL(filePath: "/bin/zsh")
        loginStatus.arguments = ["-i", "-c", "codex login status"]
        loginStatus.standardOutput = FileHandle.nullDevice
        loginStatus.standardError = FileHandle.nullDevice
        do {
            try loginStatus.run()
        } catch {
            throw XCTSkip("Real Codex continuity requires an installed, authenticated Codex CLI")
        }
        loginStatus.waitUntilExit()
        guard loginStatus.terminationStatus == 0 else {
            throw XCTSkip("Real Codex continuity requires an installed, authenticated Codex CLI")
        }

        typealias PasteboardRepresentation = (type: NSPasteboard.PasteboardType, data: Data)
        let priorPasteboardItems: [[PasteboardRepresentation]] = {
            var snapshots: [[PasteboardRepresentation]] = []
            for pasteboardItem in NSPasteboard.general.pasteboardItems ?? [] {
                var representations: [PasteboardRepresentation] = []
                for type in pasteboardItem.types {
                    if let data = pasteboardItem.data(forType: type) {
                        representations.append((type: type, data: data))
                    }
                }
                snapshots.append(representations)
            }
            return snapshots
        }()
        defer {
            NSPasteboard.general.clearContents()
            var restoredItems: [NSPasteboardItem] = []
            for representations in priorPasteboardItems {
                let item = NSPasteboardItem()
                for representation in representations {
                    item.setData(representation.data, forType: representation.type)
                }
                restoredItems.append(item)
            }
            if !restoredItems.isEmpty {
                _ = NSPasteboard.general.writeObjects(restoredItems)
            }
        }

        let onboardingSkipButton = app.buttons["onboarding-skip-button"]
        waitFor(onboardingSkipButton)
        onboardingSkipButton.click()

        app.typeKey(",", modifierFlags: .command)
        let settingsWindow = app.windows["AgentSessionManager Settings"]
        waitFor(settingsWindow)
        let toolsTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-tools").firstMatch
        waitFor(toolsTab)
        toolsTab.click()
        let codexTool = settingsWindow.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Codex")).firstMatch
        waitFor(codexTool)
        codexTool.click()
        let codexToggle = settingsWindow.checkBoxes["settings-tool-enable-toggle-codex"]
        waitFor(codexToggle)
        if codexToggle.value as? Int != 1 { codexToggle.click() }
        XCTAssertEqual(codexToggle.value as? Int, 1)
        app.typeKey("w", modifierFlags: .command)

        app.typeKey("t", modifierFlags: .command)
        let tabNameField = app.textFields["new-tab-name-field"]
        waitFor(tabNameField)
        tabNameField.click()
        tabNameField.typeText("Resize Codex Continuity")
        app.buttons["new-tab-choose-dir-button"].click()
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
            (directoryLabel.value as? String).map { URL(filePath: $0).resolvingSymlinksInPath().path },
            GitUITestWorkspace.directoryURL.resolvingSymlinksInPath().path)
        let createTabButton = app.buttons["new-tab-create-button"]
        XCTAssertTrue(createTabButton.isEnabled)
        createTabButton.click()
        waitFor(app.buttons["tab-button-Resize Codex Continuity"].firstMatch)

        app.typeKey("p", modifierFlags: .command)
        let paneName = "resize-codex-source"
        let paneNameField = app.textFields["new-pane-name-field"]
        waitFor(paneNameField)
        paneNameField.click()
        paneNameField.typeText(paneName)
        let codexPicker = app.descendants(matching: .any)
            .matching(identifier: "new-pane-cli-picker").firstMatch
        waitFor(codexPicker)
        let codexChoice = codexPicker.radioButtons.matching(NSPredicate(format: "label == %@", "Codex")).firstMatch
        waitFor(codexChoice)
        codexChoice.click()
        app.buttons["new-pane-open-button"].click()
        waitForDisappear(paneNameField, timeout: 30)

        let codexTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-\(paneName)").firstMatch
        waitFor(codexTerminal, timeout: 30)
        let codexIdleIndicator = app.descendants(matching: .any)
            .matching(identifier: "pane-activity-idle-\(paneName)").firstMatch
        waitFor(codexIdleIndicator, timeout: 30)

        let worktreeURL = GitUITestWorkspace.directoryURL
            .appending(path: ".agent-session-manager/worktrees/\(paneName)")
            .resolvingSymlinksInPath()
        let repositoryURL = GitUITestWorkspace.directoryURL.resolvingSymlinksInPath()
        let startupState = waitForCodexStartup(
            from: codexTerminal,
            worktreeURL: worktreeURL,
            repositoryURL: repositoryURL)
        if startupState == .trustPrompt {
            codexTerminal.typeKey(.enter, modifierFlags: [])
            XCTAssertEqual(
                waitForCodexStartup(
                    from: codexTerminal,
                    worktreeURL: worktreeURL,
                    repositoryURL: repositoryURL),
                .ready)
        }

        let codexHeader = app.descendants(matching: .any)
            .matching(identifier: "pane-header-\(paneName)").firstMatch
        waitFor(codexHeader)
        codexHeader.rightClick()
        let openShellItem = app.windows.firstMatch.menuItems["Open Shell Here"]
        waitFor(openShellItem)
        openShellItem.click()
        let shellName = "shell:\(paneName)"
        waitFor(app.staticTexts["pane-name-\(shellName)"].firstMatch, timeout: 15)
        codexTerminal.click()
        requestCodexMarkerResponse(from: codexTerminal)

        let divider = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'column-divider-0'")).firstMatch
        waitFor(divider)
        let initialWidth = try XCTUnwrap((divider.value as? NSNumber)?.doubleValue)
        let pointerStart = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        pointerStart.press(forDuration: 0.1, thenDragTo: pointerStart.withOffset(CGVector(dx: 24, dy: 0)))
        XCTAssertEqual((divider.value as? NSNumber)?.doubleValue ?? -1, initialWidth + 24, accuracy: 2)

        requestCodexMarkerResponse(from: codexTerminal)

        let widthBeforeKeyboard = try XCTUnwrap((divider.value as? NSNumber)?.doubleValue)
        app.typeKey(.rightArrow, modifierFlags: [.command, .option, .shift])
        XCTAssertEqual((divider.value as? NSNumber)?.doubleValue ?? -1, widthBeforeKeyboard + 16, accuracy: 2)

        requestCodexMarkerResponse(from: codexTerminal)
        screenshot("section-resizing-live-codex-continuity")
    }

    private func requestCodexMarkerResponse(from terminal: XCUIElement) {
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let firstFragment = String(nonce.prefix(16))
        let secondFragment = String(nonce.suffix(16))
        let marker = firstFragment + secondFragment
        let prompt =
            "Concatenate these two fragments in order and reply with only the result: \(firstFragment) then \(secondFragment)"
        XCTAssertFalse(prompt.contains(marker))
        terminal.click()
        app.typeText(prompt)
        terminal.typeKey(.enter, modifierFlags: [])

        let responseDeadline = Date().addingTimeInterval(120)
        var responseCopied = false
        while Date() < responseDeadline && !responseCopied {
            responseCopied = normalizeTerminalOutput(copiedTerminalOutput(from: terminal)).contains(marker)
            if !responseCopied {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }
        XCTAssertTrue(responseCopied, "Expected the real Codex response in the copied terminal output")
    }

    private func waitForCodexStartup(
        from terminal: XCUIElement,
        worktreeURL: URL,
        repositoryURL: URL
    ) -> CodexStartupState {
        let exitPrompt = app.descendants(matching: .any)
            .matching(identifier: "pane-exit-prompt-resize-codex-source").firstMatch
        let deadline = Date().addingTimeInterval(60)
        terminal.click()

        while Date() < deadline {
            let output = copiedTerminalOutput(from: terminal)
            let normalizedOutput = normalizeTerminalOutput(output)

            if exitPrompt.exists {
                XCTFail("Codex exited before its interactive prompt became ready")
                return .ready
            }

            if normalizedOutput.contains("Folderaccess") || normalizedOutput.contains("Trustthisfolder?") {
                let displayedWorktree =
                    normalizedOutput
                    .components(separatedBy: "Folderaccess")
                    .dropFirst()
                    .first?
                    .components(separatedBy: "Note:")
                    .first
                let displayedRepository =
                    normalizedOutput
                    .components(separatedBy: "repositoryroot:")
                    .dropFirst()
                    .first?
                    .components(separatedBy: "Trustthisfolder?")
                    .first
                let displayedWorktreeIdentity = displayedWorktree.flatMap(canonicalDirectoryPath)
                let expectedWorktreeIdentity = canonicalDirectoryPath(worktreeURL.path)
                let displayedRepositoryIdentity = displayedRepository.flatMap(canonicalDirectoryPath)
                let expectedRepositoryIdentity = canonicalDirectoryPath(repositoryURL.path)
                let trustPromptIsExpected =
                    normalizedOutput.contains("Folderaccess")
                    && normalizedOutput.contains("Trustthisfolder?")
                    && normalizedOutput.contains("repositoryroot:")
                    && displayedWorktreeIdentity != nil
                    && displayedWorktreeIdentity == expectedWorktreeIdentity
                    && displayedRepositoryIdentity != nil
                    && displayedRepositoryIdentity == expectedRepositoryIdentity
                let trustOptionIsSelected =
                    normalizedOutput.contains("›1.Trustandcontinue")
                    && normalizedOutput.contains("2.Quit")

                guard trustPromptIsExpected, trustOptionIsSelected else {
                    XCTFail(
                        "Codex showed an unexpected workspace trust prompt or selection "
                            + "(worktreePathParsed: \(displayedWorktree != nil), "
                            + "worktreeIdentityMatched: \(displayedWorktreeIdentity == expectedWorktreeIdentity), "
                            + "repositoryPathParsed: \(displayedRepository != nil), "
                            + "repositoryIdentityMatched: \(displayedRepositoryIdentity == expectedRepositoryIdentity), "
                            + "trustOptionSelected: \(trustOptionIsSelected))")
                    return .ready
                }

                return .trustPrompt
            }

            if normalizedOutput.contains("AskCodextodoanything") {
                return .ready
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTFail("Codex did not reach its interactive prompt within 60 seconds")
        return .ready
    }

    private func copiedTerminalOutput(from terminal: XCUIElement) -> String {
        terminal.typeKey("a", modifierFlags: .command)
        terminal.typeKey("c", modifierFlags: .command)
        return NSPasteboard.general.string(forType: .string) ?? ""
    }

    private func normalizeTerminalOutput(_ output: String) -> String {
        output.filter { !$0.isWhitespace }
    }

    private func canonicalDirectoryPath(_ path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(filePath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
