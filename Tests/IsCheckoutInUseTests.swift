import XCTest

@testable import AgentSessionManager

@MainActor
final class IsCheckoutInUseTests: XCTestCase {
    func testSelfMatchExcluded() {
        let state = AppState()
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        state.tabs.append(tab)

        let pane = tab.addPaneWithLoadingState(name: "feature", harness: .claude, worktreeIsManaged: true)
        let checkout = Tab.worktreeDirectoryURL(repoRoot: tab.directory, name: "feature")

        XCTAssertFalse(
            state.isCheckoutInUse(directory: tab.directory, checkout: checkout, excludingPaneIDs: [pane.id]),
            "Loading pane must not match itself"
        )
    }

    func testDifferentPaneStillDetected() {
        let state = AppState()
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        state.tabs.append(tab)

        let pane = tab.addPaneWithLoadingState(name: "feature", harness: .claude, worktreeIsManaged: true)
        let checkout = Tab.worktreeDirectoryURL(repoRoot: tab.directory, name: "feature")
        let unrelatedID = UUID()

        XCTAssertTrue(
            state.isCheckoutInUse(directory: tab.directory, checkout: checkout, excludingPaneIDs: [unrelatedID]),
            "A different pane that owns the same checkout must still be detected"
        )
        _ = pane
    }

    func testDefaultBehaviorWithoutExclusion() {
        let state = AppState()
        let tab = Tab(name: "repo", directory: URL(filePath: "/repo"))
        state.tabs.append(tab)

        let pane = tab.addPaneWithLoadingState(name: "feature", harness: .claude, worktreeIsManaged: true)
        let checkout = Tab.worktreeDirectoryURL(repoRoot: tab.directory, name: "feature")

        XCTAssertTrue(
            state.isCheckoutInUse(directory: tab.directory, checkout: checkout),
            "Without exclusion the loading pane must match (backward-compatible behavior)"
        )
        _ = pane
    }
}
