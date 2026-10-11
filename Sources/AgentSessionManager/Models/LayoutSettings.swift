import AppKit
import Foundation

enum ResizeDirection: String, Codable, CaseIterable {
    case left, right, up, down

    var axis: ResizeAxis { self == .left || self == .right ? .columns : .rows }
    var sign: Double { self == .left || self == .up ? -1 : 1 }
    var key: String {
        switch self {
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        }
    }
}

enum ResizeAxis: String, Codable, Hashable {
    case columns, rows
}

struct ResizeAction: Hashable, Codable, CaseIterable {
    var direction: ResizeDirection
    var larger: Bool

    static var allCases: [Self] {
        ResizeDirection.allCases.flatMap { [Self(direction: $0, larger: false), Self(direction: $0, larger: true)] }
    }
    var id: String { direction.rawValue + (larger ? "-larger" : "") }
    var step: Double { larger ? 16 : 4 }
    var label: String { "Resize \(direction.rawValue.capitalized)" + (larger ? " (Larger Step)" : "") }
    var defaultBinding: ResizeKeyBinding {
        ResizeKeyBinding(key: direction.key, modifiers: larger ? [.command, .option, .shift] : [.command, .option])
    }
}

struct ResizeKeyBinding: Codable, Equatable, Hashable {
    var key: String
    var modifierBits: UInt

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key.lowercased()
        modifierBits = modifiers.intersection([.command, .option, .shift, .control]).rawValue
    }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierBits) }
    var isValid: Bool {
        key.count == 1 && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && key == key.lowercased()
            && !["\u{7f}", "\u{1b}"].contains(key)
            && modifiers.contains(.command)
            && modifiers.intersection([.command, .option, .shift, .control]).rawValue == modifierBits
    }
    var display: String {
        "⌘" + (modifiers.contains(.option) ? "⌥" : "") + (modifiers.contains(.shift) ? "⇧" : "")
            + (modifiers.contains(.control) ? "⌃" : "") + key.uppercased()
    }

    static func key(for event: NSEvent) -> String {
        switch event.keyCode {
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: event.charactersIgnoringModifiers?.lowercased() ?? ""
        }
    }

    enum CodingKeys: String, CodingKey { case key, modifierBits }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key).lowercased()
        modifierBits = try container.decode(UInt.self, forKey: .modifierBits)
    }

    static func appBindings(defaults: UserDefaults = .standard) -> Set<Self> {
        var bindings: Set<Self> = Set((1...9).map { Self(key: String($0), modifiers: .command) })
        for (name, key) in [
            ("newTab", "t"), ("newPane", "p"), ("closePane", "w"), ("closeTab", "k"),
            ("refreshPane", "r"), ("viewPaneSettings", "i"),
        ] {
            bindings.insert(Self(key: defaults.string(forKey: "keyBinding.\(name)Key") ?? key, modifiers: .command))
        }
        bindings.insert(
            Self(key: defaults.string(forKey: "keyBinding.openShellHereKey") ?? "s", modifiers: [.command, .shift]))
        for key in ["c", "v", "x", "a", "q", "h", "m", ",", "z"] {
            bindings.insert(Self(key: key, modifiers: .command))
        }
        for key in ["d", "i", "z"] {
            bindings.insert(Self(key: key, modifiers: [.command, .shift]))
        }
        bindings.insert(Self(key: "h", modifiers: [.command, .option]))
        return bindings
    }
}

struct PaneResizeShortcutBindings: Codable, Equatable {
    var entries: [String: ResizeKeyBinding] = Dictionary(
        uniqueKeysWithValues: ResizeAction.allCases.map { ($0.id, $0.defaultBinding) })
    var conflicts: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let values = (try? container.decode([String: ResizeBindingEntry].self)) ?? [:]
        for action in ResizeAction.allCases {
            if let entry = values[action.id] {
                switch entry {
                case .binding(let binding) where binding.isValid:
                    entries[action.id] = binding
                case .disabled:
                    entries.removeValue(forKey: action.id)
                default:
                    break
                }
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var values: [String: ResizeKeyBinding?] = [:]
        for action in ResizeAction.allCases {
            if let binding = entries[action.id] {
                values[action.id] = binding
            } else {
                values.updateValue(nil, forKey: action.id)
            }
        }
        try container.encode(values)
    }

    mutating func resolveConflicts(appBindings: Set<ResizeKeyBinding>) {
        let conflicting = ResizeAction.allCases.filter { action in
            guard let binding = entries[action.id] else { return false }
            return appBindings.contains(binding)
                || ResizeAction.allCases.contains { other in
                    other != action && entries[other.id] == binding
                }
        }
        for action in conflicting {
            entries.removeValue(forKey: action.id)
            if !conflicts.contains(action.id) { conflicts.append(action.id) }
        }
    }

    func binding(for action: ResizeAction) -> ResizeKeyBinding? {
        entries[action.id]
    }

    mutating func setBinding(_ binding: ResizeKeyBinding?, for action: ResizeAction) {
        if let binding {
            entries[action.id] = binding
        } else {
            entries.removeValue(forKey: action.id)
        }
        conflicts.removeAll { $0 == action.id }
    }

    func action(key: String, modifiers: NSEvent.ModifierFlags) -> ResizeAction? {
        let binding = ResizeKeyBinding(key: key, modifiers: modifiers)
        return ResizeAction.allCases.first { entries[$0.id] == binding }
    }
}

private enum ResizeBindingEntry: Decodable {
    case binding(ResizeKeyBinding)
    case disabled
    case invalid

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .disabled
        } else if let binding = try? container.decode(ResizeKeyBinding.self) {
            self = .binding(binding)
        } else {
            self = .invalid
        }
    }
}

struct LayoutSettings: Codable, Equatable {
    var tabBarHeight: Double = 44
    var notificationSidebarWidth: Double = 240
    var bindings = PaneResizeShortcutBindings()

    enum CodingKeys: String, CodingKey { case tabBarHeight, notificationSidebarWidth, bindings }
    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Double.self, forKey: .tabBarHeight), value.isFinite,
            (44...96).contains(value)
        {
            tabBarHeight = value
        }
        if let value = try? container.decode(Double.self, forKey: .notificationSidebarWidth), value.isFinite,
            (160...480).contains(value)
        {
            notificationSidebarWidth = value
        }
        bindings =
            (try? container.decode(PaneResizeShortcutBindings.self, forKey: .bindings)) ?? PaneResizeShortcutBindings()
        bindings.resolveConflicts(appBindings: ResizeKeyBinding.appBindings())
    }

    mutating func resetSections() {
        tabBarHeight = 44
        notificationSidebarWidth = 240
    }
}

struct PaneGridSizePreferences: Codable, Equatable {
    var columnWeights: [Double] = []
    var rowWeights: [Double] = []

    enum CodingKeys: String, CodingKey { case columnWeights, rowWeights }
    init(columnWeights: [Double] = [], rowWeights: [Double] = []) {
        self.columnWeights = GridLayout.normalized(columnWeights)
        self.rowWeights = GridLayout.normalized(rowWeights)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columnWeights = GridLayout.normalized((try? container.decode([Double].self, forKey: .columnWeights)) ?? [])
        rowWeights = GridLayout.normalized((try? container.decode([Double].self, forKey: .rowWeights)) ?? [])
    }

    mutating func reconcile(layout: GridLayout) {
        if columnWeights.count != layout.columns {
            columnWeights = Array(repeating: 1 / Double(layout.columns), count: layout.columns)
        }
        if rowWeights.count != layout.rows {
            rowWeights = Array(repeating: 1 / Double(layout.rows), count: layout.rows)
        }
    }
}
