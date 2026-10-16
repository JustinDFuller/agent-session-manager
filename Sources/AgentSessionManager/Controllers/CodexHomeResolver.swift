import Darwin
import Foundation

struct CodexHomeResolver {
    static func resolve(
        shell: String,
        workingDirectory: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 2
    ) -> URL {
        let shellHome = exportedHome(
            shell: shell, workingDirectory: workingDirectory, environment: environment, timeout: timeout)
        let configuredHome = shellHome ?? environment["CODEX_HOME"]
        if let configuredHome, !configuredHome.isEmpty {
            return URL(filePath: configuredHome).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    static func databaseURL(
        shell: String,
        workingDirectory: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 2
    ) -> URL {
        resolve(shell: shell, workingDirectory: workingDirectory, environment: environment, timeout: timeout)
            .appending(path: "state_5.sqlite")
    }

    private static func exportedHome(
        shell: String,
        workingDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval
    ) -> String? {
        let marker = "AGENT_SESSION_MANAGER_CODEX_HOME_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let command = "printf '\\n\(marker)\\n%s\\n\(marker)\\n' \"${CODEX_HOME-}\""
        let process = Process()
        let output = Pipe()
        let captured = CodexHomeOutput()
        let readerFinished = DispatchSemaphore(value: 0)
        process.executableURL = URL(filePath: shell)
        process.arguments = ["-i", "-c", command]
        process.environment = environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        if let workingDirectory { process.currentDirectoryURL = URL(filePath: workingDirectory) }
        do {
            try process.run()
        } catch {
            return nil
        }
        DispatchQueue.global(qos: .utility).async {
            defer { readerFinished.signal() }
            while let chunk = try? output.fileHandleForReading.read(upToCount: 512), !chunk.isEmpty {
                captured.lock.lock()
                captured.data.append(chunk)
                if captured.data.count > 4096 {
                    captured.data.removeFirst(captured.data.count - 4096)
                }
                captured.lock.unlock()
            }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.1)
            while process.isRunning && Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        _ = readerFinished.wait(timeout: .now() + 0.1)
        guard process.terminationStatus == 0 else { return nil }
        captured.lock.lock()
        let outputText = String(decoding: captured.data, as: UTF8.self)
        captured.lock.unlock()
        let lines = outputText.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(of: marker),
            let end = lines.dropFirst(start + 1).firstIndex(of: marker), end > start + 1
        else { return nil }
        let value = lines[(start + 1)..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private final class CodexHomeOutput: @unchecked Sendable {
    let lock = NSLock()
    var data = Data()
}
