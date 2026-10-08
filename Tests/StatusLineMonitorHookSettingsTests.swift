import XCTest

@testable import AgentSessionManager

final class StatusLineMonitorHookSettingsTests: XCTestCase {
    private func makeSettings(hidePRStatus: Bool = false) -> [String: Any] {
        StatusLineMonitor.makeClaudeSettingsDictionaryForTesting(
            statusOutputPath: "/tmp/status.json",
            attentionOutputPath: "/tmp/attention.json",
            hookLogScriptPath: "/tmp/hooklog.py",
            hidePRStatus: hidePRStatus
        )
    }

    private func entries(for event: String, in hooks: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(hooks[event] as? [[String: Any]])
    }

    private func firstEntry(for event: String, in hooks: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap((hooks[event] as? [[String: Any]])?.first)
    }

    private func command(in entry: [String: Any]) throws -> String {
        try XCTUnwrap((entry["hooks"] as? [[String: Any]])?.first?["command"] as? String)
    }

    func testMakeClaudeSettingsAlwaysIncludesLifecycleHooks() throws {
        let settings = makeSettings()
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])

        for event in ["UserPromptSubmit", "Stop", "StopFailure"] {
            let entry = try firstEntry(for: event, in: hooks)
            XCTAssertEqual(try command(in: entry), "'/tmp/hooklog.py'")
        }
    }

    func testMakeClaudeSettingsIncludesFocusedAttentionHooks() throws {
        let hooks = try XCTUnwrap(makeSettings()["hooks"] as? [String: Any])

        XCTAssertEqual(
            try firstEntry(for: "PreToolUse", in: hooks)["matcher"] as? String,
            "AskUserQuestion|ExitPlanMode"
        )
        XCTAssertEqual(
            try firstEntry(for: "Notification", in: hooks)["matcher"] as? String,
            "permission_prompt|elicitation_dialog|idle_prompt|agent_needs_input"
        )
        for event in ["PreToolUse", "PermissionRequest", "Notification", "Elicitation"] {
            let entry = try firstEntry(for: event, in: hooks)
            XCTAssertEqual(try command(in: entry), "'/tmp/hooklog.py' --attention '/tmp/attention.json'")
        }
    }

    func testMakeClaudeSettingsDoesNotRegisterSubagentStopHook() throws {
        let hooks = try XCTUnwrap(makeSettings()["hooks"] as? [String: Any])
        XCTAssertNil(hooks["SubagentStop"])
    }

    func testMakeClaudeSettingsPreToolUseHasOnlyAttentionEntry() throws {
        let hooks = try XCTUnwrap(makeSettings()["hooks"] as? [String: Any])
        let preToolUseEntries = try entries(for: "PreToolUse", in: hooks)
        XCTAssertEqual(preToolUseEntries.count, 1)
        XCTAssertEqual(preToolUseEntries.first?["matcher"] as? String, "AskUserQuestion|ExitPlanMode")
        XCTAssertEqual(try command(in: preToolUseEntries[0]), "'/tmp/hooklog.py' --attention '/tmp/attention.json'")
    }

    func testMakeClaudeSettingsLogsAllNotificationTypesForObservability() throws {
        let hooks = try XCTUnwrap(makeSettings()["hooks"] as? [String: Any])
        let notificationEntries = try entries(for: "Notification", in: hooks)
        XCTAssertEqual(notificationEntries.count, 2)
        let unmatched = try XCTUnwrap(notificationEntries.first { $0["matcher"] == nil })
        XCTAssertEqual(try command(in: unmatched), "'/tmp/hooklog.py'")
    }

    func testMakeClaudeSettingsOmitsPRStatusFooterByDefault() {
        let settings = makeSettings()
        XCTAssertNil(settings["prStatusFooterEnabled"])
        XCTAssertNil(settings["showPRStatus"])
    }

    func testMakeClaudeSettingsIncludesPRStatusFooterFalseWhenHidden() {
        let settings = makeSettings(hidePRStatus: true)
        XCTAssertEqual(settings["prStatusFooterEnabled"] as? Bool, false)
        XCTAssertEqual(settings["showPRStatus"] as? Bool, false)
        XCTAssertNotNil(settings["hooks"])
        XCTAssertNotNil(settings["statusLine"])
    }
}
