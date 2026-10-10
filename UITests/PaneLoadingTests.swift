import XCTest

final class PaneLoadingTests: BaseTestCase {
    func testLoadingOverlayIsVisible() throws {
        let directory = GitUITestWorkspace.directoryURL.appending(path: ".git/hooks")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hook = directory.appending(path: "post-checkout")
        try Data("#!/bin/sh\nsleep 10\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        GitUITestWorkspace.runGitOrFail(
            ["config", "core.hooksPath", directory.path], cwd: GitUITestWorkspace.directoryURL)
        createTab(named: "LoadingTab")
        app.typeKey("p", modifierFlags: .command)
        let field = app.textFields["new-pane-name-field"]
        waitFor(field)
        field.click()
        field.typeText("loading-pane")
        app.buttons["new-pane-open-button"].click()

        let overlay = app.descendants(matching: .any)
            .matching(identifier: "pane-loading-overlay-loading-pane").firstMatch
        waitFor(overlay)
        waitForDisappear(overlay, timeout: 20)
        waitFor(app.descendants(matching: .any).matching(identifier: "pane-terminal-loading-pane").firstMatch)
    }

    func testErrorOverlayIsVisible() throws {
        let directory = GitUITestWorkspace.directoryURL.appending(path: ".agent-session-manager/worktrees/error-pane")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        createTab(named: "ErrorTab")
        app.typeKey("p", modifierFlags: .command)
        let field = app.textFields["new-pane-name-field"]
        waitFor(field)
        field.click()
        field.typeText("error-pane")
        app.buttons["new-pane-open-button"].click()

        let overlay = app.descendants(matching: .any)
            .matching(identifier: "pane-error-overlay-error-pane").firstMatch
        waitFor(overlay, timeout: 15)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'not a git worktree' OR value CONTAINS 'not a git worktree'")
            ).firstMatch.exists)
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "pane-terminal-error-pane").firstMatch.exists)
    }
}
