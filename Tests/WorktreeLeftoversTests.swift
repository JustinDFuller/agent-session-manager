import XCTest

@testable import AgentSessionManager

@MainActor
final class WorktreeLeftoversTests: XCTestCase {
    private let subdirectory = "worktree-leftovers-tests-\(UUID().uuidString)"
    private var repository: GitTestRepository!
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    override func setUpWithError() throws {
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        repository = try GitTestRepository.make()
    }

    override func tearDown() {
        repository.cleanUp()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: support.appending(path: subdirectory))
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        TracingService.shared.resetForTesting()
        super.tearDown()
    }

    private func age(_ checkout: URL, by interval: TimeInterval) throws {
        let pointer = try String(contentsOf: checkout.appending(path: ".git"), encoding: .utf8)
        let admin = URL(
            filePath: pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines),
            directoryHint: .isDirectory)
        for name in ["HEAD", "index"] {
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-interval)], ofItemAtPath: admin.appending(path: name).path)
        }
    }

    private func oldWorktree(_ name: String) throws -> URL {
        let checkout = try repository.addManagedWorktree(name: name)
        try age(checkout, by: 3 * 24 * 3600)
        return checkout
    }

    private func sweep(
        deleteBranch: Bool = true, open: Set<String> = []
    ) async -> [WorktreeSweepOutcome] {
        await WorktreeLeftovers.sweep(
            repositories: [repository.root], openCheckouts: open, deleteBranch: deleteBranch, now: now)
    }

    private func reason(for checkout: URL, in outcomes: [WorktreeSweepOutcome]) -> String? {
        outcomes.first { $0.leftover.checkout.resolvingSymlinksInPath() == checkout.resolvingSymlinksInPath() }?
            .leftover.keptReason
    }

    func testOldCleanPushedWorktreeIsRemovedWithItsBranch() async throws {
        let checkout = try oldWorktree("old-clean")
        let outcomes = await sweep()
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes.first?.result?.isDeleted, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertFalse(try repository.branches().contains("old-clean"))
    }

    func testBranchStaysWhenTheSettingIsOff() async throws {
        let checkout = try oldWorktree("keep-branch")
        _ = await sweep(deleteBranch: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertTrue(try repository.branches().contains("keep-branch"))
    }

    func testAgeBoundaryIsTwentyFourHours() async throws {
        let justInside = try repository.addManagedWorktree(name: "inside")
        let justOutside = try repository.addManagedWorktree(name: "outside")
        try age(justInside, by: WorktreeLeftovers.minimumAge - 60)
        try age(justOutside, by: WorktreeLeftovers.minimumAge + 60)
        let outcomes = await sweep()
        XCTAssertEqual(reason(for: justInside, in: outcomes), "It changed within the last 24 hours.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: justInside.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: justOutside.path))
    }

    func testModifiedAndUntrackedWorktreesAreKept() async throws {
        let modified = try oldWorktree("modified")
        try "edit".write(to: modified.appending(path: "file-edit.txt"), atomically: true, encoding: .utf8)
        try repository.git(["add", "file-edit.txt"], in: modified)
        let untracked = try oldWorktree("untracked")
        try "new".write(to: untracked.appending(path: "new.txt"), atomically: true, encoding: .utf8)
        let outcomes = await sweep()
        XCTAssertEqual(reason(for: modified, in: outcomes), "It has unsaved work: 1 modified file.")
        XCTAssertEqual(reason(for: untracked, in: outcomes), "It has unsaved work: 1 untracked file.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: modified.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: untracked.path))
    }

    func testUnpushedCommitsKeepTheWorktree() async throws {
        let checkout = try repository.addManagedWorktree(name: "unpushed")
        try repository.commit("local", in: checkout)
        try age(checkout, by: 3 * 24 * 3600)
        let outcomes = await sweep()
        XCTAssertEqual(
            reason(for: checkout, in: outcomes), "It has unsaved work: 1 commit not on any remote on unpushed.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testDetachedHeadWithLocalCommitsIsKept() async throws {
        let path = Tab.gitWorktreeAddPath(name: "detached")
        try repository.git(["worktree", "add", "--detach", path, "main"])
        let checkout = Tab.worktreeDirectoryURL(repoRoot: repository.root, name: "detached")
            .resolvingSymlinksInPath()
        try repository.commit("detached local", in: checkout)
        try age(checkout, by: 3 * 24 * 3600)
        let outcomes = await sweep()
        XCTAssertEqual(
            reason(for: checkout, in: outcomes),
            "It has unsaved work: 1 commit not on any remote on a detached HEAD.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testLockedWorktreeIsKept() async throws {
        let checkout = try oldWorktree("locked")
        try repository.git(["worktree", "lock", checkout.path])
        let outcomes = await sweep()
        XCTAssertEqual(reason(for: checkout, in: outcomes), "It is locked in git.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testWorktreeAnOpenPaneUsesIsNotListedOrRemoved() async throws {
        let checkout = try oldWorktree("in-use")
        let outcomes = await sweep(open: [checkout.resolvingSymlinksInPath().path])
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testRepositoryWithoutAnyTabIsSwept() async throws {
        let checkout = try oldWorktree("no-tab")
        let outcomes = await WorktreeLeftovers.sweep(
            repositories: [repository.root], openCheckouts: [], deleteBranch: true, now: now)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testStaleRegistrationIsPruned() async throws {
        let checkout = try oldWorktree("stale")
        try FileManager.default.removeItem(at: checkout)
        XCTAssertTrue(try repository.git(["worktree", "list", "--porcelain"]).contains("prunable"))
        _ = await sweep()
        XCTAssertFalse(try repository.isRegistered(checkout))
    }

    func testUnregisteredFolderIsListedButNeverDeleted() async throws {
        let folder = repository.root.appending(path: ".agent-session-manager/worktrees/milestone-x")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outcomes = await sweep()
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes.first?.leftover.isRegistered, false)
        XCTAssertEqual(outcomes.first?.leftover.keptReason, WorktreeLeftovers.unregisteredReason)
        XCTAssertNil(outcomes.first?.result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testWorktreeOutsideManagedFoldersIsNeverTouched() async throws {
        let outside = repository.root.deletingLastPathComponent().appending(path: "agent-made")
        try repository.git(["worktree", "add", outside.path, "-b", "agent-made", "main"])
        let outcomes = await sweep()
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(try repository.branches().contains("agent-made"))
    }

    func testLegacyTreeFolderIsSwept() async throws {
        let checkout = repository.root.appending(path: ".tree/legacy").resolvingSymlinksInPath()
        try repository.git(["worktree", "add", ".tree/legacy", "-b", "legacy", "main"])
        try age(checkout, by: 3 * 24 * 3600)
        _ = await sweep()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testMissingRepositoryFolderIsSkipped() async {
        let missing = FileManager.default.temporaryDirectory.appending(path: "gone-\(UUID().uuidString)")
        let outcomes = await WorktreeLeftovers.sweep(
            repositories: [missing], openCheckouts: [], deleteBranch: true, now: now)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testScanReportsWithoutDeleting() async throws {
        let eligible = try oldWorktree("scan-eligible")
        let recent = try repository.addManagedWorktree(name: "scan-recent")
        try age(recent, by: 60)
        let leftovers = await WorktreeLeftovers.scan(
            repositories: [repository.root], openCheckouts: [], now: now)
        XCTAssertEqual(leftovers.map(\.name), ["scan-eligible", "scan-recent"])
        XCTAssertEqual(leftovers.map(\.isEligible), [true, false])
        XCTAssertTrue(FileManager.default.fileExists(atPath: eligible.path))
    }

    func testEveryDecisionIsTraced() async throws {
        TracingService.shared.enableTestCapture()
        let removed = try oldWorktree("traced-removed")
        let kept = try repository.addManagedWorktree(name: "traced-kept")
        try age(kept, by: 60)
        _ = await sweep()
        let events = TracingService.shared.recordedEventsForTesting
        let removal = events.first { $0.name == "worktree.leftover.removed" }
        XCTAssertEqual(removal?.attributes["checkout"], removed.path)
        let skip = events.first { $0.name == "worktree.leftover.skipped" }
        XCTAssertEqual(skip?.attributes["checkout"], kept.path)
        XCTAssertEqual(skip?.attributes["reason"], "It changed within the last 24 hours.")
    }

    func testLaunchCleanupSweepsKnownRepositoriesAndSparesOpenPanes() async throws {
        let settings = AppSettings()
        let state = AppState()
        let tab = Tab(name: "Repo", directory: repository.root)
        state.tabs = [tab]
        let removed = try repository.addManagedWorktree(name: "launch-old")
        let open = try repository.addManagedWorktree(name: "launch-open")
        let realNow = Date()
        for checkout in [removed, open] {
            let pointer = try String(contentsOf: checkout.appending(path: ".git"), encoding: .utf8)
            let admin = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            for name in ["HEAD", "index"] {
                try FileManager.default.setAttributes(
                    [.modificationDate: realNow.addingTimeInterval(-3 * 24 * 3600)],
                    ofItemAtPath: "\(admin)/\(name)")
            }
        }
        _ = tab.addPane(
            name: "launch-open", harness: .claude, worktreeDirectory: open, worktreeIsManaged: true,
            appSettings: settings)
        let task = try XCTUnwrap(LaunchCleanup.start(appState: state, appSettings: settings))
        _ = await task.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: removed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: open.path))
        XCTAssertEqual(KnownRepositories.load().map(\.path), [repository.root.path])
    }

    func testLaunchCleanupDoesNothingWhenTheSettingIsOff() async throws {
        let settings = AppSettings()
        settings.cleanUpLeftoversAtLaunch = false
        let state = AppState()
        state.tabs = [Tab(name: "Repo", directory: repository.root)]
        let checkout = try oldWorktree("setting-off")
        XCTAssertNil(LaunchCleanup.start(appState: state, appSettings: settings))
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }
}
