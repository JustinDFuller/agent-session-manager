import Foundation
import XCTest

@testable import AgentSessionManager

final class GitHubExecutionContextTests: XCTestCase {
    func testShellEnvironmentUsesConfiguredPathAndFillsOnlyMissingAuthenticationValues() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-github-context-\(UUID().uuidString)")
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = bin.appending(path: "gh")
        try "#!/bin/sh\nexit 0\n".write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let shell = root.appending(path: "interactive-shell")
        try
            "#!/bin/sh\nexport PATH='\(bin.path)'\nexport GH_TOKEN=shell-secret\nexport GH_CONFIG_DIR=/shell/config\nexport GH_REPO=github.com/shell-owner/shell-repo\nprintf 'startup noise\\n'\nprintf '\\n\(GitHubExecutionContext.environmentMarker)\\n'\n/usr/bin/env -0\n"
            .write(
                to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)

        let context = await GitHubExecutionContext.resolve(
            inheritedEnvironment: [
                "PATH": "/fallback", "GH_TOKEN": "inherited-secret",
                "GH_REPO": "github.com/inherited-owner/inherited-repo",
            ],
            shellPath: shell.path)

        XCTAssertEqual(context.executable?.path, wrapper.path)
        XCTAssertEqual(context.environment["GH_TOKEN"], "inherited-secret")
        XCTAssertEqual(context.environment["GH_CONFIG_DIR"], "/shell/config")
        XCTAssertEqual(context.environment["GH_REPO"], "github.com/inherited-owner/inherited-repo")
        XCTAssertTrue(context.environment["PATH"]?.contains(bin.path) == true)
        XCTAssertFalse(context.environment.values.contains("shell-secret"))
    }

    func testInheritedExecutableOverrideWinsOverShellPath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-github-override-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "gh-wrapper")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let shell = root.appending(path: "interactive-shell")
        try
            "#!/bin/sh\nexport PATH=/missing\nprintf '\\n\(GitHubExecutionContext.environmentMarker)\\n'\n/usr/bin/env -0\n"
            .write(
                to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)

        let context = await GitHubExecutionContext.resolve(
            inheritedEnvironment: ["GH_PATH": executable.path],
            shellPath: shell.path)

        XCTAssertEqual(context.executable?.path, executable.path)
    }

    func testInvalidInheritedExecutableOverrideDoesNotFallBackToShellPath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-github-invalid-override-\(UUID().uuidString)")
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = bin.appending(path: "gh")
        try "#!/bin/sh\nexit 0\n".write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let shell = root.appending(path: "interactive-shell")
        try
            "#!/bin/sh\nexport PATH='\(bin.path)'\nprintf '\\n\(GitHubExecutionContext.environmentMarker)\\n'\n/usr/bin/env -0\n"
            .write(
                to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)

        let context = await GitHubExecutionContext.resolve(
            inheritedEnvironment: ["GH_PATH": root.appending(path: "missing-gh").path],
            shellPath: shell.path)

        XCTAssertNil(context.executable)
    }

    func testExportedEnvironmentIgnoresStartupNoiseAndUnapprovedValues() {
        let text =
            "startup banner\n\(GitHubExecutionContext.environmentMarker)\nPATH=/bin\0GH_REPO=github.com/owner/repo\0GH_TOKEN=secret\0PASSWORD=secret\0"

        let environment = GitHubExecutionContext.parseExportedEnvironment(Data(text.utf8))

        XCTAssertEqual(environment["PATH"], "/bin")
        XCTAssertEqual(environment["GH_REPO"], "github.com/owner/repo")
        XCTAssertEqual(environment["GH_TOKEN"], "secret")
        XCTAssertNil(environment["PASSWORD"])
    }

    func testShellContextTimeoutReturnsWithoutShellEnvironment() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-github-timeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let shell = root.appending(path: "slow-shell")
        try "#!/bin/sh\nsleep 0.4\n".write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        let startedAt = Date()

        let environment = await GitHubExecutionContext.exportedEnvironment(
            shellPath: shell.path, inheritedEnvironment: ["PATH": "/bin"], timeout: 0.05)

        XCTAssertTrue(environment.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.3)
    }

    func testShellOutputCaptureIsBounded() {
        let pipe = Pipe()
        let writeTask = Task.detached {
            try? pipe.fileHandleForWriting.write(contentsOf: Data(repeating: 0x61, count: 400_000))
            try? pipe.fileHandleForWriting.close()
        }

        let captured = GitHubExecutionContext.readBoundedOutput(pipe.fileHandleForReading)

        XCTAssertEqual(captured.count, GitHubExecutionContext.maximumShellOutputBytes)
        writeTask.cancel()
    }
}
