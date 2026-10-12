import AppKit
import Foundation
import XCTest

@testable import AgentSessionManager

@MainActor
final class SectionResizingPersistenceTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        TracingService.shared.resetForTesting()
    }

    override func tearDown() async throws {
        TracingService.shared.resetForTesting()
        try await super.tearDown()
    }

    func testTrackSizingClampsMinimaAndRestoresPreferredWeightsAfterGrowth() {
        let minima = [100.0, 100.0, 100.0]
        let weights = [0.7, 0.2, 0.1]
        let constrained = GridLayout.sizes(weights: weights, extent: 400, minima: minima)
        let expanded = GridLayout.sizes(weights: weights, extent: 1_000, minima: minima)
        XCTAssertEqual(constrained[0], 200, accuracy: 0.000_001)
        XCTAssertEqual(constrained[1], 100, accuracy: 0.000_001)
        XCTAssertEqual(constrained[2], 100, accuracy: 0.000_001)
        XCTAssertEqual(expanded[0], 700, accuracy: 0.000_001)
        XCTAssertEqual(expanded[1], 200, accuracy: 0.000_001)
        XCTAssertEqual(expanded[2], 100, accuracy: 0.000_001)
    }

    func testAdjacentAdjustmentConservesSpaceAndLeavesOtherTracksFixed() {
        let sizes = GridLayout.adjusting([180, 210, 120], boundary: 0, delta: 20, minima: [100, 100, 100])
        XCTAssertEqual(sizes, [200, 190, 120])
        XCTAssertEqual(sizes.reduce(0, +), 510)
    }

    func testDividerEqualizationPreservesAdjacentPairExtentAndThirdTrack() {
        let sizes = [420.0, 300.0, 180.0]
        let equalized = GridLayout.equalizingAdjacent(sizes, boundary: 0, minima: [160, 160, 160])
        XCTAssertEqual(equalized[0], 360, accuracy: 0.000_001)
        XCTAssertEqual(equalized[1], 360, accuracy: 0.000_001)
        XCTAssertEqual(equalized[0] + equalized[1], sizes[0] + sizes[1], accuracy: 0.000_001)
        XCTAssertEqual(equalized[2], sizes[2], accuracy: 0.000_001)
    }

    func testBlockedAdjacentAdjustmentDoesNotChangeAnotherBoundary() {
        let sizes = GridLayout.adjusting([180, 100, 220], boundary: 0, delta: 20, minima: [100, 100, 100])
        XCTAssertEqual(sizes, [180, 100, 220])
    }

    func testAdjacentAdjustmentRejectsMalformedBoundsAndNonFiniteMovement() {
        let sizes = [180.0, 210.0, 120.0]
        XCTAssertEqual(GridLayout.adjusting(sizes, boundary: 0, delta: 20, minima: [100, 100]), sizes)
        XCTAssertEqual(GridLayout.adjusting(sizes, boundary: -1, delta: 20, minima: [100, 100, 100]), sizes)
        XCTAssertEqual(GridLayout.adjusting(sizes, boundary: 2, delta: 20, minima: [100, 100, 100]), sizes)
        XCTAssertEqual(GridLayout.adjusting(sizes, boundary: 0, delta: .infinity, minima: [100, 100, 100]), sizes)
        XCTAssertEqual(GridLayout.adjusting(sizes, boundary: 0, delta: .nan, minima: [100, 100, 100]), sizes)
    }

    func testDirectionalBoundarySelectionCoversEveryTrackEdgeAndMiddle() {
        let layout = GridLayout(columns: 3, rows: 3, paneCount: 9)
        XCTAssertEqual((0..<3).map { layout.boundary(paneIndex: $0, direction: .left) }, [0, 0, 1])
        XCTAssertEqual((0..<3).map { layout.boundary(paneIndex: $0, direction: .right) }, [0, 1, 1])
        XCTAssertEqual((0..<3).map { layout.boundary(paneIndex: $0 * 3, direction: .up) }, [0, 0, 1])
        XCTAssertEqual((0..<3).map { layout.boundary(paneIndex: $0 * 3, direction: .down) }, [0, 1, 1])
    }

    func testPartialGridKeepsSharedTracksForEmptyCells() {
        let layout = GridLayout.forPaneCount(3)
        XCTAssertEqual(layout.totalCells, 4)
        XCTAssertEqual(layout.emptyCells, 1)
        XCTAssertEqual(layout.boundary(paneIndex: 2, direction: .up), 0)
        XCTAssertEqual(layout.boundary(paneIndex: 2, direction: .down), 0)
    }

    func testSingleTrackAndInvalidPaneIndexHaveNoBoundary() {
        XCTAssertNil(GridLayout.forPaneCount(1).boundary(paneIndex: 0, direction: .left))
        XCTAssertNil(GridLayout.forPaneCount(2).boundary(paneIndex: 4, direction: .right))
    }

    func testNormalizedWeightsStayPositiveForExtremeFiniteInputs() {
        let weights = GridLayout.normalized([Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude])
        XCTAssertEqual(weights.count, 2)
        XCTAssertTrue(weights.allSatisfy { $0.isFinite && $0 > 0 })
        XCTAssertEqual(weights.reduce(0, +), 1, accuracy: 0.000_001)
    }

    func testTopologyReconciliationResetsOnlyTheChangedAxis() {
        var preferences = PaneGridSizePreferences(columnWeights: [0.7, 0.3], rowWeights: [0.6, 0.4])
        preferences.reconcile(layout: GridLayout.forPaneCount(5))
        XCTAssertEqual(preferences.columnWeights.count, 3)
        XCTAssertTrue(preferences.columnWeights.allSatisfy { abs($0 - 1.0 / 3) < 0.000_001 })
        XCTAssertEqual(preferences.rowWeights, [0.6, 0.4])
    }

    func testInvalidSavedAxisResetsIndependently() throws {
        let json = Data(#"{"columnWeights":[0.75,0.25],"rowWeights":[0,-1]}"#.utf8)
        var preferences = try JSONDecoder().decode(PaneGridSizePreferences.self, from: json)
        preferences.reconcile(layout: GridLayout(columns: 2, rows: 2, paneCount: 3))
        XCTAssertEqual(preferences.columnWeights, [0.75, 0.25])
        XCTAssertEqual(preferences.rowWeights, [0.5, 0.5])
    }

    func testMissingAndMalformedResizeBindingsUseDefaultsWhileNullDisablesOne() throws {
        let command = UInt(NSEvent.ModifierFlags.command.rawValue)
        let json = Data(
            """
            {"tabBarHeight":102,"notificationSidebarWidth":310,"bindings":{"left":{"key":"b","modifierBits":\(command)},"right":{"key":5,"modifierBits":\(command)},"up":null}}
            """.utf8)
        let settings = try JSONDecoder().decode(LayoutSettings.self, from: json)
        XCTAssertEqual(settings.tabBarHeight, 44)
        XCTAssertEqual(settings.notificationSidebarWidth, 310)
        XCTAssertEqual(settings.bindings.binding(for: ResizeAction(direction: .left, larger: false))?.key, "b")
        XCTAssertEqual(
            settings.bindings.binding(for: ResizeAction(direction: .right, larger: false)),
            ResizeAction(direction: .right, larger: false).defaultBinding
        )
        XCTAssertNil(settings.bindings.binding(for: ResizeAction(direction: .up, larger: false)))
        XCTAssertEqual(
            settings.bindings.binding(for: ResizeAction(direction: .down, larger: false)),
            ResizeAction(direction: .down, larger: false).defaultBinding
        )
    }

    func testRestoredKeysNormalizeCaseAndRejectInvalidCharactersOrModifiers() throws {
        let command = UInt(NSEvent.ModifierFlags.command.rawValue)
        let noCommand = UInt(NSEvent.ModifierFlags.option.rawValue)
        let unsupported = command | (1 << 40)
        let json = Data(
            """
            {"bindings":{"left":{"key":"B","modifierBits":\(command)},"right":{"key":"\\n","modifierBits":\(command)},"up":{"key":"b","modifierBits":\(noCommand)},"down":{"key":"b","modifierBits":\(unsupported)}}}
            """.utf8)
        let settings = try JSONDecoder().decode(LayoutSettings.self, from: json)
        XCTAssertEqual(settings.bindings.binding(for: ResizeAction(direction: .left, larger: false))?.key, "b")
        XCTAssertEqual(
            settings.bindings.binding(for: ResizeAction(direction: .right, larger: false)),
            ResizeAction(direction: .right, larger: false).defaultBinding
        )
        XCTAssertEqual(
            settings.bindings.binding(for: ResizeAction(direction: .up, larger: false)),
            ResizeAction(direction: .up, larger: false).defaultBinding
        )
        XCTAssertEqual(
            settings.bindings.binding(for: ResizeAction(direction: .down, larger: false)),
            ResizeAction(direction: .down, larger: false).defaultBinding
        )
    }

    func testRestoredBindingsRejectExistingMenuAndUndoShortcuts() throws {
        let commandShift = UInt((NSEvent.ModifierFlags.command.union(.shift)).rawValue)
        let command = UInt(NSEvent.ModifierFlags.command.rawValue)
        let json = Data(
            """
            {"bindings":{"left":{"key":"d","modifierBits":\(commandShift)},"right":{"key":"z","modifierBits":\(command)}}}
            """.utf8)
        let settings = try JSONDecoder().decode(LayoutSettings.self, from: json)
        XCTAssertNil(settings.bindings.binding(for: ResizeAction(direction: .left, larger: false)))
        XCTAssertNil(settings.bindings.binding(for: ResizeAction(direction: .right, larger: false)))
        XCTAssertEqual(settings.bindings.conflicts.count, 2)
    }

    func testRestoredConflictsDisableEveryResizeActionInvolved() throws {
        let command = UInt(NSEvent.ModifierFlags.command.rawValue)
        let json = Data(
            """
            {"bindings":{"left":{"key":"x","modifierBits":\(command)},"right":{"key":"x","modifierBits":\(command)},"up":{"key":"c","modifierBits":\(command)}}}
            """.utf8)
        let settings = try JSONDecoder().decode(LayoutSettings.self, from: json)
        XCTAssertNil(settings.bindings.binding(for: ResizeAction(direction: .left, larger: false)))
        XCTAssertNil(settings.bindings.binding(for: ResizeAction(direction: .right, larger: false)))
        XCTAssertNil(settings.bindings.binding(for: ResizeAction(direction: .up, larger: false)))
        XCTAssertEqual(settings.bindings.conflicts.count, 3)
        XCTAssertEqual(settings.notificationSidebarWidth, 240)
    }

    func testDisabledBindingAndDimensionsRoundTripIndependently() throws {
        var settings = LayoutSettings()
        settings.tabBarHeight = 72
        settings.notificationSidebarWidth = 360
        settings.bindings.setBinding(nil, for: ResizeAction(direction: .left, larger: false))
        settings.bindings.setBinding(
            ResizeKeyBinding(key: "b", modifiers: .command),
            for: ResizeAction(direction: .right, larger: true)
        )
        let restored = try JSONDecoder().decode(LayoutSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.tabBarHeight, 72)
        XCTAssertEqual(restored.notificationSidebarWidth, 360)
        XCTAssertNil(restored.bindings.binding(for: ResizeAction(direction: .left, larger: false)))
        XCTAssertEqual(
            restored.bindings.binding(for: ResizeAction(direction: .right, larger: true))?.key,
            "b"
        )
    }

    func testGenericSettingsPersistenceRoundTripsLayoutSettingsInIsolation() throws {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let subdirectory = "agent-session-manager-layout-settings-\(UUID().uuidString)"
        let appSupport = supportDirectory.appending(path: subdirectory, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let unrelatedSettings = Data(#"{"preserved":true}"#.utf8)
        try unrelatedSettings.write(to: appSupport.appending(path: "settings.json"))
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        defer {
            PersistenceHelpers.overrideAppSupportSubdirectory = nil
            try? fileManager.removeItem(at: appSupport)
        }

        var layout = LayoutSettings()
        layout.tabBarHeight = 72
        layout.notificationSidebarWidth = 360
        layout.bindings.setBinding(
            ResizeKeyBinding(key: "b", modifiers: [.command, .control]),
            for: ResizeAction(direction: .left, larger: false)
        )
        layout.bindings.setBinding(nil, for: ResizeAction(direction: .right, larger: false))
        SettingsPersistence.save(layout, to: "layout-settings.json")

        let restored = try XCTUnwrap(SettingsPersistence.load(LayoutSettings.self, from: "layout-settings.json"))
        XCTAssertEqual(restored.tabBarHeight, 72)
        XCTAssertEqual(restored.notificationSidebarWidth, 360)
        XCTAssertEqual(restored.bindings.entries.count, 7)
        XCTAssertEqual(
            restored.bindings.binding(for: ResizeAction(direction: .left, larger: false)),
            ResizeKeyBinding(key: "b", modifiers: [.command, .control])
        )
        XCTAssertNil(restored.bindings.binding(for: ResizeAction(direction: .right, larger: false)))
        XCTAssertEqual(
            restored.bindings.binding(for: ResizeAction(direction: .right, larger: true)),
            ResizeAction(direction: .right, larger: true).defaultBinding
        )
        XCTAssertEqual(try Data(contentsOf: appSupport.appending(path: "settings.json")), unrelatedSettings)
    }

    func testGlobalDimensionResetRetainsCustomAndDisabledBindings() {
        var settings = LayoutSettings()
        settings.tabBarHeight = 70
        settings.notificationSidebarWidth = 320
        settings.bindings.setBinding(nil, for: ResizeAction(direction: .left, larger: false))
        settings.bindings.setBinding(
            ResizeKeyBinding(key: "b", modifiers: .command),
            for: ResizeAction(direction: .right, larger: false)
        )
        settings.resetSections()
        XCTAssertEqual(settings.tabBarHeight, 44)
        XCTAssertEqual(settings.notificationSidebarWidth, 240)
        XCTAssertNil(settings.bindings.binding(for: ResizeAction(direction: .left, larger: false)))
        XCTAssertEqual(settings.bindings.binding(for: ResizeAction(direction: .right, larger: false))?.key, "b")
    }

    func testPersistedTabAndPaneKeepOnlyValidNewDimensions() throws {
        let tabID = UUID()
        let paneID = UUID()
        let persistedTab = PersistedTab(
            id: tabID,
            name: "Tab",
            directory: "/tmp",
            gridSizePreferences: PaneGridSizePreferences(columnWeights: [0.65, 0.35], rowWeights: [1]),
            panes: [PersistedPane(id: paneID, name: "Pane", harness: .codex, statusLineHeight: 112)]
        )
        let restored = try JSONDecoder().decode(PersistedTab.self, from: JSONEncoder().encode(persistedTab))
        let restoredColumns = try XCTUnwrap(restored.gridSizePreferences?.columnWeights)
        XCTAssertEqual(restoredColumns.count, 2)
        XCTAssertEqual(restoredColumns[0], 0.65, accuracy: 0.000_001)
        XCTAssertEqual(restoredColumns[1], 0.35, accuracy: 0.000_001)
        XCTAssertEqual(restored.panes.first?.statusLineHeight, 112)

        let invalid = Data(
            """
            {"id":"\(paneID.uuidString)","name":"Pane","harness":"codex","statusLineHeight":300}
            """.utf8)
        XCTAssertNil(try JSONDecoder().decode(PersistedPane.self, from: invalid).statusLineHeight)
    }

    func testRestoreSkipsMissingPanesAndReconcilesOnlyChangedTopologyAxis() throws {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let subdirectory = "agent-session-manager-resize-restore-\(UUID().uuidString)"
        let appSupport = supportDirectory.appending(path: subdirectory, directoryHint: .isDirectory)
        let root = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let worktrees = (0..<4).map { root.appending(path: "pane-\($0)", directoryHint: .isDirectory) }
        for worktree in worktrees {
            try fileManager.createDirectory(at: worktree, withIntermediateDirectories: true)
        }
        let savedPreferences = PaneGridSizePreferences(columnWeights: [0.6, 0.3, 0.1], rowWeights: [0.7, 0.3])
        let persistedTab = PersistedTab(
            id: UUID(),
            name: "Restore Test",
            directory: root.path,
            gridSizePreferences: savedPreferences,
            panes: (0..<5).map { index in
                PersistedPane(
                    id: UUID(),
                    name: "pane-\(index)",
                    harness: .cursor,
                    worktreeDirectory: index < 4 ? worktrees[index].path : root.appending(path: "missing-pane").path,
                    statusLineHeight: 88 + Double(index)
                )
            }
        )
        let session = PersistedSession(tabs: [persistedTab], activeTabIndex: 0)
        try JSONEncoder().encode(session).write(to: appSupport.appending(path: "sessions.json"))
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        let appState = AppState()
        let settings = AppSettings()
        settings.agentControlInjectionPolicy = .never
        defer {
            for pane in appState.tabs.flatMap(\.panes) {
                pane.terminalController?.terminate()
                pane.removeStatusLineMonitor()
            }
            PersistenceHelpers.overrideAppSupportSubdirectory = nil
            try? fileManager.removeItem(at: appSupport)
            try? fileManager.removeItem(at: root)
        }

        SessionPersistence.restore(into: appState, appSettings: settings)

        let restoredTab = try XCTUnwrap(appState.tabs.first)
        XCTAssertEqual(restoredTab.panes.count, 4)
        XCTAssertEqual(restoredTab.gridSizePreferences.columnWeights.count, 2)
        XCTAssertEqual(restoredTab.gridSizePreferences.columnWeights, [0.5, 0.5])
        XCTAssertEqual(restoredTab.gridSizePreferences.rowWeights, savedPreferences.rowWeights)
        XCTAssertEqual(restoredTab.panes.compactMap(\.statusLineHeight), [88, 89, 90, 91])
    }

    func testLegacyPersistedTabAndPaneDecodeWithDefaultPreferences() throws {
        let paneID = UUID()
        let json = Data(
            """
            {"id":"\(UUID().uuidString)","name":"Tab","directory":"/tmp","panes":[{"id":"\(paneID.uuidString)","name":"Pane"}]}
            """.utf8)
        let tab = try JSONDecoder().decode(PersistedTab.self, from: json)
        XCTAssertNil(tab.gridSizePreferences)
        XCTAssertEqual(tab.panes.first?.harness, .claude)
        XCTAssertNil(tab.panes.first?.statusLineHeight)
    }
}
