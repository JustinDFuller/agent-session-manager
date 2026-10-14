import Foundation
import XCTest

enum GitUITestWorkspace {
    static var directoryURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "UITestWorkspace", directoryHint: .isDirectory)
    }

    static func prepareCleanRepo() {
        let url = directoryURL
        try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            XCTFail("create UITestWorkspace: \(error)")
            return
        }
        runGitOrFail(["init"], cwd: url)
        runGitOrFail(
            ["-c", "user.email=uitest@example.com", "-c", "user.name=uitest", "commit", "--allow-empty", "-m", "init"],
            cwd: url
        )
        runGitOrFail(["branch", "-M", "ui-root"], cwd: url)
        addOrigin(to: url)
    }

    static var originURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "UITestOrigin.git", directoryHint: .isDirectory)
    }

    private static func addOrigin(to url: URL) {
        try? FileManager.default.removeItem(at: originURL)
        runGitOrFail(["init", "--bare", originURL.path], cwd: url)
        runGitOrFail(["remote", "add", "origin", originURL.path], cwd: url)
        runGitOrFail(["push", "origin", "ui-root"], cwd: url)
    }

    static func worktreeURL(folder: String) -> URL {
        directoryURL.appending(path: ".agent-session-manager/worktrees/\(folder)", directoryHint: .isDirectory)
    }

    static func ageWorktree(folder: String, days: Int) {
        let admin = directoryURL.appending(path: ".git/worktrees/\(folder)", directoryHint: .isDirectory)
        let date = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        for name in ["HEAD", "index"] {
            try? FileManager.default.setAttributes(
                [.modificationDate: date], ofItemAtPath: admin.appending(path: name).path)
        }
    }

    static func localBranches() -> [String] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["branch", "--format=%(refname:short)"]
        process.currentDirectoryURL = directoryURL
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.split(separator: "\n").map(String.init) ?? []
    }

    static func addManagedSecondaryWorktree(
        folder: String,
        newTrackingBranch: String,
        baseBranch: String = "ui-root",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let rel = ".agent-session-manager/worktrees/\(folder)"
        runGitOrFail(
            ["worktree", "add", rel, "-b", newTrackingBranch, baseBranch], cwd: directoryURL, file: file, line: line)
    }

    static func runGitOrFail(_ args: [String], cwd: URL, file: StaticString = #file, line: UInt = #line) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd

        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            XCTFail("git launch failed \(args.joined(separator: " ")): \(error)", file: file, line: line)
            return
        }
        process.waitUntilExit()

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: errData, encoding: .utf8) ?? ""

        XCTAssertEqual(
            process.terminationStatus, 0, "git \(args.joined(separator: " ")) failed: \(errText)", file: file,
            line: line)
    }
}
