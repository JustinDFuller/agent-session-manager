import Foundation

extension Pane {
    @MainActor
    func bindNotifications(appState: AppState, isPriority: Bool) {
        self.isPriority = isPriority
        notificationAppState = appState
        attachTerminalNotificationHandlers()
        attachStatusLineNotificationHandlers()
    }

    @MainActor
    func attachTerminalNotificationHandlers() {
        guard let appState = notificationAppState, let tab else { return }
        terminalController?.terminalView.onUserInput = { [weak appState, weak self] in
            Task { @MainActor in
                guard let appState, let pane = self else { return }
                appState.clearNotification(paneID: pane.id)
            }
        }
        terminalController?.onAttention = { [weak appState, weak tab, weak self] event in
            Task { @MainActor in
                guard let appState, let tab, let pane = self else { return }
                appState.addNotification(
                    paneID: pane.id,
                    paneName: pane.name,
                    tabID: tab.id,
                    tabName: tab.name,
                    isPriority: pane.isPriority,
                    event: event
                )
            }
        }
    }

    @MainActor
    func attachStatusLineNotificationHandlers() {
        guard let appState = notificationAppState, let tab else { return }
        statusLineMonitor?.onClaudeHookAttention = { [weak self] event in
            Task { @MainActor in
                self?.terminalController?.onAttention?(event)
            }
        }
        statusLineMonitor?.onClaudeStopped = { [weak appState, weak tab, weak self] in
            Task { @MainActor in
                guard let appState, let tab, let pane = self else { return }
                guard SettingsPersistence.isClaudeStopNotificationEnabled() else { return }
                appState.addNotification(
                    paneID: pane.id,
                    paneName: pane.name,
                    tabID: tab.id,
                    tabName: tab.name,
                    isPriority: pane.isPriority,
                    event: .claudeStop
                )
            }
        }
        statusLineMonitor?.onCodexStopped = { [weak appState, weak tab, weak self] in
            Task { @MainActor in
                guard let appState, let tab, let pane = self else { return }
                guard
                    SettingsPersistence.load(NotificationConfig.self, from: "notification-settings.json")?
                        .isCodexCompletionNotificationEnabled ?? true
                else { return }
                appState.addNotification(
                    paneID: pane.id,
                    paneName: pane.name,
                    tabID: tab.id,
                    tabName: tab.name,
                    isPriority: pane.isPriority,
                    event: .codexStop
                )
            }
        }
        statusLineMonitor?.onCodexAttention = { [weak appState, weak tab, weak self] event in
            guard let appState, let tab, let pane = self else { return }
            appState.addNotification(
                paneID: pane.id,
                paneName: pane.name,
                tabID: tab.id,
                tabName: tab.name,
                isPriority: pane.isPriority,
                event: event
            )
        }
        statusLineMonitor?.onCodexAttentionResolved = { [weak appState, weak self] kind in
            guard let appState, let pane = self else { return }
            appState.clearNotification(paneID: pane.id, kind: kind)
        }
        statusLineMonitor?.onOpencodeStopped = { [weak appState, weak tab, weak self] in
            Task { @MainActor in
                guard let appState, let tab, let pane = self else { return }
                guard SettingsPersistence.isOpencodeStopNotificationEnabled() else { return }
                appState.addNotification(
                    paneID: pane.id,
                    paneName: pane.name,
                    tabID: tab.id,
                    tabName: tab.name,
                    isPriority: pane.isPriority,
                    event: .opencodeStop
                )
            }
        }
        statusLineMonitor?.onOpencodeSessionBound = { [weak appState, weak self] id in
            Task { @MainActor in
                self?.opencodeRaceLossRestarted = false
                self?.opencodeSessionID = id
                if let appState { SessionPersistence.save(appState: appState) }
            }
        }
        statusLineMonitor?.onCodexSessionBound = { [weak appState, weak self] id, transcriptPath in
            guard let pane = self else { return }
            if let requestedID = pane.codexLaunchResumeSessionID, requestedID != id {
                pane.codexContinuationRecovery = .exactSessionUnavailable
                InvariantReporter.shared.violated(
                    .codexContinuationIdentity,
                    context: [
                        "pane.id": pane.id.uuidString,
                        "pane.name": pane.name,
                        "tab.id": pane.tab?.id.uuidString ?? "unknown",
                        "tab.name": pane.tab?.name ?? "unknown",
                        "requested_session_id_prefix": String(requestedID.prefix(12)),
                        "bound_session_id_prefix": String(id.prefix(12)),
                    ])
                return
            }
            if pane.codexLaunchResumeSessionID == id {
                pane.codexLaunchResumeSessionID = nil
            }
            pane.codexSessionID = id
            pane.codexTranscriptPath = transcriptPath
            pane.codexContinuationRecovery = nil
            pane.codexContinuationNotice = nil
            TracingService.shared.record(
                "session.pane.codex_identity.saved",
                attributes: [
                    "pane.id": pane.id.uuidString,
                    "pane.name": pane.name,
                    "tab.id": pane.tab?.id.uuidString ?? "unknown",
                    "tab.name": pane.tab?.name ?? "unknown",
                    "session_id_prefix": String(id.prefix(12)),
                    "transcript_available": transcriptPath == nil ? "false" : "true",
                ])
            if let appState { SessionPersistence.save(appState: appState) }
        }
        statusLineMonitor?.onOpencodePermissionReplied = { [weak appState, weak self] in
            Task { @MainActor in
                guard let appState, let pane = self else { return }
                appState.clearNotification(paneID: pane.id, kind: .opencodePermissionRequest)
            }
        }
        statusLineMonitor?.onOpencodePortRaceLost = { [weak self] in
            Task { @MainActor in
                guard let pane = self, let tab = pane.tab, !pane.opencodeRaceLossRestarted else { return }
                pane.opencodeRaceLossRestarted = true
                tab.restartPane(pane, appSettings: pane.appSettings)
            }
        }
        statusLineMonitor?.onPRMerged = { [weak appState, weak tab, weak self] prNumber, prTitle in
            Task { @MainActor in
                guard let appState, let tab, let pane = self else { return }
                appState.addPRMergedNotification(
                    paneID: pane.id,
                    paneName: pane.name,
                    tabID: tab.id,
                    tabName: tab.name,
                    prNumber: prNumber,
                    prTitle: prTitle
                )
            }
        }
        statusLineMonitor?.onPRClosed = { [weak appState, weak tab, weak self] prNumber, prTitle in
            Task { @MainActor in
                guard let appState, let tab, let pane = self else { return }
                appState.addPRClosedNotification(
                    paneID: pane.id,
                    paneName: pane.name,
                    tabID: tab.id,
                    tabName: tab.name,
                    prNumber: prNumber,
                    prTitle: prTitle
                )
            }
        }
        statusLineMonitor?.onPRReopened = { [weak appState, weak self] in
            Task { @MainActor in
                guard let appState, let pane = self else { return }
                appState.clearPRMergedNotification(paneID: pane.id)
                appState.clearPRClosedNotification(paneID: pane.id)
            }
        }
    }
}
