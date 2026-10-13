import XCTest

@testable import AgentSessionManager

final class WorktreeCleanupRemoveTests: XCTestCase {
    private var repository: GitTestRepository!

    override func setUpWithError() throws {
        repository = try GitTestRepository.make()
    }

    override func tearDown() {
        repository.cleanUp()
        TracingService.shared.resetForTesting()
        super.tearDown()
    }

    func testRemovesCleanWorktreeAndItsBranch() async throws {
        let checkout = try repository.addManagedWorktree(name: "clean")
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: true)
        XCTAssertEqual(result.outcome, .deleted(branch: .deleted("clean")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertFalse(try repository.isRegistered(checkout))
        XCTAssertFalse(try repository.branches().contains("clean"))
    }

    func testKeepsBranchWhenSettingIsOff() async throws {
        let checkout = try repository.addManagedWorktree(name: "keep-branch")
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: false)
        XCTAssertEqual(result.outcome, .deleted(branch: .notRequested))
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertTrue(try repository.branches().contains("keep-branch"))
    }

    func testRefusesDirtyWorktreeWithoutForce() async throws {
        let checkout = try repository.addManagedWorktree(name: "dirty")
        try Data("u".utf8).write(to: checkout.appending(path: "new.txt"))
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: true)
        guard case .failed(let reason) = result.outcome else {
            XCTFail("expected failure, got \(result.outcome)")
            return
        }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(result.name, "dirty")
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertTrue(try repository.isRegistered(checkout))
        XCTAssertTrue(try repository.branches().contains("dirty"))
    }

    func testFailureIsRecordedInTraces() async throws {
        TracingService.shared.enableTestCapture()
        let checkout = try repository.addManagedWorktree(name: "traced")
        try Data("u".utf8).write(to: checkout.appending(path: "new.txt"))
        _ = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: true)
        let failures = TracingService.shared.recordedEventsForTesting.filter { $0.name == "tab.git.command.failed" }
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures.first?.attributes["args"]?.hasPrefix("worktree remove") ?? false)
    }

    func testForceRemovesDirtyWorktree() async throws {
        let checkout = try repository.addManagedWorktree(name: "forced")
        try Data("u".utf8).write(to: checkout.appending(path: "new.txt"))
        let result = await WorktreeCleanup.remove(
            repository: repository.root, checkout: checkout, force: true, deleteBranch: true)
        XCTAssertTrue(result.isDeleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertFalse(try repository.branches().contains("forced"))
    }

    func testBranchWithUnpushedCommitsKeptWithoutForce() async throws {
        let checkout = try repository.addManagedWorktree(name: "local-work")
        try repository.commit("local", in: checkout)
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: true)
        guard case .deleted(let branch) = result.outcome, case .kept("local-work", _) = branch else {
            XCTFail("expected worktree deleted and branch kept, got \(result.outcome)")
            return
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertTrue(try repository.branches().contains("local-work"))
    }

    func testBranchWithUnpushedCommitsDeletedWithForce() async throws {
        let checkout = try repository.addManagedWorktree(name: "local-forced")
        try repository.commit("local", in: checkout)
        let result = await WorktreeCleanup.remove(
            repository: repository.root, checkout: checkout, force: true, deleteBranch: true)
        XCTAssertEqual(result.outcome, .deleted(branch: .deleted("local-forced")))
        XCTAssertFalse(try repository.branches().contains("local-forced"))
    }

    func testPushedBranchIsDeletedEvenWhenNotMergedIntoHead() async throws {
        let checkout = try repository.addManagedWorktree(name: "pushed-feature")
        try repository.commit("feature", in: checkout)
        try repository.git(["push", "origin", "pushed-feature"], in: checkout)
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: true)
        XCTAssertEqual(result.outcome, .deleted(branch: .deleted("pushed-feature")))
        XCTAssertFalse(try repository.branches().contains("pushed-feature"))
    }

    func testDefaultBranchIsNeverDeleted() async throws {
        try repository.git(["checkout", "-b", "scratch"])
        let checkout = try repository.addManagedWorktree(name: "on-main", branch: "main-copy", from: "main")
        try repository.git(["checkout", "main"], in: checkout)
        try repository.git(["branch", "-D", "main-copy"])
        try repository.git(["checkout", "main"], in: checkout)
        let result = await WorktreeCleanup.remove(
            repository: repository.root, checkout: checkout, force: true, deleteBranch: true)
        guard case .deleted(let branch) = result.outcome, case .kept("main", _) = branch else {
            XCTFail("expected default branch kept, got \(result.outcome)")
            return
        }
        XCTAssertTrue(try repository.branches().contains("main"))
    }

    func testBranchCheckedOutElsewhereReportsReason() async throws {
        let target = try repository.addManagedWorktree(name: "target", branch: "dup-branch")
        try repository.git(["worktree", "add", "--force", Tab.gitWorktreeAddPath(name: "other"), "dup-branch"])
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: target, deleteBranch: true)
        guard case .deleted(let branch) = result.outcome, case .kept("dup-branch", let reason) = branch else {
            XCTFail("expected branch kept, got \(result.outcome)")
            return
        }
        XCTAssertTrue(reason.contains("another worktree"))
        XCTAssertTrue(try repository.branches().contains("dup-branch"))
    }

    func testDetachedWorktreeRemovesWithoutBranchDeletion() async throws {
        let checkout = try repository.addManagedWorktree(name: "detached")
        try repository.git(["checkout", "--detach"], in: checkout)
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: true)
        XCTAssertEqual(result.outcome, .deleted(branch: .notRequested))
        XCTAssertTrue(try repository.branches().contains("detached"))
    }

    func testLockedWorktreeIsNotRemoved() async throws {
        let checkout = try repository.addManagedWorktree(name: "locked")
        try repository.git(["worktree", "lock", checkout.path])
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: true)
        guard case .failed = result.outcome else {
            XCTFail("expected failure, got \(result.outcome)")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testMainCheckoutIsNeverRemoved() async throws {
        let result = await WorktreeCleanup.remove(
            repository: repository.root, checkout: repository.root, force: true, deleteBranch: true)
        guard case .kept = result.outcome else {
            XCTFail("expected kept, got \(result.outcome)")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.root.path))
    }

    func testUnregisteredFolderIsKept() async throws {
        let folder = Tab.worktreeDirectoryURL(repoRoot: repository.root, name: "stray")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result = await WorktreeCleanup.remove(
            repository: repository.root, checkout: folder, force: true, deleteBranch: true)
        guard case .kept = result.outcome else {
            XCTFail("expected kept, got \(result.outcome)")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testMissingFolderPrunesRegistration() async throws {
        let checkout = try repository.addManagedWorktree(name: "gone")
        try FileManager.default.removeItem(at: checkout)
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: true)
        XCTAssertTrue(result.isDeleted)
        XCTAssertFalse(try repository.isRegistered(checkout))
    }

    func testMissingFolderStillDeletesTheBranch() async throws {
        let checkout = try repository.addManagedWorktree(name: "gone-with-branch")
        try FileManager.default.removeItem(at: checkout)
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: true)
        XCTAssertTrue(result.isDeleted)
        XCTAssertFalse(try repository.isRegistered(checkout))
        XCTAssertFalse(try repository.branches().contains("gone-with-branch"))
    }

    func testMissingFolderKeepsTheBranchWhenTheSettingIsOff() async throws {
        let checkout = try repository.addManagedWorktree(name: "gone-keep-branch")
        try FileManager.default.removeItem(at: checkout)
        let result = await WorktreeCleanup.remove(repository: repository.root, checkout: checkout, deleteBranch: false)
        XCTAssertTrue(result.isDeleted)
        XCTAssertTrue(try repository.branches().contains("gone-keep-branch"))
    }
}
