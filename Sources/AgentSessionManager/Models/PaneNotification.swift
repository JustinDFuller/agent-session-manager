import Foundation

enum NotificationKind: String, Codable {
    case terminalBell
    case prMerged
    case prClosed
    case claudeStop
    case cursorStop
    case opencodeStop
    case opencodePermissionRequest
}

struct PaneAttentionEvent: Equatable {
    enum Source: String {
        case rawBell = "bell"
        case osc777
        case claudeNotification = "claude_notification"
        case claudePermissionRequest = "claude_permission_request"
        case claudeQuestion = "claude_question"
        case claudePlanApproval = "claude_plan_approval"
        case claudeStop = "claude_stop"
        case cursorStop = "cursor_stop"
        case opencodeStop = "opencode_stop"
        case opencodePermissionRequest = "opencode_permission_request"
    }

    static let fallbackReason = "Attention needed"

    let source: Source
    let reason: String

    init(source: Source, reason: String?) {
        self.source = source
        self.reason = Self.normalize(reason) ?? Self.fallbackReason
    }

    static var rawBell: PaneAttentionEvent {
        PaneAttentionEvent(source: .rawBell, reason: nil)
    }

    static var claudeStop: PaneAttentionEvent {
        PaneAttentionEvent(source: .claudeStop, reason: "Claude finished responding")
    }

    static var cursorStop: PaneAttentionEvent {
        PaneAttentionEvent(source: .cursorStop, reason: "Agent turn completed")
    }

    static var opencodeStop: PaneAttentionEvent {
        PaneAttentionEvent(source: .opencodeStop, reason: "OpenCode finished responding")
    }

    static func osc777(_ text: String) -> PaneAttentionEvent? {
        let parts = text.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0] == "notify" else { return nil }
        let title = String(parts[1])
        let body = parts.count == 3 ? String(parts[2]) : nil
        return PaneAttentionEvent(source: .osc777, reason: Self.normalize(body) ?? Self.normalize(title))
    }

    static func claudeHook(_ data: Data) -> PaneAttentionEvent? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch payload["hook_event_name"] as? String {
        case "Notification":
            return PaneAttentionEvent(
                source: .claudeNotification,
                reason: string(payload["message"]) ?? string(payload["title"])
            )
        case "PreToolUse":
            switch payload["tool_name"] as? String {
            case "AskUserQuestion":
                return PaneAttentionEvent(source: .claudeQuestion, reason: "Claude has a question")
            case "ExitPlanMode":
                return PaneAttentionEvent(source: .claudePlanApproval, reason: "Claude needs plan approval")
            default:
                return nil
            }
        case "PermissionRequest":
            let toolName = string(payload["tool_name"])
            return PaneAttentionEvent(
                source: .claudePermissionRequest,
                reason: toolName.map { "Permission needed for \($0)" } ?? "Permission needed"
            )
        default:
            return nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        normalize(value as? String)
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized =
            value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}

struct PaneNotification: Identifiable {
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

    init(
        paneID: UUID,
        paneName: String,
        tabID: UUID,
        tabName: String,
        isPriority: Bool,
        kind: NotificationKind = .terminalBell,
        reason: String? = nil,
        prNumber: Int? = nil,
        prTitle: String? = nil
    ) {
        self.init(
            id: UUID(),
            paneID: paneID,
            paneName: paneName,
            tabID: tabID,
            tabName: tabName,
            isPriority: isPriority,
            timestamp: Date(),
            kind: kind,
            reason: reason,
            prNumber: prNumber,
            prTitle: prTitle
        )
    }

    init(
        id: UUID,
        paneID: UUID,
        paneName: String,
        tabID: UUID,
        tabName: String,
        isPriority: Bool,
        timestamp: Date,
        kind: NotificationKind = .terminalBell,
        reason: String? = nil,
        prNumber: Int? = nil,
        prTitle: String? = nil
    ) {
        self.id = id
        self.paneID = paneID
        self.paneName = paneName
        self.tabID = tabID
        self.tabName = tabName
        self.isPriority = isPriority
        self.timestamp = timestamp
        self.kind = kind
        self.reason = reason
        self.prNumber = prNumber
        self.prTitle = prTitle
    }

    var displayReason: String {
        if kind == .prMerged, let prNumber {
            return "PR #\(prNumber) merged"
        }
        if kind == .prClosed, let prNumber {
            return "PR #\(prNumber) closed"
        }
        return reason ?? PaneAttentionEvent.fallbackReason
    }
}
