import SwiftUI

enum ProfileEditorMode: Identifiable {
    case new
    case edit(Profile)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let profile): return profile.id.uuidString
        }
    }

    var profile: Profile? {
        switch self {
        case .new: return nil
        case .edit(let profile): return profile
        }
    }
}

struct ProfilesContent: View {
    @Environment(AppSettings.self) private var appSettings
    @State private var editorMode: ProfileEditorMode?

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            if appSettings.profiles.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 36))
                            .foregroundStyle(.quaternary)
                        Text("No profiles yet")
                            .foregroundStyle(.secondary)
                        Text("Create a profile to save your preferred CLI configuration for quick reuse.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                Section("Profiles") {
                    ForEach(Array(appSettings.profiles.enumerated()), id: \.element.id) { index, profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(profile.name)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.medium)
                                    Text(profile.harness.displayName)
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 8)
                                        .background(.quaternary)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .foregroundStyle(.secondary)
                                    if profile.statusLineConfig != nil {
                                        Text("Custom status line")
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 8)
                                            .background(.quaternary)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                let flagCount = profile.cliOptions.filter(\.isEnabled).count
                                let envCount = profile.envVars.filter(\.isEnabled).count
                                let flagSummary = flagCount > 0 ? "\(flagCount) flag\(flagCount == 1 ? "" : "s")" : nil
                                let envSummary = envCount > 0 ? "\(envCount) env var\(envCount == 1 ? "" : "s")" : nil
                                Text([flagSummary, envSummary].compactMap { $0 }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                appSettings.profiles.swapAt(index, index - 1)
                                SettingsPersistence.saveProfiles(appSettings: appSettings)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(index == 0 ? .tertiary : .secondary)
                            .disabled(index == 0)
                            .accessibilityIdentifier("profile-move-up-\(profile.id)")

                            Button {
                                appSettings.profiles.swapAt(index, index + 1)
                                SettingsPersistence.saveProfiles(appSettings: appSettings)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(index == appSettings.profiles.count - 1 ? .tertiary : .secondary)
                            .disabled(index == appSettings.profiles.count - 1)
                            .accessibilityIdentifier("profile-move-down-\(profile.id)")

                            Menu {
                                Button("Edit") {
                                    editorMode = .edit(profile)
                                }
                                Button("Duplicate") {
                                    var copy = profile
                                    copy.id = UUID()
                                    copy.name = "\(profile.name) Copy"
                                    appSettings.profiles.append(copy)
                                    SettingsPersistence.saveProfiles(appSettings: appSettings)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    appSettings.profiles.removeAll { $0.id == profile.id }
                                    SettingsPersistence.saveProfiles(appSettings: appSettings)
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 24)
                        }
                    }
                }
            }
            Section {
                Button {
                    editorMode = .new
                } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("profile-new-button")
            }
        }
        .formStyle(.grouped)
        .pinnedFormBackground()
        .sheet(item: $editorMode) { mode in
            ProfileEditorSheet(
                profile: mode.profile,
                appSettings: appSettings,
                onSave: { saved in
                    if let index = appSettings.profiles.firstIndex(where: { $0.id == saved.id }) {
                        appSettings.profiles[index] = saved
                    } else {
                        appSettings.profiles.append(saved)
                    }
                    SettingsPersistence.saveProfiles(appSettings: appSettings)
                }
            )
        }
    }
}

private struct ProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    let profile: Profile?
    let appSettings: AppSettings
    let onSave: (Profile) -> Void

    @State private var name: String = ""
    @State private var harness: Harness = .claude
    @State private var optionStates: [String: ProfileOptionDraft] = [:]
    @State private var envVarStates: [String: ProfileOptionDraft] = [:]
    @State private var useCustomStatusLine = false
    @State private var statusLineConfig = StatusLineConfig()
    @State private var didSeedCustomStatusLineFromGlobal = false
    @State private var showHiddenOptions = false
    @State private var showHiddenEnvVars = false

    @FocusState private var isNameFocused: Bool

    init(profile: Profile?, appSettings: AppSettings, onSave: @escaping (Profile) -> Void) {
        self.profile = profile
        self.appSettings = appSettings
        self.onSave = onSave
        _harness = State(initialValue: profile?.harness ?? .claude)
    }

    private var activeToolList: [Harness] {
        Harness.allCases.filter { appSettings.isActive($0) }
    }

    private var activeOptions: [CLIOptionConfig] {
        switch harness {
        case .claude: return appSettings.cliOptions
        case .codex: return appSettings.codexCliOptions
        case .cursor: return appSettings.cursorCliOptions
        case .opencode: return appSettings.opencodeCliOptions
        case .shell: return []
        }
    }

    private var hiddenOptions: [CLIOptionConfig] {
        activeOptions.filter { !$0.isAvailable }
    }

    private var hiddenEnvVars: [EnvVarConfig] {
        currentEnvVarOptions.filter { !$0.isAvailable }
    }

    private var currentEnvVarOptions: [EnvVarConfig] {
        switch harness {
        case .claude: return appSettings.envVarOptions
        case .opencode: return appSettings.opencodeEnvVarOptions
        case .codex, .cursor, .shell: return []
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(profile == nil ? "New Profile" : "Edit Profile")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile Name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Complex Task, Quick Side Quest, …", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($isNameFocused)
                            .accessibilityIdentifier("profile-editor-name-field")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Harness")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Harness", selection: $harness) {
                            ForEach(activeToolList, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: harness) { _, _ in
                            initializeFromGlobal()
                        }
                    }

                    let available = activeOptions.filter(\.isAvailable)
                    if !available.isEmpty || !hiddenOptions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CLI Options")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(
                                "Checked options appear in the New Pane sheet so you can adjust them each time you start a pane."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if !available.isEmpty {
                                HStack(spacing: 8) {
                                    Spacer()
                                    Color.clear.frame(maxWidth: .infinity)
                                    Text("Show on new pane")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .help(
                                            "Options marked here appear in the New Pane sheet each time you create a pane with this profile."
                                        )
                                }
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(available) { option in
                                            ProfileEditorOptionRow(
                                                option: option,
                                                state: editorStateBinding(for: option.id)
                                            )
                                        }
                                    }
                                }
                                .frame(maxHeight: 160)
                            }
                            if !hiddenOptions.isEmpty {
                                Button {
                                    showHiddenOptions.toggle()
                                } label: {
                                    Text(showHiddenOptions ? "Fewer options" : "Show all options")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("profile-editor-show-hidden-options-button")

                                if showHiddenOptions {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(hiddenOptions) { option in
                                                ProfileEditorHiddenOptionRow(
                                                    option: option,
                                                    state: editorStateBinding(for: option.id),
                                                    onAddToGlobal: {
                                                        switch harness {
                                                        case .claude:
                                                            if let i = appSettings.cliOptions.firstIndex(where: {
                                                                $0.id == option.id
                                                            }) {
                                                                appSettings.cliOptions[i].isAvailable = true
                                                            }
                                                            SettingsPersistence.save(appSettings: appSettings)
                                                        case .codex:
                                                            if let i = appSettings.codexCliOptions.firstIndex(where: {
                                                                $0.id == option.id
                                                            }) {
                                                                appSettings.codexCliOptions[i].isAvailable = true
                                                            }
                                                            SettingsPersistence.saveCodexOptions(
                                                                appSettings: appSettings)
                                                        case .cursor:
                                                            if let i = appSettings.cursorCliOptions.firstIndex(where: {
                                                                $0.id == option.id
                                                            }) {
                                                                appSettings.cursorCliOptions[i].isAvailable = true
                                                            }
                                                            SettingsPersistence.saveCursorOptions(
                                                                appSettings: appSettings)
                                                        case .opencode:
                                                            if let i = appSettings.opencodeCliOptions.firstIndex(
                                                                where: {
                                                                    $0.id == option.id
                                                                })
                                                            {
                                                                appSettings.opencodeCliOptions[i].isAvailable = true
                                                            }
                                                            SettingsPersistence.saveOpenCodeOptions(
                                                                appSettings: appSettings)
                                                        case .shell:
                                                            break
                                                        }
                                                    }
                                                )
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 160)
                                    .accessibilityIdentifier("profile-editor-hidden-options-scroll-view")
                                }
                            }
                        }
                    }

                    if harness == .claude || harness == .opencode {
                        let availableEnvVars = currentEnvVarOptions.filter(\.isAvailable)
                        if !availableEnvVars.isEmpty || !hiddenEnvVars.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Environment Variables")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(
                                    "Checked options appear in the New Pane sheet so you can adjust them each time you start a pane."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if !availableEnvVars.isEmpty {
                                    HStack(spacing: 8) {
                                        Spacer()
                                        Color.clear.frame(maxWidth: .infinity)
                                        Text("Show on new pane")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .help(
                                                "Options marked here appear in the New Pane sheet each time you create a pane with this profile."
                                            )
                                    }
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(availableEnvVars) { envVar in
                                                ProfileEditorEnvVarRow(
                                                    envVar: envVar,
                                                    state: editorEnvVarStateBinding(for: envVar.id)
                                                )
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 120)
                                }
                                if !hiddenEnvVars.isEmpty {
                                    Button {
                                        showHiddenEnvVars.toggle()
                                    } label: {
                                        Text(showHiddenEnvVars ? "Fewer options" : "Show all options")
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("profile-editor-show-hidden-env-vars-button")

                                    if showHiddenEnvVars {
                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 6) {
                                                ForEach(hiddenEnvVars) { envVar in
                                                    ProfileEditorHiddenEnvVarRow(
                                                        envVar: envVar,
                                                        state: editorEnvVarStateBinding(for: envVar.id),
                                                        onAddToGlobal: {
                                                            switch harness {
                                                            case .claude:
                                                                if let i = appSettings.envVarOptions.firstIndex(where: {
                                                                    $0.id == envVar.id
                                                                }) {
                                                                    appSettings.envVarOptions[i].isAvailable = true
                                                                }
                                                                SettingsPersistence.saveEnvVarOptions(
                                                                    appSettings: appSettings)
                                                            case .opencode:
                                                                if let i = appSettings.opencodeEnvVarOptions.firstIndex(
                                                                    where: {
                                                                        $0.id == envVar.id
                                                                    })
                                                                {
                                                                    appSettings.opencodeEnvVarOptions[i].isAvailable =
                                                                        true
                                                                }
                                                                SettingsPersistence.saveOpenCodeEnvVars(
                                                                    appSettings: appSettings)
                                                            case .codex, .cursor, .shell:
                                                                break
                                                            }
                                                        }
                                                    )
                                                }
                                            }
                                        }
                                        .frame(maxHeight: 120)
                                        .accessibilityIdentifier("profile-editor-hidden-env-vars-scroll-view")
                                    }
                                }
                            }
                        }
                    }

                    Toggle(isOn: $useCustomStatusLine) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Custom Status Line")
                                .font(.subheadline)
                            Text("Override the global status line for panes using this profile.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .onChange(of: useCustomStatusLine) { _, isOn in
                        guard isOn else { return }
                        if !didSeedCustomStatusLineFromGlobal {
                            statusLineConfig = appSettings.statusLineConfig
                            didSeedCustomStatusLineFromGlobal = true
                        }
                    }

                    if useCustomStatusLine {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                "Customize facts and rows for panes created with this profile. GitHub PR tracking still follows Settings → Status Line → GitHub PR Tracking."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Form {
                                StatusLineConfigLayoutEditor(
                                    config: $statusLineConfig,
                                    filterCLI: harness,
                                    phases: .full,
                                    onPersist: {},
                                    onRunNow: profile.map { profile in
                                        { fieldID in
                                            appState.runSavedStatusLineFieldNow(
                                                fieldID: fieldID,
                                                profileID: profile.id,
                                                appSettings: appSettings)
                                        }
                                    },
                                    isRunNowAvailable: profile.map { profile in
                                        { field in
                                            profile.statusLineConfig?.customField(withID: field.id) == field
                                        }
                                    }
                                )
                            }
                            .formStyle(.grouped)
                            .pinnedFormBackground()
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(24)
        }
        .frame(minWidth: 620, idealWidth: 620, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(Theme.windowBackground)
        .pinnedSheetBackground()
        .onAppear {
            if let existing = profile {
                name = existing.name
                for opt in existing.cliOptions {
                    let config = activeOptions.first { $0.id == opt.id }
                    optionStates[opt.id] = opt.draft(using: config)
                }
                for ev in existing.envVars {
                    envVarStates[ev.id] = ev.draft()
                }
                if let slc = existing.statusLineConfig {
                    useCustomStatusLine = true
                    statusLineConfig = slc
                }
                let availableIDs = Set(activeOptions.filter(\.isAvailable).map(\.id))
                if existing.cliOptions.contains(where: { $0.isEnabled && !availableIDs.contains($0.id) }) {
                    showHiddenOptions = true
                }
                let availableEnvIDs = Set(currentEnvVarOptions.filter(\.isAvailable).map(\.id))
                if existing.envVars.contains(where: { $0.isEnabled && !availableEnvIDs.contains($0.id) }) {
                    showHiddenEnvVars = true
                }
            } else {
                if !activeToolList.contains(harness) {
                    harness = activeToolList.first ?? .claude
                }
                initializeFromGlobal()
            }
            didSeedCustomStatusLineFromGlobal = profile?.statusLineConfig != nil
            isNameFocused = true
        }
    }

    private func initializeFromGlobal() {
        optionStates = [:]
        for option in activeOptions where option.isAvailable {
            optionStates[option.id] = ProfileOptionDraft(
                enabled: option.isDefaultEnabled, value: "")
        }
        envVarStates = [:]
        if harness == .claude || harness == .opencode {
            for envVar in currentEnvVarOptions where envVar.isAvailable {
                envVarStates[envVar.id] = ProfileOptionDraft(
                    enabled: envVar.isDefaultEnabled, value: envVar.defaultValue)
            }
        }
    }

    private func editorStateBinding(for id: String) -> Binding<ProfileOptionDraft> {
        Binding(
            get: { optionStates[id] ?? ProfileOptionDraft(enabled: false, value: "") },
            set: { optionStates[id] = $0 }
        )
    }

    private func editorEnvVarStateBinding(for id: String) -> Binding<ProfileOptionDraft> {
        Binding(
            get: { envVarStates[id] ?? ProfileOptionDraft(enabled: false, value: "") },
            set: { envVarStates[id] = $0 }
        )
    }

    private func save() {
        guard isValid else { return }
        let cliOptions = ProfileSnapshotBuilder.cliOptions(catalog: activeOptions, states: optionStates)
        let envVars =
            harness == .claude || harness == .opencode
            ? ProfileSnapshotBuilder.environmentVariables(
                catalog: currentEnvVarOptions,
                states: envVarStates
            )
            : []

        let saved = Profile(
            id: profile?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            harness: harness,
            cliOptions: cliOptions,
            envVars: envVars,
            statusLineConfig: useCustomStatusLine ? statusLineConfig : nil
        )
        onSave(saved)
        dismiss()
    }
}

private struct ProfileEditorOptionRow: View {
    let option: CLIOptionConfig
    @Binding var state: ProfileOptionDraft

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(isOn: $state.enabled) {
                Text(option.id)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CLIOptionValueField(option: option, value: $state.value, values: $state.values, enabled: state.enabled)
                .frame(maxWidth: .infinity)
            Toggle("Show on new pane", isOn: $state.showOnPaneCreate)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(
                    "Options marked here appear in the New Pane sheet each time you create a pane with this profile."
                )
                .accessibilityIdentifier("profile-editor-show-on-pane-\(option.id)")
        }
    }
}

private struct ProfileEditorEnvVarRow: View {
    let envVar: EnvVarConfig
    @Binding var state: ProfileOptionDraft

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(isOn: $state.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(envVar.id)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    if envVar.isAppControlled {
                        Text("Controlled by Agent Session Manager")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(envVar.isAppControlled)
            TextField("Value", text: $state.value)
                .textFieldStyle(.roundedBorder)
                .disabled(!state.enabled || envVar.isAppControlled)
                .frame(maxWidth: .infinity)
            Toggle("Show on new pane", isOn: $state.showOnPaneCreate)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(envVar.isAppControlled)
                .help(
                    "Options marked here appear in the New Pane sheet each time you create a pane with this profile."
                )
        }
    }
}

private struct ProfileEditorHiddenOptionRow: View {
    let option: CLIOptionConfig
    @Binding var state: ProfileOptionDraft
    let onAddToGlobal: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(isOn: $state.enabled) {
                Text(option.id)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CLIOptionValueField(option: option, value: $state.value, values: $state.values, enabled: state.enabled)
                .frame(maxWidth: .infinity)
            if state.enabled {
                Button("Show in all profiles", action: onAddToGlobal)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

private struct ProfileEditorHiddenEnvVarRow: View {
    let envVar: EnvVarConfig
    @Binding var state: ProfileOptionDraft
    let onAddToGlobal: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(isOn: $state.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(envVar.id)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    if envVar.isAppControlled {
                        Text("Controlled by Agent Session Manager")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(envVar.isAppControlled)
            TextField("Value", text: $state.value)
                .textFieldStyle(.roundedBorder)
                .disabled(!state.enabled || envVar.isAppControlled)
                .frame(maxWidth: .infinity)
            if state.enabled && !envVar.isAppControlled {
                Button("Show in all profiles", action: onAddToGlobal)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
