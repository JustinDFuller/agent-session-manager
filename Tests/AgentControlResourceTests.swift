import Foundation
import MCP
import XCTest

@testable import AgentSessionManager

@MainActor
final class AgentControlResourceTests: XCTestCase {
    func testResourceURIParsingUsesStableIDs() {
        let id = UUID()

        XCTAssertEqual(AgentControlResourceURI("agent-session-manager://workspace"), .workspace)
        XCTAssertEqual(
            AgentControlResourceURI("agent-session-manager://panes/\(id.uuidString)"), .pane(id))
        XCTAssertEqual(
            AgentControlResourceURI("agent-session-manager://status-lines/pane/\(id.uuidString)"),
            .paneStatus(id))
        XCTAssertNil(AgentControlResourceURI("agent-session-manager://panes/not-an-id"))
        XCTAssertNil(AgentControlResourceURI("https://example.com/panes/\(id.uuidString)"))
    }

    func testScopeFilteringAndProfileEnvironmentRedaction() async throws {
        let fixture = makeFixture()
        defer { stopPanes(in: fixture.state) }

        let paneWorkspace = try JSONDecoder().decode(
            AgentControlWorkspaceSnapshot.self,
            from: Data(
                try await fixture.router.read(
                    uri: AgentControlResourceURI.workspace.rawValue, source: fixture.paneSource
                ).utf8))
        XCTAssertEqual(paneWorkspace.tabs.count, 1)
        XCTAssertEqual(paneWorkspace.tabs.first?.panes.map(\.id), [fixture.paneID])
        let paneSnapshot = try XCTUnwrap(paneWorkspace.tabs.first?.panes.first)
        XCTAssertEqual(
            paneSnapshot.extraArgs,
            ["--api-key=<redacted>", "--prompt", "<redacted>"])
        fixture.state.activePaneID = fixture.otherPaneID
        let scopedActivePane = try JSONDecoder().decode(
            AgentControlWorkspaceSnapshot.self,
            from: Data(
                try await fixture.router.read(
                    uri: AgentControlResourceURI.workspace.rawValue, source: fixture.paneSource
                ).utf8))
        XCTAssertNil(scopedActivePane.activePaneID)

        let tabWorkspace = try JSONDecoder().decode(
            AgentControlWorkspaceSnapshot.self,
            from: Data(
                try await fixture.router.read(
                    uri: AgentControlResourceURI.workspace.rawValue, source: fixture.tabSource
                ).utf8))
        XCTAssertEqual(tabWorkspace.tabs.count, 1)
        XCTAssertEqual(tabWorkspace.tabs.first?.panes.count, 2)

        let globalWorkspace = try JSONDecoder().decode(
            AgentControlWorkspaceSnapshot.self,
            from: Data(
                try await fixture.router.read(
                    uri: AgentControlResourceURI.workspace.rawValue, source: fixture.globalSource
                ).utf8))
        XCTAssertEqual(globalWorkspace.tabs.count, 2)

        do {
            _ = try await fixture.router.read(
                uri: AgentControlResourceURI.pane(fixture.otherPaneID).rawValue,
                source: fixture.paneSource)
            XCTFail("Pane scope must not read another pane")
        } catch {
            XCTAssertTrue(error is MCPError)
        }

        let profiles = try await fixture.router.read(
            uri: AgentControlResourceURI.profiles.rawValue, source: fixture.paneSource)
        XCTAssertTrue(profiles.contains("Secret Profile"))
        XCTAssertFalse(profiles.contains("secret-value"))
        XCTAssertFalse(profiles.contains("runtime-secret"))
    }

    func testAllReadOnlyResourcesAndTemplatesRespectScope() async throws {
        let fixture = makeFixture()
        defer { stopPanes(in: fixture.state) }
        fixture.state.notifications = [
            PaneNotification(
                paneID: fixture.paneID,
                paneName: "First Pane",
                tabID: fixture.tabID,
                tabName: fixture.firstTabName,
                isPriority: true,
                reason: "Needs attention"),
            PaneNotification(
                paneID: fixture.otherPaneID,
                paneName: "Second Pane",
                tabID: fixture.tabID,
                tabName: fixture.firstTabName,
                isPriority: false,
                reason: "Second attention"),
        ]

        let sources = [fixture.paneSource, fixture.tabSource, fixture.globalSource]
        for source in sources {
            let profiles = try await fixture.router.read(
                uri: AgentControlResourceURI.profiles.rawValue, source: source)
            XCTAssertTrue(profiles.contains("Secret Profile"))
            XCTAssertFalse(profiles.contains("secret-value"))
            XCTAssertFalse(profiles.contains("runtime-secret"))

            if source.scope == .global {
                let harnesses = try await fixture.router.read(
                    uri: AgentControlResourceURI.harnesses.rawValue, source: source)
                let harnessSnapshots = try JSONDecoder().decode(
                    [AgentControlHarnessSnapshot].self, from: Data(harnesses.utf8))
                XCTAssertEqual(harnessSnapshots.count, Harness.allCases.count)
                XCTAssertFalse(harnesses.contains("secret-value"))
            } else {
                do {
                    _ = try await fixture.router.read(
                        uri: AgentControlResourceURI.harnesses.rawValue, source: source)
                    XCTFail("Non-global scopes must not read harness catalogs")
                } catch {
                    XCTAssertTrue(error is MCPError)
                }
            }

            let statusLines = try await fixture.router.read(
                uri: AgentControlResourceURI.statusLines.rawValue, source: source)
            let statusSnapshot = try JSONDecoder().decode(
                AgentControlStatusLineSnapshot.self, from: Data(statusLines.utf8))
            let expectedPaneCount: Int
            switch source.scope {
            case .pane: expectedPaneCount = 1
            case .tab: expectedPaneCount = 2
            case .global: expectedPaneCount = 3
            }
            XCTAssertEqual(statusSnapshot.panes.count, expectedPaneCount)
            XCTAssertEqual(statusSnapshot.globalConfiguration != nil, source.scope == .global)

            let notifications = try await fixture.router.read(
                uri: AgentControlResourceURI.notifications.rawValue, source: source)
            let notificationSnapshots = try JSONDecoder().decode(
                [AgentControlNotificationSnapshot].self, from: Data(notifications.utf8))
            switch source.scope {
            case .pane: XCTAssertEqual(notificationSnapshots.count, 1)
            case .tab, .global: XCTAssertEqual(notificationSnapshots.count, 2)
            }
        }

        _ = try await fixture.router.read(
            uri: AgentControlResourceURI.profile(fixture.profileID).rawValue,
            source: fixture.paneSource)
        _ = try await fixture.router.read(
            uri: AgentControlResourceURI.tab(fixture.tabID).rawValue,
            source: fixture.paneSource)
        _ = try await fixture.router.read(
            uri: AgentControlResourceURI.pane(fixture.otherPaneID).rawValue,
            source: fixture.tabSource)
        _ = try await fixture.router.read(
            uri: AgentControlResourceURI.paneStatus(fixture.otherPaneID).rawValue,
            source: fixture.tabSource)

        for uri in [
            AgentControlResourceURI.tab(UUID()).rawValue,
            AgentControlResourceURI.pane(UUID()).rawValue,
            AgentControlResourceURI.profile(UUID()).rawValue,
            AgentControlResourceURI.paneStatus(UUID()).rawValue,
        ] {
            do {
                _ = try await fixture.router.read(uri: uri, source: fixture.globalSource)
                XCTFail("Stale resource IDs must be rejected: \(uri)")
            } catch {
                XCTAssertTrue(error is MCPError)
            }
        }

        do {
            _ = try await fixture.router.read(
                uri: AgentControlResourceURI.pane(fixture.otherPaneID).rawValue,
                source: fixture.paneSource)
            XCTFail("Pane scope must not read another pane's resource")
        } catch {
            XCTAssertTrue(error is MCPError)
        }

        do {
            _ = try await fixture.router.read(
                uri: AgentControlResourceURI.paneStatus(fixture.otherPaneID).rawValue,
                source: fixture.paneSource)
            XCTFail("Pane scope must not read another pane's status")
        } catch {
            XCTAssertTrue(error is MCPError)
        }
    }

    func testResourceDiscoveryAndReadThroughMCPClient() async throws {
        let fixture = makeFixture()
        defer { stopPanes(in: fixture.state) }

        let tokenStore = AgentControlTokenStore()
        let application = AgentControlHTTPApplication(
            tokenStore: tokenStore,
            limits: .default,
            resourceRouter: fixture.router)
        let port = try await application.start()
        let credential = try tokenStore.register(source: fixture.globalSource, limits: .default)
        let endpoint = URL(string: "http://127.0.0.1:\(port)/mcp")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            "Authorization": "Bearer \(credential.bearerToken)"
        ]
        let transport = HTTPClientTransport(
            endpoint: endpoint,
            configuration: configuration)
        let client = Client(name: "AgentControlResourceTests", version: "1.0")
        defer {
            Task {
                await client.disconnect()
                await application.stop()
            }
        }

        try await client.connect(transport: transport)
        let resources = try await client.listResources()
        XCTAssertEqual(resources.resources.count, 9)
        let templates = try await client.listResourceTemplates()
        XCTAssertEqual(templates.templates.count, 4)
        let tools = try await client.listTools()
        XCTAssertEqual(tools.tools.count, 23)
        XCTAssertTrue(tools.tools.contains { $0.name == "profiles_create" })
        XCTAssertTrue(tools.tools.contains { $0.name == "harnesses_configure_cli_option" })
        XCTAssertTrue(tools.tools.contains { $0.name == "status_lines_update_global" })
        XCTAssertTrue(tools.tools.contains { $0.name == "notifications_acknowledge" })

        let contents = try await client.readResource(uri: AgentControlResourceURI.workspace.rawValue)
        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(contents.first?.mimeType, "application/json")
        XCTAssertTrue(contents.first?.text?.contains(fixture.firstTabName) == true)

        for resource in [
            AgentControlResourceURI.diagnosticSummary,
            AgentControlResourceURI.diagnosticTraces,
            AgentControlResourceURI.diagnosticInvariants,
            AgentControlResourceURI.diagnosticLogs,
        ] {
            let diagnosticContents = try await client.readResource(uri: resource.rawValue)
            XCTAssertEqual(diagnosticContents.count, 1)
            XCTAssertEqual(diagnosticContents.first?.mimeType, "application/json")
            XCTAssertTrue(diagnosticContents.first?.text?.contains("availability") == true)
        }

        let traceQuery = try await client.callTool(
            name: "diagnostics_query_traces",
            arguments: ["limit": .int(1)])
        XCTAssertNil(traceQuery.isError)
        XCTAssertTrue(toolText(traceQuery.content)?.contains("records") == true)

        let logQuery = try await client.callTool(
            name: "diagnostics_query_logs",
            arguments: ["limit": .int(1)])
        XCTAssertNil(logQuery.isError)
        XCTAssertTrue(toolText(logQuery.content)?.contains("records") == true)

        let debugModeResult = try await client.callTool(
            name: "debug_set_mode",
            arguments: ["enabled": .bool(false)])
        XCTAssertNil(debugModeResult.isError)
    }

    func testDiagnosticSummaryAndResourceQueryExposeScopeContract() async throws {
        let fixture = makeFixture()
        defer { stopPanes(in: fixture.state) }

        let summaryData = Data(
            try await fixture.router.read(
                uri: AgentControlResourceURI.diagnosticSummary.rawValue,
                source: fixture.paneSource
            ).utf8)
        let summary = try JSONDecoder().decode(AgentControlDiagnosticSummary.self, from: summaryData)
        XCTAssertEqual(summary.currentScope, .pane)
        XCTAssertTrue(summary.globalOnlyResources.contains(AgentControlResourceURI.harnesses.rawValue))
        XCTAssertTrue(summary.globalOnlyTools.contains("debug_set_mode"))

        let traceData = try await fixture.router.read(
            uri: "\(AgentControlResourceURI.diagnosticTraces.rawValue)?limit=1",
            source: fixture.paneSource)
        let traceResult = try JSONDecoder().decode(
            AgentControlTraceQueryResult.self, from: Data(traceData.utf8))
        XCTAssertEqual(traceResult.metadata.query.limit, 1)
    }

    func testResourceReadTelemetryContainsContextButNoPayload() async throws {
        let fixture = makeFixture()
        defer { stopPanes(in: fixture.state) }
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        _ = try await fixture.router.read(
            uri: AgentControlResourceURI.workspace.rawValue, source: fixture.paneSource)

        let event = try XCTUnwrap(
            TracingService.shared.recordedEventsForTesting.last {
                $0.name == "agent_control.resource.read"
            })
        XCTAssertEqual(event.attributes["pane.id"], fixture.paneID.uuidString)
        XCTAssertEqual(event.attributes["tab.id"], fixture.tabID.uuidString)
        XCTAssertEqual(event.attributes["result"], "success")
        XCTAssertNil(event.attributes["payload"])
        XCTAssertNil(event.attributes["token"])
    }

    func testToolNamesAreAPISafe() {
        let fixture = makeFixture()
        defer { stopPanes(in: fixture.state) }

        let pattern = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_-]{1,64}$")
        for tool in fixture.router.tools() {
            let range = NSRange(tool.name.startIndex..., in: tool.name)
            XCTAssertNotNil(
                pattern.firstMatch(in: tool.name, range: range),
                "Tool name \(tool.name) is not a safe Anthropic API tool name")
        }
    }

    func testToolSchemasAreWellFormed() throws {
        let fixture = makeFixture()
        defer { stopPanes(in: fixture.state) }

        for tool in fixture.router.tools() {
            let root = try XCTUnwrap(tool.inputSchema.objectValue, "\(tool.name) root schema is not an object")
            XCTAssertEqual(root["type"]?.stringValue, "object", "\(tool.name) root type is not object")
            let properties = try XCTUnwrap(
                root["properties"]?.objectValue, "\(tool.name) properties is not an object")
            for (propertyName, propertyValue) in properties {
                try assertWellFormedSubschema(
                    propertyValue, context: "\(tool.name).\(propertyName)")
            }
            let required = root["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
            for name in required {
                XCTAssertNotNil(
                    properties[name], "\(tool.name) requires \(name), which is not in properties")
            }
        }
    }

    func testEveryAdvertisedToolIsDispatchable() async throws {
        let fixture = makeFixture()
        defer { stopPanes(in: fixture.state) }

        for tool in fixture.router.tools() {
            do {
                _ = try await fixture.router.callTool(
                    name: tool.name, arguments: [:], source: fixture.globalSource)
            } catch {
                let message = (error as? MCPError)?.errorDescription ?? String(describing: error)
                XCTAssertFalse(
                    message.contains("Unknown Agent Session Manager mutation tool")
                        || message.contains("Unknown Agent Session Manager diagnostic tool"),
                    "\(tool.name) advertised in tools() but not dispatchable: \(message)")
            }
        }
    }

    private func assertWellFormedSubschema(_ value: Value, context: String) throws {
        let object = try XCTUnwrap(value.objectValue, "\(context) is not an object")
        let type = try XCTUnwrap(object["type"]?.stringValue, "\(context) has no type")
        let validTypes: Set<String> = ["string", "integer", "number", "boolean", "array", "object"]
        XCTAssertTrue(validTypes.contains(type), "\(context) has unrecognized type \(type)")
        if type == "array" {
            let items = try XCTUnwrap(object["items"], "\(context) array has no items schema")
            try assertWellFormedSubschema(items, context: "\(context).items")
        }
    }

    private struct Fixture {
        let state: AppState
        let router: AgentControlResourceRouter
        let paneSource: AgentControlSource
        let tabSource: AgentControlSource
        let globalSource: AgentControlSource
        let tabID: UUID
        let paneID: UUID
        let otherPaneID: UUID
        let profileID: UUID
        let firstTabName: String
    }

    private func makeFixture() -> Fixture {
        let state = AppState()
        let settings = AppSettings()
        let profile = Profile(
            name: "Secret Profile",
            harness: .claude,
            envVars: [ProfileEnvVar(id: "API_KEY", isEnabled: true, value: "secret-value")])
        settings.profiles = [profile]

        let firstTab = Tab(name: "First Tab", directory: URL(filePath: "/tmp/first-repo"))
        let firstPane = firstTab.addPane(
            name: "First Pane",
            harness: .claude,
            worktreeDirectory: URL(filePath: "/tmp/first-worktree"),
            extraEnvVars: ["API_KEY": "runtime-secret"],
            profileID: profile.id,
            appSettings: settings)
        firstPane.extraArgs = ["--api-key=secret", "--prompt", "sensitive prompt"]
        let secondPane = firstTab.addPane(
            name: "Second Pane",
            harness: .codex,
            worktreeDirectory: URL(filePath: "/tmp/second-worktree"),
            appSettings: settings)
        let secondTab = Tab(name: "Second Tab", directory: URL(filePath: "/tmp/second-repo"))
        _ = secondTab.addPane(
            name: "Other Pane",
            harness: .cursor,
            worktreeDirectory: URL(filePath: "/tmp/other-worktree"),
            appSettings: settings)
        state.tabs = [firstTab, secondTab]
        state.activeTabID = firstTab.id
        state.activePaneID = firstPane.id

        let router = AgentControlResourceRouter(appState: state, appSettings: settings)
        return Fixture(
            state: state,
            router: router,
            paneSource: AgentControlSource(
                paneID: firstPane.id, paneName: firstPane.name, tabID: firstTab.id,
                tabName: firstTab.name, scope: .pane),
            tabSource: AgentControlSource(
                paneID: firstPane.id, paneName: firstPane.name, tabID: firstTab.id,
                tabName: firstTab.name, scope: .tab),
            globalSource: AgentControlSource(
                paneID: firstPane.id, paneName: firstPane.name, tabID: firstTab.id,
                tabName: firstTab.name, scope: .global),
            tabID: firstTab.id,
            paneID: firstPane.id,
            otherPaneID: secondPane.id,
            profileID: profile.id,
            firstTabName: firstTab.name)
    }

    private func stopPanes(in state: AppState) {
        for pane in state.tabs.flatMap(\.panes) {
            pane.terminalController?.terminate()
            pane.removeStatusLineMonitor()
        }
    }

    private func toolText(_ content: [Tool.Content]) -> String? {
        guard case .text(let text, _, _) = content.first(where: { _ in true }) else { return nil }
        return text
    }
}
