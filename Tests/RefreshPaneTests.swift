import Foundation
import XCTest

@testable import AgentSessionManager

final class RefreshPaneTests: XCTestCase {
    func testInjectContinueFlagIntoArgsAddsWhenMissing() {
        let result = Tab.injectContinueFlagIntoArgs(["--model", "opus"])
        XCTAssertEqual(result, ["--model", "opus", "--continue"])
    }

    func testInjectContinueFlagIntoArgsNoOpWhenPresent() {
        let result = Tab.injectContinueFlagIntoArgs(["--continue", "--model", "opus"])
        XCTAssertEqual(result, ["--continue", "--model", "opus"])
    }

    func testInjectContinueFlagIntoArgsEmpty() {
        let result = Tab.injectContinueFlagIntoArgs([])
        XCTAssertEqual(result, ["--continue"])
    }

    func testInjectContinueFlagIntoArgsPreservesExplicitResume() {
        for args in [
            ["--resume", "chat-id"],
            ["--resume=chat-id"],
            ["--continue", "--model", "opus"],
        ] {
            XCTAssertEqual(Tab.injectContinueFlagIntoArgs(args), args)
        }
    }

    func testBuildClaudeCommandIncludesContinue() {
        let cmd = Tab.buildClaudeCommand(settingsPath: "/tmp/test.json", extraArgs: ["--model", "opus", "--continue"])
        XCTAssertTrue(cmd.contains("--continue"))
        XCTAssertTrue(cmd.contains("--settings"))
        XCTAssertTrue(cmd.contains("--model"))
        XCTAssertTrue(cmd.contains("opus"))
    }

    func testBuildCodexCommandResumesExactSessionAfterPreservedOptions() throws {
        let command = Tab.buildCodexCommand(
            hookScriptPath: "/tmp/codex-hook.py",
            adapter: .current(version: "0.162.1"),
            extraArgs: ["--model", "gpt-6-luna", "resume", "old-session"],
            resumeSessionID: "current-session",
            previousResumeSessionID: "old-session")

        XCTAssertEqual(Array(command[1...2]), ["-c", "features.hooks=true"])
        XCTAssertEqual(command[command.count - 4], "--model")
        XCTAssertEqual(command[command.count - 3], "gpt-6-luna")
        let resumeIndex = try XCTUnwrap(command.firstIndex(of: "resume"))
        XCTAssertEqual(command[resumeIndex - 1], "gpt-6-luna")
        XCTAssertEqual(command.last, "current-session")
        XCTAssertTrue(command[..<resumeIndex].contains("features.hooks=true"))
        XCTAssertTrue(command[(resumeIndex + 1)..<command.count].allSatisfy { !$0.hasPrefix("hooks.") })
        XCTAssertTrue(command.contains(where: { $0.hasPrefix("hooks.SessionStart=") }))
    }

    func testBuildCodexCommandStartsFreshAfterRemovingPreviousAppResumeTarget() {
        let command = Tab.buildCodexCommand(
            hookScriptPath: "/tmp/codex-hook.py",
            adapter: .current(version: "0.162.1"),
            extraArgs: ["--model", "gpt-6-luna", "resume", "old-session"],
            previousResumeSessionID: "old-session")

        XCTAssertEqual(Array(command.suffix(2)), ["--model", "gpt-6-luna"])
        XCTAssertFalse(command.contains("resume"))
    }

    func testBuildCodexCommandKeepsHookOverridesBeforeFreshPromptOptions() {
        let command = Tab.buildCodexCommand(
            hookScriptPath: "/tmp/codex-hook.py",
            adapter: .current(version: "0.162.1"),
            extraArgs: ["--model", "gpt-6-luna"])

        XCTAssertEqual(command[1...2], ["-c", "features.hooks=true"])
        XCTAssertEqual(Array(command.suffix(2)), ["--model", "gpt-6-luna"])
    }

    func testRestoreResumeTargetRequiresEnabledCodexContinuationAndSavedIdentity() {
        XCTAssertEqual(
            Tab.codexResumeSessionIDForRestore(
                harness: .codex, savedSessionID: "saved-session", continueOnRestart: true),
            "saved-session")
        XCTAssertNil(
            Tab.codexResumeSessionIDForRestore(
                harness: .codex, savedSessionID: "saved-session", continueOnRestart: false))
        XCTAssertNil(
            Tab.codexResumeSessionIDForRestore(
                harness: .claude, savedSessionID: "saved-session", continueOnRestart: true))
        XCTAssertEqual(
            Tab.codexRestoreNotice(harness: .codex, savedSessionID: nil, continueOnRestart: true),
            "No prior Codex conversation was recorded. This pane started a new conversation.")
        XCTAssertNil(Tab.codexRestoreNotice(harness: .codex, savedSessionID: "saved", continueOnRestart: true))
        XCTAssertNil(Tab.codexRestoreNotice(harness: .codex, savedSessionID: nil, continueOnRestart: false))
    }

    func testCodexRestoreBuildsResumeForSavedIdentityWithoutLatestFallback() {
        let savedSessionID = "saved-exact-session"
        let resumeSessionID = Tab.codexResumeSessionIDForRestore(
            harness: .codex, savedSessionID: savedSessionID, continueOnRestart: true)
        let resumedCommand = Tab.buildCodexCommand(
            hookScriptPath: "/tmp/codex-hook.py",
            adapter: .unsupported(version: nil),
            extraArgs: ["--model", "gpt-6-luna"],
            resumeSessionID: resumeSessionID)

        XCTAssertEqual(resumeSessionID, savedSessionID)
        XCTAssertEqual(Array(resumedCommand.suffix(4)), ["--model", "gpt-6-luna", "resume", savedSessionID])
        XCTAssertFalse(resumedCommand.contains("--last"))

        let legacyResumeSessionID = Tab.codexResumeSessionIDForRestore(
            harness: .codex, savedSessionID: nil, continueOnRestart: true)
        let legacyCommand = Tab.buildCodexCommand(
            hookScriptPath: "/tmp/codex-hook.py",
            adapter: .unsupported(version: nil),
            extraArgs: ["--model", "gpt-6-luna"],
            resumeSessionID: legacyResumeSessionID)

        XCTAssertNil(legacyResumeSessionID)
        XCTAssertEqual(Array(legacyCommand.suffix(2)), ["--model", "gpt-6-luna"])
        XCTAssertFalse(legacyCommand.contains("--last"))
        XCTAssertEqual(
            Tab.codexRestoreNotice(harness: .codex, savedSessionID: nil, continueOnRestart: true),
            "No prior Codex conversation was recorded. This pane started a new conversation.")
    }

    @MainActor
    func testCodexMissingSessionIdentitySurvivesPreflightUntilExplicitFreshStart() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "codex-continuation-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repository = root.appending(path: "repo", directoryHint: .isDirectory)
        let codexHome = root.appending(path: "codex-home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = AppSettings()
        settings.preferredShell = "/bin/sh"
        settings.agentControlInjectionPolicy = .never
        let tab = Tab(name: "repo", directory: repository)
        let pane = Pane(
            name: "codex-pane", tab: tab, harness: .codex,
            agentControlInjectionEnabled: false, appSettings: settings)
        pane.extraEnvVars = ["CODEX_HOME": codexHome.path]
        pane.codexSessionID = "deleted-exact-session"
        pane.codexTranscriptPath = root.appending(path: "deleted-transcript.jsonl").path
        let originalController = TerminalController()
        originalController.pendingDirectory = repository.path
        originalController.pendingShell = "/bin/sh"
        originalController.pendingEnvironment = Tab.hostEnvironmentForChildProcess()
        originalController.pendingCommandArgs = ["codex"]
        pane.installTerminalController(originalController)
        tab.panes.append(pane)

        tab.refreshPane(pane, appSettings: settings)

        XCTAssertTrue(pane.terminalController === originalController)
        XCTAssertEqual(pane.codexSessionID, "deleted-exact-session")
        XCTAssertEqual(pane.codexTranscriptPath, root.appending(path: "deleted-transcript.jsonl").path)
        XCTAssertEqual(pane.codexContinuationRecovery, .exactSessionUnavailable)

        tab.refreshPane(
            pane,
            extraArgs: pane.extraArgs,
            harness: .codex,
            extraEnvVars: pane.extraEnvVars,
            profileID: .some(pane.profileID),
            appSettings: settings)

        XCTAssertNil(pane.codexSessionID)
        XCTAssertNil(pane.codexTranscriptPath)
        XCTAssertNil(pane.codexContinuationRecovery)
        XCTAssertFalse(pane.terminalController?.pendingCommandArgs?.contains("resume") == true)
        XCTAssertFalse(pane.terminalController?.pendingCommandArgs?.contains("--last") == true)
    }

    @MainActor
    func testCodexQuickRefreshWithoutBindingKeepsCurrentProcessRunning() {
        let tab = Tab(name: "repo", directory: URL(filePath: "/tmp/repo"))
        let pane = Pane(name: "codex-pane", tab: tab, harness: .codex)
        let controller = TerminalController()
        controller.pendingCommandArgs = ["codex"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.refreshPane(pane)

        XCTAssertTrue(pane.terminalController === controller)
        XCTAssertEqual(pane.codexContinuationRecovery, .identityNotRecorded)
        XCTAssertEqual(pane.terminalController?.pendingCommandArgs, ["codex"])
    }

    @MainActor
    func testCodexRefreshSheetExplainsExactContinuationAndFreshSettingsBehavior() {
        let tab = Tab(name: "repo", directory: URL(filePath: "/tmp/repo"))
        let pane = Pane(name: "codex-pane", tab: tab, harness: .codex)
        let sheet = RefreshPaneSheet(pane: pane, onQuickRefresh: { _ in }, onRefreshWithSettings: { _ in })

        XCTAssertTrue(sheet.isContinuationDisabled)
        XCTAssertEqual(sheet.continuationDescription, "Codex has not reported a conversation to continue.")
        XCTAssertEqual(sheet.settingsDescription, "Start a fresh Codex conversation with reconfigured options.")

        pane.codexSessionID = "exact-session"
        XCTAssertFalse(sheet.isContinuationDisabled)
        XCTAssertEqual(sheet.continuationDescription, "Resume this pane's exact foreground conversation.")

        pane.codexContinuationRecovery = .exactSessionUnavailable
        XCTAssertTrue(sheet.isContinuationDisabled)
        XCTAssertEqual(
            sheet.continuationDescription,
            "The saved Codex conversation is unavailable. Choose Retry or start a new conversation.")
        XCTAssertEqual(sheet.settingsDescription, "Start a fresh Codex conversation with reconfigured options.")
    }

    @MainActor
    func testCodexRestoreDefersLaunchUntilUnavailableConversationRecoveryChoice() {
        let tab = Tab(name: "repo", directory: URL(filePath: "/tmp/repo"))

        let pane = tab.addPane(
            name: "codex-pane",
            harness: .codex,
            codexContinuationRecovery: .exactSessionUnavailable)

        XCTAssertNil(pane.terminalController)
        XCTAssertNil(pane.statusLineMonitor)
        XCTAssertEqual(pane.codexContinuationRecovery, .exactSessionUnavailable)
        XCTAssertTrue(tab.panes.contains(where: { $0 === pane }))
    }

    @MainActor
    func testRestoredCodexPaneRetainsExactSessionAndStatusHookOverrides() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "codex-restore-hooks-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repository = root.appending(path: "repo", directoryHint: .isDirectory)
        let bin = root.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let codexExecutable = bin.appending(path: "codex")
        try "#!/bin/sh\nprintf '%s\\n' 'codex 0.162.1'\n".write(
            to: codexExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codexExecutable.path)

        let settings = AppSettings()
        settings.preferredShell = "/bin/sh"
        settings.agentControlInjectionPolicy = .never
        let tab = Tab(name: "repo", directory: repository)
        let sessionID = "restored-exact-session"
        let pane = tab.addPane(
            name: "codex-pane",
            harness: .codex,
            worktreeDirectory: repository,
            extraEnvVars: [
                "PATH": "\(bin.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")",
                "CODEX_HOME": root.appending(path: "codex-home").path,
            ],
            agentControlInjectionEnabled: false,
            resumeCodexSessionID: sessionID,
            appSettings: settings)
        pane.codexSessionID = sessionID
        defer {
            pane.removeStatusLineMonitor()
            pane.terminalController?.terminate()
        }

        let command = pane.terminalController?.pendingCommandArgs ?? []

        XCTAssertEqual(pane.codexSessionID, sessionID)
        XCTAssertEqual(pane.codexLaunchResumeSessionID, sessionID)
        let resumeIndex = try XCTUnwrap(command.firstIndex(of: "resume"))
        XCTAssertEqual(command[resumeIndex + 1], sessionID)
        XCTAssertEqual(command.last, sessionID)
        XCTAssertTrue(command[..<resumeIndex].contains("features.hooks=true"))
        for event in ["SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest", "PostToolUse", "Interrupt"] {
            XCTAssertTrue(
                command.contains(where: { $0.contains("hooks.\(event)=") }),
                "Missing \(event) hook override")
        }

        let originalMonitor = try XCTUnwrap(pane.statusLineMonitor)
        let restoredMonitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: repository.path,
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name)
        defer { restoredMonitor.stop() }
        try restoredMonitor.writeCodexHookScript()

        XCTAssertNotEqual(originalMonitor.codexLaunchGeneration, restoredMonitor.codexLaunchGeneration)
        XCTAssertNotEqual(originalMonitor.codexHookQueueFilePath, restoredMonitor.codexHookQueueFilePath)
        XCTAssertNotEqual(originalMonitor.codexHookDiagnosticFilePath, restoredMonitor.codexHookDiagnosticFilePath)
        XCTAssertEqual(originalMonitor.codexHookScriptFilePath, restoredMonitor.codexHookScriptFilePath)
        XCTAssertTrue(command.contains(where: { $0.contains(originalMonitor.codexHookScriptFilePath) }))

        restoredMonitor.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalMonitor.codexHookScriptFilePath))
        originalMonitor.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalMonitor.codexHookScriptFilePath))
    }

    @MainActor
    func testQuickRefreshPreservesCursorPaneEnvironmentAndCommand() {
        let tab = Tab(name: "repo", directory: URL(filePath: "/tmp/repo"))
        let pane = Pane(name: "cursor-pane", tab: tab, harness: .cursor)
        pane.extraArgs = ["--model", "test"]
        let controller = TerminalController()
        controller.pendingCommandArgs = ["agent", "--model", "test"]
        controller.pendingDirectory = "/tmp/repo"
        controller.pendingEnvironment = ["PATH=/usr/bin"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.refreshPane(pane)

        XCTAssertEqual(pane.terminalController?.pendingCommandArgs, ["agent", "--model", "test"])
        XCTAssertTrue(
            pane.terminalController?.pendingEnvironment?
                .contains("AGENT_SESSION_MANAGER_PANE_ID=\(pane.id.uuidString)") == true)
    }

    @MainActor
    func testQuickRefreshRebuildsOpenCodeCommandWithFreshPort() {
        let tab = Tab(name: "repo", directory: URL(filePath: "/tmp/repo"))
        let pane = Pane(name: "opencode-pane", tab: tab, harness: .opencode)
        pane.opencodePort = 11111
        pane.extraArgs = ["--verbose"]
        let controller = TerminalController()
        controller.pendingCommandArgs = ["opencode", "--old-flag"]
        controller.pendingDirectory = "/tmp/repo"
        controller.pendingEnvironment = ["PATH=/usr/bin"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.refreshPane(pane)

        XCTAssertNotEqual(pane.opencodePort, 11111)
        XCTAssertNotNil(pane.opencodePort)
        let args = pane.terminalController?.pendingCommandArgs ?? []
        XCTAssertEqual(args.prefix(4), ["opencode", "--hostname", "127.0.0.1", "--mdns"])
        XCTAssertTrue(args.contains("--port"))
        XCTAssertTrue(args.contains(String(pane.opencodePort!)))
        XCTAssertTrue(args.contains("--verbose"))
        XCTAssertTrue(
            pane.terminalController?.pendingEnvironment?
                .contains("AGENT_SESSION_MANAGER_OPENCODE_PORT=\(pane.opencodePort!)") == true)
        XCTAssertTrue(
            pane.terminalController?.pendingEnvironment?
                .contains("OPENCODE_EXPERIMENTAL_EVENT_SYSTEM=true") == true)
        XCTAssertFalse(
            pane.terminalController?.pendingEnvironment?
                .contains("OPENCODE_DISABLE_PRUNE=true") == true)
    }

    @MainActor
    func testQuickRefreshReinjectsOpenCodeSessionIdWhenKnown() {
        let tab = Tab(name: "repo", directory: URL(filePath: "/tmp/repo"))
        let pane = Pane(name: "opencode-pane", tab: tab, harness: .opencode)
        pane.opencodePort = 11111
        pane.opencodeSessionID = "ses_resume"
        pane.extraArgs = ["--verbose"]
        let controller = TerminalController()
        controller.pendingCommandArgs = ["opencode", "--old-flag"]
        controller.pendingDirectory = "/tmp/repo"
        controller.pendingEnvironment = ["PATH=/usr/bin"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.refreshPane(pane)

        XCTAssertNotEqual(pane.opencodePort, 11111)
        XCTAssertNotNil(pane.opencodePort)
        let args = pane.terminalController?.pendingCommandArgs ?? []
        XCTAssertTrue(args.contains("--port"))
        XCTAssertTrue(args.contains(String(pane.opencodePort!)))
        XCTAssertTrue(args.contains("--session"))
        XCTAssertTrue(args.contains("ses_resume"))
        XCTAssertTrue(args.contains("--verbose"))
        XCTAssertTrue(
            pane.terminalController?.pendingEnvironment?
                .contains("OPENCODE_DISABLE_PRUNE=true") == true)
    }

    @MainActor
    func testRefreshWithNewSettingsPreservesOpenCodeSessionFlag() {
        let tab = Tab(name: "repo", directory: URL(filePath: "/tmp/repo"))
        let pane = Pane(name: "opencode-pane", tab: tab, harness: .opencode)
        pane.installTerminalController(TerminalController())
        tab.panes.append(pane)

        tab.refreshPane(pane, extraArgs: ["--session", "ses_resume", "--verbose"], harness: .opencode)

        let args = pane.terminalController?.pendingCommandArgs ?? []
        XCTAssertTrue(args.contains("--session"))
        XCTAssertTrue(args.contains("ses_resume"))
        XCTAssertTrue(args.contains("--verbose"))
        XCTAssertEqual(args.prefix(4), ["opencode", "--hostname", "127.0.0.1", "--mdns"])
        XCTAssertTrue(
            pane.terminalController?.pendingEnvironment?
                .contains("OPENCODE_DISABLE_PRUNE=true") == true)
    }

    @MainActor
    func testRefreshWithNewSettingsPreservesExtraArgsForClaude() {
        let tab = Tab(name: "repo", directory: URL(filePath: "/tmp/repo"))
        let pane = Pane(name: "claude-pane", tab: tab, harness: .claude)
        pane.extraArgs = ["--model", "opus"]
        let controller = TerminalController()
        controller.pendingCommandArgs = ["claude", "--settings", "/tmp/old.json", "--model", "opus"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        tab.refreshPane(pane, extraArgs: ["--model", "sonnet"], harness: .claude)

        let args = pane.terminalController?.pendingCommandArgs ?? []
        XCTAssertTrue(args.contains("--settings"))
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("sonnet"))
    }

    @MainActor
    func testRefreshWithNewCodexSettingsStartsFreshWithUpdatedOptions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "codex-refresh-settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bin = directory.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let codex = bin.appending(path: "codex")
        try "#!/bin/sh\nprintf 'codex-cli 0.162.1\\n'\n".write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        let shell = directory.appending(path: "shell")
        try "#!/bin/sh\nPATH='\(bin.path)'\nexport PATH\nexec /bin/sh -c \"$3\"\n"
            .write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settings = AppSettings()
        settings.preferredShell = shell.path
        settings.agentControlInjectionPolicy = .never
        let tab = Tab(name: "repo", directory: directory)
        let pane = Pane(name: "codex-pane", tab: tab, harness: .codex, agentControlInjectionEnabled: false)
        pane.extraArgs = ["--model", "old-model"]
        pane.codexSessionID = "previous-conversation"
        pane.codexTranscriptPath = "/tmp/previous-rollout.jsonl"
        let oldController = TerminalController()
        oldController.pendingDirectory = directory.path
        oldController.pendingCommandArgs = ["codex", "resume", "previous-conversation"]
        pane.installTerminalController(oldController)
        tab.panes.append(pane)

        tab.refreshPane(
            pane,
            extraArgs: ["--model", "gpt-5.2"],
            harness: .codex,
            appSettings: settings)

        XCTAssertFalse(pane.terminalController === oldController)
        XCTAssertNil(pane.codexSessionID)
        XCTAssertNil(pane.codexTranscriptPath)
        XCTAssertEqual(pane.extraArgs, ["--model", "gpt-5.2"])
        XCTAssertEqual(
            pane.terminalController?.pendingCommandArgs?.suffix(2), ["--model", "gpt-5.2"])
        XCTAssertFalse(pane.terminalController?.pendingCommandArgs?.contains("resume") ?? true)
    }
}
