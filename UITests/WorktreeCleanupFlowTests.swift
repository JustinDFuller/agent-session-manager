import XCTest

final class WorktreeCleanupFlowTests: BaseTestCase {
    override func setUp() {
        super.setUp()
        try? Data("\"head\"".utf8).write(to: UITestAppSupport.directory.appending(path: "worktree-base-ref.json"))
        createTab(named: "CleanupTab")
    }

    func testUnsavedWorkDialogKeepsThenDeletesAnyway() {
        makeUnsavedWorktree(folder: "wt-unsaved")
        openPane(named: "wt-unsaved")

        closePane(named: "wt-unsaved")
        let unsavedKeep = app.windows.buttons["Keep Worktree"].firstMatch
        let deleteAnyway = app.windows.buttons["Delete Anyway"].firstMatch
        waitFor(deleteAnyway, timeout: cleanupWait)
        XCTAssertTrue(unsavedKeep.exists)
        XCTAssertTrue(showsText("Worktree Has Unsaved Work"))
        XCTAssertTrue(
            showsText("1 untracked file"))
        XCTAssertTrue(
            showsText("1 commit not on any remote"))
        screenshot("20-unsaved-work-dialog")
        unsavedKeep.click()
        waitForDisappear(app.staticTexts["pane-name-wt-unsaved"].firstMatch, timeout: 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-unsaved").path))
        XCTAssertTrue(GitUITestWorkspace.localBranches().contains("track-wt-unsaved"))

        openPane(named: "wt-unsaved")
        closePane(named: "wt-unsaved")
        waitFor(deleteAnyway, timeout: cleanupWait)
        deleteAnyway.click()
        waitForDisappear(app.staticTexts["pane-name-wt-unsaved"].firstMatch, timeout: 10)
        waitUntil { !FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-unsaved").path) }
        waitUntil { !GitUITestWorkspace.localBranches().contains("track-wt-unsaved") }
    }

    func testCleanWorktreeIsDeletedWithItsBranchWithoutAnUnsavedWorkDialog() {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-clean", newTrackingBranch: "track-wt-clean")
        openPane(named: "wt-clean")
        closePane(named: "wt-clean")
        XCTAssertFalse(app.windows.buttons["Delete Anyway"].firstMatch.waitForExistence(timeout: 3))
        waitUntil { !FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-clean").path) }
        waitUntil { !GitUITestWorkspace.localBranches().contains("track-wt-clean") }
    }

    func testSharedShellPaneKeepsTheWorktreeAndSaysWhy() {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-shared", newTrackingBranch: "track-wt-shared")
        openPane(named: "wt-shared")
        let shellName = openShellHere(from: "wt-shared")

        closePane(named: "wt-shared")
        let ok = app.windows.buttons["OK"].firstMatch
        waitFor(ok, timeout: cleanupWait)
        XCTAssertTrue(showsText("Worktree Kept"))
        XCTAssertTrue(
            showsText("Another pane is still using it."))
        screenshot("21-worktree-in-use-notice")
        ok.click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-shared").path))
        XCTAssertTrue(app.staticTexts["pane-name-\(shellName)"].firstMatch.exists)
    }

    func testClosingATabAsksOnceAndOnlyTheUnsavedWorktreeStays() {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-tab-clean", newTrackingBranch: "track-wt-tab-clean")
        makeUnsavedWorktree(folder: "wt-tab-dirty")
        openPane(named: "wt-tab-clean")
        openPane(named: "wt-tab-dirty")

        app.typeKey("k", modifierFlags: .command)
        let deleteWorktrees = app.windows.buttons["Delete Worktrees"].firstMatch
        waitFor(deleteWorktrees, timeout: cleanupWait)
        XCTAssertTrue(app.windows.buttons["Keep Worktrees"].firstMatch.exists)
        XCTAssertTrue(app.windows.buttons["Cancel"].firstMatch.exists)
        screenshot("22-tab-close-dialog")
        deleteWorktrees.click()

        let keep = app.windows.buttons["Keep Worktree"].firstMatch
        waitFor(keep, timeout: cleanupWait)
        XCTAssertTrue(app.windows.buttons["Delete Anyway"].firstMatch.exists)
        XCTAssertTrue(
            showsText("wt-tab-dirty has unsaved work"))
        XCTAssertFalse(
            showsText("wt-tab-clean has unsaved work"))
        screenshot("23-tab-close-unsaved-dialog")
        keep.click()

        waitFor(emptyStateHint, timeout: 15)
        waitUntil {
            !FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-tab-clean").path)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-tab-dirty").path))
    }

    func testTabCloseCancelLeavesTheTabAndWorktreesAlone() {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-cancel", newTrackingBranch: "track-wt-cancel")
        openPane(named: "wt-cancel")
        app.typeKey("k", modifierFlags: .command)
        let cancel = app.windows.buttons["Cancel"].firstMatch
        waitFor(cancel, timeout: cleanupWait)
        cancel.click()
        waitForDisappear(cancel)
        XCTAssertTrue(app.buttons["tab-button-CleanupTab"].firstMatch.exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-cancel").path))
    }

    func testLeftoversListShowsEveryCaseAndDeletesThroughTheSameChecks() {
        makeUnsavedWorktree(folder: "left-dirty")
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "left-clean", newTrackingBranch: "track-left-clean")
        let unregistered = GitUITestWorkspace.worktreeURL(folder: "milestone-x")
        try? FileManager.default.createDirectory(at: unregistered, withIntermediateDirectories: true)
        try? Data("state".utf8).write(to: unregistered.appending(path: "UserInterfaceState.xcuserstate"))

        openSettingsPanes()
        let cleanRow = app.checkBoxes["settings-leftover-left-clean"]
        scrollToVisible(app.checkBoxes["settings-leftover-milestone-x"])
        XCTAssertTrue(app.checkBoxes["settings-leftover-left-dirty"].exists)
        XCTAssertTrue(app.checkBoxes["settings-leftover-milestone-x"].exists)
        XCTAssertTrue(app.checkBoxes["settings-leftover-milestone-x"].label.contains("Not a git worktree"))
        screenshot("24-leftovers-list")

        cleanRow.click()
        app.buttons["settings-leftovers-delete"].click()
        waitUntil { !FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "left-clean").path) }
        waitForDisappear(app.checkBoxes["settings-leftover-left-clean"], timeout: 15)
        XCTAssertFalse(GitUITestWorkspace.localBranches().contains("track-left-clean"))

        app.checkBoxes["settings-leftover-left-dirty"].click()
        app.buttons["settings-leftovers-delete"].click()
        let keep = app.sheets.buttons["Keep Worktree"].firstMatch
        waitFor(keep, timeout: 15)
        XCTAssertTrue(app.sheets.buttons["Delete Anyway"].firstMatch.exists)
        screenshot("25-leftovers-unsaved-dialog")
        keep.click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "left-dirty").path))

        select(app.checkBoxes["settings-leftover-left-dirty"])
        select(app.checkBoxes["settings-leftover-milestone-x"])
        app.buttons["settings-leftovers-delete"].click()
        let anyway = app.sheets.buttons["Delete Anyway"].firstMatch
        waitFor(anyway, timeout: 15)
        anyway.click()
        let deleteFolder = app.sheets.buttons["Delete Folder"].firstMatch
        waitFor(deleteFolder, timeout: 15)
        screenshot("26-leftovers-folder-confirmation")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unregistered.path))
        deleteFolder.click()
        waitUntil { !FileManager.default.fileExists(atPath: unregistered.path) }
        waitUntil { !FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "left-dirty").path) }
        waitFor(app.staticTexts["settings-leftovers-empty"].firstMatch, timeout: 15)
        screenshot("27-leftovers-empty")
    }
}

final class LaunchCleanupFlowTests: BaseTestCase {
    override var appLaunchArguments: [String] { ["--uitesting"] }

    override func prepareTestWorkspace() {
        for folder in ["stale-clean", "stale-dirty", "fresh-clean"] {
            GitUITestWorkspace.addManagedSecondaryWorktree(folder: folder, newTrackingBranch: "track-\(folder)")
        }
        try? Data("scratch".utf8).write(
            to: GitUITestWorkspace.worktreeURL(folder: "stale-dirty").appending(path: "scratch.txt"))
        GitUITestWorkspace.ageWorktree(folder: "stale-clean", days: 3)
        GitUITestWorkspace.ageWorktree(folder: "stale-dirty", days: 3)
        let known = try? JSONEncoder().encode([GitUITestWorkspace.directoryURL.path])
        try? known?.write(to: UITestAppSupport.directory.appending(path: "known-repositories.json"))
        try? Data(#"{"schemaVersion":1,"enabled":true}"#.utf8).write(
            to: UITestAppSupport.directory.appending(path: "debug-settings.json"))
    }

    private func recordedSweepDecisions() -> String {
        let traces = UITestAppSupport.directory.appending(path: "traces")
        guard
            let files = FileManager.default.enumerator(at: traces, includingPropertiesForKeys: nil)?
                .compactMap({ $0 as? URL }).filter({ $0.pathExtension == "jsonl" })
        else { return "" }
        return files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    func testLaunchRemovesAStaleCleanLeftoverAndKeepsTheRest() {
        let deadline = Date().addingTimeInterval(60)
        while FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "stale-clean").path)
            || GitUITestWorkspace.localBranches().contains("track-stale-clean"),
            Date() < deadline
        {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "stale-clean").path))
        XCTAssertFalse(GitUITestWorkspace.localBranches().contains("track-stale-clean"))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "stale-dirty").path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "fresh-clean").path))
        XCTAssertTrue(GitUITestWorkspace.localBranches().contains("track-stale-dirty"))
        XCTAssertTrue(GitUITestWorkspace.localBranches().contains("track-fresh-clean"))
        screenshot("28-after-launch-cleanup")

        var decisions = recordedSweepDecisions()
        let traceDeadline = Date().addingTimeInterval(15)
        while !decisions.contains("worktree.leftover.skipped"), Date() < traceDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            decisions = recordedSweepDecisions()
        }
        XCTAssertTrue(decisions.contains("worktree.leftover.removed"))
        XCTAssertTrue(decisions.contains("worktree.leftover.skipped"))
        XCTAssertTrue(decisions.contains("stale-clean"))
        XCTAssertTrue(decisions.contains("stale-dirty"))
        XCTAssertTrue(decisions.contains("fresh-clean"))
        if let outputPath = ProcessInfo.processInfo.environment["SCREENSHOTS_OUTPUT_PATH"] {
            try? decisions.write(
                to: URL(filePath: outputPath).appending(path: "launch-sweep-traces.jsonl"),
                atomically: true, encoding: .utf8)
        }

        app.typeKey(",", modifierFlags: .command)
        let sidebar = app.descendants(matching: .any).matching(identifier: "settings-sidebar-panes").firstMatch
        waitFor(sidebar, timeout: 10)
        sidebar.click()
        let dirtyRow = app.checkBoxes["settings-leftover-stale-dirty"]
        let window = app.windows["AgentSessionManager Settings"]
        let content = window.scrollViews.containing(.button, identifier: "settings-leftovers-delete").firstMatch
        var attempts = 0
        while !dirtyRow.exists || !window.frame.contains(dirtyRow.frame), attempts < 20 {
            content.scroll(byDeltaX: 0, deltaY: -400)
            attempts += 1
        }
        waitFor(dirtyRow)
        XCTAssertFalse(app.checkBoxes["settings-leftover-stale-clean"].exists)
        screenshot("29-leftovers-after-launch-cleanup")
    }
}
