import XCTest

@testable import AgentSessionManager

@MainActor
final class WorktreeCleanupSettingsTests: XCTestCase {
    private var subdirectory = ""
    private var supportDirectory: URL!

    override func setUpWithError() throws {
        subdirectory = "agent-session-manager-cleanup-settings-\(UUID().uuidString)"
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDirectory = base.appending(path: subdirectory, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
    }

    override func tearDown() {
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        try? FileManager.default.removeItem(at: supportDirectory)
        super.tearDown()
    }

    func testBothSettingsDefaultToOn() {
        let settings = AppSettings()
        XCTAssertTrue(settings.deleteBranchWithWorktree)
        XCTAssertTrue(settings.cleanUpLeftoversAtLaunch)
    }

    func testLoadWithoutFilesKeepsDefaults() {
        let settings = AppSettings()
        SettingsPersistence.loadWorktreeCleanupFlags(into: settings)
        XCTAssertTrue(settings.deleteBranchWithWorktree)
        XCTAssertTrue(settings.cleanUpLeftoversAtLaunch)
    }

    func testRoundTripOffValues() {
        SettingsPersistence.save(false, to: SettingsPersistence.deleteBranchWithWorktreeFile)
        SettingsPersistence.save(false, to: SettingsPersistence.cleanUpLeftoversAtLaunchFile)
        let settings = AppSettings()
        SettingsPersistence.loadWorktreeCleanupFlags(into: settings)
        XCTAssertFalse(settings.deleteBranchWithWorktree)
        XCTAssertFalse(settings.cleanUpLeftoversAtLaunch)
    }

    func testSettingsPersistIndependently() {
        SettingsPersistence.save(false, to: SettingsPersistence.cleanUpLeftoversAtLaunchFile)
        let settings = AppSettings()
        SettingsPersistence.loadWorktreeCleanupFlags(into: settings)
        XCTAssertTrue(settings.deleteBranchWithWorktree)
        XCTAssertFalse(settings.cleanUpLeftoversAtLaunch)
    }

    func testInvalidFileIsIsolatedToItsOwnSetting() throws {
        try Data("not json".utf8).write(
            to: supportDirectory.appending(path: SettingsPersistence.deleteBranchWithWorktreeFile))
        SettingsPersistence.save(false, to: SettingsPersistence.cleanUpLeftoversAtLaunchFile)
        let settings = AppSettings()
        SettingsPersistence.loadWorktreeCleanupFlags(into: settings)
        XCTAssertTrue(settings.deleteBranchWithWorktree)
        XCTAssertFalse(settings.cleanUpLeftoversAtLaunch)
    }

    func testSettingsFilesDoNotTouchWorktreeCleanupBehaviorFile() {
        SettingsPersistence.save(WorktreeCleanupBehavior.delete, to: "worktree-cleanup.json")
        SettingsPersistence.save(false, to: SettingsPersistence.deleteBranchWithWorktreeFile)
        XCTAssertEqual(
            SettingsPersistence.load(WorktreeCleanupBehavior.self, from: "worktree-cleanup.json"), .delete)
    }

    func testResetListsAndUITestInventoryNameTheNewFiles() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let makefile = try String(contentsOf: root.appending(path: "Makefile"), encoding: .utf8)
        let inventory = try String(
            contentsOf: root.appending(path: "UITests/Helpers/BaseTestCase.swift"), encoding: .utf8)
        for file in [
            SettingsPersistence.deleteBranchWithWorktreeFile,
            SettingsPersistence.cleanUpLeftoversAtLaunchFile,
            "known-repositories.json",
        ] {
            XCTAssertEqual(makefile.components(separatedBy: file).count - 1, 2, "\(file) in Makefile reset lists")
            XCTAssertTrue(inventory.contains("\"\(file)\""), "\(file) in UI test inventory")
        }
    }
}
