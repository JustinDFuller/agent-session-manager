import XCTest

final class WorktreeCleanupVariantsFlowTests: BaseTestCase {
    override func prepareTestWorkspace() {
        let root = GitUITestWorkspace.directoryURL
        try? Data("tracked".utf8).write(to: root.appending(path: "tracked.txt"))
        try? Data("*.log\n".utf8).write(to: root.appending(path: ".gitignore"))
        GitUITestWorkspace.runGitOrFail(["add", "tracked.txt", ".gitignore"], cwd: root)
        GitUITestWorkspace.runGitOrFail(
            ["-c", "user.email=uitest@example.com", "-c", "user.name=uitest", "commit", "-m", "tracked file"],
            cwd: root)
        GitUITestWorkspace.runGitOrFail(["push", "origin", "ui-root"], cwd: root)
        try? Data("\"head\"".utf8).write(to: UITestAppSupport.directory.appending(path: "worktree-base-ref.json"))
    }

    override func setUp() {
        super.setUp()
        createTab(named: "VariantTab")
    }

    func testModifiedFileShowsTheUnsavedWorkDialog() {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-modified", newTrackingBranch: "track-wt-modified")
        let checkout = GitUITestWorkspace.worktreeURL(folder: "wt-modified")
        try? Data("changed".utf8).write(to: checkout.appending(path: "tracked.txt"))
        openPane(named: "wt-modified")

        closePane(named: "wt-modified")
        let keep = app.windows.buttons["Keep Worktree"].firstMatch
        waitFor(keep, timeout: cleanupWait)
        XCTAssertTrue(showsText("1 modified file"))
        XCTAssertFalse(showsText("untracked"))
        screenshot("30-modified-file-dialog")
        keep.click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testDetachedHeadWithLocalCommitShowsTheUnsavedWorkDialog() {
        let folder = "wt-detached"
        let rel = ".agent-session-manager/worktrees/\(folder)"
        GitUITestWorkspace.runGitOrFail(
            ["worktree", "add", "--detach", rel, "ui-root"], cwd: GitUITestWorkspace.directoryURL)
        let checkout = GitUITestWorkspace.worktreeURL(folder: folder)
        GitUITestWorkspace.runGitOrFail(
            [
                "-c", "user.email=uitest@example.com", "-c", "user.name=uitest", "commit", "--allow-empty", "-m",
                "local",
            ],
            cwd: checkout)
        openPane(named: folder)

        closePane(named: folder)
        let keep = app.windows.buttons["Keep Worktree"].firstMatch
        waitFor(keep, timeout: cleanupWait)
        XCTAssertTrue(showsText("1 commit not on any remote on a detached HEAD"))
        screenshot("31-detached-head-dialog")
        keep.click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testGitRefusalShowsTheFailureAlertAndKeepsTheWorktree() {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-locked", newTrackingBranch: "track-wt-locked")
        openPane(named: "wt-locked")
        GitUITestWorkspace.runGitOrFail(
            ["worktree", "lock", GitUITestWorkspace.worktreeURL(folder: "wt-locked").path],
            cwd: GitUITestWorkspace.directoryURL)

        closePane(named: "wt-locked")
        let ok = app.windows.buttons["OK"].firstMatch
        waitFor(ok, timeout: cleanupWait)
        XCTAssertTrue(showsText("Worktree Cleanup Failed"))
        XCTAssertTrue(showsText("Could not delete wt-locked"))
        screenshot("32-cleanup-failed-alert")
        ok.click()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-locked").path))
        XCTAssertTrue(GitUITestWorkspace.localBranches().contains("track-wt-locked"))
    }

    func testProcessStillWritingInTheWorktreeEndsWithRemovalOrAFailureAlert() {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-busy", newTrackingBranch: "track-wt-busy")
        openPane(named: "wt-busy")
        let checkout = GitUITestWorkspace.worktreeURL(folder: "wt-busy")
        let writer = Process()
        writer.executableURL = URL(filePath: "/bin/sh")
        writer.arguments = ["-c", "while true; do date >> busy.log; sleep 0.05; done"]
        writer.currentDirectoryURL = checkout
        try? writer.run()
        defer { writer.terminate() }
        let log = checkout.appending(path: "busy.log")
        waitUntil { FileManager.default.fileExists(atPath: log.path) }

        closePane(named: "wt-busy")
        let ok = app.windows.buttons["OK"].firstMatch
        let deadline = Date().addingTimeInterval(30)
        while FileManager.default.fileExists(atPath: checkout.path), !ok.exists, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let removed = !FileManager.default.fileExists(atPath: checkout.path)
        XCTAssertTrue(removed || ok.exists, "The worktree must be removed or a failure alert must be shown")
        XCTContext.runActivity(named: removed ? "Observed: removed" : "Observed: failure alert") { _ in }
        if ok.exists {
            XCTAssertTrue(showsText("Worktree Cleanup Failed"))
            screenshot("36-busy-worktree-failure-alert")
        }
    }

    func testTabCloseButtonAsksOnceAndDeletes() {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-button", newTrackingBranch: "track-wt-button")
        openPane(named: "wt-button")

        let tab = app.buttons["tab-button-VariantTab"].firstMatch
        tab.hover()
        let close = app.descendants(matching: .any).matching(identifier: "tab-close-VariantTab").firstMatch
        waitFor(close)
        close.click()
        let delete = app.windows.buttons["Delete Worktree"].firstMatch
        waitFor(delete, timeout: cleanupWait)
        screenshot("33-tab-close-button-dialog")
        delete.click()
        waitFor(emptyStateHint, timeout: 15)
        waitUntil {
            !FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-button").path)
        }
    }

    func testDeleteThisTabMenuItemAsksOnceAndKeeps() {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-menu", newTrackingBranch: "track-wt-menu")
        openPane(named: "wt-menu")

        app.buttons["tab-button-VariantTab"].firstMatch.rightClick()
        let item = app.menuItems["Delete This Tab"]
        waitFor(item)
        item.click()
        let keep = app.windows.buttons["Keep Worktree"].firstMatch
        waitFor(keep, timeout: cleanupWait)
        keep.click()
        waitFor(emptyStateHint, timeout: 15)
        XCTAssertTrue(FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-menu").path))
        XCTAssertTrue(GitUITestWorkspace.localBranches().contains("track-wt-menu"))
    }

    func testTabWithoutManagedWorktreesClosesWithoutADialog() {
        app.typeKey("k", modifierFlags: .command)
        waitFor(emptyStateHint, timeout: 15)
        XCTAssertFalse(app.windows.buttons["Delete Worktree"].firstMatch.exists)
        XCTAssertFalse(app.windows.buttons["Keep Worktree"].firstMatch.exists)
    }

    func testAlwaysKeepClosesTheTabWithoutADialogAndKeepsTheWorktree() {
        setWorktreeCleanup("Always Keep")
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-keep", newTrackingBranch: "track-wt-keep")
        openPane(named: "wt-keep")

        app.typeKey("k", modifierFlags: .command)
        waitFor(emptyStateHint, timeout: 15)
        XCTAssertFalse(app.windows.buttons["Delete Worktree"].firstMatch.exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-keep").path))
        XCTAssertTrue(GitUITestWorkspace.localBranches().contains("track-wt-keep"))
    }

    func testAlwaysDeleteRemovesCleanWorktreesAndStillAsksAboutUnsavedWork() {
        setWorktreeCleanup("Always Delete")
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-auto", newTrackingBranch: "track-wt-auto")
        makeUnsavedWorktree(folder: "wt-risky")
        openPane(named: "wt-auto")
        openPane(named: "wt-risky")

        app.descendants(matching: .any).matching(identifier: "pane-close-wt-auto").firstMatch.click()
        waitFor(app.staticTexts["pane-name-wt-risky"].firstMatch, timeout: 10)
        XCTAssertFalse(app.windows.buttons["Delete Worktree"].firstMatch.waitForExistence(timeout: 2))
        waitUntil { !FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-auto").path) }

        app.descendants(matching: .any).matching(identifier: "pane-close-wt-risky").firstMatch.click()
        let keep = app.windows.buttons["Keep Worktree"].firstMatch
        waitFor(keep, timeout: cleanupWait)
        XCTAssertTrue(showsText("wt-risky has unsaved work"))
        keep.click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-risky").path))
    }

    func testTabCloseWithThreeWorktreesNamesOnlyTheOnesThatStay() {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-three-clean", newTrackingBranch: "track-three-clean")
        makeUnsavedWorktree(folder: "wt-three-dirty")
        GitUITestWorkspace.addManagedSecondaryWorktree(
            folder: "wt-three-locked", newTrackingBranch: "track-three-locked")
        openPane(named: "wt-three-clean")
        openPane(named: "wt-three-dirty")
        openPane(named: "wt-three-locked")
        GitUITestWorkspace.runGitOrFail(
            ["worktree", "lock", GitUITestWorkspace.worktreeURL(folder: "wt-three-locked").path],
            cwd: GitUITestWorkspace.directoryURL)

        app.typeKey("k", modifierFlags: .command)
        let deleteWorktrees = app.windows.buttons["Delete Worktrees"].firstMatch
        waitFor(deleteWorktrees, timeout: cleanupWait)
        deleteWorktrees.click()

        let deleteAnyway = app.windows.buttons["Delete Anyway"].firstMatch
        waitFor(deleteAnyway, timeout: cleanupWait)
        XCTAssertTrue(showsText("wt-three-dirty has unsaved work"))
        XCTAssertFalse(showsText("wt-three-clean has unsaved work"))
        XCTAssertFalse(showsText("wt-three-locked has unsaved work"))
        screenshot("34-three-worktrees-unsaved-dialog")
        deleteAnyway.click()

        let ok = app.windows.buttons["OK"].firstMatch
        waitFor(ok, timeout: cleanupWait)
        XCTAssertTrue(showsText("Could not delete wt-three-locked"))
        XCTAssertFalse(showsText("wt-three-clean"))
        XCTAssertFalse(showsText("wt-three-dirty"))
        screenshot("35-three-worktrees-partial-failure")
        ok.click()
        waitUntil {
            !FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-three-clean").path)
        }
        waitUntil {
            !FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-three-dirty").path)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: GitUITestWorkspace.worktreeURL(folder: "wt-three-locked").path))
    }

    private func setWorktreeCleanup(_ label: String) {
        openSettingsPanes()
        let option = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        scrollToVisible(option)
        option.click()
        XCTAssertEqual(option.value as? Int, 1)
        app.typeKey("w", modifierFlags: .command)
        waitForDisappear(app.windows["AgentSessionManager Settings"])
    }
}
