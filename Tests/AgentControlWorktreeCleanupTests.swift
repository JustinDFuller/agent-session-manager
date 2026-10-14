import Foundation
import MCP
import XCTest

@testable import AgentSessionManager

@MainActor
final class AgentControlWorktreeCleanupTests: XCTestCase {
    private let testDirectory = "agent-control-cleanup-tests-\(UUID().uuidString)"
    private var repository: GitTestRepository!
    private var state: AppState!
    private var settings: AppSettings!
    private var tab: Tab!
    private var router: AgentControlMutationRouter!
    private var source: AgentControlSource!

    override func setUpWithError() throws {
        PersistenceHelpers.overrideAppSupportSubdirectory = testDirectory
        repository = try GitTestRepository.make()
        state = AppState()
        settings = AppSettings()
        settings.worktreeCleanupBehavior = .delete
        tab = Tab(name: "Repo", directory: repository.root)
        state.tabs = [tab]
        state.activeTabID = tab.id
        router = AgentControlMutationRouter(appState: state, appSettings: settings)
        source = AgentControlSource(
            paneID: UUID(), paneName: "agent", tabID: tab.id, tabName: tab.name, scope: .global)
    }

    override func tearDown() {
        repository.cleanUp()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: base.appending(path: testDirectory))
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        super.tearDown()
    }

    private func managedPane(_ name: String) throws -> (Pane, URL) {
        let checkout = try repository.addManagedWorktree(name: name)
        let pane = tab.addPane(
            name: name, harness: .claude, worktreeDirectory: checkout, worktreeIsManaged: true, appSettings: settings)
        return (pane, checkout)
    }

    private func call(_ tool: String, _ arguments: [String: MCP.Value]) async throws -> AgentControlMutationResult {
        let response = try await router.callTool(name: tool, arguments: arguments, source: source)
        guard case .text(let text, _, _) = response.content.first else {
            throw XCTSkip("Tool returned no text")
        }
        return try JSONDecoder().decode(AgentControlMutationResult.self, from: Data(text.utf8))
    }

    func testDeletingCleanPaneRemovesWorktreeAndBranch() async throws {
        let (pane, checkout) = try managedPane("clean-pane")
        let result = try await call("panes_delete", ["paneID": .string(pane.id.uuidString)])
        XCTAssertEqual(result.status, "succeeded")
        XCTAssertEqual(result.cleanup.map(\.status), ["deleted"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertFalse(try repository.branches().contains("clean-pane"))
    }

    func testDeletingPaneWithModifiedFilesKeepsWorktreeWithReason() async throws {
        let (pane, checkout) = try managedPane("dirty-pane")
        try "change".write(to: checkout.appending(path: "dirty.txt"), atomically: true, encoding: .utf8)
        let result = try await call("panes_delete", ["paneID": .string(pane.id.uuidString)])
        XCTAssertEqual(result.status, "succeeded")
        XCTAssertEqual(result.cleanup.map(\.status), ["kept"])
        XCTAssertEqual(result.cleanup.first?.error, "It has unsaved work: 1 untracked file.")
        XCTAssertTrue(tab.panes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertTrue(try repository.branches().contains("dirty-pane"))
    }

    func testDeletingPaneWithUnpushedCommitsKeepsWorktree() async throws {
        let (pane, checkout) = try managedPane("unpushed-pane")
        try repository.commit("local only", in: checkout)
        let result = try await call("panes_delete", ["paneID": .string(pane.id.uuidString)])
        XCTAssertEqual(result.cleanup.map(\.status), ["kept"])
        XCTAssertEqual(
            result.cleanup.first?.error, "It has unsaved work: 1 commit not on any remote on unpushed-pane.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testDeletingPaneKeepsWorktreeAnotherPaneUses() async throws {
        let (pane, checkout) = try managedPane("shared-pane")
        _ = tab.addPane(
            name: "shell:shared-pane", harness: .shell, worktreeDirectory: checkout, worktreeIsManaged: false,
            appSettings: settings)
        let result = try await call("panes_delete", ["paneID": .string(pane.id.uuidString)])
        XCTAssertEqual(result.cleanup.map(\.status), ["kept"])
        XCTAssertEqual(result.cleanup.first?.error, WorktreeCloseFlow.inUseReason)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testDeletingPaneKeepsBranchWhenSettingIsOff() async throws {
        settings.deleteBranchWithWorktree = false
        let (pane, checkout) = try managedPane("branch-stays")
        let result = try await call("panes_delete", ["paneID": .string(pane.id.uuidString)])
        XCTAssertEqual(result.cleanup.map(\.status), ["deleted"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
        XCTAssertTrue(try repository.branches().contains("branch-stays"))
    }

    func testKeepDecisionNeverDeletes() async throws {
        settings.worktreeCleanupBehavior = .ask
        let (pane, checkout) = try managedPane("keep-pane")
        let result = try await call(
            "panes_delete", ["paneID": .string(pane.id.uuidString), "cleanup": .string("keep")])
        XCTAssertEqual(result.cleanup.map(\.status), ["kept"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testDeletingTabReportsEachWorktreeAndNeverDeletesUnsavedWork() async throws {
        let (cleanPane, cleanCheckout) = try managedPane("tab-clean")
        let (dirtyPane, dirtyCheckout) = try managedPane("tab-dirty")
        try "change".write(to: dirtyCheckout.appending(path: "dirty.txt"), atomically: true, encoding: .utf8)
        let result = try await call("tabs_delete", ["tabID": .string(tab.id.uuidString)])
        let byPane = Dictionary(uniqueKeysWithValues: result.cleanup.map { ($0.paneID, $0) })
        XCTAssertEqual(byPane[cleanPane.id]?.status, "deleted")
        XCTAssertEqual(byPane[dirtyPane.id]?.status, "kept")
        XCTAssertNotNil(byPane[dirtyPane.id]?.error)
        XCTAssertTrue(state.tabs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanCheckout.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyCheckout.path))
    }

    func testDeletingTabWithTwoPanesOnOneCheckoutReportsBothAgainstOneRemoval() async throws {
        let (first, checkout) = try managedPane("twin")
        let second = tab.addPane(
            name: "twin-2", harness: .codex, worktreeDirectory: checkout, worktreeIsManaged: true,
            appSettings: settings)
        let result = try await call("tabs_delete", ["tabID": .string(tab.id.uuidString)])
        XCTAssertEqual(Set(result.cleanup.map(\.paneID)), [first.id, second.id])
        XCTAssertEqual(Set(result.cleanup.map(\.status)), ["deleted"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkout.path))
    }

    func testLockedWorktreeReportsFailure() async throws {
        let (pane, checkout) = try managedPane("locked-pane")
        _ = try repository.git(["worktree", "lock", checkout.path])
        let result = try await call("panes_delete", ["paneID": .string(pane.id.uuidString)])
        XCTAssertEqual(result.status, "partial_failure")
        XCTAssertEqual(result.cleanup.map(\.status), ["failed"])
        XCTAssertNotNil(result.cleanup.first?.error)
    }

    func testUnmanagedPaneReportsNoCleanup() async throws {
        let pane = tab.addPane(
            name: "plain", harness: .claude, worktreeDirectory: repository.root, worktreeIsManaged: false,
            appSettings: settings)
        let result = try await call("panes_delete", ["paneID": .string(pane.id.uuidString)])
        XCTAssertTrue(result.cleanup.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.root.path))
    }
}
