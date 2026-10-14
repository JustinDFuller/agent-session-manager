import Darwin
import Foundation
import XCTest

@testable import AgentSessionManager

final class GitHubCLIRunnerTests: XCTestCase {
    func testGHPathTakesPrecedenceAndReceivesArgumentsAndStdin() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-gh-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "gh")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\"\ncat\nprintf stderr >&2\n".write(
            to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let shell = directory.appending(path: "configured-shell")
        try """
        #!/bin/sh
        export GH_PATH='/shell/override/gh'
            export PATH='/shell/path:/bin:/usr/bin'
        exec /bin/sh -c "$4"
        """.write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)

        let runner = GitHubCLIRunner(
            environment: [
                "GH_PATH": executable.path,
                "PATH": "/missing",
                "HOME": "/tmp/home",
                "GH_CONFIG_DIR": "/tmp/gh",
            ], shell: shell.path)
        let result = await runner.run(arguments: ["api", "graphql"], stdin: Data("body".utf8), timeout: 2)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "api\ngraphql\nbody")
        XCTAssertEqual(result.stderrPrefix, "stderr")
    }

    func testInteractiveShellPathAndAuthenticationContextReachGitHubWrapper() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-gh-shell-\(UUID().uuidString)")
        let bin = directory.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = bin.appending(path: "gh")
        try """
        #!/bin/sh
        printf '%s:%s\\n' "$GH_CONFIG_DIR" "$GH_TOKEN"
        printf '%s\\n' "$@"
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let shell = directory.appending(path: "configured-shell")
        let shellScript = """
            #!/bin/sh
            export PATH='\(bin.path):/base'
            export GH_CONFIG_DIR='/configured/gh'
            export GH_TOKEN='session-token'
            printf startup-noise
            exec /bin/sh -c "$4"
            """
        try shellScript.write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        let runner = GitHubCLIRunner(
            environment: ["PATH": "/base", "GH_CONFIG_DIR": "/inherited/gh", "GH_TOKEN": "explicit-token"],
            shell: shell.path
        )
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        let result = await runner.run(arguments: ["auth", "status"], timeout: 2)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(
            String(data: result.stdout, encoding: .utf8),
            "/inherited/gh:explicit-token\nauth\nstatus\n"
        )
        let environmentEvent = TracingService.shared.recordedEventsForTesting
            .first { $0.name == "pr.shell.environment" }
        XCTAssertEqual(environmentEvent?.attributes["result"], "resolved")
        XCTAssertFalse(environmentEvent?.attributes.values.contains("session-token") ?? true)
    }

    func testInteractiveShellTimeoutAndNoiseAreBounded() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-gh-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferred = directory.appending(path: "preferred", directoryHint: .isDirectory)
        let fallback = directory.appending(path: "fallback", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: preferred, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        for bin in [preferred, fallback] {
            let executable = bin.appending(path: "gh")
            try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        let noisyShell = directory.appending(path: "noisy-shell")
        let noisyScript = """
            #!/bin/sh
            export PATH='\(preferred.path):\(fallback.path)'
            export GH_CONFIG_DIR='/configured/gh'
            export GH_TOKEN='session-token'
            printf startup-noise
            exec /bin/sh -c "$3"
            """
        try noisyScript.write(to: noisyShell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: noisyShell.path)

        let environment = GitHubShellEnvironmentResolver.resolve(
            shell: noisyShell.path,
            baseEnvironment: ["PATH": "/base", "GH_CONFIG_DIR": "/inherited/gh"],
            timeout: 1
        )

        XCTAssertEqual(environment?["PATH"], "\(preferred.path):\(fallback.path)")
        XCTAssertEqual(environment?["GH_CONFIG_DIR"], "/inherited/gh")
        XCTAssertEqual(environment?["GH_TOKEN"], "session-token")
        XCTAssertEqual(
            GitHubCLIRunner.resolveExecutable(environment: environment ?? [:])?.path,
            preferred.appending(path: "gh").path
        )

        let stalledShell = directory.appending(path: "stalled-shell")
        try """
        #!/bin/sh
        exec /bin/sleep 10
        """.write(to: stalledShell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stalledShell.path)
        let start = Date()
        let timedOutEnvironment = GitHubShellEnvironmentResolver.resolve(
            shell: stalledShell.path,
            baseEnvironment: [:],
            timeout: 0.1
        )

        XCTAssertNil(timedOutEnvironment)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)

        let noisyShellWithExcessOutput = directory.appending(path: "oversized-shell-output")
        try """
        #!/bin/sh
        /usr/bin/head -c 300000 /dev/zero
        exec /bin/sh -c "$3"
        """.write(to: noisyShellWithExcessOutput, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: noisyShellWithExcessOutput.path)
        let oversizedOutputStart = Date()
        let oversizedEnvironment = GitHubShellEnvironmentResolver.resolve(
            shell: noisyShellWithExcessOutput.path,
            baseEnvironment: [:],
            timeout: 1
        )

        XCTAssertNil(oversizedEnvironment)
        XCTAssertLessThan(Date().timeIntervalSince(oversizedOutputStart), 1)
    }

    func testMissingExecutableAndFailureClassification() async {
        XCTAssertNil(GitHubCLIRunner.resolveExecutable(environment: ["PATH": "/missing"]))
        XCTAssertEqual(GitHubCLIRunner.classify(exitCode: 4, stderr: ""), .authentication)
        XCTAssertEqual(GitHubCLIRunner.classify(exitCode: 2, stderr: ""), .cancelled)
        XCTAssertEqual(GitHubCLIRunner.classify(exitCode: 1, stderr: "no such host"), .network)
        XCTAssertEqual(
            GitHubCLIRunner.classify(exitCode: 1, stderr: "gh: Bad credentials (HTTP 401)"), .authentication)
        XCTAssertEqual(
            GitHubCLIRunner.classify(exitCode: 1, stderr: "gh: API request failed (HTTP 401)"), .authentication)
        XCTAssertEqual(
            GitHubCLIRunner.classify(exitCode: 1, stderr: "gh: Resource not accessible (HTTP 403)"), .api)
        XCTAssertEqual(GitHubCLIRunner.classify(exitCode: 1, stderr: "HTTP/2.0 500"), .api)
    }

    func testHTTP401BadCredentialsCLIResponseIsAuthenticationFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-gh-auth-response-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "gh")
        try """
        #!/bin/sh
        printf '%s\\n' '{"status":401}'
        printf '%s\\n' 'gh: Bad credentials (HTTP 401)' >&2
        exit 1
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let runner = GitHubCLIRunner(environment: ["GH_PATH": executable.path])

        let result = await runner.run(arguments: ["api", "graphql"], stdin: Data("{}".utf8), timeout: 2)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.failure, .authentication)
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "{\"status\":401}\n")
        XCTAssertEqual(result.stderrPrefix, "gh: Bad credentials (HTTP 401)\n")
    }

    func testExecutableDirectoryIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-gh-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executableDirectory = directory.appending(path: "gh")
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        let fallbackDirectory = directory.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        let fallbackExecutable = fallbackDirectory.appending(path: "gh")
        try "#!/bin/sh\nexit 0\n".write(to: fallbackExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fallbackExecutable.path)

        XCTAssertNil(
            GitHubCLIRunner.resolveExecutable(
                environment: ["GH_PATH": executableDirectory.path, "PATH": fallbackDirectory.path]))
    }

    func testTimeoutTerminatesReplacementProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-gh-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let replacement = directory.appending(path: "replacement")
        let terminationMarker = directory.appending(path: "terminated")
        let replacementScript = """
            #!/bin/bash
            trap '
                /usr/bin/touch "\(terminationMarker.path)"
                kill "$child" 2>/dev/null
                exit 0
            ' TERM
            /bin/sleep 2 >/dev/null 2>&1 &
            child=$!
            wait "$child"
            """
        try replacementScript.write(to: replacement, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: replacement.path)
        let executable = directory.appending(path: "gh")
        try "#!/bin/sh\nrm \"$0\"\nexec \"\(replacement.path)\"\n".write(
            to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let runner = GitHubCLIRunner(environment: ["GH_PATH": executable.path], shell: "/bin/sh")
        let start = Date()
        let result = await runner.run(arguments: [], timeout: 0.1)

        XCTAssertEqual(result.failure, .timeout)
        XCTAssertTrue(FileManager.default.fileExists(atPath: terminationMarker.path))
    }

    func testClosedStdinReportsFailureWithoutTerminatingApp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-gh-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "gh")
        try "#!/bin/sh\nexec 0<&-\nsleep 1\necho unreachable\n".write(
            to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let runner = GitHubCLIRunner(environment: ["GH_PATH": executable.path])

        for _ in 0..<3 {
            let result = await runner.run(
                arguments: [],
                stdin: Data(repeating: 0x61, count: 1_000_000),
                timeout: 2)
            XCTAssertEqual(result.failure, .stdinWrite)
            XCTAssertEqual(result.inputFailure?.stage, .write)
            XCTAssertEqual(result.inputFailure?.errorCode, EPIPE)
        }
    }

    func testClosedStdinPreservesAuthenticationFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-gh-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "gh")
        try "#!/bin/sh\nexec 0<&-\nsleep 0.1\necho auth >&2\nexit 4\n".write(
            to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let runner = GitHubCLIRunner(environment: ["GH_PATH": executable.path])

        let result = await runner.run(
            arguments: [],
            stdin: Data(repeating: 0x61, count: 1_000_000),
            timeout: 2)

        XCTAssertEqual(result.failure, .authentication)
        XCTAssertNotNil(result.inputFailure)
    }

    func testCancellationWithStdinReturnsCancelled() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-gh-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "gh")
        try "#!/bin/sh\ncat >/dev/null\nexec sleep 5\n".write(
            to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let runner = GitHubCLIRunner(environment: ["GH_PATH": executable.path])

        let task = Task {
            await runner.run(
                arguments: [],
                stdin: Data(repeating: 0x61, count: 1_000_000),
                timeout: 10)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result.failure, .cancelled)
    }
}
