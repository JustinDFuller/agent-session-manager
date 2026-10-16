import Foundation
import Observation

enum ExitBehavior: String, Codable, CaseIterable {
    case prompt
    case autoShell
    case close

    var displayName: String {
        switch self {
        case .prompt: return "Show Prompt"
        case .autoShell: return "Open Shell"
        case .close: return "Close Pane"
        }
    }

    var description: String {
        switch self {
        case .prompt: return "Show a prompt offering Restart, Open Shell, and Close when a process exits."
        case .autoShell: return "Automatically replace the pane with a live shell when a process exits."
        case .close: return "Automatically close the pane when a process exits."
        }
    }
}

enum WorktreeCleanupBehavior: String, Codable, CaseIterable {
    case ask
    case keep
    case delete

    var displayName: String {
        switch self {
        case .ask: return "Ask"
        case .keep: return "Always Keep"
        case .delete: return "Always Delete"
        }
    }

    var description: String {
        switch self {
        case .ask: return "Ask whether to clean up the worktree each time you close a pane."
        case .keep: return "Never delete worktrees when closing a pane."
        case .delete: return "Automatically delete worktrees when closing a pane without asking."
        }
    }
}

enum WorktreeBaseRef: String, Codable, CaseIterable {
    case fresh
    case head

    var displayName: String {
        switch self {
        case .fresh: return "Fresh"
        case .head: return "HEAD"
        }
    }

    var description: String {
        switch self {
        case .fresh: return "Branch from origin/<default-branch> for a clean tree matching the remote."
        case .head: return "Branch from local HEAD, including unpushed commits and current branch state."
        }
    }
}

enum ExistingWorktreeManagement: String, Codable, CaseIterable {
    case ask
    case always
    case never

    var displayName: String {
        switch self {
        case .ask: return "Ask"
        case .always: return "Always"
        case .never: return "Never"
        }
    }

    var description: String {
        switch self {
        case .ask: return "Ask whether to take over management each time an existing worktree is reused."
        case .always: return "Automatically take over management of existing worktrees so they can be cleaned up later."
        case .never: return "Never manage existing worktrees — use them as-is without offering cleanup."
        }
    }
}

enum FocusModeTabSwitchBehavior: String, Codable, CaseIterable {
    case rememberFocus
    case showAllPanes

    var displayName: String {
        switch self {
        case .rememberFocus: return "Remember Focus"
        case .showAllPanes: return "Show All Panes"
        }
    }

    var description: String {
        switch self {
        case .rememberFocus: return "Return to the focused pane when switching back to a tab."
        case .showAllPanes: return "Restore the pane grid whenever you leave a tab."
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    var layoutSettings = LayoutSettings()
    var layoutSaveError: String?
    var cliOptions: [CLIOptionConfig] = CLIOptionConfig.all
    var codexCliOptions: [CLIOptionConfig] = CLIOptionConfig.codexAll
    var cursorCliOptions: [CLIOptionConfig] = CLIOptionConfig.cursorAll
    var opencodeCliOptions: [CLIOptionConfig] = CLIOptionConfig.opencodeAll
    var envVarOptions: [EnvVarConfig] = EnvVarConfig.all
    var opencodeEnvVarOptions: [EnvVarConfig] = EnvVarConfig.opencodeAll
    var statusLineConfig = StatusLineConfig()
    var activeTools: Set<String> = [Harness.claude.rawValue]
    var defaultBranch: String = "main"
    var isDefaultBranchEnabled: Bool = true
    var notificationSidebarSide: SidebarSide = .left
    var alwaysShowNotificationsSidebar: Bool = true
    var isPriorityNotificationsEnabled: Bool = true
    var isMacOSBannerNotificationsEnabled: Bool = true
    var isCursorNotificationHookAttentionEnabled: Bool = true
    var isClaudeStopNotificationEnabled: Bool = true
    var isOpencodeStopNotificationEnabled: Bool = true
    var isCodexCompletionNotificationEnabled: Bool = true
    var continueOnRestart: Bool = true
    var worktreeCleanupBehavior: WorktreeCleanupBehavior = .ask
    var deleteBranchWithWorktree: Bool = true
    var cleanUpLeftoversAtLaunch: Bool = true
    var existingWorktreeManagement: ExistingWorktreeManagement = .ask
    var worktreeBaseRef: WorktreeBaseRef = .fresh
    var debugModeEnabled: Bool = false
    var githubPRTrackingEnabled: Bool = true
    var isPRMergedNotificationsEnabled: Bool = true
    var isPRClosedNotificationsEnabled: Bool = true
    var prPollingIntervalSeconds: Int = 30
    var prRequestTimeoutSeconds: Int = 15
    var prBackgroundRefreshEnabled: Bool = true
    var prBackgroundPollingIntervalSeconds: Int = 60
    var defaultScrollback: ScrollbackLimit = .defaultValue
    var exitBehavior: ExitBehavior = .prompt
    var profiles: [Profile] = []
    var autoSetSessionName: Bool = true
    var preferredShell: String = ""
    var hasCompletedOnboarding: Bool = false
    var paneActivityIndicatorsEnabled: Bool = true
    var focusModeTabSwitchBehavior: FocusModeTabSwitchBehavior = .rememberFocus
    var hideNotificationSidebarWhileFocused: Bool = true
    var updateReminderEnabled: Bool = true
    var agentControlInjectionPolicy: AgentControlInjectionPolicy = .askOn
    var agentControlScope: AgentControlScope = .global

    nonisolated static let debugFileMaxBytes = 10 * 1024 * 1024

    var resolvedTracingDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return
            appSupport
            .appending(path: PersistenceHelpers.appSupportSubdirectory)
            .appending(path: "traces")
            .standardizedFileURL
    }

    var resolvedInvariantDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return
            appSupport
            .appending(path: PersistenceHelpers.appSupportSubdirectory)
            .appending(path: "invariants")
            .standardizedFileURL
    }

    func isActive(_ tool: Harness) -> Bool {
        activeTools.contains(tool.rawValue)
    }

    func setActive(_ tool: Harness, _ active: Bool) {
        if active { activeTools.insert(tool.rawValue) } else { activeTools.remove(tool.rawValue) }
    }

    var activeHarnesses: [Harness] {
        Harness.allCases.filter { isActive($0) }
    }

    func resolvedAgentControlInjectionDecision(persistedDecision: Bool?) -> Bool {
        agentControlInjectionPolicy.resolve(persistedDecision: persistedDecision)
    }
}
