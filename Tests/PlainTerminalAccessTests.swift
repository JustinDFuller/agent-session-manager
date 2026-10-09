import XCTest

@testable import AgentSessionManager

@MainActor
final class PlainTerminalAccessTests: XCTestCase {
    func testShellHarnessDisplayName() {
        XCTAssertEqual(Harness.shell.displayName, "Shell")
    }

    func testShellHarnessCommandDescription() {
        XCTAssertEqual(Harness.shell.commandDescription, "$SHELL")
    }

    func testShellNotInAllCases() {
        XCTAssertFalse(Harness.allCases.contains(.shell))
    }

    func testAllCasesContainsUserFacingTools() {
        XCTAssertTrue(Harness.allCases.contains(.claude))
        XCTAssertTrue(Harness.allCases.contains(.codex))
        XCTAssertTrue(Harness.allCases.contains(.cursor))
        XCTAssertTrue(Harness.allCases.contains(.opencode))
    }

    func testShellHarnessCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(Harness.shell)
        let decoded = try JSONDecoder().decode(Harness.self, from: encoded)
        XCTAssertEqual(decoded, .shell)
    }

    func testRestartTokenIsInitializedToNonNilUUID() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude)
        let token = pane.restartToken
        XCTAssertNotNil(token)
    }

    func testRestartPanePreservesCommand() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude)
        let controller = TerminalController()
        controller.pendingCommandArgs = ["claude", "--settings", "/tmp/test.json"]
        controller.pendingDirectory = "/tmp/repo"
        controller.pendingEnvironment = ["PATH=/usr/bin"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.restartPane(pane)

        XCTAssertEqual(pane.terminalController?.pendingCommandArgs, ["claude", "--settings", "/tmp/test.json"])
    }

    func testRestartPanePreservesDirectory() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude)
        let controller = TerminalController()
        controller.pendingCommandArgs = ["claude"]
        controller.pendingDirectory = "/tmp/my-repo"
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.restartPane(pane)

        XCTAssertEqual(pane.terminalController?.pendingDirectory, "/tmp/my-repo")
    }

    func testRestartPanePreservesEnvironment() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude)
        let controller = TerminalController()
        controller.pendingCommandArgs = ["claude"]
        controller.pendingEnvironment = ["FOO=bar", "PATH=/usr/bin"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.restartPane(pane)

        XCTAssertEqual(pane.terminalController?.pendingEnvironment, ["FOO=bar", "PATH=/usr/bin"])
    }

    func testRestartTokenChangesOnRestart() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude)
        let controller = TerminalController()
        controller.pendingCommandArgs = ["claude"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)
        let originalToken = pane.restartToken

        tab.restartPane(pane)

        XCTAssertNotEqual(pane.restartToken, originalToken)
    }

    func testRestartPaneCreatesNewController() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude)
        let original = TerminalController()
        original.pendingCommandArgs = ["claude"]
        pane.installTerminalController(original)
        tab.panes.append(pane)

        tab.restartPane(pane)

        XCTAssertFalse(pane.terminalController === original)
    }

    func testOpenShellInPaneClearsCommand() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude)
        let controller = TerminalController()
        controller.pendingCommandArgs = ["claude", "--settings", "/tmp/test.json"]
        controller.pendingDirectory = "/tmp/repo"
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.openShellInPane(pane)

        XCTAssertNil(pane.terminalController?.pendingCommandArgs)
    }

    func testOpenShellInPanePreservesDirectory() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude)
        let controller = TerminalController()
        controller.pendingCommandArgs = ["claude"]
        controller.pendingDirectory = "/tmp/my-repo"
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.openShellInPane(pane)

        XCTAssertEqual(pane.terminalController?.pendingDirectory, "/tmp/my-repo")
    }

    func testOpenShellInPaneSetsShellHarness() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude)
        let controller = TerminalController()
        controller.pendingCommandArgs = ["claude"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.openShellInPane(pane)

        XCTAssertEqual(pane.harness, .shell)
    }

    func testOpenShellInPaneChangesRestartToken() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "test", tab: tab, harness: .claude)
        let controller = TerminalController()
        controller.pendingCommandArgs = ["claude"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)
        let originalToken = pane.restartToken

        tab.openShellInPane(pane)

        XCTAssertNotEqual(pane.restartToken, originalToken)
    }

    func testOpenShellPaneAddsPaneToTab() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let existingPane = Pane(name: "claude", tab: tab, harness: .claude)
        tab.panes.append(existingPane)
        let initialCount = tab.panes.count

        tab.openShellPane(activePane: existingPane, appState: AppState())

        XCTAssertEqual(tab.panes.count, initialCount + 1)
    }

    func testOpenShellPaneNamesShellAfterSourcePane() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let sourcePane = Pane(name: "reader", tab: tab, harness: .claude)
        tab.panes.append(sourcePane)

        tab.openShellPane(activePane: sourcePane, appState: AppState())

        XCTAssertEqual(tab.panes.last?.name, "shell:reader")
    }

    func testShellPaneNameHelperUsesSourcePaneName() {
        let name = Tab.shellPaneName(sourcePaneName: "reader", existingPaneNames: [])

        XCTAssertEqual(name, "shell:reader")
    }

    func testOpenShellPaneDeduplicatesShellNamesFromSameSource() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let sourcePane = Pane(name: "reader", tab: tab, harness: .claude)
        tab.panes.append(sourcePane)
        tab.panes.append(Pane(name: "shell:reader", tab: tab, harness: .shell))

        tab.openShellPane(activePane: sourcePane, appState: AppState())

        XCTAssertEqual(tab.panes.last?.name, "shell:reader-2")
    }

    func testShellPaneNameHelperDeduplicatesRepeatedNames() {
        let name = Tab.shellPaneName(
            sourcePaneName: "reader",
            existingPaneNames: ["shell:reader", "shell:reader-2"]
        )

        XCTAssertEqual(name, "shell:reader-3")
    }

    func testOpenShellPaneAddedPaneHasShellHarness() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        tab.openShellPane(activePane: nil, appState: AppState())
        XCTAssertEqual(tab.panes.last?.harness, .shell)
    }

    func testShellPaneNameHelperFallsBackToPlainShellName() {
        let name = Tab.shellPaneName(sourcePaneName: nil, existingPaneNames: [])

        XCTAssertEqual(name, "shell")
    }

    func testOpenShellPaneFallsBackToPlainShellNameWithoutSourcePane() {
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))

        tab.openShellPane(activePane: nil, appState: AppState())

        XCTAssertEqual(tab.panes.last?.name, "shell")
    }

    func testExitBehaviorDisplayNames() {
        XCTAssertEqual(ExitBehavior.prompt.displayName, "Show Prompt")
        XCTAssertEqual(ExitBehavior.autoShell.displayName, "Open Shell")
        XCTAssertEqual(ExitBehavior.close.displayName, "Close Pane")
    }

    func testExitBehaviorCodableRoundTrip() throws {
        for behavior in ExitBehavior.allCases {
            let encoded = try JSONEncoder().encode(behavior)
            let decoded = try JSONDecoder().decode(ExitBehavior.self, from: encoded)
            XCTAssertEqual(decoded, behavior)
        }
    }

    func testExitBehaviorDefaultIsPrompt() {
        let settings = AppSettings()
        XCTAssertEqual(settings.exitBehavior, .prompt)
    }

    func testShellPanesExcludedFromSessionPersistence() {
        let appState = AppState()
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let claudePane = Pane(
            name: "claude-session", tab: tab, harness: .claude,
            worktreeDirectory: URL(filePath: "/tmp"))
        let shellPane = Pane(name: "shell", tab: tab, harness: .shell)
        tab.panes.append(claudePane)
        tab.panes.append(shellPane)
        appState.tabs.append(tab)

        let session = SessionPersistence.makePersistedSession(appState: appState)

        let savedPaneTypes = session.tabs.first?.panes.map(\.harness) ?? []
        XCTAssertFalse(savedPaneTypes.contains(.shell), "Shell panes should not be saved")
        XCTAssertTrue(savedPaneTypes.contains(.claude), "Claude panes should be saved")
    }
}
