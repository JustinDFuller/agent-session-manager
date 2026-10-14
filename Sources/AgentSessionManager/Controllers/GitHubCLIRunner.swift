import Foundation

protocol GitHubCLIRunning: Sendable {
    func run(arguments: [String], stdin: Data?, timeout: TimeInterval) async -> GitHubCLIResult
}

enum GitHubCLIFailure: String, Sendable, Equatable, Codable {
    case missingExecutable = "missing_executable"
    case launch
    case authentication
    case network
    case timeout
    case cancelled
    case stdinWrite = "stdin_write"
    case api
    case parse
}

struct GitHubCLIResult: Sendable {
    let stdout: Data
    let stderrPrefix: String
    let exitCode: Int32?
    let failure: GitHubCLIFailure?
    let inputFailure: ChildProcessInputWriteFailure?

    var succeeded: Bool { failure == nil && exitCode == 0 }
}

final class GitHubCLIRunner: GitHubCLIRunning, @unchecked Sendable {
    static let shared = GitHubCLIRunner()
    static let stderrPrefixLimit = 1_024

    private let environment: [String: String]
    private let fileManager: FileManager
    private let shell: String?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        shell: String? = nil
    ) {
        self.environment = Dictionary(
            uniqueKeysWithValues: ProcessEnvironment.sanitize(environment.map { "\($0.key)=\($0.value)" })
                .compactMap { entry in
                    guard let index = entry.firstIndex(of: "=") else { return nil }
                    return (String(entry[..<index]), String(entry[entry.index(after: index)...]))
                })
        self.fileManager = fileManager
        self.shell = shell
    }

    func run(arguments: [String], stdin: Data? = nil, timeout: TimeInterval) async -> GitHubCLIResult {
        let shellSettings = SettingsPersistence.load(
            SettingsPersistence.ShellSettings.self, from: "shell-settings.json")
        let preferredShell = shellSettings?.preferredShell.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shellPath = shell ?? (preferredShell.isEmpty ? ShellResolver.detectedLoginShell() : preferredShell)
        let context = await GitHubExecutionContext.resolve(
            inheritedEnvironment: environment, shellPath: shellPath, fileManager: fileManager)
        TracingService.shared.record(
            "pr.shell.environment",
            attributes: [
                "result": context.environment == environment ? "inherited_fallback" : "resolved"
            ])
        guard let executable = context.executable else {
            return GitHubCLIResult(
                stdout: Data(), stderrPrefix: "", exitCode: nil, failure: .missingExecutable,
                inputFailure: nil)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var childEnvironment = context.environment
        childEnvironment["GH_PROMPT_DISABLED"] = "1"
        process.environment = childEnvironment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let input = stdin.map { _ in Pipe() }
        process.standardInput = input
        let exitState = ChildProcessExitState()
        process.terminationHandler = { finishedProcess in
            exitState.lock.lock()
            if let continuation = exitState.continuation {
                exitState.continuation = nil
                exitState.lock.unlock()
                continuation.resume(returning: finishedProcess.terminationStatus)
            } else {
                exitState.status = finishedProcess.terminationStatus
                exitState.lock.unlock()
            }
        }
        do {
            try process.run()
        } catch {
            try? input?.fileHandleForWriting.close()
            return GitHubCLIResult(
                stdout: Data(), stderrPrefix: "", exitCode: nil, failure: .launch,
                inputFailure: nil)
        }
        let inputWriteTask: Task<ChildProcessInputWriteFailure?, Never>? = stdin.flatMap { stdin in
            input.map { input in
                Task.detached(priority: .userInitiated) { () -> ChildProcessInputWriteFailure? in
                    ChildProcessInputWriter.write(
                        stdin,
                        to: input.fileHandleForWriting,
                        timeout: timeout)
                }
            }
        }

        let failure = await withTaskCancellationHandler(
            operation: {
                await withTaskGroup(of: GitHubCLIFailure?.self, returning: GitHubCLIFailure?.self) { group in
                    group.addTask {
                        _ = await withCheckedContinuation {
                            (continuation: CheckedContinuation<Int32, Never>) in
                            exitState.lock.lock()
                            if let status = exitState.status {
                                exitState.lock.unlock()
                                continuation.resume(returning: status)
                            } else {
                                exitState.continuation = continuation
                                exitState.lock.unlock()
                            }
                        }
                        return nil
                    }
                    group.addTask {
                        do {
                            try await Task.sleep(for: .seconds(timeout))
                        } catch {
                            return nil
                        }
                        process.terminate()
                        return .timeout
                    }
                    let result = await group.next() ?? .timeout
                    group.cancelAll()
                    return result
                }
            },
            onCancel: { process.terminate() })
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        if failure == .timeout || Task.isCancelled {
            try? input?.fileHandleForWriting.close()
        }
        let inputFailure = await inputWriteTask?.value
        if Task.isCancelled {
            return GitHubCLIResult(
                stdout: outData, stderrPrefix: "", exitCode: nil, failure: .cancelled,
                inputFailure: inputFailure)
        }
        let stderrText = String(data: errData.prefix(Self.stderrPrefixLimit), encoding: .utf8) ?? ""
        if failure == .timeout {
            return GitHubCLIResult(
                stdout: outData, stderrPrefix: stderrText, exitCode: nil, failure: .timeout,
                inputFailure: inputFailure)
        }
        let status = process.terminationStatus
        let classifiedFailure = Self.classify(
            exitCode: status,
            stderr: stderrText,
            stdout: String(data: outData.prefix(Self.stderrPrefixLimit), encoding: .utf8) ?? "")
        if let classifiedFailure {
            return GitHubCLIResult(
                stdout: outData, stderrPrefix: stderrText, exitCode: status,
                failure: classifiedFailure, inputFailure: inputFailure)
        }
        if inputFailure != nil {
            return GitHubCLIResult(
                stdout: outData, stderrPrefix: stderrText, exitCode: status,
                failure: .stdinWrite, inputFailure: inputFailure)
        }
        return GitHubCLIResult(
            stdout: outData, stderrPrefix: stderrText, exitCode: status,
            failure: nil,
            inputFailure: nil)
    }

    nonisolated static func resolveExecutable(
        environment: [String: String], fileManager: FileManager = .default
    ) -> URL? {
        if let configured = environment["GH_PATH"] {
            return isExecutable(configured, fileManager: fileManager) ? URL(filePath: configured) : nil
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = (String(directory) as NSString).appendingPathComponent("gh")
            if isExecutable(candidate, fileManager: fileManager) { return URL(filePath: candidate) }
        }
        return nil
    }

    nonisolated private static func isExecutable(_ path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.isExecutableFile(atPath: path)
            && fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    static func classify(exitCode: Int32, stderr: String, stdout: String = "") -> GitHubCLIFailure? {
        guard exitCode != 0 else { return nil }
        if exitCode == 4 { return .authentication }
        if exitCode == 2 { return .cancelled }
        let lower = "\(stderr)\n\(stdout)".lowercased()
        if lower.contains("bad credentials") || lower.contains("http 401") || lower.contains("http/2.0 401 unauthorized")
            || lower.contains("http/1.1 401 unauthorized")
        {
            return .authentication
        }
        if [
            "no such host", "network is unreachable", "connection refused", "connection reset", "tls", "x509",
            "timeout",
        ].contains(where: lower.contains) {
            return .network
        }
        return .api
    }
}
