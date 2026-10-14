import AppKit
import SwiftUI

struct NewPaneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var appSettings
    let tab: Tab
    var refreshingPane: Pane?

    @State private var sessionInput = ""
    @State private var selectedHarness: Harness = .claude
    @State private var selectedProfileID: UUID?
    @State private var optionStates: [String: OptionState] = [:]
    @State private var envVarStates: [String: OptionState] = [:]
    @State private var isPriority = false
    @State private var agentControlInjectionEnabled = true
    @State private var scrollbackOverride: ScrollbackLimit?
    @State private var scrollbackLinesText = ""

    @State private var showSaveProfileSheet = false
    @State private var saveProfileName = ""
    @State private var showCLIOptionsSheet = false
    @State private var showAdvancedSettingsSheet = false

    @FocusState private var isSessionInputFocused: Bool

    private var activeToolList: [Harness] {
        Harness.allCases.filter { appSettings.isActive($0) }
    }

    private var activeOptions: [CLIOptionConfig] {
        switch selectedHarness {
        case .claude: return appSettings.cliOptions
        case .codex: return appSettings.codexCliOptions
        case .cursor: return appSettings.cursorCliOptions
        case .opencode: return appSettings.opencodeCliOptions
        case .shell: return []
        }
    }

    private var trimmedInput: String {
        sessionInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isRefreshing: Bool { refreshingPane != nil }

    private var validationError: String? {
        let trimmed = trimmedInput
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") || trimmed.hasPrefix("refs/") {
            return nil
        }
        if !Tab.isValidWorktreeName(trimmed) {
            return
                "Name may only contain letters, digits, dots, underscores, and dashes. For a branch, use a ref such as origin/feature."
        }
        if !isRefreshing
            && appState.tabs.contains(where: {
                $0.directory == tab.directory && $0.panes.contains(where: { $0.name == trimmed })
            })
        {
            return "A pane with this worktree is already open."
        }
        return nil
    }

    private var canSubmit: Bool {
        guard !activeToolList.isEmpty else { return false }
        return !trimmedInput.isEmpty && validationError == nil
    }

    private var worktreePathPreview: String {
        let name = trimmedInput.isEmpty ? "<name>" : trimmedInput
        return "\(tab.directory.lastPathComponent)/\(Tab.worktreesRootRelativePath)/\(name)"
    }

    private var selectedProfile: Profile? {
        guard let id = selectedProfileID else { return nil }
        return appSettings.profiles.first { $0.id == id }
    }

    private var visibleCLIOptions: [CLIOptionConfig] {
        Self.defaultVisibleCLIOptions(catalog: activeOptions, profile: selectedProfile)
    }

    private var visibleEnvVars: [EnvVarConfig] {
        Self.defaultVisibleEnvVars(catalog: currentEnvVarOptions, profile: selectedProfile)
    }

    private var hiddenCLIOptions: [CLIOptionConfig] {
        let visibleIDs = Set(visibleCLIOptions.map(\.id))
        return activeOptions.filter { !visibleIDs.contains($0.id) }
    }

    private var hiddenEnvVarOptions: [EnvVarConfig] {
        let visibleIDs = Set(visibleEnvVars.map(\.id))
        return currentEnvVarOptions.filter { !visibleIDs.contains($0.id) }
    }

    private var currentEnvVarOptions: [EnvVarConfig] {
        switch selectedHarness {
        case .claude: return appSettings.envVarOptions
        case .opencode: return appSettings.opencodeEnvVarOptions
        case .codex, .cursor, .shell: return []
        }
    }

    private var isFormModifiedFromProfile: Bool {
        guard let profile = selectedProfile else { return true }
        if selectedHarness != profile.harness { return true }
        for opt in profile.cliOptions {
            let state = optionStates[opt.id]
            if state?.enabled != opt.isEnabled { return true }
            if let val = opt.value, state?.value != val { return true }
            if opt.value == nil && !(state?.value ?? "").isEmpty { return true }
            let config = activeOptions.first { $0.id == opt.id }
            let expectedValues = opt.seededValues(allowsMultipleValues: config?.allowsMultipleValues ?? false)
            if (state?.values ?? []) != expectedValues { return true }
        }
        for ev in profile.envVars {
            let state = envVarStates[ev.id]
            if state?.enabled != ev.isEnabled { return true }
            if state?.value != ev.value { return true }
        }
        return false
    }

    private var paneCreationSummary: PaneCreationSummary {
        PaneCreationSummary(
            configuredOptionIDs: activeOptions.compactMap { option in
                let state =
                    optionStates[option.id]
                    ?? OptionState(enabled: option.isDefaultEnabled, value: "")
                return state.enabled ? option.id : nil
            },
            configuredEnvironmentVariableIDs: currentEnvVarOptions.compactMap { envVar in
                let state =
                    envVarStates[envVar.id]
                    ?? OptionState(enabled: envVar.isDefaultEnabled, value: envVar.defaultValue)
                return state.enabled ? envVar.id : nil
            },
            additionalOptionCount: hiddenCLIOptions.count,
            additionalEnvironmentVariableCount: hiddenEnvVarOptions.count
        )
    }

    private var advancedSettingsSummary: String {
        let control = appSettings.resolvedAgentControlInjectionDecision(
            persistedDecision: agentControlInjectionEnabled
        )
        let controlText = control ? "Control on" : "Control off"
        let scrollbackText: String
        if let scrollbackOverride {
            scrollbackText = "\(scrollbackOverride.resolvedLines.formatted()) lines"
        } else {
            scrollbackText = "Global scrollback"
        }
        let priorityText =
            appSettings.isPriorityNotificationsEnabled
            ? (isPriority ? "Priority on" : "Priority off")
            : nil
        return [priorityText, controlText, scrollbackText].compactMap { $0 }.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isRefreshing ? "Refresh Pane" : "New Pane")
                .font(.headline)

            if !isRefreshing {
                profilePickerSection
            }

            if selectedProfileID == nil {
                cliPickerSection
            }

            sessionNameSection

            paneOptionsSection
            moreSettingsSection

            actionButtons
        }
        .padding(24)
        .frame(width: 460, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .pinnedSheetBackground()
        .sheet(isPresented: $showSaveProfileSheet) {
            SaveProfileSheet(
                suggestedName: selectedProfile?.name ?? "",
                harness: selectedHarness,
                onSave: { name in
                    var profileOptionStates: [String: ProfileOptionDraft] = [:]
                    for option in activeOptions {
                        let state = optionStates[option.id] ?? OptionState(enabled: false, value: "")
                        let showOnCreate =
                            selectedProfile?.cliOptions.first { $0.id == option.id }?.showOnPaneCreate ?? false
                        profileOptionStates[option.id] = ProfileOptionDraft(
                            enabled: state.enabled,
                            value: state.value,
                            values: state.values,
                            showOnPaneCreate: showOnCreate
                        )
                    }
                    let cliOptions = ProfileSnapshotBuilder.cliOptions(
                        catalog: activeOptions,
                        states: profileOptionStates
                    )

                    let envVars: [ProfileEnvVar]
                    if selectedHarness == .claude || selectedHarness == .opencode {
                        var profileEnvironmentStates: [String: ProfileOptionDraft] = [:]
                        for envVar in currentEnvVarOptions {
                            let state = envVarStates[envVar.id] ?? OptionState(enabled: false, value: "")
                            let showOnCreate =
                                selectedProfile?.envVars.first { $0.id == envVar.id }?.showOnPaneCreate ?? false
                            profileEnvironmentStates[envVar.id] = ProfileOptionDraft(
                                enabled: state.enabled,
                                value: state.value,
                                showOnPaneCreate: showOnCreate
                            )
                        }
                        envVars = ProfileSnapshotBuilder.environmentVariables(
                            catalog: currentEnvVarOptions,
                            states: profileEnvironmentStates
                        )
                    } else {
                        envVars = []
                    }
                    let profile = Profile(
                        name: name, harness: selectedHarness, cliOptions: cliOptions, envVars: envVars,
                        statusLineConfig: nil)
                    appSettings.profiles.append(profile)
                    selectedProfileID = profile.id
                    SettingsPersistence.saveProfiles(appSettings: appSettings)
                    create()
                }
            )
        }
        .sheet(isPresented: $showCLIOptionsSheet) {
            PaneCreationOptionsSheet(
                selectedHarness: selectedHarness,
                visibleCLIOptions: visibleCLIOptions,
                hiddenCLIOptions: hiddenCLIOptions,
                visibleEnvVars: visibleEnvVars,
                hiddenEnvVarOptions: hiddenEnvVarOptions,
                optionStates: $optionStates,
                envVarStates: $envVarStates,
                onAddCLIOptionToGlobal: { option in
                    switch selectedHarness {
                    case .claude:
                        if let index = appSettings.cliOptions.firstIndex(where: { $0.id == option.id }) {
                            appSettings.cliOptions[index].isAvailable = true
                        }
                        SettingsPersistence.save(appSettings: appSettings)
                    case .codex:
                        if let index = appSettings.codexCliOptions.firstIndex(where: { $0.id == option.id }) {
                            appSettings.codexCliOptions[index].isAvailable = true
                        }
                        SettingsPersistence.saveCodexOptions(appSettings: appSettings)
                    case .cursor:
                        if let index = appSettings.cursorCliOptions.firstIndex(where: { $0.id == option.id }) {
                            appSettings.cursorCliOptions[index].isAvailable = true
                        }
                        SettingsPersistence.saveCursorOptions(appSettings: appSettings)
                    case .opencode:
                        if let index = appSettings.opencodeCliOptions.firstIndex(where: { $0.id == option.id }) {
                            appSettings.opencodeCliOptions[index].isAvailable = true
                        }
                        SettingsPersistence.saveOpenCodeOptions(appSettings: appSettings)
                    case .shell:
                        break
                    }
                },
                onAddEnvVarToGlobal: { envVar in
                    switch selectedHarness {
                    case .claude:
                        if let index = appSettings.envVarOptions.firstIndex(where: { $0.id == envVar.id }) {
                            appSettings.envVarOptions[index].isAvailable = true
                        }
                        SettingsPersistence.saveEnvVarOptions(appSettings: appSettings)
                    case .opencode:
                        if let index = appSettings.opencodeEnvVarOptions.firstIndex(where: { $0.id == envVar.id }) {
                            appSettings.opencodeEnvVarOptions[index].isAvailable = true
                        }
                        SettingsPersistence.saveOpenCodeEnvVars(appSettings: appSettings)
                    case .codex, .cursor, .shell:
                        break
                    }
                }
            )
        }
        .sheet(isPresented: $showAdvancedSettingsSheet) {
            PaneAdvancedSettingsSheet(
                isPriority: $isPriority,
                agentControlInjectionEnabled: $agentControlInjectionEnabled,
                scrollbackOverride: $scrollbackOverride,
                scrollbackLinesText: $scrollbackLinesText
            )
        }
        .onAppear {
            if let pane = refreshingPane {
                sessionInput = pane.name
                selectedHarness = pane.harness
                selectedProfileID = pane.profileID
                scrollbackOverride = pane.scrollbackOverride
            }
            if !activeToolList.contains(selectedHarness) {
                selectedHarness = activeToolList.first ?? .claude
            }
            agentControlInjectionEnabled =
                appSettings.resolvedAgentControlInjectionDecision(
                    persistedDecision: refreshingPane?.agentControlInjectionEnabled)
            if !isRefreshing && selectedProfileID == nil {
                let filtered = appSettings.profiles.filter { activeToolList.contains($0.harness) }
                selectedProfileID = filtered.first?.id
            }
            applyProfileOrDefaults()
            if !isRefreshing {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    isSessionInputFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private var profilePickerSection: some View {
        let profiles = appSettings.profiles.filter { activeToolList.contains($0.harness) }
        if !profiles.isEmpty || selectedProfileID != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Profile")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Profile", selection: $selectedProfileID) {
                    Text("Custom").tag(nil as UUID?)
                    ForEach(profiles) { profile in
                        HStack {
                            Text(profile.name)
                            Text("(\(profile.harness.displayName))")
                                .foregroundStyle(.secondary)
                        }
                        .tag(profile.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180, alignment: .leading)
                .labelsHidden()
                .accessibilityIdentifier("new-pane-profile-picker")
                .onChange(of: selectedProfileID) { _, _ in
                    applyProfileOrDefaults()
                    isSessionInputFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private var cliPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Harness")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if activeToolList.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    (Text("No tools are active. Enable a tool in ")
                        .foregroundStyle(.secondary)
                        + Text("Settings \u{2192} Tools")
                        .foregroundColor(Theme.accent))
                }
                .font(.subheadline)
            } else {
                Picker("Harness", selection: $selectedHarness) {
                    ForEach(activeToolList, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("new-pane-cli-picker")
                .onChange(of: selectedHarness) { _, _ in
                    initializeOptionStatesFromGlobal()
                    isSessionInputFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private var sessionNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session, branch, or worktree")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("auth-refactor, origin/feature, my-worktree, …", text: $sessionInput)
                .textFieldStyle(.roundedBorder)
                .focused($isSessionInputFocused)
                .onSubmit { create() }
                .accessibilityIdentifier("new-pane-name-field")
                .disabled(isRefreshing)
            VStack(alignment: .leading, spacing: 4) {
                Text("Session name, branch ref, or worktree.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(worktreePathPreview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if let validation = validationError {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("new-pane-name-error")
                }
            }
        }
    }

    @ViewBuilder
    private var paneOptionsSection: some View {
        if !activeOptions.isEmpty || !currentEnvVarOptions.isEmpty {
            let summary = paneCreationSummary
            VStack(alignment: .leading, spacing: 8) {
                Text("CLI Options")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showCLIOptionsSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(summary.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.1))
                )
                .accessibilityIdentifier("new-pane-cli-options-button")
            }
        }
    }

    private var moreSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pane Settings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showAdvancedSettingsSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("More Settings")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text(advancedSettingsSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
            .accessibilityIdentifier("new-pane-more-settings-button")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("new-pane-cancel-button")
            if !isRefreshing {
                Button("Save Profile & Create") {
                    saveProfileName = selectedProfile?.name ?? ""
                    showSaveProfileSheet = true
                }
                .disabled(!canSubmit || (selectedProfile != nil && !isFormModifiedFromProfile))
                .accessibilityIdentifier("new-pane-save-profile-button")
            }
            Button(isRefreshing ? "Refresh" : "Create Pane") { create() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .accessibilityIdentifier("new-pane-open-button")
        }
    }

    private func applyProfileOrDefaults() {
        if let profile = selectedProfile {
            selectedHarness = profile.harness
            optionStates = [:]
            for opt in profile.cliOptions {
                let config = activeOptions.first { $0.id == opt.id }
                let draft = opt.draft(using: config)
                optionStates[opt.id] = OptionState(
                    enabled: draft.enabled,
                    value: draft.value,
                    values: draft.values
                )
            }
            envVarStates = [:]
            for envVar in profile.envVars {
                let draft = envVar.draft()
                envVarStates[envVar.id] = OptionState(enabled: draft.enabled, value: draft.value)
            }
        } else {
            initializeOptionStatesFromGlobal()
        }
    }

    private func initializeOptionStatesFromGlobal() {
        optionStates = [:]
        for option in activeOptions where option.isAvailable {
            let enabled = option.isDefaultEnabled || (isRefreshing && option.id == "--continue")
            optionStates[option.id] = OptionState(enabled: enabled, value: "")
        }
        envVarStates = [:]
        if selectedHarness == .claude || selectedHarness == .opencode {
            for envVar in currentEnvVarOptions where envVar.isAvailable {
                let value = envVar.isDefaultEnabled ? envVar.defaultValue : ""
                envVarStates[envVar.id] = OptionState(enabled: envVar.isDefaultEnabled, value: value)
            }
        }
    }

    private func create() {
        guard canSubmit else { return }
        let trimmed = trimmedInput
        guard !trimmed.isEmpty, validationError == nil else { return }
        let extraArgs = buildExtraArgs()
        let extraEnvVars = buildExtraEnvVars()
        let committedScrollbackOverride: ScrollbackLimit?
        if case .finite? = scrollbackOverride, let lines = Int(scrollbackLinesText) {
            committedScrollbackOverride = ScrollbackLimit(finiteLines: lines)
        } else {
            committedScrollbackOverride = scrollbackOverride
        }

        if let pane = refreshingPane {
            pane.agentControlInjectionEnabled = appSettings.resolvedAgentControlInjectionDecision(
                persistedDecision: agentControlInjectionEnabled)
            pane.scrollbackOverride = committedScrollbackOverride
            tab.refreshPane(
                pane, extraArgs: extraArgs, harness: selectedHarness, extraEnvVars: extraEnvVars,
                appSettings: appSettings)
            pane.profileID = selectedProfileID
            SessionPersistence.save(appState: appState)
            resetForm()
            dismiss()
            return
        }

        tab.setFocusedPane(id: nil, reason: "pane_created")
        let pane = tab.addPaneWithLoadingState(
            name: trimmed,
            harness: selectedHarness,
            worktreeIsManaged: true,
            profileID: selectedProfileID,
            scrollbackOverride: committedScrollbackOverride,
            agentControlInjectionEnabled: appSettings.resolvedAgentControlInjectionDecision(
                persistedDecision: agentControlInjectionEnabled),
            appSettings: appSettings
        )
        pane.bindNotifications(appState: appState, isPriority: isPriority)
        appState.setActivePane(id: pane.id)
        SessionPersistence.save(appState: appState)
        resetForm()
        dismiss()

        let defaultBranch: String?
        let branchSource: String
        if let override = tab.baseBranchOverride, !override.isEmpty {
            defaultBranch = override
            branchSource = "tab-override"
        } else if appSettings.isDefaultBranchEnabled {
            defaultBranch = appSettings.defaultBranch
            branchSource = "global-default"
        } else {
            defaultBranch = nil
            branchSource = "none"
        }
        let worktreeBaseRef = appSettings.worktreeBaseRef
        let existingWorktreeManagement = appSettings.existingWorktreeManagement
        let autoSetSessionName = appSettings.autoSetSessionName
        let tabName = tab.name
        let harness = selectedHarness
        let statusLineOverride = selectedProfile?.statusLineConfig
        let paneID = pane.id
        let paneName = trimmed
        let tabID = tab.id
        let resolvedDefaultBranch = defaultBranch

        Task<Void, Never> { @MainActor in
            TracingService.shared.record(
                "tab.worktree.base_branch_resolved",
                attributes: [
                    "pane.id": paneID.uuidString,
                    "pane.name": paneName,
                    "tab.id": tabID.uuidString,
                    "tab.name": tabName,
                    "base.branch": resolvedDefaultBranch ?? "",
                    "base.branch.source": branchSource,
                ]
            )
            if harness == .opencode {
                let shell = ShellResolver.resolved(appSettings)
                let installed = await HarnessDetector.isInstalled(harness: .opencode, shell: shell)
                if !installed {
                    await MainActor.run {
                        pane.setupState = .failed(
                            error:
                                "OpenCode binary not found in PATH. Install OpenCode or check your shell configuration."
                        )
                    }
                    return
                }
            }
            do {
                let resolved = try await tab.resolveOrAttachWorktree(
                    userRef: trimmed,
                    defaultBranch: defaultBranch,
                    baseRef: worktreeBaseRef
                )
                let inUse = await MainActor.run {
                    appState.isCheckoutInUse(
                        checkout: resolved.checkoutURL,
                        excludingPaneIDs: [pane.id])
                }
                if inUse {
                    await MainActor.run {
                        pane.setupState = .failed(error: "A pane with this worktree is already open.")
                    }
                    return
                }
                guard let managed = await resolveManaged(for: resolved, policy: existingWorktreeManagement, pane: pane)
                else { return }
                let effectiveExtraArgs = Tab.applyAutoSessionName(
                    tabName: tabName, paneName: resolved.paneTitle,
                    extraArgs: extraArgs, harness: harness, enabled: autoSetSessionName
                )
                await MainActor.run {
                    tab.completeSetup(
                        for: pane, resolved: resolved, managed: managed,
                        effectiveExtraArgs: effectiveExtraArgs, extraEnvVars: extraEnvVars,
                        statusLineConfigOverride: statusLineOverride, appSettings: appSettings
                    )
                    SessionPersistence.save(appState: appState)
                }
            } catch {
                await MainActor.run { pane.setupState = .failed(error: setupErrorMessage(from: error)) }
            }
        }
    }

    private func resetForm() {
        sessionInput = ""
    }
}

extension NewPaneSheet {
    static func defaultVisibleCLIOptions(
        catalog: [CLIOptionConfig],
        profile: Profile?
    ) -> [CLIOptionConfig] {
        guard let profile else { return catalog.filter(\.isAvailable) }
        let visibleIDs = Set(
            profile.cliOptions
                .filter { $0.isEnabled || $0.showOnPaneCreate }
                .map(\.id)
        )
        return catalog.filter { visibleIDs.contains($0.id) }
    }

    static func defaultVisibleEnvVars(
        catalog: [EnvVarConfig],
        profile: Profile?
    ) -> [EnvVarConfig] {
        guard let profile else { return catalog.filter(\.isAvailable) }
        let visibleIDs = Set(
            profile.envVars
                .filter { $0.isEnabled || $0.showOnPaneCreate }
                .map(\.id)
        )
        return catalog.filter { visibleIDs.contains($0.id) }
    }

    static func buildExtraArgs(options: [CLIOptionConfig], states: [String: OptionState]) -> [String] {
        var args: [String] = []
        for option in options {
            guard let state = states[option.id], state.enabled else { continue }
            args.append(contentsOf: option.commandLineArguments(value: state.value, values: state.values))
        }
        return args
    }

    fileprivate func buildExtraArgs() -> [String] {
        var args = Self.buildExtraArgs(options: activeOptions, states: optionStates)
        if isRefreshing, selectedHarness == .opencode, let id = refreshingPane?.opencodeSessionID,
            !args.contains("--session")
        {
            args.append(contentsOf: ["--session", id])
        }
        return args
    }

    fileprivate func buildExtraEnvVars() -> [String: String] {
        guard selectedHarness == .claude || selectedHarness == .opencode else { return [:] }
        var envVars: [String: String] = [:]
        for envVar in currentEnvVarOptions {
            guard let state = envVarStates[envVar.id], state.enabled else { continue }
            let value = state.value.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { envVars[envVar.id] = value }
        }
        return envVars
    }

    fileprivate func resolveManaged(
        for resolved: ResolvedWorktree,
        policy: ExistingWorktreeManagement,
        pane: Pane
    ) async -> Bool? {
        guard resolved.isExternalTakeover else { return true }
        switch policy {
        case .always: return true
        case .never: return false
        case .ask:
            let response = await MainActor.run { () -> NSApplication.ModalResponse in
                let alert = NSAlert()
                alert.messageText = "Manage existing worktree?"
                alert.informativeText =
                    "A checkout for this repo already exists:\n\(resolved.processDirectory.path)\n\nTake over management so the worktree can be cleaned up later?"
                alert.addButton(withTitle: "Manage")
                alert.addButton(withTitle: "Don't Manage")
                alert.addButton(withTitle: "Cancel")
                return alert.runModal()
            }
            switch response {
            case .alertFirstButtonReturn: return true
            case .alertSecondButtonReturn: return false
            default:
                await MainActor.run { pane.setupState = .failed(error: "Cancelled.") }
                return nil
            }
        }
    }

    fileprivate func setupErrorMessage(from error: Error) -> String {
        if let worktreeError = error as? WorktreeResolutionError {
            return worktreeError.localizedDescription
        } else if let gitError = error as? GitCommandError {
            return gitError.localizedDescription
        } else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct SaveProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let suggestedName: String
    let harness: Harness
    let onSave: (String) -> Void

    @State private var profileName = ""
    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Save Profile")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Profile Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Complex Task, Quick Side Quest, …", text: $profileName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit { if isValid { submit() } }
                Text("Harness: \(harness.displayName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save & Create") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 320)
        .pinnedSheetBackground()
        .onAppear {
            profileName = suggestedName
            isFocused = true
        }
    }

    private func submit() {
        guard isValid else { return }
        onSave(profileName.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
