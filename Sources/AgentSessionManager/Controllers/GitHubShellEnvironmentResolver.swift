import Darwin
import Foundation

struct GitHubShellEnvironmentResolver {
    static let maximumOutputBytes = 262_144

    static func resolve(
        shell: String,
        baseEnvironment: [String: String],
        timeout: TimeInterval = 2
    ) -> [String: String]? {
        let marker = "AGENT_SESSION_MANAGER_GH_ENV_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let command = "printf '\\n%s\\n' '\(marker)'; /usr/bin/env -0; printf '\\n%s\\n' '\(marker)'"
        let process = Process()
        let output = Pipe()
        let captured = GitHubShellEnvironmentOutput()
        let readerFinished = DispatchSemaphore(value: 0)
        process.executableURL = URL(filePath: shell)
        process.arguments = ["-i", "-c", command]
        process.environment = baseEnvironment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        DispatchQueue.global(qos: .utility).async {
            defer { readerFinished.signal() }
            while let chunk = try? output.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                captured.lock.lock()
                let remaining = maximumOutputBytes - captured.data.count
                if remaining > 0 {
                    captured.data.append(chunk.prefix(remaining))
                }
                if chunk.count > remaining { captured.didOverflow = true }
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
        let data = captured.data
        let didOverflow = captured.didOverflow
        captured.lock.unlock()
        guard !didOverflow,
            let start = data.range(of: Data("\n\(marker)\n".utf8))?.upperBound,
            let end = data.range(of: Data("\n\(marker)\n".utf8), in: start..<data.endIndex)?.lowerBound
        else { return nil }
        var resolvedEnvironment = baseEnvironment
        for entry in data[start..<end].split(separator: 0) {
            guard let separator = entry.firstIndex(of: 61), separator > entry.startIndex else { continue }
            let key = String(decoding: entry[..<separator], as: UTF8.self)
            let value = String(decoding: entry[entry.index(after: separator)...], as: UTF8.self)
            if key.hasPrefix("GH_"), baseEnvironment[key] != nil { continue }
            resolvedEnvironment[key] = value
        }
        if let explicitPath = baseEnvironment["GH_PATH"] { resolvedEnvironment["GH_PATH"] = explicitPath }
        return resolvedEnvironment
    }
}

private final class GitHubShellEnvironmentOutput: @unchecked Sendable {
    let lock = NSLock()
    var data = Data()
    var didOverflow = false
}
