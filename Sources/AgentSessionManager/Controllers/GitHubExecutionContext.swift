import Foundation

struct GitHubExecutionContext: Sendable {
    let executable: URL?
    let environment: [String: String]

    static let maximumShellOutputBytes = 262_144
    static let shellTimeout: TimeInterval = 4
    static let environmentMarker = "__AGENT_SESSION_MANAGER_GITHUB_ENV__"

    static func resolve(
        inheritedEnvironment: [String: String],
        shellPath: String,
        fileManager: FileManager = .default,
        timeout: TimeInterval = shellTimeout
    ) async -> GitHubExecutionContext {
        let shellEnvironment = await exportedEnvironment(
            shellPath: shellPath,
            inheritedEnvironment: inheritedEnvironment,
            timeout: timeout)
        var mergedEnvironment = inheritedEnvironment
        for name in [
            "HOME", "PATH", "GH_CONFIG_DIR", "XDG_CONFIG_HOME", "GH_HOST", "GH_TOKEN",
            "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN",
        ] where mergedEnvironment[name] == nil {
            mergedEnvironment[name] = shellEnvironment[name]
        }
        let searchPath = shellEnvironment["PATH"] ?? inheritedEnvironment["PATH"] ?? ""
        var lookupEnvironment = ["PATH": searchPath]
        if let override = inheritedEnvironment["GH_PATH"] {
            lookupEnvironment["GH_PATH"] = override
            lookupEnvironment["PATH"] = ""
        }
        let executable = GitHubCLIRunner.resolveExecutable(
            environment: lookupEnvironment,
            fileManager: fileManager)
        if !searchPath.isEmpty {
            mergedEnvironment["PATH"] = ProcessEnvironment.mergedPATH(
                currentPath: searchPath,
                defaultEntries: ProcessEnvironment.defaultPATHEntries(fileManager: fileManager))
        }
        return GitHubExecutionContext(executable: executable, environment: mergedEnvironment)
    }

    static func parseExportedEnvironment(_ output: Data) -> [String: String] {
        guard let marker = ("\n" + environmentMarker + "\n").data(using: .utf8),
            let markerRange = output.range(of: marker)
        else { return [:] }
        let exported = output[markerRange.upperBound...]
        let allowed = Set([
            "HOME", "PATH", "GH_CONFIG_DIR", "XDG_CONFIG_HOME", "GH_HOST", "GH_TOKEN",
            "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN",
        ])
        var result: [String: String] = [:]
        for entry in exported.split(separator: 0) {
            guard let separator = entry.firstIndex(of: 61), separator > entry.startIndex else { continue }
            let key = String(decoding: entry[..<separator], as: UTF8.self)
            guard allowed.contains(key) else { continue }
            let value = String(decoding: entry[entry.index(after: separator)...], as: UTF8.self)
            result[key] = value
        }
        return result
    }

    static func exportedEnvironment(
        shellPath: String,
        inheritedEnvironment: [String: String],
        timeout: TimeInterval
    ) async -> [String: String] {
        let process = Process()
        process.executableURL = URL(filePath: shellPath)
        process.arguments = [
            "-l", "-i", "-c",
            "printf '\\n\(environmentMarker)\\n'; /usr/bin/env -0 | /usr/bin/head -c \(maximumShellOutputBytes)",
        ]
        process.environment = inheritedEnvironment
        process.standardInput = FileHandle.nullDevice
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return [:]
        }
        let outputTask = Task.detached(priority: .utility) {
            Self.readBoundedOutput(outputPipe.fileHandleForReading)
        }
        let deadline = Date.now.addingTimeInterval(timeout)
        while process.isRunning, Date.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let completed = !process.isRunning && !Task.isCancelled
        if !completed, process.isRunning { process.terminate() }
        if !completed { try? outputPipe.fileHandleForReading.close() }
        let output = await outputTask.value
        guard completed, output.count <= maximumShellOutputBytes + 65_536 else { return [:] }
        return parseExportedEnvironment(output)
    }

    static func readBoundedOutput(_ handle: FileHandle) -> Data {
        var output = Data()
        while let chunk = try? handle.read(upToCount: 32_768), !chunk.isEmpty {
            if output.count < maximumShellOutputBytes {
                output.append(chunk.prefix(maximumShellOutputBytes - output.count))
            }
        }
        try? handle.close()
        return output
    }
}
