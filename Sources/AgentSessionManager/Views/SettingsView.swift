import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case panes
    case profiles
    case tools
    case shortcuts
    case statusLine = "status-line"
    case notifications
    case debug
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .panes: "Panes"
        case .profiles: "Profiles"
        case .tools: "Harnesses"
        case .shortcuts: "Shortcuts"
        case .statusLine: "Status Line"
        case .notifications: "Notifications"
        case .debug: "Debug"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .panes: "square.split.2x1"
        case .profiles: "person.crop.rectangle.stack"
        case .tools: "wrench.and.screwdriver"
        case .shortcuts: "keyboard"
        case .statusLine: "chart.bar"
        case .notifications: "bell"
        case .debug: "ladybug"
        case .about: "info.circle"
        }
    }
}

enum SettingsSidebarMetrics {
    static let contentWidth: CGFloat = 200
    static let outerPadding: CGFloat = 12
    static let innerPadding: CGFloat = 8
    static let rowSpacing: CGFloat = 4
    static let rowHeight: CGFloat = 44
    static let rowCornerRadius: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 14
}

enum SettingsSidebarTheme {
    static let gutterBackground = Theme.mac26Content
    static let panelBackground = Theme.mac26WindowChrome
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var appSettings
    @State private var selection: SettingsSection = .panes
    @State private var updateCheckCoordinator = UpdateCheckCoordinator.shared

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: SettingsSidebarMetrics.rowSpacing) {
                    ForEach(SettingsSection.allCases) { section in
                        SettingsSidebarRow(
                            section: section,
                            isSelected: selection == section,
                            showBadge: section == .about && updateCheckCoordinator.updateAvailable,
                            onSelect: { selection = section }
                        )
                    }
                }
                .padding(SettingsSidebarMetrics.innerPadding)
            }
            .frame(width: SettingsSidebarMetrics.contentWidth)
            .padding(SettingsSidebarMetrics.outerPadding)
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                ZStack {
                    SettingsSidebarTheme.gutterBackground
                    RoundedRectangle(cornerRadius: SettingsSidebarMetrics.rowCornerRadius)
                        .fill(SettingsSidebarTheme.panelBackground)
                        .padding(SettingsSidebarMetrics.outerPadding)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsSidebarMetrics.rowCornerRadius)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    .padding(SettingsSidebarMetrics.outerPadding)
            }
            .accessibilityIdentifier("settings-sidebar-container")

            ZStack(alignment: .topLeading) {
                switch selection {
                case .panes:
                    PanesContent()
                        .environment(appSettings)
                case .profiles:
                    ProfilesContent()
                        .environment(appSettings)
                case .tools:
                    ToolsContent()
                        .environment(appSettings)
                case .shortcuts:
                    KeyboardShortcutsContent()
                case .statusLine:
                    StatusLineContent()
                        .environment(appSettings)
                case .notifications:
                    NotificationsContent()
                        .environment(appSettings)
                case .debug:
                    DebugView()
                        .environment(appSettings)
                case .about:
                    AboutContent()
                        .environment(appSettings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.mac26Content)
        .frame(minWidth: 900, idealWidth: 900, minHeight: 552, idealHeight: 552)
        .pinnedWindowChrome(Theme.settingsWindowChrome)
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsSection)) { notif in
            guard
                let raw = notif.userInfo?["section"] as? String,
                let section = SettingsSection(rawValue: raw)
            else { return }
            selection = section
        }
    }
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    var showBadge: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 22)
                Text(section.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if showBadge {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .accessibilityIdentifier("settings-sidebar-about-badge")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, SettingsSidebarMetrics.rowHorizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: SettingsSidebarMetrics.rowHeight,
                maxHeight: SettingsSidebarMetrics.rowHeight,
                alignment: .leading
            )
            .background(
                RoundedRectangle(cornerRadius: SettingsSidebarMetrics.rowCornerRadius)
                    .fill(isSelected ? Theme.mac26SelectedBlue : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("settings-sidebar-\(section.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DefaultValueLabel: View {
    let value: String

    var body: some View {
        Text("Default: \(value)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    let description: String
    var defaultValue: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        LabeledContent {
            control()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let defaultValue {
                    DefaultValueLabel(value: defaultValue)
                }
            }
        }
        .pinnedListRowBackground()
    }
}

private struct PanesContent: View {
    @Environment(AppSettings.self) private var appSettings
    @State private var shellPickerSelection: String = ""
    @State private var pendingDefaultScrollback: ScrollbackLimit?
    @State private var showsScrollbackReductionWarning = false
    @State private var scrollbackLinesText = ""

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            Section("Layout") {
                SettingRow(
                    title: "Tab Bar Height",
                    description: "Preferred height of the tab bar.",
                    defaultValue: "44 points"
                ) {
                    Stepper(
                        "\(Int(appSettings.layoutSettings.tabBarHeight)) points",
                        value: $appSettings.layoutSettings.tabBarHeight,
                        in: 44...96,
                        step: 4
                    )
                    .accessibilityIdentifier("settings-layout-tab-bar-height")
                    .onChange(of: appSettings.layoutSettings.tabBarHeight) { before, after in
                        let saved = SettingsPersistence.saveLayout(appSettings: appSettings)
                        LayoutResizeTelemetry.record(
                            event: "completed", section: "tab_bar", axis: .rows, source: "settings",
                            before: before, after: after, result: saved ? "saved" : "save_failed"
                        )
                    }
                }
                SettingRow(
                    title: "Notification Sidebar Width",
                    description: "Preferred width of the notification sidebar.",
                    defaultValue: "240 points"
                ) {
                    Stepper(
                        "\(Int(appSettings.layoutSettings.notificationSidebarWidth)) points",
                        value: $appSettings.layoutSettings.notificationSidebarWidth,
                        in: 160...480,
                        step: 16
                    )
                    .accessibilityIdentifier("settings-layout-sidebar-width")
                    .onChange(of: appSettings.layoutSettings.notificationSidebarWidth) { before, after in
                        let saved = SettingsPersistence.saveLayout(appSettings: appSettings)
                        LayoutResizeTelemetry.record(
                            event: "completed", section: "notification_sidebar", axis: .columns, source: "settings",
                            before: before, after: after, result: saved ? "saved" : "save_failed"
                        )
                    }
                }
                Button("Reset Section Sizes") {
                    let beforeTabBar = appSettings.layoutSettings.tabBarHeight
                    let beforeSidebar = appSettings.layoutSettings.notificationSidebarWidth
                    appSettings.layoutSettings.resetSections()
                    let saved = SettingsPersistence.saveLayout(appSettings: appSettings)
                    LayoutResizeTelemetry.record(
                        event: "reset", section: "tab_bar", axis: .rows, source: "settings",
                        before: beforeTabBar, after: appSettings.layoutSettings.tabBarHeight,
                        result: saved ? "saved" : "save_failed"
                    )
                    LayoutResizeTelemetry.record(
                        event: "reset", section: "notification_sidebar", axis: .columns, source: "settings",
                        before: beforeSidebar, after: appSettings.layoutSettings.notificationSidebarWidth,
                        result: saved ? "saved" : "save_failed"
                    )
                }
                .accessibilityIdentifier("settings-layout-reset-sections")
            }
            Section("New Pane") {
                SettingRow(
                    title: "Default Branch",
                    description: "Start new panes from a specific branch by default."
                ) {
                    Toggle("Default Branch", isOn: $appSettings.isDefaultBranchEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-default-branch-toggle")
                        .onChange(of: appSettings.isDefaultBranchEnabled) {
                            SettingsPersistence.saveDefaultBranch(appSettings: appSettings)
                        }
                }
                if appSettings.isDefaultBranchEnabled {
                    SettingRow(
                        title: "Branch Name",
                        description: "Branch used as the base when creating new worktrees.",
                        defaultValue: "main"
                    ) {
                        TextField("", text: $appSettings.defaultBranch)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 120)
                            .accessibilityIdentifier("settings-default-branch-field")
                            .onChange(of: appSettings.defaultBranch) {
                                SettingsPersistence.saveDefaultBranch(appSettings: appSettings)
                            }
                    }
                }
                SettingRow(
                    title: "Starting Point",
                    description: appSettings.worktreeBaseRef.description,
                    defaultValue: "Fresh"
                ) {
                    Picker("Starting Point", selection: $appSettings.worktreeBaseRef) {
                        ForEach(WorktreeBaseRef.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings-worktree-base-ref-picker")
                    .onChange(of: appSettings.worktreeBaseRef) {
                        SettingsPersistence.save(appSettings.worktreeBaseRef, to: "worktree-base-ref.json")
                    }
                }
                SettingRow(
                    title: "If Branch Exists",
                    description: appSettings.existingWorktreeManagement.description,
                    defaultValue: "Ask"
                ) {
                    Picker("If Branch Exists", selection: $appSettings.existingWorktreeManagement) {
                        ForEach(ExistingWorktreeManagement.allCases, id: \.self) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings-existing-worktree-management-picker")
                    .onChange(of: appSettings.existingWorktreeManagement) {
                        SettingsPersistence.save(
                            appSettings.existingWorktreeManagement, to: "existing-worktree-management.json")
                    }
                }
            }
            AgentControlSettingsSection()
            Section("Terminal") {
                SettingRow(
                    title: "Shell",
                    description:
                        "The command-line shell used to start agents. Its startup files load first so tools you've installed (such as Node or Homebrew packages) are found. Leave on Auto-detect unless an agent can't locate a tool.",
                    defaultValue: "Auto-detect"
                ) {
                    Picker("Shell", selection: $shellPickerSelection) {
                        Text("Auto-detect (\(ShellResolver.detectedLoginShell()))").tag("")
                        ForEach(ShellResolver.commonShells, id: \.self) { shell in
                            Text(shell).tag(shell)
                        }
                        Text("Other\u{2026}").tag("__other__")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 280)
                    .accessibilityIdentifier("settings-shell-picker")
                    .onChange(of: shellPickerSelection) {
                        if shellPickerSelection != "__other__" {
                            appSettings.preferredShell = shellPickerSelection
                            SettingsPersistence.saveShellSettings(appSettings: appSettings)
                        }
                    }
                }
                if shellPickerSelection == "__other__" {
                    SettingRow(
                        title: "Custom Path",
                        description: "Full path to the shell executable."
                    ) {
                        TextField("/bin/zsh", text: $appSettings.preferredShell)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 280)
                            .accessibilityIdentifier("settings-shell-custom-path-field")
                            .onChange(of: appSettings.preferredShell) {
                                SettingsPersistence.saveShellSettings(appSettings: appSettings)
                            }
                    }
                }
                SettingRow(
                    title: "Scrollback History",
                    description:
                        "Default history retained by terminal panes. Existing pane overrides are unchanged.",
                    defaultValue: "5,000 lines"
                ) {
                    ScrollbackLimitEditor(
                        value: appSettings.defaultScrollback,
                        allowsInheritance: false,
                        inheritedValue: .defaultValue,
                        accessibilityPrefix: "settings-scrollback",
                        onChange: { limit in
                            guard let limit else { return }
                            if limit.resolvedLines < appSettings.defaultScrollback.resolvedLines {
                                pendingDefaultScrollback = limit
                                showsScrollbackReductionWarning = true
                            } else {
                                appSettings.defaultScrollback = limit
                                SettingsPersistence.save(
                                    SettingsPersistence.TerminalSettings(scrollback: limit),
                                    to: "terminal-settings.json"
                                )
                            }
                        },
                        finiteLinesText: $scrollbackLinesText
                    )
                    .frame(width: 280, alignment: .leading)
                }
                SettingRow(
                    title: "Auto Session Name",
                    description:
                        "Passes --name <tab>/<pane> to Claude so sessions appear by name in claude resume "
                        + "and the terminal title. Skipped if --name is set manually in CLI Options."
                ) {
                    Toggle("Auto Session Name", isOn: $appSettings.autoSetSessionName)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-auto-session-name-toggle")
                        .onChange(of: appSettings.autoSetSessionName) {
                            SettingsPersistence.save(appSettings.autoSetSessionName, to: "session-name-settings.json")
                        }
                }
                SettingRow(
                    title: "When Process Exits",
                    description: appSettings.exitBehavior.description,
                    defaultValue: "Show Prompt"
                ) {
                    Picker("When Process Exits", selection: $appSettings.exitBehavior) {
                        ForEach(ExitBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings-exit-behavior-picker")
                    .onChange(of: appSettings.exitBehavior) {
                        SettingsPersistence.save(appSettings.exitBehavior, to: "exit-behavior.json")
                    }
                }
            }
            .alert(
                "Reduce Scrollback History?",
                isPresented: $showsScrollbackReductionWarning,
                presenting: pendingDefaultScrollback
            ) { limit in
                Button("Reduce History", role: .destructive) {
                    appSettings.defaultScrollback = limit
                    scrollbackLinesText = String(limit.resolvedLines)
                    SettingsPersistence.save(
                        SettingsPersistence.TerminalSettings(scrollback: limit),
                        to: "terminal-settings.json"
                    )
                    pendingDefaultScrollback = nil
                }
                Button("Cancel", role: .cancel) {
                    scrollbackLinesText = String(appSettings.defaultScrollback.resolvedLines)
                    pendingDefaultScrollback = nil
                }
            } message: { _ in
                Text("Oldest retained terminal lines are discarded immediately and cannot be recovered.")
            }
            Section("Cleanup") {
                SettingRow(
                    title: "Worktree Cleanup",
                    description: appSettings.worktreeCleanupBehavior.description,
                    defaultValue: "Ask"
                ) {
                    Picker("Worktree Cleanup", selection: $appSettings.worktreeCleanupBehavior) {
                        ForEach(WorktreeCleanupBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings-worktree-cleanup-picker")
                    .onChange(of: appSettings.worktreeCleanupBehavior) {
                        SettingsPersistence.save(appSettings.worktreeCleanupBehavior, to: "worktree-cleanup.json")
                    }
                }
                SettingRow(
                    title: "Delete Branch With Worktree",
                    description:
                        "Also delete the local branch when a worktree is deleted. A branch with commits that are on "
                        + "no remote is only deleted after you confirm, and the default branch is never deleted.",
                    defaultValue: "On"
                ) {
                    Toggle("Delete Branch With Worktree", isOn: $appSettings.deleteBranchWithWorktree)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-delete-branch-with-worktree-toggle")
                        .onChange(of: appSettings.deleteBranchWithWorktree) {
                            SettingsPersistence.save(
                                appSettings.deleteBranchWithWorktree,
                                to: SettingsPersistence.deleteBranchWithWorktreeFile)
                        }
                }
                SettingRow(
                    title: "Clean Up Leftovers at Launch",
                    description:
                        "When the app starts, delete leftover worktrees it created that no pane uses, that have no "
                        + "unsaved work, and that have not changed in 24 hours. Anything else stays in the list below.",
                    defaultValue: "On"
                ) {
                    Toggle("Clean Up Leftovers at Launch", isOn: $appSettings.cleanUpLeftoversAtLaunch)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-clean-up-leftovers-toggle")
                        .onChange(of: appSettings.cleanUpLeftoversAtLaunch) {
                            SettingsPersistence.save(
                                appSettings.cleanUpLeftoversAtLaunch,
                                to: SettingsPersistence.cleanUpLeftoversAtLaunchFile)
                        }
                }
                SettingRow(
                    title: "Continue on Restart",
                    description:
                        "Resume the last conversation when Claude, Cursor, or OpenCode panes "
                        + "reopen after a restart."
                ) {
                    Toggle("Continue on Restart", isOn: $appSettings.continueOnRestart)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-continue-on-restart-toggle")
                        .onChange(of: appSettings.continueOnRestart) {
                            SettingsPersistence.save(
                                RestartConfig(continueOnRestart: appSettings.continueOnRestart),
                                to: "restart-settings.json")
                        }
                }
            }
            Section("Activity Indicators") {
                SettingRow(
                    title: "Show Activity Indicators",
                    description:
                        "Show pane and tab activity indicators (idle ring, soft neutral working glow, crisp accent waiting dot)."
                ) {
                    Toggle("Show Activity Indicators", isOn: $appSettings.paneActivityIndicatorsEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-activity-indicators-toggle")
                        .onChange(of: appSettings.paneActivityIndicatorsEnabled) {
                            SettingsPersistence.save(
                                SettingsPersistence.ActivityIndicatorConfig(
                                    enabled: appSettings.paneActivityIndicatorsEnabled),
                                to: "activity-indicator-settings.json")
                        }
                }
            }
            Section("Focus Mode") {
                SettingRow(
                    title: "When Switching Tabs",
                    description: appSettings.focusModeTabSwitchBehavior.description,
                    defaultValue: "Remember Focus"
                ) {
                    Picker("When Switching Tabs", selection: $appSettings.focusModeTabSwitchBehavior) {
                        ForEach(FocusModeTabSwitchBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings-focus-mode-tab-switch-picker")
                    .onChange(of: appSettings.focusModeTabSwitchBehavior) {
                        SettingsPersistence.saveFocusModeSettings(appSettings: appSettings)
                    }
                }
                SettingRow(
                    title: "Hide Notification Sidebar",
                    description: "Use the full tab-body width while a pane is focused."
                ) {
                    Toggle(
                        "Hide Notification Sidebar While Focused",
                        isOn: $appSettings.hideNotificationSidebarWhileFocused
                    )
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityIdentifier("settings-focus-mode-hide-sidebar-toggle")
                    .onChange(of: appSettings.hideNotificationSidebarWhileFocused) {
                        SettingsPersistence.saveFocusModeSettings(appSettings: appSettings)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .pinnedFormBackground()
        .onAppear {
            let preferred = appSettings.preferredShell
            if preferred.isEmpty {
                shellPickerSelection = ""
            } else if ShellResolver.commonShells.contains(preferred) {
                shellPickerSelection = preferred
            } else {
                shellPickerSelection = "__other__"
            }
        }
    }
}

private struct ToolsContent: View {
    @Environment(AppSettings.self) private var appSettings
    @State private var selectedTool: Harness = .claude

    private var configurableTools: [Harness] {
        Harness.allCases.filter { $0 != .shell }
    }

    var body: some View {
        @Bindable var appSettings = appSettings
        VStack(spacing: 0) {
            Picker("Tool", selection: $selectedTool) {
                ForEach(configurableTools, id: \.self) { tool in
                    Text(tool.displayName).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedTool.displayName)
                            Text(selectedTool.commandDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontDesign(.monospaced)
                        }
                        Spacer()
                        Toggle(
                            selectedTool.displayName,
                            isOn: Binding(
                                get: { appSettings.isActive(selectedTool) },
                                set: { active in
                                    appSettings.setActive(selectedTool, active)
                                    SettingsPersistence.saveActiveTools(appSettings: appSettings)
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-tool-enable-toggle-\(selectedTool.rawValue)")
                    }
                    if !appSettings.isActive(selectedTool) {
                        Text("Enable to configure \(selectedTool.displayName) CLI options.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if appSettings.isActive(selectedTool) {
                    switch selectedTool {
                    case .claude:
                        CLIOptionsContent(
                            options: Binding(
                                get: { appSettings.cliOptions },
                                set: { appSettings.cliOptions = $0 }
                            ),
                            onSave: { SettingsPersistence.save(appSettings: appSettings) },
                            customFlagFooter: "Custom flags may not be recognized by all Claude CLI versions.",
                            envVarOptions: Binding(
                                get: { appSettings.envVarOptions },
                                set: { appSettings.envVarOptions = $0 }
                            ),
                            onEnvVarSave: { SettingsPersistence.saveEnvVarOptions(appSettings: appSettings) }
                        )
                    case .codex:
                        CLIOptionsContent(
                            options: Binding(
                                get: { appSettings.codexCliOptions },
                                set: { appSettings.codexCliOptions = $0 }
                            ),
                            onSave: { SettingsPersistence.saveCodexOptions(appSettings: appSettings) },
                            customFlagFooter: "Custom flags may not be recognized by all Codex CLI versions."
                        )
                    case .cursor:
                        CLIOptionsContent(
                            options: Binding(
                                get: { appSettings.cursorCliOptions },
                                set: { appSettings.cursorCliOptions = $0 }
                            ),
                            onSave: { SettingsPersistence.saveCursorOptions(appSettings: appSettings) },
                            customFlagFooter: "Custom flags may not be recognized by all Cursor CLI versions."
                        )
                    case .opencode:
                        CLIOptionsContent(
                            options: Binding(
                                get: { appSettings.opencodeCliOptions },
                                set: { appSettings.opencodeCliOptions = $0 }
                            ),
                            onSave: { SettingsPersistence.saveOpenCodeOptions(appSettings: appSettings) },
                            customFlagFooter: "Custom flags may not be recognized by all OpenCode CLI versions.",
                            envVarOptions: Binding(
                                get: { appSettings.opencodeEnvVarOptions },
                                set: { appSettings.opencodeEnvVarOptions = $0 }
                            ),
                            onEnvVarSave: { SettingsPersistence.saveOpenCodeEnvVars(appSettings: appSettings) },
                            envVarHarnessDisplayName: "OpenCode"
                        )
                    case .shell:
                        EmptyView()
                    }
                }
            }
            .formStyle(.grouped)
            .pinnedFormBackground()
        }
        .background(Theme.windowBackground)
    }
}

struct CLIOptionsContent: View {
    @Binding var options: [CLIOptionConfig]
    let onSave: () -> Void
    let customFlagFooter: String
    var envVarOptions: Binding<[EnvVarConfig]>?
    var onEnvVarSave: (() -> Void)?
    var envVarHarnessDisplayName: String?
    @State private var showAddCustomFlagSheet = false
    @State private var showAddCustomEnvVarSheet = false

    private var enabledOptions: [CLIOptionConfig] {
        options.filter { $0.isAvailable && !$0.isUserAdded }.sorted { $0.id < $1.id }
    }

    private var disabledOptions: [CLIOptionConfig] {
        options.filter { !$0.isAvailable && !$0.isUserAdded }.sorted { $0.id < $1.id }
    }

    private var customOptions: [CLIOptionConfig] {
        options.filter(\.isUserAdded).sorted { $0.id < $1.id }
    }

    var body: some View {
        Group {
            if !enabledOptions.isEmpty {
                Section("Enabled") {
                    ForEach(enabledOptions, id: \.id) { option in
                        let optIndex = options.firstIndex(where: { $0.id == option.id })!
                        CLIOptionRow(option: $options[optIndex], onChange: onSave)
                    }
                }
            }
            Section("Not Enabled") {
                ForEach(disabledOptions, id: \.id) { option in
                    let optIndex = options.firstIndex(where: { $0.id == option.id })!
                    CLIOptionRow(option: $options[optIndex], onChange: onSave)
                }
            }
            Section(
                header: Text("Custom Options"),
                footer: Text(customFlagFooter).font(.caption).foregroundStyle(.secondary)
            ) {
                ForEach(customOptions, id: \.id) { option in
                    let optIndex = options.firstIndex(where: { $0.id == option.id })!
                    CustomCLIOptionRow(
                        option: $options[optIndex],
                        onChange: onSave,
                        onDelete: {
                            options.removeAll { $0.id == option.id }
                            onSave()
                        }
                    )
                }
                Button {
                    showAddCustomFlagSheet = true
                } label: {
                    Label("Add Custom Flag", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            if let envBinding = envVarOptions, let envSave = onEnvVarSave {
                EnvVarSections(
                    options: envBinding,
                    onSave: envSave,
                    showAddSheet: $showAddCustomEnvVarSheet,
                    harnessDisplayName: envVarHarnessDisplayName ?? "Claude Code"
                )
            }
        }
        .sheet(isPresented: $showAddCustomFlagSheet) {
            AddCustomFlagSheet(existingIDs: options.map(\.id)) { id, isString in
                options.append(
                    CLIOptionConfig(
                        id: id, label: id, description: "User-defined option", isAvailable: false,
                        isDefaultEnabled: false, isUserAdded: true, customIsStringType: isString))
                onSave()
            }
        }
        .sheet(isPresented: $showAddCustomEnvVarSheet) {
            if let envBinding = envVarOptions, let envSave = onEnvVarSave {
                AddCustomEnvVarSheet(existingIDs: envBinding.wrappedValue.map(\.id)) { id in
                    envBinding.wrappedValue.append(
                        EnvVarConfig(
                            id: id, label: id, description: "User-defined environment variable",
                            isAvailable: true, isUserAdded: true))
                    envSave()
                }
            }
        }
    }
}

private struct EnvVarSections: View {
    @Binding var options: [EnvVarConfig]
    let onSave: () -> Void
    @Binding var showAddSheet: Bool
    var harnessDisplayName: String = "Claude Code"

    private var enabledOptions: [EnvVarConfig] {
        options.filter { $0.isAvailable && !$0.isUserAdded }.sorted { $0.id < $1.id }
    }

    private var disabledOptions: [EnvVarConfig] {
        options.filter { !$0.isAvailable && !$0.isUserAdded }.sorted { $0.id < $1.id }
    }

    private var customOptions: [EnvVarConfig] {
        options.filter(\.isUserAdded).sorted { $0.id < $1.id }
    }

    var body: some View {
        Group {
            Section("Environment Variables") {
                Text(
                    "Configure which environment variables are set when launching \(harnessDisplayName). Variables marked as default will be pre-enabled with their default value in the New Pane dialog."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !enabledOptions.isEmpty {
                Section("Enabled Env Vars") {
                    ForEach(enabledOptions, id: \.id) { option in
                        let optIndex = options.firstIndex(where: { $0.id == option.id })!
                        EnvVarOptionRow(option: $options[optIndex], onChange: onSave)
                    }
                }
            }
            Section("Not Enabled Env Vars") {
                ForEach(disabledOptions, id: \.id) { option in
                    let optIndex = options.firstIndex(where: { $0.id == option.id })!
                    EnvVarOptionRow(option: $options[optIndex], onChange: onSave)
                }
            }
            Section(
                header: Text("Custom Env Vars"),
                footer: Text("Custom environment variables are passed to the \(harnessDisplayName) process.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            ) {
                ForEach(customOptions, id: \.id) { option in
                    let optIndex = options.firstIndex(where: { $0.id == option.id })!
                    CustomEnvVarOptionRow(
                        option: $options[optIndex],
                        onChange: onSave,
                        onDelete: {
                            options.removeAll { $0.id == option.id }
                            onSave()
                        }
                    )
                }
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Custom Env Var", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct KeyboardShortcutsContent: View {
    @Environment(AppSettings.self) private var appSettings
    @AppStorage("keyBinding.newTabKey") var newTabKey = "t"
    @AppStorage("keyBinding.newPaneKey") var newPaneKey = "p"
    @AppStorage("keyBinding.closePaneKey") var closePaneKey = "w"
    @AppStorage("keyBinding.closeTabKey") var closeTabKey = "k"
    @AppStorage("keyBinding.openShellHereKey") var openShellHereKey = "s"
    @AppStorage("keyBinding.refreshPaneKey") var refreshPaneKey = "r"
    @AppStorage("keyBinding.viewPaneSettingsKey") var viewPaneSettingsKey = "i"

    var body: some View {
        Form {
            Section {
                KeyBindingRow(
                    id: "new-tab",
                    label: "New Tab", description: "Open the New Tab sheet", modifier: "⌘",
                    key: $newTabKey, validateBinding: validateAppBinding)
                KeyBindingRow(
                    id: "new-pane",
                    label: "New Pane in Current Tab", description: "Open the New Pane sheet",
                    modifier: "⌘", key: $newPaneKey, validateBinding: validateAppBinding)
                KeyBindingRow(
                    id: "close-pane",
                    label: "Close Active Pane", description: "Close the focused pane", modifier: "⌘",
                    key: $closePaneKey, validateBinding: validateAppBinding)
                KeyBindingRow(
                    id: "close-tab",
                    label: "Close Active Tab", description: "Close the current tab", modifier: "⌘",
                    key: $closeTabKey, validateBinding: validateAppBinding)
                KeyBindingRow(
                    id: "open-shell-here",
                    label: "Open Shell Here",
                    description: "Open a new plain shell pane in the same working directory",
                    modifier: "⌘⇧", key: $openShellHereKey, validateBinding: validateAppBinding)
                KeyBindingRow(
                    id: "refresh-pane",
                    label: "Refresh Active Pane",
                    description: "Restart pane with fresh environment",
                    modifier: "⌘", key: $refreshPaneKey, validateBinding: validateAppBinding)
                KeyBindingRow(
                    id: "view-pane-settings",
                    label: "View Pane Settings",
                    description: "Show the active pane's configuration",
                    modifier: "⌘", key: $viewPaneSettingsKey, validateBinding: validateAppBinding)
            }
            Section(
                header: Text("Pane Resizing"),
                footer: Text("Resize shortcuts work while a terminal pane has keyboard focus. Command is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            ) {
                ForEach(ResizeAction.allCases, id: \.id) { action in
                    ResizeShortcutRow(action: action, appSettings: appSettings)
                }
            }
            Section(
                header: Text("Fixed Shortcuts"),
                footer: Text("Tab switching shortcuts are not configurable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            ) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("⌘1 – ⌘9")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Text("Switch to tab by index")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .pinnedFormBackground()
    }

    private func validateAppBinding(_ candidate: ResizeKeyBinding) -> String? {
        ResizeShortcutValidation.validateAppBinding(
            candidate,
            resizeBindings: appSettings.layoutSettings.bindings
        )
    }
}

private struct KeyBindingRow: View {
    let id: String
    let label: String
    let description: String
    let modifier: String
    @Binding var key: String
    var validateBinding: (ResizeKeyBinding) -> String? = { _ in nil }

    @State private var draft = ""
    @State private var validationMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 16) {
                Text(label)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .accessibilityIdentifier("settings-shortcut-title-\(id)")

                Spacer(minLength: 16)

                HStack(spacing: 4) {
                    Text(modifier)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextField("", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 36)
                        .multilineTextAlignment(.center)
                        .focused($isFocused)
                        .accessibilityIdentifier("settings-shortcut-key-\(id)")
                        .onChange(of: draft) {
                            let trimmed = String(draft.prefix(1)).lowercased()
                            if draft != trimmed {
                                draft = trimmed
                            }
                        }
                        .onChange(of: isFocused) {
                            if !isFocused {
                                if draft.isEmpty {
                                    draft = key
                                } else {
                                    let binding = ResizeKeyBinding(key: draft, modifiers: modifierFlags)
                                    if let message = validateBinding(binding) {
                                        validationMessage = message
                                        draft = key
                                    } else {
                                        key = draft
                                        validationMessage = nil
                                    }
                                }
                            }
                        }
                        .onAppear { draft = key }
                }
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings-shortcut-description-\(id)")
            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings-shortcut-error-\(id)")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-shortcut-row-\(id)")
    }

    private var modifierFlags: NSEvent.ModifierFlags {
        modifier.contains("⇧") ? [.command, .shift] : .command
    }
}

private struct ResizeShortcutRow: View {
    let action: ResizeAction
    let appSettings: AppSettings

    @State private var isCapturing = false
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.label)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .accessibilityIdentifier("settings-resize-shortcut-title-\(action.id)")
                    Text("Move the active pane divider by \(Int(action.step)) points.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ShortcutCaptureControl(
                    action: action,
                    binding: appSettings.layoutSettings.bindings.binding(for: action),
                    isCapturing: $isCapturing,
                    onCapture: { binding in
                        if let message = ResizeShortcutValidation.validateResizeBinding(
                            binding,
                            action: action,
                            bindings: appSettings.layoutSettings.bindings,
                            appBindings: ResizeKeyBinding.appBindings()
                        ) {
                            validationMessage = message
                            return
                        }
                        appSettings.layoutSettings.bindings.setBinding(binding, for: action)
                        validationMessage = nil
                        save()
                    },
                    onCancel: { validationMessage = nil },
                    onInvalid: { validationMessage = $0 }
                )
                Button("Disable") {
                    appSettings.layoutSettings.bindings.setBinding(nil, for: action)
                    validationMessage = nil
                    save()
                }
                .accessibilityIdentifier("settings-resize-shortcut-disable-\(action.id)")
            }
            if let conflict = appSettings.layoutSettings.bindings.conflicts.first(where: { $0 == action.id }) {
                Text("This saved shortcut conflicted with another app shortcut and was disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-resize-shortcut-restored-conflict-\(conflict)")
            }
            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings-resize-shortcut-error-\(action.id)")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-resize-shortcut-row-\(action.id)")
    }

    private func save() {
        SettingsPersistence.saveLayout(appSettings: appSettings)
    }
}

private struct CLIOptionRow: View {
    @Binding var option: CLIOptionConfig
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
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Show")
                            .font(.caption)
                        Toggle("Show", isOn: $option.isAvailable)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .accessibilityIdentifier("settings-cli-option-show-\(option.id)")
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
                            .disabled(!option.isAvailable)
                            .onChange(of: option.isDefaultEnabled) { onChange() }
                    }
                }
            }
            if case .string = option.optionType {
                CLIOptionPresetEditor(
                    optionID: option.id,
                    presetValues: $option.presetValues,
                    allowsMultipleValues: $option.allowsMultipleValues,
                    onChange: onChange
                )
            }
        }
        .padding(.vertical, 8)
    }
}

private struct CLIOptionPresetEditor: View {
    let optionID: String
    @Binding var presetValues: [String]
    @Binding var allowsMultipleValues: Bool
    let onChange: () -> Void

    @State private var drafts: [PresetDraft] = []

    private struct PresetDraft: Identifiable {
        let id = UUID()
        var value: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Allow multiple selections", isOn: $allowsMultipleValues)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help(
                    "Only enable this for flags whose CLI accepts multiple space-separated values behind one "
                        + "flag (e.g. --mcp-config a.json b.json). Enabling it for a flag that only accepts a "
                        + "single value will produce an incorrect command line."
                )
                .accessibilityIdentifier("settings-cli-option-allow-multi-\(optionID)")
                .onChange(of: allowsMultipleValues) { onChange() }
            HStack(spacing: 6) {
                Text("Preset values")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    drafts.append(PresetDraft(value: ""))
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings-cli-option-preset-add-\(optionID)")
            }
            ForEach($drafts) { $draft in
                HStack(spacing: 6) {
                    TextField("Value", text: $draft.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .onChange(of: draft.value) { commit() }
                        .accessibilityIdentifier("settings-cli-option-preset-value-\(optionID)")
                    Button {
                        drafts.removeAll { $0.id == draft.id }
                        commit()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("settings-cli-option-preset-remove-\(optionID)")
                }
            }
        }
        .padding(.top, 4)
        .onAppear {
            drafts = presetValues.map { PresetDraft(value: $0) }
        }
    }

    private func commit() {
        presetValues = CLIOptionConfig.normalizedPresetValues(drafts.map(\.value))
        onChange()
    }
}

private struct CustomCLIOptionRow: View {
    @Binding var option: CLIOptionConfig
    let onChange: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(option.id)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Text(option.customIsStringType ? "text" : "boolean")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
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
                            .accessibilityIdentifier("settings-cli-option-show-\(option.id)")
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
                            .disabled(!option.isAvailable)
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
        }
        .padding(.vertical, 8)
    }
}

private struct AboutContent: View {
    @Environment(AppSettings.self) private var appSettings
    @State private var coordinator = UpdateCheckCoordinator.shared

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static func shortSHA(_ sha: String) -> String { String(sha.prefix(7)) }

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            if let channel = coordinator.channel {
                Section("Build") {
                    if channel == .sourceMain, let provenance = BuildProvenance.current() {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Built from \(provenance.branch) @ \(Self.shortSHA(provenance.commit))")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                            if let date = provenance.commitDate {
                                Text(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")"
                            )
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if channel == .sourceMain {
                    Section("Updates") {
                        if let latest = coordinator.latestVersion {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Latest main: \(Self.shortSHA(latest))")
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                if let checked = coordinator.lastCheckedAt {
                                    Text(
                                        "Checked \(Self.relativeFormatter.localizedString(for: checked, relativeTo: Date()))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if coordinator.updateAvailable {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Update available")
                                        .fontWeight(.medium)
                                    Text("Run git pull && make run to update.")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("settings-about-update-available-banner")
                        }

                        Button {
                            coordinator.check()
                        } label: {
                            if coordinator.isChecking {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Check for Updates")
                            }
                        }
                        .disabled(coordinator.isChecking)
                        .accessibilityIdentifier("settings-check-for-updates-button")

                        SettingRow(
                            title: "Update Reminder",
                            description: "Show a reminder in the tab bar when a newer commit exists on GitHub main.",
                            defaultValue: "On"
                        ) {
                            Toggle("Update Reminder", isOn: $appSettings.updateReminderEnabled)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .accessibilityIdentifier("settings-update-reminder-toggle")
                                .onChange(of: appSettings.updateReminderEnabled) {
                                    SettingsPersistence.saveUpdateCheckSettings(appSettings: appSettings)
                                    if appSettings.updateReminderEnabled {
                                        UpdateCheckCoordinator.shared.start()
                                    } else {
                                        UpdateCheckCoordinator.shared.stop()
                                    }
                                }
                        }
                    }
                } else if channel == .dmg {
                    Section("Updates") {
                        if let latest = coordinator.latestVersion {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Latest release: \(latest)")
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                if let checked = coordinator.lastCheckedAt {
                                    Text(
                                        "Checked \(Self.relativeFormatter.localizedString(for: checked, relativeTo: Date()))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if coordinator.updateAvailable {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Update available")
                                        .fontWeight(.medium)
                                    Text("Download and install the latest release.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("settings-about-update-available-banner")
                        }

                        HStack(spacing: 12) {
                            Button {
                                coordinator.check()
                            } label: {
                                if coordinator.isChecking {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Check for Updates")
                                }
                            }
                            .disabled(coordinator.isChecking)
                            .accessibilityIdentifier("settings-check-for-updates-button")

                            if coordinator.updateAvailable {
                                Button {
                                    coordinator.performUpdate()
                                } label: {
                                    Text("Install Update")
                                }
                                .accessibilityIdentifier("settings-install-update-button")
                            }
                        }

                        SettingRow(
                            title: "Update Reminder",
                            description: "Show a reminder in the tab bar when a newer DMG release is available.",
                            defaultValue: "On"
                        ) {
                            Toggle("Update Reminder", isOn: $appSettings.updateReminderEnabled)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .accessibilityIdentifier("settings-update-reminder-toggle")
                                .onChange(of: appSettings.updateReminderEnabled) {
                                    SettingsPersistence.saveUpdateCheckSettings(appSettings: appSettings)
                                    if appSettings.updateReminderEnabled {
                                        UpdateCheckCoordinator.shared.start()
                                    } else {
                                        UpdateCheckCoordinator.shared.stop()
                                    }
                                }
                        }
                    }
                }
            } else {
                Section("Version") {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
            }
        }
        .formStyle(.grouped)
        .pinnedFormBackground()
    }
}
