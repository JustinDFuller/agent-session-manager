import Foundation

private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct DefaultBranchConfig: Codable, Equatable {
    var isEnabled: Bool = true
    var branchName: String = "main"
}

struct NotificationConfig: Codable {
    var sidebarSide: SidebarSide
    var isPriorityEnabled: Bool
    var isMacOSBannerEnabled: Bool
    var isCursorHookAttentionEnabled: Bool
    var isPRMergedNotificationsEnabled: Bool
    var isPRClosedNotificationsEnabled: Bool
    var alwaysShowNotificationsSidebar: Bool
    var isClaudeStopNotificationEnabled: Bool
    var isOpencodeStopNotificationEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case sidebarSide
        case isPriorityEnabled
        case isMacOSBannerEnabled
        case isCursorHookAttentionEnabled
        case isPRMergedNotificationsEnabled
        case isPRClosedNotificationsEnabled
        case alwaysShowNotificationsSidebar
        case isClaudeStopNotificationEnabled
        case isOpencodeStopNotificationEnabled
    }

    init(
        sidebarSide: SidebarSide,
        isPriorityEnabled: Bool,
        isMacOSBannerEnabled: Bool,
        isCursorHookAttentionEnabled: Bool,
        isPRMergedNotificationsEnabled: Bool,
        isPRClosedNotificationsEnabled: Bool,
        alwaysShowNotificationsSidebar: Bool,
        isClaudeStopNotificationEnabled: Bool,
        isOpencodeStopNotificationEnabled: Bool
    ) {
        self.sidebarSide = sidebarSide
        self.isPriorityEnabled = isPriorityEnabled
        self.isMacOSBannerEnabled = isMacOSBannerEnabled
        self.isCursorHookAttentionEnabled = isCursorHookAttentionEnabled
        self.isPRMergedNotificationsEnabled = isPRMergedNotificationsEnabled
        self.isPRClosedNotificationsEnabled = isPRClosedNotificationsEnabled
        self.alwaysShowNotificationsSidebar = alwaysShowNotificationsSidebar
        self.isClaudeStopNotificationEnabled = isClaudeStopNotificationEnabled
        self.isOpencodeStopNotificationEnabled = isOpencodeStopNotificationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sidebarSide = try container.decodeIfPresent(SidebarSide.self, forKey: .sidebarSide) ?? .left
        isPriorityEnabled = try container.decodeIfPresent(Bool.self, forKey: .isPriorityEnabled) ?? true
        isMacOSBannerEnabled = try container.decodeIfPresent(Bool.self, forKey: .isMacOSBannerEnabled) ?? true
        isCursorHookAttentionEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .isCursorHookAttentionEnabled) ?? true
        isPRMergedNotificationsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .isPRMergedNotificationsEnabled) ?? true
        isPRClosedNotificationsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .isPRClosedNotificationsEnabled) ?? true
        alwaysShowNotificationsSidebar =
            try container.decodeIfPresent(Bool.self, forKey: .alwaysShowNotificationsSidebar) ?? true
        isClaudeStopNotificationEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .isClaudeStopNotificationEnabled) ?? true
        isOpencodeStopNotificationEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .isOpencodeStopNotificationEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sidebarSide, forKey: .sidebarSide)
        try container.encode(isPriorityEnabled, forKey: .isPriorityEnabled)
        try container.encode(isMacOSBannerEnabled, forKey: .isMacOSBannerEnabled)
        try container.encode(isCursorHookAttentionEnabled, forKey: .isCursorHookAttentionEnabled)
        try container.encode(isPRMergedNotificationsEnabled, forKey: .isPRMergedNotificationsEnabled)
        try container.encode(isPRClosedNotificationsEnabled, forKey: .isPRClosedNotificationsEnabled)
        try container.encode(alwaysShowNotificationsSidebar, forKey: .alwaysShowNotificationsSidebar)
        try container.encode(isClaudeStopNotificationEnabled, forKey: .isClaudeStopNotificationEnabled)
        try container.encode(isOpencodeStopNotificationEnabled, forKey: .isOpencodeStopNotificationEnabled)
    }
}

struct RestartConfig: Codable {
    var continueOnRestart: Bool = true
}

@MainActor
struct SettingsPersistence {
    nonisolated private static var appSupportDir: URL {
        let config = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = config.appending(path: PersistenceHelpers.appSupportSubdirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var settingsURL: URL { appSupportDir.appending(path: "settings.json") }
    private static var codexSettingsURL: URL { appSupportDir.appending(path: "codex-settings.json") }
    private static var cursorSettingsURL: URL { appSupportDir.appending(path: "cursor-settings.json") }
    private static var opencodeSettingsURL: URL { appSupportDir.appending(path: "opencode-settings.json") }
    private static var statusLineSettingsURL: URL { appSupportDir.appending(path: "statusline-settings.json") }
    private static var layoutSettingsURL: URL { appSupportDir.appending(path: "layout-settings.json") }
    private static var activeToolsURL: URL { appSupportDir.appending(path: "active-tools-settings.json") }
    private static var defaultBranchURL: URL { appSupportDir.appending(path: "default-branch.json") }
    private static var notificationSettingsURL: URL { appSupportDir.appending(path: "notification-settings.json") }
    private static var restartSettingsURL: URL { appSupportDir.appending(path: "restart-settings.json") }
    private static var worktreeCleanupURL: URL { appSupportDir.appending(path: "worktree-cleanup.json") }
    private static var existingWorktreeManagementURL: URL {
        appSupportDir.appending(path: "existing-worktree-management.json")
    }
    private static var debugSettingsURL: URL { appSupportDir.appending(path: "debug-settings.json") }
    private static var prTrackingSettingsURL: URL { appSupportDir.appending(path: "pr-tracking-settings.json") }
    private static var terminalSettingsURL: URL { appSupportDir.appending(path: "terminal-settings.json") }
    private static var prPollingSettingsURL: URL { appSupportDir.appending(path: "pr-polling-settings.json") }
    private static var worktreeBaseRefURL: URL { appSupportDir.appending(path: "worktree-base-ref.json") }
    private static var exitBehaviorURL: URL { appSupportDir.appending(path: "exit-behavior.json") }
    private static var envVarSettingsURL: URL { appSupportDir.appending(path: "env-var-settings.json") }
    private static var opencodeEnvVarSettingsURL: URL {
        appSupportDir.appending(path: "opencode-env-var-settings.json")
    }
    private static var profilesURL: URL { appSupportDir.appending(path: "profiles.json") }
    private static var sessionNameSettingsURL: URL { appSupportDir.appending(path: "session-name-settings.json") }
    private static var shellSettingsURL: URL { appSupportDir.appending(path: "shell-settings.json") }
    private static var onboardingSettingsURL: URL { appSupportDir.appending(path: "onboarding-settings.json") }
    private static var activityIndicatorSettingsURL: URL {
        appSupportDir.appending(path: "activity-indicator-settings.json")
    }
    private static var focusModeSettingsURL: URL { appSupportDir.appending(path: "focus-mode-settings.json") }
    private static var updateCheckSettingsURL: URL { appSupportDir.appending(path: "update-check-settings.json") }
    private static var agentControlSettingsURL: URL { appSupportDir.appending(path: "agent-control-settings.json") }

    static func save<Value: Encodable>(_ value: Value, to filename: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: appSupportDir.appending(path: filename))
    }

    @discardableResult
    static func saveLayout(appSettings: AppSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(appSettings.layoutSettings) else {
            appSettings.layoutSaveError = "Could not save layout settings. Changes remain active until the app closes."
            LayoutResizeTelemetry.record(
                event: "persistence_failed",
                section: "global",
                axis: .columns,
                source: "settings",
                before: 0,
                after: 0,
                result: "encode_failed"
            )
            return false
        }
        do {
            try data.write(to: layoutSettingsURL, options: .atomic)
            appSettings.layoutSaveError = nil
            return true
        } catch {
            appSettings.layoutSaveError = "Could not save layout settings. Changes remain active until the app closes."
            LayoutResizeTelemetry.record(
                event: "persistence_failed",
                section: "global",
                axis: .columns,
                source: "settings",
                before: 0,
                after: 0,
                result: "write_failed"
            )
            return false
        }
    }

    static func saveDebugSettings(enabled: Bool) -> Bool {
        guard let data = try? JSONEncoder().encode(DebugSettings(schemaVersion: 1, enabled: enabled)) else {
            return false
        }
        do {
            try data.write(to: debugSettingsURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    nonisolated static func load<Value: Decodable>(_ type: Value.Type, from filename: String) -> Value? {
        guard let data = try? Data(contentsOf: appSupportDir.appending(path: filename)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func loadFailableArray<Value: Decodable>(_ type: Value.Type, from filename: String) -> [Value] {
        guard let data = try? Data(contentsOf: appSupportDir.appending(path: filename)) else { return [] }
        return
            (try? JSONDecoder().decode([FailableDecodable<Value>].self, from: data))?
            .compactMap(\.value) ?? []
    }

    static func loadCLIOptions(from filename: String, harness: Harness) -> [CLIOptionConfig] {
        guard let data = try? Data(contentsOf: appSupportDir.appending(path: filename)) else { return [] }
        let decoder = JSONDecoder()
        decoder.userInfo[CLIOptionConfig.harnessUserInfoKey] = harness
        return
            (try? decoder.decode([FailableDecodable<CLIOptionConfig>].self, from: data))?
            .compactMap(\.value) ?? []
    }

    static func mergeCLIOptions(_ saved: [CLIOptionConfig], into defaults: [CLIOptionConfig]) -> [CLIOptionConfig] {
        var updated = defaults
        var userAdded: [CLIOptionConfig] = []
        for savedOption in saved {
            if savedOption.isUserAdded {
                userAdded.append(savedOption)
            } else if let index = updated.firstIndex(where: { $0.id == savedOption.id }) {
                updated[index].isAvailable = savedOption.isAvailable
                updated[index].isDefaultEnabled = savedOption.isDefaultEnabled
                updated[index].presetValues = savedOption.presetValues
                updated[index].allowsMultipleValues = savedOption.allowsMultipleValues
            }
        }
        return updated + userAdded
    }

    static func mergeEnvVarOptions(_ saved: [EnvVarConfig], into defaults: [EnvVarConfig]) -> [EnvVarConfig] {
        var updated = defaults
        var userAdded: [EnvVarConfig] = []
        for saved in saved {
            if saved.isUserAdded {
                userAdded.append(saved)
            } else if let index = updated.firstIndex(where: { $0.id == saved.id }) {
                updated[index].isAvailable = saved.isAvailable
                updated[index].isDefaultEnabled = saved.isDefaultEnabled
                updated[index].defaultValue = saved.defaultValue
            }
        }
        return updated + userAdded
    }

    @discardableResult
    static func save(appSettings: AppSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(appSettings.cliOptions) else { return false }
        do {
            try data.write(to: settingsURL, options: .atomic)
            return true
        } catch { return false }
    }

    @discardableResult
    static func saveCodexOptions(appSettings: AppSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(appSettings.codexCliOptions) else { return false }
        do {
            try data.write(to: codexSettingsURL, options: .atomic)
            return true
        } catch { return false }
    }

    @discardableResult
    static func saveCursorOptions(appSettings: AppSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(appSettings.cursorCliOptions) else { return false }
        do {
            try data.write(to: cursorSettingsURL, options: .atomic)
            return true
        } catch { return false }
    }

    @discardableResult
    static func saveOpenCodeOptions(appSettings: AppSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(appSettings.opencodeCliOptions) else { return false }
        do {
            try data.write(to: opencodeSettingsURL, options: .atomic)
            return true
        } catch { return false }
    }

    static func saveOpenCodeEnvVars(appSettings: AppSettings) {
        guard let data = try? JSONEncoder().encode(appSettings.opencodeEnvVarOptions) else { return }
        try? data.write(to: opencodeEnvVarSettingsURL)
    }

    @discardableResult
    static func saveActiveTools(appSettings: AppSettings) -> Bool {
        let sorted = appSettings.activeTools.sorted()
        guard let data = try? JSONEncoder().encode(sorted) else { return false }
        do {
            try data.write(to: activeToolsURL, options: .atomic)
            return true
        } catch { return false }
    }

    @discardableResult
    static func saveStatusLine(appSettings: AppSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(appSettings.statusLineConfig) else { return false }
        do {
            try data.write(to: statusLineSettingsURL, options: .atomic)
            if appSettings.statusLineConfig.needsPersistenceMigration {
                appSettings.statusLineConfig.markPersistenceMigrationHandled()
            }
            return true
        } catch {
            return false
        }
    }

    static func saveDefaultBranch(appSettings: AppSettings) {
        let config = DefaultBranchConfig(
            isEnabled: appSettings.isDefaultBranchEnabled, branchName: appSettings.defaultBranch)
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: defaultBranchURL)
    }

    static func saveNotificationSettings(appSettings: AppSettings) {
        let config = NotificationConfig(
            sidebarSide: appSettings.notificationSidebarSide,
            isPriorityEnabled: appSettings.isPriorityNotificationsEnabled,
            isMacOSBannerEnabled: appSettings.isMacOSBannerNotificationsEnabled,
            isCursorHookAttentionEnabled: appSettings.isCursorNotificationHookAttentionEnabled,
            isPRMergedNotificationsEnabled: appSettings.isPRMergedNotificationsEnabled,
            isPRClosedNotificationsEnabled: appSettings.isPRClosedNotificationsEnabled,
            alwaysShowNotificationsSidebar: appSettings.alwaysShowNotificationsSidebar,
            isClaudeStopNotificationEnabled: appSettings.isClaudeStopNotificationEnabled,
            isOpencodeStopNotificationEnabled: appSettings.isOpencodeStopNotificationEnabled
        )
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: notificationSettingsURL)
    }

    static func isClaudeStopNotificationEnabled() -> Bool {
        guard
            let data = try? Data(contentsOf: notificationSettingsURL),
            let config = try? JSONDecoder().decode(NotificationConfig.self, from: data)
        else { return true }
        return config.isClaudeStopNotificationEnabled
    }

    static func isOpencodeStopNotificationEnabled() -> Bool {
        guard
            let data = try? Data(contentsOf: notificationSettingsURL),
            let config = try? JSONDecoder().decode(NotificationConfig.self, from: data)
        else { return true }
        return config.isOpencodeStopNotificationEnabled
    }

    static func isPRMergedNotificationsEnabled() -> Bool {
        guard
            let data = try? Data(contentsOf: notificationSettingsURL),
            let config = try? JSONDecoder().decode(NotificationConfig.self, from: data)
        else { return true }
        return config.isPRMergedNotificationsEnabled
    }

    static func isPRClosedNotificationsEnabled() -> Bool {
        guard
            let data = try? Data(contentsOf: notificationSettingsURL),
            let config = try? JSONDecoder().decode(NotificationConfig.self, from: data)
        else { return true }
        return config.isPRClosedNotificationsEnabled
    }

    struct DebugSettings: Codable {
        var schemaVersion: Int
        var enabled: Bool = false
    }

    static func isPRTrackingEnabled() -> Bool {
        guard
            let data = try? Data(contentsOf: prTrackingSettingsURL),
            let enabled = try? JSONDecoder().decode(Bool.self, from: data)
        else { return true }
        return enabled
    }

    struct TerminalSettings: Codable {
        var scrollback: ScrollbackLimit = .defaultValue

        private enum CodingKeys: String, CodingKey {
            case scrollback
            case scrollbackLines
        }

        init(scrollback: ScrollbackLimit = .defaultValue) {
            self.scrollback = scrollback
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let scrollback = try container.decodeIfPresent(
                ScrollbackLimit.self,
                forKey: .scrollback
            ) {
                self.scrollback = scrollback
            } else if let legacyLines = try container.decodeIfPresent(
                Int.self,
                forKey: .scrollbackLines
            ) {
                scrollback = ScrollbackLimit(finiteLines: legacyLines)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(scrollback, forKey: .scrollback)
        }
    }

    struct PRPollingSettings: Codable {
        var intervalSeconds: Int = 30
        var timeoutSeconds: Int = 15
        var backgroundRefreshEnabled: Bool = true
        var backgroundIntervalSeconds: Int = 60
    }

    static func savePRPollingSettings(appSettings: AppSettings) {
        let payload = PRPollingSettings(
            intervalSeconds: appSettings.prPollingIntervalSeconds,
            timeoutSeconds: appSettings.prRequestTimeoutSeconds,
            backgroundRefreshEnabled: appSettings.prBackgroundRefreshEnabled,
            backgroundIntervalSeconds: appSettings.prBackgroundPollingIntervalSeconds
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: prPollingSettingsURL)
    }

    static func prPollingSettings() -> PRPollingSettings {
        guard
            let data = try? Data(contentsOf: prPollingSettingsURL),
            let settings = try? JSONDecoder().decode(PRPollingSettings.self, from: data)
        else { return PRPollingSettings() }
        return PRPollingSettings(
            intervalSeconds: max(15, settings.intervalSeconds),
            timeoutSeconds: max(5, settings.timeoutSeconds),
            backgroundRefreshEnabled: settings.backgroundRefreshEnabled,
            backgroundIntervalSeconds: max(15, settings.backgroundIntervalSeconds)
        )
    }

    static func saveEnvVarOptions(appSettings: AppSettings) {
        guard let data = try? JSONEncoder().encode(appSettings.envVarOptions) else { return }
        try? data.write(to: envVarSettingsURL)
    }

    struct ProfilesContainer: Codable {
        var profiles: [Profile]
    }

    @discardableResult
    static func saveProfiles(appSettings: AppSettings) -> Bool {
        let container = ProfilesContainer(profiles: appSettings.profiles)
        let enabledCLIOptionCount = appSettings.profiles
            .flatMap(\.cliOptions)
            .filter(\.isEnabled)
            .count
        let enabledEnvironmentVariableCount = appSettings.profiles
            .flatMap(\.envVars)
            .filter(\.isEnabled)
            .count
        var telemetryAttributes = [
            "profile.count": "\(appSettings.profiles.count)",
            "profile.enabled_cli_option.count": "\(enabledCLIOptionCount)",
            "profile.enabled_env_var.count": "\(enabledEnvironmentVariableCount)",
        ]
        guard let data = try? JSONEncoder().encode(container) else {
            telemetryAttributes["result"] = "encode_failed"
            TracingService.shared.record("profile.save", attributes: telemetryAttributes)
            return false
        }
        do {
            try data.write(to: profilesURL, options: .atomic)
            for index in appSettings.profiles.indices {
                appSettings.profiles[index].statusLineConfig?.markPersistenceMigrationHandled()
            }
            telemetryAttributes["result"] = "success"
            TracingService.shared.record("profile.save", attributes: telemetryAttributes)
            return true
        } catch {
            telemetryAttributes["result"] = "write_failed"
            TracingService.shared.record("profile.save", attributes: telemetryAttributes)
            return false
        }
    }

    struct ShellSettings: Codable {
        var preferredShell: String = ""
    }

    static func saveShellSettings(appSettings: AppSettings) {
        let payload = ShellSettings(preferredShell: appSettings.preferredShell)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: shellSettingsURL)
    }

    struct OnboardingSettings: Codable {
        var completed: Bool = false
    }

    struct ActivityIndicatorConfig: Codable {
        var enabled: Bool = true

        enum CodingKeys: String, CodingKey {
            case enabled
        }

        init(enabled: Bool) {
            self.enabled = enabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enabled, forKey: .enabled)
        }
    }

    struct FocusModeConfig: Codable {
        var tabSwitchBehavior: FocusModeTabSwitchBehavior = .rememberFocus
        var hideNotificationSidebar: Bool = true
    }

    static func saveFocusModeSettings(appSettings: AppSettings) {
        let payload = FocusModeConfig(
            tabSwitchBehavior: appSettings.focusModeTabSwitchBehavior,
            hideNotificationSidebar: appSettings.hideNotificationSidebarWhileFocused
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: focusModeSettingsURL)
    }

    struct UpdateCheckSettings: Codable {
        var enabled: Bool = true
    }

    static func saveUpdateCheckSettings(appSettings: AppSettings) {
        let payload = UpdateCheckSettings(enabled: appSettings.updateReminderEnabled)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: updateCheckSettingsURL)
    }

    static func saveAgentControlSettings(appSettings: AppSettings) {
        let payload = AgentControlSettings(
            injectionPolicy: appSettings.agentControlInjectionPolicy,
            scope: appSettings.agentControlScope
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: agentControlSettingsURL)
    }

    static func isUpdateReminderEnabled() -> Bool {
        guard
            let data = try? Data(contentsOf: updateCheckSettingsURL),
            let settings = try? JSONDecoder().decode(UpdateCheckSettings.self, from: data)
        else { return true }
        return settings.enabled
    }
}
