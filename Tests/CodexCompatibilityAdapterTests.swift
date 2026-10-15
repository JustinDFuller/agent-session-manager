import Foundation
import XCTest

@testable import AgentSessionManager

private struct HookProcessResult {
    let status: Int32
    let standardOutput: Data
    let standardError: Data
}

final class CodexCompatibilityAdapterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agent-session-manager-codex-compatibility-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSelectsCurrentLegacyAndUnknownAdapters() {
        XCTAssertEqual(CodexCompatibilityAdapter.select("codex-cli 0.162.1"), .current(version: "0.162.1"))
        XCTAssertEqual(CodexCompatibilityAdapter.select("codex 0.136.4"), .legacy(version: "0.136.4"))
        XCTAssertEqual(CodexCompatibilityAdapter.select("codex 0.163.0"), .unsupported(version: "0.163.0"))
        XCTAssertEqual(CodexCompatibilityAdapter.select("startup noise 9.9.9"), .unsupported(version: nil))
    }

    func testCurrentAndLegacyHookEventsMatchSupportedSchemas() {
        XCTAssertEqual(
            CodexCompatibilityAdapter.select("0.162.1").hookEvents,
            ["SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest", "PostToolUse", "Interrupt"])
        XCTAssertEqual(
            CodexCompatibilityAdapter.select("0.136.0").hookEvents,
            ["SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest", "PostToolUse"])
        XCTAssertTrue(CodexCompatibilityAdapter.select(nil).hookEvents.isEmpty)
    }

    func testProviderParserUsesSelectedAdaptersForCurrentLegacyAndUnknownVersions() {
        let currentLine = Data(CodexCompatibilityFixtures.currentTokenCount.utf8)
        let legacyLine = Data(CodexCompatibilityFixtures.legacyTokenCount.utf8)

        let current = CodexRolloutParser.parseLine(
            currentLine,
            expectedCWD: "/repo",
            adapter: .current(version: "0.162.1"))
        let legacy = CodexRolloutParser.parseLine(
            legacyLine,
            expectedCWD: "/repo",
            adapter: .legacy(version: "0.136.0"))
        let unknown = CodexRolloutParser.parseLine(
            currentLine,
            expectedCWD: "/repo",
            adapter: .unsupported(version: "0.163.0"))

        XCTAssertEqual(current?.contextWindow?.totalInputTokens, 30)
        XCTAssertEqual(current?.contextWindow?.totalOutputTokens, 10)
        XCTAssertEqual(current?.contextWindow?.usedPercentage, 40)
        XCTAssertEqual(current?.rateLimits?.fiveHour?.usedPercentage, 25)
        XCTAssertEqual(current?.rateLimits?.sevenDay?.usedPercentage, 50)
        XCTAssertEqual(legacy?.contextWindow?.totalInputTokens, 20)
        XCTAssertEqual(legacy?.contextWindow?.totalOutputTokens, 5)
        XCTAssertEqual(legacy?.contextWindow?.usedPercentage, 31)
        XCTAssertEqual(legacy?.rateLimits?.fiveHour?.usedPercentage, 12.5)
        XCTAssertEqual(legacy?.rateLimits?.sevenDay?.usedPercentage, 44)
        XCTAssertNil(unknown)
    }

    func testDetectUsesConfiguredShellPathAndAnchorsCodexVersionLine() throws {
        let binDirectory = tempDir.appending(path: "bin")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try "for index in {1..1000}; do printf 'codex-cli 0.136.1 startup noise\\n'; done\n"
            .write(to: tempDir.appending(path: ".bashrc"), atomically: true, encoding: .utf8)
        let codexExecutable = binDirectory.appending(path: "codex")
        try "#!/bin/sh\nprintf 'plugin 9.9.9\\ncodex-cli 0.162.1\\n'\n"
            .write(to: codexExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codexExecutable.path)

        let adapter = CodexCompatibilityAdapter.detect(
            shell: "/bin/bash",
            workingDirectory: tempDir.path,
            environment: ["PATH=\(binDirectory.path)", "HOME=\(tempDir.path)", "TERM=dumb"],
            timeout: 2)

        XCTAssertEqual(adapter, .current(version: "0.162.1"))
    }

    @MainActor
    func testConfiguredShellSelectionControlsLaunchArgumentsAndProviderParsing() throws {
        let binDirectory = tempDir.appending(path: "configured-bin")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let codexExecutable = binDirectory.appending(path: "codex")
        try "#!/bin/sh\nprintf 'codex-cli 0.162.1\\n'\n"
            .write(to: codexExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codexExecutable.path)
        let adapter = CodexCompatibilityAdapter.detect(
            shell: "/bin/bash",
            workingDirectory: tempDir.path,
            environment: ["PATH=\(binDirectory.path)", "HOME=\(tempDir.path)", "TERM=dumb"])
        let tab = Tab(name: "repo", directory: tempDir)
        let pane = Pane(name: "codex-pane", tab: tab, harness: .codex)
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: tempDir.path,
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: adapter)
        defer { try? FileManager.default.removeItem(atPath: monitor.codexHookScriptFilePath) }
        let controller = TerminalController()

        XCTAssertTrue(
            tab.configureCodexLaunch(
                for: pane,
                monitor: monitor,
                controller: controller,
                extraArgs: ["--model", "custom-model"],
                appSettings: nil))
        XCTAssertEqual(monitor.codexAdapter, .current(version: "0.162.1"))
        XCTAssertTrue(controller.pendingCommandArgs?.contains(where: { $0.hasPrefix("hooks.Interrupt=") }) == true)
        XCTAssertFalse(controller.pendingCommandArgs?.contains(where: { $0.hasPrefix("hooks.SessionEnd=") }) == true)
        XCTAssertTrue(controller.pendingCommandArgs?.contains("custom-model") == true)

        let context = StatusProviderContext(
            paneID: pane.id,
            paneName: pane.name,
            tabID: tab.id,
            tabName: tab.name,
            workingDirectory: tempDir.path,
            harness: .codex,
            processStartTime: Date(),
            launchArgs: controller.pendingCommandArgs ?? [],
            environment: [:],
            detectedHarnessVersion: adapter.version,
            codexHookRecordPath: nil,
            opencodePort: nil,
            opencodeSessionID: nil,
            codexAdapter: monitor.codexAdapter)
        let parsed = CodexRolloutParser.parseLine(
            Data(CodexCompatibilityFixtures.currentTokenCount.utf8),
            expectedCWD: context.workingDirectory,
            adapter: context.codexAdapter ?? .unsupported(version: nil))

        XCTAssertEqual(parsed?.contextWindow?.totalInputTokens, 30)
        XCTAssertEqual(parsed?.contextWindow?.usedPercentage, 40)
    }

    func testUnsupportedSavedBuiltinApprovalIsRejectedButDisabledOrCustomOptionIsPreserved() {
        var builtin = CLIOptionConfig.codexAll.first { $0.id == "--ask-for-approval" }!
        builtin.isAvailable = true
        let current = CodexCompatibilityAdapter.select("0.162.1")

        XCTAssertEqual(
            current.unsupportedBuiltinOption(in: ["--ask-for-approval", "untrusted"], catalog: [builtin])?.value,
            "untrusted")

        builtin.isAvailable = false
        XCTAssertEqual(
            current.unsupportedBuiltinOption(
                in: ["--ask-for-approval=untrusted"],
                catalog: [builtin])?
                .value,
            "untrusted")

        var custom = builtin
        custom.isUserAdded = true
        custom.isAvailable = true
        XCTAssertNil(
            current.unsupportedBuiltinOption(in: ["--ask-for-approval", "untrusted"], catalog: [builtin, custom]))
    }

    @MainActor
    func testRefreshWithNewSettingsStoresSelectedProfileBeforeCodexPreparation() {
        let tab = Tab(name: "repo", directory: URL(filePath: tempDir.path))
        let previousProfile = Profile(name: "Previous", harness: .codex)
        let selectedProfile = Profile(name: "Selected", harness: .codex)
        let settings = AppSettings()
        settings.profiles = [previousProfile, selectedProfile]
        let pane = Pane(name: "codex-pane", tab: tab, harness: .codex, profileID: previousProfile.id)
        pane.installTerminalController(TerminalController())
        tab.panes.append(pane)

        tab.refreshPane(
            pane,
            extraArgs: ["--model", "test"],
            harness: .codex,
            profileID: selectedProfile.id,
            appSettings: settings)

        XCTAssertEqual(pane.profileID, selectedProfile.id)
    }

    @MainActor
    func testCodexLaunchRejectsUnsupportedSavedApprovalWithoutChangingOptions() {
        let tab = Tab(name: "repo", directory: URL(filePath: tempDir.path))
        let pane = Pane(name: "codex-pane", tab: tab, harness: .codex)
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: tempDir.path,
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"))
        let settings = AppSettings()
        var approvalOption = CLIOptionConfig.codexAll.first { $0.id == "--ask-for-approval" }!
        approvalOption.isAvailable = false
        settings.codexCliOptions = [approvalOption]
        let savedArguments = ["--ask-for-approval", "untrusted", "--custom-value", "retained"]
        pane.extraArgs = savedArguments

        let didConfigure = tab.configureCodexLaunch(
            for: pane,
            monitor: monitor,
            controller: TerminalController(),
            extraArgs: savedArguments,
            appSettings: settings)

        guard case .failed(let error) = pane.setupState else {
            XCTFail("Expected Codex setup failure for the saved approval value")
            return
        }
        XCTAssertFalse(didConfigure)
        XCTAssertTrue(error.contains("untrusted"))
        XCTAssertTrue(error.contains("Refresh Pane → Refresh with New Settings"))
        XCTAssertEqual(pane.extraArgs, savedArguments)
        XCTAssertEqual(settings.codexCliOptions.first?.isAvailable, false)
    }

    @MainActor
    func testCodexHookFileSetupFailureSurfacesPaneSetupError() throws {
        let tab = Tab(name: "repo", directory: URL(filePath: tempDir.path))
        let pane = Pane(name: "codex-pane", tab: tab, harness: .codex)
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: tempDir.path,
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"))
        let scriptURL = URL(filePath: monitor.codexHookScriptFilePath)
        try FileManager.default.createDirectory(at: scriptURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        let controller = TerminalController()

        let didConfigure = tab.configureCodexLaunch(
            for: pane,
            monitor: monitor,
            controller: controller,
            extraArgs: [],
            appSettings: nil)

        guard case .failed(let error) = pane.setupState else {
            XCTFail("Expected hook file setup failure to surface in pane state")
            return
        }
        XCTAssertFalse(didConfigure)
        XCTAssertTrue(error.contains("could not prepare Codex lifecycle integration"))
        XCTAssertNil(controller.pendingCommandArgs)
    }

    @MainActor
    func testGeneratedHookScriptQueuesOnlyAllowedMetadata() throws {
        let paneID = UUID()
        let tabID = UUID()
        let monitor = StatusLineMonitor(
            paneID: paneID,
            paneName: "metadata-test",
            workingDirectory: tempDir.path,
            harness: .codex,
            tabID: tabID,
            tabName: "metadata-tab",
            codexAdapter: .current(version: "0.162.1"))
        try monitor.writeCodexHookScript()
        let environment = ProcessInfo.processInfo.environment.merging([
            "AGENT_SESSION_MANAGER_PANE_ID": paneID.uuidString,
            "AGENT_SESSION_MANAGER_TAB_ID": tabID.uuidString,
            "AGENT_SESSION_MANAGER_CODEX_LAUNCH_GENERATION": monitor.codexLaunchGeneration,
            "AGENT_SESSION_MANAGER_CODEX_HOOK_QUEUE_PATH": monitor.codexHookQueueFilePath,
            "AGENT_SESSION_MANAGER_CODEX_HOOK_DIAGNOSTIC_PATH": monitor.codexHookDiagnosticFilePath,
        ]) { _, new in new }

        let input = """
            {"hook_event_name":"PermissionRequest","session_id":"session-safe","turn_id":"turn-safe","cwd":"\(tempDir.path)","model":"gpt-test","prompt":"SENSITIVE_PROMPT_SENTINEL","tool_input":{"command":"SENSITIVE_COMMAND_SENTINEL"},"tool_response":"SENSITIVE_OUTPUT_SENTINEL","authorization":"SENSITIVE_CREDENTIAL_SENTINEL","api_key":"SENSITIVE_API_KEY_SENTINEL"}
            """
        func runHook(_ payload: Data) throws -> HookProcessResult {
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            let standardInput = Pipe()
            process.executableURL = URL(filePath: "/usr/bin/env")
            process.arguments = ["python3", monitor.codexHookScriptFilePath]
            process.environment = environment
            process.standardInput = standardInput
            process.standardOutput = standardOutput
            process.standardError = standardError
            try process.run()
            standardInput.fileHandleForWriting.write(payload)
            try standardInput.fileHandleForWriting.close()
            process.waitUntilExit()
            return HookProcessResult(
                status: process.terminationStatus,
                standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                standardError: standardError.fileHandleForReading.readDataToEndOfFile())
        }
        func holdQueueLock(for duration: TimeInterval, readyAt readyURL: URL) throws -> Process {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/python3")
            process.arguments = [
                "-c",
                "import fcntl,sys,time; handle=open(sys.argv[1], 'a'); fcntl.flock(handle.fileno(), fcntl.LOCK_EX); open(sys.argv[2], 'w').close(); time.sleep(float(sys.argv[3]))",
                monitor.codexHookQueueFilePath,
                readyURL.path,
                String(duration),
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(1)
            while !FileManager.default.fileExists(atPath: readyURL.path), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: readyURL.path))
            return process
        }

        let firstResult = try runHook(Data(input.utf8))
        XCTAssertEqual(firstResult.status, 0)
        XCTAssertTrue(firstResult.standardOutput.isEmpty)
        XCTAssertTrue(firstResult.standardError.isEmpty)
        let hookQueue = CodexHookQueue(fileURL: URL(filePath: monitor.codexHookQueueFilePath))
        XCTAssertEqual(try hookQueue.drain().records.count, 1)
        let holderReady = tempDir.appending(path: "queue-lock-ready")
        let lockHolder = try holdQueueLock(for: 0.2, readyAt: holderReady)
        let retryResult = try runHook(Data(input.utf8))
        lockHolder.waitUntilExit()
        XCTAssertEqual(retryResult.status, 0)
        XCTAssertTrue(retryResult.standardOutput.isEmpty)
        XCTAssertTrue(retryResult.standardError.isEmpty)
        let recoveredQueueText = try String(
            contentsOf: URL(filePath: monitor.codexHookQueueFilePath), encoding: .utf8)
        let recoveredRecords = try hookQueue.drain().records
        XCTAssertEqual(recoveredRecords.count, 1)
        XCTAssertEqual(recoveredRecords.first?.sessionID, "session-safe")
        let timeoutReady = tempDir.appending(path: "queue-lock-timeout-ready")
        let timeoutHolder = try holdQueueLock(for: 0.7, readyAt: timeoutReady)
        let timeoutResult = try runHook(Data(input.utf8))
        timeoutHolder.waitUntilExit()
        XCTAssertEqual(timeoutResult.status, 0)
        XCTAssertTrue(timeoutResult.standardOutput.isEmpty)
        XCTAssertTrue(timeoutResult.standardError.isEmpty)
        let invalidResult = try runHook(Data("{invalid json".utf8))
        XCTAssertNotEqual(invalidResult.status, 0)
        XCTAssertTrue(invalidResult.standardOutput.isEmpty)
        XCTAssertTrue(invalidResult.standardError.isEmpty)

        let invocationTraceObserved = expectation(description: "hook invocation is traced after queue failure")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { invocationTraceObserved.fulfill() }
        wait(for: [invocationTraceObserved], timeout: 2)
        let invocationTrace = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "statusline.codex.hook.invoked"
                && $0.attributes["pane.id"] == paneID.uuidString
                && $0.attributes["hook_event_name"] == "PermissionRequest"
        }
        XCTAssertEqual(invocationTrace?.attributes["result"], "started")
        let failureTrace = TracingService.shared.recordedEventsForTesting.first {
            $0.name == "statusline.codex.hook_queue.write_failed"
                && $0.attributes["pane.id"] == paneID.uuidString
                && $0.attributes["result"] == "queue_lock_timeout"
        }
        XCTAssertEqual(failureTrace?.attributes["hook_event_name"], "PermissionRequest")
        let diagnosticQueueURL = tempDir.appending(path: "codex-diagnostics.jsonl")
        try "invoked|SessionStart|started\nfailed|Interrupt|hook_write_failed\ninvalid|Sensitive|value\n"
            .write(to: diagnosticQueueURL, atomically: true, encoding: .utf8)
        let diagnosticQueue = CodexHookDiagnosticQueue(fileURL: diagnosticQueueURL)
        XCTAssertEqual(
            try diagnosticQueue.drain(),
            [
                CodexHookDiagnosticRecord(kind: "invoked", eventName: "SessionStart", result: "started"),
                CodexHookDiagnosticRecord(kind: "failed", eventName: "Interrupt", result: "hook_write_failed"),
            ])
        XCTAssertTrue(try diagnosticQueue.drain().isEmpty)

        XCTAssertFalse(recoveredQueueText.contains("SENSITIVE_PROMPT_SENTINEL"))
        XCTAssertFalse(recoveredQueueText.contains("SENSITIVE_COMMAND_SENTINEL"))
        XCTAssertFalse(recoveredQueueText.contains("SENSITIVE_OUTPUT_SENTINEL"))
        XCTAssertFalse(recoveredQueueText.contains("SENSITIVE_CREDENTIAL_SENTINEL"))
        XCTAssertFalse(recoveredQueueText.contains("SENSITIVE_API_KEY_SENTINEL"))
        XCTAssertFalse(recoveredQueueText.contains("prompt"))
        XCTAssertTrue(recoveredQueueText.contains("session-safe"))
        XCTAssertTrue(recoveredQueueText.contains("turn-safe"))
        XCTAssertTrue(recoveredQueueText.contains(paneID.uuidString))
        let attributes = try FileManager.default.attributesOfItem(atPath: monitor.codexHookQueueFilePath)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        monitor.stop()
    }

    @MainActor
    func testReplacingCodexMonitorPreservesReplacementHookScriptAndQueue() throws {
        let tab = Tab(name: "repo", directory: tempDir)
        let pane = Pane(name: "codex-pane", tab: tab, harness: .codex)
        let previousMonitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: tempDir.path,
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"))
        let replacementMonitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: tempDir.path,
            harness: .codex,
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"))
        defer {
            pane.removeStatusLineMonitor()
            previousMonitor.stop()
            replacementMonitor.stop()
        }

        try previousMonitor.writeCodexHookScript()
        pane.installStatusLineMonitor(previousMonitor)
        try replacementMonitor.writeCodexHookScript()
        pane.installStatusLineMonitor(replacementMonitor)

        XCTAssertEqual(previousMonitor.codexHookScriptFilePath, replacementMonitor.codexHookScriptFilePath)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: replacementMonitor.codexHookScriptFilePath))

        let environment = ProcessInfo.processInfo.environment.merging([
            "AGENT_SESSION_MANAGER_PANE_ID": pane.id.uuidString,
            "AGENT_SESSION_MANAGER_TAB_ID": tab.id.uuidString,
            "AGENT_SESSION_MANAGER_CODEX_LAUNCH_GENERATION": replacementMonitor.codexLaunchGeneration,
            "AGENT_SESSION_MANAGER_CODEX_HOOK_QUEUE_PATH": replacementMonitor.codexHookQueueFilePath,
            "AGENT_SESSION_MANAGER_CODEX_HOOK_DIAGNOSTIC_PATH": replacementMonitor.codexHookDiagnosticFilePath,
        ]) { _, new in new }
        let process = Process()
        let standardInput = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["python3", replacementMonitor.codexHookScriptFilePath]
        process.environment = environment
        process.standardInput = standardInput
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        standardInput.fileHandleForWriting.write(
            Data(
                "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"replacement-session\",\"cwd\":\"\(tempDir.path)\"}"
                    .utf8))
        try standardInput.fileHandleForWriting.close()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let records = try CodexHookQueue(fileURL: URL(filePath: replacementMonitor.codexHookQueueFilePath)).drain()
        XCTAssertEqual(records.records.count, 1)
        XCTAssertEqual(records.records.first?.sessionID, "replacement-session")
        XCTAssertEqual(records.records.first?.launchGeneration, replacementMonitor.codexLaunchGeneration)
    }

    @MainActor
    func testGeneratedHookProducerCompactsWithinCapacityAndRetainsNewestRecord() throws {
        let monitor = StatusLineMonitor(
            paneID: UUID(),
            paneName: "capacity-test",
            workingDirectory: tempDir.path,
            harness: .codex,
            tabID: UUID(),
            tabName: "capacity-tab",
            codexAdapter: .current(version: "0.162.1"))
        try monitor.writeCodexHookScript()
        let environment = ProcessInfo.processInfo.environment.merging([
            "AGENT_SESSION_MANAGER_PANE_ID": "pane-capacity",
            "AGENT_SESSION_MANAGER_TAB_ID": "tab-capacity",
            "AGENT_SESSION_MANAGER_CODEX_LAUNCH_GENERATION": monitor.codexLaunchGeneration,
            "AGENT_SESSION_MANAGER_CODEX_HOOK_QUEUE_PATH": monitor.codexHookQueueFilePath,
            "AGENT_SESSION_MANAGER_CODEX_HOOK_DIAGNOSTIC_PATH": monitor.codexHookDiagnosticFilePath,
        ]) { _, new in new }
        let wrapper = tempDir.appending(path: "produce-capacity.py")
        try """
        import io
        import json
        import runpy
        import sys
        for index in range(1000):
            payload = {"hook_event_name": "SessionStart", "session_id": f"session-{index}", "transcript_path": "x" * 1024}
            sys.stdin = io.StringIO(json.dumps(payload))
            runpy.run_path(sys.argv[1], run_name="__main__")
        """.write(to: wrapper, atomically: true, encoding: .utf8)
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments = [wrapper.path, monitor.codexHookScriptFilePath]
        process.environment = environment
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(standardOutput.fileHandleForReading.readDataToEndOfFile().isEmpty)
        XCTAssertTrue(standardError.fileHandleForReading.readDataToEndOfFile().isEmpty)

        let queueData = try Data(contentsOf: URL(filePath: monitor.codexHookQueueFilePath))
        XCTAssertLessThanOrEqual(queueData.count, 1_048_576)
        let drain = try CodexHookQueue(fileURL: URL(filePath: monitor.codexHookQueueFilePath)).drain()
        XCTAssertFalse(drain.records.isEmpty)
        XCTAssertEqual(drain.records.last?.sessionID, "session-999")
        XCTAssertEqual(drain.malformedRecordCount, 0)
        monitor.stop()
    }

    func testQueuePreservesOrderingAndPartialLineAcrossDrainAndCompaction() throws {
        let queueURL = tempDir.appending(path: "hooks.jsonl")
        let queue = CodexHookQueue(fileURL: queueURL)
        let first = queueRecord(event: "SessionStart", generation: "generation-one")
        let second = queueRecord(event: "UserPromptSubmit", generation: "generation-one")
        let firstData = try JSONEncoder().encode(first)
        let secondData = try JSONEncoder().encode(second)
        var initial = firstData
        initial.append(0x0A)
        initial.append(contentsOf: secondData.prefix(12))
        try initial.write(to: queueURL)

        let firstDrain = try queue.drain()
        XCTAssertEqual(firstDrain.records, [first])
        XCTAssertTrue(firstDrain.partialRecordRetained)

        let handle = try FileHandle(forWritingTo: queueURL)
        try handle.seekToEnd()
        var continuation = Data(secondData.dropFirst(12))
        continuation.append(0x0A)
        try handle.write(contentsOf: continuation)
        try handle.close()

        let secondDrain = try queue.drain()
        XCTAssertEqual(secondDrain.records, [second])
        XCTAssertFalse(secondDrain.partialRecordRetained)
        XCTAssertTrue(try Data(contentsOf: queueURL).isEmpty)
    }

    private func queueRecord(event: String, generation: String) -> CodexHookQueueRecord {
        CodexHookQueueRecord(
            paneID: "pane",
            tabID: "tab",
            launchGeneration: generation,
            hookEventName: event,
            sessionID: "session",
            turnID: nil,
            requestID: nil,
            timestamp: 1,
            source: "hook",
            model: nil,
            transcriptPath: nil,
            result: nil)
    }
}
