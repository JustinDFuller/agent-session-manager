import XCTest

@testable import AgentSessionManager

@MainActor
final class WorktreeResolutionTests: XCTestCase {
    private func makeGitRepo() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "asm-resolve-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init"], cwd: url)
        try runGit(
            ["-c", "user.email=t@t.com", "-c", "user.name=t", "commit", "--allow-empty", "-m", "init"],
            cwd: url
        )
        try runGit(["branch", "-M", "resolve-test-branch"], cwd: url)
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

    private func currentBranch(cwd: URL) throws -> String {
        let proc = Process()
        proc.executableURL = URL(filePath: "/usr/bin/git")
        proc.arguments = ["branch", "--show-current"]
        proc.currentDirectoryURL = cwd
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testNovelSimpleNameCreatesWorktreeFromDefaultBranch() async throws {
        let repo = try makeGitRepo()
        let baseBranch = try currentBranch(cwd: repo)
        try runGit(["branch", "novel-base", baseBranch], cwd: repo)

        let tab = Tab(name: "T", directory: repo)
        let slug = "fresh-session-\(UUID().uuidString.prefix(8))"
        let resolved = try await tab.resolveOrAttachWorktree(
            userRef: slug, defaultBranch: "novel-base", baseRef: .head)
        XCTAssertEqual(resolved.paneTitle, slug)
        XCTAssertFalse(resolved.isExternalTakeover)
        XCTAssertTrue(resolved.processDirectory.path.hasSuffix(Tab.gitWorktreeAddPath(name: slug)))

        _ = await tab.removeWorktree(
            of: Pane(
                name: slug,
                tab: tab,
                harness: .claude,
                worktreeDirectory: resolved.processDirectory,
                worktreeIsManaged: true
            ),
            deleteBranch: false
        )
    }

    func testNovelSimpleNameWithoutDefaultBranchThrows() async throws {
        let repo = try makeGitRepo()
        let tab = Tab(name: "T", directory: repo)
        let slug = "fresh-session-\(UUID().uuidString.prefix(8))"
        do {
            _ = try await tab.resolveOrAttachWorktree(userRef: slug, defaultBranch: nil)
            XCTFail("Expected error when plain name has no default branch")
        } catch let error as WorktreeResolutionError {
            XCTAssertEqual(error, .refNotFound(slug))
        }
    }

    func testLooseBranchRefResolvesWorktree() async throws {
        let repo = try makeGitRepo()
        try runGit(["branch", "loose-branch", "HEAD"], cwd: repo)

        let tab = Tab(name: "T", directory: repo)
        let resolved = try await tab.resolveOrAttachWorktree(userRef: "loose-branch")
        XCTAssertEqual(resolved.paneTitle, "loose-branch")
        XCTAssertFalse(resolved.isExternalTakeover)

        _ = await tab.removeWorktree(
            of: Pane(
                name: "loose-branch",
                tab: tab,
                harness: .claude,
                worktreeDirectory: resolved.processDirectory,
                worktreeIsManaged: true
            ),
            deleteBranch: false
        )
    }

    func testPrimaryCheckoutBranchReturnsExternalTakeover() async throws {
        let repo = try makeGitRepo()
        let branch = try currentBranch(cwd: repo)
        XCTAssertEqual(branch, "resolve-test-branch")
        let tab = Tab(name: "T", directory: repo)
        let resolved = try await tab.resolveOrAttachWorktree(userRef: branch)
        XCTAssertTrue(resolved.isExternalTakeover)
        XCTAssertFalse(resolved.processDirectory.path.contains(".agent-session-manager/worktrees"))
    }

    func testExistingAppManagedLinkedWorktreeReturnsManaged() async throws {
        let repo = try makeGitRepo()
        let branch = try currentBranch(cwd: repo)
        XCTAssertEqual(branch, "resolve-test-branch")
        let rel = Tab.gitWorktreeAddPath(name: "wt-sidecar")
        try runGit(["worktree", "add", rel, "-b", "wt-sidecar-tracking", branch], cwd: repo)

        let tab = Tab(name: "T", directory: repo)
        let resolved = try await tab.resolveOrAttachWorktree(userRef: "wt-sidecar")
        XCTAssertEqual(resolved.paneTitle, "wt-sidecar")
        XCTAssertFalse(resolved.isExternalTakeover)
        XCTAssertTrue(resolved.processDirectory.path.hasSuffix(rel))

        _ = await tab.removeWorktree(
            of: Pane(
                name: "wt-sidecar",
                tab: tab,
                harness: .claude,
                worktreeDirectory: resolved.processDirectory,
                worktreeIsManaged: true
            ),
            deleteBranch: false
        )
    }

    func testRemoteStyleRefFetchesAndCreatesWorktree() async throws {
        let repo = try makeGitRepo()
        let tab = Tab(name: "T", directory: repo)

        do {
            let resolved = try await tab.resolveOrAttachWorktree(
                userRef: "origin/nonexistent-branch-xyz", defaultBranch: nil)
            XCTFail("Expected error for non-existent remote ref, got \(resolved)")
        } catch let error as WorktreeResolutionError {
            XCTAssertEqual(error, .refNotFound("origin/nonexistent-branch-xyz"))
        }
    }

    func testResolvedWorktreeEquatable() {
        let first = ResolvedWorktree(
            paneTitle: "test",
            processDirectory: URL(filePath: "/tmp/a"),
            checkoutURL: URL(filePath: "/tmp/a"),
            isExternalTakeover: false
        )
        let second = ResolvedWorktree(
            paneTitle: "test",
            processDirectory: URL(filePath: "/tmp/a"),
            checkoutURL: URL(filePath: "/tmp/a"),
            isExternalTakeover: false
        )
        let third = ResolvedWorktree(
            paneTitle: "other",
            processDirectory: URL(filePath: "/tmp/b"),
            checkoutURL: URL(filePath: "/tmp/b"),
            isExternalTakeover: true
        )
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, third)
        XCTAssertTrue(third.isExternalTakeover)
    }
}
