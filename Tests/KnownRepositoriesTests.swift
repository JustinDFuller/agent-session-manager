import XCTest

@testable import AgentSessionManager

@MainActor
final class KnownRepositoriesTests: XCTestCase {
    private let subdirectory = "known-repositories-tests-\(UUID().uuidString)"
    private var scratch: URL!

    private var storageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: subdirectory)
    }

    override func setUpWithError() throws {
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        scratch = FileManager.default.temporaryDirectory
            .appending(path: "known-repos-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storageDirectory)
        try? FileManager.default.removeItem(at: scratch)
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        super.tearDown()
    }

    private func folder(_ name: String) throws -> URL {
        let url = scratch.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testLoadIsEmptyWithoutAFile() {
        XCTAssertTrue(KnownRepositories.load().isEmpty)
    }

    func testRecordAddsRootsOnceEach() throws {
        let first = try folder("first")
        let second = try folder("second")
        KnownRepositories.record([first, second])
        KnownRepositories.record([first])
        XCTAssertEqual(KnownRepositories.load().map(\.path), [first.path, second.path])
    }

    func testRefreshDropsFoldersThatNoLongerExist() throws {
        let kept = try folder("kept")
        let gone = try folder("gone")
        KnownRepositories.record([kept, gone])
        try FileManager.default.removeItem(at: gone)
        KnownRepositories.refresh(with: [])
        XCTAssertEqual(KnownRepositories.load().map(\.path), [kept.path])
    }

    func testRecordKeepsMissingFoldersUntilTheNextRefresh() throws {
        let gone = try folder("gone")
        KnownRepositories.record([gone])
        try FileManager.default.removeItem(at: gone)
        KnownRepositories.record([])
        XCTAssertEqual(KnownRepositories.load().map(\.path), [gone.path])
    }

    func testFirstRefreshSeedsFromRestoredTabs() throws {
        let alpha = try folder("alpha")
        let beta = try folder("beta")
        KnownRepositories.refresh(with: [alpha, beta])
        XCTAssertEqual(KnownRepositories.load().map(\.path), [alpha.path, beta.path])
    }

    func testCorruptFileIsIgnoredAndReplaced() throws {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: storageDirectory.appending(path: "known-repositories.json"))
        XCTAssertTrue(KnownRepositories.load().isEmpty)
        let repo = try folder("repo")
        KnownRepositories.record([repo])
        XCTAssertEqual(KnownRepositories.load().map(\.path), [repo.path])
    }

    func testCorruptFileDoesNotAffectOtherPersistence() throws {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: storageDirectory.appending(path: "known-repositories.json"))
        let settings = AppSettings()
        XCTAssertTrue(settings.cleanUpLeftoversAtLaunch)
        XCTAssertTrue(settings.deleteBranchWithWorktree)
    }
}
