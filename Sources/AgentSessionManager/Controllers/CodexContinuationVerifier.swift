import Foundation

enum CodexSessionAccess: Equatable {
    case available
    case missing
    case inaccessible
}

struct CodexContinuationVerifier {
    static func check(
        sessionID: String,
        transcriptPath: String?,
        shell: String,
        workingDirectory: String,
        environment: [String: String]
    ) -> CodexSessionAccess {
        let store = CodexStateStore(
            databaseURL: CodexHomeResolver.databaseURL(
                shell: shell, workingDirectory: workingDirectory, environment: environment))
        do {
            guard let thread = try store.selectThread(sessionID: sessionID, rolloutPath: nil),
                thread.id == sessionID, !thread.isArchived,
                let threadCWD = thread.cwd,
                URL(filePath: threadCWD).standardizedFileURL.path
                    == URL(filePath: workingDirectory).standardizedFileURL.path,
                let rolloutPath = thread.rolloutPath
            else { return .missing }
            guard transcriptPath == nil || transcriptPath == rolloutPath,
                FileManager.default.fileExists(atPath: rolloutPath)
            else { return .missing }
            return .available
        } catch {
            return .inaccessible
        }
    }
}
