import AppKit
import XCTest

final class SectionResizingDenseContentFlowTests: BaseTestCase {
    override var appLaunchArguments: [String] { ["--uitesting-skip-restore"] + additionalLaunchArguments }

    func testDenseGridKeepsLongMultirowStatusAndDividerGrabRegionsUsable() throws {
        let onboardingSkipButton = app.buttons["onboarding-skip-button"]
        waitFor(onboardingSkipButton)
        onboardingSkipButton.click()

        app.typeKey("t", modifierFlags: .command)
        let tabNameField = app.textFields["new-tab-name-field"]
        waitFor(tabNameField)
        tabNameField.click()
        tabNameField.typeText("Dense Content")
        app.buttons["new-tab-choose-dir-button"].click()
        let directoryPicker = app.dialogs["open-panel"]
        let selectDirectory = directoryPicker.buttons["OKButton"]
        waitFor(selectDirectory)
        let pickerInitiallyReady = expectation(
            for: NSPredicate(format: "hittable == true"), evaluatedWith: selectDirectory)
        wait(for: [pickerInitiallyReady], timeout: 15)
        directoryPicker.typeKey("g", modifierFlags: [.command, .shift])
        let folderEntryReady = expectation(
            for: NSPredicate(format: "hittable == false"), evaluatedWith: selectDirectory)
        wait(for: [folderEntryReady], timeout: 15)
        directoryPicker.typeKey("a", modifierFlags: .command)
        directoryPicker.typeText(GitUITestWorkspace.directoryURL.path)
        directoryPicker.typeKey(.enter, modifierFlags: [])
        let pickerReady = expectation(
            for: NSPredicate(format: "hittable == true"), evaluatedWith: selectDirectory)
        wait(for: [pickerReady], timeout: 15)
        selectDirectory.click()
        let directoryLabel = app.staticTexts["new-tab-directory-label"]
        waitFor(directoryLabel)
        XCTAssertEqual(
            (directoryLabel.value as? String).map { URL(filePath: $0).resolvingSymlinksInPath().path },
            GitUITestWorkspace.directoryURL.resolvingSymlinksInPath().path
        )
        let createTabButton = app.buttons["new-tab-create-button"]
        XCTAssertTrue(createTabButton.isEnabled)
        createTabButton.click()
        waitFor(app.buttons["tab-button-Dense Content"].firstMatch)

        let paneNames = (1...9).map { String(format: "dense-pane-%02d-long-title", $0) }
        for paneName in paneNames {
            createPane(named: paneName)
        }
        let lastPaneName = paneNames[paneNames.count - 1]
        let worktreePathSuffix = "/.agent-session-manager/worktrees/\(lastPaneName)"
        let expectedWorktreePath = GitUITestWorkspace.directoryURL
            .appending(path: String(worktreePathSuffix.dropFirst()))
            .resolvingSymlinksInPath().standardizedFileURL.path

        app.typeKey(",", modifierFlags: .command)
        let settingsWindow = app.windows["AgentSessionManager Settings"]
        waitFor(settingsWindow)
        let statusLineTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-status-line").firstMatch
        waitFor(statusLineTab)
        statusLineTab.click()

        let addCustomField = settingsWindow.buttons["settings-statusline-add-custom-field-button"]
        waitFor(addCustomField)
        addCustomField.click()
        let longLabel = "Dense Status Value With a Deliberately Long User Configured Label for Horizontal Reachability"
        let labelField = app.textFields["custom-statusline-label-field"]
        let commandField = app.textViews["custom-statusline-command-field"]
        waitFor(labelField)
        waitFor(commandField)
        labelField.click()
        labelField.typeText(longLabel)
        commandField.click()
        commandField.typeText("pwd")
        app.buttons["custom-statusline-save-button"].click()
        waitForDisappear(labelField)

        let contentScroll = settingsWindow.scrollViews
            .containing(.button, identifier: "settings-statusline-add-custom-field-button").firstMatch
        waitFor(contentScroll)
        let fourthRowAddItem = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-statusline-add-item-3").firstMatch
        for _ in 0..<40 where !fourthRowAddItem.exists || !fourthRowAddItem.isHittable {
            contentScroll.scroll(byDeltaX: 0, deltaY: -160)
        }
        waitFor(fourthRowAddItem)
        fourthRowAddItem.click()
        let customItem = app.menuItems[longLabel]
        waitFor(customItem)
        customItem.click()

        let addRow = settingsWindow.buttons["settings-statusline-add-row-button"]
        for _ in 0..<40 where !addRow.isHittable {
            contentScroll.scroll(byDeltaX: 0, deltaY: 120)
        }
        XCTAssertTrue(addRow.isHittable)
        addRow.click()
        let fifthRowAddItem = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-statusline-add-item-4").firstMatch
        for _ in 0..<40 where !fifthRowAddItem.exists || !fifthRowAddItem.isHittable {
            contentScroll.scroll(byDeltaX: 0, deltaY: 120)
        }
        waitFor(fifthRowAddItem)
        fifthRowAddItem.click()
        let versionItem = app.menuItems["Version"]
        waitFor(versionItem)
        versionItem.click()
        app.typeKey("w", modifierFlags: .command)
        waitForDisappear(settingsWindow)

        let mainWindow = app.windows[mainWindowTitle]
        waitFor(mainWindow)
        let initialFrame = mainWindow.frame
        let lowerRight = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.999))
        lowerRight.press(
            forDuration: 0.1,
            thenDragTo: lowerRight.withOffset(
                CGVector(dx: 900 - initialFrame.width, dy: 600 - initialFrame.height)
            )
        )
        XCTAssertGreaterThanOrEqual(mainWindow.frame.width, 900)
        XCTAssertGreaterThanOrEqual(mainWindow.frame.height, 600)

        let lastPane = app.descendants(matching: .any)
            .matching(identifier: "pane-\(lastPaneName)").firstMatch
        let lastTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-\(lastPaneName)").firstMatch
        let lastStatusHandle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Resize status line for \(lastPaneName)"))
            .firstMatch
        waitFor(lastPane)
        waitFor(lastTerminal)
        waitFor(lastStatusHandle)
        for paneName in paneNames {
            let paneCell = app.descendants(matching: .any)
                .matching(identifier: "pane-\(paneName)").firstMatch
            let header = app.descendants(matching: .any)
                .matching(identifier: "pane-header-\(paneName)").firstMatch
            let closeButton = app.buttons.matching(identifier: "pane-close-\(paneName)").firstMatch
            let terminal = app.descendants(matching: .any)
                .matching(identifier: "pane-terminal-\(paneName)").firstMatch
            waitFor(paneCell)
            waitFor(header)
            waitFor(closeButton)
            waitFor(terminal)
            XCTAssertTrue(app.staticTexts["pane-name-\(paneName)"].exists)
            XCTAssertTrue(paneCell.isHittable)
            XCTAssertTrue(header.isHittable)
            XCTAssertTrue(closeButton.isHittable)
            XCTAssertGreaterThanOrEqual(terminal.frame.height, 64)
        }
        screenshot("section-resizing-dense-nine-pane-status-before-interaction")

        let lastStatusHeight = (lastStatusHandle.value as? NSNumber)?.doubleValue ?? -1
        let viewportID = String(lastStatusHandle.identifier.dropFirst("pane-status-resize-".count))
        let lastStatusViewport = app.scrollViews["status-line-viewport-\(viewportID)"]
        let lastStatusContent = lastPane.descendants(matching: .any)
            .matching(identifier: "status-line-row").firstMatch
        waitFor(lastStatusViewport)
        waitFor(lastStatusContent)
        let initialStatusViewportFrame = lastStatusViewport.frame
        let longLabelText = lastPane.staticTexts[longLabel]
        let longValueText = lastPane.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@ OR value ENDSWITH %@", worktreePathSuffix, worktreePathSuffix)
        ).firstMatch
        waitFor(longLabelText, timeout: 45)
        waitFor(longValueText, timeout: 45)
        let statusContentBoundsBeforeResize = statusContentBounds(in: lastStatusViewport)
        XCTAssertGreaterThan(statusContentBoundsBeforeResize.height, lastStatusViewport.frame.height)
        XCTAssertGreaterThan(statusContentBoundsBeforeResize.width, lastStatusViewport.frame.width)
        let actualWorktreePath = try XCTUnwrap(
            [longValueText.value as? String, longValueText.label]
                .compactMap { $0 }
                .first { $0.hasSuffix(worktreePathSuffix) }
        )
        XCTAssertTrue(actualWorktreePath.hasSuffix(worktreePathSuffix))
        let actualCanonicalPath = URL(filePath: actualWorktreePath).resolvingSymlinksInPath()
            .standardizedFileURL.path
        XCTAssertEqual(actualCanonicalPath, expectedWorktreePath)

        for _ in 0..<8 {
            let currentStatusHeight = (lastStatusHandle.value as? NSNumber)?.doubleValue ?? -1
            if currentStatusHeight <= 24 { break }
            lastStatusHandle.rightClick()
            let decreaseStatus = app.menuItems["Decrease Resize status line for \(lastPaneName) Size"]
            waitFor(decreaseStatus)
            decreaseStatus.click()
        }
        XCTAssertEqual((lastStatusHandle.value as? NSNumber)?.doubleValue ?? -1, 24, accuracy: 1)
        XCTAssertLessThanOrEqual(lastStatusViewport.frame.height, 24.5)
        let resizedStatusHeight = try XCTUnwrap((lastStatusHandle.value as? NSNumber)?.doubleValue)
        let resizedStatusViewportFrame = lastStatusViewport.frame
        let statusContentBoundsAt24 = statusContentBounds(in: lastStatusViewport)
        XCTAssertGreaterThan(statusContentBoundsAt24.height, resizedStatusViewportFrame.height)
        XCTAssertGreaterThan(statusContentBoundsAt24.width, resizedStatusViewportFrame.width)

        let fifthRowLabel = lastPane.staticTexts["Version"]
        waitFor(fifthRowLabel)
        screenshot("section-resizing-dense-status-at-24-before-vertical-scroll")
        let beforeVerticalScrollGeometry = XCTAttachment(
            string:
                "viewportBeforeResize=\(initialStatusViewportFrame); statusHeightBeforeResize=\(lastStatusHeight); viewport=\(lastStatusViewport.frame); content=\(statusContentBoundsAt24); version=\(fifthRowLabel.frame); terminal=\(lastTerminal.frame)"
        )
        beforeVerticalScrollGeometry.name = "section-resizing-dense-status-before-vertical-scroll-geometry"
        beforeVerticalScrollGeometry.lifetime = .keepAlways
        add(beforeVerticalScrollGeometry)
        let statusHierarchy = XCTAttachment(string: lastStatusViewport.debugDescription)
        statusHierarchy.name = "section-resizing-dense-status-hierarchy-before-scroll"
        statusHierarchy.lifetime = .keepAlways
        add(statusHierarchy)
        var verticalScrollMeasurements: [String] = []
        for iteration in 0..<12 where !fifthRowLabel.isHittable {
            let verticalScrollPoint = lastStatusViewport.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            verticalScrollPoint.scroll(byDeltaX: 0, deltaY: -64)
            verticalScrollMeasurements.append(
                "iteration=\(iteration + 1); viewport=\(lastStatusViewport.frame); scrollpoint=\(verticalScrollPoint.screenPoint); version=\(fifthRowLabel.frame); terminal=\(lastTerminal.frame)"
            )
        }
        let verticalScrollGeometry = XCTAttachment(
            string: verticalScrollMeasurements.joined(separator: "\n")
        )
        verticalScrollGeometry.name = "section-resizing-dense-status-vertical-scroll-measurements"
        verticalScrollGeometry.lifetime = .keepAlways
        add(verticalScrollGeometry)
        screenshot("section-resizing-dense-status-after-vertical-scroll")
        XCTAssertTrue(fifthRowLabel.isHittable)
        let versionFrame = fifthRowLabel.frame
        XCTAssertGreaterThanOrEqual(
            versionFrame.intersection(lastStatusViewport.frame).height, versionFrame.height - 1)
        screenshot("section-resizing-dense-status-version-row-reachable")

        let fourthRowScrollPoint = lastStatusViewport.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        fourthRowScrollPoint.scroll(byDeltaX: 0, deltaY: 17)
        for _ in 0..<12 {
            let distance = longLabelText.frame.minX - (lastStatusViewport.frame.minX + 4)
            if abs(distance) <= 1 { break }
            let horizontalScrollPoint = lastStatusViewport.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            horizontalScrollPoint.scroll(byDeltaX: -min(160, max(-160, distance)), deltaY: 0)
        }
        XCTAssertTrue(longLabelText.isHittable)
        let visibleLongLabelFrame = longLabelText.frame
        XCTAssertEqual(visibleLongLabelFrame.minX, lastStatusViewport.frame.minX + 4, accuracy: 2)
        XCTAssertGreaterThanOrEqual(
            visibleLongLabelFrame.intersection(lastStatusViewport.frame).height, visibleLongLabelFrame.height - 1)
        screenshot("section-resizing-dense-status-long-label-reachable")
        var horizontalScrollMeasurements: [String] = []
        for iteration in 0..<12 {
            let distance = longValueText.frame.maxX - (lastStatusViewport.frame.maxX - 4)
            if abs(distance) <= 1 { break }
            let horizontalScrollPoint = lastStatusViewport.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            horizontalScrollPoint.scroll(byDeltaX: -min(160, max(-160, distance)), deltaY: 0)
            horizontalScrollMeasurements.append(
                "iteration=\(iteration + 1); viewport=\(lastStatusViewport.frame); label=\(longLabelText.frame); value=\(longValueText.frame)"
            )
        }
        let horizontalScrollGeometry = XCTAttachment(string: horizontalScrollMeasurements.joined(separator: "\n"))
        horizontalScrollGeometry.name = "section-resizing-dense-status-horizontal-scroll-measurements"
        horizontalScrollGeometry.lifetime = .keepAlways
        add(horizontalScrollGeometry)
        XCTAssertTrue(longValueText.isHittable)
        let visibleLongValueFrame = longValueText.frame
        screenshot("section-resizing-dense-status-worktree-path-before-endpoint-assertion")
        XCTAssertEqual(visibleLongValueFrame.maxX, lastStatusViewport.frame.maxX - 4, accuracy: 2)
        XCTAssertGreaterThanOrEqual(
            visibleLongValueFrame.intersection(lastStatusViewport.frame).height, visibleLongValueFrame.height - 1)
        screenshot("section-resizing-dense-status-worktree-path-reachable")
        let finalStatusViewportFrame = lastStatusViewport.frame

        let firstColumnDivider = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'column-divider-0'")).firstMatch
        waitFor(firstColumnDivider)
        let gridID = firstColumnDivider.identifier.components(separatedBy: "-column-divider-").first ?? ""
        let grid = app.scrollViews[gridID]
        let secondColumnDivider = app.descendants(matching: .any)
            .matching(identifier: "\(gridID)-column-divider-1").firstMatch
        let firstRowDivider = app.descendants(matching: .any)
            .matching(identifier: "\(gridID)-row-divider-0").firstMatch
        let secondRowDivider = app.descendants(matching: .any)
            .matching(identifier: "\(gridID)-row-divider-1").firstMatch
        waitFor(grid)
        waitFor(secondColumnDivider)
        waitFor(firstRowDivider)
        waitFor(secondRowDivider)

        let columnsBeforeDiagonal = [
            (firstColumnDivider.value as? NSNumber)?.doubleValue ?? -1,
            (secondColumnDivider.value as? NSNumber)?.doubleValue ?? -1,
        ]
        let rowsBeforeDiagonal = [
            (firstRowDivider.value as? NSNumber)?.doubleValue ?? -1,
            (secondRowDivider.value as? NSNumber)?.doubleValue ?? -1,
        ]
        let thirdRowBeforeDiagonal = grid.frame.height - 16 - rowsBeforeDiagonal[0] - rowsBeforeDiagonal[1]
        let intersectionStart = firstRowDivider.coordinate(
            withNormalizedOffset: CGVector(
                dx: (firstColumnDivider.frame.midX - firstRowDivider.frame.minX) / firstRowDivider.frame.width,
                dy: 0.5
            )
        )
        intersectionStart.press(
            forDuration: 0.1,
            thenDragTo: intersectionStart.withOffset(CGVector(dx: 20, dy: -20))
        )
        let rowsAfterDiagonal = [
            try XCTUnwrap((firstRowDivider.value as? NSNumber)?.doubleValue),
            try XCTUnwrap((secondRowDivider.value as? NSNumber)?.doubleValue),
        ]
        let columnsAfterDiagonal = [
            try XCTUnwrap((firstColumnDivider.value as? NSNumber)?.doubleValue),
            try XCTUnwrap((secondColumnDivider.value as? NSNumber)?.doubleValue),
        ]
        let thirdRowAfterDiagonal = grid.frame.height - 16 - rowsAfterDiagonal[0] - rowsAfterDiagonal[1]
        XCTAssertEqual(rowsAfterDiagonal[0], rowsBeforeDiagonal[0] - 20, accuracy: 2)
        XCTAssertEqual(rowsAfterDiagonal[1], rowsBeforeDiagonal[1] + 20, accuracy: 2)
        XCTAssertEqual(columnsAfterDiagonal, columnsBeforeDiagonal)
        XCTAssertEqual(thirdRowAfterDiagonal, thirdRowBeforeDiagonal, accuracy: 2)

        let columnsBeforeEdgeDrag = [
            (firstColumnDivider.value as? NSNumber)?.doubleValue ?? -1,
            (secondColumnDivider.value as? NSNumber)?.doubleValue ?? -1,
        ]
        let rowsBeforeEdgeDrag = [
            (firstRowDivider.value as? NSNumber)?.doubleValue ?? -1,
            (secondRowDivider.value as? NSNumber)?.doubleValue ?? -1,
        ]
        let thirdColumnBeforeEdgeDrag = grid.frame.width - 16 - columnsBeforeEdgeDrag[0] - columnsBeforeEdgeDrag[1]
        let edgeStart = firstColumnDivider.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.25))
        edgeStart.press(forDuration: 0.1, thenDragTo: edgeStart.withOffset(CGVector(dx: 20, dy: 0)))
        let columnsAfterEdgeDrag = [
            try XCTUnwrap((firstColumnDivider.value as? NSNumber)?.doubleValue),
            try XCTUnwrap((secondColumnDivider.value as? NSNumber)?.doubleValue),
        ]
        let rowsAfterEdgeDrag = [
            try XCTUnwrap((firstRowDivider.value as? NSNumber)?.doubleValue),
            try XCTUnwrap((secondRowDivider.value as? NSNumber)?.doubleValue),
        ]
        XCTAssertEqual(columnsAfterEdgeDrag[0], columnsBeforeEdgeDrag[0] + 20, accuracy: 2)
        XCTAssertEqual(columnsAfterEdgeDrag[1], columnsBeforeEdgeDrag[1] - 20, accuracy: 2)
        XCTAssertEqual(
            columnsAfterEdgeDrag[0] + columnsAfterEdgeDrag[1],
            columnsBeforeEdgeDrag[0] + columnsBeforeEdgeDrag[1], accuracy: 2)
        XCTAssertEqual(
            grid.frame.width - 16 - columnsAfterEdgeDrag[0] - columnsAfterEdgeDrag[1],
            thirdColumnBeforeEdgeDrag,
            accuracy: 2
        )
        XCTAssertEqual(rowsAfterEdgeDrag, rowsBeforeEdgeDrag)
        screenshot("section-resizing-dense-status-and-eight-point-grab-proof")

        let dimensions = XCTAttachment(
            string:
                "window=\(mainWindow.frame); grid=\(grid.frame); lastPane=\(lastPane.frame); terminal=\(lastTerminal.frame); statusViewportBefore=\(initialStatusViewportFrame); statusViewportAt24=\(resizedStatusViewportFrame); statusViewportAfterScroll=\(finalStatusViewportFrame); statusContentBoundsBeforeResize=\(statusContentBoundsBeforeResize); statusContentBoundsAt24=\(statusContentBoundsAt24); longLabelWhenReachable=\(visibleLongLabelFrame); worktreePathWhenReachable=\(visibleLongValueFrame); actualWorktreePath=\(actualWorktreePath); versionWhenReachable=\(versionFrame); statusHeightBefore=\(lastStatusHeight); statusHeightAt24=\(resizedStatusHeight); diagonalRowsBefore=\(rowsBeforeDiagonal); diagonalRowsAfter=\(rowsAfterDiagonal); thirdRowBefore=\(thirdRowBeforeDiagonal); thirdRowAfter=\(thirdRowAfterDiagonal); diagonalColumnsBefore=\(columnsBeforeDiagonal); diagonalColumnsAfter=\(columnsAfterDiagonal); edgeRowsBefore=\(rowsBeforeEdgeDrag); edgeRowsAfter=\(rowsAfterEdgeDrag); edgeColumnsBefore=\(columnsBeforeEdgeDrag); edgeColumnsAfter=\(columnsAfterEdgeDrag)"
        )
        dimensions.name = "section-resizing-dense-content-measured-geometry"
        dimensions.lifetime = .keepAlways
        add(dimensions)
    }

    private func statusContentBounds(in viewport: XCUIElement) -> CGRect {
        let elements = viewport.staticTexts.allElementsBoundByIndex + viewport.images.allElementsBoundByIndex
        return elements.map { $0.frame }
            .filter { !$0.isNull && !$0.isEmpty && $0.width > 0 && $0.height > 0 }
            .reduce(CGRect.null) { $0.union($1) }
    }
}
