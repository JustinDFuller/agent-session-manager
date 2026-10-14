import XCTest

@testable import AgentSessionManager

@MainActor
final class AppStateTabFocusTests: XCTestCase {
    private func makeState(tabs: [(name: String, paneNames: [String])]) -> (AppState, [[Pane]]) {
        let state = AppState()
        let url = URL(filePath: "/tmp")
        var allPanes: [[Pane]] = []
        for tabSpec in tabs {
            let tab = Tab(name: tabSpec.name, directory: url)
            let panes = tabSpec.paneNames.map { Pane(name: $0, tab: tab) }
            tab.panes = panes
            state.tabs.append(tab)
            allPanes.append(panes)
        }
        return (state, allPanes)
    }

    func testSwitchTabFallsBackToFirstPane() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a", "b"]),
            (name: "tab2", paneNames: ["c", "d"]),
        ])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][1].id

        state.switchToTab(id: state.tabs[1].id)

        XCTAssertEqual(state.activePaneID, panes[1][0].id)
    }

    func testSwitchTabRestoresLastActivePaneID() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a", "b"]),
            (name: "tab2", paneNames: ["c", "d"]),
        ])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][1].id

        state.switchToTab(id: state.tabs[1].id)
        state.setActivePane(id: panes[1][1].id)

        state.switchToTab(id: state.tabs[0].id)
        XCTAssertEqual(state.activePaneID, panes[0][1].id)

        state.switchToTab(id: state.tabs[1].id)
        XCTAssertEqual(state.activePaneID, panes[1][1].id)
    }

    func testSetActivePaneUpdatesLastActivePaneID() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a", "b"])
        ])
        state.activeTabID = state.tabs[0].id

        state.setActivePane(id: panes[0][1].id)

        XCTAssertEqual(state.activePaneID, panes[0][1].id)
        XCTAssertEqual(state.tabs[0].lastActivePaneID, panes[0][1].id)
    }

    func testNewPaneBecomesActivePane() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a"])
        ])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][0].id

        let newPane = Pane(name: "b", tab: state.tabs[0])
        state.tabs[0].panes.append(newPane)
        state.setActivePane(id: state.tabs[0].panes.last?.id)

        XCTAssertEqual(state.activePaneID, newPane.id)
        XCTAssertEqual(state.tabs[0].lastActivePaneID, newPane.id)
    }

    func testFocusPaneSwitchesTabAndActivePane() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a", "b"]),
            (name: "tab2", paneNames: ["c", "d"]),
        ])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][0].id

        state.focusPane(tabID: state.tabs[1].id, paneID: panes[1][1].id)

        XCTAssertEqual(state.activeTabID, state.tabs[1].id)
        XCTAssertEqual(state.activePaneID, panes[1][1].id)
    }

    func testSwitchTabIgnoresInvalidLastActivePaneID() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a", "b"]),
            (name: "tab2", paneNames: ["c"]),
        ])
        state.activeTabID = state.tabs[1].id
        state.activePaneID = panes[1][0].id

        state.tabs[0].lastActivePaneID = UUID()

        state.switchToTab(id: state.tabs[0].id)

        XCTAssertEqual(state.activePaneID, panes[0][0].id)
    }

    func testIsCheckoutInUseExternalPath() {
        let state = AppState()
        let repo = URL(filePath: "/tmp/myproject")
        let tab = Tab(name: "t", directory: repo)
        let external = URL(filePath: "/tmp/sibling-wt")
        tab.panes = [Pane(name: "sibling-wt", tab: tab, worktreeDirectory: external)]
        state.tabs = [tab]

        XCTAssertTrue(state.isCheckoutInUse(checkout: external))
        XCTAssertFalse(state.isCheckoutInUse(checkout: URL(filePath: "/tmp/other")))
    }

    func testIsCheckoutInUseManagedWorktreePath() {
        let state = AppState()
        let repo = URL(filePath: "/tmp/myproject")
        let tab = Tab(name: "t", directory: repo)
        tab.panes = [Pane(name: "feat", tab: tab)]
        state.tabs = [tab]
        let managed = Tab.worktreeDirectoryURL(repoRoot: repo, name: "feat")

        XCTAssertTrue(state.isCheckoutInUse(checkout: managed))
    }

    func testCloseTabRemovesTabAndFallsBackActiveTabID() {
        let (state, _) = makeState(tabs: [
            (name: "tab1", paneNames: ["a"]),
            (name: "tab2", paneNames: ["b"]),
        ])
        state.activeTabID = state.tabs[0].id

        state.closeTab(state.tabs[0])

        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.tabs[0].name, "tab2")
        XCTAssertEqual(state.activeTabID, state.tabs[0].id)
    }

    func testNavigateToTerminalBellNotificationSwitchesTabAndPane() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a"]),
            (name: "tab2", paneNames: ["b"]),
        ])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][0].id

        let notification = PaneNotification(
            paneID: panes[1][0].id,
            paneName: "b",
            tabID: state.tabs[1].id,
            tabName: "tab2",
            isPriority: false
        )
        state.notifications = [notification]
        state.acknowledgeNotification(id: notification.id)

        XCTAssertEqual(state.activeTabID, state.tabs[1].id)
        XCTAssertEqual(state.activePaneID, panes[1][0].id)
    }

    func testNavigateToPRMergedNotificationSwitchesTabAndPane() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a"]),
            (name: "tab2", paneNames: ["b"]),
        ])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][0].id

        let notification = PaneNotification(
            paneID: panes[1][0].id,
            paneName: "b",
            tabID: state.tabs[1].id,
            tabName: "tab2",
            isPriority: false,
            kind: .prMerged,
            prNumber: 42,
            prTitle: "My PR"
        )
        state.notifications = [notification]
        state.acknowledgeNotification(id: notification.id)

        XCTAssertEqual(state.activeTabID, state.tabs[1].id)
        XCTAssertEqual(state.activePaneID, panes[1][0].id)
    }

    func testCloseLastTabLeavesEmptyState() {
        let (state, _) = makeState(tabs: [
            (name: "tab1", paneNames: ["a"])
        ])
        state.activeTabID = state.tabs[0].id

        state.closeTab(state.tabs[0])

        XCTAssertTrue(state.tabs.isEmpty)
        XCTAssertNil(state.activeTabID)
    }

    func testCloseInactiveTabPreservesActiveTabID() {
        let (state, _) = makeState(tabs: [
            (name: "tab1", paneNames: ["a"]),
            (name: "tab2", paneNames: ["b"]),
        ])
        state.activeTabID = state.tabs[1].id

        state.closeTab(state.tabs[0])

        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.tabs[0].name, "tab2")
        XCTAssertEqual(state.activeTabID, state.tabs[0].id)
    }
}
