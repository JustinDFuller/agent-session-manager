import XCTest

@testable import AgentSessionManager

@MainActor
final class FocusPaneTests: XCTestCase {
    private struct Fixture {
        let state: AppState
        let tab: Tab
        let panes: [Pane]
    }

    private func makeState(paneNames: [String]) -> Fixture {
        let state = AppState()
        let tab = Tab(name: "Work", directory: URL(filePath: "/tmp"))
        let panes = paneNames.map { Pane(name: $0, tab: tab) }
        tab.panes = panes
        state.tabs = [tab]
        state.activeTabID = tab.id
        state.activePaneID = panes.first?.id
        return Fixture(state: state, tab: tab, panes: panes)
    }

    func testFocusPaneRequiresSplitTab() {
        let fixture = makeState(paneNames: ["one"])

        fixture.tab.setFocusedPane(id: fixture.panes[0].id, reason: "test")

        XCTAssertNil(fixture.tab.focusedPaneID)
    }

    func testFocusPaneIgnoresUnknownPane() {
        let fixture = makeState(paneNames: ["one", "two"])

        fixture.tab.setFocusedPane(id: UUID(), reason: "test")

        XCTAssertNil(fixture.tab.focusedPaneID)
    }

    func testFocusPaneCanRestoreGrid() {
        let fixture = makeState(paneNames: ["one", "two"])

        fixture.tab.setFocusedPane(id: fixture.panes[1].id, reason: "test")
        XCTAssertEqual(fixture.tab.focusedPaneID, fixture.panes[1].id)

        fixture.tab.setFocusedPane(id: nil, reason: "test")
        XCTAssertNil(fixture.tab.focusedPaneID)
    }

    func testClosingFocusedPaneRestoresGrid() {
        let fixture = makeState(paneNames: ["one", "two"])
        fixture.tab.setFocusedPane(id: fixture.panes[1].id, reason: "test")

        fixture.tab.closePane(fixture.panes[1])

        XCTAssertNil(fixture.tab.focusedPaneID)
    }

    func testOpeningShellPaneRestoresGrid() {
        let fixture = makeState(paneNames: ["one", "two"])
        fixture.tab.setFocusedPane(id: fixture.panes[1].id, reason: "test")

        fixture.tab.openShellPane(activePane: fixture.panes[1], appState: fixture.state)

        XCTAssertNil(fixture.tab.focusedPaneID)
    }

    func testSwitchingTabsCanRestoreGrid() {
        let fixture = makeState(paneNames: ["one", "two"])
        let secondTab = Tab(name: "Other", directory: URL(filePath: "/tmp"))
        fixture.state.tabs.append(secondTab)
        fixture.tab.setFocusedPane(id: fixture.panes[1].id, reason: "test")

        fixture.state.switchToTab(id: secondTab.id, focusModeTabSwitchBehavior: .showAllPanes)

        XCTAssertNil(fixture.tab.focusedPaneID)
    }

    func testSwitchingTabsRemembersFocusByDefault() {
        let fixture = makeState(paneNames: ["one", "two"])
        let secondTab = Tab(name: "Other", directory: URL(filePath: "/tmp"))
        fixture.state.tabs.append(secondTab)
        fixture.tab.setFocusedPane(id: fixture.panes[1].id, reason: "test")

        fixture.state.switchToTab(id: secondTab.id)

        XCTAssertEqual(fixture.tab.focusedPaneID, fixture.panes[1].id)
    }

    func testSwitchingBackToFocusedTabActivatesFocusedPane() {
        let fixture = makeState(paneNames: ["one", "two"])
        let secondTab = Tab(name: "Other", directory: URL(filePath: "/tmp"))
        fixture.state.tabs.append(secondTab)
        fixture.tab.setFocusedPane(id: fixture.panes[0].id, reason: "test")
        fixture.tab.lastActivePaneID = fixture.panes[1].id

        fixture.state.switchToTab(id: secondTab.id)
        fixture.state.switchToTab(id: fixture.tab.id)

        XCTAssertEqual(fixture.state.activePaneID, fixture.panes[0].id)
    }

    func testNotificationNavigationRestoresGrid() {
        let fixture = makeState(paneNames: ["one", "two"])
        fixture.tab.setFocusedPane(id: fixture.panes[0].id, reason: "test")
        let notification = PaneNotification(
            paneID: fixture.panes[1].id,
            paneName: fixture.panes[1].name,
            tabID: fixture.tab.id,
            tabName: fixture.tab.name,
            isPriority: false
        )
        fixture.state.notifications = [notification]

        fixture.state.acknowledgeNotification(id: notification.id)

        XCTAssertNil(fixture.tab.focusedPaneID)
        XCTAssertEqual(fixture.state.activePaneID, fixture.panes[1].id)
    }

    func testFocusModeTelemetryIncludesPaneContext() {
        let fixture = makeState(paneNames: ["one", "two"])
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        fixture.tab.setFocusedPane(id: fixture.panes[1].id, reason: "test")

        let event = TracingService.shared.recordedEventsForTesting.last
        XCTAssertEqual(event?.name, "pane.focus_mode.changed")
        XCTAssertEqual(event?.attributes["pane.id"], fixture.panes[1].id.uuidString)
        XCTAssertEqual(event?.attributes["pane.name"], fixture.panes[1].name)
        XCTAssertEqual(event?.attributes["tab.id"], fixture.tab.id.uuidString)
        XCTAssertEqual(event?.attributes["tab.name"], fixture.tab.name)
        XCTAssertEqual(event?.attributes["state"], "focused")
        XCTAssertEqual(event?.attributes["reason"], "test")
    }

    func testFocusModeTelemetryReasonIsBounded() {
        let fixture = makeState(paneNames: ["one", "two"])
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        fixture.tab.setFocusedPane(id: fixture.panes[1].id, reason: String(repeating: "x", count: 100))

        XCTAssertEqual(TracingService.shared.recordedEventsForTesting.last?.attributes["reason"]?.count, 64)
    }

    func testNotificationPaneActivationTelemetryIncludesPaneContext() {
        let fixture = makeState(paneNames: ["one", "two"])
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        fixture.state.focusPane(tabID: fixture.tab.id, paneID: fixture.panes[1].id)

        let event = TracingService.shared.recordedEventsForTesting.first { $0.name == "pane.activated" }
        XCTAssertEqual(event?.attributes["pane.id"], fixture.panes[1].id.uuidString)
        XCTAssertEqual(event?.attributes["pane.name"], fixture.panes[1].name)
        XCTAssertEqual(event?.attributes["tab.id"], fixture.tab.id.uuidString)
        XCTAssertEqual(event?.attributes["tab.name"], fixture.tab.name)
    }

    func testFocusModeSettingsDefaults() {
        let settings = AppSettings()

        XCTAssertEqual(settings.focusModeTabSwitchBehavior, .rememberFocus)
        XCTAssertTrue(settings.hideNotificationSidebarWhileFocused)
    }

    func testFocusModeSettingsRoundTrip() {
        let subdirectory = "focus-pane-test-\(UUID().uuidString)"
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        defer {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: appSupport.appending(path: subdirectory))
            PersistenceHelpers.overrideAppSupportSubdirectory = nil
        }
        let settings = AppSettings()
        settings.focusModeTabSwitchBehavior = .showAllPanes
        settings.hideNotificationSidebarWhileFocused = false

        SettingsPersistence.saveFocusModeSettings(appSettings: settings)
        let restored = SettingsPersistence.load(
            SettingsPersistence.FocusModeConfig.self,
            from: "focus-mode-settings.json"
        )

        XCTAssertEqual(restored?.tabSwitchBehavior, .showAllPanes)
        XCTAssertFalse(restored?.hideNotificationSidebar ?? true)
    }
}
