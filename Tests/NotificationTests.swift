import XCTest

@testable import AgentSessionManager

@MainActor
private func restoreNotificationSettings(into settings: AppSettings) {
    guard let config = SettingsPersistence.load(NotificationConfig.self, from: "notification-settings.json") else {
        return
    }
    settings.notificationSidebarSide = config.sidebarSide
    settings.isPriorityNotificationsEnabled = config.isPriorityEnabled
    settings.isMacOSBannerNotificationsEnabled = config.isMacOSBannerEnabled
    settings.isCursorNotificationHookAttentionEnabled = config.isCursorHookAttentionEnabled
    settings.isPRMergedNotificationsEnabled = config.isPRMergedNotificationsEnabled
    settings.alwaysShowNotificationsSidebar = config.alwaysShowNotificationsSidebar
    settings.isClaudeStopNotificationEnabled = config.isClaudeStopNotificationEnabled
    settings.isOpencodeStopNotificationEnabled = config.isOpencodeStopNotificationEnabled
}

@MainActor
final class NotificationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PersistenceHelpers.overrideAppSupportSubdirectory = "agent-session-manager"
    }

    override func tearDown() {
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        super.tearDown()
    }

    func testAddNotification() {
        let state = AppState()
        let paneID = UUID()
        let tabID = UUID()
        state.addNotification(paneID: paneID, paneName: "auth-fix", tabID: tabID, tabName: "myapp", isPriority: false)
        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.notifications[0].paneID, paneID)
        XCTAssertEqual(state.notifications[0].paneName, "auth-fix")
        XCTAssertEqual(state.notifications[0].tabName, "myapp")
        XCTAssertFalse(state.notifications[0].isPriority)
    }

    func testAddNotificationDeduplication() {
        let state = AppState()
        let paneID = UUID()
        let tabID = UUID()
        state.addNotification(paneID: paneID, paneName: "auth-fix", tabID: tabID, tabName: "myapp", isPriority: false)
        state.addNotification(paneID: paneID, paneName: "auth-fix", tabID: tabID, tabName: "myapp", isPriority: false)
        XCTAssertEqual(state.notifications.count, 1)
    }

    func testAddNotificationRefreshesSamePaneReasonAndTimestamp() {
        let state = AppState()
        let paneID = UUID()
        let tabID = UUID()
        state.addNotification(
            paneID: paneID, paneName: "auth-fix", tabID: tabID, tabName: "myapp", isPriority: false,
            event: PaneAttentionEvent(source: .osc777, reason: "First"))
        let first = state.notifications[0]
        state.addNotification(
            paneID: paneID, paneName: "auth-fix", tabID: tabID, tabName: "myapp", isPriority: false,
            event: PaneAttentionEvent(source: .osc777, reason: "Second"))
        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.notifications[0].reason, "Second")
        XCTAssertNotEqual(state.notifications[0].id, first.id)
        XCTAssertGreaterThanOrEqual(state.notifications[0].timestamp, first.timestamp)
    }

    func testAddNotificationIncludesActivePane() {
        let state = AppState()
        let paneID = UUID()
        state.activePaneID = paneID
        state.addNotification(paneID: paneID, paneName: "auth-fix", tabID: UUID(), tabName: "myapp", isPriority: false)
        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.notifications[0].paneID, paneID)
    }

    func testClearNotification() {
        let state = AppState()
        let paneID = UUID()
        state.addNotification(paneID: paneID, paneName: "auth-fix", tabID: UUID(), tabName: "myapp", isPriority: false)
        state.clearNotification(paneID: paneID)
        XCTAssertTrue(state.notifications.isEmpty)
    }

    func testClearNotificationOnlyRemovesTargetPane() {
        let state = AppState()
        let pane1 = UUID()
        let pane2 = UUID()
        let tabID = UUID()
        state.addNotification(paneID: pane1, paneName: "pane1", tabID: tabID, tabName: "myapp", isPriority: false)
        state.addNotification(paneID: pane2, paneName: "pane2", tabID: tabID, tabName: "myapp", isPriority: false)
        state.clearNotification(paneID: pane1)
        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.notifications[0].paneID, pane2)
    }

    func testSetActivePaneClearsNotification() {
        let state = AppState()
        let paneID = UUID()
        let tabID = UUID()
        state.addNotification(paneID: paneID, paneName: "auth-fix", tabID: tabID, tabName: "myapp", isPriority: false)
        XCTAssertEqual(state.notifications.count, 1)
        state.setActivePane(id: paneID)
        XCTAssertTrue(state.notifications.isEmpty)
    }

    func testSetActivePaneNilDoesNotClear() {
        let state = AppState()
        let paneID = UUID()
        state.addNotification(paneID: paneID, paneName: "auth-fix", tabID: UUID(), tabName: "myapp", isPriority: false)
        state.setActivePane(id: nil)
        XCTAssertEqual(state.notifications.count, 1)
    }

    func testPriorityNotification() {
        let state = AppState()
        state.addNotification(paneID: UUID(), paneName: "pane1", tabID: UUID(), tabName: "myapp", isPriority: true)
        XCTAssertTrue(state.notifications[0].isPriority)
    }

    func testNotificationSettingsDefaults() {
        let settings = AppSettings()
        XCTAssertEqual(settings.notificationSidebarSide, .left)
        XCTAssertTrue(settings.isPriorityNotificationsEnabled)
        XCTAssertTrue(settings.isMacOSBannerNotificationsEnabled)
        XCTAssertTrue(settings.alwaysShowNotificationsSidebar)
    }

    func testNotificationSettingsPersistRoundTrip() {
        let notificationURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "agent-session-manager/notification-settings.json")
        defer { try? FileManager.default.removeItem(at: notificationURL) }

        let settings = AppSettings()
        settings.notificationSidebarSide = .left
        settings.isPriorityNotificationsEnabled = false
        settings.isMacOSBannerNotificationsEnabled = false
        settings.alwaysShowNotificationsSidebar = false
        SettingsPersistence.saveNotificationSettings(appSettings: settings)

        let restored = AppSettings()
        restoreNotificationSettings(into: restored)
        XCTAssertEqual(restored.notificationSidebarSide, .left)
        XCTAssertFalse(restored.isPriorityNotificationsEnabled)
        XCTAssertFalse(restored.isMacOSBannerNotificationsEnabled)
        XCTAssertFalse(restored.alwaysShowNotificationsSidebar)
    }

    func testClaudeStopNotificationEnabledRoundTrip() {
        let notificationURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "agent-session-manager/notification-settings.json")
        defer { try? FileManager.default.removeItem(at: notificationURL) }

        let settings = AppSettings()
        settings.isClaudeStopNotificationEnabled = false
        SettingsPersistence.saveNotificationSettings(appSettings: settings)

        let restored = AppSettings()
        restoreNotificationSettings(into: restored)
        XCTAssertFalse(restored.isClaudeStopNotificationEnabled)
    }

    func testOpencodeStopNotificationEnabledRoundTrip() {
        let notificationURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "agent-session-manager/notification-settings.json")
        defer { try? FileManager.default.removeItem(at: notificationURL) }

        let settings = AppSettings()
        settings.isOpencodeStopNotificationEnabled = false
        SettingsPersistence.saveNotificationSettings(appSettings: settings)

        let restored = AppSettings()
        restoreNotificationSettings(into: restored)
        XCTAssertFalse(restored.isOpencodeStopNotificationEnabled)
    }

    func testOpencodeStopNotificationEnabledLegacyDefaultsTrue() throws {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "agent-session-manager")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appending(path: "notification-settings.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data(#"{"sidebarSide":"right","isPriorityEnabled":true}"#.utf8).write(to: url)
        let restored = AppSettings()
        restored.isOpencodeStopNotificationEnabled = false
        restoreNotificationSettings(into: restored)
        XCTAssertTrue(restored.isOpencodeStopNotificationEnabled)
    }

    func testClaudeStopNotificationEnabledLegacyDefaultsTrue() throws {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "agent-session-manager")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appending(path: "notification-settings.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data(#"{"sidebarSide":"right","isPriorityEnabled":true}"#.utf8).write(to: url)
        let restored = AppSettings()
        restored.isClaudeStopNotificationEnabled = false
        restoreNotificationSettings(into: restored)
        XCTAssertTrue(restored.isClaudeStopNotificationEnabled)
    }

    func testAlwaysShowNotificationsSidebarRoundTrip() {
        let notificationURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "agent-session-manager/notification-settings.json")
        defer { try? FileManager.default.removeItem(at: notificationURL) }

        let settings = AppSettings()
        settings.alwaysShowNotificationsSidebar = true
        SettingsPersistence.saveNotificationSettings(appSettings: settings)

        let restored = AppSettings()
        restored.alwaysShowNotificationsSidebar = false
        restoreNotificationSettings(into: restored)
        XCTAssertTrue(restored.alwaysShowNotificationsSidebar)
    }

    func testAlwaysShowNotificationsSidebarLegacyJSONDefaultsTrue() throws {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "agent-session-manager")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appending(path: "notification-settings.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let legacy = Data(
            """
            {"sidebarSide":"right","isPriorityEnabled":true,"isMacOSBannerEnabled":true,"isClaudeHookAttentionEnabled":true,"isPRMergedNotificationsEnabled":true}
            """.utf8)
        try legacy.write(to: url)

        let restored = AppSettings()
        restored.alwaysShowNotificationsSidebar = false
        restoreNotificationSettings(into: restored)
        XCTAssertTrue(restored.alwaysShowNotificationsSidebar)
    }

    func testLegacyClaudeHookAttentionKeyIsIgnoredAndOmittedOnSave() throws {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "agent-session-manager")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appending(path: "notification-settings.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data(#"{"isClaudeHookAttentionEnabled":false}"#.utf8).write(to: url)
        let restored = AppSettings()
        restoreNotificationSettings(into: restored)
        SettingsPersistence.saveNotificationSettings(appSettings: restored)

        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil(saved["isClaudeHookAttentionEnabled"])
    }

    func testNotificationSettingsLegacyJSONDefaultsMacOSBannerOn() throws {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "agent-session-manager")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appending(path: "notification-settings.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let legacy = Data(
            """
            {"sidebarSide":"left","isPriorityEnabled":true}
            """.utf8)
        try legacy.write(to: url)

        let restored = AppSettings()
        restored.isMacOSBannerNotificationsEnabled = false
        restoreNotificationSettings(into: restored)
        XCTAssertEqual(restored.notificationSidebarSide, .left)
        XCTAssertTrue(restored.isPriorityNotificationsEnabled)
        XCTAssertTrue(restored.isMacOSBannerNotificationsEnabled)
    }

    func testPersistedPaneIsPriorityRoundTrip() throws {
        let pane = PersistedPane(id: UUID(), name: "test", harness: .claude, isPriority: true)
        let data = try JSONEncoder().encode(pane)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: data)
        XCTAssertTrue(decoded.isPriority)
    }

    func testPersistedPaneIsPriorityDefaultsFalse() throws {
        let json = Data(
            """
            {"id":"00000000-0000-0000-0000-000000000001","name":"test","harness":"claude"}
            """.utf8)
        let decoded = try JSONDecoder().decode(PersistedPane.self, from: json)
        XCTAssertFalse(decoded.isPriority)
    }

    func testUserInputClearsNotificationForActivePane() {
        let state = AppState()
        let paneID = UUID()
        state.addNotification(paneID: paneID, paneName: "fix", tabID: UUID(), tabName: "myapp", isPriority: false)
        XCTAssertEqual(state.notifications.count, 1)
        state.clearNotification(paneID: paneID)
        XCTAssertTrue(state.notifications.isEmpty)
    }

    func testUserInputIsNoOpWhenNoNotification() {
        let state = AppState()
        let paneID = UUID()
        state.clearNotification(paneID: paneID)
        XCTAssertTrue(state.notifications.isEmpty)
    }

    func testUserInputInPaneDoesNotClearOtherPanesNotifications() {
        let state = AppState()
        let typingPane = UUID()
        let otherPane = UUID()
        let tabID = UUID()
        state.addNotification(paneID: otherPane, paneName: "other", tabID: tabID, tabName: "myapp", isPriority: false)
        state.clearNotification(paneID: typingPane)
        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.notifications[0].paneID, otherPane)
    }

    func testSidebarSideCodable() throws {
        let encoded = try JSONEncoder().encode(SidebarSide.left)
        let decoded = try JSONDecoder().decode(SidebarSide.self, from: encoded)
        XCTAssertEqual(decoded, .left)
    }

    func testSidebarSideDisplayNames() {
        XCTAssertEqual(SidebarSide.left.displayName, "Left")
        XCTAssertEqual(SidebarSide.right.displayName, "Right")
    }

    func testPaneNotificationHasUniqueIDs() {
        let tabID = UUID()
        let paneID = UUID()
        let n1 = PaneNotification(paneID: paneID, paneName: "pane", tabID: tabID, tabName: "tab", isPriority: false)
        let n2 = PaneNotification(paneID: paneID, paneName: "pane", tabID: tabID, tabName: "tab", isPriority: false)
        XCTAssertNotEqual(n1.id, n2.id)
    }

    func testRawBellReason() {
        XCTAssertEqual(PaneAttentionEvent.rawBell.reason, "Attention needed")
    }

    func testOsc777UsesBodyThenTitleThenFallbackAndNormalizesWhitespace() {
        XCTAssertEqual(PaneAttentionEvent.osc777("notify; title ; body \n text ")?.reason, "body text")
        XCTAssertEqual(PaneAttentionEvent.osc777("notify; title ;  ")?.reason, "title")
        XCTAssertEqual(PaneAttentionEvent.osc777("notify;;")?.reason, "Attention needed")
    }

    func testClaudeNotificationUsesMessageThenTitleThenFallback() {
        XCTAssertEqual(
            claudeEvent(#"{"hook_event_name":"Notification","message":" message ","title":"title"}"#)?.reason, "message"
        )
        XCTAssertEqual(
            claudeEvent(#"{"hook_event_name":"Notification","message":" ","title":" title "}"#)?.reason, "title")
        XCTAssertEqual(claudeEvent(#"{"hook_event_name":"Notification"}"#)?.reason, "Attention needed")
    }

    func testClaudePermissionRequestUsesToolNameThenFallback() {
        XCTAssertEqual(
            claudeEvent(#"{"hook_event_name":"PermissionRequest","tool_name":" Bash "}"#)?.reason,
            "Permission needed for Bash")
        XCTAssertEqual(claudeEvent(#"{"hook_event_name":"PermissionRequest"}"#)?.reason, "Permission needed")
    }

    func testClaudeQuestionAndPlanPreToolUseAttention() {
        let question = claudeEvent(#"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}"#)
        XCTAssertEqual(question?.source.rawValue, "claude_question")
        XCTAssertEqual(question?.reason, "Claude has a question")
        let plan = claudeEvent(#"{"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode"}"#)
        XCTAssertEqual(plan?.source.rawValue, "claude_plan_approval")
        XCTAssertEqual(plan?.reason, "Claude needs plan approval")
    }

    func testClaudePreToolUseIgnoresUnrelatedAndMissingTools() {
        XCTAssertNil(claudeEvent(#"{"hook_event_name":"PreToolUse","tool_name":"Bash"}"#))
        XCTAssertNil(claudeEvent(#"{"hook_event_name":"PreToolUse"}"#))
    }

    func testCursorStopReason() {
        XCTAssertEqual(PaneAttentionEvent.cursorStop.reason, "Agent turn completed")
    }

    func testClaudeStopReason() {
        XCTAssertEqual(PaneAttentionEvent.claudeStop.reason, "Claude finished responding")
    }

    func testOpencodeStopReason() {
        XCTAssertEqual(PaneAttentionEvent.opencodeStop.reason, "OpenCode finished responding")
    }

    func testAddNotificationClaudeStopCreatesClaudeStopKind() {
        let state = AppState()
        let paneID = UUID()
        state.addNotification(
            paneID: paneID, paneName: "pane", tabID: UUID(), tabName: "tab",
            isPriority: false, event: .claudeStop
        )
        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.notifications[0].kind, .claudeStop)
        XCTAssertEqual(state.notifications[0].reason, "Claude finished responding")
    }

    func testAddNotificationOpencodeStopCreatesOpencodeStopKind() {
        let state = AppState()
        let paneID = UUID()
        state.addNotification(
            paneID: paneID, paneName: "pane", tabID: UUID(), tabName: "tab",
            isPriority: false, event: .opencodeStop
        )
        XCTAssertEqual(state.notifications.count, 1)
        XCTAssertEqual(state.notifications[0].kind, .opencodeStop)
        XCTAssertEqual(state.notifications[0].reason, "OpenCode finished responding")
    }

    func testAddNotificationCursorStopCreatesCursorStopKind() {
        let state = AppState()
        state.addNotification(
            paneID: UUID(), paneName: "pane", tabID: UUID(), tabName: "tab",
            isPriority: false, event: .cursorStop
        )
        XCTAssertEqual(state.notifications[0].kind, .cursorStop)
        XCTAssertEqual(state.notifications[0].reason, "Agent turn completed")
    }

    func testAddNotificationTerminalBellCreatesTerminalBellKind() {
        let state = AppState()
        state.addNotification(
            paneID: UUID(), paneName: "pane", tabID: UUID(), tabName: "tab",
            isPriority: false, event: .rawBell
        )
        XCTAssertEqual(state.notifications[0].kind, .terminalBell)
    }

    func testAddNotificationOpencodePermissionRequestCreatesOpencodePermissionRequestKind() {
        let state = AppState()
        let event = PaneAttentionEvent(
            source: .opencodePermissionRequest,
            reason: "Permission needed for external_directory: /etc/*")
        state.addNotification(
            paneID: UUID(), paneName: "pane", tabID: UUID(), tabName: "tab",
            isPriority: false, event: event
        )
        XCTAssertEqual(state.notifications[0].kind, .opencodePermissionRequest)
        XCTAssertEqual(state.notifications[0].reason, "Permission needed for external_directory: /etc/*")
    }

    private func claudeEvent(_ json: String) -> PaneAttentionEvent? {
        PaneAttentionEvent.claudeHook(Data(json.utf8))
    }
}
