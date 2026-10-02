import Foundation

struct Invariant: Identifiable, Hashable, Sendable {
    enum Severity: String, Codable, Sendable {
        case warning
        case error
    }

    let id: String
    let integration: String
    let severity: Severity
    let description: String
    let traceEventName: String?

    static let statusLineWorktreeName = Invariant(
        id: "statusline.worktree.name",
        integration: "Status Line",
        severity: .warning,
        description: "The reported worktree name must match the pane working directory.",
        traceEventName: "statusline.worktree.name_mismatch"
    )

    static let statusLineLinesSource = Invariant(
        id: "statusline.lines.source",
        integration: "Status Line",
        severity: .warning,
        description: "Displayed line counts must come from the pane's git diff.",
        traceEventName: "statusline.lines.source_mismatch"
    )

    static let appBundleIdentityPreferredURL = Invariant(
        id: "app.bundle_identity.preferred_url",
        integration: "App Bundle",
        severity: .warning,
        description: "Launch Services must prefer the running app bundle URL for its bundle identifier.",
        traceEventName: "app.bundle_identity.preferred_url_mismatch"
    )

    static let opencodeConfigContentAppControlled = Invariant(
        id: "opencode.config_content.app_controlled",
        integration: "OpenCode",
        severity: .warning,
        description: """
            OPENCODE_CONFIG_CONTENT and OPENCODE_PERMISSION are app-injected per pane; \
            user-provided values are silently overridden.
            """,
        traceEventName: "opencode.config_content.user_override_silenced"
    )

    static let opencodePortMissing = Invariant(
        id: "opencode.port_missing",
        integration: "OpenCode",
        severity: .error,
        description: "An OpenCode pane was started without a configured opencode port.",
        traceEventName: "statusline.opencode.port_missing"
    )

    static let opencodePortPolicy = Invariant(
        id: "opencode.port.policy",
        integration: "OpenCode",
        severity: .error,
        description: "An OpenCode pane must bind to localhost, use an ephemeral port, and disable mDNS.",
        traceEventName: "opencode.port.policy_violated"
    )

    static let opencodeSessionRebindable = Invariant(
        id: "opencode.session.rebindable",
        integration: "OpenCode",
        severity: .warning,
        description: "An OpenCode pane must bind to a session id and rebind to the same id across restore.",
        traceEventName: "opencode.session.rebindable_violated"
    )

    static let opencodeTUIEndpointsUnused = Invariant(
        id: "opencode.tui.endpoints_unused",
        integration: "OpenCode",
        severity: .error,
        description: "The app must not call OpenCode /tui/* endpoints; the terminal is the user surface.",
        traceEventName: "opencode.tui.endpoint_forbidden"
    )

    static let cursorAgentControlBridgeAvailable = Invariant(
        id: "cursor.agent_control.bridge_available",
        integration: "Cursor",
        severity: .error,
        description: "A Cursor pane with Agent Control enabled must find an executable bundled bridge.",
        traceEventName: "cursor.agent_control.bridge_missing"
    )

    static let terminalClipboardCopyRequiresSelection = Invariant(
        id: "terminal.clipboard.copy_requires_selection",
        integration: "Terminal",
        severity: .warning,
        description:
            "A copy request must carry an active, non-empty selection; the pasteboard is never cleared without one.",
        traceEventName: "terminal.clipboard.copy_without_selection"
    )

    static let appLaunchAuxiliaryWindowsClosed = Invariant(
        id: "app.launch.auxiliary_windows_closed",
        integration: "App Launch",
        severity: .error,
        description: "An auxiliary dashboard window must not be open unless something explicitly requested it.",
        traceEventName: "app.launch.auxiliary_window_opened"
    )

    static let claudeStopBackgroundState = Invariant(
        id: "claude.stop.background_state",
        integration: "Claude",
        severity: .warning,
        description: "A Claude Stop event must report both background_tasks and session_crons.",
        traceEventName: "statusline.claude.stop_background_state_missing"
    )

    static let githubCLIAvailable = Invariant(
        id: "github.cli.available",
        integration: "GitHub CLI",
        severity: .warning,
        description: "PR tracking requires a discoverable GitHub CLI executable.",
        traceEventName: "github.cli.missing_executable"
    )
}

struct InvariantViolation: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let invariantID: String
    let integration: String
    let severity: Invariant.Severity
    let description: String
    let timestamp: Date
    let context: [String: String]

    init(invariant: Invariant, context: [String: String], id: UUID = UUID(), timestamp: Date = Date()) {
        self.id = id
        invariantID = invariant.id
        integration = invariant.integration
        severity = invariant.severity
        description = invariant.description
        self.timestamp = timestamp
        self.context = context
    }
}
