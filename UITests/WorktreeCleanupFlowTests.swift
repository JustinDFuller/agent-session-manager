import XCTest

final class WorktreeCleanupFlowTests: BaseTestCase {
    private let paneWait: TimeInterval = 25

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
        waitFor(deleteAnyway, timeout: paneWait)
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
        waitFor(deleteAnyway, timeout: paneWait)
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
        waitFor(ok, timeout: paneWait)
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
        waitFor(deleteWorktrees, timeout: paneWait)
        XCTAssertTrue(app.windows.buttons["Keep Worktrees"].firstMatch.exists)
        XCTAssertTrue(app.windows.buttons["Cancel"].firstMatch.exists)
        screenshot("22-tab-close-dialog")
        deleteWorktrees.click()

        let keep = app.windows.buttons["Keep Worktree"].firstMatch
        waitFor(keep, timeout: paneWait)
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
        waitFor(cancel, timeout: paneWait)
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

    private func showsText(_ text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        return app.sheets.staticTexts.matching(predicate).firstMatch.exists
    }

    private func makeUnsavedWorktree(folder: String) {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: folder, newTrackingBranch: "track-\(folder)")
        let checkout = GitUITestWorkspace.worktreeURL(folder: folder)
        try? Data("committed".utf8).write(to: checkout.appending(path: "committed.txt"))
        GitUITestWorkspace.runGitOrFail(["add", "committed.txt"], cwd: checkout)
        GitUITestWorkspace.runGitOrFail(
            ["-c", "user.email=uitest@example.com", "-c", "user.name=uitest", "commit", "-m", "local work"],
            cwd: checkout)
        try? Data("scratch".utf8).write(to: checkout.appending(path: "scratch.txt"))
    }

    private func openPane(named name: String) {
        app.typeKey("p", modifierFlags: .command)
        let field = app.textFields["new-pane-name-field"]
        waitFor(field)
        field.click()
        field.typeText(name)
        app.buttons["new-pane-open-button"].click()
        waitForDisappear(field, timeout: paneWait)
        waitFor(app.staticTexts.matching(identifier: "pane-name-\(name)").firstMatch, timeout: 10)
    }

    private func closePane(named name: String) {
        app.descendants(matching: .any).matching(identifier: "pane-close-\(name)").firstMatch.click()
        let delete = app.windows.buttons["Delete Worktree"].firstMatch
        if delete.waitForExistence(timeout: 5) { delete.click() }
    }

    private func openSettingsPanes() {
        app.typeKey(",", modifierFlags: .command)
        let sidebar = app.descendants(matching: .any).matching(identifier: "settings-sidebar-panes").firstMatch
        waitFor(sidebar, timeout: 10)
        sidebar.click()
    }

    private func select(_ row: XCUIElement) {
        let isOn = (row.value as? NSNumber)?.intValue == 1 || (row.value as? String) == "1"
        if !isOn { row.click() }
    }

    private func scrollToVisible(_ element: XCUIElement) {
        let window = app.windows["AgentSessionManager Settings"]
        let content = window.scrollViews.containing(.button, identifier: "settings-leftovers-refresh").firstMatch
        var attempts = 0
        while !element.exists || !window.frame.contains(element.frame), attempts < 20 {
            content.scroll(byDeltaX: 0, deltaY: -400)
            attempts += 1
        }
        waitFor(element)
    }

    private func waitUntil(timeout: TimeInterval = 30, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(condition(), "Condition was not met within \(timeout)s")
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

        app.typeKey(",", modifierFlags: .command)
        let sidebar = app.descendants(matching: .any).matching(identifier: "settings-sidebar-panes").firstMatch
        waitFor(sidebar, timeout: 10)
        sidebar.click()
        let dirtyRow = app.checkBoxes["settings-leftover-stale-dirty"]
        let window = app.windows["AgentSessionManager Settings"]
        let content = window.scrollViews.containing(.button, identifier: "settings-leftovers-refresh").firstMatch
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
