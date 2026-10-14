import XCTest

@testable import AgentSessionManager

@MainActor
final class WorktreeCloseFlowTests: XCTestCase {
    private var repository: GitTestRepository!
    private var state: AppState!
    private var settings: AppSettings!
    private var tab: Tab!
    private var supportSubdirectory: String!

    override func setUpWithError() throws {
        supportSubdirectory = "agent-session-manager-close-flow-\(UUID().uuidString)"
        PersistenceHelpers.overrideAppSupportSubdirectory = supportSubdirectory
        repository = try GitTestRepository.make()
        state = AppState()
        settings = AppSettings()
        tab = Tab(name: "Repo", directory: repository.root)
        state.tabs = [tab]
        state.activeTabID = tab.id
    }

    override func tearDown() {
        repository.cleanUp()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: support.appending(path: supportSubdirectory))
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        super.tearDown()
    }

    private func managedPane(_ name: String) throws -> (Pane, URL) {
        let checkout = try repository.addManagedWorktree(name: name)
        let pane = tab.addPane(
            name: name, harness: .claude, worktreeDirectory: checkout, worktreeIsManaged: true, appSettings: settings)
        return (pane, checkout)
    }

    private func makeDirty(_ checkout: URL) throws {
        try "change".write(to: checkout.appending(path: "dirty.txt"), atomically: true, encoding: .utf8)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line
    )
        async
    {
        let deadline = Date().addingTimeInterval(20)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "condition was not met in time", file: file, line: line)
    }

    private var flow: WorktreeCloseFlow { state.worktreeCloseFlow }

    func testAlwaysKeepClosesPaneWithoutPrompt() throws {
        settings.worktreeCleanupBehavior = .keep
        let (pane, checkout) = try managedPane("keep-me")
        state.requestClose(.pane(pane), appSettings: settings)
        XCTAssertTrue(tab.panes.isEmpty)
        XCTAssertNil(flow.askPrompt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testAskThenDeleteRemovesCleanWorktreeAndBranch() async throws {
        settings.worktreeCleanupBehavior = .ask
        let (pane, checkout) = try managedPane("ask-delete")
        state.requestClose(.pane(pane), appSettings: settings)
        XCTAssertEqual(flow.askPrompt?.title, "Close Worktree Pane")
        XCTAssertEqual(flow.askPrompt?.deleteLabel, "Delete Worktree")
        XCTAssertEqual(tab.panes.count, 1)
        flow.answer(WorktreeAskChoice.delete)
        await waitUntil { tab.panes.isEmpty }
        await flow.waitForCompletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertFalse(try repository.isRegistered(checkout))
        XCTAssertFalse(try repository.branches().contains("ask-delete"))
        XCTAssertNil(flow.notice)
    }

    func testAskThenKeepClosesPaneAndKeepsWorktree() throws {
        settings.worktreeCleanupBehavior = .ask
        let (pane, checkout) = try managedPane("ask-keep")
        state.requestClose(.pane(pane), appSettings: settings)
        flow.answer(WorktreeAskChoice.keep)
        XCTAssertTrue(tab.panes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testAskThenCancelKeepsPaneOpen() throws {
        settings.worktreeCleanupBehavior = .ask
        let (pane, checkout) = try managedPane("ask-cancel")
        state.requestClose(.pane(pane), appSettings: settings)
        flow.answer(WorktreeAskChoice.cancel)
        XCTAssertEqual(tab.panes.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
        state.requestClose(.pane(pane), appSettings: settings)
        XCTAssertNotNil(flow.askPrompt)
    }

    func testUnmanagedPaneClosesWithoutPrompt() throws {
        settings.worktreeCleanupBehavior = .ask
        let pane = tab.addPane(
            name: "plain", harness: .claude, worktreeDirectory: repository.root, worktreeIsManaged: false,
            appSettings: settings)
        state.requestClose(.pane(pane), appSettings: settings)
        XCTAssertTrue(tab.panes.isEmpty)
        XCTAssertNil(flow.askPrompt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.root.path))
    }

    func testAlwaysDeleteWithUnsavedWorkAsksFirst() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (pane, checkout) = try managedPane("dirty-delete")
        try makeDirty(checkout)
        state.requestClose(.pane(pane), appSettings: settings)
        await waitUntil { flow.unsavedPrompt != nil }
        XCTAssertEqual(flow.unsavedPrompt?.keepLabel, "Keep Worktree")
        XCTAssertTrue(flow.unsavedPrompt?.message.contains("1 untracked file") == true)
        XCTAssertEqual(tab.panes.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testUnsavedKeepClosesPaneAndKeepsWorktree() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (pane, checkout) = try managedPane("dirty-keep")
        try makeDirty(checkout)
        state.requestClose(.pane(pane), appSettings: settings)
        await waitUntil { flow.unsavedPrompt != nil }
        flow.answer(WorktreeUnsavedChoice.keep)
        await waitUntil { tab.panes.isEmpty }
        await flow.waitForCompletion()
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertTrue(try repository.branches().contains("dirty-keep"))
        XCTAssertNil(flow.notice)
    }

    func testUnsavedDeleteAnywayRemovesWorktree() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (pane, checkout) = try managedPane("dirty-force")
        try makeDirty(checkout)
        state.requestClose(.pane(pane), appSettings: settings)
        await waitUntil { flow.unsavedPrompt != nil }
        flow.answer(WorktreeUnsavedChoice.deleteAnyway)
        await waitUntil { tab.panes.isEmpty }
        await flow.waitForCompletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertNil(flow.notice)
    }

    func testUnsavedCancelKeepsPaneOpen() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (pane, checkout) = try managedPane("dirty-cancel")
        try makeDirty(checkout)
        state.requestClose(.pane(pane), appSettings: settings)
        await waitUntil { flow.unsavedPrompt != nil }
        flow.answer(WorktreeUnsavedChoice.cancel)
        XCTAssertEqual(tab.panes.count, 1)
        XCTAssertNil(flow.unsavedPrompt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testUnpushedCommitsAreListedWithBranchWarning() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (pane, checkout) = try managedPane("unpushed")
        try repository.commit("local only", in: checkout)
        state.requestClose(.pane(pane), appSettings: settings)
        await waitUntil { flow.unsavedPrompt != nil }
        let message = flow.unsavedPrompt?.message ?? ""
        XCTAssertTrue(message.contains("1 commit not on any remote on unpushed"))
        XCTAssertTrue(message.contains("Its branch \"unpushed\" is deleted too."))
        flow.answer(WorktreeUnsavedChoice.cancel)
    }

    func testSharedCheckoutIsKeptWithReason() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (pane, checkout) = try managedPane("shared")
        _ = tab.addPane(
            name: "shell:shared", harness: .shell, worktreeDirectory: checkout, worktreeIsManaged: false,
            appSettings: settings)
        state.requestClose(.pane(pane), appSettings: settings)
        await waitUntil { flow.notice != nil }
        XCTAssertEqual(flow.notice?.title, "Worktree Kept")
        XCTAssertEqual(flow.notice?.message, "Kept shared: Another pane is still using it.")
        XCTAssertEqual(tab.panes.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testRefusedRemovalReportsFailureWithReason() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (pane, checkout) = try managedPane("locked")
        _ = try repository.git(["worktree", "lock", checkout.path])
        state.requestClose(.pane(pane), appSettings: settings)
        await waitUntil { flow.notice != nil }
        XCTAssertEqual(flow.notice?.title, "Worktree Cleanup Failed")
        XCTAssertTrue(flow.notice?.message.hasPrefix("Could not delete locked: ") == true)
        XCTAssertTrue(tab.panes.isEmpty)
        XCTAssertTrue(try repository.isRegistered(checkout))
        flow.dismissNotice()
        XCTAssertNil(flow.notice)
    }

    func testALaterNoticeIsAddedToTheOneStillShowing() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (first, firstCheckout) = try managedPane("locked-first")
        let (second, secondCheckout) = try managedPane("locked-second")
        _ = try repository.git(["worktree", "lock", firstCheckout.path])
        _ = try repository.git(["worktree", "lock", secondCheckout.path])
        state.requestClose(.pane(first), appSettings: settings)
        await waitUntil { flow.notice != nil }
        await flow.waitForCompletion()
        state.requestClose(.pane(second), appSettings: settings)
        await waitUntil { flow.notice?.message.contains("locked-second") == true }
        XCTAssertEqual(flow.notice?.title, "Worktree Cleanup Failed")
        XCTAssertTrue(flow.notice?.message.contains("locked-first") == true)
    }

    func testNoticePostingKeepsFailureTitleAndIgnoresEmptyLines() {
        let failure = WorktreeCleanupNotice(title: WorktreeCleanupNotice.failedTitle, message: "Could not delete a: x")
        let combined = WorktreeCleanupNotice.posting(lines: ["Kept b: y"], failed: false, over: failure)
        XCTAssertEqual(combined?.title, WorktreeCleanupNotice.failedTitle)
        XCTAssertEqual(combined?.message, "Could not delete a: x\nKept b: y")
        XCTAssertEqual(WorktreeCleanupNotice.posting(lines: [], failed: false, over: failure), failure)
        XCTAssertNil(WorktreeCleanupNotice.posting(lines: [], failed: true, over: nil))
        XCTAssertEqual(
            WorktreeCleanupNotice.posting(lines: ["Kept c: z"], failed: false, over: nil)?.title,
            WorktreeCleanupNotice.keptTitle)
    }

    func testMissingFolderClosesWithoutNotice() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (pane, checkout) = try managedPane("gone")
        try FileManager.default.removeItem(at: checkout)
        state.requestClose(.pane(pane), appSettings: settings)
        await waitUntil { tab.panes.isEmpty }
        await flow.waitForCompletion()
        XCTAssertNil(flow.notice)
        XCTAssertFalse(try repository.isRegistered(checkout))
    }

    func testPullRequestKeepDecisionNeverDeletes() throws {
        settings.worktreeCleanupBehavior = .delete
        let (pane, checkout) = try managedPane("pr-keep")
        state.requestClose(.pane(pane), decision: .keep, appSettings: settings)
        XCTAssertTrue(tab.panes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testPullRequestDeleteDecisionSkipsTheAskDialog() async throws {
        settings.worktreeCleanupBehavior = .keep
        let (pane, checkout) = try managedPane("pr-delete")
        state.requestClose(.pane(pane), decision: .delete, appSettings: settings)
        XCTAssertNil(flow.askPrompt)
        await waitUntil { tab.panes.isEmpty }
        await flow.waitForCompletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testBranchIsKeptWhenSettingIsOff() async throws {
        settings.worktreeCleanupBehavior = .delete
        settings.deleteBranchWithWorktree = false
        let (pane, checkout) = try managedPane("keep-branch")
        state.requestClose(.pane(pane), appSettings: settings)
        await waitUntil { tab.panes.isEmpty }
        await flow.waitForCompletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertTrue(try repository.branches().contains("keep-branch"))
    }

    func testTabCloseAsksOnceForAllWorktrees() async throws {
        settings.worktreeCleanupBehavior = .ask
        let worktrees = try ["one", "two", "three"].map { try managedPane($0) }
        state.requestClose(.tab(tab), appSettings: settings)
        let prompt = flow.askPrompt
        XCTAssertEqual(prompt?.deleteLabel, "Delete Worktrees")
        XCTAssertEqual(prompt?.keepLabel, "Keep Worktrees")
        for name in ["one", "two", "three"] {
            XCTAssertTrue(prompt?.message.contains("\"\(name)\"") == true)
        }
        XCTAssertEqual(state.tabs.count, 1)
        flow.answer(WorktreeAskChoice.delete)
        await waitUntil { state.tabs.isEmpty }
        await flow.waitForCompletion()
        for (_, checkout) in worktrees {
            XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        }
        XCTAssertNil(flow.notice)
    }

    func testTabCloseCancelLeavesEverythingUnchanged() throws {
        settings.worktreeCleanupBehavior = .ask
        let (_, checkout) = try managedPane("stay")
        state.requestClose(.tab(tab), appSettings: settings)
        flow.answer(WorktreeAskChoice.cancel)
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(tab.panes.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testTabWithoutManagedWorktreesClosesWithoutDialog() {
        settings.worktreeCleanupBehavior = .ask
        _ = tab.addPane(name: "plain", harness: .claude, appSettings: settings)
        state.requestClose(.tab(tab), appSettings: settings)
        XCTAssertNil(flow.askPrompt)
        XCTAssertTrue(state.tabs.isEmpty)
    }

    func testTabCloseAlwaysKeepNeverAsks() throws {
        settings.worktreeCleanupBehavior = .keep
        let (_, checkout) = try managedPane("always-keep")
        state.requestClose(.tab(tab), appSettings: settings)
        XCTAssertNil(flow.askPrompt)
        XCTAssertTrue(state.tabs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testTabCloseAlwaysDeleteRemovesCleanWorktreesWithoutAsking() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (_, checkout) = try managedPane("always-delete")
        state.requestClose(.tab(tab), appSettings: settings)
        XCTAssertNil(flow.askPrompt)
        await waitUntil { state.tabs.isEmpty }
        await flow.waitForCompletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testTabCloseWithOneDirtyWorktreeNamesOnlyThatOneAndRemovesTheRest() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (_, cleanA) = try managedPane("clean-a")
        let (_, dirty) = try managedPane("dirty-b")
        let (_, cleanC) = try managedPane("clean-c")
        try makeDirty(dirty)
        state.requestClose(.tab(tab), appSettings: settings)
        await waitUntil { flow.unsavedPrompt != nil }
        let message = flow.unsavedPrompt?.message ?? ""
        XCTAssertTrue(message.contains("dirty-b"))
        XCTAssertFalse(message.contains("clean-a"))
        XCTAssertFalse(message.contains("clean-c"))
        flow.answer(WorktreeUnsavedChoice.keep)
        await waitUntil { state.tabs.isEmpty }
        await flow.waitForCompletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanC.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirty.path))
    }

    func testTabCloseWithOneFailureNamesOnlyTheFailedWorktree() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (_, cleanA) = try managedPane("ok-a")
        let (_, locked) = try managedPane("locked-b")
        _ = try repository.git(["worktree", "lock", locked.path])
        state.requestClose(.tab(tab), appSettings: settings)
        await waitUntil { flow.notice != nil }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: locked.path))
        let message = flow.notice?.message ?? ""
        XCTAssertTrue(message.contains("locked-b"))
        XCTAssertFalse(message.contains("ok-a"))
    }

    func testTabCloseTreatsShellPanesInTheSameTabAsClosing() async throws {
        settings.worktreeCleanupBehavior = .delete
        let (_, checkout) = try managedPane("with-shell")
        _ = tab.addPane(
            name: "shell:with-shell", harness: .shell, worktreeDirectory: checkout, worktreeIsManaged: false,
            appSettings: settings)
        state.requestClose(.tab(tab), appSettings: settings)
        await waitUntil { state.tabs.isEmpty }
        await flow.waitForCompletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertNil(flow.notice)
    }

    func testSecondRequestIsIgnoredWhileADialogIsOpen() throws {
        settings.worktreeCleanupBehavior = .ask
        let (first, _) = try managedPane("first")
        let (second, _) = try managedPane("second")
        state.requestClose(.pane(first), appSettings: settings)
        state.requestClose(.pane(second), appSettings: settings)
        XCTAssertTrue(flow.askPrompt?.message.contains("first") == true)
        flow.answer(WorktreeAskChoice.cancel)
    }

    func testExcludingSeveralPanesFromTheInUseCheck() throws {
        let (pane, checkout) = try managedPane("multi")
        let shell = tab.addPane(
            name: "shell:multi", harness: .shell, worktreeDirectory: checkout, worktreeIsManaged: false,
            appSettings: settings)
        XCTAssertTrue(
            state.isCheckoutInUse(checkout: checkout, excludingPaneIDs: [pane.id]))
        XCTAssertFalse(
            state.isCheckoutInUse(checkout: checkout, excludingPaneIDs: [pane.id, shell.id]))
    }
}
