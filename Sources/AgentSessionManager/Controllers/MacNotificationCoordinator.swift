import AppKit
@preconcurrency import UserNotifications

enum MacNotificationUserInfoKey {
    static let paneID = "paneID"
    static let tabID = "tabID"
    static let notificationKind = "notificationKind"
}

@MainActor
final class MacNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MacNotificationCoordinator()

    private weak var appState: AppState?
    private weak var appSettings: AppSettings?

    private(set) var isHandlingNotificationResponse = false

    private var lastChimeAt: [UUID: Date] = [:]
    private var outstanding: [UUID: (reason: String, isSpecific: Bool)] = [:]
    private static let coalesceCooldown: TimeInterval = 6

    struct CoalesceDecision: Equatable {
        let silent: Bool
        let reason: String
        let isSpecific: Bool
    }

    static func decideCoalesce(
        now: Date, cooldown: TimeInterval,
        lastChimeAt: Date?, outstanding: (reason: String, isSpecific: Bool)?,
        incomingSource: PaneAttentionEvent.Source, incomingReason: String
    ) -> CoalesceDecision {
        let incomingSpecific =
            incomingSource != .claudeStop && incomingSource != .cursorStop
            && incomingSource != .codexStop
        let withinCooldown = lastChimeAt.map { now.timeIntervalSince($0) < cooldown } ?? false
        let silent = outstanding != nil || withinCooldown
        if let outstanding, outstanding.isSpecific, !incomingSpecific {
            return CoalesceDecision(silent: silent, reason: outstanding.reason, isSpecific: true)
        }
        return CoalesceDecision(silent: silent, reason: incomingReason, isSpecific: incomingSpecific)
    }

    func bind(appState: AppState, appSettings: AppSettings) {
        self.appState = appState
        self.appSettings = appSettings
    }

    static func bundleAppIcon(in bundle: Bundle = .main) -> NSImage? {
        let name = (bundle.infoDictionary?["CFBundleIconFile"] as? String) ?? "AppIcon"
        if let url = bundle.url(forResource: name, withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        if bundle == .main, let app = NSApp {
            return app.applicationIconImage
        }
        return nil
    }

    nonisolated static func escapedBannerBody(_ value: String) -> String {
        value.replacingOccurrences(of: "%", with: "%%")
    }

    nonisolated static func makePaneAttentionContent(
        tabName: String, paneName: String, reason: String
    )
        -> UNMutableNotificationContent
    {
        let content = UNMutableNotificationContent()
        content.title = tabName
        content.subtitle = paneName
        content.body = escapedBannerBody(reason)
        return content
    }

    nonisolated static func makePRMergedContent(
        tabName: String, paneName: String, prNumber: Int, prTitle: String
    )
        -> UNMutableNotificationContent
    {
        let content = UNMutableNotificationContent()
        content.title = tabName
        content.subtitle = paneName
        content.body = escapedBannerBody("PR #\(prNumber) merged: \(prTitle)")
        return content
    }

    nonisolated static func makePRClosedContent(
        tabName: String, paneName: String, prNumber: Int, prTitle: String
    )
        -> UNMutableNotificationContent
    {
        let content = UNMutableNotificationContent()
        content.title = tabName
        content.subtitle = paneName
        content.body = escapedBannerBody("PR #\(prNumber) closed: \(prTitle)")
        return content
    }

    func requestAuthorizationIfNeeded() async {
        guard !AgentSessionManagerApp.isUITesting else { return }
        guard let appSettings = self.appSettings else { return }
        guard appSettings.isMacOSBannerNotificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            TracingService.shared.record(
                "notification.auth.requested",
                attributes: Self.errorAttributes(error, result: "request_error"))
            return
        }
        TracingService.shared.record(
            "notification.auth.requested",
            attributes: ["result": granted ? "authorized" : "denied"])
    }

    func postPaneAttentionIfNeeded(
        paneID: UUID,
        paneName: String,
        tabID: UUID,
        tabName: String,
        reason: String,
        source: PaneAttentionEvent.Source
    ) {
        guard let appSettings = self.appSettings else { return }
        guard appSettings.isMacOSBannerNotificationsEnabled else { return }
        guard !AgentSessionManagerApp.isUITesting else { return }
        let now = Date()
        let decision = Self.decideCoalesce(
            now: now, cooldown: Self.coalesceCooldown,
            lastChimeAt: lastChimeAt[paneID], outstanding: outstanding[paneID],
            incomingSource: source, incomingReason: reason
        )
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            guard settings.alertSetting == .enabled else { return }
            let content = Self.makePaneAttentionContent(
                tabName: tabName, paneName: paneName, reason: decision.reason)
            content.sound = decision.silent ? nil : .default
            content.userInfo = [
                MacNotificationUserInfoKey.paneID: paneID.uuidString,
                MacNotificationUserInfoKey.tabID: tabID.uuidString,
            ]
            let identifier = "pane-\(paneID.uuidString)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            let paneAttributes = Self.paneAttributes(
                paneID: paneID, paneName: paneName, tabID: tabID, tabName: tabName)
            do {
                try await center.add(request)
                if !decision.silent {
                    lastChimeAt[paneID] = now
                }
                outstanding[paneID] = (decision.reason, decision.isSpecific)
                TracingService.shared.record(
                    "notification.pane_attention.posted",
                    attributes: paneAttributes.merging([
                        "reason": decision.reason,
                        "source": source.rawValue,
                        "result": "posted",
                        "coalesced": decision.silent ? "true" : "false",
                    ]) { _, new in new })
            } catch {
                TracingService.shared.record(
                    "notification.pane_attention.skipped",
                    attributes: paneAttributes.merging(
                        Self.errorAttributes(error, result: "schedule_error")
                    ) { _, new in new })
            }
        }
    }

    func postPRMergedBannerIfNeeded(
        paneID: UUID,
        paneName: String,
        tabID: UUID,
        tabName: String,
        prNumber: Int,
        prTitle: String
    ) {
        guard let appSettings = self.appSettings, appSettings.isMacOSBannerNotificationsEnabled else { return }
        guard !AgentSessionManagerApp.isUITesting else { return }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            guard settings.alertSetting == .enabled else { return }
            let content = Self.makePRMergedContent(
                tabName: tabName, paneName: paneName, prNumber: prNumber, prTitle: prTitle)
            content.sound = .default
            content.userInfo = [
                MacNotificationUserInfoKey.paneID: paneID.uuidString,
                MacNotificationUserInfoKey.tabID: tabID.uuidString,
                MacNotificationUserInfoKey.notificationKind: NotificationKind.prMerged.rawValue,
            ]
            let identifier = "pr-merged-\(paneID.uuidString)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            let paneAttributes = Self.paneAttributes(
                paneID: paneID, paneName: paneName, tabID: tabID, tabName: tabName)
            do {
                try await center.add(request)
                TracingService.shared.record(
                    "notification.pr_merged.posted",
                    attributes: paneAttributes.merging([
                        "pr.title": prTitle,
                        "result": "posted",
                    ]) { _, new in new })
            } catch {
                TracingService.shared.record(
                    "notification.pr_merged.skipped",
                    attributes: paneAttributes.merging(
                        Self.errorAttributes(error, result: "schedule_error")
                    ) { _, new in new })
            }
        }
    }

    func postPRClosedBannerIfNeeded(
        paneID: UUID,
        paneName: String,
        tabID: UUID,
        tabName: String,
        prNumber: Int,
        prTitle: String
    ) {
        guard let appSettings = self.appSettings, appSettings.isMacOSBannerNotificationsEnabled else { return }
        guard !AgentSessionManagerApp.isUITesting else { return }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            guard settings.alertSetting == .enabled else { return }
            let content = Self.makePRClosedContent(
                tabName: tabName, paneName: paneName, prNumber: prNumber, prTitle: prTitle)
            content.sound = .default
            content.userInfo = [
                MacNotificationUserInfoKey.paneID: paneID.uuidString,
                MacNotificationUserInfoKey.tabID: tabID.uuidString,
                MacNotificationUserInfoKey.notificationKind: NotificationKind.prClosed.rawValue,
            ]
            let identifier = "pr-closed-\(paneID.uuidString)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            let paneAttributes = Self.paneAttributes(
                paneID: paneID, paneName: paneName, tabID: tabID, tabName: tabName)
            do {
                try await center.add(request)
                TracingService.shared.record(
                    "notification.pr_closed.posted",
                    attributes: paneAttributes.merging([
                        "pr.title": prTitle,
                        "result": "posted",
                    ]) { _, new in new })
            } catch {
                TracingService.shared.record(
                    "notification.pr_closed.skipped",
                    attributes: paneAttributes.merging(
                        Self.errorAttributes(error, result: "schedule_error")
                    ) { _, new in new })
            }
        }
    }

    func removeDeliveredNotifications(forPaneID paneID: UUID) {
        markPaneAcknowledged(paneID: paneID)
        guard appSettings != nil else { return }
        guard !AgentSessionManagerApp.isUITesting else { return }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            center.removeDeliveredNotifications(withIdentifiers: [
                "pane-\(paneID.uuidString)",
                "pr-merged-\(paneID.uuidString)",
                "pr-closed-\(paneID.uuidString)",
            ])
        }
    }

    func markPaneAcknowledged(paneID: UUID) {
        outstanding[paneID] = nil
    }

    func forgetPane(paneID: UUID) {
        outstanding[paneID] = nil
        lastChimeAt[paneID] = nil
    }

    @discardableResult
    func handleNotificationNavigation(paneIDStr: String, tabIDStr: String, kind: String?) -> String {
        guard
            let paneID = UUID(uuidString: paneIDStr),
            let tabID = UUID(uuidString: tabIDStr)
        else { return "invalid_context" }
        guard let state = appState else { return "state_unavailable" }
        state.focusPane(tabID: tabID, paneID: paneID)
        if let kind, kind == NotificationKind.prMerged.rawValue || kind == NotificationKind.prClosed.rawValue {
            NotificationCenter.default.post(
                name: .prResolutionActionRequested,
                object: nil,
                userInfo: ["paneID": paneIDStr, "tabID": tabIDStr, "kind": kind]
            )
        }
        return "navigated"
    }

    func handleNotificationResponse(paneIDStr: String?, tabIDStr: String?, kind: String?) {
        guard let paneIDStr, let tabIDStr else {
            TracingService.shared.record(
                "notification.response.navigation",
                attributes: ["result": "missing_context"])
            return
        }
        let tab = UUID(uuidString: tabIDStr).flatMap { tabID in
            appState?.tabs.first { $0.id == tabID }
        }
        let pane = UUID(uuidString: paneIDStr).flatMap { paneID in
            tab?.panes.first { $0.id == paneID }
        }
        isHandlingNotificationResponse = true
        defer { isHandlingNotificationResponse = false }

        #if DEV_BUILD
        WindowSnapshot.record(
            event: "notification.click.handler_entered",
            extra: [
                "paneID": paneIDStr,
                "tabID": tabIDStr,
                "kind": kind ?? "paneAttention",
            ])
        #endif

        let result = handleNotificationNavigation(paneIDStr: paneIDStr, tabIDStr: tabIDStr, kind: kind)
        TracingService.shared.record(
            "notification.response.navigation",
            attributes: [
                "pane.id": paneIDStr,
                "pane.name": pane?.name ?? "unknown",
                "tab.id": tabIDStr,
                "tab.name": tab?.name ?? "unknown",
                "notification.kind": kind ?? "attention",
                "result": result,
            ])

        #if DEV_BUILD
        WindowSnapshot.record(event: "notification.click.after_navigation")
        #endif

        (NSApp.delegate as? AppDelegate)?.focusMainWindow()

        #if DEV_BUILD
        WindowSnapshot.record(event: "notification.click.after_focus")
        #endif
    }

    nonisolated static func paneAttributes(
        paneID: UUID, paneName: String, tabID: UUID, tabName: String
    ) -> [String: String] {
        [
            "pane.id": paneID.uuidString,
            "pane.name": paneName,
            "tab.id": tabID.uuidString,
            "tab.name": tabName,
        ]
    }

    nonisolated static func errorAttributes(_ error: Error, result: String) -> [String: String] {
        let nsError = error as NSError
        return [
            "error.domain": String(nsError.domain.prefix(128)),
            "error.code": String(nsError.code),
            "result": result,
        ]
    }

    nonisolated static let willPresentPresentationOptions: UNNotificationPresentationOptions = [.banner, .sound]

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.willPresentPresentationOptions)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let paneIDStr = userInfo[MacNotificationUserInfoKey.paneID] as? String
        let tabIDStr = userInfo[MacNotificationUserInfoKey.tabID] as? String
        let kind = userInfo[MacNotificationUserInfoKey.notificationKind] as? String
        completionHandler()
        Task { @MainActor in
            MacNotificationCoordinator.shared.handleNotificationResponse(
                paneIDStr: paneIDStr,
                tabIDStr: tabIDStr,
                kind: kind
            )
        }
    }
}
