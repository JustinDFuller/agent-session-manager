import Darwin
import Foundation

private final class CodexVersionOutputBuffer: @unchecked Sendable {
    let lock = NSLock()
    var data = Data()
}

enum CodexCompatibilityAdapter: Equatable, Sendable {
    case current(version: String)
    case legacy(version: String)
    case unsupported(version: String?)

    static func select(_ rawVersion: String?) -> CodexCompatibilityAdapter {
        guard let version = normalize(rawVersion) else { return .unsupported(version: nil) }
        if version.hasPrefix("0.162.") { return .current(version: version) }
        if version.hasPrefix("0.136.") { return .legacy(version: version) }
        return .unsupported(version: version)
    }

    var version: String? {
        switch self {
        case .current(let version), .legacy(let version): version
        case .unsupported(let version): version
        }
    }

    var identifier: String {
        switch self {
        case .current: "codex_0_162"
        case .legacy: "codex_0_136"
        case .unsupported: "unsupported"
        }
    }

    var hookEvents: [String] {
        switch self {
        case .current:
            ["SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest", "PostToolUse", "Interrupt"]
        case .legacy:
            ["SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest", "PostToolUse"]
        case .unsupported:
            []
        }
    }

    var supportsRichStatus: Bool {
        switch self {
        case .current, .legacy: true
        case .unsupported: false
        }
    }

    static func normalize(_ rawVersion: String?) -> String? {
        guard let rawVersion else { return nil }
        let trimmed = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:codex(?:-cli)?\s+)?v?(\d+\.\d+\.\d+)(?:\s|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = expression.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)),
            let versionRange = Range(match.range(at: 1), in: trimmed)
        else { return nil }
        return String(trimmed[versionRange])
    }

    static func detect(
        shell: String,
        workingDirectory: String? = nil,
        environment: [String] = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" },
        timeout: TimeInterval = 2
    ) -> CodexCompatibilityAdapter {
        let process = Process()
        let output = Pipe()
        let capturedOutput = CodexVersionOutputBuffer()
        let outputReaderFinished = DispatchSemaphore(value: 0)
        let marker = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let startMarker = "AGENT_SESSION_MANAGER_CODEX_VERSION_BEGIN_\(marker)"
        let endMarker = "AGENT_SESSION_MANAGER_CODEX_VERSION_END_\(marker)"
        process.executableURL = URL(filePath: shell)
        process.arguments = [
            "-i", "-c",
            "printf '\\n\(startMarker)\\n'; codex --version; codex_status=$?; printf '\\n\(endMarker)\\n'; exit \"$codex_status\"",
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.environment = Dictionary(
            environment.compactMap { entry -> (String, String)? in
                guard let separator = entry.firstIndex(of: "=") else { return nil }
                return (String(entry[..<separator]), String(entry[entry.index(after: separator)...]))
            },
            uniquingKeysWith: { _, new in new })
        if let workingDirectory { process.currentDirectoryURL = URL(filePath: workingDirectory) }
        do {
            try process.run()
        } catch {
            return .unsupported(version: nil)
        }
        DispatchQueue.global(qos: .utility).async {
            defer { outputReaderFinished.signal() }
            while let chunk = try? output.fileHandleForReading.read(upToCount: 256), !chunk.isEmpty {
                capturedOutput.lock.lock()
                capturedOutput.data.append(chunk)
                if capturedOutput.data.count > 8192 {
                    capturedOutput.data.removeFirst(capturedOutput.data.count - 8192)
                }
                capturedOutput.lock.unlock()
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
        _ = outputReaderFinished.wait(timeout: .now() + 0.1)
        guard process.terminationStatus == 0 else { return .unsupported(version: nil) }
        capturedOutput.lock.lock()
        let outputText = String(decoding: capturedOutput.data, as: UTF8.self)
        capturedOutput.lock.unlock()
        let lines = outputText.split(whereSeparator: \.isNewline).map(String.init)
        guard let startIndex = lines.firstIndex(of: startMarker),
            let endIndex = lines.dropFirst(startIndex + 1).firstIndex(of: endMarker),
            let line = lines[(startIndex + 1)..<endIndex].first(where: {
                $0.range(of: #"^codex(?:-cli)?\s+\d+\.\d+\.\d+(?:\s|$)"#, options: .regularExpression) != nil
            })
        else { return .unsupported(version: nil) }
        return select(line)
    }

    func unsupportedBuiltinOption(
        in arguments: [String],
        catalog: [CLIOptionConfig]
    ) -> (name: String, value: String)? {
        guard case .current = self else { return nil }
        let builtinEnabled = catalog.contains { $0.id == "--ask-for-approval" && !$0.isUserAdded }
        let customEnabled = catalog.contains {
            $0.id == "--ask-for-approval" && $0.isUserAdded && $0.isAvailable
        }
        guard builtinEnabled, !customEnabled else { return nil }
        for index in arguments.indices {
            if arguments[index] == "--ask-for-approval" {
                let valueIndex = arguments.index(after: index)
                if valueIndex < arguments.endIndex, arguments[valueIndex] == "untrusted" {
                    return ("--ask-for-approval", "untrusted")
                }
            } else if arguments[index] == "--ask-for-approval=untrusted" {
                return ("--ask-for-approval", "untrusted")
            }
        }
        return nil
    }
}

struct CodexHookQueueRecord: Codable, Equatable, Sendable {
    let paneID: String
    let tabID: String
    let launchGeneration: String
    let hookEventName: String
    let sessionID: String?
    let turnID: String?
    let requestID: String?
    let timestamp: Double
    let source: String
    let model: String?
    let transcriptPath: String?
    let result: String?

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case tabID = "tab_id"
        case launchGeneration = "launch_generation"
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case turnID = "turn_id"
        case requestID = "request_id"
        case timestamp
        case source
        case model
        case transcriptPath = "transcript_path"
        case result
    }
}

struct CodexHookQueueDrain: Equatable {
    let records: [CodexHookQueueRecord]
    let malformedRecordCount: Int
    let partialRecordRetained: Bool
}

enum CodexHookQueueError: Error, Equatable {
    case openFailed
    case lockUnavailable
    case readFailed
    case writeFailed
    case fileTooLarge
}

final class CodexHookQueue {
    let fileURL: URL
    private let maximumBytes: Int

    init(fileURL: URL, maximumBytes: Int = 1_048_576) {
        self.fileURL = fileURL
        self.maximumBytes = maximumBytes
    }

    func drain() throws -> CodexHookQueueDrain {
        let descriptor = fileURL.path.withCString { open($0, O_RDWR | O_CREAT | O_CLOEXEC, 0o600) }
        guard descriptor >= 0 else { throw CodexHookQueueError.openFailed }
        defer { _ = close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw CodexHookQueueError.lockUnavailable }
        defer { _ = flock(descriptor, LOCK_UN) }

        var information = stat()
        guard fstat(descriptor, &information) == 0 else { throw CodexHookQueueError.readFailed }
        guard information.st_size <= maximumBytes else { throw CodexHookQueueError.fileTooLarge }
        var bytes = [UInt8](repeating: 0, count: Int(information.st_size))
        if !bytes.isEmpty {
            let readCount = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            guard readCount == bytes.count else { throw CodexHookQueueError.readFailed }
        }
        let newlineIndices = bytes.indices.filter { bytes[$0] == 0x0A }
        let consumedByteCount = newlineIndices.last.map { $0 + 1 } ?? 0
        let hasPartialRecord = consumedByteCount < bytes.count
        let completeData = Data(bytes.prefix(consumedByteCount))
        let remainder = Data(bytes.dropFirst(consumedByteCount))
        var records: [CodexHookQueueRecord] = []
        var malformedCount = 0
        for line in completeData.split(separator: 0x0A) {
            guard let record = try? JSONDecoder().decode(CodexHookQueueRecord.self, from: Data(line)) else {
                malformedCount += 1
                continue
            }
            records.append(record)
        }
        if consumedByteCount > 0 {
            guard ftruncate(descriptor, 0) == 0 else { throw CodexHookQueueError.writeFailed }
            if !remainder.isEmpty {
                guard lseek(descriptor, 0, SEEK_SET) == 0 else { throw CodexHookQueueError.writeFailed }
                let writeCount = remainder.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
                guard writeCount == remainder.count else { throw CodexHookQueueError.writeFailed }
            }
        }
        return CodexHookQueueDrain(
            records: records,
            malformedRecordCount: malformedCount,
            partialRecordRetained: hasPartialRecord)
    }
}

struct CodexHookDiagnosticRecord: Equatable {
    let kind: String
    let eventName: String
    let result: String
}

final class CodexHookDiagnosticQueue {
    static let maximumBytes = 8192
    private static let allowedEvents = Set([
        "SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest", "PostToolUse", "Interrupt", "unknown",
    ])
    private static let allowedResults = Set(["started", "queue_lock_timeout", "hook_write_failed"])

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func drain() throws -> [CodexHookDiagnosticRecord] {
        let descriptor = fileURL.path.withCString { open($0, O_RDWR | O_CREAT | O_CLOEXEC, 0o600) }
        guard descriptor >= 0 else { throw CodexHookQueueError.openFailed }
        defer { _ = close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw CodexHookQueueError.lockUnavailable }
        defer { _ = flock(descriptor, LOCK_UN) }

        var information = stat()
        guard fstat(descriptor, &information) == 0 else { throw CodexHookQueueError.readFailed }
        guard information.st_size <= Self.maximumBytes else { throw CodexHookQueueError.fileTooLarge }
        var bytes = [UInt8](repeating: 0, count: Int(information.st_size))
        if !bytes.isEmpty {
            let readCount = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            guard readCount == bytes.count else { throw CodexHookQueueError.readFailed }
        }
        var records: [CodexHookDiagnosticRecord] = []
        for line in Data(bytes).split(separator: 0x0A) {
            let fields = line.split(separator: 0x7C, omittingEmptySubsequences: false)
            guard fields.count == 3,
                let kind = String(bytes: fields[0], encoding: .ascii),
                let eventName = String(bytes: fields[1], encoding: .ascii),
                let result = String(bytes: fields[2], encoding: .ascii),
                ["invoked", "failed"].contains(kind),
                Self.allowedEvents.contains(eventName),
                Self.allowedResults.contains(result)
            else { continue }
            records.append(CodexHookDiagnosticRecord(kind: kind, eventName: eventName, result: result))
        }
        guard ftruncate(descriptor, 0) == 0 else { throw CodexHookQueueError.writeFailed }
        return records
    }
}
