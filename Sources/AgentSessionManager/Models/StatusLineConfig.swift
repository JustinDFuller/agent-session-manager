import AppKit
import Foundation

enum StatusFactOwner: String, Codable {
    case app
    case harness
    case merged
}

enum MissingStatusFactBehavior: String, Codable {
    case pending
    case unsupported
}

struct StatusFactCapability: Codable, Equatable {
    let owner: StatusFactOwner
    let supportedHarnesses: Set<Harness>
    let missingBehavior: MissingStatusFactBehavior

    func supports(_ harness: Harness) -> Bool {
        supportedHarnesses.contains(harness)
    }
}

enum FactLabelStyle: String, Codable, CaseIterable {
    case symbolOnly
    case symbolAndLabel
    case labelOnly

    var displayName: String {
        switch self {
        case .symbolOnly: return "Symbol only"
        case .symbolAndLabel: return "Symbol + label"
        case .labelOnly: return "Label only"
        }
    }
}

enum RowAlignment: String, Codable, CaseIterable {
    case leading
    case spaceBetween

    var displayName: String {
        switch self {
        case .leading: return "Left-aligned"
        case .spaceBetween: return "Spread evenly"
        }
    }
}

struct StatusLineItem: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var sfSymbol: String

    init(id: String, label: String, sfSymbol: String) {
        self.id = id
        self.label = label
        self.sfSymbol = sfSymbol
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        sfSymbol =
            try container.decodeIfPresent(String.self, forKey: .sfSymbol)
            ?? StatusLineConfig.itemMetadata[id]?.symbol ?? "circle"
    }

    var capability: StatusFactCapability {
        StatusLineConfig.itemCapabilities[id] ?? StatusLineConfig.appCapability
    }

    func supportedBy(_ harness: Harness) -> Bool {
        capability.supports(harness)
    }

    enum CodingKeys: String, CodingKey {
        case id, label, sfSymbol
    }
}

struct StatusLineRow: Codable, Identifiable, Equatable {
    var id: UUID
    var items: [StatusLineItem]

    init(items: [StatusLineItem] = []) {
        self.id = UUID()
        self.items = items
    }
}

enum CustomFieldTint: String, Codable {
    case normal
    case good
    case warning
    case critical
}

enum StatusLineIconCategory: String, CaseIterable, Hashable, Sendable {
    case development = "Development"
    case repository = "Repository"
    case status = "Status"
    case time = "Time"
    case cost = "Cost"
    case data = "Data"
    case network = "Network"
    case people = "People"
    case alert = "Alert"
}

struct StatusLineIconOption: Identifiable, Hashable, Sendable {
    let symbol: String
    let displayName: String
    let category: StatusLineIconCategory
    let keywords: [String]

    var id: String { symbol }

    var searchTerms: [String] {
        [displayName, symbol] + keywords
    }
}

struct CustomFieldRenderValue: Codable, Equatable {
    var text: String?
    var percent: Double?
    var tint: CustomFieldTint?
    var icon: String?

    var isEmpty: Bool { text == nil && percent == nil && tint == nil && icon == nil }
}

struct CustomStatusLineField: Codable, Identifiable, Equatable {
    static let minimumRefreshIntervalSeconds = 5
    static let defaultRefreshIntervalSeconds = 15
    static let defaultTimeoutSeconds = 10

    var id: String
    var label: String
    var sfSymbol: String
    var command: String
    var refreshIntervalSeconds: Int
    var timeoutSeconds: Int
    var supportedHarnesses: Set<Harness>
    fileprivate(set) var needsPersistenceMigration = false

    init(
        id: String = "custom:\(UUID().uuidString)",
        label: String,
        sfSymbol: String = "terminal",
        command: String,
        refreshIntervalSeconds: Int = defaultRefreshIntervalSeconds,
        timeoutSeconds: Int = defaultTimeoutSeconds,
        supportedHarnesses: Set<Harness> = StatusLineConfig.allHarnesses
    ) {
        self.id = id
        self.label = label
        self.sfSymbol = sfSymbol
        self.command = command
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.timeoutSeconds = timeoutSeconds
        self.supportedHarnesses = supportedHarnesses
    }

    var effectiveRefreshIntervalSeconds: Int {
        max(Self.minimumRefreshIntervalSeconds, refreshIntervalSeconds)
    }

    func supports(_ harness: Harness) -> Bool {
        supportedHarnesses.contains(harness)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        sfSymbol = try container.decodeIfPresent(String.self, forKey: .sfSymbol) ?? "terminal"
        command = try container.decode(String.self, forKey: .command)
        refreshIntervalSeconds =
            try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds)
            ?? Self.defaultRefreshIntervalSeconds
        timeoutSeconds =
            try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds)
            ?? Self.defaultTimeoutSeconds
        supportedHarnesses =
            try container.decodeIfPresent(Set<Harness>.self, forKey: .supportedHarnesses)
            ?? StatusLineConfig.allHarnesses
        needsPersistenceMigration =
            !container.contains(.sfSymbol) || !container.contains(.supportedHarnesses)
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, sfSymbol, command, refreshIntervalSeconds, timeoutSeconds, supportedHarnesses
    }

    static func == (lhs: CustomStatusLineField, rhs: CustomStatusLineField) -> Bool {
        lhs.id == rhs.id
            && lhs.label == rhs.label
            && lhs.sfSymbol == rhs.sfSymbol
            && lhs.command == rhs.command
            && lhs.refreshIntervalSeconds == rhs.refreshIntervalSeconds
            && lhs.timeoutSeconds == rhs.timeoutSeconds
            && lhs.supportedHarnesses == rhs.supportedHarnesses
    }
}

private struct LegacyStatusLineItem: Decodable {
    var id: String
    var label: String
    var sfSymbol: String?
    var isVisible: Bool

    enum CodingKeys: String, CodingKey {
        case id, label, sfSymbol, isVisible
    }
}

struct StatusLineConfig: Codable, Equatable, Sendable {
    var rows: [StatusLineRow]
    var factLabelStyle: FactLabelStyle
    var rowAlignment: RowAlignment
    var showPercentagesAsText: Bool
    var customFields: [CustomStatusLineField]
    fileprivate(set) var needsPersistenceMigration = false

    static let itemMetadata: [String: (label: String, symbol: String)] = [
        "model": ("Model", "cpu"),
        "worktree": ("Worktree", "folder.badge.gearshape"),
        "cost": ("Cost", "dollarsign.circle"),
        "context": ("Context Used", "gauge.with.needle"),
        "effort": ("Effort", "dial.high"),
        "thinking": ("Thinking", "brain"),
        "vimMode": ("Vim Mode", "keyboard"),
        "agentName": ("Agent", "person.crop.circle"),
        "sessionName": ("Session Name", "tag"),
        "linesAdded": ("Lines Added", "plus.square"),
        "linesRemoved": ("Lines Removed", "minus.square"),
        "duration": ("Duration", "clock"),
        "contextRemaining": ("Context Remaining", "gauge.with.needle.fill"),
        "inputTokens": ("Input Tokens", "arrow.down.circle"),
        "outputTokens": ("Output Tokens", "arrow.up.circle"),
        "rate5h": ("5h Rate", "timer"),
        "rate7d": ("7d Rate", "calendar.badge.clock"),
        "rate5hReset": ("5h Resets At", "arrow.clockwise.circle"),
        "rate7dReset": ("7d Resets At", "arrow.clockwise.circle.fill"),
        "version": ("Version", "info.circle"),
        "outputStyle": ("Output Style", "text.alignleft"),
        "exceeds200k": ("Exceeds 200k", "exclamationmark.triangle"),
        "pr": ("PR", "arrow.triangle.pull"),
        "profileName": ("Profile", "person.crop.rectangle"),
        "repo": ("Repository", "chevron.left.forwardslash.chevron.right"),
        "contextSize": ("Context Size", "ruler"),
        "cacheRead": ("Cache Read", "arrow.down.doc"),
        "cacheCreation": ("Cache Write", "arrow.up.doc"),
        "apiDuration": ("API Duration", "clock.arrow.2.circlepath"),
    ]

    static let allHarnesses: Set<Harness> = [.claude, .codex, .cursor, .opencode]
    static let customFieldIconOptions: [StatusLineIconOption] = [
        StatusLineIconOption(
            symbol: "terminal", displayName: "Terminal", category: .development,
            keywords: ["shell", "command", "console"]),
        StatusLineIconOption(
            symbol: "cpu", displayName: "CPU", category: .development,
            keywords: ["processor", "compute", "performance"]),
        StatusLineIconOption(
            symbol: "brain", displayName: "Brain", category: .development,
            keywords: ["thinking", "reasoning", "agent"]),
        StatusLineIconOption(
            symbol: "keyboard", displayName: "Keyboard", category: .development,
            keywords: ["vim", "input", "editor"]),
        StatusLineIconOption(
            symbol: "curlybraces", displayName: "Code", category: .development,
            keywords: ["source", "programming", "json"]),
        StatusLineIconOption(
            symbol: "pencil.line", displayName: "Draft", category: .development,
            keywords: ["edit", "writing", "change"]),

        StatusLineIconOption(
            symbol: "folder", displayName: "Folder", category: .repository,
            keywords: ["directory", "project", "workspace"]),
        StatusLineIconOption(
            symbol: "folder.badge.gearshape", displayName: "Worktree", category: .repository,
            keywords: ["git", "directory", "workspace"]),
        StatusLineIconOption(
            symbol: "arrow.branch", displayName: "Branch", category: .repository,
            keywords: ["git", "version control", "fork"]),
        StatusLineIconOption(
            symbol: "arrow.triangle.merge", displayName: "Merged", category: .repository,
            keywords: ["git", "pull request", "integrate"]),
        StatusLineIconOption(
            symbol: "arrow.triangle.pull", displayName: "Pull Request", category: .repository,
            keywords: ["git", "review", "github"]),
        StatusLineIconOption(
            symbol: "tag", displayName: "Tag", category: .repository,
            keywords: ["release", "version", "label"]),

        StatusLineIconOption(
            symbol: "checkmark.circle", displayName: "Complete", category: .status,
            keywords: ["success", "passed", "done"]),
        StatusLineIconOption(
            symbol: "checkmark.seal", displayName: "Verified", category: .status,
            keywords: ["approved", "success", "passed"]),
        StatusLineIconOption(
            symbol: "xmark.circle", displayName: "Closed", category: .status,
            keywords: ["failed", "cancelled", "error"]),
        StatusLineIconOption(
            symbol: "circle.dotted", displayName: "In Progress", category: .status,
            keywords: ["working", "pending", "loading"]),
        StatusLineIconOption(
            symbol: "info.circle", displayName: "Information", category: .status,
            keywords: ["details", "help", "about"]),
        StatusLineIconOption(
            symbol: "text.alignleft", displayName: "Response Style", category: .status,
            keywords: ["style", "text", "response"]),

        StatusLineIconOption(
            symbol: "clock", displayName: "Clock", category: .time,
            keywords: ["duration", "time", "elapsed"]),
        StatusLineIconOption(
            symbol: "clock.arrow.2.circlepath", displayName: "API Duration", category: .time,
            keywords: ["request", "latency", "elapsed"]),
        StatusLineIconOption(
            symbol: "timer", displayName: "Timer", category: .time,
            keywords: ["deadline", "duration", "countdown"]),
        StatusLineIconOption(
            symbol: "calendar.badge.clock", displayName: "Scheduled", category: .time,
            keywords: ["date", "reset", "calendar"]),
        StatusLineIconOption(
            symbol: "arrow.clockwise.circle", displayName: "Refresh", category: .time,
            keywords: ["retry", "reload", "reset"]),
        StatusLineIconOption(
            symbol: "stopwatch", displayName: "Stopwatch", category: .time,
            keywords: ["duration", "performance", "elapsed"]),

        StatusLineIconOption(
            symbol: "dollarsign.circle", displayName: "Cost", category: .cost,
            keywords: ["price", "spend", "budget"]),
        StatusLineIconOption(
            symbol: "dollarsign.square", displayName: "Dollars", category: .cost,
            keywords: ["price", "spend", "budget"]),
        StatusLineIconOption(
            symbol: "creditcard", displayName: "Billing", category: .cost,
            keywords: ["payment", "cost", "spend"]),
        StatusLineIconOption(
            symbol: "chart.line.uptrend.xyaxis", displayName: "Spend Trend", category: .cost,
            keywords: ["cost", "budget", "chart"]),

        StatusLineIconOption(
            symbol: "gauge.with.needle", displayName: "Usage", category: .data,
            keywords: ["context", "rate", "capacity"]),
        StatusLineIconOption(
            symbol: "gauge.with.needle.fill", displayName: "Usage Filled", category: .data,
            keywords: ["context", "rate", "capacity"]),
        StatusLineIconOption(
            symbol: "percent", displayName: "Percent", category: .data,
            keywords: ["percentage", "rate", "usage"]),
        StatusLineIconOption(
            symbol: "number", displayName: "Number", category: .data,
            keywords: ["count", "metric", "value"]),
        StatusLineIconOption(
            symbol: "plus.square", displayName: "Lines Added", category: .data,
            keywords: ["diff", "git", "added"]),
        StatusLineIconOption(
            symbol: "minus.square", displayName: "Lines Removed", category: .data,
            keywords: ["diff", "git", "deleted"]),
        StatusLineIconOption(
            symbol: "arrow.down.circle", displayName: "Input", category: .data,
            keywords: ["tokens", "received", "download"]),
        StatusLineIconOption(
            symbol: "arrow.up.circle", displayName: "Output", category: .data,
            keywords: ["tokens", "sent", "upload"]),
        StatusLineIconOption(
            symbol: "ruler", displayName: "Context Size", category: .data,
            keywords: ["tokens", "window", "limit"]),

        StatusLineIconOption(
            symbol: "network", displayName: "Network", category: .network,
            keywords: ["connection", "service", "api"]),
        StatusLineIconOption(
            symbol: "globe", displayName: "Globe", category: .network,
            keywords: ["internet", "remote", "web"]),
        StatusLineIconOption(
            symbol: "antenna.radiowaves.left.and.right", displayName: "Signal", category: .network,
            keywords: ["connection", "wireless", "availability"]),
        StatusLineIconOption(
            symbol: "cloud", displayName: "Cloud", category: .network,
            keywords: ["remote", "service", "sync"]),
        StatusLineIconOption(
            symbol: "link", displayName: "Link", category: .network,
            keywords: ["url", "connection", "reference"]),

        StatusLineIconOption(
            symbol: "person", displayName: "Person", category: .people,
            keywords: ["user", "owner", "author"]),
        StatusLineIconOption(
            symbol: "person.2", displayName: "People", category: .people,
            keywords: ["team", "collaboration", "users"]),
        StatusLineIconOption(
            symbol: "person.crop.circle", displayName: "Agent", category: .people,
            keywords: ["profile", "assistant", "user"]),
        StatusLineIconOption(
            symbol: "person.crop.rectangle", displayName: "Profile", category: .people,
            keywords: ["account", "user", "identity"]),
        StatusLineIconOption(
            symbol: "figure.walk", displayName: "Walking", category: .people,
            keywords: ["activity", "progress", "movement"]),

        StatusLineIconOption(
            symbol: "bell", displayName: "Bell", category: .alert,
            keywords: ["notification", "attention", "alert"]),
        StatusLineIconOption(
            symbol: "bell.badge", displayName: "Notification", category: .alert,
            keywords: ["attention", "unread", "alert"]),
        StatusLineIconOption(
            symbol: "exclamationmark.triangle", displayName: "Warning", category: .alert,
            keywords: ["error", "attention", "risk"]),
        StatusLineIconOption(
            symbol: "shield", displayName: "Security", category: .alert,
            keywords: ["safe", "protection", "warning"]),
        StatusLineIconOption(
            symbol: "flag", displayName: "Flag", category: .alert,
            keywords: ["attention", "marker", "priority"]),
    ]
    static let appCapability = StatusFactCapability(
        owner: .app, supportedHarnesses: allHarnesses, missingBehavior: .pending)
    static let mergedCapability = StatusFactCapability(
        owner: .merged, supportedHarnesses: allHarnesses, missingBehavior: .pending)
    static let claudeCapability = StatusFactCapability(
        owner: .harness, supportedHarnesses: [.claude], missingBehavior: .unsupported)
    static let claudeCodexCapability = StatusFactCapability(
        owner: .harness, supportedHarnesses: [.claude, .codex], missingBehavior: .pending)
    static let modelCapability = StatusFactCapability(
        owner: .merged, supportedHarnesses: allHarnesses, missingBehavior: .pending)
    static let claudeOpencodeCapability = StatusFactCapability(
        owner: .harness, supportedHarnesses: [.claude, .opencode], missingBehavior: .pending)
    static let inputOutputTokenCapability = StatusFactCapability(
        owner: .harness, supportedHarnesses: [.claude, .codex, .opencode], missingBehavior: .pending)

    static let itemCapabilities: [String: StatusFactCapability] = [
        "worktree": appCapability,
        "duration": appCapability,
        "version": mergedCapability,
        "pr": appCapability,
        "linesAdded": appCapability,
        "linesRemoved": appCapability,
        "profileName": appCapability,
        "model": modelCapability,
        "cost": claudeOpencodeCapability,
        "inputTokens": inputOutputTokenCapability,
        "outputTokens": inputOutputTokenCapability,
        "context": claudeCodexCapability,
        "contextRemaining": claudeCodexCapability,
        "rate5h": claudeCodexCapability,
        "rate7d": claudeCodexCapability,
        "rate5hReset": claudeCodexCapability,
        "rate7dReset": claudeCodexCapability,
        "effort": claudeCapability,
        "thinking": claudeCapability,
        "vimMode": claudeCapability,
        "agentName": claudeCapability,
        "sessionName": claudeOpencodeCapability,
        "outputStyle": claudeCapability,
        "exceeds200k": claudeCapability,
        "repo": appCapability,
        "contextSize": claudeCapability,
        "cacheRead": claudeCapability,
        "cacheCreation": claudeCapability,
        "apiDuration": claudeCapability,
    ]

    static let itemAvailability: [String: StatusFactCapability] = itemCapabilities

    static func isSFSymbolAvailable(_ symbol: String) -> Bool {
        guard !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
    }

    static func renderedCustomFieldSymbol(scriptOverride: String?, configuredSymbol: String) -> String {
        if let scriptOverride, isSFSymbolAvailable(scriptOverride) {
            return scriptOverride
        }
        if isSFSymbolAvailable(configuredSymbol) {
            return configuredSymbol
        }
        return "terminal"
    }

    static let itemOrder: [String] = [
        "model", "worktree", "cost", "context", "effort", "thinking", "vimMode",
        "agentName", "sessionName", "linesAdded",
        "linesRemoved", "duration", "contextRemaining", "inputTokens", "outputTokens",
        "rate5h", "rate7d", "rate5hReset", "rate7dReset", "version", "outputStyle", "exceeds200k",
        "pr", "profileName",
        "repo", "contextSize", "cacheRead", "cacheCreation", "apiDuration",
    ]

    private static let defaultRowItemIDs: [[String]] = [
        ["pr", "profileName", "model", "effort"],
        ["context", "contextRemaining", "contextSize", "exceeds200k"],
        ["inputTokens", "outputTokens", "cacheRead", "cacheCreation"],
        ["worktree", "cost", "linesAdded", "linesRemoved"],
    ]

    static var allItems: [StatusLineItem] {
        itemOrder.compactMap { id in
            guard let meta = itemMetadata[id] else { return nil }
            return StatusLineItem(id: id, label: meta.label, sfSymbol: meta.symbol)
        }
    }

    func availableItems() -> [StatusLineItem] {
        Self.allItems + customFields.map { StatusLineItem(id: $0.id, label: $0.label, sfSymbol: $0.sfSymbol) }
    }

    func customField(withID id: String) -> CustomStatusLineField? {
        customFields.first { $0.id == id }
    }

    func capability(for item: StatusLineItem) -> StatusFactCapability {
        guard let field = customField(withID: item.id) else {
            return item.capability
        }
        return StatusFactCapability(
            owner: .app,
            supportedHarnesses: field.supportedHarnesses,
            missingBehavior: .unsupported
        )
    }

    func supports(_ item: StatusLineItem, on harness: Harness) -> Bool {
        capability(for: item).supports(harness)
    }

    var usedItemIDs: Set<String> {
        Set(rows.flatMap { $0.items.map(\.id) })
    }

    init() {
        rows = Self.defaultRowItemIDs.map { itemIDs in
            StatusLineRow(
                items: itemIDs.compactMap { id -> StatusLineItem? in
                    guard let meta = Self.itemMetadata[id] else { return nil }
                    return StatusLineItem(id: id, label: meta.label, sfSymbol: meta.symbol)
                })
        }
        factLabelStyle = .symbolAndLabel
        rowAlignment = .spaceBetween
        showPercentagesAsText = false
        customFields = []
        needsPersistenceMigration = false
    }

    static func wizardDefault() -> StatusLineConfig {
        StatusLineConfig()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        factLabelStyle =
            try container.decodeIfPresent(FactLabelStyle.self, forKey: .factLabelStyle) ?? .symbolAndLabel
        rowAlignment = try container.decodeIfPresent(RowAlignment.self, forKey: .rowAlignment) ?? .spaceBetween
        showPercentagesAsText = try container.decodeIfPresent(Bool.self, forKey: .showPercentagesAsText) ?? false
        let decodedCustomFields =
            try container.decodeIfPresent([CustomStatusLineField].self, forKey: .customFields) ?? []
        customFields = decodedCustomFields
        var migrationNeeded = decodedCustomFields.contains { $0.needsPersistenceMigration }

        if let savedRows = try container.decodeIfPresent([StatusLineRow].self, forKey: .rows) {
            rows = savedRows.enumerated().map { rowIndex, row in
                var mutableRow = row
                let rowHasWorktree = row.items.contains { $0.id == "worktree" }
                mutableRow.items = row.items.enumerated().compactMap { itemIndex, item in
                    if item.id == "gitWorktree" {
                        migrationNeeded = true
                        TracingService.shared.record(
                            "statusline.migration.gitworktree_dropped",
                            attributes: ["row_index": "\(rowIndex)", "position": "\(itemIndex)"])
                        return nil
                    }
                    if item.id == "worktreeBranch" {
                        migrationNeeded = true
                        let substituted = !rowHasWorktree
                        TracingService.shared.record(
                            "statusline.migration.worktreebranch_merged",
                            attributes: [
                                "row_index": "\(rowIndex)",
                                "position": "\(itemIndex)",
                                "substituted": substituted ? "true" : "false",
                            ])
                        if substituted {
                            let meta = StatusLineConfig.itemMetadata["worktree"]!
                            return StatusLineItem(id: "worktree", label: meta.label, sfSymbol: meta.symbol)
                        }
                        return nil
                    }
                    if let meta = StatusLineConfig.itemMetadata[item.id] {
                        if item.label != meta.label || item.sfSymbol != meta.symbol {
                            migrationNeeded = true
                        }
                        return StatusLineItem(id: item.id, label: meta.label, sfSymbol: meta.symbol)
                    }
                    if let field = decodedCustomFields.first(where: { $0.id == item.id }) {
                        if item.label != field.label || item.sfSymbol != field.sfSymbol {
                            migrationNeeded = true
                        }
                        return StatusLineItem(id: field.id, label: field.label, sfSymbol: field.sfSymbol)
                    }
                    return item
                }
                return mutableRow
            }
        } else if let legacyItems = try container.decodeIfPresent([LegacyStatusLineItem].self, forKey: .items) {
            migrationNeeded = true
            let visibleLegacyItems = legacyItems.enumerated().filter { $0.element.isVisible }
            let hasWorktree = visibleLegacyItems.contains { $0.element.id == "worktree" }
            let visibleItems =
                visibleLegacyItems.compactMap { itemIndex, legacy -> StatusLineItem? in
                    if legacy.id == "gitWorktree" {
                        TracingService.shared.record(
                            "statusline.migration.gitworktree_dropped",
                            attributes: ["row_index": "0", "position": "\(itemIndex)"])
                        return nil
                    }
                    if legacy.id == "worktreeBranch" {
                        let substituted = !hasWorktree
                        TracingService.shared.record(
                            "statusline.migration.worktreebranch_merged",
                            attributes: [
                                "row_index": "0",
                                "position": "\(itemIndex)",
                                "substituted": substituted ? "true" : "false",
                            ])
                        guard substituted, let meta = StatusLineConfig.itemMetadata["worktree"] else {
                            return nil
                        }
                        return StatusLineItem(id: "worktree", label: meta.label, sfSymbol: meta.symbol)
                    }
                    guard let meta = StatusLineConfig.itemMetadata[legacy.id] else { return nil }
                    return StatusLineItem(
                        id: legacy.id,
                        label: meta.label,
                        sfSymbol: legacy.sfSymbol ?? meta.symbol
                    )
                }
            rows = [StatusLineRow(items: visibleItems)]
        } else {
            let defaults = StatusLineConfig()
            rows = defaults.rows
        }
        needsPersistenceMigration = migrationNeeded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rows, forKey: .rows)
        try container.encode(factLabelStyle, forKey: .factLabelStyle)
        try container.encode(rowAlignment, forKey: .rowAlignment)
        try container.encode(showPercentagesAsText, forKey: .showPercentagesAsText)
        try container.encode(customFields, forKey: .customFields)
    }

    enum CodingKeys: String, CodingKey {
        case rows, factLabelStyle, rowAlignment, showPercentagesAsText, customFields
        case items
    }

    func validateForAgentControl() throws {
        let customIDs = customFields.map(\.id)
        guard Set(customIDs).count == customIDs.count else {
            throw StatusLineConfigurationValidationError.duplicateCustomFieldID
        }
        for field in customFields {
            let prefix = "custom:"
            guard field.id.hasPrefix(prefix),
                UUID(uuidString: String(field.id.dropFirst(prefix.count))) != nil
            else {
                throw StatusLineConfigurationValidationError.invalidCustomFieldID(field.id)
            }
            guard !field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !field.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw StatusLineConfigurationValidationError.emptyCustomField(field.id)
            }
            guard !field.supportedHarnesses.isEmpty,
                field.supportedHarnesses.isSubset(of: Self.allHarnesses)
            else {
                throw StatusLineConfigurationValidationError.invalidCustomFieldHarnesses(field.id)
            }
            guard Self.isSFSymbolAvailable(field.sfSymbol) else {
                throw StatusLineConfigurationValidationError.unsupportedCustomFieldIcon(field.sfSymbol)
            }
        }

        let knownIDs = Set(Self.itemMetadata.keys).union(customIDs)
        var usedIDs = Set<String>()
        for row in rows {
            for item in row.items {
                guard knownIDs.contains(item.id) else {
                    throw StatusLineConfigurationValidationError.unknownItemID(item.id)
                }
                guard usedIDs.insert(item.id).inserted else {
                    throw StatusLineConfigurationValidationError.duplicateItemID(item.id)
                }
            }
        }
    }

    mutating func markPersistenceMigrationHandled() {
        needsPersistenceMigration = false
        for index in customFields.indices {
            customFields[index].needsPersistenceMigration = false
        }
    }

    static func == (lhs: StatusLineConfig, rhs: StatusLineConfig) -> Bool {
        lhs.rows == rhs.rows
            && lhs.factLabelStyle == rhs.factLabelStyle
            && lhs.rowAlignment == rhs.rowAlignment
            && lhs.showPercentagesAsText == rhs.showPercentagesAsText
            && lhs.customFields == rhs.customFields
    }
}

enum StatusLineConfigurationValidationError: Error, Equatable, LocalizedError {
    case duplicateCustomFieldID
    case invalidCustomFieldID(String)
    case emptyCustomField(String)
    case invalidCustomFieldHarnesses(String)
    case unsupportedCustomFieldIcon(String)
    case unknownItemID(String)
    case duplicateItemID(String)

    var errorDescription: String? {
        switch self {
        case .duplicateCustomFieldID:
            return "Status-line custom field IDs must be unique"
        case .invalidCustomFieldID(let id):
            return "Status-line custom field ID is invalid: \(id)"
        case .emptyCustomField(let id):
            return "Status-line custom field must have a label and command: \(id)"
        case .invalidCustomFieldHarnesses(let id):
            return "Status-line custom field must target one or more supported harnesses: \(id)"
        case .unsupportedCustomFieldIcon(let symbol):
            return "Status-line custom field icon is not supported: \(symbol)"
        case .unknownItemID(let id):
            return "Status-line item is not in the catalog: \(id)"
        case .duplicateItemID(let id):
            return "Status-line item appears more than once: \(id)"
        }
    }
}

struct StatusCheck: Codable, Identifiable {
    let name: String
    let status: String
    let conclusion: String?
    let detailsUrl: String?

    var id: String { name }

    var isFailing: Bool {
        let failedConclusions: Set<String> = ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED"]
        return failedConclusions.contains(conclusion?.uppercased() ?? "")
    }

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case conclusion
        case detailsUrl
    }
}

enum BuildStatus: Equatable {
    case success
    case running
    case failed
    case cancelled
    case unknown
}

struct PullRequest: Codable, Identifiable {
    let number: Int
    let title: String
    let state: String
    let url: String
    var isDraft: Bool?
    var statusCheckRollup: [StatusCheck]?
    var unresolvedCommentCount: Int?
    var commitStatusState: String?
    var mergeable: String?
    var reviewDecision: String?

    var reviewStateLabel: String? {
        if isDraft == true { return "draft" }
        guard let decision = reviewDecision else { return nil }
        switch decision {
        case "APPROVED": return "approved"
        case "CHANGES_REQUESTED": return "changes requested"
        case "REVIEW_REQUIRED": return "pending"
        default: return nil
        }
    }

    var id: Int { number }

    var hasMergeConflicts: Bool {
        mergeable?.uppercased() == "CONFLICTING"
    }

    var displayState: String {
        if isDraft == true { return "draft" }
        switch state.lowercased() {
        case "open": return "open"
        case "merged": return "merged"
        case "closed": return "closed"
        default: return state.lowercased()
        }
    }

    var buildStatus: BuildStatus {
        if let checks = statusCheckRollup, !checks.isEmpty {
            let failedConclusions: Set<String> = ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED"]
            if checks.contains(where: { failedConclusions.contains($0.conclusion?.uppercased() ?? "") }) {
                return .failed
            }
            if checks.contains(where: { $0.conclusion?.uppercased() == "CANCELLED" }) {
                return .cancelled
            }
            let runningStatuses: Set<String> = ["IN_PROGRESS", "QUEUED", "WAITING", "REQUESTED", "PENDING"]
            if checks.contains(where: { runningStatuses.contains($0.status.uppercased()) }) {
                return .running
            }
            let passConclusions: Set<String> = ["SUCCESS", "NEUTRAL", "SKIPPED"]
            if checks.allSatisfy({ passConclusions.contains($0.conclusion?.uppercased() ?? "") }) {
                return .success
            }
        }
        guard let apiState = commitStatusState else { return .unknown }
        switch apiState.uppercased() {
        case "SUCCESS": return .success
        case "FAILURE", "ERROR": return .failed
        case "PENDING": return .running
        default: return .unknown
        }
    }

    var stateIconName: String {
        if isDraft == true { return "pencil.line" }
        switch state.lowercased() {
        case "open": return "arrow.triangle.pull"
        case "merged": return "arrow.triangle.merge"
        case "closed": return "xmark.circle"
        default: return "arrow.triangle.pull"
        }
    }

    var failingChecks: [StatusCheck] {
        statusCheckRollup?.filter { $0.isFailing } ?? []
    }

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case state
        case url
        case isDraft
        case statusCheckRollup
        case mergeable
    }
}

struct StatusLineData: Codable {
    enum PRTrackingState: Equatable, Codable {
        case loading
        case current
        case absent
        case failed(GitHubCLIFailure)
    }

    struct Repo: Codable {
        let host: String
        let owner: String
        let name: String
    }

    struct Model: Codable {
        let id: String?
        let displayName: String?
        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    struct Cost: Codable {
        let totalCostUsd: Double?
        let totalDurationMs: Double?
        let totalLinesAdded: Int?
        let totalLinesRemoved: Int?
        let totalApiDurationMs: Double?
        enum CodingKeys: String, CodingKey {
            case totalCostUsd = "total_cost_usd"
            case totalDurationMs = "total_duration_ms"
            case totalLinesAdded = "total_lines_added"
            case totalLinesRemoved = "total_lines_removed"
            case totalApiDurationMs = "total_api_duration_ms"
        }

        init(
            totalCostUsd: Double?,
            totalDurationMs: Double?,
            totalLinesAdded: Int?,
            totalLinesRemoved: Int?,
            totalApiDurationMs: Double? = nil
        ) {
            self.totalCostUsd = totalCostUsd
            self.totalDurationMs = totalDurationMs
            self.totalLinesAdded = totalLinesAdded
            self.totalLinesRemoved = totalLinesRemoved
            self.totalApiDurationMs = totalApiDurationMs
        }
    }

    struct ContextWindow: Codable {
        struct CurrentUsage: Codable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?
            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
            }
        }

        let usedPercentage: Int?
        let remainingPercentage: Int?
        let totalInputTokens: Int?
        let totalOutputTokens: Int?
        let contextWindowSize: Int?
        let currentUsage: CurrentUsage?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case remainingPercentage = "remaining_percentage"
            case totalInputTokens = "total_input_tokens"
            case totalOutputTokens = "total_output_tokens"
            case contextWindowSize = "context_window_size"
            case currentUsage = "current_usage"
        }

        init(
            usedPercentage: Int?,
            remainingPercentage: Int?,
            totalInputTokens: Int?,
            totalOutputTokens: Int?,
            contextWindowSize: Int? = nil,
            currentUsage: CurrentUsage? = nil
        ) {
            self.usedPercentage = usedPercentage
            self.remainingPercentage = remainingPercentage
            self.totalInputTokens = totalInputTokens
            self.totalOutputTokens = totalOutputTokens
            self.contextWindowSize = contextWindowSize
            self.currentUsage = currentUsage
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercentage = Self.flexInt(container, key: .usedPercentage)
            remainingPercentage = Self.flexInt(container, key: .remainingPercentage)
            totalInputTokens = Self.flexInt(container, key: .totalInputTokens)
            totalOutputTokens = Self.flexInt(container, key: .totalOutputTokens)
            contextWindowSize = Self.flexInt(container, key: .contextWindowSize)
            currentUsage = try? container.decodeIfPresent(CurrentUsage.self, forKey: .currentUsage)
        }

        private static func flexInt(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
            if let decoded = try? container.decodeIfPresent(Int.self, forKey: key) { return decoded }
            if let decoded = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(decoded) }
            return nil
        }
    }

    struct RateLimit: Codable {
        let usedPercentage: Double?
        let resetsAt: Int?
        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }

    struct RateLimits: Codable {
        let fiveHour: RateLimit?
        let sevenDay: RateLimit?
        var bucketID: String?
        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case bucketID = "bucket_id"
        }
    }

    struct Workspace: Codable {
        let gitWorktree: String?
        enum CodingKeys: String, CodingKey {
            case gitWorktree = "git_worktree"
        }
    }

    struct Worktree: Codable {
        let name: String?
        let branch: String?

        var factText: String {
            guard let name else { return "—" }
            if let branch { return "\(name) • \(branch)" }
            return name
        }
    }

    struct Effort: Codable {
        let level: String?
    }

    struct Thinking: Codable {
        let enabled: Bool?
    }

    struct Agent: Codable {
        let name: String?
    }

    struct OutputStyle: Codable {
        let name: String?
        enum CodingKeys: String, CodingKey { case name }
    }

    struct Vim: Codable {
        let mode: String?
    }

    struct SessionStatus: Codable {
        let state: String?
    }

    var model: Model?
    var cost: Cost?
    var contextWindow: ContextWindow?
    var rateLimits: RateLimits?
    var worktree: Worktree?
    let workspace: Workspace?
    var effort: Effort?
    var thinking: Thinking?
    var agent: Agent?
    var outputStyle: OutputStyle?
    var vim: Vim?
    var sessionName: String?
    var version: String?
    var exceeds200kTokens: Bool?
    var pr: PullRequest?
    var prTrackingState: PRTrackingState?
    var sessionStatus: SessionStatus?
    var repo: Repo?
    var customFields: [String: CustomFieldRenderValue]?

    enum CodingKeys: String, CodingKey {
        case model
        case cost
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
        case worktree
        case workspace
        case effort
        case thinking
        case agent
        case outputStyle = "output_style"
        case vim
        case sessionName = "session_name"
        case version
        case exceeds200kTokens = "exceeds_200k_tokens"
        case sessionStatus = "session_status"
        case repo
        case prTrackingState = "pr_tracking_state"
    }

    static func empty(pr: PullRequest? = nil) -> StatusLineData {
        StatusLineData(
            model: nil, cost: nil, contextWindow: nil, rateLimits: nil,
            worktree: nil, workspace: nil, effort: nil, thinking: nil,
            agent: nil, outputStyle: nil, vim: nil,
            sessionName: nil, version: nil, exceeds200kTokens: nil,
            pr: pr, prTrackingState: nil, sessionStatus: nil, repo: nil
        )
    }
}
