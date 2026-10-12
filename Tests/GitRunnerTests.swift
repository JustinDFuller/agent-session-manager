import XCTest

@testable import AgentSessionManager

final class GitRunnerTests: XCTestCase {
    override func tearDown() {
        TracingService.shared.resetForTesting()
        super.tearDown()
    }

    func testOutputReturnsStdoutFromDirectory() async throws {
        let repository = try GitTestRepository.make(withRemote: false)
        defer { repository.cleanUp() }
        let output = try await GitRunner.output(["rev-parse", "--abbrev-ref", "HEAD"], in: repository.root)
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "main")
    }

    func testFailureThrowsGitCommandErrorWithStderr() async throws {
        let repository = try GitTestRepository.make(withRemote: false)
        defer { repository.cleanUp() }
        do {
            _ = try await GitRunner.output(["rev-parse", "--verify", "no-such-ref"], in: repository.root)
            XCTFail("expected failure")
        } catch let error as GitCommandError {
            XCTAssertNotEqual(error.exitCode, 0)
            XCTAssertEqual(error.arguments, ["rev-parse", "--verify", "no-such-ref"])
        }
    }

    func testFailureRecordsFailedEventWithReason() async throws {
        TracingService.shared.enableTestCapture()
        let repository = try GitTestRepository.make(withRemote: false)
        defer { repository.cleanUp() }
        _ = try? await GitRunner.output(["worktree", "remove", "/no/such/worktree"], in: repository.root)
        let failures = TracingService.shared.recordedEventsForTesting.filter { $0.name == "tab.git.command.failed" }
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.attributes["args"], "worktree remove /no/such/worktree")
        XCTAssertEqual(failures.first?.attributes["cwd"], repository.root.path)
        XCTAssertFalse(failures.first?.attributes["error"]?.isEmpty ?? true)
    }

    func testSuccessRecordsNoFailedEvent() async throws {
        TracingService.shared.enableTestCapture()
        let repository = try GitTestRepository.make(withRemote: false)
        defer { repository.cleanUp() }
        _ = try await GitRunner.output(["status"], in: repository.root)
        XCTAssertFalse(
            TracingService.shared.recordedEventsForTesting.contains { $0.name == "tab.git.command.failed" })
    }

    func testLargeOutputDoesNotDeadlock() async throws {
        let repository = try GitTestRepository.make(withRemote: false)
        defer { repository.cleanUp() }
        for index in 0..<3000 {
            try Data().write(to: repository.root.appending(path: "untracked-file-with-a-long-name-\(index).txt"))
        }
        let output = try await GitRunner.output(["status", "--porcelain=v1", "-z"], in: repository.root)
        XCTAssertGreaterThan(output.utf8.count, 100_000)
    }
}
