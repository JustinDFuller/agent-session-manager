import Foundation

enum GitRunner {
    @discardableResult
    static func output(_ args: [String], in directory: URL) async throws -> String {
        let cwd = directory.path
        let attributes = ["cwd": cwd, "args": args.joined(separator: " ")]
        do {
            return try await TracingService.shared.withSpan("tab.git.command", attributes: attributes) {
                try await execute(args, in: directory)
            }
        } catch {
            var failure = attributes
            failure["error"] = error.localizedDescription
            TracingService.shared.record("tab.git.command.failed", attributes: failure)
            throw error
        }
    }

    private static func execute(_ args: [String], in directory: URL) async throws -> String {
        let job = GitProcess(args: args, directory: directory)
        let output: String = try await withTaskCancellationHandler(
            operation: { try await job.run() },
            onCancel: { job.cancel() })
        try Task.checkCancellation()
        return output
    }
}

private final class GitProcess: @unchecked Sendable {
    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private let exited = DispatchSemaphore(value: 0)
    private let args: [String]

    init(args: [String], directory: URL) {
        self.args = args
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.terminationHandler = { [exited] _ in exited.signal() }
    }

    func cancel() {
        if process.isRunning { process.terminate() }
    }

    func run() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.global().async {
                continuation.resume(with: self.collect())
            }
        }
    }

    private func collect() -> Result<String, Error> {
        let errData = PipeData()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData.set(self.errPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        exited.wait()
        guard process.terminationStatus == 0 else {
            return .failure(
                GitCommandError(
                    arguments: args, exitCode: process.terminationStatus,
                    stderr: String(data: errData.value, encoding: .utf8) ?? ""))
        }
        return .success(String(data: outData, encoding: .utf8) ?? "")
    }
}

private final class PipeData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data { lock.withLock { data } }

    func set(_ newValue: Data) {
        lock.withLock { data = newValue }
    }
}
