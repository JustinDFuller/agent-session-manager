import Foundation
import XCTest

@testable import AgentSessionManager

struct GitTestRepository {
    let root: URL
    let remote: URL

    static func make(withRemote: Bool = true) throws -> GitTestRepository {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "asm-git-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = base.appending(path: "repo", directoryHint: .isDirectory)
        let remote = base.appending(path: "origin.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = GitTestRepository(root: root.resolvingSymlinksInPath(), remote: remote)
        try repository.git(["init", "-b", "main"])
        try repository.commit("init")
        if withRemote {
            try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
            try repository.git(["init", "--bare", "-b", "main"], in: remote)
            try repository.git(["remote", "add", "origin", remote.path])
            try repository.git(["push", "-u", "origin", "main"])
            try repository.git(["remote", "set-head", "origin", "main"])
        }
        return repository
    }

    @discardableResult
    func git(_ args: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        let out = Pipe()
        let err = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-c", "user.email=t@t.com", "-c", "user.name=t", "-c", "commit.gpgsign=false"] + args
        process.currentDirectoryURL = directory ?? root
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let stdout = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw GitCommandError(
                arguments: args, exitCode: process.terminationStatus,
                stderr: String(decoding: errData, as: UTF8.self))
        }
        return stdout
    }

    func commit(_ message: String, in directory: URL? = nil) throws {
        let target = directory ?? root
        let file = target.appending(path: "file-\(UUID().uuidString).txt")
        try Data(message.utf8).write(to: file)
        try git(["add", "-A"], in: target)
        try git(["commit", "-m", message], in: target)
    }

    @discardableResult
    func addManagedWorktree(name: String, branch: String? = nil, from base: String = "main") throws -> URL {
        let path = Tab.gitWorktreeAddPath(name: name)
        try git(["worktree", "add", path, "-b", branch ?? name, base])
        return Tab.worktreeDirectoryURL(repoRoot: root, name: name).resolvingSymlinksInPath()
    }

    func branches() throws -> [String] {
        try git(["for-each-ref", "--format=%(refname:short)", "refs/heads"])
            .split(separator: "\n").map(String.init)
    }

    func isRegistered(_ checkout: URL) throws -> Bool {
        let target = checkout.resolvingSymlinksInPath().path
        return try git(["worktree", "list", "--porcelain"])
            .split(separator: "\n")
            .filter { $0.hasPrefix("worktree ") }
            .contains {
                URL(filePath: String($0.dropFirst("worktree ".count))).resolvingSymlinksInPath().path == target
            }
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }
}
