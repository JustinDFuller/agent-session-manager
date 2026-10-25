import Foundation
import SwiftTerm

enum ProcessEnvironment {
    nonisolated static func dictionary(from env: [String]) -> [String: String] {
        var values: [String: String] = [:]
        for entry in env {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            values[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
        }
        return values
    }

    nonisolated static func sanitize(
        _ env: [String],
        etcDirectory: String = "/etc",
        fileManager: FileManager = .default
    ) -> [String] {
        var values: [String: String] = [:]
        for entry in env {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<separator])
            let value = String(entry[entry.index(after: separator)...])
            values[key] = value
        }

        for baseline in swiftTermBaseline() {
            guard let separator = baseline.firstIndex(of: "=") else { continue }
            let key = String(baseline[..<separator])
            let value = String(baseline[baseline.index(after: separator)...])
            if values[key] == nil {
                values[key] = value
            }
        }

        let currentPath = values["PATH"] ?? ""
        values["PATH"] = mergedPATH(
            currentPath: currentPath,
            defaultEntries: defaultPATHEntries(etcDirectory: etcDirectory, fileManager: fileManager))

        return values.map { "\($0.key)=\($0.value)" }
    }

    nonisolated static func swiftTermBaseline() -> [String] {
        Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
    }

    nonisolated static func defaultPATHEntries(
        etcDirectory: String = "/etc",
        fileManager: FileManager = .default
    ) -> [String] {
        let pathsFile = (etcDirectory as NSString).appendingPathComponent("paths")
        let pathsDir = (etcDirectory as NSString).appendingPathComponent("paths.d")

        var entries: [String] = []

        if let content = try? String(contentsOfFile: pathsFile, encoding: .utf8) {
            entries.append(contentsOf: parsePATHLines(content))
        }

        if let files = try? fileManager.contentsOfDirectory(atPath: pathsDir) {
            for file in files.sorted() {
                let fullPath = (pathsDir as NSString).appendingPathComponent(file)
                if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                    entries.append(contentsOf: parsePATHLines(content))
                }
            }
        }

        return entries.isEmpty ? fallbackPATHEntries : entries
    }

    nonisolated static func parsePATHLines(_ content: String) -> [String] {
        content
            .split(whereSeparator: { $0.isNewline || $0 == " " || $0 == ":" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func mergedPATH(currentPath: String, defaultEntries: [String]) -> String {
        let currentParts = currentPath.split(separator: ":", omittingEmptySubsequences: true)
            .map { String($0) }

        var seen = Set<String>()
        var result: [String] = []

        for entry in defaultEntries where !seen.contains(entry) {
            result.append(entry)
            seen.insert(entry)
        }

        for entry in currentParts where !seen.contains(entry) {
            result.append(entry)
            seen.insert(entry)
        }

        return result.joined(separator: ":")
    }

    static let fallbackPATHEntries: [String] = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/go/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]
}
