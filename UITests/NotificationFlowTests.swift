import XCTest

final class NotificationFlowTests: BaseTestCase {
    func testPRMergedNotificationFlow() throws {
        let shell = Process()
        let output = Pipe()
        shell.executableURL = URL(filePath: "/bin/zsh")
        shell.arguments = [
            "-i", "-c",
            "command -v gh; gh pr view 377 --repo JustinDFuller-org/agent-session-manager --json number,headRefName,state",
        ]
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice
        try shell.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()
        guard shell.terminationStatus == 0 else {
            throw XCTSkip("The real merged-PR flow requires GitHub CLI access to the repository")
        }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", maxSplits: 1)
        XCTAssertEqual(lines.count, 2)
        let executable = String(lines[0])
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
        XCTAssertEqual(metadata["state"] as? String, "MERGED")
        let branch = try XCTUnwrap(metadata["headRefName"] as? String)
        let number = try XCTUnwrap(metadata["number"] as? Int)
        let directory = GitUITestWorkspace.directoryURL
        GitUITestWorkspace.runGitOrFail(
            ["remote", "add", "origin", "https://github.com/JustinDFuller-org/agent-session-manager.git"],
            cwd: directory)
        GitUITestWorkspace.runGitOrFail(
            ["fetch", "--depth=1", "origin", "refs/pull/\(number)/head"], cwd: directory)
        GitUITestWorkspace.runGitOrFail(
            ["worktree", "add", ".agent-session-manager/worktrees/merged-pr", "-b", branch, "FETCH_HEAD"],
            cwd: directory)

        createTab(named: "MergedPR")
        createPane(named: "merged-pr")
        app.terminate()
        app.launchEnvironment["GH_PATH"] = executable
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.activate()

        let row = app.descendants(matching: .any).matching(identifier: "notification-row-merged-pr").firstMatch
        waitFor(row, timeout: 30)
        XCTAssertTrue(row.label.contains("MergedPR / merged-pr"))
        XCTAssertTrue(row.label.contains("PR #\(number) merged"))
        row.click()
        let alert = app.sheets.containing(.button, identifier: "Close Pane").firstMatch
        waitFor(alert)
        XCTAssertTrue(alert.buttons["Close Pane"].exists)
        XCTAssertTrue(alert.buttons["Close Pane and Clean Up Worktree"].exists)
        alert.buttons["Cancel"].click()
        waitForDisappear(alert)
        XCTAssertEqual(app.buttons["tab-button-MergedPR"].firstMatch.value as? String, "active")
        waitForDisappear(row)

        app.typeKey(",", modifierFlags: .command)
        let notificationsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-notifications").firstMatch
        waitFor(notificationsTab)
        notificationsTab.click()
        waitFor(app.checkBoxes["settings-pr-merged-notifications-toggle"])
    }

    func testRegularNotificationReasonFlow() {
        createTab(named: "Attention")
        createPane(named: "attention-source")
        let shellName = openShellHere(from: "attention-source")
        let terminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-\(shellName)").firstMatch
        waitFor(terminal)
        terminal.click()
        typeTerminalCommand("printf '\\033]777;notify;Agent Session Manager;Permission needed for Bash\\007'")
        let row = app.descendants(matching: .any)
            .matching(identifier: "notification-row-\(shellName)").firstMatch
        waitFor(row)
        XCTAssertTrue(row.label.contains("Attention / \(shellName)"))
        XCTAssertTrue(row.label.contains("Permission needed for Bash"))
        row.click()
        waitForDisappear(row)
        XCTAssertTrue(app.staticTexts["pane-name-\(shellName)"].exists)
    }
}
