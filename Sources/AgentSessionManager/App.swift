import AppKit
import SwiftUI

struct ContentView: View {
    let launchLifecycleResult: ApplicationLifecycleRecordResult
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var appSettings
    @State private var traceCleanupService: TraceCleanupService?
    @State private var showingNewTab = false
    @State private var showCleanupAlert = false
    @State private var pendingCleanupPane: Pane?
    @State private var pendingCleanupTab: Tab?
    @State private var showPRResolutionAlert = false
    @State private var pendingPRResolutionPane: Pane?
    @State private var pendingPRResolutionTab: Tab?
    @State private var pendingPRResolutionKind: NotificationKind = .prMerged
    @State private var paneToRefresh: Pane?
    @State private var pendingRefreshSettings: Pane?
    @State private var paneForRefreshSettings: Pane?
    @State private var showOnboarding = false
    @State private var paneForSettings: Pane?
    @State private var tabBarResizePreview: Double?
    @State private var sidebarResizePreview: Double?
    @State private var tabBarResizeSnapshot: Double?
    @State private var sidebarResizeSnapshot: Double?
    @State private var layoutMeasurements: [String: Double] = [:]

    var body: some View {
        @Bindable var appState = appState
        let hasNotifications = !appState.notifications.isEmpty
        let hideNotificationSidebar =
            appSettings.hideNotificationSidebarWhileFocused
            && appState.activeTab?.focusedPaneID != nil
        GeometryReader { geometry in
            let activeTab = appState.activeTab
            let layout = GridLayout.forPaneCount(activeTab?.panes.count ?? 0)
            let isFocused = activeTab?.focusedPaneID != nil
            let effectiveLayout = isFocused ? GridLayout.forPaneCount(1) : layout
            let mainMinimumWidth =
                activeTab?.panes.isEmpty != false
                ? 160.0
                : isFocused ? 168.0 : max(168, Double(layout.columns) * 160 + Double(layout.columns - 1) * 4 + 8)
            let visiblePanes =
                isFocused
                ? activeTab?.panes.filter { $0.id == activeTab?.focusedPaneID } ?? []
                : activeTab?.panes ?? []
            let rowMinimums = (0..<effectiveLayout.rows).map { rowIndex in
                let panesInRow = visiblePanes.enumerated().compactMap { index, pane in
                    index / effectiveLayout.columns == rowIndex ? pane : nil
                }
                guard !panesInRow.isEmpty else { return 64.0 }
                return panesInRow.map { pane in
                    let headerHeight = layoutMeasurements["header-\(pane.id.uuidString)"] ?? 28
                    let statusConfig: StatusLineConfig
                    if let profileID = pane.profileID,
                        let profile = appSettings.profiles.first(where: { $0.id == profileID })
                    {
                        statusConfig = profile.resolvedStatusLineConfig(inheriting: appSettings.statusLineConfig)
                    } else {
                        statusConfig = appSettings.statusLineConfig
                    }
                    let hasStatusRows =
                        pane.statusLineMonitor != nil
                        && statusConfig.rows.contains {
                            $0.items.contains { statusConfig.supports($0, on: pane.harness) }
                        }
                    return headerHeight + 1 + 64 + (hasStatusRows ? 32 : 0)
                }.max() ?? 64
            }
            let mainMinimumHeight =
                activeTab?.panes.isEmpty == false
                ? rowMinimums.reduce(0, +) + Double(max(0, effectiveLayout.rows - 1)) * 4 + 8
                : 64.0
            let tabBarMinimum = max(
                44,
                (layoutMeasurements.filter { $0.key.hasPrefix("tabbar-") }.values.max() ?? 0) + 12
            )
            let tabBarMaximum = max(tabBarMinimum, min(96, Double(geometry.size.height) - mainMinimumHeight))
            let tabBarSize = min(
                max(tabBarResizePreview ?? appSettings.layoutSettings.tabBarHeight, tabBarMinimum),
                tabBarMaximum
            )
            let sidebarIsVisible =
                (hasNotifications || appSettings.alwaysShowNotificationsSidebar)
                && !hideNotificationSidebar
            let sidebarMaximum = max(160, min(480, Double(geometry.size.width) - mainMinimumWidth - 8))
            let sidebarSize = min(
                max(sidebarResizePreview ?? appSettings.layoutSettings.notificationSidebarWidth, 160),
                sidebarMaximum
            )
            let cancellationKey = [
                activeTab?.id.uuidString ?? "empty",
                activeTab?.panes.map { $0.id.uuidString }.joined(separator: ",") ?? "",
                activeTab?.focusedPaneID?.uuidString ?? "grid",
                appState.activePaneID?.uuidString ?? "none",
                "\(layout.columns)x\(layout.rows)",
                "\(geometry.size.width)x\(geometry.size.height)",
                "\(mainMinimumWidth)x\(mainMinimumHeight)",
                appSettings.notificationSidebarSide.rawValue,
                "\(sidebarIsVisible)",
            ].joined(separator: "|")

            VStack(spacing: 0) {
                TabBarView()
                    .frame(height: tabBarSize)

                HStack(spacing: 0) {
                    if appSettings.notificationSidebarSide == .left && sidebarIsVisible {
                        NotificationSidebarView()
                            .environment(appState)
                            .environment(appSettings)
                            .frame(width: sidebarSize)
                        GlobalSectionHandle(
                            axis: .columns,
                            identifier: "notification-sidebar-resize-handle",
                            label: "Notification Sidebar",
                            value: sidebarSize,
                            minimum: 160,
                            maximum: sidebarMaximum,
                            cancellationKey: cancellationKey,
                            onPreview: { newValue in
                                if let newValue {
                                    if sidebarResizeSnapshot == nil { sidebarResizeSnapshot = sidebarSize }
                                    sidebarResizePreview = newValue
                                } else {
                                    sidebarResizePreview = nil
                                    sidebarResizeSnapshot = nil
                                }
                            },
                            onCommit: { newValue, source in
                                let previousValue = sidebarResizeSnapshot ?? sidebarSize
                                appSettings.layoutSettings.notificationSidebarWidth = newValue
                                sidebarResizeSnapshot = nil
                                let saved = SettingsPersistence.saveLayout(appSettings: appSettings)
                                LayoutResizeTelemetry.record(
                                    event: "completed", section: "notification_sidebar", axis: .columns,
                                    source: source, before: previousValue, after: newValue,
                                    result: saved ? "saved" : "save_failed", tab: activeTab
                                )
                            },
                            onReset: { source in
                                let previousValue = sidebarSize
                                let resetValue = min(max(240, 160), sidebarMaximum)
                                appSettings.layoutSettings.notificationSidebarWidth = 240
                                sidebarResizePreview = nil
                                sidebarResizeSnapshot = nil
                                let saved = SettingsPersistence.saveLayout(appSettings: appSettings)
                                LayoutResizeTelemetry.record(
                                    event: "reset", section: "notification_sidebar", axis: .columns,
                                    source: source, before: previousValue, after: resetValue,
                                    result: saved ? "saved" : "save_failed", tab: activeTab
                                )
                            },
                            onCancel: {
                                let before = appSettings.layoutSettings.notificationSidebarWidth
                                sidebarResizePreview = nil
                                LayoutResizeTelemetry.record(
                                    event: "canceled", section: "notification_sidebar", axis: .columns,
                                    source: "pointer", before: sidebarResizeSnapshot ?? before,
                                    after: sidebarResizeSnapshot ?? before, result: "canceled", tab: activeTab
                                )
                                sidebarResizeSnapshot = nil
                            }
                        )
                    }

                    Group {
                        if appState.tabs.isEmpty {
                            EmptyStateView()
                        } else if let tab = activeTab {
                            PaneGridView(
                                tab: tab, onClosePane: handleClosePane, onRefreshPane: handleRefreshPane,
                                onViewPaneSettings: handleViewPaneSettings
                            )
                        }
                    }
                    .frame(minWidth: mainMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)

                    if appSettings.notificationSidebarSide == .right && sidebarIsVisible {
                        GlobalSectionHandle(
                            axis: .columns,
                            identifier: "notification-sidebar-resize-handle",
                            label: "Notification Sidebar",
                            value: sidebarSize,
                            minimum: 160,
                            maximum: sidebarMaximum,
                            movementSign: -1,
                            cancellationKey: cancellationKey,
                            onPreview: { newValue in
                                if let newValue {
                                    if sidebarResizeSnapshot == nil { sidebarResizeSnapshot = sidebarSize }
                                    sidebarResizePreview = newValue
                                } else {
                                    sidebarResizePreview = nil
                                    sidebarResizeSnapshot = nil
                                }
                            },
                            onCommit: { newValue, source in
                                let previousValue = sidebarResizeSnapshot ?? sidebarSize
                                appSettings.layoutSettings.notificationSidebarWidth = newValue
                                sidebarResizeSnapshot = nil
                                let saved = SettingsPersistence.saveLayout(appSettings: appSettings)
                                LayoutResizeTelemetry.record(
                                    event: "completed", section: "notification_sidebar", axis: .columns,
                                    source: source, before: previousValue, after: newValue,
                                    result: saved ? "saved" : "save_failed", tab: activeTab
                                )
                            },
                            onReset: { source in
                                let previousValue = sidebarSize
                                let resetValue = min(max(240, 160), sidebarMaximum)
                                appSettings.layoutSettings.notificationSidebarWidth = 240
                                sidebarResizePreview = nil
                                sidebarResizeSnapshot = nil
                                let saved = SettingsPersistence.saveLayout(appSettings: appSettings)
                                LayoutResizeTelemetry.record(
                                    event: "reset", section: "notification_sidebar", axis: .columns,
                                    source: source, before: previousValue, after: resetValue,
                                    result: saved ? "saved" : "save_failed", tab: activeTab
                                )
                            },
                            onCancel: {
                                let before = appSettings.layoutSettings.notificationSidebarWidth
                                sidebarResizePreview = nil
                                LayoutResizeTelemetry.record(
                                    event: "canceled", section: "notification_sidebar", axis: .columns,
                                    source: "pointer", before: sidebarResizeSnapshot ?? before,
                                    after: sidebarResizeSnapshot ?? before, result: "canceled", tab: activeTab
                                )
                                sidebarResizeSnapshot = nil
                            }
                        )
                        NotificationSidebarView()
                            .environment(appState)
                            .environment(appSettings)
                            .frame(width: sidebarSize)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                GlobalSectionHandle(
                    axis: .rows,
                    identifier: "tab-bar-resize-handle",
                    label: "Tab Bar",
                    value: tabBarSize,
                    minimum: tabBarMinimum,
                    maximum: tabBarMaximum,
                    cancellationKey: cancellationKey,
                    onPreview: { newValue in
                        if let newValue {
                            if tabBarResizeSnapshot == nil { tabBarResizeSnapshot = tabBarSize }
                            tabBarResizePreview = newValue
                        } else {
                            tabBarResizePreview = nil
                            tabBarResizeSnapshot = nil
                        }
                    },
                    onCommit: { newValue, source in
                        let previousValue = tabBarResizeSnapshot ?? tabBarSize
                        appSettings.layoutSettings.tabBarHeight = newValue
                        tabBarResizeSnapshot = nil
                        let saved = SettingsPersistence.saveLayout(appSettings: appSettings)
                        LayoutResizeTelemetry.record(
                            event: "completed", section: "tab_bar", axis: .rows, source: source,
                            before: previousValue, after: newValue,
                            result: saved ? "saved" : "save_failed", tab: activeTab
                        )
                    },
                    onReset: { source in
                        let previousValue = tabBarSize
                        let resetValue = min(max(44, tabBarMinimum), tabBarMaximum)
                        appSettings.layoutSettings.tabBarHeight = 44
                        tabBarResizePreview = nil
                        tabBarResizeSnapshot = nil
                        let saved = SettingsPersistence.saveLayout(appSettings: appSettings)
                        LayoutResizeTelemetry.record(
                            event: "reset", section: "tab_bar", axis: .rows, source: source,
                            before: previousValue, after: resetValue,
                            result: saved ? "saved" : "save_failed", tab: activeTab
                        )
                    },
                    onCancel: {
                        let before = appSettings.layoutSettings.tabBarHeight
                        tabBarResizePreview = nil
                        LayoutResizeTelemetry.record(
                            event: "canceled", section: "tab_bar", axis: .rows, source: "pointer",
                            before: tabBarResizeSnapshot ?? before,
                            after: tabBarResizeSnapshot ?? before, result: "canceled", tab: activeTab
                        )
                        tabBarResizeSnapshot = nil
                    }
                )
                .frame(height: 8)
                .offset(y: tabBarSize - 4)
            }
            .onPreferenceChange(LayoutMeasurementKey.self) { layoutMeasurements = $0 }
        }
        .background(Theme.controlBackground)
        .overlay(alignment: .bottom) {
            if let message = appSettings.layoutSaveError {
                HStack(spacing: 8) {
                    Text(message)
                        .font(.caption)
                    Button("Dismiss") { appSettings.layoutSaveError = nil }
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Theme.overlayMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(8)
                .accessibilityIdentifier("layout-save-error")
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .agentSessionManagerCursorNotificationSettingChanged)
        ) { _ in
            appState.configureCursorAttentionWatchers(
                enabled: appSettings.isCursorNotificationHookAttentionEnabled)
        }
        .task {
            if let config = SettingsPersistence.load(DefaultBranchConfig.self, from: "default-branch.json") {
                appSettings.isDefaultBranchEnabled = config.isEnabled
                appSettings.defaultBranch = config.branchName
            } else if let branch = SettingsPersistence.load(String.self, from: "default-branch.json"), !branch.isEmpty {
                appSettings.defaultBranch = branch
                appSettings.isDefaultBranchEnabled = true
            }
            var restoredLayoutSettings =
                SettingsPersistence.load(LayoutSettings.self, from: "layout-settings.json")
                ?? LayoutSettings()
            restoredLayoutSettings.bindings.resolveConflicts(appBindings: ResizeKeyBinding.appBindings())
            appSettings.layoutSettings = restoredLayoutSettings
            if !CommandLine.arguments.contains("--uitesting-skip-restore") {
                appSettings.cliOptions = SettingsPersistence.mergeCLIOptions(
                    SettingsPersistence.loadCLIOptions(from: "settings.json", harness: .claude),
                    into: CLIOptionConfig.all)
                appSettings.codexCliOptions = SettingsPersistence.mergeCLIOptions(
                    SettingsPersistence.loadCLIOptions(from: "codex-settings.json", harness: .codex),
                    into: CLIOptionConfig.codexAll)
                appSettings.cursorCliOptions = SettingsPersistence.mergeCLIOptions(
                    SettingsPersistence.loadCLIOptions(from: "cursor-settings.json", harness: .cursor),
                    into: CLIOptionConfig.cursorAll)
                appSettings.opencodeCliOptions = SettingsPersistence.mergeCLIOptions(
                    SettingsPersistence.loadCLIOptions(from: "opencode-settings.json", harness: .opencode),
                    into: CLIOptionConfig.opencodeAll)
                if let config = SettingsPersistence.load(StatusLineConfig.self, from: "statusline-settings.json") {
                    appSettings.statusLineConfig = config
                    if config.needsPersistenceMigration {
                        _ = SettingsPersistence.saveStatusLine(appSettings: appSettings)
                    }
                }
                if let tools = SettingsPersistence.load([String].self, from: "active-tools-settings.json") {
                    appSettings.activeTools = Set(tools).intersection(Harness.allCases.map(\.rawValue))
                }
                if let config = SettingsPersistence.load(NotificationConfig.self, from: "notification-settings.json") {
                    appSettings.notificationSidebarSide = config.sidebarSide
                    appSettings.isPriorityNotificationsEnabled = config.isPriorityEnabled
                    appSettings.isMacOSBannerNotificationsEnabled = config.isMacOSBannerEnabled
                    appSettings.isCursorNotificationHookAttentionEnabled = config.isCursorHookAttentionEnabled
                    appSettings.isPRMergedNotificationsEnabled = config.isPRMergedNotificationsEnabled
                    appSettings.isPRClosedNotificationsEnabled = config.isPRClosedNotificationsEnabled
                    appSettings.alwaysShowNotificationsSidebar = config.alwaysShowNotificationsSidebar
                    appSettings.isClaudeStopNotificationEnabled = config.isClaudeStopNotificationEnabled
                    appSettings.isOpencodeStopNotificationEnabled = config.isOpencodeStopNotificationEnabled
                }
                if let config = SettingsPersistence.load(RestartConfig.self, from: "restart-settings.json") {
                    appSettings.continueOnRestart = config.continueOnRestart
                }
                if let value = SettingsPersistence.load(WorktreeCleanupBehavior.self, from: "worktree-cleanup.json") {
                    appSettings.worktreeCleanupBehavior = value
                }
                if let value = SettingsPersistence.load(
                    ExistingWorktreeManagement.self, from: "existing-worktree-management.json")
                {
                    appSettings.existingWorktreeManagement = value
                }
                if let value = SettingsPersistence.load(WorktreeBaseRef.self, from: "worktree-base-ref.json") {
                    appSettings.worktreeBaseRef = value
                }
                if let value = SettingsPersistence.load(Bool.self, from: "pr-tracking-settings.json") {
                    appSettings.githubPRTrackingEnabled = value
                }
                if let config = SettingsPersistence.load(
                    SettingsPersistence.PRPollingSettings.self, from: "pr-polling-settings.json")
                {
                    appSettings.prPollingIntervalSeconds = max(15, config.intervalSeconds)
                    appSettings.prRequestTimeoutSeconds = max(5, config.timeoutSeconds)
                    appSettings.prBackgroundRefreshEnabled = config.backgroundRefreshEnabled
                    appSettings.prBackgroundPollingIntervalSeconds = max(15, config.backgroundIntervalSeconds)
                }
                if let config = SettingsPersistence.load(
                    SettingsPersistence.TerminalSettings.self, from: "terminal-settings.json")
                {
                    appSettings.defaultScrollback = config.scrollback
                }
                if let value = SettingsPersistence.load(ExitBehavior.self, from: "exit-behavior.json") {
                    appSettings.exitBehavior = value
                }
                appSettings.envVarOptions = SettingsPersistence.mergeEnvVarOptions(
                    SettingsPersistence.loadFailableArray(EnvVarConfig.self, from: "env-var-settings.json"),
                    into: EnvVarConfig.all)
                appSettings.opencodeEnvVarOptions = SettingsPersistence.mergeEnvVarOptions(
                    SettingsPersistence.loadFailableArray(EnvVarConfig.self, from: "opencode-env-var-settings.json"),
                    into: EnvVarConfig.opencodeAll)
                if let config = SettingsPersistence.load(
                    SettingsPersistence.ProfilesContainer.self, from: "profiles.json")
                {
                    appSettings.profiles = config.profiles
                    if config.profiles.contains(where: {
                        $0.statusLineConfig?.needsPersistenceMigration == true
                    }) {
                        _ = SettingsPersistence.saveProfiles(appSettings: appSettings)
                    }
                }
                if let value = SettingsPersistence.load(Bool.self, from: "session-name-settings.json") {
                    appSettings.autoSetSessionName = value
                }
                if let config = SettingsPersistence.load(
                    SettingsPersistence.DebugSettings.self, from: "debug-settings.json"),
                    config.schemaVersion == 1
                {
                    appSettings.debugModeEnabled = config.enabled
                }
                if let config = SettingsPersistence.load(
                    SettingsPersistence.ShellSettings.self, from: "shell-settings.json")
                {
                    appSettings.preferredShell = config.preferredShell
                }
                if let config = SettingsPersistence.load(
                    SettingsPersistence.OnboardingSettings.self, from: "onboarding-settings.json")
                {
                    appSettings.hasCompletedOnboarding = config.completed
                }
                if let config = SettingsPersistence.load(
                    SettingsPersistence.ActivityIndicatorConfig.self, from: "activity-indicator-settings.json")
                {
                    appSettings.paneActivityIndicatorsEnabled = config.enabled
                }
                if let config = SettingsPersistence.load(
                    SettingsPersistence.FocusModeConfig.self, from: "focus-mode-settings.json")
                {
                    appSettings.focusModeTabSwitchBehavior = config.tabSwitchBehavior
                    appSettings.hideNotificationSidebarWhileFocused = config.hideNotificationSidebar
                }
                if let config = SettingsPersistence.load(
                    SettingsPersistence.UpdateCheckSettings.self, from: "update-check-settings.json")
                {
                    appSettings.updateReminderEnabled = config.enabled
                }
                if let config = SettingsPersistence.load(
                    AgentControlSettings.self, from: "agent-control-settings.json")
                {
                    appSettings.agentControlInjectionPolicy = config.injectionPolicy
                    appSettings.agentControlScope = config.scope
                }
                TracingService.shared.configure(from: appSettings)
                TracingService.shared.record(
                    "app.launched",
                    attributes: [
                        "previous_exit": launchLifecycleResult.previousExit.rawValue,
                        "marker_result": launchLifecycleResult.writeResult.rawValue,
                    ])
                InvariantReporter.shared.configure(from: appSettings)
            }
            await AgentControlService.shared.configure(appState: appState, appSettings: appSettings)
            await AgentControlService.shared.start()
            if !CommandLine.arguments.contains("--uitesting-skip-restore") {
                UpdateCheckCoordinator.shared.start()
                if let bundleIdentifier = Bundle.main.bundleIdentifier {
                    BundleIdentityVerifier.checkPreferredURL(
                        runningURL: Bundle.main.bundleURL,
                        preferredURL: NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: bundleIdentifier),
                        bundleIdentifier: bundleIdentifier)
                }
                let cleanup = TraceCleanupService(tracesDirectory: appSettings.resolvedTracingDirectoryURL)
                traceCleanupService = cleanup
                SessionPersistence.restore(into: appState, appSettings: appSettings)
                await SessionPersistence.checkForResolvedPRsAfterRestore(appState: appState)
            }
            await MacNotificationCoordinator.shared.requestAuthorizationIfNeeded()
            if !AgentSessionManagerApp.isUITesting
                || CommandLine.arguments.contains("--uitesting-show-onboarding")
            {
                showOnboarding = !appSettings.hasCompletedOnboarding
            }
        }
        .onChange(of: appState.tabs.count) { SessionPersistence.save(appState: appState) }
        .onChange(of: appState.activeTabID) { SessionPersistence.save(appState: appState) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.activePane?.terminalController?.focusTerminal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
            showingNewTab = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openShellHere)) { _ in
            guard let tab = appState.activeTab else { return }
            tab.openShellPane(activePane: appState.activePane, appState: appState, appSettings: appSettings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewPaneSettings)) { _ in
            guard let pane = appState.activePane else { return }
            handleViewPaneSettings(pane)
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
            closeActiveTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .prResolutionActionRequested)) { notif in
            guard
                let paneIDStr = notif.userInfo?["paneID"] as? String,
                let tabIDStr = notif.userInfo?["tabID"] as? String,
                let paneID = UUID(uuidString: paneIDStr),
                let tabID = UUID(uuidString: tabIDStr),
                let tab = appState.tabs.first(where: { $0.id == tabID }),
                let pane = tab.panes.first(where: { $0.id == paneID })
            else { return }
            if let kindStr = notif.userInfo?["kind"] as? String,
                let kind = NotificationKind(rawValue: kindStr)
            {
                pendingPRResolutionKind = kind
            }
            pendingPRResolutionPane = pane
            pendingPRResolutionTab = tab
            showPRResolutionAlert = true
        }
        .background(
            KeyboardShortcutView(
                appState: appState,
                appSettings: appSettings,
                onClosePane: closeActivePane,
                onCloseTab: closeActiveTab,
                onSwitchTab: switchTab,
                onRefreshPane: refreshActivePane
            )
        )
        .sheet(isPresented: $showOnboarding) {
            OnboardingWizardView()
                .environment(appSettings)
        }
        .sheet(isPresented: $showingNewTab) {
            NewTabSheet()
        }
        .sheet(
            item: $paneToRefresh,
            onDismiss: {
                paneForRefreshSettings = pendingRefreshSettings
                pendingRefreshSettings = nil
            },
            content: { pane in
                RefreshPaneSheet(
                    pane: pane,
                    onQuickRefresh: { pane in
                        pane.tab?.refreshPane(pane)
                    },
                    onRefreshWithSettings: { pane in
                        pendingRefreshSettings = pane
                    }
                )
            }
        )
        .sheet(item: $paneForRefreshSettings) { pane in
            if let tab = pane.tab {
                NewPaneSheet(tab: tab, refreshingPane: pane)
            }
        }
        .sheet(item: $paneForSettings) { pane in
            PaneSettingsView(snapshot: pane.settingsSnapshot(profiles: appSettings.profiles))
        }
        .alert("Close Worktree Pane", isPresented: $showCleanupAlert) {
            Button("Keep Worktree") {
                guard let pane = pendingCleanupPane, let tab = pendingCleanupTab else { return }
                pendingCleanupPane = nil
                pendingCleanupTab = nil
                tab.closePane(pane)
                SessionPersistence.save(appState: appState)
            }
            Button("Delete Worktree", role: .destructive) {
                guard let pane = pendingCleanupPane, let tab = pendingCleanupTab else { return }
                pendingCleanupPane = nil
                pendingCleanupTab = nil
                tab.closePane(pane)
                SessionPersistence.save(appState: appState)
                Task { try? await tab.cleanupWorktree(for: pane) }
            }
            Button("Cancel", role: .cancel) {
                pendingCleanupPane = nil
                pendingCleanupTab = nil
            }
        } message: {
            if let pane = pendingCleanupPane {
                Text("The worktree \"\(pane.name)\" was created by Agent Session Manager. Would you like to delete it?")
            }
        }
        .alert(
            pendingPRResolutionKind == .prMerged ? "PR Merged" : "PR Closed",
            isPresented: $showPRResolutionAlert
        ) {
            Button("Close Pane") {
                guard let pane = pendingPRResolutionPane, let tab = pendingPRResolutionTab else { return }
                pendingPRResolutionPane = nil
                pendingPRResolutionTab = nil
                appState.clearNotification(paneID: pane.id)
                tab.closePane(pane)
                SessionPersistence.save(appState: appState)
            }
            Button("Close Pane and Clean Up Worktree", role: .destructive) {
                guard let pane = pendingPRResolutionPane, let tab = pendingPRResolutionTab else { return }
                pendingPRResolutionPane = nil
                pendingPRResolutionTab = nil
                appState.clearNotification(paneID: pane.id)
                tab.closePane(pane)
                SessionPersistence.save(appState: appState)
                Task { try? await tab.cleanupWorktree(for: pane) }
            }
            Button("Cancel", role: .cancel) {
                if let pane = pendingPRResolutionPane, let tab = pendingPRResolutionTab {
                    appState.focusPane(tabID: tab.id, paneID: pane.id)
                    appState.clearNotification(paneID: pane.id)
                }
                pendingPRResolutionPane = nil
                pendingPRResolutionTab = nil
            }
        } message: {
            if let pane = pendingPRResolutionPane {
                let outcomeText =
                    pendingPRResolutionKind == .prMerged
                    ? "has been merged"
                    : "was closed without being merged"
                let prInfo = pane.statusLineMonitor?.currentData?.pr
                if let pr = prInfo {
                    let msg =
                        "PR #\(pr.number) \"\(pr.title)\" for pane \"\(pane.name)\" \(outcomeText). What would you like to do?"
                    Text(msg)
                } else {
                    Text("The PR for pane \"\(pane.name)\" \(outcomeText). What would you like to do?")
                }
            }
        }
    }

    private func closeActivePane() {
        guard let tab = appState.activeTab else { return }
        let pane = appState.activePane ?? tab.panes.last
        guard let pane else { return }
        handleClosePane(pane)
    }

    private func refreshActivePane() {
        guard let tab = appState.activeTab else { return }
        let pane = appState.activePane ?? tab.panes.last
        guard let pane, pane.harness != .shell else { return }
        handleRefreshPane(pane)
    }

    private func handleRefreshPane(_ pane: Pane) {
        paneToRefresh = pane
    }

    private func handleViewPaneSettings(_ pane: Pane) {
        paneForSettings = pane
    }

    private func handleClosePane(_ pane: Pane) {
        guard let tab = pane.tab else { return }
        switch appSettings.worktreeCleanupBehavior {
        case .ask where pane.worktreeIsManaged:
            pendingCleanupPane = pane
            pendingCleanupTab = tab
            showCleanupAlert = true
        case .delete where pane.worktreeIsManaged:
            tab.closePane(pane)
            SessionPersistence.save(appState: appState)
            Task { try? await tab.cleanupWorktree(for: pane) }
        default:
            tab.closePane(pane)
            SessionPersistence.save(appState: appState)
        }
    }

    private func switchTab(index: Int) {
        guard index < appState.tabs.count else { return }
        appState.switchToTab(
            id: appState.tabs[index].id,
            focusModeTabSwitchBehavior: appSettings.focusModeTabSwitchBehavior
        )
    }

    private func closeActiveTab() {
        guard let tab = appState.activeTab else { return }
        appState.closeTab(tab)
        SessionPersistence.save(appState: appState)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("Press ⌘T to create a tab")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("empty-state-hint")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GlobalSectionHandle: View {
    @Environment(AppState.self) private var appState
    let axis: ResizeAxis
    let identifier: String
    let label: String
    let value: Double
    let minimum: Double
    let maximum: Double
    var movementSign = 1.0
    let cancellationKey: String
    let onPreview: (Double?) -> Void
    let onCommit: (Double, String) -> Void
    let onReset: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        ResizeHandle(
            axis: axis,
            identifier: identifier,
            label: label,
            value: value,
            minimum: minimum,
            maximum: maximum,
            focusTarget: appState.activePane?.terminalController?.terminalView,
            movementSign: movementSign,
            cancellationKey: cancellationKey,
            onPreview: onPreview,
            onCommit: onCommit,
            onReset: onReset,
            onCancel: onCancel
        )
        .frame(width: axis == .columns ? 8 : nil, height: axis == .rows ? 8 : nil)
        .frame(maxWidth: axis == .rows ? .infinity : nil, maxHeight: axis == .columns ? .infinity : nil)
    }
}

enum WindowEventRouting {
    @MainActor
    static func shouldHandleMainWindowEvent(hostWindow: NSWindow?, eventWindow: NSWindow?) -> Bool {
        guard let hostWindow, let eventWindow else { return false }
        return hostWindow === eventWindow
    }
}

private final class WindowTrackingView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}

private struct KeyboardShortcutView: NSViewRepresentable {
    let appState: AppState
    let appSettings: AppSettings
    let onClosePane: () -> Void
    let onCloseTab: () -> Void
    let onSwitchTab: (Int) -> Void
    let onRefreshPane: () -> Void

    func makeNSView(context: Context) -> WindowTrackingView { WindowTrackingView() }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onClosePane = onClosePane
        coordinator.onCloseTab = onCloseTab
        coordinator.onSwitchTab = onSwitchTab
        coordinator.onRefreshPane = onRefreshPane
        coordinator.appState = appState
        coordinator.appSettings = appSettings
        nsView.onWindowChanged = { [weak coordinator] window in
            coordinator?.hostWindow = window
        }
        coordinator.hostWindow = nsView.window
        guard coordinator.keyMonitor == nil else { return }

        coordinator.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let shouldHandleEvent = WindowEventRouting.shouldHandleMainWindowEvent(
                hostWindow: coordinator.hostWindow,
                eventWindow: event.window
            )
            guard shouldHandleEvent else { return event }
            if let bindings = coordinator.appSettings?.layoutSettings.bindings,
                let appState = coordinator.appState,
                let pane = appState.activePane,
                let terminalView = pane.terminalController?.terminalView,
                let action = ResizeCommandRouting.action(
                    key: ResizeKeyBinding.key(for: event),
                    modifiers: event.modifierFlags,
                    bindings: bindings,
                    isMainWindow: true,
                    terminalHasFocus: coordinator.hostWindow?.firstResponder === terminalView,
                    hasAttachedSheet: coordinator.hostWindow?.attachedSheet != nil
                )
            {
                coordinator.activeResizeActions[action] = ResizeKeyBinding.key(for: event)
                NotificationCenter.default.post(
                    name: .paneResizeCommand,
                    object: nil,
                    userInfo: ["action": action, "paneID": pane.id]
                )
                return nil
            }
            let flags = event.modifierFlags.intersection([.shift, .command, .control, .option])
            if event.keyCode == 36 && flags == .shift,
                let termView = coordinator.appState?.activePane?.terminalController?.terminalView,
                !termView.terminal.keyboardEnhancementFlags.isEmpty
            {
                termView.send([0x1b, 0x5b, 0x31, 0x33, 0x3b, 0x32, 0x75])
                return nil
            }
            guard event.modifierFlags.contains(.command) else { return event }
            let closePaneKey = UserDefaults.standard.string(forKey: "keyBinding.closePaneKey") ?? "w"
            if let chars = event.characters, chars == closePaneKey {
                coordinator.onClosePane()
                return nil
            }
            let closeTabKey = UserDefaults.standard.string(forKey: "keyBinding.closeTabKey") ?? "k"
            if let chars = event.characters, chars == closeTabKey {
                coordinator.onCloseTab()
                return nil
            }
            let refreshPaneKey = UserDefaults.standard.string(forKey: "keyBinding.refreshPaneKey") ?? "r"
            if let chars = event.characters, chars == refreshPaneKey {
                coordinator.onRefreshPane()
                return nil
            }
            if let chars = event.characters, let digit = Int(chars), (1...9).contains(digit) {
                coordinator.onSwitchTab(digit - 1)
                return nil
            }
            return event
        }

        coordinator.keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            let shouldHandleEvent = WindowEventRouting.shouldHandleMainWindowEvent(
                hostWindow: coordinator.hostWindow,
                eventWindow: event.window
            )
            guard shouldHandleEvent else { return event }
            let key = ResizeKeyBinding.key(for: event)
            let released = coordinator.activeResizeActions.filter { $0.value == key }.map(\.key)
            for action in released {
                NotificationCenter.default.post(
                    name: .paneResizeReleased,
                    object: nil,
                    userInfo: ["action": action]
                )
                coordinator.activeResizeActions.removeValue(forKey: action)
            }
            return released.isEmpty ? event : nil
        }

        coordinator.windowLossObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: coordinator.hostWindow,
            queue: .main
        ) { [weak coordinator] _ in
            MainActor.assumeIsolated {
                guard let coordinator else { return }
                for action in Array(coordinator.activeResizeActions.keys) {
                    NotificationCenter.default.post(
                        name: .paneResizeReleased,
                        object: nil,
                        userInfo: ["action": action]
                    )
                }
                coordinator.activeResizeActions.removeAll()
            }
        }

        coordinator.mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let shouldHandleEvent = WindowEventRouting.shouldHandleMainWindowEvent(
                hostWindow: coordinator.hostWindow,
                eventWindow: event.window
            )
            guard shouldHandleEvent else { return event }
            for action in Array(coordinator.activeResizeActions.keys) {
                NotificationCenter.default.post(
                    name: .paneResizeReleased,
                    object: nil,
                    userInfo: ["action": action]
                )
            }
            coordinator.activeResizeActions.removeAll()
            if let hitView = event.window?.contentView?.hitTest(event.locationInWindow),
                hitView is ResizeHandleNativeView
            {
                return event
            }
            if let appState = coordinator.appState, let tab = appState.activeTab {
                let loc = event.locationInWindow
                for pane in tab.panes {
                    guard let termView = pane.terminalController?.terminalView else { continue }
                    let converted = termView.convert(loc, from: nil)
                    if termView.bounds.contains(converted) {
                        appState.setActivePane(id: pane.id)
                        break
                    }
                }
            }
            return event
        }

        coordinator.scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let shouldHandleEvent = WindowEventRouting.shouldHandleMainWindowEvent(
                hostWindow: coordinator.hostWindow,
                eventWindow: event.window
            )
            guard shouldHandleEvent else { return event }
            guard let window = event.window else { return event }
            guard abs(event.deltaY) >= 0.5 else { return event }
            let point = event.locationInWindow
            guard let hitView = window.contentView?.hitTest(point) else { return event }
            var view: NSView? = hitView
            while let current = view, !(current is BellCapturingTerminalView) {
                view = current.superview
            }
            guard let termView = view as? BellCapturingTerminalView else { return event }
            let terminal = termView.getTerminal()
            guard terminal.isCurrentBufferAlternate else { return event }
            guard terminal.mouseMode != .off else { return event }

            let localPoint = termView.convert(point, from: nil)
            let bw = termView.bounds.width
            let bh = termView.bounds.height
            guard bw > 0, bh > 0 else { return event }
            let cellX = max(0, min(terminal.cols - 1, Int(localPoint.x / bw * CGFloat(terminal.cols))))
            let terminalY = max(0, min(terminal.rows - 1, Int((1 - localPoint.y / bh) * CGFloat(terminal.rows))))
            let pixelX = Int(localPoint.x)
            let pixelY = Int(bh - localPoint.y)
            let flags = event.modifierFlags
            let pressFlags = terminal.encodeButton(
                button: event.deltaY > 0 ? 4 : 5,
                release: false,
                shift: flags.contains(.shift),
                meta: flags.contains(.option),
                control: flags.contains(.control)
            )
            terminal.sendEvent(buttonFlags: pressFlags, x: cellX, y: terminalY, pixelX: pixelX, pixelY: pixelY)
            return nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var onClosePane: () -> Void = {}
        var onCloseTab: () -> Void = {}
        var onSwitchTab: (Int) -> Void = { _ in }
        var onRefreshPane: () -> Void = {}
        var appState: AppState?
        var appSettings: AppSettings?
        var activeResizeActions: [ResizeAction: String] = [:]
        weak var hostWindow: NSWindow?
        nonisolated(unsafe) var keyMonitor: Any?
        nonisolated(unsafe) var keyUpMonitor: Any?
        nonisolated(unsafe) var mouseMonitor: Any?
        nonisolated(unsafe) var scrollWheelMonitor: Any?
        nonisolated(unsafe) var windowLossObserver: NSObjectProtocol?

        deinit {
            if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = keyUpMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = scrollWheelMonitor { NSEvent.removeMonitor(monitor) }
            if let windowLossObserver { NotificationCenter.default.removeObserver(windowLossObserver) }
        }
    }
}
