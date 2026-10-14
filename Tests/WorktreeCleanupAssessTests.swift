import XCTest

@testable import AgentSessionManager

final class WorktreeCleanupAssessTests: XCTestCase {
    private var repository: GitTestRepository!

    override func setUpWithError() throws {
        repository = try GitTestRepository.make()
    }

    override func tearDown() {
        repository.cleanUp()
        super.tearDown()
    }

    func testCleanPushedWorktreeHasNoUnsavedWork() async throws {
        let checkout = try repository.addManagedWorktree(name: "clean")
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertEqual(assessment.branch, "clean")
        XCTAssertEqual(assessment.modifiedCount, 0)
        XCTAssertEqual(assessment.untrackedCount, 0)
        XCTAssertEqual(assessment.unpushedCommitCount, 0)
        XCTAssertFalse(assessment.hasUnsavedWork)
        XCTAssertTrue(assessment.unsavedWorkLines.isEmpty)
        XCTAssertFalse(assessment.isLocked)
        XCTAssertFalse(assessment.isUsedByOtherPane)
    }

    func testModifiedFilesAreCounted() async throws {
        let checkout = try repository.addManagedWorktree(name: "modified")
        let tracked = checkout.appending(path: "tracked.txt")
        try Data("a".utf8).write(to: tracked)
        try repository.git(["add", "tracked.txt"], in: checkout)
        try repository.git(["commit", "-m", "tracked"], in: checkout)
        try repository.git(["push", "origin", "modified"], in: checkout)
        try Data("b".utf8).write(to: tracked)
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertEqual(assessment.modifiedCount, 1)
        XCTAssertEqual(assessment.untrackedCount, 0)
        XCTAssertEqual(assessment.unpushedCommitCount, 0)
        XCTAssertTrue(assessment.hasUnsavedWork)
        XCTAssertEqual(assessment.unsavedWorkLines, ["1 modified file"])
    }

    func testManyModifiedAndUntrackedFilesAreCounted() async throws {
        let checkout = try repository.addManagedWorktree(name: "many")
        for index in 0..<25 {
            try Data("x".utf8).write(to: checkout.appending(path: "m\(index).txt"))
        }
        try repository.git(["add", "-A"], in: checkout)
        try repository.git(["commit", "-m", "files"], in: checkout)
        try repository.git(["push", "origin", "many"], in: checkout)
        for index in 0..<25 {
            try Data("y".utf8).write(to: checkout.appending(path: "m\(index).txt"))
        }
        for index in 0..<3 {
            try Data("z".utf8).write(to: checkout.appending(path: "u\(index).txt"))
        }
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertEqual(assessment.modifiedCount, 25)
        XCTAssertEqual(assessment.untrackedCount, 3)
        XCTAssertEqual(assessment.unsavedWorkLines, ["25 modified files", "3 untracked files"])
    }

    func testUntrackedFileIsCounted() async throws {
        let checkout = try repository.addManagedWorktree(name: "untracked")
        try Data("u".utf8).write(to: checkout.appending(path: "new.txt"))
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertEqual(assessment.modifiedCount, 0)
        XCTAssertEqual(assessment.untrackedCount, 1)
        XCTAssertTrue(assessment.hasUnsavedWork)
    }

    func testUntrackedFilesInsideNewFolderAreCountedIndividually() async throws {
        let checkout = try repository.addManagedWorktree(name: "folder")
        let folder = checkout.appending(path: "dir", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("1".utf8).write(to: folder.appending(path: "a.txt"))
        try Data("2".utf8).write(to: folder.appending(path: "b.txt"))
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertEqual(assessment.untrackedCount, 2)
    }

    func testIgnoredOnlyChangesAreNotUnsavedWork() async throws {
        try Data(".build/\n".utf8).write(to: repository.root.appending(path: ".gitignore"))
        try repository.git(["add", ".gitignore"])
        try repository.git(["commit", "-m", "ignore"])
        try repository.git(["push", "origin", "main"])
        let checkout = try repository.addManagedWorktree(name: "ignored")
        let build = checkout.appending(path: ".build", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data("artifact".utf8).write(to: build.appending(path: "artifact.o"))
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertFalse(assessment.hasUnsavedWork)
    }

    func testRenamedFileCountsAsOneChange() async throws {
        let checkout = try repository.addManagedWorktree(name: "renamed")
        try Data("r".utf8).write(to: checkout.appending(path: "old.txt"))
        try repository.git(["add", "old.txt"], in: checkout)
        try repository.git(["commit", "-m", "old"], in: checkout)
        try repository.git(["push", "origin", "renamed"], in: checkout)
        try repository.git(["mv", "old.txt", "new.txt"], in: checkout)
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertEqual(assessment.modifiedCount, 1)
        XCTAssertEqual(assessment.untrackedCount, 0)
    }

    func testUnpushedCommitsAreCounted() async throws {
        let checkout = try repository.addManagedWorktree(name: "unpushed")
        for index in 0..<3 { try repository.commit("local \(index)", in: checkout) }
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertEqual(assessment.unpushedCommitCount, 3)
        XCTAssertEqual(assessment.unsavedWorkLines, ["3 commits not on any remote on unpushed"])
    }

    func testPushedCommitsAreNotUnsavedWork() async throws {
        let checkout = try repository.addManagedWorktree(name: "pushed")
        try repository.commit("local", in: checkout)
        try repository.git(["push", "origin", "pushed"], in: checkout)
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertEqual(assessment.unpushedCommitCount, 0)
        XCTAssertFalse(assessment.hasUnsavedWork)
    }

    func testDetachedHeadWithLocalCommitsIsUnsavedWork() async throws {
        let checkout = try repository.addManagedWorktree(name: "detached-local")
        try repository.git(["checkout", "--detach"], in: checkout)
        try repository.commit("detached local", in: checkout)
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertNil(assessment.branch)
        XCTAssertTrue(assessment.isDetached)
        XCTAssertEqual(assessment.unpushedCommitCount, 1)
        XCTAssertEqual(assessment.unsavedWorkLines, ["1 commit not on any remote on a detached HEAD"])
    }

    func testDetachedHeadFullyPushedIsClean() async throws {
        let checkout = try repository.addManagedWorktree(name: "detached-pushed")
        try repository.git(["checkout", "--detach"], in: checkout)
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertTrue(assessment.isDetached)
        XCTAssertFalse(assessment.hasUnsavedWork)
    }

    func testLockedWorktreeIsReported() async throws {
        let checkout = try repository.addManagedWorktree(name: "locked")
        try repository.git(["worktree", "lock", checkout.path])
        let assessment = try await WorktreeCleanup.assess(repository: repository.root, checkout: checkout)
        XCTAssertTrue(assessment.isLocked)
    }

    func testOtherPaneUseIsCarriedThrough() async throws {
        let checkout = try repository.addManagedWorktree(name: "shared")
        let assessment = try await WorktreeCleanup.assess(
            repository: repository.root, checkout: checkout, isUsedByOtherPane: true)
        XCTAssertTrue(assessment.isUsedByOtherPane)
    }

    func testAssessingNonRepositoryFolderThrows() async throws {
        let folder = repository.root.deletingLastPathComponent().appending(path: "plain", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            _ = try await WorktreeCleanup.assess(repository: repository.root, checkout: folder)
            XCTFail("expected failure")
        } catch is GitCommandError {}
    }

    func testCountChangesHandlesEmptyAndShortTokens() {
        XCTAssertEqual(WorktreeCleanup.countChanges(porcelainZ: "").modified, 0)
        XCTAssertEqual(WorktreeCleanup.countChanges(porcelainZ: "M\0").modified, 0)
        let result = WorktreeCleanup.countChanges(porcelainZ: " M a\0?? b\0!! c\0R  new\0old\0A  d\0")
        XCTAssertEqual(result.modified, 3)
        XCTAssertEqual(result.untracked, 1)
    }
}
