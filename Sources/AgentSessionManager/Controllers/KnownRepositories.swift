import Foundation

enum KnownRepositories {
    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appending(path: PersistenceHelpers.appSupportSubdirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "known-repositories.json")
    }

    static func load() -> [URL] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return paths.map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    static func record(_ directories: [URL]) {
        merge(adding: directories, dropMissing: false)
    }

    static func refresh(with directories: [URL]) {
        merge(adding: directories, dropMissing: true)
    }

    private static func merge(adding directories: [URL], dropMissing: Bool) {
        var seen: Set<String> = []
        var paths: [String] = []
        let candidates = load() + directories
        for directory in candidates {
            let path = directory.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            if dropMissing, !FileManager.default.fileExists(atPath: path) { continue }
            paths.append(path)
        }
        guard let data = try? JSONEncoder().encode(paths) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
