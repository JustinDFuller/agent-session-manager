import XCTest

final class WorktreeFlowTests: BaseTestCase {
    private let primaryCheckoutPaneIdentifier = "UITestWorkspace"
    private let paneWait: TimeInterval = 25

    override func setUp() {
        super.setUp()
        try? Data("\"head\"".utf8).write(to: UITestAppSupport.directory.appending(path: "worktree-base-ref.json"))
        createTab(named: "RoutingTab")
    }

    func testWorktreeRoutingFlow() {
        app.typeKey("p", modifierFlags: .command)
        var nameField = app.textFields["new-pane-name-field"]
        waitFor(nameField)
        let uniqueName = "uitest-pane-\(UUID().uuidString.prefix(8))"
        nameField.click()
        nameField.typeText(uniqueName)
        app.buttons["new-pane-open-button"].click()

        XCTAssertFalse(app.scrollViews["new-pane-worktree-error"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "pane-close-\(uniqueName)").firstMatch
                .waitForExistence(timeout: paneWait))
        XCTAssertFalse(app.textFields["new-pane-name-field"].waitForExistence(timeout: 2))

        GitUITestWorkspace.runGitOrFail(["branch", "loose-ui", "HEAD"], cwd: GitUITestWorkspace.directoryURL)
        app.typeKey("p", modifierFlags: .command)
        nameField = app.textFields["new-pane-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("loose-ui")
        app.buttons["new-pane-open-button"].click()

        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "pane-close-loose-ui").firstMatch.waitForExistence(
                timeout: paneWait))
        XCTAssertFalse(app.scrollViews["new-pane-worktree-error"].waitForExistence(timeout: 2))

        app.typeKey("p", modifierFlags: .command)
        nameField = app.textFields["new-pane-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("ui-root")
        app.buttons["new-pane-open-button"].click()

        let cancelBtn = app.dialogs.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancelBtn.waitForExistence(timeout: paneWait))
        cancelBtn.click()
        let dontManageBtn =
            app.dialogs.buttons["Don't Manage"].firstMatch
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, dontManageBtn.exists || cancelBtn.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(dontManageBtn.exists || cancelBtn.exists)
        let cancelledPane = app.staticTexts["pane-name-ui-root"].firstMatch
        waitFor(cancelledPane)
        let removePane = app.windows.buttons["Remove Pane"].firstMatch
        waitFor(removePane)
        removePane.click()
        let keepCancelledWorktree = app.sheets.buttons["Keep Worktree"].firstMatch
        waitFor(keepCancelledWorktree)
        keepCancelledWorktree.click()
        waitForDisappear(cancelledPane)
        app.typeKey("p", modifierFlags: .command)
        nameField = app.textFields["new-pane-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("ui-root")
        app.buttons["new-pane-open-button"].click()
        let continueBtn = app.dialogs.buttons["Don't Manage"].firstMatch
        XCTAssertTrue(continueBtn.waitForExistence(timeout: paneWait))
        continueBtn.click()

        XCTAssertTrue(
            app.staticTexts.matching(identifier: "pane-name-\(primaryCheckoutPaneIdentifier)").firstMatch
                .waitForExistence(timeout: paneWait))
        XCTAssertFalse(app.textFields["new-pane-name-field"].waitForExistence(timeout: 2))

        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-dup", newTrackingBranch: "wt-track-dup-ui")
        app.typeKey("p", modifierFlags: .command)
        nameField = app.textFields["new-pane-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("wt-dup")
        app.buttons["new-pane-open-button"].click()
        XCTAssertTrue(
            app.staticTexts.matching(identifier: "pane-name-wt-dup").firstMatch.waitForExistence(timeout: paneWait))

        app.typeKey("p", modifierFlags: .command)
        nameField = app.textFields["new-pane-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("wt-dup")
        let dupError = app.staticTexts["new-pane-name-error"]
        waitFor(dupError)
        XCTAssertFalse(app.buttons["new-pane-open-button"].isEnabled)
        app.buttons["new-pane-cancel-button"].click()
        waitForDisappear(nameField)

        GitUITestWorkspace.addManagedSecondaryWorktree(folder: "wt-side", newTrackingBranch: "wt-track-side-ui")
        app.typeKey("p", modifierFlags: .command)
        nameField = app.textFields["new-pane-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("wt-side")
        app.buttons["new-pane-open-button"].click()
        XCTAssertTrue(
            app.staticTexts.matching(identifier: "pane-name-wt-side").firstMatch.waitForExistence(timeout: paneWait))
    }

    func testWorktreeCleanupFlow() {
        openPrimaryCheckoutPane()
        let primaryPaneName = app.staticTexts.matching(identifier: "pane-name-UITestWorkspace").firstMatch
        waitFor(primaryPaneName, timeout: paneWait)

        app.descendants(matching: .any).matching(identifier: "pane-close-UITestWorkspace").firstMatch.click()
        screenshot("14-simple-close")

        XCTAssertFalse(app.windows.buttons["Keep Worktree"].firstMatch.waitForExistence(timeout: 2))
        waitForDisappear(primaryPaneName)

        createManagedWorktreePane(folder: "wt-alert")
        app.descendants(matching: .any).matching(identifier: "pane-close-wt-alert").firstMatch.click()
        screenshot("15-cleanup-alert")

        let keepButton = app.windows.buttons["Keep Worktree"].firstMatch
        XCTAssertTrue(keepButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.buttons["Delete Worktree"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists)

        app.windows.firstMatch.buttons["Cancel"].firstMatch.click()
        waitForDisappear(keepButton)

        createManagedWorktreePane(folder: "wt-managed")
        openPrimaryCheckoutPane()
        let primaryPaneName2 = app.staticTexts.matching(identifier: "pane-name-UITestWorkspace").firstMatch
        waitFor(primaryPaneName2, timeout: paneWait)

        app.descendants(matching: .any).matching(identifier: "pane-close-UITestWorkspace").firstMatch.click()
        XCTAssertFalse(app.windows.buttons["Keep Worktree"].firstMatch.waitForExistence(timeout: 2))
        waitForDisappear(primaryPaneName2)

        app.descendants(matching: .any).matching(identifier: "pane-close-wt-managed").firstMatch.click()
        screenshot("16-mixed-close")
        XCTAssertTrue(app.windows.buttons["Keep Worktree"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.buttons["Delete Worktree"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists)
    }

    func testWorktreeDeleteFlowClosesImmediately() {
        createManagedWorktreePane(folder: "wt-immediate")

        let paneLabel = app.staticTexts.matching(identifier: "pane-name-wt-immediate").firstMatch
        XCTAssertTrue(paneLabel.waitForExistence(timeout: paneWait))

        app.descendants(matching: .any).matching(identifier: "pane-close-wt-immediate").firstMatch.click()

        let deleteButton = app.windows.buttons["Delete Worktree"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.click()

        XCTAssertFalse(paneLabel.waitForExistence(timeout: 2))
    }

    func testBaseBranchOverrideCreatesWorktreeFromOverrideBranch() {
        GitUITestWorkspace.runGitOrFail(["branch", "qa-ui", "HEAD"], cwd: GitUITestWorkspace.directoryURL)

        app.typeKey("t", modifierFlags: .command)
        let nameField = app.textFields["new-tab-name-field"]
        waitFor(nameField)
        nameField.click()
        nameField.typeText("OverrideTab")
        app.buttons["new-tab-choose-dir-button"].click()
        waitFor(app.buttons["new-tab-create-button"])
        let baseBranchField = app.textFields["new-tab-base-branch-field"]
        waitFor(baseBranchField)
        baseBranchField.click()
        baseBranchField.typeText("qa-ui")
        app.buttons["new-tab-create-button"].click()
        waitFor(app.buttons["tab-button-OverrideTab"].firstMatch)

        let uniqueName = "qa-override-\(UUID().uuidString.prefix(8))"
        app.typeKey("p", modifierFlags: .command)
        let paneField = app.textFields["new-pane-name-field"]
        waitFor(paneField)
        paneField.click()
        paneField.typeText(uniqueName)
        app.buttons["new-pane-open-button"].click()

        XCTAssertFalse(app.scrollViews["new-pane-worktree-error"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.staticTexts.matching(identifier: "pane-name-\(uniqueName)").firstMatch
                .waitForExistence(timeout: paneWait))
    }

    private func openPrimaryCheckoutPane() {
        app.typeKey("p", modifierFlags: .command)
        let field = app.textFields["new-pane-name-field"]
        waitFor(field)
        field.click()
        field.typeText("ui-root")
        app.buttons["new-pane-open-button"].click()
        let dontManage = app.dialogs.buttons["Don't Manage"].firstMatch
        XCTAssertTrue(dontManage.waitForExistence(timeout: paneWait))
        dontManage.click()
        waitForDisappear(field, timeout: 25)
    }

    private func createManagedWorktreePane(folder: String) {
        GitUITestWorkspace.addManagedSecondaryWorktree(
            folder: folder,
            newTrackingBranch: "track-\(folder)"
        )
        app.typeKey("p", modifierFlags: .command)
        let field = app.textFields["new-pane-name-field"]
        waitFor(field)
        field.click()
        field.typeText(folder)
        app.buttons["new-pane-open-button"].click()
        waitForDisappear(field, timeout: 25)
        waitFor(app.staticTexts.matching(identifier: "pane-name-\(folder)").firstMatch, timeout: 10)
    }
}
