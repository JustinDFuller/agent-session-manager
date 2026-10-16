import Foundation
import Observation

enum PaneSetupState {
    case loading
    case failed(error: String)
}

enum CodexContinuationRecovery: Equatable {
    case identityNotRecorded
    case exactSessionUnavailable
}

extension CodexSessionAccess {
    var traceValue: String {
        switch self {
        case .available: "available"
        case .missing: "missing"
        case .inaccessible: "inaccessible"
        }
    }
}

enum Harness: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case cursor
    case opencode
    case shell

    static var allCases: [Harness] { [.claude, .codex, .cursor, .opencode] }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .opencode: return "OpenCode"
        case .shell: return "Shell"
        }
    }

    var commandDescription: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .cursor: return "agent"
        case .opencode: return "opencode"
        case .shell: return "$SHELL"
        }
    }
}

@Observable
@MainActor
final class Pane: Identifiable {
    let id: UUID
    var name: String
    var statusLineHeight: Double?
    var harness: Harness
    var worktreeDirectory: URL?
    var worktreeIsManaged: Bool = false
    weak var tab: Tab?
    private(set) var terminalController: TerminalController?
    private(set) var statusLineMonitor: StatusLineMonitor?
    @ObservationIgnored weak var notificationAppState: AppState?
    var isPriority: Bool = false
    var isMerged: Bool = false
    var isClosed: Bool = false
    var restartToken = UUID()
    var profileID: UUID?
    var scrollbackOverride: ScrollbackLimit?
    var extraArgs: [String] = []
    var extraEnvVars: [String: String] = [:]
    var setupState: PaneSetupState?
    var agentControlInjectionEnabled: Bool
    var isRestarting = false
    weak var appSettings: AppSettings?
    var uiTestActivityStateOverride: PaneActivityState?
    var opencodeRaceLossRestarted = false
    var opencodePort: Int?
    var cursorAgentControlPluginDirectory: URL?
    var opencodeSessionID: String?
    var codexSessionID: String?
    var codexTranscriptPath: String?
    var codexLaunchResumeSessionID: String?
    var codexContinuationRecovery: CodexContinuationRecovery?
    var codexContinuationNotice: String?

    init(
        id: UUID = UUID(),
        name: String,
        tab: Tab,
        harness: Harness = .claude,
        worktreeDirectory: URL? = nil,
        worktreeIsManaged: Bool = false,
        profileID: UUID? = nil,
        scrollbackOverride: ScrollbackLimit? = nil,
        agentControlInjectionEnabled: Bool = true,
        appSettings: AppSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.harness = harness
        self.worktreeDirectory = worktreeDirectory
        self.worktreeIsManaged = worktreeIsManaged
        self.tab = tab
        self.profileID = profileID
        self.scrollbackOverride = scrollbackOverride
        self.agentControlInjectionEnabled = agentControlInjectionEnabled
        self.appSettings = appSettings
    }

    var worktreePath: URL? {
        if let worktreeDirectory { return worktreeDirectory }
        guard let tab else { return nil }
        return Tab.worktreeDirectoryURL(repoRoot: tab.directory, name: name)
    }

    var effectiveScrollback: ScrollbackLimit {
        scrollbackOverride ?? appSettings?.defaultScrollback ?? .defaultValue
    }

    func installTerminalController(_ controller: TerminalController?) {
        guard terminalController !== controller else { return }
        terminalController?.terminalView.onUserInput = nil
        terminalController?.onAttention = nil
        terminalController = controller
        attachTerminalNotificationHandlers()
    }

    func installStatusLineMonitor(_ monitor: StatusLineMonitor) {
        guard statusLineMonitor !== monitor else { return }
        removeStatusLineMonitor()
        statusLineMonitor = monitor
        attachStatusLineNotificationHandlers()
        monitor.start()
    }

    func removeStatusLineMonitor() {
        statusLineMonitor?.stop()
        statusLineMonitor?.onClaudeHookAttention = nil
        statusLineMonitor?.onCodexSessionBound = nil
        statusLineMonitor?.onPRMerged = nil
        statusLineMonitor?.onPRClosed = nil
        statusLineMonitor?.onPRReopened = nil
        statusLineMonitor = nil
    }
}
