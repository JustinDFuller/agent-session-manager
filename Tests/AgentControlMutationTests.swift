import Foundation
import MCP
import XCTest

@testable import AgentSessionManager

@MainActor
final class AgentControlMutationTests: XCTestCase {
    private let testDirectory = "agent-control-mutation-tests-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        PersistenceHelpers.overrideAppSupportSubdirectory = testDirectory
    }

    override func tearDown() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: base.appending(path: testDirectory))
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        TracingService.shared.resetForTesting()
        super.tearDown()
    }

    func testPaneScopeCannotMutateAnotherPaneOrCreatePane() async throws {
        let fixture = makeFixture()

        do {
            _ = try await fixture.router.callTool(
                name: "panes_focus",
                arguments: ["paneID": .string(fixture.otherPane.id.uuidString)],
                source: fixture.paneSource)
            XCTFail("Pane scope must not focus another pane")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("scope"))
        }

        do {
            _ = try await fixture.router.callTool(
                name: "panes_create",
                arguments: [
                    "tabID": .string(fixture.tab.id.uuidString),
                    "worktreeRef": .string("new-pane"),
                    "harness": .string("claude"),
                ],
                source: fixture.paneSource)
            XCTFail("Pane scope must not create a pane")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("scope"))
        }
    }

    func testTabScopeCanFocusAndReorderPanesOnlyInItsTab() async throws {
        let fixture = makeFixture()

        let focus = try await fixture.router.callTool(
            name: "panes_focus",
            arguments: ["paneID": .string(fixture.otherPane.id.uuidString)],
            source: fixture.tabSource)
        XCTAssertNil(focus.isError)
        XCTAssertEqual(fixture.state.activePaneID, fixture.otherPane.id)
        XCTAssertEqual(fixture.tab.focusedPaneID, fixture.otherPane.id)

        let reorder = try await fixture.router.callTool(
            name: "panes_reorder",
            arguments: [
                "paneID": .string(fixture.firstPane.id.uuidString),
                "destinationIndex": .int(2),
            ],
            source: fixture.tabSource)
        XCTAssertNil(reorder.isError)
        XCTAssertEqual(fixture.tab.panes.map(\.id), [fixture.otherPane.id, fixture.firstPane.id])

        do {
            _ = try await fixture.router.callTool(
                name: "panes_focus",
                arguments: ["paneID": .string(fixture.secondTabPane.id.uuidString)],
                source: fixture.tabSource)
            XCTFail("Tab scope must not reach another tab")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("scope"))
        }
    }

    func testGlobalScopeCanFocusAndReorderTabs() async throws {
        let fixture = makeFixture()

        let focus = try await fixture.router.callTool(
            name: "tabs_focus",
            arguments: ["tabID": .string(fixture.secondTab.id.uuidString)],
            source: fixture.globalSource)
        XCTAssertNil(focus.isError)
        XCTAssertEqual(fixture.state.activeTabID, fixture.secondTab.id)

        let reorder = try await fixture.router.callTool(
            name: "tabs_reorder",
            arguments: [
                "tabID": .string(fixture.secondTab.id.uuidString),
                "destinationIndex": .int(0),
            ],
            source: fixture.globalSource)
        XCTAssertNil(reorder.isError)
        XCTAssertEqual(fixture.state.tabs.map(\.id), [fixture.secondTab.id, fixture.tab.id])
    }

    func testDeletingActiveTabReturnsConsistentActiveSelection() async throws {
        let fixture = makeFixture()
        fixture.state.activeTabID = fixture.secondTab.id
        fixture.state.activePaneID = fixture.secondTabPane.id

        let response = try await fixture.router.callTool(
            name: "tabs_delete",
            arguments: ["tabID": .string(fixture.secondTab.id.uuidString)],
            source: fixture.globalSource)
        let result = try decodeMutationResult(response)

        XCTAssertEqual(result.activeTabID, fixture.tab.id)
        XCTAssertEqual(result.activePaneID, fixture.firstPane.id)
        XCTAssertEqual(fixture.state.activeTabID, fixture.tab.id)
        XCTAssertEqual(fixture.state.activePaneID, fixture.firstPane.id)
    }

    func testGlobalScopeCanCreateTabFromAnExistingDirectory() async throws {
        let fixture = makeFixture()
        let directory = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)

        let response = try await fixture.router.callTool(
            name: "tabs_create",
            arguments: [
                "name": .string("Created Tab"),
                "directory": .string(directory.path),
            ],
            source: fixture.globalSource)

        XCTAssertNil(response.isError)
        XCTAssertEqual(fixture.state.tabs.count, 3)
        XCTAssertEqual(fixture.state.tabs.last?.name, "Created Tab")
        XCTAssertEqual(fixture.state.activeTabID, fixture.state.tabs.last?.id)
    }

    func testGlobalScopeCanToggleHarnessAvailability() async throws {
        let fixture = makeFixture()
        let response = try await fixture.router.callTool(
            name: "harnesses_set_enabled",
            arguments: [
                "harness": .string("codex"),
                "enabled": .bool(false),
            ],
            source: fixture.globalSource)

        XCTAssertNil(response.isError)
        XCTAssertFalse(fixture.settings.isActive(.codex))

        let restored = try await fixture.router.callTool(
            name: "harnesses_set_enabled",
            arguments: [
                "harness": .string("codex"),
                "enabled": .bool(true),
            ],
            source: fixture.globalSource)
        XCTAssertNil(restored.isError)
        XCTAssertTrue(fixture.settings.isActive(.codex))
    }

    func testCleanupPolicyRequiresChoiceAndReportsPartialFailures() async throws {
        let state = AppState()
        let settings = AppSettings()
        let base = URL(filePath: NSTemporaryDirectory()).appending(path: "cleanup-failure-\(UUID().uuidString)")
        let checkout = base.appending(path: "checkout")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let tab = Tab(name: "Managed Tab", directory: base)
        let pane = tab.addPane(
            name: "Managed Pane", harness: .claude,
            worktreeDirectory: checkout, worktreeIsManaged: true,
            appSettings: settings)
        state.tabs = [tab]
        state.activeTabID = tab.id
        state.activePaneID = pane.id
        let router = AgentControlMutationRouter(appState: state, appSettings: settings)
        let source = AgentControlSource(
            paneID: pane.id, paneName: pane.name, tabID: tab.id, tabName: tab.name, scope: .global)

        do {
            _ = try await router.callTool(
                name: "tabs_delete", arguments: ["tabID": .string(tab.id.uuidString)], source: source)
            XCTFail("Ask cleanup policy must require an explicit choice")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("cleanup"))
        }
        XCTAssertEqual(state.tabs.count, 1)

        let response = try await router.callTool(
            name: "tabs_delete",
            arguments: [
                "tabID": .string(tab.id.uuidString),
                "cleanup": .string("delete"),
            ],
            source: source)
        XCTAssertNil(response.isError)
        XCTAssertTrue(toolText(response.content)?.contains("partial_failure") == true)
        XCTAssertTrue(toolText(response.content)?.contains("failed") == true)
        XCTAssertTrue(state.tabs.isEmpty)
    }

    func testMutationTelemetryContainsScopeAndIDsWithoutPayload() async throws {
        let fixture = makeFixture()
        TracingService.shared.enableTestCapture()
        defer { TracingService.shared.resetForTesting() }

        _ = try await fixture.router.callTool(
            name: "panes_focus",
            arguments: ["paneID": .string(fixture.otherPane.id.uuidString)],
            source: fixture.tabSource)

        let event = try XCTUnwrap(
            TracingService.shared.recordedEventsForTesting.last { $0.name == "agent_control.mutation" })
        XCTAssertEqual(event.attributes["tool"], "panes_focus")
        XCTAssertEqual(event.attributes["scope"], "tab")
        XCTAssertEqual(event.attributes["target.pane.id"], fixture.otherPane.id.uuidString)
        XCTAssertNil(event.attributes["payload"])
        XCTAssertNil(event.attributes["token"])
    }

    func testGlobalScopeCanCreateUpdateReorderAndDeleteProfiles() async throws {
        let fixture = makeFixture()
        let response = try await fixture.router.callTool(
            name: "profiles_create",
            arguments: [
                "name": .string("Review Profile"),
                "harness": .string("claude"),
                "cliOptions": .array([
                    .object([
                        "id": .string("--continue"),
                        "enabled": .bool(false),
                        "showOnPaneCreate": .bool(true),
                    ])
                ]),
                "environment": .array([
                    .object([
                        "id": .string("ANTHROPIC_API_KEY"),
                        "enabled": .bool(true),
                        "value": .string("secret-value"),
                    ])
                ]),
            ],
            source: fixture.globalSource)
        let result = try decodeMutationResult(response)
        XCTAssertEqual(result.status, "succeeded")
        XCTAssertEqual(result.profile?.name, "Review Profile")
        XCTAssertEqual(result.profile?.environment.first?.isConfigured, true)
        let profileID = try XCTUnwrap(result.profileID)

        let update = try await fixture.router.callTool(
            name: "profiles_update",
            arguments: [
                "profileID": .string(profileID.uuidString),
                "name": .string("Updated Profile"),
                "environment": .array([
                    .object([
                        "id": .string("ANTHROPIC_API_KEY"),
                        "enabled": .bool(false),
                    ])
                ]),
            ],
            source: fixture.globalSource)
        let updated = try decodeMutationResult(update)
        XCTAssertEqual(updated.profile?.name, "Updated Profile")
        XCTAssertEqual(updated.profile?.environment.first?.isConfigured, true)
        XCTAssertEqual(fixture.state.tabs.count, 2)

        let second = try await fixture.router.callTool(
            name: "profiles_create",
            arguments: ["name": .string("Second Profile"), "harness": .string("codex")],
            source: fixture.globalSource)
        let secondID = try XCTUnwrap(decodeMutationResult(second).profileID)
        let reorder = try await fixture.router.callTool(
            name: "profiles_reorder",
            arguments: [
                "profileID": .string(secondID.uuidString),
                "destinationIndex": .int(0),
            ],
            source: fixture.globalSource)
        XCTAssertEqual(try decodeMutationResult(reorder).profileOrder?.first, secondID)

        let deletion = try await fixture.router.callTool(
            name: "profiles_delete",
            arguments: ["profileID": .string(profileID.uuidString)],
            source: fixture.globalSource)
        XCTAssertEqual(try decodeMutationResult(deletion).profileID, profileID)
        XCTAssertFalse(fixture.settings.profiles.contains { $0.id == profileID })
    }

    func testGlobalStatusLineMutationPersistsAndReturnsConfiguration() async throws {
        let fixture = makeFixture()
        var configuration = StatusLineConfig()
        configuration.rows = [
            StatusLineRow(items: [
                StatusLineItem(id: "model", label: "Model", sfSymbol: "cpu"),
                StatusLineItem(id: "worktree", label: "Worktree", sfSymbol: "folder.badge.gearshape"),
            ])
        ]

        let response = try await fixture.router.callTool(
            name: "status_lines_update_global",
            arguments: ["configuration": try value(for: configuration)],
            source: fixture.globalSource)
        let result = try decodeMutationResult(response)

        XCTAssertEqual(result.status, "succeeded")
        XCTAssertEqual(result.statusLineConfiguration, configuration)
        XCTAssertEqual(fixture.settings.statusLineConfig, configuration)
        XCTAssertEqual(
            SettingsPersistence.load(StatusLineConfig.self, from: "statusline-settings.json"), configuration)
    }

    func testGlobalStatusLineMutationAcceptsInstalledExactSymbolOutsideCuratedCatalog() async throws {
        let fixture = makeFixture()
        let exactSymbol = "heart.fill"
        XCTAssertTrue(StatusLineConfig.isSFSymbolAvailable(exactSymbol))
        XCTAssertFalse(StatusLineConfig.customFieldIconOptions.contains { $0.symbol == exactSymbol })

        var configuration = StatusLineConfig()
        configuration.customFields = [
            CustomStatusLineField(
                id: "custom:00000000-0000-0000-0000-000000000042",
                label: "Health",
                sfSymbol: exactSymbol,
                command: "printf healthy"
            )
        ]

        let response = try await fixture.router.callTool(
            name: "status_lines_update_global",
            arguments: ["configuration": try value(for: configuration)],
            source: fixture.globalSource)
        let result = try decodeMutationResult(response)

        XCTAssertEqual(result.status, "succeeded")
        XCTAssertEqual(result.statusLineConfiguration?.customFields.first?.sfSymbol, exactSymbol)
        XCTAssertEqual(fixture.settings.statusLineConfig.customFields.first?.sfSymbol, exactSymbol)
    }

    func testGlobalStatusLineMutationRejectsUnavailableExactSymbol() async throws {
        let fixture = makeFixture()
        let unavailableSymbol = "not.a.real.sf.symbol"
        let previousConfiguration = fixture.settings.statusLineConfig
        XCTAssertFalse(StatusLineConfig.isSFSymbolAvailable(unavailableSymbol))

        var configuration = StatusLineConfig()
        configuration.customFields = [
            CustomStatusLineField(
                id: "custom:00000000-0000-0000-0000-000000000043",
                label: "Invalid",
                sfSymbol: unavailableSymbol,
                command: "printf invalid"
            )
        ]

        do {
            _ = try await fixture.router.callTool(
                name: "status_lines_update_global",
                arguments: ["configuration": try value(for: configuration)],
                source: fixture.globalSource)
            XCTFail("An unavailable exact SF Symbol must be rejected")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("not supported"))
            XCTAssertTrue(String(describing: error).contains(unavailableSymbol))
        }

        XCTAssertEqual(fixture.settings.statusLineConfig, previousConfiguration)
    }

    func testProfileStatusLineMutationUpdatesAndClearsOnlyTheOverride() async throws {
        let fixture = makeFixture()
        var profile = Profile(name: "Status Profile", harness: .claude)
        profile.cliOptions = [ProfileCLIOption(id: "--model", isEnabled: true, value: "opus")]
        profile.envVars = [ProfileEnvVar(id: "API_KEY", isEnabled: true, value: "secret")]
        fixture.settings.profiles = [profile]

        var configuration = StatusLineConfig()
        configuration.rows = [
            StatusLineRow(items: [
                StatusLineItem(id: "context", label: "Context Used", sfSymbol: "gauge.with.needle")
            ])
        ]
        let update = try await fixture.router.callTool(
            name: "status_lines_update_profile",
            arguments: [
                "profileID": .string(profile.id.uuidString),
                "configuration": try value(for: configuration),
            ],
            source: fixture.globalSource)
        let updated = try decodeMutationResult(update)

        XCTAssertEqual(updated.profile?.statusLineConfig, configuration)
        XCTAssertEqual(updated.profile?.cliOptions.first?.value, "opus")
        XCTAssertEqual(updated.profile?.environment.first?.isConfigured, true)

        let cleared = try await fixture.router.callTool(
            name: "status_lines_clear_profile_override",
            arguments: ["profileID": .string(profile.id.uuidString)],
            source: fixture.globalSource)
        XCTAssertNil(try decodeMutationResult(cleared).profile?.statusLineConfig)
        XCTAssertNil(fixture.settings.profiles.first?.statusLineConfig)
    }

    func testStatusLineMutationsRejectInvalidConfigurationsAndNonGlobalScope() async throws {
        let fixture = makeFixture()
        let previousConfiguration = fixture.settings.statusLineConfig
        var duplicate = StatusLineConfig()
        duplicate.rows = [
            StatusLineRow(items: [
                StatusLineItem(id: "model", label: "Model", sfSymbol: "cpu"),
                StatusLineItem(id: "model", label: "Model", sfSymbol: "cpu"),
            ])
        ]

        do {
            _ = try await fixture.router.callTool(
                name: "status_lines_update_global",
                arguments: ["configuration": try value(for: duplicate)],
                source: fixture.globalSource)
            XCTFail("Duplicate status-line items must be rejected")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("appears more than once"))
        }

        do {
            _ = try await fixture.router.callTool(
                name: "status_lines_update_global",
                arguments: ["configuration": try value(for: StatusLineConfig())],
                source: fixture.tabSource)
            XCTFail("Status-line mutations must require Global scope")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("Global scope"))
        }
        XCTAssertEqual(fixture.settings.statusLineConfig, previousConfiguration)
    }

    func testNotificationAcknowledgementNavigatesAndRemovesThroughAppStatePath() async throws {
        let fixture = makeFixture()
        let notification = PaneNotification(
            paneID: fixture.otherPane.id, paneName: fixture.otherPane.name,
            tabID: fixture.tab.id, tabName: fixture.tab.name, isPriority: true)
        fixture.state.notifications = [notification]

        let response = try await fixture.router.callTool(
            name: "notifications_acknowledge",
            arguments: ["notificationID": .string(notification.id.uuidString)],
            source: fixture.tabSource)
        let result = try decodeMutationResult(response)

        XCTAssertEqual(result.status, "succeeded")
        XCTAssertEqual(result.acknowledgedNotificationID, notification.id)
        XCTAssertEqual(result.activeTabID, fixture.tab.id)
        XCTAssertEqual(result.activePaneID, fixture.otherPane.id)
        XCTAssertTrue(fixture.state.notifications.isEmpty)
        XCTAssertNil(fixture.tab.focusedPaneID)
    }

    func testNotificationAcknowledgementRejectsOutOfScopeAndStaleTargets() async throws {
        let fixture = makeFixture()
        let otherTabNotification = PaneNotification(
            paneID: fixture.secondTabPane.id, paneName: fixture.secondTabPane.name,
            tabID: fixture.secondTab.id, tabName: fixture.secondTab.name, isPriority: false)
        fixture.state.notifications = [otherTabNotification]

        do {
            _ = try await fixture.router.callTool(
                name: "notifications_acknowledge",
                arguments: ["notificationID": .string(otherTabNotification.id.uuidString)],
                source: fixture.tabSource)
            XCTFail("Tab scope must not acknowledge another tab's notification")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("outside scope"))
        }
        XCTAssertEqual(fixture.state.notifications.count, 1)

        let stale = PaneNotification(
            paneID: UUID(), paneName: "stale", tabID: fixture.tab.id, tabName: fixture.tab.name, isPriority: false)
        fixture.state.notifications = [stale]
        do {
            _ = try await fixture.router.callTool(
                name: "notifications_acknowledge",
                arguments: ["notificationID": .string(stale.id.uuidString)],
                source: fixture.globalSource)
            XCTFail("Stale notification targets must be rejected")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("no longer exists"))
        }
        XCTAssertEqual(fixture.state.notifications.map(\.id), [stale.id])
    }

    func testNotificationAcknowledgementTelemetryContainsIDWithoutContent() async throws {
        let fixture = makeFixture()
        let notification = PaneNotification(
            paneID: fixture.otherPane.id, paneName: fixture.otherPane.name,
            tabID: fixture.tab.id, tabName: fixture.tab.name, isPriority: true)
        fixture.state.notifications = [notification]
        TracingService.shared.enableTestCapture()

        _ = try await fixture.router.callTool(
            name: "notifications_acknowledge",
            arguments: ["notificationID": .string(notification.id.uuidString)],
            source: fixture.tabSource)

        let event = try XCTUnwrap(
            TracingService.shared.recordedEventsForTesting.last {
                $0.name == "agent_control.mutation" && $0.attributes["tool"] == "notifications_acknowledge"
            })
        XCTAssertEqual(event.attributes["notification.id"], notification.id.uuidString)
        XCTAssertNil(event.attributes["notification.text"])
        XCTAssertNil(event.attributes["payload"])
    }

    func testProfileAndHarnessConfigurationRequireGlobalScope() async throws {
        let fixture = makeFixture()

        for name in ["profiles_create", "harnesses_set_enabled", "harnesses_configure_cli_option"] {
            do {
                _ = try await fixture.router.callTool(
                    name: name,
                    arguments: name == "profiles_create"
                        ? ["name": .string("Denied"), "harness": .string("claude")]
                        : ["harness": .string("codex"), "enabled": .bool(true)],
                    source: fixture.paneSource)
                XCTFail("\(name) must require Global scope")
            } catch let error as MCPError {
                XCTAssertTrue(String(describing: error).contains("Global scope"))
            }
        }
        XCTAssertTrue(fixture.settings.profiles.isEmpty)
    }

    func testHarnessConfigurationPreservesCustomOptionsAndNormalizesPresets() async throws {
        let fixture = makeFixture()
        let custom = CLIOptionConfig(
            id: "--custom-review", label: "Custom Review", description: "Test option", isAvailable: true,
            isDefaultEnabled: false, isUserAdded: true, customIsStringType: true)
        fixture.settings.cliOptions.append(custom)

        let response = try await fixture.router.callTool(
            name: "harnesses_configure_cli_option",
            arguments: [
                "harness": .string("claude"),
                "optionID": .string("--continue"),
                "isAvailable": .bool(true),
                "isDefaultEnabled": .bool(true),
                "presetValues": .array([.string(" high "), .string(""), .string("high"), .string("low")]),
                "allowsMultipleValues": .bool(true),
            ],
            source: fixture.globalSource)
        let result = try decodeMutationResult(response)
        let option = result.harness?.cliOptions.first { $0.id == "--continue" }
        XCTAssertEqual(option?.isAvailable, true)
        XCTAssertEqual(option?.isDefaultEnabled, true)
        XCTAssertEqual(option?.presetValues, ["high", "low"])
        XCTAssertEqual(option?.allowsMultipleValues, true)
        XCTAssertTrue(fixture.settings.cliOptions.contains { $0.id == custom.id && $0.isUserAdded })
    }

    func testProfileValidationRejectsUnknownOptionsAndControlledEnvironment() async throws {
        let fixture = makeFixture()

        do {
            _ = try await fixture.router.callTool(
                name: "profiles_create",
                arguments: [
                    "name": .string("Invalid"),
                    "harness": .string("claude"),
                    "cliOptions": .array([
                        .object(["id": .string("--not-a-real-option"), "enabled": .bool(true)])
                    ]),
                ],
                source: fixture.globalSource)
            XCTFail("Unknown options must be rejected")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("Unknown CLI option"))
        }

        do {
            _ = try await fixture.router.callTool(
                name: "profiles_create",
                arguments: [
                    "name": .string("Invalid Environment"),
                    "harness": .string("opencode"),
                    "environment": .array([
                        .object([
                            "id": .string("OPENCODE_CONFIG_CONTENT"),
                            "enabled": .bool(true),
                            "value": .string("{}"),
                        ])
                    ]),
                ],
                source: fixture.globalSource)
            XCTFail("App-controlled environment variables must be rejected")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("controlled"))
        }
        XCTAssertTrue(fixture.settings.profiles.isEmpty)
    }

    func testPaneCreationRejectsUnavailableHarnessOptionsBeforeWorktreeSetup() async throws {
        let fixture = makeFixture()
        fixture.settings.codexCliOptions = [
            CLIOptionConfig(
                id: "--prompt", label: "Prompt", description: "Initial prompt", isAvailable: false,
                isDefaultEnabled: false)
        ]

        do {
            _ = try await fixture.router.callTool(
                name: "panes_create",
                arguments: [
                    "tabID": .string(fixture.secondTab.id.uuidString),
                    "worktreeRef": .string("prompt-test"),
                    "harness": .string("codex"),
                    "cliOptions": .array([
                        .object(["id": .string("--prompt"), "enabled": .bool(true)])
                    ]),
                ],
                source: fixture.globalSource)
            XCTFail("Unavailable harness options must be rejected")
        } catch let error as MCPError {
            XCTAssertTrue(String(describing: error).contains("unavailable"))
        }
        XCTAssertEqual(fixture.state.tabs.flatMap(\.panes).count, 3)
    }

    private struct Fixture {
        let state: AppState
        let settings: AppSettings
        let router: AgentControlMutationRouter
        let tab: Tab
        let firstPane: Pane
        let otherPane: Pane
        let secondTab: Tab
        let secondTabPane: Pane
        let paneSource: AgentControlSource
        let tabSource: AgentControlSource
        let globalSource: AgentControlSource
    }

    private func makeFixture() -> Fixture {
        let state = AppState()
        let settings = AppSettings()
        let tab = Tab(name: "First Tab", directory: URL(filePath: NSTemporaryDirectory()))
        let firstPane = tab.addPane(
            name: "First Pane", harness: .claude,
            worktreeDirectory: URL(filePath: "/tmp/first-worktree"), appSettings: settings)
        let otherPane = tab.addPane(
            name: "Other Pane", harness: .codex,
            worktreeDirectory: URL(filePath: "/tmp/other-worktree"), appSettings: settings)
        let secondTab = Tab(name: "Second Tab", directory: URL(filePath: NSTemporaryDirectory()))
        let secondTabPane = secondTab.addPane(
            name: "Second Tab Pane", harness: .shell,
            worktreeDirectory: URL(filePath: "/tmp/second-tab-worktree"), appSettings: settings)
        state.tabs = [tab, secondTab]
        state.activeTabID = tab.id
        state.activePaneID = firstPane.id

        let router = AgentControlMutationRouter(appState: state, appSettings: settings)
        let paneSource = AgentControlSource(
            paneID: firstPane.id, paneName: firstPane.name, tabID: tab.id, tabName: tab.name, scope: .pane)
        let tabSource = AgentControlSource(
            paneID: firstPane.id, paneName: firstPane.name, tabID: tab.id, tabName: tab.name, scope: .tab)
        let globalSource = AgentControlSource(
            paneID: firstPane.id, paneName: firstPane.name, tabID: tab.id, tabName: tab.name, scope: .global)
        return Fixture(
            state: state, settings: settings, router: router, tab: tab, firstPane: firstPane, otherPane: otherPane,
            secondTab: secondTab, secondTabPane: secondTabPane, paneSource: paneSource,
            tabSource: tabSource, globalSource: globalSource)
    }

    private func toolText(_ content: [Tool.Content]) -> String? {
        guard case .text(let text, _, _) = content.first else { return nil }
        return text
    }

    private func decodeMutationResult(_ response: CallTool.Result) throws -> AgentControlMutationResult {
        try JSONDecoder().decode(
            AgentControlMutationResult.self,
            from: Data(try XCTUnwrap(toolText(response.content)).utf8))
    }

    private func value<T: Encodable>(for value: T) throws -> MCP.Value {
        try JSONDecoder().decode(
            MCP.Value.self,
            from: JSONEncoder().encode(value))
    }
}
