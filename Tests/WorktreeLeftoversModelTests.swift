import XCTest

@testable import AgentSessionManager

@MainActor
final class WorktreeLeftoversModelTests: XCTestCase {
    private let subdirectory = "worktree-leftovers-model-tests-\(UUID().uuidString)"
    private var repository: GitTestRepository!
    private var state: AppState!
    private var settings: AppSettings!
    private var model: WorktreeLeftoversModel!

    override func setUpWithError() throws {
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        repository = try GitTestRepository.make()
        state = AppState()
        settings = AppSettings()
        state.tabs = [Tab(name: "Repo", directory: repository.root)]
        model = WorktreeLeftoversModel()
    }

    override func tearDown() {
        repository.cleanUp()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: support.appending(path: subdirectory))
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        super.tearDown()
    }

    private func unregisteredFolder(_ name: String) throws -> URL {
        let folder = Tab.worktreeDirectoryURL(repoRoot: repository.root, name: name).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "state".write(
            to: folder.appending(path: "UserInterfaceState.xcuserstate"), atomically: true, encoding: .utf8)
        return folder
    }

    private func scan() async {
        await model.scan(appState: state, appSettings: settings)
    }

    private func select(_ checkout: URL) throws {
        let match = model.leftovers.first {
            $0.checkout.resolvingSymlinksInPath() == checkout.resolvingSymlinksInPath()
        }
        model.selection = [try XCTUnwrap(match).id]
    }

    func testScanListsRegisteredAndUnregisteredLeftovers() async throws {
        let registered = try repository.addManagedWorktree(name: "listed")
        let folder = try unregisteredFolder("milestone-1")
        await scan()
        XCTAssertTrue(model.hasScanned)
        XCTAssertEqual(
            Set(model.leftovers.map { $0.checkout.resolvingSymlinksInPath().path }),
            [registered.resolvingSymlinksInPath().path, folder.resolvingSymlinksInPath().path])
        XCTAssertEqual(model.leftovers.first { $0.name == "milestone-1" }?.isRegistered, false)
        XCTAssertEqual(
            model.leftovers.first { $0.name == "milestone-1" }?.keptReason, WorktreeLeftovers.unregisteredReason)
    }

    func testScanWithoutLeftoversIsEmpty() async {
        await scan()
        XCTAssertTrue(model.hasScanned)
        XCTAssertTrue(model.leftovers.isEmpty)
    }

    func testScanLeavesOutWorktreesAPaneUses() async throws {
        let checkout = try repository.addManagedWorktree(name: "in-use")
        state.tabs[0].addPane(
            name: "in-use", harness: .claude, worktreeDirectory: checkout, worktreeIsManaged: true,
            appSettings: settings)
        await scan()
        XCTAssertFalse(model.leftovers.contains { $0.name == "in-use" })
    }

    func testScanDropsSelectionsThatNoLongerExist() async throws {
        let checkout = try repository.addManagedWorktree(name: "gone-soon")
        await scan()
        try select(checkout)
        _ = try repository.git(["worktree", "remove", "--force", checkout.path])
        await scan()
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testReasonExplainsWhySafeEntriesAreStillListed() throws {
        let safe = WorktreeLeftover(
            repository: repository.root, checkout: repository.root.appending(path: "safe"), isRegistered: true,
            keptReason: nil)
        let kept = WorktreeLeftover(
            repository: repository.root, checkout: repository.root.appending(path: "kept"), isRegistered: true,
            keptReason: "It is locked in git.")
        XCTAssertEqual(
            model.reason(for: safe, launchCleanupEnabled: true),
            "It is safe to delete and will be removed at the next launch.")
        XCTAssertEqual(model.reason(for: safe, launchCleanupEnabled: false), "Clean Up Leftovers at Launch is off.")
        XCTAssertEqual(model.reason(for: kept, launchCleanupEnabled: true), "It is locked in git.")
    }

    func testSizeLoadsAfterTheScan() async throws {
        let checkout = try repository.addManagedWorktree(name: "sized")
        try String(repeating: "x", count: 200_000).write(
            to: checkout.appending(path: "big.txt"), atomically: true, encoding: .utf8)
        await scan()
        let leftover = try XCTUnwrap(model.leftovers.first)
        XCTAssertNil(model.sizes[leftover.id])
        await model.loadSize(of: leftover)
        XCTAssertGreaterThan(try XCTUnwrap(model.sizes[leftover.id]), 200_000)
    }

    func testSizeOfMissingFolderIsZero() {
        XCTAssertEqual(WorktreeLeftovers.size(of: repository.root.appending(path: "missing")), 0)
    }

    func testDeletingCleanEntryRemovesWorktreeAndBranch() async throws {
        let checkout = try repository.addManagedWorktree(name: "clean-entry")
        await scan()
        try select(checkout)
        model.requestDelete(appState: state, appSettings: settings)
        await model.waitForDeletion()
        XCTAssertNil(model.unsavedPrompt)
        XCTAssertNil(model.notice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertFalse(try repository.branches().contains("clean-entry"))
        XCTAssertTrue(model.leftovers.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testDeletingDirtyEntryAsksAndKeepLeavesIt() async throws {
        let checkout = try repository.addManagedWorktree(name: "dirty-keep")
        try "change".write(to: checkout.appending(path: "dirty.txt"), atomically: true, encoding: .utf8)
        await scan()
        try select(checkout)
        model.requestDelete(appState: state, appSettings: settings)
        await waitForPrompt { self.model.unsavedPrompt != nil }
        XCTAssertEqual(model.unsavedPrompt?.title, "Worktree Has Unsaved Work")
        XCTAssertEqual(model.unsavedPrompt?.keepLabel, "Keep Worktree")
        XCTAssertTrue(model.unsavedPrompt?.message.contains("1 untracked file") == true)
        model.answer(.keep)
        await model.waitForDeletion()
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertTrue(try repository.branches().contains("dirty-keep"))
    }

    func testDeleteAnywayRemovesDirtyEntry() async throws {
        let checkout = try repository.addManagedWorktree(name: "dirty-force")
        try "change".write(to: checkout.appending(path: "dirty.txt"), atomically: true, encoding: .utf8)
        await scan()
        try select(checkout)
        model.requestDelete(appState: state, appSettings: settings)
        await waitForPrompt { self.model.unsavedPrompt != nil }
        model.answer(.deleteAnyway)
        await model.waitForDeletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertFalse(try repository.branches().contains("dirty-force"))
    }

    func testCancelOnUnsavedPromptDeletesNothing() async throws {
        let clean = try repository.addManagedWorktree(name: "clean-cancel")
        let dirty = try repository.addManagedWorktree(name: "dirty-cancel")
        try "change".write(to: dirty.appending(path: "dirty.txt"), atomically: true, encoding: .utf8)
        await scan()
        model.selection = Set(model.leftovers.map(\.id))
        model.requestDelete(appState: state, appSettings: settings)
        await waitForPrompt { self.model.unsavedPrompt != nil }
        model.answer(.cancel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clean.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirty.path))
    }

    func testKeepStillDeletesTheCleanEntriesInTheSelection() async throws {
        let clean = try repository.addManagedWorktree(name: "clean-mixed")
        let dirty = try repository.addManagedWorktree(name: "dirty-mixed")
        try "change".write(to: dirty.appending(path: "dirty.txt"), atomically: true, encoding: .utf8)
        await scan()
        model.selection = Set(model.leftovers.map(\.id))
        model.requestDelete(appState: state, appSettings: settings)
        await waitForPrompt { self.model.unsavedPrompt != nil }
        XCTAssertFalse(model.unsavedPrompt?.message.contains("clean-mixed") == true)
        model.answer(.keep)
        await model.waitForDeletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: clean.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirty.path))
    }

    func testBranchStaysWhenTheSettingIsOff() async throws {
        settings.deleteBranchWithWorktree = false
        let checkout = try repository.addManagedWorktree(name: "branch-stays")
        await scan()
        try select(checkout)
        model.requestDelete(appState: state, appSettings: settings)
        await model.waitForDeletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertTrue(try repository.branches().contains("branch-stays"))
    }

    func testUnregisteredFolderIsRemovedOnlyAfterConfirmation() async throws {
        let folder = try unregisteredFolder("milestone-confirm")
        await scan()
        try select(folder)
        model.requestDelete(appState: state, appSettings: settings)
        await waitForPrompt { self.model.folderPrompt != nil }
        XCTAssertEqual(model.folderPrompt?.title, "Delete Folder?")
        XCTAssertEqual(model.folderPrompt?.deleteLabel, "Delete Folder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        model.confirmFolders(true)
        await model.waitForDeletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(model.leftovers.isEmpty)
    }

    func testCancellingTheFolderPromptKeepsEverything() async throws {
        let folder = try unregisteredFolder("milestone-cancel")
        let checkout = try repository.addManagedWorktree(name: "alongside")
        await scan()
        model.selection = Set(model.leftovers.map(\.id))
        model.requestDelete(appState: state, appSettings: settings)
        await waitForPrompt { self.model.folderPrompt != nil }
        model.confirmFolders(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testEntryAPaneStartedUsingIsKeptWithReason() async throws {
        let checkout = try repository.addManagedWorktree(name: "late-use")
        await scan()
        try select(checkout)
        state.tabs[0].addPane(
            name: "late-use", harness: .claude, worktreeDirectory: checkout, worktreeIsManaged: true,
            appSettings: settings)
        model.requestDelete(appState: state, appSettings: settings)
        await model.waitForDeletion()
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertEqual(model.notice?.title, "Worktree Kept")
        XCTAssertEqual(model.notice?.message, "Kept late-use: Another pane is still using it.")
        model.dismissNotice()
        XCTAssertNil(model.notice)
    }

    func testRequestWithoutSelectionDoesNothing() async throws {
        _ = try repository.addManagedWorktree(name: "unselected")
        await scan()
        model.requestDelete(appState: state, appSettings: settings)
        XCTAssertNil(model.unsavedPrompt)
        XCTAssertNil(model.folderPrompt)
    }

    func testRemoveUnregisteredRefusesARegisteredWorktree() async throws {
        let checkout = try repository.addManagedWorktree(name: "registered")
        let leftover = WorktreeLeftover(
            repository: repository.root, checkout: checkout, isRegistered: false, keptReason: nil)
        let result = await WorktreeLeftovers.removeUnregistered(leftover)
        XCTAssertEqual(result.outcome, .kept(reason: "Git lists it as a worktree."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testRemoveUnregisteredRefusesFoldersOutsideTheManagedFolders() async throws {
        let outside = repository.root.appending(path: "Sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let leftover = WorktreeLeftover(
            repository: repository.root, checkout: outside, isRegistered: false, keptReason: nil)
        let result = await WorktreeLeftovers.removeUnregistered(leftover)
        XCTAssertEqual(result.outcome, .kept(reason: "It is not directly inside a managed worktrees folder."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testRemoveUnregisteredRefusesNestedFolders() async throws {
        let folder = try unregisteredFolder("milestone-parent")
        let nested = folder.appending(path: "nested", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let leftover = WorktreeLeftover(
            repository: repository.root, checkout: nested, isRegistered: false, keptReason: nil)
        let result = await WorktreeLeftovers.removeUnregistered(leftover)
        XCTAssertFalse(result.isDeleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testRemoveUnregisteredTreatsAMissingFolderAsDeleted() async throws {
        let folder = try unregisteredFolder("milestone-missing")
        try FileManager.default.removeItem(at: folder)
        let leftover = WorktreeLeftover(
            repository: repository.root, checkout: folder, isRegistered: false, keptReason: nil)
        let result = await WorktreeLeftovers.removeUnregistered(leftover)
        XCTAssertTrue(result.isDeleted)
    }

    private func waitForPrompt(_ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(20)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "prompt did not appear in time")
    }
}
