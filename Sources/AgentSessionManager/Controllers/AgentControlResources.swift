import Foundation
import MCP

enum AgentControlResourceURI: Equatable {
    case workspace
    case profiles
    case harnesses
    case statusLines
    case notifications
    case diagnosticSummary
    case diagnosticTraces
    case diagnosticInvariants
    case diagnosticLogs
    case tab(UUID)
    case pane(UUID)
    case profile(UUID)
    case paneStatus(UUID)

    init?(_ rawValue: String) {
        guard let url = URL(string: rawValue), url.scheme == "agent-session-manager",
            let host = url.host, !host.isEmpty
        else { return nil }

        let components = url.path.split(separator: "/").map(String.init)
        guard components.allSatisfy({ !$0.isEmpty }) else { return nil }
        if host == "diagnostics" {
            guard components.count == 1 else { return nil }
            switch components[0] {
            case "summary": self = .diagnosticSummary
            case "traces": self = .diagnosticTraces
            case "invariants": self = .diagnosticInvariants
            case "logs": self = .diagnosticLogs
            default: return nil
            }
            return
        }
        if components.isEmpty {
            switch host {
            case "workspace": self = .workspace
            case "profiles": self = .profiles
            case "harnesses": self = .harnesses
            case "status-lines": self = .statusLines
            case "notifications": self = .notifications
            default: return nil
            }
            return
        }

        guard components.count == 1 || (host == "status-lines" && components.count == 2) else {
            return nil
        }
        if host == "status-lines", components[0] == "pane", let uuid = UUID(uuidString: components[1]) {
            self = .paneStatus(uuid)
        } else if components.count == 1, let uuid = UUID(uuidString: components[0]) {
            switch host {
            case "tabs": self = .tab(uuid)
            case "panes": self = .pane(uuid)
            case "profiles": self = .profile(uuid)
            default: return nil
            }
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .workspace: return "agent-session-manager://workspace"
        case .profiles: return "agent-session-manager://profiles"
        case .harnesses: return "agent-session-manager://harnesses"
        case .statusLines: return "agent-session-manager://status-lines"
        case .notifications: return "agent-session-manager://notifications"
        case .diagnosticSummary: return "agent-session-manager://diagnostics/summary"
        case .diagnosticTraces: return "agent-session-manager://diagnostics/traces"
        case .diagnosticInvariants: return "agent-session-manager://diagnostics/invariants"
        case .diagnosticLogs: return "agent-session-manager://diagnostics/logs"
        case .tab(let id): return "agent-session-manager://tabs/\(id.uuidString)"
        case .pane(let id): return "agent-session-manager://panes/\(id.uuidString)"
        case .profile(let id): return "agent-session-manager://profiles/\(id.uuidString)"
        case .paneStatus(let id): return "agent-session-manager://status-lines/pane/\(id.uuidString)"
        }
    }

    var kind: String {
        switch self {
        case .workspace: return "workspace"
        case .profiles, .profile: return "profiles"
        case .harnesses: return "harnesses"
        case .statusLines, .paneStatus: return "status_lines"
        case .notifications: return "notifications"
        case .diagnosticSummary: return "diagnostic_summary"
        case .diagnosticTraces: return "diagnostic_traces"
        case .diagnosticInvariants: return "diagnostic_invariants"
        case .diagnosticLogs: return "diagnostic_logs"
        case .tab: return "tab"
        case .pane: return "pane"
        }
    }
}

struct AgentControlWorkspaceSnapshot: Codable {
    let activeTabID: UUID?
    let activePaneID: UUID?
    let tabs: [AgentControlTabSnapshot]
}

struct AgentControlTabSnapshot: Codable {
    let id: UUID
    let name: String
    let directory: String
    let baseBranchOverride: String?
    let focusedPaneID: UUID?
    let activity: String
    let panes: [AgentControlPaneSnapshot]
}

struct AgentControlPaneSnapshot: Codable {
    let id: UUID
    let name: String
    let harness: Harness
    let processState: String
    let activity: String
    let setupState: String?
    let worktreePath: String?
    let worktreeIsManaged: Bool
    let profileID: UUID?
    let profileName: String?
    let extraArgs: [String]
    let agentControlInjectionEnabled: Bool
    let statusData: StatusLineData?
    let statusLineConfig: StatusLineConfig?
}

struct AgentControlProfileSnapshot: Codable {
    let id: UUID
    let name: String
    let harness: Harness
    let cliOptions: [AgentControlCLIOptionSnapshot]
    let environment: [AgentControlEnvironmentSnapshot]
    let statusLineConfig: StatusLineConfig?
}

struct AgentControlCLIOptionSnapshot: Codable {
    let id: String
    let label: String
    let description: String
    let isAvailable: Bool
    let isDefaultEnabled: Bool
    let isUserAdded: Bool
    let customIsStringType: Bool
    let presetValues: [String]
    let allowsMultipleValues: Bool
    let isEnabled: Bool?
    let value: String?
    let values: [String]?
    let showOnPaneCreate: Bool?
}

struct AgentControlEnvironmentSnapshot: Codable {
    let id: String
    let isEnabled: Bool
    let showOnPaneCreate: Bool
    let isConfigured: Bool
}

struct AgentControlHarnessSnapshot: Codable {
    let harness: Harness
    let displayName: String
    let isEnabled: Bool
    let cliOptions: [AgentControlCLIOptionSnapshot]
    let environment: [AgentControlEnvironmentCatalogSnapshot]
}

struct AgentControlEnvironmentCatalogSnapshot: Codable {
    let id: String
    let label: String
    let description: String
    let isAvailable: Bool
    let isDefaultEnabled: Bool
    let isUserAdded: Bool
    let isAppControlled: Bool
}

struct AgentControlPaneStatusSnapshot: Codable {
    let paneID: UUID
    let tabID: UUID
    let data: StatusLineData?
    let claudeLifecycle: String
    let isOpenCodeWorking: Bool
}

struct AgentControlStatusLineSnapshot: Codable {
    let globalConfiguration: StatusLineConfig?
    let profileConfigurations: [AgentControlProfileStatusSnapshot]
    let panes: [AgentControlPaneStatusSnapshot]
}

struct AgentControlProfileStatusSnapshot: Codable {
    let profileID: UUID
    let profileName: String
    let configuration: StatusLineConfig?
}

struct AgentControlNotificationSnapshot: Codable {
    let id: UUID
    let paneID: UUID
    let paneName: String
    let tabID: UUID
    let tabName: String
    let isPriority: Bool
    let timestamp: Date
    let kind: NotificationKind
    let reason: String?
    let prNumber: Int?
    let prTitle: String?
}

@MainActor
final class AgentControlResourceRouter {
    private let appState: AppState
    private let appSettings: AppSettings
    private let diagnostics: AgentControlDiagnosticsRouter
    private let mutations: AgentControlMutationRouter

    init(appState: AppState, appSettings: AppSettings) {
        self.appState = appState
        self.appSettings = appSettings
        diagnostics = AgentControlDiagnosticsRouter(appState: appState, appSettings: appSettings)
        mutations = AgentControlMutationRouter(appState: appState, appSettings: appSettings)
    }

    func resources() -> [Resource] {
        [
            Resource(
                name: "Agent Session Manager workspace",
                uri: AgentControlResourceURI.workspace.rawValue,
                description: "The scoped tabs, panes, active IDs, and activity state.",
                mimeType: "application/json"),
            Resource(
                name: "Agent Session Manager profiles",
                uri: AgentControlResourceURI.profiles.rawValue,
                description: "Read-only profiles with environment values redacted.",
                mimeType: "application/json"),
            Resource(
                name: "Agent Session Manager harnesses",
                uri: AgentControlResourceURI.harnesses.rawValue,
                description: "Read-only harness and CLI option catalogs. Global scope required.",
                mimeType: "application/json"),
            Resource(
                name: "Agent Session Manager status lines",
                uri: AgentControlResourceURI.statusLines.rawValue,
                description: "Status-line configuration and scoped current status data.",
                mimeType: "application/json"),
            Resource(
                name: "Agent Session Manager notifications",
                uri: AgentControlResourceURI.notifications.rawValue,
                description: "Scoped pane notifications.",
                mimeType: "application/json"),
        ] + diagnostics.resources()
    }

    func tools() -> [Tool] {
        diagnostics.tools() + mutations.tools()
    }

    func callTool(
        name: String, arguments: [String: Value]?, source: AgentControlSource
    ) async throws -> CallTool.Result {
        if mutations.handles(name) {
            return try await mutations.callTool(name: name, arguments: arguments, source: source)
        }
        return try await diagnostics.callTool(name: name, arguments: arguments, source: source)
    }

    func resourceTemplates() -> [Resource.Template] {
        [
            Resource.Template(
                uriTemplate: "agent-session-manager://tabs/{tabID}",
                name: "Agent Session Manager tab",
                description: "A scoped tab snapshot addressed by stable tab ID.",
                mimeType: "application/json"),
            Resource.Template(
                uriTemplate: "agent-session-manager://panes/{paneID}",
                name: "Agent Session Manager pane",
                description: "A scoped pane snapshot addressed by stable pane ID.",
                mimeType: "application/json"),
            Resource.Template(
                uriTemplate: "agent-session-manager://profiles/{profileID}",
                name: "Agent Session Manager profile",
                description: "A read-only profile addressed by stable profile ID.",
                mimeType: "application/json"),
            Resource.Template(
                uriTemplate: "agent-session-manager://status-lines/pane/{paneID}",
                name: "Agent Session Manager pane status",
                description: "Current structured status data for a visible pane.",
                mimeType: "application/json"),
        ]
    }

    func read(uri: String, source: AgentControlSource) async throws -> String {
        let parsedURL = URL(string: uri)
        let diagnosticQuery: AgentControlDiagnosticResourceQuery?
        if let parsedURL, parsedURL.host == "diagnostics" {
            diagnosticQuery = try AgentControlDiagnosticResourceQuery(
                queryItems: URLComponents(url: parsedURL, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        } else {
            diagnosticQuery = nil
        }
        guard let resource = AgentControlResourceURI(uri) else {
            recordRead(uri: uri, source: source, kind: "unknown", result: "invalid_uri")
            throw MCPError.invalidParams("Unknown Agent Session Manager resource")
        }

        do {
            let data: Data
            switch resource {
            case .workspace:
                data = try JSONEncoder().encode(workspaceSnapshot(source: source))
            case .profiles:
                data = try JSONEncoder().encode(profileSnapshots(source: source))
            case .harnesses:
                guard source.scope == .global else {
                    throw MCPError.invalidRequest(
                        "Global scope is required for harness catalogs; current scope is \(source.scope.displayName)")
                }
                data = try JSONEncoder().encode(harnessSnapshots())
            case .statusLines:
                data = try JSONEncoder().encode(statusLineSnapshot(source: source))
            case .notifications:
                data = try JSONEncoder().encode(notificationSnapshots(source: source))
            case .diagnosticSummary, .diagnosticTraces, .diagnosticInvariants, .diagnosticLogs:
                let diagnostic = try await diagnostics.read(
                    uri: resource, source: source, resourceQuery: diagnosticQuery)
                recordRead(uri: uri, source: source, kind: resource.kind, result: "success")
                return diagnostic
            case .tab(let id):
                guard let tab = visibleTabs(source: source).first(where: { $0.id == id }) else {
                    throw MCPError.invalidParams("Agent Session Manager resource not found")
                }
                data = try JSONEncoder().encode(tabSnapshot(tab, source: source))
            case .pane(let id):
                guard let pane = visiblePane(id: id, source: source) else {
                    throw MCPError.invalidParams("Agent Session Manager resource not found")
                }
                data = try JSONEncoder().encode(paneSnapshot(pane))
            case .profile(let id):
                guard let profile = visibleProfiles(source: source).first(where: { $0.id == id }) else {
                    throw MCPError.invalidParams("Agent Session Manager resource not found")
                }
                data = try JSONEncoder().encode(profileSnapshot(profile))
            case .paneStatus(let id):
                guard let pane = visiblePane(id: id, source: source) else {
                    throw MCPError.invalidParams("Agent Session Manager resource not found")
                }
                data = try JSONEncoder().encode(paneStatusSnapshot(pane))
            }
            guard let result = String(data: data, encoding: .utf8) else {
                throw MCPError.internalError("Unable to encode resource")
            }
            recordRead(uri: uri, source: source, kind: resource.kind, result: "success")
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MCPError {
            recordRead(uri: uri, source: source, kind: resource.kind, result: "rejected")
            throw error
        } catch {
            recordRead(uri: uri, source: source, kind: resource.kind, result: "failed")
            throw MCPError.internalError("Unable to read Agent Session Manager resource")
        }
    }

    func visibleTabs(source: AgentControlSource) -> [Tab] {
        switch source.scope {
        case .global: return appState.tabs
        case .tab:
            return appState.tabs.filter { $0.id == source.tabID }
        case .pane:
            return appState.tabs.filter { $0.id == source.tabID }
        }
    }

    func visiblePane(id: UUID, source: AgentControlSource) -> Pane? {
        visibleTabs(source: source).flatMap(\.panes).first { pane in
            guard pane.id == id else { return false }
            return source.scope != .pane || pane.id == source.paneID
        }
    }

    func workspaceSnapshot(source: AgentControlSource) -> AgentControlWorkspaceSnapshot {
        let tabs = visibleTabs(source: source).map { tabSnapshot($0, source: source) }
        let activeTabID = tabs.contains { $0.id == appState.activeTabID } ? appState.activeTabID : nil
        let activePaneID =
            tabs.filter { $0.id == activeTabID }.flatMap(\.panes).contains { $0.id == appState.activePaneID }
            ? appState.activePaneID : nil
        return AgentControlWorkspaceSnapshot(activeTabID: activeTabID, activePaneID: activePaneID, tabs: tabs)
    }

    func tabSnapshot(_ tab: Tab, source: AgentControlSource) -> AgentControlTabSnapshot {
        let panes = tab.panes.filter { pane in
            source.scope != .pane || pane.id == source.paneID
        }.map(paneSnapshot)
        return AgentControlTabSnapshot(
            id: tab.id,
            name: tab.name,
            directory: tab.directory.path,
            baseBranchOverride: tab.baseBranchOverride,
            focusedPaneID: panes.contains { $0.id == tab.focusedPaneID } ? tab.focusedPaneID : nil,
            activity: tabActivityState(panes.map { activityState($0.activity) }).rawValue,
            panes: panes)
    }

    func paneSnapshot(_ pane: Pane) -> AgentControlPaneSnapshot {
        let profile = pane.profileID.flatMap { id in appSettings.profiles.first { $0.id == id } }
        let monitor = pane.statusLineMonitor
        return AgentControlPaneSnapshot(
            id: pane.id,
            name: pane.name,
            harness: pane.harness,
            processState: processState(pane),
            activity: paneActivity(pane),
            setupState: setupState(pane.setupState, recovery: pane.codexContinuationRecovery),
            worktreePath: pane.worktreePath?.path,
            worktreeIsManaged: pane.worktreeIsManaged,
            profileID: pane.profileID,
            profileName: profile?.name,
            extraArgs: pane.extraArgs.map { argument in
                guard argument.hasPrefix("-") else { return "<redacted>" }
                guard let equals = argument.firstIndex(of: "=") else { return argument }
                return "\(argument[..<equals])=<redacted>"
            },
            agentControlInjectionEnabled: pane.agentControlInjectionEnabled,
            statusData: monitor?.currentData,
            statusLineConfig: profile?.statusLineConfig ?? appSettings.statusLineConfig)
    }

    func profileSnapshots(source: AgentControlSource) -> [AgentControlProfileSnapshot] {
        visibleProfiles(source: source).map(profileSnapshot)
    }

    func profileSnapshot(_ profile: Profile) -> AgentControlProfileSnapshot {
        AgentControlProfileSnapshot(
            id: profile.id,
            name: profile.name,
            harness: profile.harness,
            cliOptions: profile.cliOptions.map {
                AgentControlCLIOptionSnapshot(
                    id: $0.id, label: $0.id, description: "Profile CLI option",
                    isAvailable: true, isDefaultEnabled: false, isUserAdded: false,
                    customIsStringType: false, presetValues: [], allowsMultipleValues: false,
                    isEnabled: $0.isEnabled, value: $0.value, values: $0.values,
                    showOnPaneCreate: $0.showOnPaneCreate)
            },
            environment: profile.envVars.map {
                AgentControlEnvironmentSnapshot(
                    id: $0.id, isEnabled: $0.isEnabled, showOnPaneCreate: $0.showOnPaneCreate,
                    isConfigured: !$0.value.isEmpty)
            },
            statusLineConfig: profile.statusLineConfig)
    }

    func harnessSnapshots() -> [AgentControlHarnessSnapshot] {
        Harness.allCases.map { harness in
            let options: [CLIOptionConfig]
            let environment: [EnvVarConfig]
            switch harness {
            case .claude:
                options = appSettings.cliOptions
                environment = appSettings.envVarOptions
            case .codex:
                options = appSettings.codexCliOptions
                environment = []
            case .cursor:
                options = appSettings.cursorCliOptions
                environment = []
            case .opencode:
                options = appSettings.opencodeCliOptions
                environment = appSettings.opencodeEnvVarOptions
            case .shell:
                options = []
                environment = []
            }
            return AgentControlHarnessSnapshot(
                harness: harness,
                displayName: harness.displayName,
                isEnabled: appSettings.isActive(harness),
                cliOptions: options.map {
                    AgentControlCLIOptionSnapshot(
                        id: $0.id, label: $0.label, description: $0.description,
                        isAvailable: $0.isAvailable, isDefaultEnabled: $0.isDefaultEnabled,
                        isUserAdded: $0.isUserAdded, customIsStringType: $0.customIsStringType,
                        presetValues: $0.presetValues, allowsMultipleValues: $0.allowsMultipleValues,
                        isEnabled: nil, value: nil, values: nil, showOnPaneCreate: nil)
                },
                environment: environment.map {
                    AgentControlEnvironmentCatalogSnapshot(
                        id: $0.id, label: $0.label, description: $0.description,
                        isAvailable: $0.isAvailable, isDefaultEnabled: $0.isDefaultEnabled,
                        isUserAdded: $0.isUserAdded, isAppControlled: $0.isAppControlled)
                })
        }
    }

    func statusLineSnapshot(source: AgentControlSource) -> AgentControlStatusLineSnapshot {
        let profiles = visibleProfiles(source: source).map {
            AgentControlProfileStatusSnapshot(
                profileID: $0.id, profileName: $0.name, configuration: $0.statusLineConfig)
        }
        let panes = visibleTabs(source: source).flatMap(\.panes).filter {
            source.scope != .pane || $0.id == source.paneID
        }.map(paneStatusSnapshot)
        return AgentControlStatusLineSnapshot(
            globalConfiguration: source.scope == .global ? appSettings.statusLineConfig : nil,
            profileConfigurations: profiles,
            panes: panes)
    }

    func visibleProfiles(source: AgentControlSource) -> [Profile] {
        guard source.scope != .global else { return appSettings.profiles }
        let profileIDs = Set(
            visibleTabs(source: source)
                .flatMap(\.panes)
                .filter { source.scope != .pane || $0.id == source.paneID }
                .compactMap(\.profileID)
        )
        return appSettings.profiles.filter { profileIDs.contains($0.id) }
    }

    func paneStatusSnapshot(_ pane: Pane) -> AgentControlPaneStatusSnapshot {
        AgentControlPaneStatusSnapshot(
            paneID: pane.id,
            tabID: pane.tab?.id ?? UUID(),
            data: pane.statusLineMonitor?.currentData,
            claudeLifecycle: {
                switch pane.statusLineMonitor?.claudeLifecycle {
                case .working: return "working"
                case .stopped: return "stopped"
                default: return "unknown"
                }
            }(),
            isOpenCodeWorking: pane.statusLineMonitor?.isOpenCodeWorking ?? false)
    }

    func notificationSnapshots(source: AgentControlSource) -> [AgentControlNotificationSnapshot] {
        appState.notifications.filter { notification in
            switch source.scope {
            case .global: return true
            case .tab: return notification.tabID == source.tabID
            case .pane: return notification.paneID == source.paneID
            }
        }.map {
            AgentControlNotificationSnapshot(
                id: $0.id, paneID: $0.paneID, paneName: $0.paneName, tabID: $0.tabID,
                tabName: $0.tabName, isPriority: $0.isPriority, timestamp: $0.timestamp,
                kind: $0.kind, reason: $0.reason, prNumber: $0.prNumber, prTitle: $0.prTitle)
        }
    }

    private func processState(_ pane: Pane) -> String {
        switch pane.terminalController?.processState {
        case .running: return "running"
        case .exited: return "exited"
        default: return "idle"
        }
    }

    private func paneActivity(_ pane: Pane) -> String {
        let state = paneActivityState(
            processState: pane.terminalController?.processState,
            isWorking: pane.statusLineMonitor?.isClaudeWorking == true
                || pane.statusLineMonitor?.isOpenCodeWorking == true
                || pane.statusLineMonitor?.isCodexWorking == true,
            isStopped: pane.statusLineMonitor?.isClaudeStopped == true
                || pane.statusLineMonitor?.isCursorStopped == true
                || pane.statusLineMonitor?.isCodexStopped == true,
            sessionState: pane.statusLineMonitor?.currentData?.sessionStatus?.state,
            hasNotification: appState.notifications.contains { $0.paneID == pane.id })
        return state.rawValue
    }

    private func activityState(_ rawValue: String) -> PaneActivityState {
        switch rawValue {
        case "working": return .working
        case "stopped": return .stopped
        case "waiting": return .waiting
        default: return .idle
        }
    }

    private func setupState(
        _ state: PaneSetupState?, recovery: CodexContinuationRecovery?
    ) -> String? {
        if recovery != nil { return "codex_continuation_unavailable" }
        switch state {
        case .loading: return "loading"
        case .failed: return "failed"
        case nil: return nil
        }
    }

    private func recordRead(uri: String, source: AgentControlSource, kind: String, result: String) {
        TracingService.shared.record(
            "agent_control.resource.read",
            attributes: [
                "pane.id": source.paneID.uuidString,
                "pane.name": source.paneName,
                "tab.id": source.tabID.uuidString,
                "tab.name": source.tabName,
                "scope": source.scope.rawValue,
                "resource.kind": kind,
                "result": result,
            ])
    }
}

extension PaneActivityState {
    var rawValue: String {
        switch self {
        case .idle: return "idle"
        case .working: return "working"
        case .stopped: return "stopped"
        case .waiting: return "waiting"
        }
    }
}
