import SwiftUI

struct StatusLineEditorPhases: OptionSet {
    let rawValue: Int

    static let display = StatusLineEditorPhases(rawValue: 1 << 0)
    static let rows = StatusLineEditorPhases(rawValue: 1 << 1)
    static let full: StatusLineEditorPhases = [.display, .rows]
}

private enum CustomFieldSheetTarget: Identifiable {
    case new
    case edit(CustomStatusLineField)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let field): return field.id
        }
    }
}

struct StatusLineConfigLayoutEditor: View {
    @Binding var config: StatusLineConfig
    var filterCLI: Harness?
    let phases: StatusLineEditorPhases
    let onPersist: () -> Void
    var onRunNow: ((String) -> String?)?
    var isRunNowAvailable: ((CustomStatusLineField) -> Bool)?

    @State private var customFieldSheetTarget: CustomFieldSheetTarget?

    var body: some View {
        Group {
            if phases.contains(.display) {
                Section("Display") {
                    LabeledContent {
                        Picker("Fact style", selection: factStylePickerBinding) {
                            ForEach(FactLabelStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 160)
                    } label: {
                        Text("Fact style")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    .pinnedListRowBackground()
                    LabeledContent {
                        Picker("Item alignment", selection: rowAlignmentPickerBinding) {
                            ForEach(RowAlignment.allCases, id: \.self) { alignment in
                                Text(alignment.displayName).tag(alignment)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 160)
                    } label: {
                        Text("Item alignment")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    .pinnedListRowBackground()
                    LabeledContent {
                        Toggle("", isOn: showPercentagesAsTextBinding)
                            .labelsHidden()
                            .accessibilityIdentifier("settings-statusline-percentages-text-toggle")
                    } label: {
                        Text("Show percentages as text")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    .pinnedListRowBackground()
                }
            }
            if phases.contains(.rows) {
                ForEach(Array(config.rows.indices), id: \.self) { rowIndex in
                    let rowCount = config.rows.count
                    let base = config.availableItems().filter { !config.usedItemIDs.contains($0.id) }
                    let filtered = filterCLI.map { cli in base.filter { config.supports($0, on: cli) } } ?? base
                    let available = filtered.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
                    Section {
                        ForEach(config.rows[rowIndex].items) { item in
                            HStack {
                                Image(
                                    systemName: item.id.hasPrefix("custom:")
                                        ? StatusLineConfig.renderedCustomFieldSymbol(
                                            scriptOverride: nil,
                                            configuredSymbol: item.sfSymbol
                                        )
                                        : item.sfSymbol
                                )
                                .frame(width: 16)
                                .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.label)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.medium)
                                    let descriptions = [
                                        "model": "Selected model name",
                                        "worktree": "Git worktree name and current branch",
                                        "cost": "Total session cost in USD",
                                        "context": "Context window used (progress bar or text)",
                                        "effort": "Effort level (Claude only)",
                                        "thinking": "Whether extended thinking is on or off (Claude only)",
                                        "vimMode": "Vim editor mode (Claude only)",
                                        "agentName": "Agent name (Claude only)",
                                        "sessionName": "Session name",
                                        "linesAdded": "Lines added vs HEAD (git diff --shortstat HEAD)",
                                        "linesRemoved": "Lines removed vs HEAD (git diff --shortstat HEAD)",
                                        "duration": "Total session duration",
                                        "contextRemaining": "Context window remaining (progress bar or text)",
                                        "inputTokens": "Total input tokens used",
                                        "outputTokens": "Total output tokens used",
                                        "rate5h": "5-hour rate limit usage with progress bar",
                                        "rate7d": "7-day rate limit usage with progress bar",
                                        "rate5hReset": "Time until 5-hour rate limit resets",
                                        "rate7dReset": "Time until 7-day rate limit resets",
                                        "version": "Tool CLI version",
                                        "outputStyle": "Output style name (Claude only)",
                                        "exceeds200k": "Warning when context exceeds 200k tokens (Claude only)",
                                        "pr": "GitHub pull request status for the current branch",
                                        "profileName": "Selected profile name when the pane uses one",
                                        "repo": "Git repository host, owner, and name (e.g. owner/repo)",
                                        "contextSize": "Total context window size in tokens (Claude only)",
                                        "cacheRead": "Cache read input tokens this session (Claude only)",
                                        "cacheCreation": "Cache creation input tokens this session (Claude only)",
                                        "apiDuration": "Total API request time in milliseconds (Claude only)",
                                    ]
                                    let customCommand = config.customFields.first { $0.id == item.id }?.command
                                    if let description = descriptions[item.id] ?? customCommand {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(capabilityLabel(for: item))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
                                Button(role: .destructive) {
                                    touch {
                                        $0.rows[rowIndex].items.removeAll { $0.id == item.id }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Menu {
                            if available.isEmpty {
                                Text(
                                    filterCLI == nil
                                        ? "All items are already used" : "No more items supported for this harness"
                                )
                                .foregroundStyle(.secondary)
                            } else {
                                ForEach(available) { item in
                                    Button {
                                        touch {
                                            $0.rows[rowIndex].items.append(item)
                                        }
                                    } label: {
                                        HStack {
                                            Text(item.label)
                                            Text(capabilityLabel(for: item))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Add Item", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("settings-statusline-add-item-\(rowIndex)")
                    } header: {
                        HStack {
                            Text("Row \(rowIndex + 1)")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button {
                                touch { $0.rows.swapAt(rowIndex, rowIndex - 1) }
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(rowIndex == 0)
                            Button {
                                touch { $0.rows.swapAt(rowIndex, rowIndex + 1) }
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(rowIndex == rowCount - 1)
                            Button(role: .destructive) {
                                touch { $0.rows.remove(at: rowIndex) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Section {
                    Button {
                        touch { $0.rows.append(StatusLineRow()) }
                    } label: {
                        Label("Add Row", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                Section("Custom Fields") {
                    ForEach(config.customFields) { field in
                        HStack {
                            Image(
                                systemName: StatusLineConfig.renderedCustomFieldSymbol(
                                    scriptOverride: nil,
                                    configuredSymbol: field.sfSymbol
                                )
                            )
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.label)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                Text(field.command)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(
                                    capabilityLabel(
                                        for: StatusLineItem(
                                            id: field.id, label: field.label, sfSymbol: field.sfSymbol
                                        ))
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                customFieldSheetTarget = .edit(field)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(field.label)")
                            .accessibilityIdentifier("settings-statusline-custom-field-edit-\(field.id)")
                            Button(role: .destructive) {
                                touch { cfg in
                                    cfg.customFields.removeAll { $0.id == field.id }
                                    for rowIndex in cfg.rows.indices {
                                        cfg.rows[rowIndex].items.removeAll { $0.id == field.id }
                                    }
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button {
                        customFieldSheetTarget = .new
                    } label: {
                        Label("Add Custom Field", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("settings-statusline-add-custom-field-button")
                }
            }
        }
        .sheet(item: $customFieldSheetTarget) { target in
            switch target {
            case .new:
                AddCustomStatusLineFieldSheet(
                    editingField: nil,
                    onRunNow: onRunNow,
                    isRunNowAvailable: isRunNowAvailable
                ) { field in
                    touch { $0.customFields.append(field) }
                }
            case .edit(let field):
                AddCustomStatusLineFieldSheet(
                    editingField: field,
                    onRunNow: onRunNow,
                    isRunNowAvailable: isRunNowAvailable
                ) { updated in
                    touch { cfg in
                        if let index = cfg.customFields.firstIndex(where: { $0.id == updated.id }) {
                            cfg.customFields[index] = updated
                            for rowIndex in cfg.rows.indices {
                                for itemIndex in cfg.rows[rowIndex].items.indices
                                where cfg.rows[rowIndex].items[itemIndex].id == updated.id {
                                    cfg.rows[rowIndex].items[itemIndex] = StatusLineItem(
                                        id: updated.id, label: updated.label, sfSymbol: updated.sfSymbol)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var factStylePickerBinding: Binding<FactLabelStyle> {
        Binding(
            get: { config.factLabelStyle },
            set: { newVal in touch { $0.factLabelStyle = newVal } })
    }

    private var rowAlignmentPickerBinding: Binding<RowAlignment> {
        Binding(
            get: { config.rowAlignment },
            set: { newVal in touch { $0.rowAlignment = newVal } })
    }

    private var showPercentagesAsTextBinding: Binding<Bool> {
        Binding(
            get: { config.showPercentagesAsText },
            set: { newVal in touch { $0.showPercentagesAsText = newVal } })
    }

    private func touch(_ update: (inout StatusLineConfig) -> Void) {
        var next = config
        update(&next)
        config = next
        onPersist()
    }

    private func capabilityLabel(for item: StatusLineItem) -> String {
        let harnesses = config.capability(for: item).supportedHarnesses
        if harnesses == StatusLineConfig.allHarnesses {
            return "All harnesses"
        }
        return Harness.allCases
            .filter { harnesses.contains($0) }
            .map(\.displayName)
            .joined(separator: ", ")
    }
}

struct StatusLineContent: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            StatusLineConfigLayoutEditor(
                config: $appSettings.statusLineConfig,
                filterCLI: nil,
                phases: .display,
                onPersist: {
                    SettingsPersistence.saveStatusLine(appSettings: appSettings)
                },
                onRunNow: { fieldID in
                    appState.runSavedStatusLineFieldNow(
                        fieldID: fieldID, profileID: nil, appSettings: appSettings)
                },
                isRunNowAvailable: { field in
                    appSettings.statusLineConfig.customField(withID: field.id) == field
                })
            Section("GitHub PR Tracking") {
                SettingRow(
                    title: "Track pull requests",
                    description:
                        "Detects the PR for the current git branch and shows its status in the status line. "
                        + "Requires the GitHub CLI (gh) installed and authenticated."
                ) {
                    Toggle("Track pull requests", isOn: $appSettings.githubPRTrackingEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .onChange(of: appSettings.githubPRTrackingEnabled) {
                            SettingsPersistence.save(
                                appSettings.githubPRTrackingEnabled, to: "pr-tracking-settings.json")
                            NotificationCenter.default.post(
                                name: .agentSessionManagerPRTrackingSettingChanged, object: nil)
                        }
                        .accessibilityIdentifier("settings-pr-tracking-toggle")
                }
                SettingRow(
                    title: "PR Polling Interval",
                    description:
                        "How often to check for PR updates across all panes (min 15s). Uses a single batched "
                        + "GraphQL request per cycle — the rate limit auto-adjusts at high pane counts.",
                    defaultValue: "30 seconds"
                ) {
                    HStack(spacing: 4) {
                        TextField(
                            "",
                            text: Binding(
                                get: { String(appSettings.prPollingIntervalSeconds) },
                                set: { newValue in
                                    if let parsed = Int(newValue) {
                                        appSettings.prPollingIntervalSeconds = max(15, parsed)
                                        SettingsPersistence.savePRPollingSettings(appSettings: appSettings)
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 72)
                        .accessibilityIdentifier("settings-pr-polling-interval-field")
                        Text("seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                SettingRow(
                    title: "Request Timeout",
                    description:
                        "Cancel the in-flight request and wait for the next cycle if it takes longer "
                        + "than this (min 5s).",
                    defaultValue: "15 seconds"
                ) {
                    HStack(spacing: 4) {
                        TextField(
                            "",
                            text: Binding(
                                get: { String(appSettings.prRequestTimeoutSeconds) },
                                set: { newValue in
                                    if let parsed = Int(newValue) {
                                        appSettings.prRequestTimeoutSeconds = max(5, parsed)
                                        SettingsPersistence.savePRPollingSettings(appSettings: appSettings)
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 72)
                        .accessibilityIdentifier("settings-pr-request-timeout-field")
                        Text("seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                SettingRow(
                    title: "Background Refresh",
                    description:
                        "Keep checking for PR updates while the app is in the background at a reduced rate. "
                        + "Disable to pause all polling when the app is not focused."
                ) {
                    Toggle("Background Refresh", isOn: $appSettings.prBackgroundRefreshEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .onChange(of: appSettings.prBackgroundRefreshEnabled) {
                            SettingsPersistence.savePRPollingSettings(appSettings: appSettings)
                        }
                        .accessibilityIdentifier("settings-pr-background-refresh-toggle")
                }
                SettingRow(
                    title: "Background Polling Interval",
                    description: "How often to check for PR updates while the app is in the background (min 15s).",
                    defaultValue: "60 seconds"
                ) {
                    HStack(spacing: 4) {
                        TextField(
                            "",
                            text: Binding(
                                get: { String(appSettings.prBackgroundPollingIntervalSeconds) },
                                set: { newValue in
                                    if let parsed = Int(newValue) {
                                        appSettings.prBackgroundPollingIntervalSeconds = max(15, parsed)
                                        SettingsPersistence.savePRPollingSettings(appSettings: appSettings)
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 72)
                        .accessibilityIdentifier("settings-pr-background-interval-field")
                        Text("seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(appSettings.prBackgroundRefreshEnabled ? 1 : 0.4)
                .disabled(!appSettings.prBackgroundRefreshEnabled)
            }
            StatusLineConfigLayoutEditor(
                config: $appSettings.statusLineConfig,
                filterCLI: nil,
                phases: .rows,
                onPersist: {
                    SettingsPersistence.saveStatusLine(appSettings: appSettings)
                },
                onRunNow: { fieldID in
                    appState.runSavedStatusLineFieldNow(
                        fieldID: fieldID, profileID: nil, appSettings: appSettings)
                },
                isRunNowAvailable: { field in
                    appSettings.statusLineConfig.customField(withID: field.id) == field
                })
        }
        .formStyle(.grouped)
        .pinnedFormBackground()
    }
}

struct EnvVarOptionRow: View {
    @Binding var option: EnvVarConfig
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.id)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if option.isAppControlled {
                        Text("Controlled by Agent Session Manager per pane; user values are overridden.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Show")
                            .font(.caption)
                        Toggle("Show", isOn: $option.isAvailable)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .disabled(option.isAppControlled)
                            .onChange(of: option.isAvailable) {
                                if !option.isAvailable {
                                    option.isDefaultEnabled = false
                                }
                                onChange()
                            }
                    }
                    HStack(spacing: 4) {
                        Text("Default on")
                            .font(.caption)
                        Toggle("Default on", isOn: $option.isDefaultEnabled)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .disabled(!option.isAvailable || option.isAppControlled)
                            .onChange(of: option.isDefaultEnabled) { onChange() }
                    }
                }
            }
            if option.isAvailable {
                HStack(spacing: 8) {
                    Text("Default value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Value", text: $option.defaultValue)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .disabled(option.isAppControlled)
                        .onChange(of: option.defaultValue) { onChange() }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct CustomEnvVarOptionRow: View {
    @Binding var option: EnvVarConfig
    let onChange: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(option.id)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Show")
                            .font(.caption)
                        Toggle("Show", isOn: $option.isAvailable)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .disabled(option.isAppControlled)
                            .onChange(of: option.isAvailable) {
                                if !option.isAvailable {
                                    option.isDefaultEnabled = false
                                }
                                onChange()
                            }
                    }
                    HStack(spacing: 4) {
                        Text("Default on")
                            .font(.caption)
                        Toggle("Default on", isOn: $option.isDefaultEnabled)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .disabled(!option.isAvailable || option.isAppControlled)
                            .onChange(of: option.isDefaultEnabled) { onChange() }
                    }
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
            }
            if option.isAvailable {
                HStack(spacing: 8) {
                    Text("Default value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Value", text: $option.defaultValue)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .disabled(option.isAppControlled)
                        .onChange(of: option.defaultValue) { onChange() }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct AddCustomEnvVarSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingIDs: [String]
    let onAdd: (String) -> Void

    @State private var varName = ""

    private var isValid: Bool {
        let trimmed = varName.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !existingIDs.contains(trimmed)
            && trimmed.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Custom Env Var")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Variable Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("MY_CUSTOM_VAR", text: $varName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { if isValid { submit() } }
                if !varName.isEmpty && existingIDs.contains(varName) {
                    Text("An environment variable with this name already exists.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !varName.isEmpty && !isValid {
                    Text(
                        "Variable name must start with a letter or underscore and contain only letters, digits, or underscores."
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func submit() {
        guard isValid else { return }
        onAdd(varName.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}

struct AddCustomFlagSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingIDs: [String]
    let onAdd: (String, Bool) -> Void

    @State private var flagName = ""
    @State private var isString = false

    private var isValid: Bool {
        !flagName.isEmpty && flagName.hasPrefix("--") && !existingIDs.contains(flagName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Custom Flag")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Flag Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("--my-flag", text: $flagName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { if isValid { submit() } }
                if !flagName.isEmpty && !flagName.hasPrefix("--") {
                    Text("Flag name must start with \"--\".")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !flagName.isEmpty && existingIDs.contains(flagName) {
                    Text("A flag with this name already exists.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Flag Type")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Flag Type", selection: $isString) {
                    Text("Boolean").tag(false)
                    Text("Text").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func submit() {
        guard isValid else { return }
        onAdd(flagName, isString)
        dismiss()
    }
}

struct AddCustomStatusLineFieldSheet: View {
    @Environment(\.dismiss) private var dismiss

    var editingField: CustomStatusLineField?
    let onRunNow: ((String) -> String?)?
    let isRunNowAvailable: ((CustomStatusLineField) -> Bool)?
    let onSave: (CustomStatusLineField) -> Void

    @State private var label = ""
    @State private var sfSymbol = "terminal"
    @State private var command = ""
    @State private var refreshIntervalSeconds = CustomStatusLineField.defaultRefreshIntervalSeconds
    @State private var timeoutSeconds = CustomStatusLineField.defaultTimeoutSeconds
    @State private var supportedHarnesses = StatusLineConfig.allHarnesses
    @State private var runNowResult: String?
    @State private var isIconPickerPresented = false
    @State private var isHarnessPickerPresented = false

    private var isValid: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty
            && !command.trimmingCharacters(in: .whitespaces).isEmpty
            && StatusLineConfig.isSFSymbolAvailable(sfSymbol)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingField == nil ? "Add Custom Field" : "Edit Custom Field")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Label").font(.subheadline).foregroundStyle(.secondary)
                TextField("Spend", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("custom-statusline-label-field")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SF Symbol").font(.subheadline).foregroundStyle(.secondary)
                Button {
                    isIconPickerPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: StatusLineConfig.renderedCustomFieldSymbol(
                                scriptOverride: nil,
                                configuredSymbol: sfSymbol
                            )
                        )
                        Text(sfSymbol)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("custom-statusline-icon-picker")
                .accessibilityLabel("SF Symbol")
                .accessibilityValue(sfSymbol)
                .popover(isPresented: $isIconPickerPresented, arrowEdge: .bottom) {
                    CustomStatusLineIconPickerPopover(
                        selectedSymbol: $sfSymbol,
                        isPresented: $isIconPickerPresented
                    )
                }
                if !StatusLineConfig.isSFSymbolAvailable(sfSymbol) {
                    Text("“\(sfSymbol)” is not available on this version of macOS. Select a different SF Symbol.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("custom-statusline-selected-icon-validation")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Harnesses").font(.subheadline).foregroundStyle(.secondary)
                Button {
                    isHarnessPickerPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Text(harnessSelectionSummary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("custom-statusline-harness-menu")
                .accessibilityLabel("Harnesses")
                .accessibilityValue(harnessSelectionSummary)
                .popover(isPresented: $isHarnessPickerPresented, arrowEdge: .bottom) {
                    CustomStatusLineHarnessPickerPopover(
                        selectedHarnesses: $supportedHarnesses,
                        isPresented: $isHarnessPickerPresented
                    )
                }
                Text("Choose one or more harnesses. New fields apply to all harnesses by default.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Command").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $command)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
                    .accessibilityIdentifier("custom-statusline-command-field")
                Text(
                    "Runs via /bin/zsh -i -c in the pane's working directory. Receives the pane's shell "
                        + "environment and status line context as stdin JSON plus AGENT_SESSION_MANAGER_* env vars. "
                        + "Print plain text, "
                        + "or JSON like {\"percent\": 42, \"tint\": \"warning\"} to render a progress bar."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text(
                    "If several fields derive from one expensive/shared source, each field's command still "
                        + "runs independently — collapse that into a shared TTL-gated cache file plus a fast "
                        + "reader script rather than relying on the app to dedupe it for you."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh (seconds)").font(.subheadline).foregroundStyle(.secondary)
                    TextField("", value: $refreshIntervalSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .accessibilityIdentifier("custom-statusline-refresh-field")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Timeout (seconds)").font(.subheadline).foregroundStyle(.secondary)
                    TextField("", value: $timeoutSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .accessibilityIdentifier("custom-statusline-timeout-field")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        guard canRunNow, let fieldID = editingField?.id else { return }
                        runNowResult = onRunNow?(fieldID) ?? "No matching saved panes."
                    } label: {
                        Label("Run Now", systemImage: "play.fill")
                    }
                    .disabled(!canRunNow)
                    .accessibilityIdentifier("custom-statusline-run-now-button")
                    Spacer()
                }
                if let runNowResult {
                    Text(runNowResult)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                }
                if editingField == nil {
                    Text("Save the field before using Run Now.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if !canRunNow {
                    Text("Save changes before using Run Now.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editingField == nil ? "Add" : "Save") {
                    guard isValid else { return }
                    let field = makeField(id: editingField?.id ?? "custom:\(UUID().uuidString)")
                    onSave(field)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .accessibilityIdentifier("custom-statusline-save-button")
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            guard let editingField else { return }
            label = editingField.label
            sfSymbol = editingField.sfSymbol
            command = editingField.command
            refreshIntervalSeconds = editingField.refreshIntervalSeconds
            timeoutSeconds = editingField.timeoutSeconds
            supportedHarnesses = editingField.supportedHarnesses
        }
    }

    private var harnessSelectionSummary: String {
        if supportedHarnesses == StatusLineConfig.allHarnesses {
            return "All harnesses"
        }
        if let harness = Harness.allCases.first(where: { supportedHarnesses == [$0] }) {
            return harness.displayName
        }
        return "\(supportedHarnesses.count) selected"
    }

    private var persistedDraft: CustomStatusLineField? {
        guard let editingField else { return nil }
        return makeField(id: editingField.id)
    }

    private var canRunNow: Bool {
        guard let editingField, onRunNow != nil,
            isRunNowAvailable?(editingField) == true
        else {
            return false
        }
        return persistedDraft == editingField
    }

    private func makeField(id: String) -> CustomStatusLineField {
        CustomStatusLineField(
            id: id,
            label: label.trimmingCharacters(in: .whitespaces),
            sfSymbol: sfSymbol,
            command: command,
            refreshIntervalSeconds: refreshIntervalSeconds,
            timeoutSeconds: timeoutSeconds,
            supportedHarnesses: supportedHarnesses
        )
    }
}

private struct CustomStatusLineHarnessPickerPopover: View {
    @Binding var selectedHarnesses: Set<Harness>
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Harnesses")
                .font(.headline)

            ForEach(Harness.allCases, id: \.self) { harness in
                Toggle(
                    harness.displayName,
                    isOn: Binding(
                        get: { selectedHarnesses.contains(harness) },
                        set: { isSelected in
                            if isSelected {
                                selectedHarnesses.insert(harness)
                            } else if selectedHarnesses.count > 1 {
                                selectedHarnesses.remove(harness)
                            }
                        }
                    )
                )
                .disabled(selectedHarnesses.count == 1 && selectedHarnesses.contains(harness))
                .accessibilityIdentifier("custom-statusline-harness-\(harness.rawValue)")
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .accessibilityIdentifier("custom-statusline-harness-done-button")
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}

private struct CustomStatusLineIconOptionRow: View {
    let option: StatusLineIconOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: option.symbol)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                    Text(option.symbol)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("custom-statusline-icon-option-\(option.symbol)")
        .accessibilityLabel(option.displayName)
    }
}

private struct CustomStatusLineIconPickerPopover: View {
    @Binding var selectedSymbol: String
    @Binding var isPresented: Bool

    @State private var searchText = ""

    private var matchingOptions: [StatusLineIconOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return StatusLineConfig.customFieldIconOptions }
        return StatusLineConfig.customFieldIconOptions.filter { option in
            option.searchTerms.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var exactSymbolName: String? {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
            !StatusLineConfig.customFieldIconOptions.contains(where: { $0.symbol == candidate }),
            StatusLineConfig.isSFSymbolAvailable(candidate)
        else {
            return nil
        }
        return candidate
    }

    private var hasInvalidExactSymbolQuery: Bool {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !candidate.isEmpty && matchingOptions.isEmpty && !StatusLineConfig.isSFSymbolAvailable(candidate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search SF Symbols", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("custom-statusline-icon-search-field")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(StatusLineIconCategory.allCases, id: \.self) { category in
                        let options = matchingOptions.filter { $0.category == category }
                        if !options.isEmpty {
                            Text(category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            ForEach(options) { option in
                                CustomStatusLineIconOptionRow(
                                    option: option,
                                    isSelected: selectedSymbol == option.symbol
                                ) {
                                    selectedSymbol = option.symbol
                                    isPresented = false
                                }
                            }
                        }
                    }
                    if matchingOptions.isEmpty && exactSymbolName == nil {
                        Text("No curated icon matches this search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 280)

            if let exactSymbolName {
                Divider()
                Button {
                    selectedSymbol = exactSymbolName
                    isPresented = false
                } label: {
                    Label(
                        "Use exact symbol name “\(exactSymbolName)”",
                        systemImage: exactSymbolName
                    )
                }
                .accessibilityIdentifier("custom-statusline-use-exact-symbol-button")
                .accessibilityValue(exactSymbolName)
            } else if hasInvalidExactSymbolQuery {
                Text("“\(searchText)” is not an available SF Symbol.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("custom-statusline-icon-validation")
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            searchText = ""
        }
    }
}

struct NotificationsContent: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            Section("macOS") {
                LabeledContent {
                    Toggle("Banner Notifications", isOn: $appSettings.isMacOSBannerNotificationsEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-macos-banner-notifications-toggle")
                        .onChange(of: appSettings.isMacOSBannerNotificationsEnabled) {
                            SettingsPersistence.saveNotificationSettings(appSettings: appSettings)
                        }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Banner Notifications")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Text(
                            "Show a system notification when a background pane rings the bell. "
                                + "Requires permission in System Settings."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(
                            "By default, macOS banners auto-dismiss after a few seconds. "
                                + "To keep them on screen until dismissed:"
                        )
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1. Click Open Notification Settings below.")
                            Text("2. Find Agent Session Manager in the list.")
                            Text("3. Set Alert Style to Persistent.")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Button("Open Notification Settings") {
                            let url = URL(
                                string: "x-apple.systempreferences:com.apple.preference.notifications"
                            )!
                            NSWorkspace.shared.open(url)
                        }
                        .font(.caption).buttonStyle(.link)
                        .accessibilityIdentifier("settings-open-notification-settings-button")
                    }
                }
            }
            Section("Claude") {
                SettingRow(
                    title: "Notify when Claude stops",
                    description: "Show a banner and sidebar row when Claude finishes a turn."
                ) {
                    Toggle(
                        "Notify when Claude stops",
                        isOn: $appSettings.isClaudeStopNotificationEnabled
                    )
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityIdentifier("settings-claude-stop-notification-toggle")
                    .onChange(of: appSettings.isClaudeStopNotificationEnabled) {
                        SettingsPersistence.saveNotificationSettings(appSettings: appSettings)
                    }
                }
            }
            Section("Cursor") {
                SettingRow(
                    title: "Stop hook for attention",
                    description:
                        "Install a Cursor stop hook so the app is notified when the agent finishes "
                        + "a turn (plan ready, task complete, etc.)."
                ) {
                    Toggle(
                        "Stop hook for attention",
                        isOn: $appSettings.isCursorNotificationHookAttentionEnabled
                    )
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityIdentifier("settings-cursor-notification-hook-toggle")
                    .onChange(of: appSettings.isCursorNotificationHookAttentionEnabled) {
                        SettingsPersistence.saveNotificationSettings(appSettings: appSettings)
                        NotificationCenter.default.post(
                            name: .agentSessionManagerCursorNotificationSettingChanged, object: nil)
                    }
                }
            }
            Section("OpenCode") {
                SettingRow(
                    title: "Notify when OpenCode stops",
                    description: "Show a banner and sidebar row when OpenCode finishes a turn."
                ) {
                    Toggle(
                        "Notify when OpenCode stops",
                        isOn: $appSettings.isOpencodeStopNotificationEnabled
                    )
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityIdentifier("settings-opencode-stop-notification-toggle")
                    .onChange(of: appSettings.isOpencodeStopNotificationEnabled) {
                        SettingsPersistence.saveNotificationSettings(appSettings: appSettings)
                    }
                }
            }
            Section("Sidebar") {
                SettingRow(
                    title: "Sidebar Position",
                    description: "Which side the notification sidebar appears on."
                ) {
                    Picker("Sidebar Position", selection: $appSettings.notificationSidebarSide) {
                        ForEach(SidebarSide.allCases, id: \.self) { side in
                            Text(side.displayName).tag(side)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)
                    .accessibilityIdentifier("settings-sidebar-side")
                    .onChange(of: appSettings.notificationSidebarSide) {
                        SettingsPersistence.saveNotificationSettings(appSettings: appSettings)
                    }
                }
                SettingRow(
                    title: "Always Show Notifications Bar",
                    description: "Keep the notifications sidebar visible even when there are no notifications."
                ) {
                    Toggle("Always Show Notifications Bar", isOn: $appSettings.alwaysShowNotificationsSidebar)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-always-show-notifications-bar-toggle")
                        .onChange(of: appSettings.alwaysShowNotificationsSidebar) {
                            SettingsPersistence.saveNotificationSettings(appSettings: appSettings)
                        }
                }
            }
            Section("Priority") {
                SettingRow(
                    title: "Priority Notifications",
                    description:
                        "Allow panes to be marked as priority. Priority notifications appear at the top "
                        + "of the sidebar."
                ) {
                    Toggle("Priority Notifications", isOn: $appSettings.isPriorityNotificationsEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-priority-notifications-toggle")
                        .onChange(of: appSettings.isPriorityNotificationsEnabled) {
                            SettingsPersistence.saveNotificationSettings(appSettings: appSettings)
                        }
                }
            }
            Section("GitHub PR") {
                SettingRow(
                    title: "PR Merged Notifications",
                    description: "Show a sidebar notification and macOS banner when a tracked PR is merged."
                ) {
                    Toggle("PR Merged Notifications", isOn: $appSettings.isPRMergedNotificationsEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-pr-merged-notifications-toggle")
                        .onChange(of: appSettings.isPRMergedNotificationsEnabled) {
                            SettingsPersistence.saveNotificationSettings(appSettings: appSettings)
                        }
                }
                SettingRow(
                    title: "PR Closed Notifications",
                    description:
                        "Show a sidebar notification and macOS banner when a tracked PR is closed without merging."
                ) {
                    Toggle("PR Closed Notifications", isOn: $appSettings.isPRClosedNotificationsEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-pr-closed-notifications-toggle")
                        .onChange(of: appSettings.isPRClosedNotificationsEnabled) {
                            SettingsPersistence.saveNotificationSettings(appSettings: appSettings)
                        }
                }
            }
        }
        .formStyle(.grouped)
        .pinnedFormBackground()
    }
}
