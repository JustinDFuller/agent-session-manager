import SwiftTerm
import XCTest

@testable import AgentSessionManager

@MainActor
final class TerminalScrollbackTests: XCTestCase {
    func testTerminalExposesAnAccessibleInteractionSurface() {
        let controller = TerminalController()
        XCTAssertTrue(controller.terminalView.isAccessibilityElement())
        XCTAssertEqual(controller.terminalView.accessibilityRole(), .group)
        XCTAssertEqual(controller.terminalView.accessibilityLabel(), "Terminal")
    }

    func testDefaultScrollbackIs5000() {
        let settings = AppSettings()
        XCTAssertEqual(settings.defaultScrollback, .finite(5_000))
        XCTAssertEqual(settings.defaultScrollback.resolvedLines, 5_000)
    }

    func testFiniteLimitsClampToSafeRange() {
        XCTAssertEqual(
            ScrollbackLimit(finiteLines: 1).resolvedLines,
            ScrollbackLimit.minimumLines
        )
        XCTAssertEqual(
            ScrollbackLimit(finiteLines: 1_000_000).resolvedLines,
            ScrollbackLimit.maximumFiniteLines
        )
    }

    func testUnlimitedUsesMemoryCap() {
        XCTAssertEqual(ScrollbackLimit.unlimited.resolvedLines, 50_000)
        XCTAssertEqual(ScrollbackLimit.unlimited.modeName, "unlimited")
    }

    func testHighCapacityTerminalResizeRemainsResponsive() {
        let controller = TerminalController()
        let terminal = controller.terminalView.getTerminal()
        controller.terminalView.changeScrollback(ScrollbackLimit.maximumFiniteLines)
        terminal.feed(text: "ready\n")

        let elapsed = ContinuousClock().measure {
            for iteration in 0..<50 {
                terminal.resize(cols: iteration.isMultiple(of: 2) ? 160 : 80, rows: 25)
            }
        }

        XCTAssertLessThan(
            elapsed,
            .seconds(1),
            "Resizing must scale with populated terminal lines, not scrollback capacity"
        )
    }

    func testScrollbackLimitRoundTrips() throws {
        for limit in [ScrollbackLimit.finite(2_000), .unlimited] {
            let data = try JSONEncoder().encode(limit)
            XCTAssertEqual(try JSONDecoder().decode(ScrollbackLimit.self, from: data), limit)
        }
    }

    func testFiniteDecodeNormalizesOutOfRangeValue() throws {
        let data = Data(#"{"mode":"finite","lines":1000000}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(ScrollbackLimit.self, from: data),
            .finite(ScrollbackLimit.maximumFiniteLines)
        )
    }

    func testInvalidModeFailsDecoding() {
        let data = Data(#"{"mode":"forever"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScrollbackLimit.self, from: data))
    }

    func testTerminalSettingsMigratesLegacyFiniteValue() throws {
        let data = Data(#"{"scrollbackLines":2000}"#.utf8)
        let decoded = try JSONDecoder().decode(SettingsPersistence.TerminalSettings.self, from: data)
        XCTAssertEqual(decoded.scrollback, .finite(2_000))
    }

    func testTerminalSettingsRoundTripsFiniteAndUnlimited() throws {
        for limit in [ScrollbackLimit.finite(2_000), .unlimited] {
            let settings = SettingsPersistence.TerminalSettings(scrollback: limit)
            let data = try JSONEncoder().encode(settings)
            let decoded = try JSONDecoder().decode(SettingsPersistence.TerminalSettings.self, from: data)
            XCTAssertEqual(decoded.scrollback, limit)
            XCTAssertNil(String(data: data, encoding: .utf8)?.range(of: "scrollbackLines"))
        }
    }

    func testMissingTerminalSettingsValueUsesDefault() throws {
        let decoded = try JSONDecoder().decode(
            SettingsPersistence.TerminalSettings.self,
            from: Data("{}".utf8)
        )
        XCTAssertEqual(decoded.scrollback, .defaultValue)
    }

    func testPaneScrollbackOverrideRoundTrips() throws {
        let persisted = PersistedPane(
            id: UUID(),
            name: "history",
            harness: .cursor,
            scrollbackOverride: .unlimited
        )

        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: data)

        XCTAssertEqual(decoded.scrollbackOverride, .unlimited)
    }

    func testLegacyPaneWithoutScrollbackOverrideInheritsGlobalDefault() throws {
        let persisted = PersistedPane(
            id: UUID(),
            name: "legacy",
            harness: .claude,
            scrollbackOverride: .finite(2_000)
        )
        let encoded = try JSONEncoder().encode(persisted)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "scrollbackOverride")

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: data)

        XCTAssertNil(decoded.scrollbackOverride)
    }

    func testInvalidPaneScrollbackOverrideFallsBackToGlobalDefault() throws {
        let persisted = PersistedPane(
            id: UUID(),
            name: "invalid",
            harness: .codex
        )
        let encoded = try JSONEncoder().encode(persisted)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["scrollbackOverride"] = ["mode": "forever"]

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: data)

        XCTAssertNil(decoded.scrollbackOverride)
    }

    func testPaneOverrideWinsOverGlobalDefault() {
        let settings = AppSettings()
        settings.defaultScrollback = .finite(8_000)
        let tab = Tab(
            name: "history",
            directory: FileManager.default.temporaryDirectory
        )
        let pane = Pane(
            name: "pane",
            tab: tab,
            scrollbackOverride: nil,
            appSettings: settings
        )

        XCTAssertEqual(pane.effectiveScrollback, .finite(8_000))
        pane.scrollbackOverride = .finite(2_000)
        XCTAssertEqual(pane.effectiveScrollback, .finite(2_000))
        pane.scrollbackOverride = .unlimited
        XCTAssertEqual(pane.effectiveScrollback, .unlimited)
    }

    func testSessionSnapshotIncludesPaneScrollbackOverride() throws {
        let settings = AppSettings()
        let tab = Tab(
            name: "history",
            directory: FileManager.default.temporaryDirectory
        )
        let pane = Pane(
            name: "pane",
            tab: tab,
            harness: .cursor,
            scrollbackOverride: .unlimited,
            appSettings: settings
        )
        tab.panes.append(pane)
        let appState = AppState()
        appState.tabs = [tab]

        let snapshot = SessionPersistence.makePersistedSession(appState: appState)
        let persistedPane = try XCTUnwrap(snapshot.tabs.first?.panes.first)

        XCTAssertEqual(persistedPane.scrollbackOverride, .unlimited)
    }

    func testScrollbackTelemetryContainsRequiredPaneContext() {
        let attributes = TerminalScrollbackTelemetry(
            limit: .unlimited,
            source: "pane_override",
            paneID: "pane-id",
            paneName: "pane-name",
            tabID: "tab-id",
            tabName: "tab-name",
            result: "applied"
        ).attributes

        XCTAssertEqual(attributes["pane.id"], "pane-id")
        XCTAssertEqual(attributes["pane.name"], "pane-name")
        XCTAssertEqual(attributes["tab.id"], "tab-id")
        XCTAssertEqual(attributes["tab.name"], "tab-name")
        XCTAssertEqual(attributes["scrollback.mode"], "unlimited")
        XCTAssertEqual(attributes["scrollback.lines"], "50000")
        XCTAssertEqual(attributes["scrollback.source"], "pane_override")
        XCTAssertEqual(attributes["result"], "applied")
    }
}
