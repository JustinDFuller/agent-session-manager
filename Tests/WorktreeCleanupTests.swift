import XCTest

@testable import AgentSessionManager

@MainActor
final class WorktreeCleanupTests: XCTestCase {
    func testPaneWorktreeIsManagedStored() throws {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude, worktreeDirectory: nil, worktreeIsManaged: true)
        XCTAssertTrue(pane.worktreeIsManaged)
    }

    func testPaneWorktreeIsManagedFalseByDefault() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude, worktreeDirectory: nil, worktreeIsManaged: false)
        XCTAssertFalse(pane.worktreeIsManaged)
    }

    func testPaneWorktreeIsManagedWorksForAllHarnesses() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let claudePane = Pane(name: "test", tab: tab, harness: .claude, worktreeDirectory: nil, worktreeIsManaged: true)
        let codexPane = Pane(name: "test", tab: tab, harness: .codex, worktreeDirectory: nil, worktreeIsManaged: true)
        XCTAssertTrue(claudePane.worktreeIsManaged)
        XCTAssertTrue(codexPane.worktreeIsManaged)
    }

    func testPaneWorktreeIsManagedFalseForExternalUntracked() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let override = URL(filePath: "/some/external/path")
        let pane = Pane(name: "test", tab: tab, harness: .claude, worktreeDirectory: override, worktreeIsManaged: false)
        XCTAssertFalse(pane.worktreeIsManaged)
        XCTAssertEqual(pane.worktreeDirectory, override)
    }

    func testWorktreeCleanupBehaviorDisplayNames() {
        XCTAssertEqual(WorktreeCleanupBehavior.ask.displayName, "Ask")
        XCTAssertEqual(WorktreeCleanupBehavior.keep.displayName, "Always Keep")
        XCTAssertEqual(WorktreeCleanupBehavior.delete.displayName, "Always Delete")
    }

    func testWorktreeCleanupBehaviorDescriptions() {
        XCTAssertTrue(WorktreeCleanupBehavior.ask.description.contains("Ask whether"))
        XCTAssertTrue(WorktreeCleanupBehavior.keep.description.contains("Never delete"))
        XCTAssertTrue(WorktreeCleanupBehavior.delete.description.contains("Automatically delete"))
    }

    func testWorktreeCleanupBehaviorCodableRoundTrip() throws {
        let cases: [WorktreeCleanupBehavior] = [.ask, .keep, .delete]
        for behavior in cases {
            let encoded = try JSONEncoder().encode(behavior)
            let decoded = try JSONDecoder().decode(WorktreeCleanupBehavior.self, from: encoded)
            XCTAssertEqual(decoded, behavior)
        }
    }

    func testWorktreeCleanupBehaviorCaseIterable() {
        XCTAssertEqual(WorktreeCleanupBehavior.allCases, [.ask, .keep, .delete])
    }

    func testExistingWorktreeManagementDisplayNames() {
        XCTAssertEqual(ExistingWorktreeManagement.ask.displayName, "Ask")
        XCTAssertEqual(ExistingWorktreeManagement.always.displayName, "Always")
        XCTAssertEqual(ExistingWorktreeManagement.never.displayName, "Never")
    }

    func testExistingWorktreeManagementCodableRoundTrip() throws {
        let cases: [ExistingWorktreeManagement] = [.ask, .always, .never]
        for behavior in cases {
            let encoded = try JSONEncoder().encode(behavior)
            let decoded = try JSONDecoder().decode(ExistingWorktreeManagement.self, from: encoded)
            XCTAssertEqual(decoded, behavior)
        }
    }
}

@MainActor
final class WorktreeCleanupGitIntegrationTests: XCTestCase {
    private func makeGitRepo() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "asm-cleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init"], cwd: url)
        try runGit(
            ["-c", "user.email=t@t.com", "-c", "user.name=t", "commit", "--allow-empty", "-m", "init"],
            cwd: url
        )
        try runGit(["branch", "-M", "cleanup-test"], cwd: url)
        return url
    }

    private func runGit(_ args: [String], cwd: URL) throws {
        let proc = Process()
        proc.executableURL = URL(filePath: "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = cwd
        let err = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTFail("git \(args.joined(separator: " ")): \(msg)")
            throw NSError(domain: "tests", code: Int(proc.terminationStatus))
        }
    }

    func testCleanupWorktreeRemovesManagedWorktree() async throws {
        let repo = try makeGitRepo()
        let tab = Tab(name: "CleanupTab", directory: repo)
        let rel = Tab.gitWorktreeAddPath(name: "test-wt")
        try runGit(["worktree", "add", rel, "-b", "cleanup-target", "cleanup-test"], cwd: repo)

        let worktreeURL = Tab.worktreeDirectoryURL(repoRoot: repo, name: "test-wt")
        let pane = Pane(
            name: "test-wt", tab: tab, harness: .claude, worktreeDirectory: worktreeURL, worktreeIsManaged: true)
        XCTAssertTrue(pane.worktreeIsManaged)

        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreeURL.path))

        let result = await tab.removeWorktree(of: pane, deleteBranch: false)

        XCTAssertEqual(result?.isDeleted, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeURL.path))
    }

    func testCleanupWorktreeNoopsForUnmanagedWorktrees() async throws {
        let repo = try makeGitRepo()
        let tab = Tab(name: "CleanupTab", directory: repo)

        let externalPath = FileManager.default.temporaryDirectory
            .appending(path: "asm-external-wt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: externalPath, withIntermediateDirectories: true)

        let pane = Pane(
            name: "external", tab: tab, harness: .claude, worktreeDirectory: externalPath, worktreeIsManaged: false)
        XCTAssertFalse(pane.worktreeIsManaged)

        let result = await tab.removeWorktree(of: pane, deleteBranch: true)
        XCTAssertNil(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalPath.path))

        try FileManager.default.removeItem(at: externalPath)
    }

    func testCleanupWorktreeNoopsForExternalTakeoverWhenManaged() async throws {
        let repo = try makeGitRepo()
        let tab = Tab(name: "CleanupTab", directory: repo)
        let wtName = "takeover-\(UUID().uuidString.prefix(8))"
        let rel = Tab.gitWorktreeAddPath(name: wtName)
        try runGit(["worktree", "add", rel, "-b", wtName, "cleanup-test"], cwd: repo)

        let worktreeURL = Tab.worktreeDirectoryURL(repoRoot: repo, name: wtName)
        let pane = Pane(
            name: "takeover", tab: tab, harness: .codex, worktreeDirectory: worktreeURL, worktreeIsManaged: true)
        XCTAssertTrue(pane.worktreeIsManaged)

        let result = await tab.removeWorktree(of: pane, deleteBranch: false)
        XCTAssertEqual(result?.isDeleted, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeURL.path))
    }

    func testCleanupWorktreeSkipsWhenPathNotOnDisk() async throws {
        let repo = try makeGitRepo()
        let tab = Tab(name: "CleanupTab", directory: repo)
        let nonexistent = URL(filePath: "/tmp/nonexistent-worktree-\(UUID().uuidString)")
        let pane = Pane(
            name: "nonexistent", tab: tab, harness: .claude, worktreeDirectory: nonexistent, worktreeIsManaged: true)
        XCTAssertTrue(pane.worktreeIsManaged)

        let result = await tab.removeWorktree(of: pane, deleteBranch: false)
        XCTAssertEqual(result?.isDeleted, true)
    }

    func testCleanupWorktreeWorksAfterClosePane() async throws {
        let repo = try makeGitRepo()
        let tab = Tab(name: "CleanupTab", directory: repo)
        let rel = Tab.gitWorktreeAddPath(name: "after-close-wt")
        try runGit(["worktree", "add", rel, "-b", "after-close-branch", "cleanup-test"], cwd: repo)

        let worktreeURL = Tab.worktreeDirectoryURL(repoRoot: repo, name: "after-close-wt")
        let pane = Pane(
            name: "after-close-wt", tab: tab, harness: .claude,
            worktreeDirectory: worktreeURL, worktreeIsManaged: true)
        tab.panes.append(pane)

        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreeURL.path))

        tab.closePane(pane)
        XCTAssertFalse(tab.panes.contains(where: { $0.id == pane.id }))

        let result = await tab.removeWorktree(of: pane, deleteBranch: false)
        XCTAssertEqual(result?.isDeleted, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeURL.path))
    }

    func testRemoveWorktreeNeverRemovesRegisteredWorktreeOutsideManagedFoldersForUnmanagedPane() async throws {
        let repository = try GitTestRepository.make()
        defer { repository.cleanUp() }
        let outside = repository.root.deletingLastPathComponent().appending(path: "tmp-agent-worktree")
        try repository.git(["worktree", "add", outside.path, "-b", "scratch", "main"])
        let tab = Tab(name: "T", directory: repository.root)
        let pane = Pane(
            name: "scratch", tab: tab, harness: .claude, worktreeDirectory: outside, worktreeIsManaged: false)
        let result = await tab.removeWorktree(of: pane, force: true, deleteBranch: true)
        XCTAssertNil(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(try repository.isRegistered(outside))
        XCTAssertTrue(try repository.branches().contains("scratch"))
    }

    func testRemoveWorktreeWithoutWorktreeDirectoryDoesNothing() async {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "p", tab: tab, harness: .claude, worktreeDirectory: nil, worktreeIsManaged: true)
        let result = await tab.removeWorktree(of: pane, deleteBranch: true)
        XCTAssertNil(result)
    }

    func testRemoveCreatedWorktreeRemovesAndDeletesBranch() async throws {
        let repository = try GitTestRepository.make()
        defer { repository.cleanUp() }
        let checkout = try repository.addManagedWorktree(name: "created")
        let tab = Tab(name: "T", directory: repository.root)
        let result = await tab.removeCreatedWorktree(at: checkout, deleteBranch: true)
        XCTAssertEqual(result.outcome, .deleted(branch: .deleted("created")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
    }
}
