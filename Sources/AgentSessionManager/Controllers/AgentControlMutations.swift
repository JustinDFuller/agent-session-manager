import Foundation
import MCP

struct AgentControlCLIOptionInput: Codable, Sendable {
    let id: String
    let enabled: Bool
    let value: String?
    let values: [String]?
}

struct AgentControlEnvironmentInput: Codable, Sendable {
    let id: String
    let enabled: Bool
    let value: String
}

struct AgentControlProfileOptionPatch: Codable, Sendable {
    let id: String
    let enabled: Bool
    let value: String?
    let values: [String]?
    let showOnPaneCreate: Bool?
}

struct AgentControlProfileEnvironmentPatch: Codable, Sendable {
    let id: String
    let enabled: Bool
    let value: String?
    let showOnPaneCreate: Bool?
}

struct AgentControlProfileCreateArguments: Codable, Sendable {
    let name: String
    let harness: Harness
    let cliOptions: [AgentControlProfileOptionPatch]?
    let environment: [AgentControlProfileEnvironmentPatch]?
}

struct AgentControlProfileUpdateArguments: Codable, Sendable {
    let profileID: String
    let name: String?
    let harness: Harness?
    let cliOptions: [AgentControlProfileOptionPatch]?
    let environment: [AgentControlProfileEnvironmentPatch]?
}

struct AgentControlProfileIDArguments: Codable, Sendable {
    let profileID: String
}

struct AgentControlProfileReorderArguments: Codable, Sendable {
    let profileID: String
    let destinationIndex: Int
}

struct AgentControlHarnessEnabledArguments: Codable, Sendable {
    let harness: Harness
    let enabled: Bool
}

struct AgentControlCLIOptionConfigArguments: Codable, Sendable {
    let harness: Harness
    let optionID: String
    let isAvailable: Bool?
    let isDefaultEnabled: Bool?
    let presetValues: [String]?
    let allowsMultipleValues: Bool?
}

struct AgentControlGlobalStatusLineArguments: Codable {
    let configuration: StatusLineConfig
}

struct AgentControlProfileStatusLineArguments: Codable {
    let profileID: String
    let configuration: StatusLineConfig
}

struct AgentControlNotificationAckArguments: Codable, Sendable {
    let notificationID: String
}

struct AgentControlTabCreateArguments: Codable, Sendable {
    let name: String
    let directory: String
    let baseBranch: String?
}

struct AgentControlTabIDArguments: Codable, Sendable {
    let tabID: String
}

struct AgentControlTabReorderArguments: Codable, Sendable {
    let tabID: String
    let destinationIndex: Int
}

struct AgentControlPaneCreateArguments: Codable, Sendable {
    let tabID: String
    let worktreeRef: String
    let harness: Harness
    let profileID: String?
    let cliOptions: [AgentControlCLIOptionInput]?
    let environment: [AgentControlEnvironmentInput]?
    let defaultBranch: String?
    let baseRef: WorktreeBaseRef?
    let priority: Bool?
    let agentControlInjectionEnabled: Bool?
    let manageExistingWorktree: Bool?
}

struct AgentControlPaneIDArguments: Codable, Sendable {
    let paneID: String
}

struct AgentControlPaneCleanupArguments: Codable, Sendable {
    let paneID: String
    let cleanup: String?
}

struct AgentControlPaneReorderArguments: Codable, Sendable {
    let paneID: String
    let destinationIndex: Int
}

struct AgentControlTabCleanupArguments: Codable, Sendable {
    let tabID: String
    let cleanup: String?
}

struct AgentControlCleanupResult: Codable, Sendable {
    let paneID: UUID
    let status: String
    let error: String?
}

struct AgentControlMutationResult: Codable, Sendable {
    let operation: String
    let status: String
    let tabID: UUID?
    let paneID: UUID?
    let profileID: UUID?
    let activeTabID: UUID?
    let activePaneID: UUID?
    let focusedPaneID: UUID?
    let tabOrder: [UUID]?
    let paneOrder: [UUID]?
    let cleanup: [AgentControlCleanupResult]
    let tab: AgentControlTabSnapshot?
    let pane: AgentControlPaneSnapshot?
    let profile: AgentControlProfileSnapshot?
    let profileOrder: [UUID]?
    let harness: AgentControlHarnessSnapshot?
    let activeHarnesses: [Harness]?
    let statusLineConfiguration: StatusLineConfig?
    let acknowledgedNotificationID: UUID?
    let error: String?
}

@MainActor
final class AgentControlMutationRouter {
    let appState: AppState
    let appSettings: AppSettings

    private static let mutationNames: Set<String> = [
        "tabs_create", "tabs_delete", "tabs_focus", "tabs_reorder",
        "panes_create", "panes_delete", "panes_focus", "panes_restart", "panes_reorder",
        "profiles_create", "profiles_update", "profiles_delete", "profiles_reorder",
        "status_lines_update_global", "status_lines_update_profile", "status_lines_clear_profile_override",
        "notifications_acknowledge",
        "harnesses_set_enabled", "harnesses_configure_cli_option",
    ]

    init(appState: AppState, appSettings: AppSettings) {
        self.appState = appState
        self.appSettings = appSettings
    }

    func handles(_ name: String) -> Bool {
        Self.mutationNames.contains(name)
    }

    private static let harnessNames = Harness.allCases.map(\.rawValue)
    private static let cleanupValues = ["keep", "delete"]
    private static let baseRefValues = WorktreeBaseRef.allCases.map(\.rawValue)

    private static let cliOptionInputSchema = AgentControlToolSchema.object(
        "A CLI option to enable or disable for the new pane",
        properties: [
            "id": .string("CLI option catalog ID"),
            "enabled": .boolean("Whether the option is enabled"),
            "value": .string("Single option value, for options that accept one"),
            "values": .array("Option values, for options that accept several", items: .string("Option value")),
        ],
        required: ["id", "enabled"])

    private static let environmentInputSchema = AgentControlToolSchema.object(
        "An environment variable to set for the new pane",
        properties: [
            "id": .string("Environment variable catalog ID"),
            "enabled": .boolean("Whether the variable is set"),
            "value": .string("Environment variable value"),
        ],
        required: ["id", "enabled", "value"])

    private static let profileOptionPatchSchema = AgentControlToolSchema.object(
        "A CLI option patch to apply to the profile",
        properties: [
            "id": .string("CLI option catalog ID"),
            "enabled": .boolean("Whether the option is enabled"),
            "value": .string("Single option value, for options that accept one"),
            "values": .array("Option values, for options that accept several", items: .string("Option value")),
            "showOnPaneCreate": .boolean("Whether to surface this option when creating a pane from the profile"),
        ],
        required: ["id", "enabled"])

    private static let profileEnvironmentPatchSchema = AgentControlToolSchema.object(
        "An environment variable patch to apply to the profile",
        properties: [
            "id": .string("Environment variable catalog ID"),
            "enabled": .boolean("Whether the variable is set"),
            "value": .string("Environment variable value"),
            "showOnPaneCreate": .boolean("Whether to surface this variable when creating a pane from the profile"),
        ],
        required: ["id", "enabled"])

    func tools() -> [Tool] {
        [
            Tool(
                name: "tabs_create",
                description: "Create a tab in the Agent Session Manager workspace. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "name": .string("Tab name"),
                        "directory": .string("Existing directory to open the tab in"),
                        "baseBranch": .string("Base branch override for worktrees created in this tab"),
                    ], required: ["name", "directory"])),
            Tool(
                name: "tabs_delete",
                description: "Delete a tab and optionally clean up its managed worktrees. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "tabID": .string("Tab UUID"),
                        "cleanup": .string(
                            "Whether to keep or delete managed worktrees", enumValues: Self.cleanupValues),
                    ], required: ["tabID"])),
            Tool(
                name: "tabs_focus",
                description: "Activate a visible tab.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    ["tabID": .string("Tab UUID")], required: ["tabID"])),
            Tool(
                name: "tabs_reorder",
                description: "Move a tab to an insertion index. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "tabID": .string("Tab UUID"),
                        "destinationIndex": .integer("Insertion index within the tab list"),
                    ], required: ["tabID", "destinationIndex"])),
            Tool(
                name: "panes_create",
                description: "Create a pane after resolving and preparing its worktree and harness.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "tabID": .string("Tab UUID to create the pane in"),
                        "worktreeRef": .string("Branch, worktree path, or reference to resolve"),
                        "harness": .string("Harness to run in the pane", enumValues: Self.harnessNames),
                        "profileID": .string("Profile UUID to apply"),
                        "cliOptions": .array("CLI options to enable or disable", items: Self.cliOptionInputSchema),
                        "environment": .array("Environment variables to set", items: Self.environmentInputSchema),
                        "defaultBranch": .string("Default branch override for the resolved worktree"),
                        "baseRef": .string(
                            "Base ref to create a new worktree from", enumValues: Self.baseRefValues),
                        "priority": .boolean("Whether notifications from this pane are treated as priority"),
                        "agentControlInjectionEnabled": .boolean("Whether to inject Agent Control into the pane"),
                        "manageExistingWorktree": .boolean(
                            "Whether to manage an existing worktree's lifecycle, when takeover is ambiguous"),
                    ], required: ["tabID", "worktreeRef", "harness"])),
            Tool(
                name: "panes_delete",
                description: "Delete a pane and optionally clean up its managed worktree.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "paneID": .string("Pane UUID"),
                        "cleanup": .string(
                            "Whether to keep or delete a managed worktree", enumValues: Self.cleanupValues),
                    ], required: ["paneID"])),
            Tool(
                name: "panes_focus",
                description: "Activate and focus a visible pane.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    ["paneID": .string("Pane UUID")], required: ["paneID"])),
            Tool(
                name: "panes_restart",
                description: "Restart a visible pane using its existing harness configuration.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    ["paneID": .string("Pane UUID")], required: ["paneID"])),
            Tool(
                name: "panes_reorder",
                description: "Move a pane within its current tab.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "paneID": .string("Pane UUID"),
                        "destinationIndex": .integer("Insertion index within the tab's pane list"),
                    ], required: ["paneID", "destinationIndex"])),
            Tool(
                name: "profiles_create",
                description: "Create a reusable harness profile. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "name": .string("Profile name"),
                        "harness": .string("Harness the profile applies to", enumValues: Self.harnessNames),
                        "cliOptions": .array("CLI option patches", items: Self.profileOptionPatchSchema),
                        "environment": .array(
                            "Environment variable patches", items: Self.profileEnvironmentPatchSchema),
                    ], required: ["name", "harness"])),
            Tool(
                name: "profiles_update",
                description: "Patch a reusable harness profile. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "profileID": .string("Profile UUID"),
                        "name": .string("Profile name"),
                        "harness": .string("Harness the profile applies to", enumValues: Self.harnessNames),
                        "cliOptions": .array("CLI option patches", items: Self.profileOptionPatchSchema),
                        "environment": .array(
                            "Environment variable patches", items: Self.profileEnvironmentPatchSchema),
                    ], required: ["profileID"])),
            Tool(
                name: "profiles_delete",
                description: "Delete a reusable harness profile. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    ["profileID": .string("Profile UUID")], required: ["profileID"])),
            Tool(
                name: "profiles_reorder",
                description: "Move a profile to an insertion index. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "profileID": .string("Profile UUID"),
                        "destinationIndex": .integer("Insertion index within the profile list"),
                    ], required: ["profileID", "destinationIndex"])),
            Tool(
                name: "status_lines_update_global",
                description: "Replace the global status-line configuration. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    ["configuration": .object("Status line configuration", properties: [:])],
                    required: ["configuration"])),
            Tool(
                name: "status_lines_update_profile",
                description: "Replace a profile's custom status-line configuration. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "profileID": .string("Profile UUID"),
                        "configuration": .object("Status line configuration", properties: [:]),
                    ], required: ["profileID", "configuration"])),
            Tool(
                name: "status_lines_clear_profile_override",
                description: "Restore a profile's status line to the global configuration. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    ["profileID": .string("Profile UUID")], required: ["profileID"])),
            Tool(
                name: "notifications_acknowledge",
                description: "Navigate to and acknowledge a visible notification.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    ["notificationID": .string("Notification UUID")], required: ["notificationID"])),
            Tool(
                name: "harnesses_set_enabled",
                description: "Enable or disable a harness for future pane creation. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "harness": .string("Harness to update", enumValues: Self.harnessNames),
                        "enabled": .boolean("Whether the harness is available for pane creation"),
                    ], required: ["harness", "enabled"])),
            Tool(
                name: "harnesses_configure_cli_option",
                description: "Update one harness CLI option catalog entry. Global scope required.",
                inputSchema: AgentControlToolSchema.inputSchema(
                    [
                        "harness": .string("Harness that owns the CLI option", enumValues: Self.harnessNames),
                        "optionID": .string("CLI option catalog ID"),
                        "isAvailable": .boolean("Whether the option is offered for pane creation"),
                        "isDefaultEnabled": .boolean("Whether the option is enabled by default"),
                        "presetValues": .array("Preset values offered for the option", items: .string("Preset value")),
                        "allowsMultipleValues": .boolean("Whether the option accepts multiple values"),
                    ], required: ["harness", "optionID"])),
        ]
    }

    func callTool(
        name: String, arguments: [String: Value]?, source: AgentControlSource
    ) async throws -> CallTool.Result {
        do {
            try Task.checkCancellation()
            let value: AgentControlMutationResult
            switch name {
            case "tabs_create":
                try requireGlobal(source, name: name)
                value = try createTab(decode(AgentControlTabCreateArguments.self, arguments: arguments), source: source)
            case "tabs_delete":
                try requireGlobal(source, name: name)
                value = try await deleteTab(
                    decode(AgentControlTabCleanupArguments.self, arguments: arguments), source: source)
            case "tabs_focus":
                let args = try decode(AgentControlTabIDArguments.self, arguments: arguments)
                value = try focusTab(args, source: source)
            case "tabs_reorder":
                try requireGlobal(source, name: name)
                value = try reorderTab(
                    decode(AgentControlTabReorderArguments.self, arguments: arguments), source: source)
            case "panes_create":
                let args = try decode(AgentControlPaneCreateArguments.self, arguments: arguments)
                value = try await createPane(args, source: source)
            case "panes_delete":
                let args = try decode(AgentControlPaneCleanupArguments.self, arguments: arguments)
                value = try await deletePane(args, source: source)
            case "panes_focus":
                value = try focusPane(
                    decode(AgentControlPaneIDArguments.self, arguments: arguments), source: source)
            case "panes_restart":
                value = try restartPane(
                    decode(AgentControlPaneIDArguments.self, arguments: arguments), source: source)
            case "panes_reorder":
                value = try reorderPane(
                    decode(AgentControlPaneReorderArguments.self, arguments: arguments), source: source)
            case "profiles_create":
                try requireGlobal(source, name: name)
                value = try createProfile(
                    decode(AgentControlProfileCreateArguments.self, arguments: arguments), source: source)
            case "profiles_update":
                try requireGlobal(source, name: name)
                value = try updateProfile(
                    decode(AgentControlProfileUpdateArguments.self, arguments: arguments), source: source)
            case "profiles_delete":
                try requireGlobal(source, name: name)
                value = try deleteProfile(
                    decode(AgentControlProfileIDArguments.self, arguments: arguments), source: source)
            case "profiles_reorder":
                try requireGlobal(source, name: name)
                value = try reorderProfile(
                    decode(AgentControlProfileReorderArguments.self, arguments: arguments), source: source)
            case "status_lines_update_global":
                try requireGlobal(source, name: name)
                value = try updateGlobalStatusLine(
                    decode(AgentControlGlobalStatusLineArguments.self, arguments: arguments), source: source)
            case "status_lines_update_profile":
                try requireGlobal(source, name: name)
                value = try updateProfileStatusLine(
                    decode(AgentControlProfileStatusLineArguments.self, arguments: arguments), source: source)
            case "status_lines_clear_profile_override":
                try requireGlobal(source, name: name)
                value = try clearProfileStatusLine(
                    decode(AgentControlProfileIDArguments.self, arguments: arguments), source: source)
            case "notifications_acknowledge":
                value = try acknowledgeNotification(
                    decode(AgentControlNotificationAckArguments.self, arguments: arguments), source: source)
            case "harnesses_set_enabled":
                try requireGlobal(source, name: name)
                value = try setHarnessEnabled(
                    decode(AgentControlHarnessEnabledArguments.self, arguments: arguments), source: source)
            case "harnesses_configure_cli_option":
                try requireGlobal(source, name: name)
                value = try configureCLIOption(
                    decode(AgentControlCLIOptionConfigArguments.self, arguments: arguments), source: source)
            default:
                throw MCPError.invalidParams("Unknown Agent Session Manager mutation tool")
            }
            return try result(value)
        } catch is CancellationError {
            record(name: name, source: source, result: "cancelled")
            throw CancellationError()
        } catch let error as MCPError {
            record(name: name, source: source, result: "rejected")
            throw error
        } catch {
            record(name: name, source: source, result: "failed")
            throw MCPError.internalError(String(error.localizedDescription.prefix(200)))
        }
    }

    private func createTab(
        _ args: AgentControlTabCreateArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPError.invalidParams("Tab name must not be empty") }
        let directory = URL(filePath: args.directory).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            throw MCPError.invalidParams("Tab directory must exist and be a directory")
        }
        let baseBranch = args.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tab = Tab(
            name: name, directory: directory, baseBranchOverride: baseBranch?.isEmpty == true ? nil : baseBranch)
        appState.tabs.append(tab)
        appState.activeTabID = tab.id
        appState.activePaneID = nil
        SessionPersistence.save(appState: appState)
        let result = mutationResult(
            operation: "tabs_create", status: "succeeded", tabID: tab.id, tab: snapshotTab(tab, source: source))
        record(name: "tabs_create", source: source, result: "succeeded", tabID: tab.id)
        return result
    }

    private func focusTab(
        _ args: AgentControlTabIDArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        let tab = try visibleTab(id: args.tabID, source: source, operation: "tabs_focus")
        appState.switchToTab(id: tab.id, focusModeTabSwitchBehavior: appSettings.focusModeTabSwitchBehavior)
        SessionPersistence.save(appState: appState)
        let result = mutationResult(
            operation: "tabs_focus", status: "succeeded", tabID: tab.id,
            activeTabID: appState.activeTabID, activePaneID: appState.activePaneID,
            tab: snapshotTab(tab, source: source))
        record(name: "tabs_focus", source: source, result: "succeeded", tabID: tab.id)
        return result
    }

    private func reorderTab(
        _ args: AgentControlTabReorderArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        guard
            let tab = appState.tabs.first(where: { $0.id.uuidString.caseInsensitiveCompare(args.tabID) == .orderedSame }
            )
        else {
            throw MCPError.invalidParams("Tab was not found")
        }
        guard (0...appState.tabs.count).contains(args.destinationIndex) else {
            throw MCPError.invalidParams("Tab destination index is out of range")
        }
        guard let index = appState.tabs.firstIndex(where: { $0.id == tab.id }) else {
            throw MCPError.invalidParams("Tab was not found")
        }
        appState.moveTab(from: IndexSet(integer: index), to: args.destinationIndex)
        let result = mutationResult(
            operation: "tabs_reorder", status: "succeeded", tabID: tab.id, tabOrder: appState.tabs.map(\.id))
        record(name: "tabs_reorder", source: source, result: "succeeded", tabID: tab.id)
        return result
    }

    private func createPane(
        _ args: AgentControlPaneCreateArguments, source: AgentControlSource
    ) async throws -> AgentControlMutationResult {
        let tab = try visibleTab(id: args.tabID, source: source, operation: "panes_create")
        guard source.scope != .pane else {
            throw MCPError.invalidRequest("Pane scope cannot create another pane")
        }
        guard args.harness != .shell, appSettings.isActive(args.harness) else {
            throw MCPError.invalidParams("Harness is unavailable for pane creation")
        }
        let profile = try resolveProfile(args.profileID, harness: args.harness)
        let options = try resolveOptions(args.cliOptions, profile: profile, harness: args.harness)
        let environment = try resolveEnvironment(args.environment, profile: profile, harness: args.harness)
        let injection = appSettings.resolvedAgentControlInjectionDecision(
            persistedDecision: args.agentControlInjectionEnabled)
        let defaultBranch = resolveDefaultBranch(args.defaultBranch, tab: tab)
        let baseRef = args.baseRef ?? appSettings.worktreeBaseRef
        let worktreeRef = args.worktreeRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !worktreeRef.isEmpty else { throw MCPError.invalidParams("Worktree reference must not be empty") }

        try Task.checkCancellation()
        let resolved = try await tab.resolveOrAttachWorktree(
            userRef: worktreeRef, defaultBranch: defaultBranch, baseRef: baseRef)
        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            if resolved.wasCreated {
                _ = await tab.removeCreatedWorktree(
                    at: resolved.checkoutURL, deleteBranch: appSettings.deleteBranchWithWorktree)
            }
            throw CancellationError()
        }
        let inUse = appState.isCheckoutInUse(
            directory: tab.directory, checkout: resolved.checkoutURL)
        guard !inUse else { throw MCPError.invalidRequest("A pane with this worktree is already open") }
        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            if resolved.wasCreated {
                _ = await tab.removeCreatedWorktree(
                    at: resolved.checkoutURL, deleteBranch: appSettings.deleteBranchWithWorktree)
            }
            throw CancellationError()
        }

        let managed: Bool
        if resolved.isExternalTakeover {
            switch appSettings.existingWorktreeManagement {
            case .always: managed = true
            case .never: managed = false
            case .ask:
                guard let choice = args.manageExistingWorktree else {
                    throw MCPError.invalidRequest("manageExistingWorktree is required for an existing worktree")
                }
                managed = choice
            }
        } else {
            managed = true
        }

        appState.switchToTab(id: tab.id, focusModeTabSwitchBehavior: appSettings.focusModeTabSwitchBehavior)
        tab.setFocusedPane(id: nil, reason: "agent_control_pane_created")
        let pane = tab.addPaneWithLoadingState(
            name: worktreeRef,
            harness: args.harness,
            worktreeIsManaged: managed,
            profileID: profile?.id,
            agentControlInjectionEnabled: injection,
            appSettings: appSettings)
        pane.bindNotifications(appState: appState, isPriority: args.priority ?? false)
        appState.setActivePane(id: pane.id)
        SessionPersistence.save(appState: appState)

        let effectiveArgs = Tab.applyAutoSessionName(
            tabName: tab.name, paneName: resolved.paneTitle, extraArgs: options,
            harness: args.harness, enabled: appSettings.autoSetSessionName)
        tab.completeSetup(
            for: pane,
            resolved: resolved,
            managed: managed,
            effectiveExtraArgs: effectiveArgs,
            extraEnvVars: environment,
            statusLineConfigOverride: profile?.statusLineConfig,
            appSettings: appSettings)
        SessionPersistence.save(appState: appState)

        let failed: String? = {
            guard case .failed(let error) = pane.setupState else { return nil }
            return error
        }()
        let status = failed == nil ? "succeeded" : "failed"
        let result = mutationResult(
            operation: "panes_create", status: status, tabID: tab.id, paneID: pane.id,
            activeTabID: appState.activeTabID, activePaneID: appState.activePaneID,
            pane: snapshotPane(pane), error: failed)
        record(name: "panes_create", source: source, result: status, tabID: tab.id, paneID: pane.id)
        return result
    }

    private func focusPane(
        _ args: AgentControlPaneIDArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        let pane = try visiblePane(id: args.paneID, source: source, operation: "panes_focus")
        guard let tab = pane.tab else { throw MCPError.internalError("Pane has no parent tab") }
        appState.switchToTab(id: tab.id, focusModeTabSwitchBehavior: .rememberFocus)
        appState.setActivePane(id: pane.id)
        tab.setFocusedPane(id: pane.id, reason: "agent_control")
        SessionPersistence.save(appState: appState)
        let result = mutationResult(
            operation: "panes_focus", status: "succeeded", tabID: tab.id, paneID: pane.id,
            activeTabID: appState.activeTabID, activePaneID: appState.activePaneID,
            focusedPaneID: tab.focusedPaneID, pane: snapshotPane(pane))
        record(name: "panes_focus", source: source, result: "succeeded", tabID: tab.id, paneID: pane.id)
        return result
    }

    private func restartPane(
        _ args: AgentControlPaneIDArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        let pane = try visiblePane(id: args.paneID, source: source, operation: "panes_restart")
        guard let tab = pane.tab else { throw MCPError.internalError("Pane has no parent tab") }
        guard pane.terminalController != nil else {
            throw MCPError.invalidRequest("Pane is not ready to restart")
        }
        let previousToken = pane.restartToken
        tab.restartPane(pane, appSettings: appSettings)
        guard pane.restartToken != previousToken else {
            throw MCPError.internalError("Pane restart did not complete")
        }
        SessionPersistence.save(appState: appState)
        let result = mutationResult(
            operation: "panes_restart", status: "succeeded", tabID: tab.id, paneID: pane.id,
            pane: snapshotPane(pane))
        record(name: "panes_restart", source: source, result: "succeeded", tabID: tab.id, paneID: pane.id)
        return result
    }

    private func reorderPane(
        _ args: AgentControlPaneReorderArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        let pane = try visiblePane(id: args.paneID, source: source, operation: "panes_reorder")
        guard let tab = pane.tab else { throw MCPError.internalError("Pane has no parent tab") }
        guard (0...tab.panes.count).contains(args.destinationIndex) else {
            throw MCPError.invalidParams("Pane destination index is out of range")
        }
        guard let index = tab.panes.firstIndex(where: { $0.id == pane.id }) else {
            throw MCPError.invalidParams("Pane was not found")
        }
        tab.movePane(from: IndexSet(integer: index), to: args.destinationIndex)
        SessionPersistence.save(appState: appState)
        let result = mutationResult(
            operation: "panes_reorder", status: "succeeded", tabID: tab.id, paneID: pane.id,
            paneOrder: tab.panes.map(\.id))
        record(name: "panes_reorder", source: source, result: "succeeded", tabID: tab.id, paneID: pane.id)
        return result
    }

    private func deletePane(
        _ args: AgentControlPaneCleanupArguments, source: AgentControlSource
    ) async throws -> AgentControlMutationResult {
        let pane = try visiblePane(id: args.paneID, source: source, operation: "panes_delete")
        guard let tab = pane.tab else { throw MCPError.internalError("Pane has no parent tab") }
        let cleanup = try cleanupDecision(args.cleanup, panes: [pane])
        let paneID = pane.id
        let processIDs = WorktreeCloseFlow.processIDs(in: [pane])
        try Task.checkCancellation()
        tab.closePane(pane)
        SessionPersistence.save(appState: appState)
        let cleanupResults = await cleanupWorktrees(cleanup, panes: [pane], tab: tab, processIDs: processIDs)
        let status = cleanupResults.contains(where: { $0.status == "failed" }) ? "partial_failure" : "succeeded"
        let result = mutationResult(
            operation: "panes_delete", status: status, tabID: tab.id, paneID: paneID,
            cleanup: cleanupResults)
        record(name: "panes_delete", source: source, result: status, tabID: tab.id, paneID: paneID)
        return result
    }

    private func deleteTab(
        _ args: AgentControlTabCleanupArguments, source: AgentControlSource
    ) async throws -> AgentControlMutationResult {
        let tab = try visibleTab(id: args.tabID, source: source, operation: "tabs_delete")
        let panes = tab.panes
        let cleanup = try cleanupDecision(args.cleanup, panes: panes)
        let tabID = tab.id
        let processIDs = WorktreeCloseFlow.processIDs(in: panes)
        appState.closeTab(tab)
        let cleanupResults = await cleanupWorktrees(cleanup, panes: panes, tab: tab, processIDs: processIDs)
        let status = cleanupResults.contains(where: { $0.status == "failed" }) ? "partial_failure" : "succeeded"
        let result = mutationResult(
            operation: "tabs_delete", status: status, tabID: tabID,
            activeTabID: appState.activeTabID, activePaneID: appState.activePaneID,
            cleanup: cleanupResults)
        record(name: "tabs_delete", source: source, result: status, tabID: tabID)
        return result
    }

    private func cleanupDecision(_ requested: String?, panes: [Pane]) throws -> String {
        guard panes.contains(where: { $0.worktreeIsManaged }) else { return "keep" }
        switch appSettings.worktreeCleanupBehavior {
        case .ask:
            guard let requested else {
                throw MCPError.invalidRequest("cleanup is required for managed worktrees")
            }
            guard requested == "keep" || requested == "delete" else {
                throw MCPError.invalidParams("cleanup must be keep or delete")
            }
            return requested
        case .keep: return "keep"
        case .delete: return "delete"
        }
    }

    private func cleanupWorktrees(
        _ decision: String, panes: [Pane], tab: Tab, processIDs: [Int32]
    ) async -> [AgentControlCleanupResult] {
        let managed = panes.filter { $0.worktreeIsManaged && $0.worktreeDirectory != nil }
        guard decision == "delete" else {
            return managed.map { AgentControlCleanupResult(paneID: $0.id, status: "kept", error: nil) }
        }
        await WorktreeCloseFlow.waitForExit(of: processIDs)
        var results: [AgentControlCleanupResult] = []
        var handled: [String: AgentControlCleanupResult] = [:]
        for pane in managed {
            guard let checkout = pane.worktreeDirectory else { continue }
            let key = checkout.resolvingSymlinksInPath().path
            if let earlier = handled[key] {
                results.append(AgentControlCleanupResult(paneID: pane.id, status: earlier.status, error: earlier.error))
                continue
            }
            let result = await cleanupWorktree(of: pane, checkout: checkout, tab: tab)
            handled[key] = result
            results.append(result)
        }
        return results
    }

    private func cleanupWorktree(of pane: Pane, checkout: URL, tab: Tab) async -> AgentControlCleanupResult {
        if appState.isCheckoutInUse(directory: tab.directory, checkout: checkout) {
            return AgentControlCleanupResult(paneID: pane.id, status: "kept", error: WorktreeCloseFlow.inUseReason)
        }
        if FileManager.default.fileExists(atPath: checkout.path) {
            do {
                let assessment = try await WorktreeCleanup.assess(repository: tab.directory, checkout: checkout)
                if assessment.hasUnsavedWork {
                    return AgentControlCleanupResult(
                        paneID: pane.id, status: "kept",
                        error: "It has unsaved work: \(assessment.unsavedWorkLines.joined(separator: ", ")).")
                }
            } catch {
                return AgentControlCleanupResult(
                    paneID: pane.id, status: "failed",
                    error: String("It could not be checked for unsaved work: \(error.localizedDescription)".prefix(200))
                )
            }
        }
        let result = await tab.removeWorktree(of: pane, deleteBranch: appSettings.deleteBranchWithWorktree)
        switch result?.outcome {
        case .kept(let reason):
            return AgentControlCleanupResult(paneID: pane.id, status: "kept", error: reason)
        case .failed(let reason):
            return AgentControlCleanupResult(paneID: pane.id, status: "failed", error: String(reason.prefix(200)))
        default:
            return AgentControlCleanupResult(paneID: pane.id, status: "deleted", error: nil)
        }
    }

    private func resolveProfile(_ rawID: String?, harness: Harness) throws -> Profile? {
        guard let rawID else { return nil }
        guard let id = UUID(uuidString: rawID), let profile = appSettings.profiles.first(where: { $0.id == id }) else {
            throw MCPError.invalidParams("Profile was not found")
        }
        guard profile.harness == harness else { throw MCPError.invalidParams("Profile harness does not match") }
        return profile
    }

    private func createProfile(
        _ args: AgentControlProfileCreateArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPError.invalidParams("Profile name must not be empty") }

        var profile = Profile(name: name, harness: args.harness)
        profile.cliOptions = defaultProfileCLIOptions(for: args.harness)
        profile.envVars = defaultProfileEnvironment(for: args.harness)
        try applyOptionPatches(args.cliOptions, to: &profile.cliOptions, harness: args.harness)
        try applyEnvironmentPatches(args.environment, to: &profile.envVars, harness: args.harness)

        appSettings.profiles.append(profile)
        guard SettingsPersistence.saveProfiles(appSettings: appSettings) else {
            appSettings.profiles.removeAll { $0.id == profile.id }
            throw MCPError.internalError("Profile could not be persisted")
        }

        record(name: "profiles_create", source: source, result: "succeeded", profileID: profile.id)
        return profileMutationResult(
            operation: "profiles_create", status: "succeeded", profile: profile)
    }

    private func updateProfile(
        _ args: AgentControlProfileUpdateArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        guard let profileID = UUID(uuidString: args.profileID),
            let index = appSettings.profiles.firstIndex(where: { $0.id == profileID })
        else { throw MCPError.invalidParams("Profile was not found") }

        let previous = appSettings.profiles[index]
        var updated = previous
        if let name = args.name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MCPError.invalidParams("Profile name must not be empty") }
            updated.name = trimmed
        }

        let harnessChanged = args.harness.map { $0 != previous.harness } ?? false
        if let harness = args.harness {
            updated.harness = harness
            if harnessChanged {
                updated.cliOptions = defaultProfileCLIOptions(for: harness)
                updated.envVars = defaultProfileEnvironment(for: harness)
            }
        }
        try applyOptionPatches(args.cliOptions, to: &updated.cliOptions, harness: updated.harness)
        try applyEnvironmentPatches(args.environment, to: &updated.envVars, harness: updated.harness)

        appSettings.profiles[index] = updated
        guard SettingsPersistence.saveProfiles(appSettings: appSettings) else {
            appSettings.profiles[index] = previous
            throw MCPError.internalError("Profile could not be persisted")
        }

        record(name: "profiles_update", source: source, result: "succeeded", profileID: profileID)
        return profileMutationResult(
            operation: "profiles_update", status: "succeeded", profile: updated)
    }

    private func deleteProfile(
        _ args: AgentControlProfileIDArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        guard let profileID = UUID(uuidString: args.profileID),
            let index = appSettings.profiles.firstIndex(where: { $0.id == profileID })
        else { throw MCPError.invalidParams("Profile was not found") }

        let removed = appSettings.profiles.remove(at: index)
        guard SettingsPersistence.saveProfiles(appSettings: appSettings) else {
            appSettings.profiles.insert(removed, at: index)
            throw MCPError.internalError("Profile could not be persisted")
        }

        record(name: "profiles_delete", source: source, result: "succeeded", profileID: profileID)
        return mutationResult(
            operation: "profiles_delete", status: "succeeded", profileID: profileID,
            profileOrder: appSettings.profiles.map(\.id))
    }

    private func reorderProfile(
        _ args: AgentControlProfileReorderArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        guard let profileID = UUID(uuidString: args.profileID),
            let sourceIndex = appSettings.profiles.firstIndex(where: { $0.id == profileID })
        else { throw MCPError.invalidParams("Profile was not found") }
        guard (0..<appSettings.profiles.count).contains(args.destinationIndex) else {
            throw MCPError.invalidParams("Profile destination index is out of range")
        }

        let previous = appSettings.profiles
        let profile = appSettings.profiles.remove(at: sourceIndex)
        appSettings.profiles.insert(profile, at: args.destinationIndex)
        guard SettingsPersistence.saveProfiles(appSettings: appSettings) else {
            appSettings.profiles = previous
            throw MCPError.internalError("Profile order could not be persisted")
        }

        record(name: "profiles_reorder", source: source, result: "succeeded", profileID: profileID)
        return mutationResult(
            operation: "profiles_reorder", status: "succeeded", profileID: profileID,
            profileOrder: appSettings.profiles.map(\.id))
    }

    private func setHarnessEnabled(
        _ args: AgentControlHarnessEnabledArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        let previous = appSettings.activeTools
        appSettings.setActive(args.harness, args.enabled)
        guard SettingsPersistence.saveActiveTools(appSettings: appSettings) else {
            appSettings.activeTools = previous
            throw MCPError.internalError("Harness availability could not be persisted")
        }

        record(name: "harnesses_set_enabled", source: source, result: "succeeded", harness: args.harness)
        return mutationResult(
            operation: "harnesses_set_enabled", status: "succeeded",
            harness: AgentControlResourceRouter(appState: appState, appSettings: appSettings)
                .harnessSnapshots().first { $0.harness == args.harness },
            activeHarnesses: appSettings.activeHarnesses)
    }

    private func configureCLIOption(
        _ args: AgentControlCLIOptionConfigArguments, source: AgentControlSource
    ) throws -> AgentControlMutationResult {
        guard args.harness != .shell else { throw MCPError.invalidParams("Shell has no CLI option catalog") }
        let previous = optionCatalog(for: args.harness)
        var updated = previous
        guard let index = updated.firstIndex(where: { $0.id == args.optionID }) else {
            throw MCPError.invalidParams("CLI option was not found")
        }

        if let isAvailable = args.isAvailable { updated[index].isAvailable = isAvailable }
        if let isDefaultEnabled = args.isDefaultEnabled { updated[index].isDefaultEnabled = isDefaultEnabled }
        if let presetValues = args.presetValues {
            updated[index].presetValues = CLIOptionConfig.normalizedPresetValues(presetValues)
        }
        if let allowsMultipleValues = args.allowsMultipleValues {
            updated[index].allowsMultipleValues = allowsMultipleValues
        }

        let persisted: Bool
        switch args.harness {
        case .claude:
            appSettings.cliOptions = updated
            persisted = SettingsPersistence.save(appSettings: appSettings)
        case .codex:
            appSettings.codexCliOptions = updated
            persisted = SettingsPersistence.saveCodexOptions(appSettings: appSettings)
        case .cursor:
            appSettings.cursorCliOptions = updated
            persisted = SettingsPersistence.saveCursorOptions(appSettings: appSettings)
        case .opencode:
            appSettings.opencodeCliOptions = updated
            persisted = SettingsPersistence.saveOpenCodeOptions(appSettings: appSettings)
        case .shell:
            persisted = false
        }
        guard persisted else {
            setOptionCatalog(previous, for: args.harness)
            throw MCPError.internalError("CLI option configuration could not be persisted")
        }

        record(
            name: "harnesses_configure_cli_option", source: source, result: "succeeded",
            harness: args.harness, optionID: args.optionID)
        return mutationResult(
            operation: "harnesses_configure_cli_option", status: "succeeded",
            harness: AgentControlResourceRouter(appState: appState, appSettings: appSettings)
                .harnessSnapshots().first { $0.harness == args.harness })
    }

    private func defaultProfileCLIOptions(for harness: Harness) -> [ProfileCLIOption] {
        optionCatalog(for: harness).filter { $0.isAvailable }.map {
            ProfileCLIOption(id: $0.id, isEnabled: $0.isDefaultEnabled)
        }
    }

    private func defaultProfileEnvironment(for harness: Harness) -> [ProfileEnvVar] {
        environmentCatalog(for: harness).filter { !$0.isAppControlled && $0.isAvailable }.map {
            ProfileEnvVar(id: $0.id, isEnabled: $0.isDefaultEnabled, value: $0.defaultValue)
        }
    }

    private func applyOptionPatches(
        _ patches: [AgentControlProfileOptionPatch]?, to options: inout [ProfileCLIOption], harness: Harness
    ) throws {
        guard let patches else { return }
        var seen = Set<String>()
        let catalog = optionCatalog(for: harness)
        for patch in patches {
            guard seen.insert(patch.id).inserted else {
                throw MCPError.invalidParams("CLI option was specified more than once: \(patch.id)")
            }
            guard let config = catalog.first(where: { $0.id == patch.id }) else {
                throw MCPError.invalidParams("Unknown CLI option: \(patch.id)")
            }
            let value = patch.value?.trimmingCharacters(in: .whitespaces)
            let values = patch.values?.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            switch config.optionType {
            case .boolean:
                guard value == nil || value?.isEmpty == true, values?.isEmpty != false else {
                    throw MCPError.invalidParams("Boolean CLI option cannot have a value: \(patch.id)")
                }
            case .string:
                guard config.allowsMultipleValues || values?.count ?? 0 <= 1 else {
                    throw MCPError.invalidParams("CLI option does not accept multiple values: \(patch.id)")
                }
            }
            let normalizedValue: String?
            let normalizedValues: [String]?
            if config.allowsMultipleValues {
                normalizedValue = value?.isEmpty == true ? nil : value
                normalizedValues = values?.isEmpty == true ? nil : values
            } else {
                normalizedValue = value?.isEmpty == true ? values?.first : value
                normalizedValues = nil
            }
            let existingIndex = options.firstIndex(where: { $0.id == patch.id })
            let current = existingIndex.map { options[$0] }
            let next = ProfileCLIOption(
                id: patch.id,
                isEnabled: patch.enabled,
                value: normalizedValue ?? current?.value,
                values: normalizedValues ?? current?.values,
                showOnPaneCreate: patch.showOnPaneCreate ?? current?.showOnPaneCreate ?? false)
            if let existingIndex { options[existingIndex] = next } else { options.append(next) }
        }
    }

    private func applyEnvironmentPatches(
        _ patches: [AgentControlProfileEnvironmentPatch]?, to environment: inout [ProfileEnvVar], harness: Harness
    ) throws {
        guard let patches else { return }
        var seen = Set<String>()
        let catalog = environmentCatalog(for: harness)
        for patch in patches {
            guard seen.insert(patch.id).inserted else {
                throw MCPError.invalidParams("Environment variable was specified more than once: \(patch.id)")
            }
            guard let config = catalog.first(where: { $0.id == patch.id }) else {
                throw MCPError.invalidParams("Unknown environment variable: \(patch.id)")
            }
            guard !config.isAppControlled else {
                throw MCPError.invalidRequest("App-controlled environment variables cannot be changed")
            }
            let existingIndex = environment.firstIndex(where: { $0.id == patch.id })
            let current = existingIndex.map { environment[$0] }
            let next = ProfileEnvVar(
                id: patch.id,
                isEnabled: patch.enabled,
                value: patch.value ?? current?.value ?? "",
                showOnPaneCreate: patch.showOnPaneCreate ?? current?.showOnPaneCreate ?? false)
            if let existingIndex { environment[existingIndex] = next } else { environment.append(next) }
        }
    }

    private func setOptionCatalog(_ options: [CLIOptionConfig], for harness: Harness) {
        switch harness {
        case .claude: appSettings.cliOptions = options
        case .codex: appSettings.codexCliOptions = options
        case .cursor: appSettings.cursorCliOptions = options
        case .opencode: appSettings.opencodeCliOptions = options
        case .shell: break
        }
    }

    func profileMutationResult(
        operation: String, status: String, profile: Profile
    ) -> AgentControlMutationResult {
        let resources = AgentControlResourceRouter(appState: appState, appSettings: appSettings)
        return mutationResult(
            operation: operation, status: status, profileID: profile.id,
            profileOrder: appSettings.profiles.map(\.id), profile: resources.profileSnapshot(profile))
    }

    private func resolveOptions(
        _ inputs: [AgentControlCLIOptionInput]?, profile: Profile?, harness: Harness
    ) throws -> [String] {
        let catalog = optionCatalog(for: harness)
        var states: [String: ProfileCLIOption] = [:]
        if let profile {
            for option in profile.cliOptions { states[option.id] = option }
        } else {
            for option in catalog where option.isAvailable && option.isDefaultEnabled {
                states[option.id] = ProfileCLIOption(id: option.id, isEnabled: true)
            }
        }
        for input in inputs ?? [] {
            guard let option = catalog.first(where: { $0.id == input.id }) else {
                throw MCPError.invalidParams("Unknown CLI option: \(input.id)")
            }
            guard option.isAvailable else {
                throw MCPError.invalidParams(
                    "CLI option \(input.id) is unavailable for \(harness.displayName)")
            }
            states[input.id] = ProfileCLIOption(
                id: option.id, isEnabled: input.enabled, value: input.value, values: input.values)
        }
        var arguments: [String] = []
        for option in catalog {
            guard let state = states[option.id], state.isEnabled else { continue }
            arguments.append(contentsOf: option.commandLineArguments(value: state.value, values: state.values ?? []))
        }
        return arguments
    }

    private func resolveEnvironment(
        _ inputs: [AgentControlEnvironmentInput]?, profile: Profile?, harness: Harness
    ) throws -> [String: String] {
        let catalog = environmentCatalog(for: harness)
        var values: [String: String] = [:]
        if let profile {
            for value in profile.envVars where value.isEnabled && !value.value.isEmpty {
                values[value.id] = value.value
            }
        }
        for input in inputs ?? [] {
            guard let config = catalog.first(where: { $0.id == input.id }) else {
                throw MCPError.invalidParams("Unknown environment variable: \(input.id)")
            }
            guard !config.isAppControlled else {
                throw MCPError.invalidRequest("App-controlled environment variables cannot be overridden")
            }
            if input.enabled {
                values[input.id] = input.value
            } else {
                values.removeValue(forKey: input.id)
            }
        }
        return values
    }

    private func optionCatalog(for harness: Harness) -> [CLIOptionConfig] {
        switch harness {
        case .claude: return appSettings.cliOptions
        case .codex: return appSettings.codexCliOptions
        case .cursor: return appSettings.cursorCliOptions
        case .opencode: return appSettings.opencodeCliOptions
        case .shell: return []
        }
    }

    private func environmentCatalog(for harness: Harness) -> [EnvVarConfig] {
        switch harness {
        case .claude: return appSettings.envVarOptions
        case .opencode: return appSettings.opencodeEnvVarOptions
        case .codex, .cursor, .shell: return []
        }
    }

    private func resolveDefaultBranch(_ requested: String?, tab: Tab) -> String? {
        if let requested, !requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return requested }
        if let override = tab.baseBranchOverride, !override.isEmpty { return override }
        return appSettings.isDefaultBranchEnabled ? appSettings.defaultBranch : nil
    }

    private func visibleTab(id rawID: String, source: AgentControlSource, operation: String) throws -> Tab {
        guard let id = UUID(uuidString: rawID), let tab = appState.tabs.first(where: { $0.id == id }) else {
            throw MCPError.invalidParams("Tab was not found")
        }
        switch source.scope {
        case .global: return tab
        case .tab, .pane:
            guard tab.id == source.tabID else {
                throw MCPError.invalidRequest("\(operation) target is outside scope")
            }
            return tab
        }
    }

    private func visiblePane(id rawID: String, source: AgentControlSource, operation: String) throws -> Pane {
        guard let id = UUID(uuidString: rawID), let pane = appState.tabs.flatMap(\.panes).first(where: { $0.id == id })
        else {
            throw MCPError.invalidParams("Pane was not found")
        }
        switch source.scope {
        case .global: return pane
        case .tab:
            guard pane.tab?.id == source.tabID else {
                throw MCPError.invalidRequest("\(operation) target is outside scope")
            }
        case .pane:
            guard pane.id == source.paneID else {
                throw MCPError.invalidRequest("\(operation) target is outside scope")
            }
        }
        return pane
    }

    private func requireGlobal(_ source: AgentControlSource, name: String) throws {
        guard source.scope == .global else {
            record(name: name, source: source, result: "scope_denied")
            throw MCPError.invalidRequest(
                "Global scope is required for \(name); current scope is \(source.scope.displayName)")
        }
    }

    private func snapshotTab(_ tab: Tab, source: AgentControlSource) -> AgentControlTabSnapshot {
        AgentControlResourceRouter(appState: appState, appSettings: appSettings).tabSnapshot(tab, source: source)
    }

    private func snapshotPane(_ pane: Pane) -> AgentControlPaneSnapshot {
        AgentControlResourceRouter(appState: appState, appSettings: appSettings).paneSnapshot(pane)
    }

    func mutationResult(
        operation: String,
        status: String,
        tabID: UUID? = nil,
        paneID: UUID? = nil,
        activeTabID: UUID? = nil,
        activePaneID: UUID? = nil,
        focusedPaneID: UUID? = nil,
        tabOrder: [UUID]? = nil,
        paneOrder: [UUID]? = nil,
        cleanup: [AgentControlCleanupResult] = [],
        tab: AgentControlTabSnapshot? = nil,
        pane: AgentControlPaneSnapshot? = nil,
        profileID: UUID? = nil,
        profileOrder: [UUID]? = nil,
        profile: AgentControlProfileSnapshot? = nil,
        harness: AgentControlHarnessSnapshot? = nil,
        activeHarnesses: [Harness]? = nil,
        statusLineConfiguration: StatusLineConfig? = nil,
        acknowledgedNotificationID: UUID? = nil,
        error: String? = nil
    ) -> AgentControlMutationResult {
        AgentControlMutationResult(
            operation: operation, status: status, tabID: tabID, paneID: paneID,
            profileID: profileID,
            activeTabID: activeTabID, activePaneID: activePaneID, focusedPaneID: focusedPaneID,
            tabOrder: tabOrder, paneOrder: paneOrder, cleanup: cleanup, tab: tab, pane: pane,
            profile: profile, profileOrder: profileOrder, harness: harness, activeHarnesses: activeHarnesses,
            statusLineConfiguration: statusLineConfiguration,
            acknowledgedNotificationID: acknowledgedNotificationID,
            error: error)
    }

    private func decode<T: Decodable>(_ type: T.Type, arguments: [String: Value]?) throws -> T {
        let data = try JSONEncoder().encode(arguments ?? [:])
        return try JSONDecoder().decode(type, from: data)
    }

    private func result(_ value: AgentControlMutationResult) throws -> CallTool.Result {
        let data = try JSONEncoder().encode(value)
        return try CallTool.Result(
            content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
            structuredContent: value)
    }
}
