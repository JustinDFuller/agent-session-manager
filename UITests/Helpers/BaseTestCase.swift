import XCTest

class BaseTestCase: XCTestCase {
    var app: XCUIApplication!

    var additionalLaunchArguments: [String] { [] }
    var additionalLaunchEnvironment: [String: String] { [:] }
    var appLaunchArguments: [String] { ["--uitesting", "--uitesting-skip-restore"] + additionalLaunchArguments }

    func prepareTestWorkspace() {}

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        clearPersistedState()
        GitUITestWorkspace.prepareCleanRepo()
        let support = UITestAppSupport.directory
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? Data("{\"isEnabled\":true,\"branchName\":\"ui-root\"}".utf8)
            .write(to: support.appending(path: "default-branch.json"))
        prepareTestWorkspace()

        app = XCUIApplication()
        app.launchArguments = appLaunchArguments
        app.launchEnvironment = additionalLaunchEnvironment.merging(["DISABLE_AUTO_UPDATE": "true"]) { _, value in value
        }
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for label in ["Allow", "Don’t Allow", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.click()
                    return true
                }
            }
            return false
        }
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "The app should reach the foreground")
        waitFor(app.windows.firstMatch, timeout: 15)
    }

    override func tearDown() {
        if let failureCount = testRun?.failureCount,
            failureCount > 0,
            app.state != .notRunning,
            app.windows.firstMatch.exists
        {
            let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            attachment.lifetime = .keepAlways
            attachment.name = "\(name)-failure"
            add(attachment)
        }
        if app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 10)
        }
        clearPersistedState()
        super.tearDown()
    }

    func screenshot(_ name: String) {
        screenshot(name, app: app)
    }

    func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected \(element.identifier) to exist within \(timeout)s"
        )
    }

    func waitForDisappear(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let pred = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: element)
        let result = XCTWaiter.wait(for: [exp], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected \(element.identifier) to disappear within \(timeout)s")
        XCTAssertNotEqual(
            app.state,
            .notRunning,
            "The application terminated while waiting for \(element.identifier) to disappear"
        )
    }

    var emptyStateHint: XCUIElement { app.staticTexts["empty-state-hint"] }

    func clearPersistedState() {
        let support = UITestAppSupport.directory
        for file in [
            "sessions.json", "settings.json", "codex-settings.json",
            "cursor-settings.json", "opencode-settings.json", "opencode-env-var-settings.json",
            "statusline-settings.json",
            "active-tools-settings.json", "default-branch.json",
            "notification-settings.json", "restart-settings.json",
            "worktree-cleanup.json", "existing-worktree-management.json",
            "debug-settings.json", "pr-tracking-settings.json",
            "tracing-settings.json", "pr-polling-settings.json",
            "terminal-settings.json", "worktree-base-ref.json", "exit-behavior.json",
            "env-var-settings.json", "profiles.json", "session-name-settings.json",
            "shell-settings.json", "onboarding-settings.json",
            "activity-indicator-settings.json", "focus-mode-settings.json",
            "app-lifecycle.json", "app-lifecycle.lock",
            "agent-control-settings.json",
        ] {
            try? FileManager.default.removeItem(at: support.appending(path: file))
        }
        try? FileManager.default.removeItem(at: support.appending(path: "traces"))
        try? FileManager.default.removeItem(at: support.appending(path: "invariants"))
    }
}
