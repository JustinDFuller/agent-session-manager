import Foundation

extension Tab {
    @discardableResult
    func addPaneWithLoadingState(
        name: String,
        harness: Harness = .claude,
        worktreeIsManaged: Bool = false,
        profileID: UUID? = nil,
        scrollbackOverride: ScrollbackLimit? = nil,
        agentControlInjectionEnabled: Bool = true,
        appSettings: AppSettings? = nil
    ) -> Pane {
        TracingService.shared.record(
            "tab.pane.added",
            attributes: [
                "pane.name": name,
                "tab.name": self.name,
            ])
        let pane = Pane(
            name: name,
            tab: self,
            harness: harness,
            worktreeIsManaged: worktreeIsManaged,
            profileID: profileID,
            scrollbackOverride: scrollbackOverride,
            agentControlInjectionEnabled: agentControlInjectionEnabled,
            appSettings: appSettings
        )
        pane.setupState = .loading
        TracingService.shared.record(
            "agent_control.injection_decision.resolved",
            attributes: [
                "pane.id": pane.id.uuidString,
                "pane.name": pane.name,
                "tab.id": self.id.uuidString,
                "tab.name": self.name,
                "agent_control.enabled": String(pane.agentControlInjectionEnabled),
                "agent_control.policy": appSettings?.agentControlInjectionPolicy.rawValue ?? "default",
                "agent_control.scope": appSettings?.agentControlScope.rawValue ?? "default",
                "agent_control.source": "pane_loading",
            ])
        panes.append(pane)
        return pane
    }

    func completeSetup(
        for pane: Pane,
        resolved: ResolvedWorktree,
        managed: Bool,
        effectiveExtraArgs: [String],
        extraEnvVars: [String: String],
        statusLineConfigOverride: StatusLineConfig?,
        appSettings: AppSettings? = nil
    ) {
        pane.name = resolved.paneTitle
        pane.worktreeDirectory = resolved.processDirectory
        pane.worktreeIsManaged = managed
        pane.extraArgs = effectiveExtraArgs
        pane.extraEnvVars = extraEnvVars

        TracingService.shared.record(
            "tab.worktree.resolved",
            attributes: [
                "user_ref": pane.name,
                "result": "dir: \(resolved.processDirectory.path)",
                "path": resolved.processDirectory.path,
                "pane.name": pane.name,
                "pane.id": pane.id.uuidString,
                "tab.id": self.id.uuidString,
                "tab.name": self.name,
            ])

        let cwd = resolved.processDirectory.path
        let codexEnvironment = ProcessEnvironment.sanitize(
            Tab.hostEnvironmentForChildProcess() + extraEnvVars.map { "\($0.key)=\($0.value)" })
        let codexAdapter =
            pane.harness == .codex
            ? CodexCompatibilityAdapter.detect(
                shell: appSettings.map { ShellResolver.resolved($0) } ?? ShellResolver.detectedLoginShell(),
                workingDirectory: cwd,
                environment: codexEnvironment) : nil

        if pane.harness != .shell && pane.harness != .opencode {
            let monitor = StatusLineMonitor(
                paneID: pane.id, paneName: pane.name,
                workingDirectory: cwd, harness: pane.harness, processStartTime: Date(),
                tabID: self.id, tabName: self.name,
                codexAdapter: codexAdapter,
                codexShell: appSettings.map { ShellResolver.resolved($0) } ?? ShellResolver.detectedLoginShell(),
                codexEnvironment: ProcessEnvironment.dictionary(from: codexEnvironment),
                customFieldEnvironment: extraEnvVars)
            pane.installStatusLineMonitor(monitor)
        }

        let controller = TerminalController()
        controller.pendingEnvironment = Tab.hostEnvironmentForChildProcess()
        controller.pendingDirectory = cwd
        controller.pendingShell = appSettings.map { ShellResolver.resolved($0) }

        switch pane.harness {
        case .shell:
            controller.pendingCommandArgs = nil
        case .claude:
            applyExtraEnvVars(extraEnvVars, to: controller)
            controller.pendingCommandArgs = Tab.buildClaudeCommand(
                settingsPath: pane.statusLineMonitor!.settingsFilePath,
                extraArgs: effectiveExtraArgs
            )
        case .codex:
            applyExtraEnvVars(extraEnvVars, to: controller)
            guard let monitor = pane.statusLineMonitor,
                configureCodexLaunch(
                    for: pane, monitor: monitor, controller: controller,
                    extraArgs: effectiveExtraArgs, appSettings: appSettings)
            else { return }
        case .cursor:
            applyExtraEnvVars(extraEnvVars, to: controller)
            controller.pendingEnvironment =
                (controller.pendingEnvironment ?? [])
                + ["AGENT_SESSION_MANAGER_PANE_ID=\(pane.id.uuidString)"]
            controller.pendingCommandArgs = ["agent"] + effectiveExtraArgs
        case .opencode:
            applyExtraEnvVars(extraEnvVars, to: controller)
            configureOpenCodeController(
                controller, pane: pane, extraArgs: effectiveExtraArgs, extraEnvVars: extraEnvVars,
                resumeSessionID: pane.opencodeSessionID)
            let monitor = StatusLineMonitor(
                paneID: pane.id, paneName: pane.name,
                workingDirectory: cwd, harness: pane.harness, processStartTime: Date(),
                tabID: self.id, tabName: self.name, opencodePort: pane.opencodePort,
                customFieldEnvironment: extraEnvVars)
            pane.installStatusLineMonitor(monitor)
        }
        controller.terminalView.telemetryTabName = self.name
        controller.terminalView.telemetryTabUUID = self.id
        controller.terminalView.telemetryPaneName = pane.name
        controller.terminalView.telemetryPaneUUID = pane.id
        guard prepareAgentControl(for: pane, controller: controller, appSettings: appSettings) else {
            return
        }
        pane.installTerminalController(controller)
        pane.setupState = nil
    }

    func configureCodexLaunch(
        for pane: Pane,
        monitor: StatusLineMonitor,
        controller: TerminalController,
        extraArgs: [String],
        appSettings: AppSettings?,
        resumeSessionID: String? = nil
    ) -> Bool {
        if pane.codexContinuationRecovery == .exactSessionUnavailable, resumeSessionID != nil {
            return false
        }
        guard let adapter = monitor.codexAdapter else {
            pane.setupState = .failed(
                error: "Codex compatibility could not be selected. Retry after checking the configured shell.")
            return false
        }
        let catalog = appSettings?.codexCliOptions ?? CLIOptionConfig.codexAll
        if let unsupported = adapter.unsupportedBuiltinOption(
            in: extraArgs,
            catalog: catalog)
        {
            pane.setupState = .failed(
                error:
                    "Codex does not support the saved value '\(unsupported.value)' for \(unsupported.name) in \(adapter.version ?? "this version"). Change the global setting in Settings → Harnesses → Codex or edit the affected profile, then use Refresh Pane → Refresh with New Settings and choose 'on-request' or 'never'. Your saved value and custom options are unchanged."
            )
            TracingService.shared.record(
                "statusline.codex.compatibility.rejected_option",
                attributes: [
                    "pane.id": pane.id.uuidString,
                    "pane.name": pane.name,
                    "tab.id": id.uuidString,
                    "tab.name": name,
                    "adapter": adapter.identifier,
                    "option": unsupported.name,
                    "reason": "unsupported_saved_builtin_value",
                ])
            return false
        }
        controller.pendingEnvironment =
            (controller.pendingEnvironment ?? [])
            + [
                "AGENT_SESSION_MANAGER_PANE_ID=\(pane.id.uuidString)",
                "AGENT_SESSION_MANAGER_TAB_ID=\(id.uuidString)",
            ]
        guard !adapter.hookEvents.isEmpty else {
            controller.pendingCommandArgs = Tab.buildCodexCommand(
                hookScriptPath: monitor.codexHookScriptFilePath,
                adapter: adapter,
                extraArgs: extraArgs,
                resumeSessionID: resumeSessionID,
                previousResumeSessionID: pane.codexLaunchResumeSessionID)
            pane.codexLaunchResumeSessionID = resumeSessionID
            TracingService.shared.record(
                "statusline.codex.compatibility.selected",
                attributes: [
                    "pane.id": pane.id.uuidString,
                    "pane.name": pane.name,
                    "tab.id": id.uuidString,
                    "tab.name": name,
                    "adapter": adapter.identifier,
                    "version": adapter.version ?? "unknown",
                    "result": "baseline_only",
                ])
            return true
        }
        do {
            try monitor.writeCodexHookScript()
        } catch {
            pane.setupState = .failed(
                error:
                    "Agent Session Manager could not prepare Codex lifecycle integration. Check temporary file access and retry."
            )
            TracingService.shared.record(
                "statusline.codex.hook_setup.failed",
                attributes: [
                    "pane.id": pane.id.uuidString,
                    "pane.name": pane.name,
                    "tab.id": id.uuidString,
                    "tab.name": name,
                    "adapter": adapter.identifier,
                    "result": "file_setup_failed",
                ])
            return false
        }
        controller.pendingEnvironment =
            (controller.pendingEnvironment ?? [])
            + [
                "AGENT_SESSION_MANAGER_CODEX_LAUNCH_GENERATION=\(monitor.codexLaunchGeneration)",
                "AGENT_SESSION_MANAGER_CODEX_HOOK_QUEUE_PATH=\(monitor.codexHookQueueFilePath)",
                "AGENT_SESSION_MANAGER_CODEX_HOOK_DIAGNOSTIC_PATH=\(monitor.codexHookDiagnosticFilePath)",
            ]
        controller.pendingCommandArgs = Tab.buildCodexCommand(
            hookScriptPath: monitor.codexHookScriptFilePath,
            adapter: adapter,
            extraArgs: extraArgs,
            resumeSessionID: resumeSessionID,
            previousResumeSessionID: pane.codexLaunchResumeSessionID)
        pane.codexLaunchResumeSessionID = resumeSessionID
        TracingService.shared.record(
            "statusline.codex.compatibility.selected",
            attributes: [
                "pane.id": pane.id.uuidString,
                "pane.name": pane.name,
                "tab.id": id.uuidString,
                "tab.name": name,
                "adapter": adapter.identifier,
                "version": adapter.version ?? "unknown",
                "result": "hooks_prepared",
                "hook_count": "\(adapter.hookEvents.count)",
            ])
        return true
    }
}
