import Foundation
import SQLite3
import XCTest

@testable import AgentSessionManager

@MainActor
final class SessionPersistenceNotificationTests: XCTestCase {
    func testDecodesLegacySessionWithoutPendingNotifications() throws {
        let json = """
            {"tabs":[],"activeTabIndex":null}
            """
        let data = Data(json.utf8)
        let session = try JSONDecoder().decode(PersistedSession.self, from: data)
        XCTAssertTrue(session.pendingNotifications.isEmpty)
    }

    func testPendingNotificationsRoundTrip() throws {
        let paneID = UUID()
        let tabID = UUID()
        let notifID = UUID()
        let ts = Date(timeIntervalSinceReferenceDate: 123_456)
        let pending = PersistedPaneNotification(
            notificationID: notifID,
            paneID: paneID,
            paneName: "p",
            tabID: tabID,
            tabName: "t",
            isPriority: true,
            timestamp: ts,
            kind: .terminalBell,
            reason: "Permission needed"
        )
        let session = PersistedSession(
            tabs: [],
            activeTabIndex: nil,
            pendingNotifications: [pending]
        )
        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(PersistedSession.self, from: encoded)
        XCTAssertEqual(decoded.pendingNotifications.count, 1)
        XCTAssertEqual(decoded.pendingNotifications[0], pending)
    }

    func testCodexNotificationKindsRoundTrip() throws {
        let kinds: [NotificationKind] = [.codexStop, .codexPermissionRequest, .codexQuestion]
        let persisted = kinds.map {
            PersistedPaneNotification(
                notificationID: UUID(),
                paneID: UUID(),
                paneName: "codex-pane",
                tabID: UUID(),
                tabName: "project",
                isPriority: true,
                timestamp: Date(),
                kind: $0)
        }

        let decoded = try JSONDecoder().decode([PersistedPaneNotification].self, from: JSONEncoder().encode(persisted))

        XCTAssertEqual(decoded.map(\.kind), kinds)
    }

    func testLegacyPendingNotificationReasonDefaultsNil() throws {
        let data = Data(
            """
            {
              "notificationID":"00000000-0000-0000-0000-000000000001",
              "paneID":"00000000-0000-0000-0000-000000000002",
              "paneName":"p",
              "tabID":"00000000-0000-0000-0000-000000000003",
              "tabName":"t",
              "isPriority":false,
              "timestamp":0
            }
            """.utf8)
        let decoded = try JSONDecoder().decode(PersistedPaneNotification.self, from: data)
        XCTAssertNil(decoded.reason)
    }

    func testUnknownNotificationKindFallsBackToTerminalBell() throws {
        let data = Data(
            """
            {
              "notificationID":"00000000-0000-0000-0000-000000000001",
              "paneID":"00000000-0000-0000-0000-000000000002",
              "paneName":"p",
              "tabID":"00000000-0000-0000-0000-000000000003",
              "tabName":"t",
              "isPriority":false,
              "timestamp":0,
              "kind":"future_kind"
            }
            """.utf8)
        let decoded = try JSONDecoder().decode(PersistedPaneNotification.self, from: data)
        XCTAssertEqual(decoded.kind, .terminalBell)
    }

    func testPersistedNotificationReasonRoundTripsThroughAppState() {
        let state = AppState()
        state.addNotification(
            paneID: UUID(), paneName: "p", tabID: UUID(), tabName: "t", isPriority: false,
            event: PaneAttentionEvent(source: .claudePermissionRequest, reason: "Permission needed for Bash")
        )
        let session = SessionPersistence.makePersistedSession(appState: state)
        XCTAssertEqual(session.pendingNotifications.first?.reason, "Permission needed for Bash")
    }

    func testRestoreUsesPersistedTabAndPaneIDs() {
        let tabID = UUID()
        let paneID = UUID()
        let tab = Tab(id: tabID, name: "T", directory: URL(fileURLWithPath: "/tmp"))
        let pane = tab.addPane(name: "P", id: paneID)
        XCTAssertEqual(tab.id, tabID)
        XCTAssertEqual(pane.id, paneID)
    }

    func testPersistedDirectoryURLPreservesSpaces() {
        let path = "/tmp/Agent Session Manager/project"
        XCTAssertEqual(SessionPersistence.persistedDirectoryURL(for: path)?.path, path)
    }

    func testPersistedDirectoryURLRejectsEmptyPath() {
        XCTAssertNil(SessionPersistence.persistedDirectoryURL(for: ""))
    }

    func testProfileIDPreservedAfterAddPane() {
        let profileID = UUID()
        let tab = Tab(id: UUID(), name: "T", directory: URL(fileURLWithPath: "/tmp"))
        let pane = tab.addPane(name: "P", profileID: profileID)
        XCTAssertEqual(pane.profileID, profileID)
    }

    func testIsMergedPersistedAndRestored() throws {
        let persisted = PersistedPane(
            id: UUID(), name: "p", harness: .claude, isPriority: false, isMerged: true,
            worktreeDirectory: nil, worktreeIsManaged: false
        )
        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: data)
        XCTAssertTrue(decoded.isMerged)
    }

    func testLegacyPaneDefaultsIsMergedFalse() throws {
        let json = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "p",
              "harness": "claude",
              "isPriority": false,
              "worktreeIsManaged": false
            }
            """.utf8)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: json)
        XCTAssertFalse(decoded.isMerged)
    }

    func testExtraArgsPreservedInPane() {
        let tab = Tab(id: UUID(), name: "T", directory: URL(fileURLWithPath: "/tmp"))
        let pane = tab.addPane(name: "P", extraArgs: ["--model", "opus"])
        XCTAssertEqual(pane.extraArgs, ["--model", "opus"])
    }

    func testOpenCodeSessionIDPreservedInPane() {
        let tab = Tab(id: UUID(), name: "T", directory: URL(fileURLWithPath: "/tmp"))
        let pane = tab.addPane(name: "P", harness: .opencode)
        pane.opencodeSessionID = "ses_abc"
        XCTAssertEqual(pane.opencodeSessionID, "ses_abc")
    }

    func testOpenCodeSessionIDIncludedInPersistedSession() {
        let appState = AppState()
        let tab = Tab(name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "P", tab: tab, harness: .opencode)
        pane.opencodeSessionID = "ses_xyz"
        pane.worktreeDirectory = URL(filePath: "/tmp")
        tab.panes.append(pane)
        appState.tabs.append(tab)

        let session = SessionPersistence.makePersistedSession(appState: appState)
        XCTAssertEqual(session.tabs.first?.panes.first?.opencodeSessionID, "ses_xyz")
    }

    func testCodexConversationMetadataPersistsWithPaneConfiguration() throws {
        let appState = AppState()
        let tab = Tab(name: "project", directory: URL(filePath: "/tmp/project"))
        let pane = Pane(
            name: "codex-pane", tab: tab, harness: .codex,
            worktreeDirectory: URL(filePath: "/tmp/project/.agent-session-manager/worktrees/codex-pane"),
            worktreeIsManaged: true, profileID: UUID(), appSettings: AppSettings())
        pane.extraArgs = ["--model", "gpt-5"]
        pane.codexSessionID = "conversation-exact"
        pane.codexTranscriptPath = "/tmp/codex-home/sessions/conversation-exact.jsonl"
        tab.panes.append(pane)
        appState.tabs.append(tab)
        appState.notifications = [
            PaneNotification(
                paneID: pane.id,
                paneName: pane.name,
                tabID: tab.id,
                tabName: tab.name,
                isPriority: true,
                kind: .codexQuestion)
        ]

        let session = SessionPersistence.makePersistedSession(appState: appState)
        let persisted = try XCTUnwrap(
            session.tabs.first?.panes.first)
        let encoded = try String(decoding: JSONEncoder().encode(persisted), as: UTF8.self)

        XCTAssertEqual(persisted.codexSessionID, "conversation-exact")
        XCTAssertEqual(persisted.codexTranscriptPath, "/tmp/codex-home/sessions/conversation-exact.jsonl")
        XCTAssertEqual(persisted.worktreeDirectory, pane.worktreeDirectory?.path)
        XCTAssertTrue(persisted.worktreeIsManaged)
        XCTAssertEqual(persisted.profileID, pane.profileID)
        XCTAssertEqual(persisted.extraArgs, ["--model", "gpt-5"])
        XCTAssertEqual(session.pendingNotifications.map(\.kind), [.codexQuestion])
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("bearer"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("credential"))
    }

    func testLegacyCodexPaneDefaultsConversationMetadataToNil() throws {
        let json = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "p",
              "harness": "codex",
              "isPriority": false,
              "worktreeIsManaged": false
            }
            """.utf8)

        let decoded = try JSONDecoder().decode(PersistedPane.self, from: json)

        XCTAssertNil(decoded.codexSessionID)
        XCTAssertNil(decoded.codexTranscriptPath)
    }

    func testExtraArgsRoundTripInPersistedPane() throws {
        let persisted = PersistedPane(
            id: UUID(), name: "p", harness: .claude,
            extraArgs: ["--model", "claude-opus-4-5"]
        )
        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: data)
        XCTAssertEqual(decoded.extraArgs, ["--model", "claude-opus-4-5"])
    }

    func testLegacyPaneDefaultsExtraArgsEmpty() throws {
        let json = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "p",
              "harness": "claude",
              "isPriority": false,
              "worktreeIsManaged": false
            }
            """.utf8)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: json)
        XCTAssertEqual(decoded.extraArgs, [])
    }

    func testRestoreCombinesExtraArgsWithContinue() throws {
        let pane = PersistedPane(
            id: UUID(), name: "p", harness: .claude,
            extraArgs: ["--model", "claude-opus-4-5"]
        )
        var extraArgs = pane.extraArgs
        let continueOnRestart = true
        if pane.harness == .claude && continueOnRestart && !extraArgs.contains("--continue") {
            extraArgs.append("--continue")
        }
        XCTAssertEqual(extraArgs, ["--model", "claude-opus-4-5", "--continue"])
    }

    func testRestoreInjectsCursorContinueAndRecordsBoundedOutcome() throws {
        let subdirectory = "session-restore-cursor-\(UUID().uuidString)"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: subdirectory)
        let worktree = FileManager.default.temporaryDirectory
            .appending(path: "cursor-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        let tabID = UUID()
        let paneID = UUID()
        let session = PersistedSession(
            tabs: [
                PersistedTab(
                    id: tabID,
                    name: "cursor-tab",
                    directory: worktree.path,
                    baseBranchOverride: nil,
                    panes: [
                        PersistedPane(
                            id: paneID,
                            name: "cursor-pane",
                            harness: .cursor,
                            worktreeDirectory: worktree.path,
                            extraArgs: ["--model", "test"],
                            agentControlInjectionEnabled: false
                        )
                    ]
                )
            ],
            activeTabIndex: 0
        )
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: appSupport.appending(path: "sessions.json"))

        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        let settings = AppSettings()
        settings.agentControlInjectionPolicy = .never
        settings.continueOnRestart = true
        let appState = AppState()
        var restoredStates = [appState]
        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        defer {
            for state in restoredStates {
                for tab in state.tabs {
                    for pane in tab.panes {
                        pane.terminalController?.terminate()
                        pane.removeStatusLineMonitor()
                    }
                }
            }
            TracingService.shared.resetForTesting()
            PersistenceHelpers.overrideAppSupportSubdirectory = nil
            try? FileManager.default.removeItem(at: appSupport)
            try? FileManager.default.removeItem(at: worktree)
        }

        SessionPersistence.restore(into: appState, appSettings: settings)

        let restoredPane = try XCTUnwrap(appState.tabs.first?.panes.first)
        XCTAssertEqual(restoredPane.id, paneID)
        XCTAssertEqual(restoredPane.extraArgs, ["--model", "test", "--continue"])
        XCTAssertEqual(
            Array(restoredPane.terminalController?.pendingCommandArgs?.prefix(4) ?? []),
            ["agent", "--model", "test", "--continue"])

        let event = try XCTUnwrap(
            TracingService.shared.recordedEventsForTesting.first {
                $0.name == "session.pane.restore.continuation"
            })
        XCTAssertEqual(event.attributes["pane.id"], paneID.uuidString)
        XCTAssertEqual(event.attributes["pane.name"], "cursor-pane")
        XCTAssertEqual(event.attributes["tab.id"], tabID.uuidString)
        XCTAssertEqual(event.attributes["tab.name"], "cursor-tab")
        XCTAssertEqual(event.attributes["harness"], Harness.cursor.rawValue)
        XCTAssertEqual(event.attributes["result"], "injected")
        XCTAssertFalse(event.attributes.values.contains("test"))

        TracingService.shared.resetForTesting()
        TracingService.shared.enableTestCapture()
        let disabledSettings = AppSettings()
        disabledSettings.agentControlInjectionPolicy = .never
        disabledSettings.continueOnRestart = false
        let disabledState = AppState()
        restoredStates.append(disabledState)

        SessionPersistence.restore(into: disabledState, appSettings: disabledSettings)

        let disabledPane = try XCTUnwrap(disabledState.tabs.first?.panes.first)
        XCTAssertEqual(disabledPane.extraArgs, ["--model", "test"])
        let disabledEvent = try XCTUnwrap(
            TracingService.shared.recordedEventsForTesting.first {
                $0.name == "session.pane.restore.continuation"
            })
        XCTAssertEqual(disabledEvent.attributes["result"], "disabled")
    }

    func testRestoreLegacyCodexPaneShowsFreshStartNotice() throws {
        let subdirectory = "session-restore-legacy-codex-\(UUID().uuidString)"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: subdirectory)
        let worktree = FileManager.default.temporaryDirectory
            .appending(path: "codex-legacy-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        let paneID = UUID()
        let tabID = UUID()
        let session = PersistedSession(
            tabs: [
                PersistedTab(
                    id: tabID,
                    name: "legacy-codex-tab",
                    directory: worktree.path,
                    baseBranchOverride: nil,
                    panes: [
                        PersistedPane(
                            id: paneID,
                            name: "legacy-codex-pane",
                            harness: .codex,
                            worktreeDirectory: worktree.path,
                            extraArgs: ["--model", "gpt-5.1"],
                            agentControlInjectionEnabled: false
                        )
                    ]
                )
            ],
            activeTabIndex: 0
        )
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: appSupport.appending(path: "sessions.json"))
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        let settings = AppSettings()
        settings.agentControlInjectionPolicy = .never
        settings.continueOnRestart = true
        let appState = AppState()
        defer {
            for tab in appState.tabs {
                for pane in tab.panes {
                    pane.terminalController?.terminate()
                    pane.removeStatusLineMonitor()
                }
            }
            PersistenceHelpers.overrideAppSupportSubdirectory = nil
            try? FileManager.default.removeItem(at: appSupport)
            try? FileManager.default.removeItem(at: worktree)
        }

        SessionPersistence.restore(into: appState, appSettings: settings)

        let restoredPane = try XCTUnwrap(appState.tabs.first?.panes.first)
        XCTAssertEqual(restoredPane.id, paneID)
        XCTAssertNil(restoredPane.codexSessionID)
        XCTAssertNil(restoredPane.codexTranscriptPath)
        XCTAssertNotNil(restoredPane.codexContinuationNotice)
    }

    func testRestoreCodexUsesExactConversationWhenEnabledAndStartsFreshWhenDisabled() throws {
        let subdirectory = "session-restore-exact-codex-\(UUID().uuidString)"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: subdirectory)
        let worktree = FileManager.default.temporaryDirectory
            .appending(path: "codex-exact-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        let codexHome = worktree.appending(path: "codex-home", directoryHint: .isDirectory)
        let fakeBin = worktree.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let savedRollout = worktree.appending(path: "saved.jsonl")
        try Data().write(to: savedRollout)
        let databaseURL = codexHome.appending(path: "state_5.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var sqlError: UnsafeMutablePointer<CChar>?
        let sql = """
            CREATE TABLE threads (id TEXT, cwd TEXT, rollout_path TEXT);
            INSERT INTO threads VALUES ('saved-conversation', '\(worktree.path)', '\(worktree.path)/saved.jsonl');
            INSERT INTO threads VALUES ('newer-conversation', '\(worktree.path)', '\(worktree.path)/newer.jsonl');
            """
        guard sqlite3_exec(database, sql, nil, nil, &sqlError) == SQLITE_OK else {
            let message = sqlError.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(sqlError)
            throw NSError(domain: "SQLiteTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        let fakeCodex = fakeBin.appending(path: "codex")
        try "#!/bin/sh\nprintf 'codex-cli 0.162.1\\n'\n"
            .write(to: fakeCodex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodex.path)
        let fakeShell = worktree.appending(path: "shell")
        try "#!/bin/sh\nPATH='\(fakeBin.path)'\nexport PATH\nexec /bin/sh -c \"$3\"\n"
            .write(to: fakeShell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeShell.path)
        let profileID = UUID()
        let session = PersistedSession(
            tabs: [
                PersistedTab(
                    id: UUID(),
                    name: "exact-codex-tab",
                    directory: worktree.path,
                    panes: [
                        PersistedPane(
                            id: UUID(),
                            name: "exact-codex-pane",
                            harness: .codex,
                            worktreeDirectory: worktree.path,
                            profileID: profileID,
                            extraArgs: ["--model", "gpt-5.1"],
                            codexSessionID: "saved-conversation",
                            codexTranscriptPath: "\(worktree.path)/saved.jsonl",
                            agentControlInjectionEnabled: false)
                    ])
            ],
            activeTabIndex: 0)
        try JSONEncoder().encode(session).write(to: appSupport.appending(path: "sessions.json"))
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        let settings = AppSettings()
        settings.agentControlInjectionPolicy = .never
        settings.preferredShell = fakeShell.path
        settings.profiles = [
            Profile(
                id: profileID,
                name: "Codex test",
                harness: .codex,
                envVars: [ProfileEnvVar(id: "CODEX_HOME", isEnabled: true, value: codexHome.path)])
        ]
        let enabledState = AppState()
        let disabledState = AppState()
        defer {
            for state in [enabledState, disabledState] {
                for tab in state.tabs {
                    for pane in tab.panes {
                        pane.terminalController?.terminate()
                        pane.removeStatusLineMonitor()
                    }
                }
            }
            PersistenceHelpers.overrideAppSupportSubdirectory = nil
            try? FileManager.default.removeItem(at: appSupport)
            try? FileManager.default.removeItem(at: worktree)
        }
        settings.continueOnRestart = true
        SessionPersistence.restore(into: enabledState, appSettings: settings)
        let enabledPane = try XCTUnwrap(enabledState.tabs.first?.panes.first)
        XCTAssertEqual(enabledPane.codexSessionID, "saved-conversation")
        XCTAssertEqual(
            Array(enabledPane.terminalController?.pendingCommandArgs?.suffix(4) ?? []),
            ["--model", "gpt-5.1", "resume", "saved-conversation"])
        let enabledGeneration = try XCTUnwrap(enabledPane.statusLineMonitor?.codexLaunchGeneration)
        XCTAssertTrue(
            enabledPane.terminalController?.pendingEnvironment?.contains(
                "AGENT_SESSION_MANAGER_CODEX_LAUNCH_GENERATION=\(enabledGeneration)") ?? false)

        settings.continueOnRestart = false
        SessionPersistence.restore(into: disabledState, appSettings: settings)
        let disabledPane = try XCTUnwrap(disabledState.tabs.first?.panes.first)
        XCTAssertNil(disabledPane.codexSessionID)
        XCTAssertFalse(disabledPane.terminalController?.pendingCommandArgs?.contains("resume") ?? true)
        XCTAssertTrue(disabledPane.terminalController?.pendingCommandArgs?.contains("--model") ?? false)
        XCTAssertNotEqual(enabledGeneration, disabledPane.statusLineMonitor?.codexLaunchGeneration)
    }

    func testOpenCodeSessionIDRoundTripInPersistedPane() throws {
        let persisted = PersistedPane(
            id: UUID(), name: "p", harness: .opencode,
            opencodeSessionID: "ses_abc123"
        )
        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: data)
        XCTAssertEqual(decoded.opencodeSessionID, "ses_abc123")
    }

    func testCodexIdentityRoundTripsWithPersistedPane() throws {
        let persisted = PersistedPane(
            id: UUID(), name: "p", harness: .codex,
            profileID: UUID(),
            extraArgs: ["--model", "gpt-5.1"],
            codexSessionID: "session-current",
            codexTranscriptPath: "/tmp/current-rollout.jsonl"
        )
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: JSONEncoder().encode(persisted))
        XCTAssertEqual(decoded.codexSessionID, "session-current")
        XCTAssertEqual(decoded.codexTranscriptPath, "/tmp/current-rollout.jsonl")
        XCTAssertEqual(decoded.extraArgs, ["--model", "gpt-5.1"])
        XCTAssertEqual(decoded.profileID, persisted.profileID)
    }

    func testLegacyCodexPaneDefaultsConversationIdentityNil() throws {
        let json = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "p",
              "harness": "codex",
              "isPriority": false,
              "worktreeIsManaged": false
            }
            """.utf8)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: json)
        XCTAssertNil(decoded.codexSessionID)
        XCTAssertNil(decoded.codexTranscriptPath)
    }

    func testLegacyPaneDefaultsOpenCodeSessionIDNil() throws {
        let json = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "p",
              "harness": "opencode",
              "isPriority": false,
              "worktreeIsManaged": false
            }
            """.utf8)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: json)
        XCTAssertNil(decoded.opencodeSessionID)
    }

    func testRestoreCombinesOpenCodeSessionIdWhenContinueOnRestartEnabled() {
        let pane = PersistedPane(
            id: UUID(), name: "p", harness: .opencode,
            extraArgs: ["--model", "test"],
            opencodeSessionID: "ses_resume"
        )
        var extraArgs = pane.extraArgs
        var resumeOpencodeSessionID: String?
        let continueOnRestart = true
        if pane.harness == .opencode && continueOnRestart {
            if let id = pane.opencodeSessionID, !extraArgs.contains("--session") {
                resumeOpencodeSessionID = id
            } else if !extraArgs.contains("--continue") {
                extraArgs.append("--continue")
            }
        }
        XCTAssertEqual(resumeOpencodeSessionID, "ses_resume")
        XCTAssertEqual(extraArgs, ["--model", "test"])
    }

    func testRestoreFallsBackToOpenCodeContinueWhenSessionIdMissing() {
        let pane = PersistedPane(
            id: UUID(), name: "p", harness: .opencode,
            extraArgs: ["--model", "test"]
        )
        var extraArgs = pane.extraArgs
        var resumeOpencodeSessionID: String?
        let continueOnRestart = true
        if pane.harness == .opencode && continueOnRestart {
            if let id = pane.opencodeSessionID, !extraArgs.contains("--session") {
                resumeOpencodeSessionID = id
            } else if !extraArgs.contains("--continue") {
                extraArgs.append("--continue")
            }
        }
        XCTAssertNil(resumeOpencodeSessionID)
        XCTAssertEqual(extraArgs, ["--model", "test", "--continue"])
    }

    func testRestoreOpenCodeNoResumeWhenContinueOnRestartDisabled() {
        let pane = PersistedPane(
            id: UUID(), name: "p", harness: .opencode,
            extraArgs: ["--model", "test"],
            opencodeSessionID: "ses_resume"
        )
        var extraArgs = pane.extraArgs
        var resumeOpencodeSessionID: String?
        let continueOnRestart = false
        if pane.harness == .opencode && continueOnRestart {
            if let id = pane.opencodeSessionID, !extraArgs.contains("--session") {
                resumeOpencodeSessionID = id
            } else if !extraArgs.contains("--continue") {
                extraArgs.append("--continue")
            }
        }
        XCTAssertNil(resumeOpencodeSessionID)
        XCTAssertEqual(extraArgs, ["--model", "test"])
    }

    func testOpenCodeSessionBoundUpdatesPane() async {
        let appState = AppState()
        let tab = Tab(id: UUID(), name: "T", directory: URL(fileURLWithPath: "/tmp"))
        let pane = Pane(name: "P", tab: tab, harness: .opencode)
        let monitor = StatusLineMonitor(
            paneID: pane.id, paneName: pane.name, workingDirectory: "/tmp",
            harness: .opencode, processStartTime: Date(), tabID: tab.id, tabName: tab.name)
        pane.installStatusLineMonitor(monitor)
        pane.bindNotifications(appState: appState, isPriority: false)

        XCTAssertNotNil(pane.tab)
        XCTAssertNotNil(pane.notificationAppState)
        XCTAssertNotNil(pane.statusLineMonitor?.onOpencodeSessionBound)

        pane.opencodeRaceLossRestarted = true
        pane.statusLineMonitor?.onOpencodeSessionBound?("ses_from_monitor")
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(pane.opencodeSessionID, "ses_from_monitor")
        XCTAssertFalse(pane.opencodeRaceLossRestarted)
    }

    func testCodexBindingMismatchPreservesRequestedIdentityAndDoesNotPersist() async throws {
        InvariantReporter.shared.resetForTesting()
        InvariantReporter.shared.enableTestCapture()
        defer { InvariantReporter.shared.resetForTesting() }
        let subdirectory = "agent-session-manager-codex-identity-\(UUID().uuidString)"
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: subdirectory)
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        defer {
            PersistenceHelpers.overrideAppSupportSubdirectory = nil
            try? FileManager.default.removeItem(at: support)
        }
        let appState = AppState()
        let tab = Tab(id: UUID(), name: "T", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "P", tab: tab, harness: .codex)
        let profileID = UUID()
        let notificationID = UUID()
        tab.panes.append(pane)
        appState.tabs.append(tab)
        pane.worktreeDirectory = URL(filePath: "/tmp/codex-worktree")
        pane.worktreeIsManaged = true
        pane.profileID = profileID
        pane.extraArgs = ["--model", "gpt-5.1"]
        pane.agentControlInjectionEnabled = true
        pane.installTerminalController(TerminalController())
        pane.terminalController?.pendingEnvironment = ["AGENT_SESSION_MANAGER_MCP_TOKEN=runtime-only-secret"]
        appState.notifications = [
            PaneNotification(
                id: notificationID,
                paneID: pane.id,
                paneName: pane.name,
                tabID: tab.id,
                tabName: tab.name,
                isPriority: true,
                timestamp: Date(timeIntervalSinceReferenceDate: 123_456),
                kind: .terminalBell,
                reason: "Existing notification")
        ]
        pane.codexLaunchResumeSessionID = "requested-session"
        let monitor = StatusLineMonitor(
            paneID: pane.id,
            paneName: pane.name,
            workingDirectory: "/tmp",
            harness: .codex,
            processStartTime: Date(),
            tabID: tab.id,
            tabName: tab.name,
            codexAdapter: .current(version: "0.162.1"))
        pane.installStatusLineMonitor(monitor)
        pane.bindNotifications(appState: appState, isPriority: false)

        monitor.onCodexSessionBound?("bound-session", "/tmp/rollout.jsonl")
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(pane.codexSessionID)
        XCTAssertNil(pane.codexTranscriptPath)
        XCTAssertEqual(pane.codexLaunchResumeSessionID, "requested-session")
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appending(path: "sessions.json").path))
        XCTAssertTrue(
            InvariantReporter.shared.violationsForTesting.contains {
                $0.invariantID == "codex.continuation.identity"
                    && $0.context["requested_session_id_prefix"] == "requested-se"
                    && $0.context["bound_session_id_prefix"] == "bound-sessio"
            })
    }

    func testOpencodePortRaceLossRestartsPaneWithFreshPortOnce() async {
        let appState = AppState()
        let tab = Tab(id: UUID(), name: "T", directory: URL(fileURLWithPath: "/tmp"))
        let pane = Pane(name: "P", tab: tab, harness: .opencode)
        let controller = TerminalController()
        controller.pendingDirectory = "/tmp"
        controller.pendingCommandArgs = ["opencode"]
        pane.installTerminalController(controller)
        tab.panes.append(pane)

        let originalPort = 12345
        pane.opencodePort = originalPort
        let monitor = StatusLineMonitor(
            paneID: pane.id, paneName: pane.name, workingDirectory: "/tmp",
            harness: .opencode, processStartTime: Date(), tabID: tab.id, tabName: tab.name,
            opencodePort: originalPort)
        pane.installStatusLineMonitor(monitor)
        pane.bindNotifications(appState: appState, isPriority: false)

        let originalToken = pane.restartToken
        pane.statusLineMonitor?.onOpencodePortRaceLost?()
        try? await Task.sleep(for: .milliseconds(100))

        let restartedPort = pane.opencodePort
        let restartedToken = pane.restartToken
        XCTAssertNotNil(restartedPort)
        XCTAssertNotEqual(restartedPort, originalPort)
        XCTAssertNotEqual(restartedToken, originalToken)
        XCTAssertTrue(pane.opencodeRaceLossRestarted)

        pane.statusLineMonitor?.onOpencodePortRaceLost?()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(pane.opencodePort, restartedPort)
        XCTAssertEqual(pane.restartToken, restartedToken)

        pane.removeStatusLineMonitor()
        pane.terminalController?.terminate()
    }

    func testBaseBranchOverrideRoundTripsInPersistedTab() throws {
        let id = UUID()
        let tab = PersistedTab(id: id, name: "T", directory: "/tmp", baseBranchOverride: "qa", panes: [])
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(PersistedTab.self, from: data)
        XCTAssertEqual(decoded.baseBranchOverride, "qa")
    }

    func testBaseBranchOverrideNilRoundTrips() throws {
        let id = UUID()
        let tab = PersistedTab(id: id, name: "T", directory: "/tmp", panes: [])
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(PersistedTab.self, from: data)
        XCTAssertNil(decoded.baseBranchOverride)
    }

    func testLegacyTabWithoutBaseBranchOverrideDecodesNil() throws {
        let json = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "T",
              "directory": "/tmp",
              "panes": []
            }
            """.utf8)
        let decoded = try JSONDecoder().decode(PersistedTab.self, from: json)
        XCTAssertNil(decoded.baseBranchOverride)
    }
}
