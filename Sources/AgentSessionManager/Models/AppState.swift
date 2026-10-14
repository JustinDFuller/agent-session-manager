import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var tabs: [Tab] = []
    var activeTabID: UUID?
    var activePaneID: UUID?
    var notifications: [PaneNotification] = []
    let worktreeCloseFlow = WorktreeCloseFlow()

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    var activePane: Pane? {
        activeTab?.panes.first { $0.id == activePaneID }
    }

    func switchToTab(id: UUID, focusModeTabSwitchBehavior: FocusModeTabSwitchBehavior = .rememberFocus) {
        if focusModeTabSwitchBehavior == .showAllPanes {
            activeTab?.setFocusedPane(id: nil, reason: "tab_switched")
        }
        activeTab?.lastActivePaneID = activePaneID
        activeTabID = id
        let focused = activeTab?.focusedPaneID
        let saved = activeTab?.lastActivePaneID
        activePaneID =
            activeTab?.panes.first(where: { $0.id == focused })?.id
            ?? activeTab?.panes.first(where: { $0.id == saved })?.id
            ?? activeTab?.panes.first?.id
    }

    func setActivePane(id: UUID?) {
        activeTab?.lastActivePaneID = id
        activePaneID = id
        if let id {
            clearNotification(paneID: id)
            MacNotificationCoordinator.shared.removeDeliveredNotifications(forPaneID: id)
        }
    }

    func isCheckoutInUse(checkout: URL, excludingPaneIDs: Set<UUID> = []) -> Bool {
        let resolved = checkout.resolvingSymlinksInPath().path
        return tabs.contains { tab in
            tab.panes.contains { pane in
                if excludingPaneIDs.contains(pane.id) { return false }
                return pane.worktreePath?.resolvingSymlinksInPath().path == resolved
            }
        }
    }

    func requestClose(
        _ target: WorktreeCloseTarget, decision: WorktreeCleanupDecision = .followSetting, appSettings: AppSettings
    ) {
        worktreeCloseFlow.begin(target, decision: decision, appState: self, appSettings: appSettings)
    }

    func closeTab(_ tab: Tab) {
        let paneIDs = Set(tab.panes.map(\.id))
        for pane in tab.panes {
            AgentControlService.shared.revoke(
                paneID: pane.id,
                paneName: pane.name,
                tabID: tab.id,
                tabName: tab.name
            )
            pane.terminalController?.terminate()
            CursorAgentControlPlugin.remove(directory: pane.cursorAgentControlPluginDirectory)
            pane.cursorAgentControlPluginDirectory = nil
            pane.installTerminalController(nil)
            pane.removeStatusLineMonitor()
            MacNotificationCoordinator.shared.forgetPane(paneID: pane.id)
        }
        notifications.removeAll { paneIDs.contains($0.paneID) }
        tabs.removeAll { $0.id == tab.id }
        if activeTabID == tab.id {
            activeTabID = tabs.last?.id
            activePaneID = activeTab?.panes.first?.id
        }
        SessionPersistence.save(appState: self)
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        SessionPersistence.save(appState: self)
    }

    func configureCursorAttentionWatchers(enabled: Bool) {
        for pane in tabs.flatMap(\.panes) where pane.harness == .cursor {
            pane.statusLineMonitor?.configureCursorAttentionWatcher(enabled: enabled)
        }
        TracingService.shared.record(
            "statusline.cursor.attention_setting.applied",
            attributes: [
                "enabled": enabled ? "true" : "false",
                "cursor_pane_count": "\(tabs.flatMap(\.panes).filter { $0.harness == .cursor }.count)",
            ])
    }

    func addNotification(
        paneID: UUID, paneName: String, tabID: UUID, tabName: String, isPriority: Bool,
        event: PaneAttentionEvent = .rawBell
    ) {
        if notifications.contains(where: {
            $0.paneID == paneID && ($0.kind == .prMerged || $0.kind == .prClosed)
        }) {
            return
        }
        let kind: NotificationKind = {
            switch event.source {
            case .claudeStop: return .claudeStop
            case .cursorStop: return .cursorStop
            case .opencodeStop: return .opencodeStop
            case .opencodePermissionRequest: return .opencodePermissionRequest
            default: return .terminalBell
            }
        }()
        let notification =
            PaneNotification(
                paneID: paneID,
                paneName: paneName,
                tabID: tabID,
                tabName: tabName,
                isPriority: isPriority,
                kind: kind,
                reason: event.reason
            )
        if let index = notifications.firstIndex(where: { $0.paneID == paneID }) {
            notifications[index] = notification
        } else {
            notifications.append(notification)
        }
        TracingService.shared.record(
            "pane.notification.added",
            attributes: [
                "pane.name": paneName,
                "tab.name": tabName,
                "notification.kind": kind.rawValue,
                "notification.source": event.source.rawValue,
                "notification.reason": event.reason,
            ])
        MacNotificationCoordinator.shared.postPaneAttentionIfNeeded(
            paneID: paneID,
            paneName: paneName,
            tabID: tabID,
            tabName: tabName,
            reason: event.reason,
            source: event.source
        )
        SessionPersistence.save(appState: self)
    }

    func addPRMergedNotification(
        paneID: UUID,
        paneName: String,
        tabID: UUID,
        tabName: String,
        prNumber: Int,
        prTitle: String
    ) {
        guard SettingsPersistence.isPRMergedNotificationsEnabled() else { return }
        if notifications.contains(where: { $0.paneID == paneID && $0.kind == .prMerged }) { return }
        notifications.removeAll { $0.paneID == paneID }
        notifications.append(
            PaneNotification(
                paneID: paneID,
                paneName: paneName,
                tabID: tabID,
                tabName: tabName,
                isPriority: false,
                kind: .prMerged,
                prNumber: prNumber,
                prTitle: prTitle
            ))
        tabs.flatMap(\.panes).first { $0.id == paneID }?.isMerged = true
        MacNotificationCoordinator.shared.postPRMergedBannerIfNeeded(
            paneID: paneID,
            paneName: paneName,
            tabID: tabID,
            tabName: tabName,
            prNumber: prNumber,
            prTitle: prTitle
        )
        SessionPersistence.save(appState: self)
    }

    func clearPRMergedNotification(paneID: UUID) {
        let pane = tabs.flatMap(\.panes).first { $0.id == paneID }
        let hasMergedRow = notifications.contains { $0.paneID == paneID && $0.kind == .prMerged }
        guard hasMergedRow || pane?.isMerged == true else { return }
        notifications.removeAll { $0.paneID == paneID && $0.kind == .prMerged }
        pane?.isMerged = false
        TracingService.shared.record(
            "pane.pr_merged.cleared",
            attributes: ["pane.id": paneID.uuidString])
        SessionPersistence.save(appState: self)
    }

    func addPRClosedNotification(
        paneID: UUID,
        paneName: String,
        tabID: UUID,
        tabName: String,
        prNumber: Int,
        prTitle: String
    ) {
        guard SettingsPersistence.isPRClosedNotificationsEnabled() else { return }
        if notifications.contains(where: { $0.paneID == paneID && $0.kind == .prClosed }) { return }
        notifications.removeAll { $0.paneID == paneID }
        notifications.append(
            PaneNotification(
                paneID: paneID,
                paneName: paneName,
                tabID: tabID,
                tabName: tabName,
                isPriority: false,
                kind: .prClosed,
                prNumber: prNumber,
                prTitle: prTitle
            ))
        tabs.flatMap(\.panes).first { $0.id == paneID }?.isClosed = true
        MacNotificationCoordinator.shared.postPRClosedBannerIfNeeded(
            paneID: paneID,
            paneName: paneName,
            tabID: tabID,
            tabName: tabName,
            prNumber: prNumber,
            prTitle: prTitle
        )
        SessionPersistence.save(appState: self)
    }

    func clearPRClosedNotification(paneID: UUID) {
        let pane = tabs.flatMap(\.panes).first { $0.id == paneID }
        let hasClosedRow = notifications.contains { $0.paneID == paneID && $0.kind == .prClosed }
        guard hasClosedRow || pane?.isClosed == true else { return }
        notifications.removeAll { $0.paneID == paneID && $0.kind == .prClosed }
        pane?.isClosed = false
        TracingService.shared.record(
            "pane.pr_closed.cleared",
            attributes: ["pane.id": paneID.uuidString])
        SessionPersistence.save(appState: self)
    }

    func clearNotification(paneID: UUID) {
        MacNotificationCoordinator.shared.markPaneAcknowledged(paneID: paneID)
        if let notification = notifications.first(where: { $0.paneID == paneID }) {
            TracingService.shared.record(
                "pane.notification.cleared",
                attributes: [
                    "pane.name": notification.paneName,
                    "tab.name": notification.tabName,
                    "reason": "cleared",
                ])
        }
        notifications.removeAll { $0.paneID == paneID }
        MacNotificationCoordinator.shared.removeDeliveredNotifications(forPaneID: paneID)
        SessionPersistence.save(appState: self)
    }

    func clearNotification(paneID: UUID, kind: NotificationKind) {
        guard notifications.contains(where: { $0.paneID == paneID && $0.kind == kind }) else { return }
        TracingService.shared.record(
            "pane.notification.cleared",
            attributes: [
                "pane.id": paneID.uuidString,
                "notification.kind": kind.rawValue,
                "reason": "kind_specific",
            ])
        notifications.removeAll { $0.paneID == paneID && $0.kind == kind }
        MacNotificationCoordinator.shared.removeDeliveredNotifications(forPaneID: paneID)
        SessionPersistence.save(appState: self)
    }

    @discardableResult
    func acknowledgeNotification(id: UUID) -> PaneNotification? {
        guard let notification = notifications.first(where: { $0.id == id }),
            let tab = tabs.first(where: { $0.id == notification.tabID }),
            tab.panes.contains(where: { $0.id == notification.paneID })
        else {
            return nil
        }

        TracingService.shared.record(
            "pane.notification.cleared",
            attributes: [
                "pane.name": notification.paneName,
                "tab.name": notification.tabName,
                "reason": "navigated",
            ])
        activeTab?.setFocusedPane(id: nil, reason: "notification_navigation")
        tabs.first(where: { $0.id == notification.tabID })?
            .setFocusedPane(id: nil, reason: "notification_navigation")
        switchToTab(id: notification.tabID)
        setActivePane(id: notification.paneID)
        if notification.kind == .prMerged || notification.kind == .prClosed {
            NotificationCenter.default.post(
                name: .prResolutionActionRequested,
                object: nil,
                userInfo: [
                    "paneID": notification.paneID.uuidString,
                    "tabID": notification.tabID.uuidString,
                    "kind": notification.kind.rawValue,
                ]
            )
        }

        return notification
    }

    @discardableResult
    func runSavedStatusLineFieldNow(
        fieldID: String, profileID: UUID?, appSettings: AppSettings
    ) -> String {
        var startedCount = 0
        var coalescedCount = 0
        for pane in tabs.flatMap(\.panes) {
            guard let monitor = pane.statusLineMonitor else { continue }

            let savedConfig: StatusLineConfig?
            if let profileID {
                guard pane.profileID == profileID,
                    let profile = appSettings.profiles.first(where: { $0.id == profileID }),
                    profile.statusLineConfig != nil
                else {
                    continue
                }
                savedConfig = profile.resolvedStatusLineConfig(inheriting: appSettings.statusLineConfig)
            } else {
                if let paneProfileID = pane.profileID,
                    let profile = appSettings.profiles.first(where: { $0.id == paneProfileID }),
                    profile.statusLineConfig != nil
                {
                    continue
                }
                savedConfig = appSettings.statusLineConfig
            }

            guard let field = savedConfig?.customField(withID: fieldID),
                field.supports(monitor.harness)
            else {
                continue
            }
            monitor.profileName = pane.profileID.flatMap { profileID in
                appSettings.profiles.first(where: { $0.id == profileID })?.name
            }
            switch monitor.runCustomFieldNow(field) {
            case .started:
                startedCount += 1
            case .coalesced:
                coalescedCount += 1
            case .unsupported:
                continue
            }
        }

        let targetCount = startedCount + coalescedCount
        var attributes = [
            "field_id": fieldID,
            "scope": profileID == nil ? "global" : "profile",
            "target_count": "\(targetCount)",
            "started_count": "\(startedCount)",
            "coalesced_count": "\(coalescedCount)",
            "result": targetCount == 0
                ? "no_matching_panes"
                : coalescedCount == targetCount ? "coalesced" : "started",
        ]
        if let profileID {
            attributes["profile_id"] = profileID.uuidString
        }
        TracingService.shared.record("statusline.custom_field.run_now", attributes: attributes)

        if targetCount == 0 {
            return "No matching saved panes."
        }
        if startedCount == 0 {
            return "Already running in \(coalescedCount) pane\(coalescedCount == 1 ? "" : "s")."
        }
        if coalescedCount == 0 {
            return "Started in \(startedCount) pane\(startedCount == 1 ? "" : "s")."
        }
        return
            "Started in \(startedCount) pane\(startedCount == 1 ? "" : "s"); "
            + "already running in \(coalescedCount) pane\(coalescedCount == 1 ? "" : "s")."
    }

    func focusPane(tabID: UUID, paneID: UUID) {
        activeTab?.setFocusedPane(id: nil, reason: "notification_navigation")
        guard let tab = tabs.first(where: { $0.id == tabID }),
            let pane = tab.panes.first(where: { $0.id == paneID })
        else { return }
        tab.setFocusedPane(id: nil, reason: "notification_navigation")
        TracingService.shared.record(
            "pane.activated",
            attributes: [
                "pane.id": pane.id.uuidString,
                "pane.name": pane.name,
                "tab.id": tab.id.uuidString,
                "tab.name": tab.name,
            ])
        switchToTab(id: tabID)
        setActivePane(id: paneID)
    }
}
