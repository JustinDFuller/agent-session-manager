import XCTest

extension BaseTestCase {
    var cleanupWait: TimeInterval { 25 }

    func showsText(_ text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        return app.sheets.staticTexts.matching(predicate).firstMatch.exists
    }

    func makeUnsavedWorktree(folder: String) {
        GitUITestWorkspace.addManagedSecondaryWorktree(folder: folder, newTrackingBranch: "track-\(folder)")
        let checkout = GitUITestWorkspace.worktreeURL(folder: folder)
        try? Data("committed".utf8).write(to: checkout.appending(path: "committed.txt"))
        GitUITestWorkspace.runGitOrFail(["add", "committed.txt"], cwd: checkout)
        GitUITestWorkspace.runGitOrFail(
            ["-c", "user.email=uitest@example.com", "-c", "user.name=uitest", "commit", "-m", "local work"],
            cwd: checkout)
        try? Data("scratch".utf8).write(to: checkout.appending(path: "scratch.txt"))
    }

    func openPane(named name: String) {
        app.typeKey("p", modifierFlags: .command)
        let field = app.textFields["new-pane-name-field"]
        waitFor(field)
        field.click()
        field.typeText(name)
        app.buttons["new-pane-open-button"].click()
        waitForDisappear(field, timeout: cleanupWait)
        waitFor(app.staticTexts.matching(identifier: "pane-name-\(name)").firstMatch, timeout: 10)
    }

    func closePane(named name: String) {
        app.descendants(matching: .any).matching(identifier: "pane-close-\(name)").firstMatch.click()
        let delete = app.windows.buttons["Delete Worktree"].firstMatch
        if delete.waitForExistence(timeout: 5) { delete.click() }
    }

    func openSettingsPanes() {
        app.typeKey(",", modifierFlags: .command)
        let sidebar = app.descendants(matching: .any).matching(identifier: "settings-sidebar-panes").firstMatch
        waitFor(sidebar, timeout: 10)
        sidebar.click()
    }

    func select(_ row: XCUIElement) {
        let isOn = (row.value as? NSNumber)?.intValue == 1 || (row.value as? String) == "1"
        if !isOn { row.click() }
    }

    func scrollToVisible(_ element: XCUIElement) {
        let window = app.windows["AgentSessionManager Settings"]
        let content = window.scrollViews.containing(.button, identifier: "settings-leftovers-refresh").firstMatch
        var attempts = 0
        while !element.exists || !window.frame.contains(element.frame), attempts < 20 {
            content.scroll(byDeltaX: 0, deltaY: -400)
            attempts += 1
        }
        waitFor(element)
    }

    func waitUntil(timeout: TimeInterval = 30, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(condition(), "Condition was not met within \(timeout)s")
    }
}
