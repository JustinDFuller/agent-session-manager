import AppKit
import XCTest

final class SectionResizingIntegratedFlowTests: BaseTestCase {
    override var appLaunchArguments: [String] { ["--uitesting-skip-restore"] + additionalLaunchArguments }

    func testDenseGridResizesWithPointerDefaultAndCustomShortcutsAndResetsPerTab() throws {
        createTab(named: "Resize Alpha")
        createPane(named: "resize-alpha-1")
        createPane(named: "resize-alpha-2")

        let window = app.windows.firstMatch

        let alphaColumn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'column-divider-0'")).firstMatch
        waitFor(alphaColumn)
        let initialColumn = (alphaColumn.value as? NSNumber)?.doubleValue ?? -1
        let alphaGridIdentifier = alphaColumn.identifier.components(separatedBy: "-column-divider-").first ?? ""
        let start = alphaColumn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 28, dy: 0)))
        XCTAssertEqual((alphaColumn.value as? NSNumber)?.doubleValue ?? -1, initialColumn + 28, accuracy: 2)

        let activeTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-resize-alpha-2").firstMatch
        waitFor(activeTerminal)
        activeTerminal.click()
        app.typeKey(.leftArrow, modifierFlags: [.command, .option])
        XCTAssertEqual((alphaColumn.value as? NSNumber)?.doubleValue ?? -1, initialColumn + 24, accuracy: 2)

        for index in 3...9 {
            createPane(named: "resize-alpha-\(index)")
        }

        let alphaRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'row-divider-0'")).firstMatch
        waitFor(alphaRow)
        let alphaGrid = app.descendants(matching: .any).matching(identifier: alphaGridIdentifier).firstMatch
        let firstPane = app.descendants(matching: .any)
            .matching(identifier: "pane-resize-alpha-1").firstMatch
        waitFor(alphaGrid)
        waitFor(firstPane)
        let alphaRightColumn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'column-divider-1'")).firstMatch
        waitFor(alphaRightColumn)
        let alphaSecondRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'row-divider-1'")).firstMatch
        waitFor(alphaSecondRow)
        func assertEqualTrackAllocations(
            grid: XCUIElement,
            firstColumnDivider: XCUIElement,
            secondColumnDivider: XCUIElement,
            firstRowDivider: XCUIElement,
            secondRowDivider: XCUIElement
        ) {
            let availableColumnWidth = grid.frame.width - 16
            let availableRowHeight = grid.frame.height - 16
            let firstColumn = (firstColumnDivider.value as? NSNumber)?.doubleValue ?? -1
            let secondColumn = (secondColumnDivider.value as? NSNumber)?.doubleValue ?? -1
            let firstRow = (firstRowDivider.value as? NSNumber)?.doubleValue ?? -1
            let secondRow = (secondRowDivider.value as? NSNumber)?.doubleValue ?? -1
            let expectedColumnWidth = availableColumnWidth / 3
            let expectedRowHeight = availableRowHeight / 3

            XCTAssertEqual(firstColumn, expectedColumnWidth, accuracy: 3)
            XCTAssertEqual(secondColumn, expectedColumnWidth, accuracy: 3)
            XCTAssertEqual(availableColumnWidth - firstColumn - secondColumn, expectedColumnWidth, accuracy: 3)
            XCTAssertEqual(firstRow, expectedRowHeight, accuracy: 3)
            XCTAssertEqual(secondRow, expectedRowHeight, accuracy: 3)
            XCTAssertEqual(availableRowHeight - firstRow - secondRow, expectedRowHeight, accuracy: 3)
        }
        let initialRow = (alphaRow.value as? NSNumber)?.doubleValue ?? -1
        let rowStart = alphaRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        rowStart.press(forDuration: 0.1, thenDragTo: rowStart.withOffset(CGVector(dx: 0, dy: -24)))
        XCTAssertEqual((alphaRow.value as? NSNumber)?.doubleValue ?? -1, initialRow - 24, accuracy: 2)
        resizeWindow(toWidth: 900, height: 600)
        let minimumFrame = window.frame
        XCTAssertGreaterThanOrEqual(minimumFrame.width, 900)
        XCTAssertGreaterThanOrEqual(minimumFrame.height, 600)
        resizeWindow(toWidth: minimumFrame.width - 20, height: minimumFrame.height - 20)
        let clampedFrame = window.frame
        XCTAssertEqual(clampedFrame.width, minimumFrame.width, accuracy: 2)
        XCTAssertEqual(clampedFrame.height, minimumFrame.height, accuracy: 2)
        XCTAssertTrue(alphaColumn.isHittable)
        XCTAssertTrue(alphaRightColumn.isHittable)
        for index in 1...9 {
            let pane = app.descendants(matching: .any)
                .matching(identifier: "pane-resize-alpha-\(index)").firstMatch
            let header = app.descendants(matching: .any)
                .matching(identifier: "pane-header-resize-alpha-\(index)").firstMatch
            let terminal = app.descendants(matching: .any)
                .matching(identifier: "pane-terminal-resize-alpha-\(index)").firstMatch
            waitFor(pane)
            waitFor(header)
            waitFor(terminal)
            XCTAssertTrue(header.isHittable)
            XCTAssertGreaterThanOrEqual(pane.frame.width, 160)
            XCTAssertGreaterThanOrEqual(terminal.frame.height, 64)
        }
        let minimumBoundsAttachment = XCTAttachment(string: "Observed minimum window frame: \(clampedFrame)")
        minimumBoundsAttachment.name = "section-resizing-minimum-window-bounds"
        minimumBoundsAttachment.lifetime = .keepAlways
        add(minimumBoundsAttachment)
        screenshot("section-resizing-dense-grid-minimum-window")
        resizeWindow(toWidth: clampedFrame.width + 120, height: clampedFrame.height + 80)
        let largerFrame = window.frame
        XCTAssertGreaterThan(largerFrame.width, clampedFrame.width)
        XCTAssertGreaterThan(largerFrame.height, clampedFrame.height)
        let largerBoundsAttachment = XCTAttachment(string: "Observed larger window frame: \(largerFrame)")
        largerBoundsAttachment.name = "section-resizing-larger-window-bounds"
        largerBoundsAttachment.lifetime = .keepAlways
        add(largerBoundsAttachment)
        screenshot("section-resizing-dense-grid-larger-window")
        let denseExtent = alphaGrid.frame.width - 16

        let localResetStart = alphaColumn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        localResetStart.press(forDuration: 0.1, thenDragTo: localResetStart.withOffset(CGVector(dx: 30, dy: 0)))
        let firstBeforeLocalReset = (alphaColumn.value as? NSNumber)?.doubleValue ?? -1
        let secondBeforeLocalReset = (alphaRightColumn.value as? NSNumber)?.doubleValue ?? -1
        let thirdBeforeLocalReset = denseExtent - firstBeforeLocalReset - secondBeforeLocalReset
        alphaColumn.rightClick()
        let resetDivider = app.menuItems["Reset Resize column divider 1 Size"]
        waitFor(resetDivider)
        resetDivider.click()
        let firstAfterLocalReset = (alphaColumn.value as? NSNumber)?.doubleValue ?? -1
        let secondAfterLocalReset = (alphaRightColumn.value as? NSNumber)?.doubleValue ?? -1
        let thirdAfterLocalReset = denseExtent - firstAfterLocalReset - secondAfterLocalReset
        XCTAssertEqual(firstAfterLocalReset, (firstBeforeLocalReset + secondBeforeLocalReset) / 2, accuracy: 3)
        XCTAssertEqual(secondAfterLocalReset, (firstBeforeLocalReset + secondBeforeLocalReset) / 2, accuracy: 3)
        XCTAssertEqual(thirdAfterLocalReset, thirdBeforeLocalReset, accuracy: 3)

        let customTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-resize-alpha-9").firstMatch
        waitFor(customTerminal)
        customTerminal.click()
        let firstBeforeEdgeDrag = (alphaColumn.value as? NSNumber)?.doubleValue ?? -1
        let secondBeforeEdgeDrag = (alphaRightColumn.value as? NSNumber)?.doubleValue ?? -1
        let edgeDrag = alphaColumn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        edgeDrag.press(forDuration: 0.1, thenDragTo: edgeDrag.withOffset(CGVector(dx: 20, dy: 0)))
        XCTAssertEqual((alphaColumn.value as? NSNumber)?.doubleValue ?? -1, firstBeforeEdgeDrag + 20, accuracy: 2)
        let secondAfterEdgeDrag = (alphaRightColumn.value as? NSNumber)?.doubleValue ?? -1
        XCTAssertEqual(secondAfterEdgeDrag, secondBeforeEdgeDrag - 20, accuracy: 2)
        app.typeKey(.leftArrow, modifierFlags: [.command, .option])
        XCTAssertEqual((alphaRightColumn.value as? NSNumber)?.doubleValue ?? -1, secondAfterEdgeDrag - 4, accuracy: 2)

        let shortcutSettings = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-shortcuts").firstMatch
        app.typeKey(",", modifierFlags: .command)
        waitFor(shortcutSettings)
        shortcutSettings.click()
        let leftCapture = app.buttons["settings-resize-shortcut-capture-left"]
        waitFor(leftCapture)
        leftCapture.click()
        app.typeKey("x", modifierFlags: [.command, .option])
        XCTAssertEqual(leftCapture.label, "⌘⌥X")
        app.typeKey(.escape, modifierFlags: [])

        customTerminal.click()
        let beforeCustom = (alphaRightColumn.value as? NSNumber)?.doubleValue ?? -1
        app.typeKey("x", modifierFlags: [.command, .option])
        XCTAssertEqual((alphaRightColumn.value as? NSNumber)?.doubleValue ?? -1, beforeCustom - 4, accuracy: 2)

        alphaGrid.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0,
                dy: (firstPane.frame.midY - alphaGrid.frame.minY) / alphaGrid.frame.height
            )
        )
        .withOffset(CGVector(dx: 2, dy: 0)).rightClick()
        let resetGrid = app.menuItems["Reset Pane Sizes"]
        waitFor(resetGrid)
        resetGrid.click()
        assertEqualTrackAllocations(
            grid: alphaGrid,
            firstColumnDivider: alphaColumn,
            secondColumnDivider: alphaRightColumn,
            firstRowDivider: alphaRow,
            secondRowDivider: alphaSecondRow
        )

        createTab(named: "Resize Beta")
        createPane(named: "resize-beta-1")
        let betaColumn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'column-divider-0'")).firstMatch
        createPane(named: "resize-beta-2")
        waitFor(betaColumn)
        let betaGridIdentifier = betaColumn.identifier.components(separatedBy: "-column-divider-").first ?? ""
        let betaGrid = app.scrollViews[betaGridIdentifier]
        waitFor(betaGrid)
        let betaShellName = openShellHere(from: "resize-beta-2")
        let betaShellTerminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-\(betaShellName)").firstMatch
        waitFor(betaShellTerminal)

        let betaProofURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "agent-session-manager-integrated-resize-\(UUID().uuidString)")
        let betaPIDBeforeURL = betaProofURL.appending(path: "pid-before")
        let betaTTYBeforeURL = betaProofURL.appending(path: "tty-before")
        let betaContextBeforeURL = betaProofURL.appending(path: "context-before")
        let betaPIDAfterPointerURL = betaProofURL.appending(path: "pid-after-pointer")
        let betaTTYAfterPointerURL = betaProofURL.appending(path: "tty-after-pointer")
        let betaDefaultInputURL = betaProofURL.appending(path: "default-shortcut-input")
        let betaCustomInputURL = betaProofURL.appending(path: "custom-shortcut-input")
        let betaPIDAfterResizeURL = betaProofURL.appending(path: "pid-after-resize")
        let betaTTYAfterResizeURL = betaProofURL.appending(path: "tty-after-resize")
        let betaContextAfterURL = betaProofURL.appending(path: "context-after")
        let betaTTYAtMinimumURL = betaProofURL.appending(path: "tty-at-minimum-window")
        let betaTTYAtLargerURL = betaProofURL.appending(path: "tty-at-larger-window")
        typealias PasteboardRepresentation = (type: NSPasteboard.PasteboardType, data: Data)
        let priorPasteboardItems: [[PasteboardRepresentation]] = {
            var snapshots: [[PasteboardRepresentation]] = []
            for pasteboardItem in NSPasteboard.general.pasteboardItems ?? [] {
                var representations: [PasteboardRepresentation] = []
                for type in pasteboardItem.types {
                    if let data = pasteboardItem.data(forType: type) {
                        representations.append((type: type, data: data))
                    }
                }
                snapshots.append(representations)
            }
            return snapshots
        }()
        defer {
            NSPasteboard.general.clearContents()
            var restoredItems: [NSPasteboardItem] = []
            for representations in priorPasteboardItems {
                let item = NSPasteboardItem()
                for representation in representations {
                    item.setData(representation.data, forType: representation.type)
                }
                restoredItems.append(item)
            }
            if !restoredItems.isEmpty {
                _ = NSPasteboard.general.writeObjects(restoredItems)
            }
        }
        defer { try? FileManager.default.removeItem(at: betaProofURL) }
        try FileManager.default.createDirectory(at: betaProofURL, withIntermediateDirectories: true)

        betaShellTerminal.click()
        typeTerminalCommand(
            "print -r -- $$ > '\(betaPIDBeforeURL.path)'; stty size > '\(betaTTYBeforeURL.path)'; pwd > '\(betaContextBeforeURL.path)'"
        )
        let betaShellReady = expectation(
            for: NSPredicate { _, _ in
                FileManager.default.fileExists(atPath: betaPIDBeforeURL.path)
                    && FileManager.default.fileExists(atPath: betaTTYBeforeURL.path)
                    && FileManager.default.fileExists(atPath: betaContextBeforeURL.path)
            },
            evaluatedWith: NSNull()
        )
        wait(for: [betaShellReady], timeout: 15)
        let betaPIDBefore = try? String(contentsOf: betaPIDBeforeURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let betaTTYBefore = try? String(contentsOf: betaTTYBeforeURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let betaContextBefore = try? String(contentsOf: betaContextBeforeURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotNil(betaPIDBefore)
        XCTAssertNotNil(betaTTYBefore)
        XCTAssertNotNil(betaContextBefore)
        typeTerminalCommand(
            "print -r -- 'INTEGRATED_RESIZE_SCROLLBACK_MARKER'; for i in {1..80}; do print -r -- \"INTEGRATED_RESIZE_SCROLLBACK_$i\"; done"
        )
        betaShellTerminal.scroll(byDeltaX: 0, deltaY: 1200)

        app.buttons["tab-button-Resize Alpha"].firstMatch.click()
        let alphaFirstName = app.staticTexts["pane-name-resize-alpha-1"].firstMatch
        let alphaSecondName = app.staticTexts["pane-name-resize-alpha-2"].firstMatch
        waitFor(alphaFirstName)
        waitFor(alphaSecondName)
        alphaFirstName.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.5,
            thenDragTo: alphaSecondName.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        )
        XCTAssertGreaterThan(alphaFirstName.frame.minX, alphaSecondName.frame.minX)
        app.buttons["tab-button-Resize Beta"].firstMatch.click()
        waitFor(betaGrid)

        let betaShellHeader = app.descendants(matching: .any)
            .matching(identifier: "pane-header-\(betaShellName)").firstMatch
        waitFor(betaShellHeader)
        betaShellHeader.rightClick()
        let focusThisPane = app.windows.firstMatch.menuItems["Focus This Pane"]
        waitFor(focusThisPane)
        focusThisPane.click()
        let showAllPanes = app.buttons["pane-show-all-\(betaShellName)"].firstMatch
        waitFor(showAllPanes)
        showAllPanes.click()
        waitFor(betaGrid)
        let betaRowDivider = app.descendants(matching: .any)
            .matching(identifier: "\(betaGridIdentifier)-row-divider-0").firstMatch
        waitFor(betaRowDivider)
        let betaRowHeightBeforePointer = (betaRowDivider.value as? NSNumber)?.doubleValue ?? -1
        let betaStartWidth = (betaColumn.value as? NSNumber)?.doubleValue ?? -1
        let betaColumnFrame = betaColumn.frame
        let betaPointerY = betaShellTerminal.frame.midY
        XCTAssertGreaterThan(abs(betaPointerY - betaRowDivider.frame.midY), 8)
        let betaStart = betaColumn.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: (betaPointerY - betaColumnFrame.minY) / betaColumnFrame.height)
        )
        betaStart.press(forDuration: 0.1, thenDragTo: betaStart.withOffset(CGVector(dx: 20, dy: 0)))
        let betaSavedWidth = (betaColumn.value as? NSNumber)?.doubleValue ?? -1
        let betaSavedFraction = betaSavedWidth / (betaGrid.frame.width - 12)
        XCTAssertEqual(betaSavedWidth, betaStartWidth + 20, accuracy: 2)
        XCTAssertEqual((betaRowDivider.value as? NSNumber)?.doubleValue ?? -1, betaRowHeightBeforePointer, accuracy: 2)
        typeTerminalCommand(
            "print -r -- $$ > '\(betaPIDAfterPointerURL.path)'; stty size > '\(betaTTYAfterPointerURL.path)'"
        )
        let betaPointerReady = expectation(
            for: NSPredicate { _, _ in
                FileManager.default.fileExists(atPath: betaPIDAfterPointerURL.path)
                    && FileManager.default.fileExists(atPath: betaTTYAfterPointerURL.path)
            },
            evaluatedWith: NSNull()
        )
        wait(for: [betaPointerReady], timeout: 15)
        let betaPIDAfterPointer = try? String(contentsOf: betaPIDAfterPointerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let betaTTYAfterPointer = try? String(contentsOf: betaTTYAfterPointerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(betaPIDAfterPointer, betaPIDBefore)
        XCTAssertNotEqual(betaTTYAfterPointer, betaTTYBefore)

        typeTerminalCommand(
            "stty -icanon -echo; read -r -k 1 -t 4 defaultInput; stty sane; print -r -- \"${defaultInput:-none}\" > '\(betaDefaultInputURL.path)'"
        )
        let defaultReadStarted = expectation(description: "The Beta shell should wait for default shortcut input")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { defaultReadStarted.fulfill() }
        wait(for: [defaultReadStarted], timeout: 2)
        let widthBeforeDefault = (betaColumn.value as? NSNumber)?.doubleValue ?? -1
        app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        XCTAssertEqual((betaColumn.value as? NSNumber)?.doubleValue ?? -1, widthBeforeDefault + 4, accuracy: 2)
        let defaultRead = expectation(
            for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: betaDefaultInputURL.path) },
            evaluatedWith: NSNull()
        )
        wait(for: [defaultRead], timeout: 8)
        XCTAssertEqual(
            try? String(contentsOf: betaDefaultInputURL, encoding: .utf8).trimmingCharacters(
                in: .whitespacesAndNewlines),
            "none"
        )

        typeTerminalCommand(
            "stty -icanon -echo; read -r -k 1 -t 4 customInput; stty sane; print -r -- \"${customInput:-none}\" > '\(betaCustomInputURL.path)'"
        )
        let customReadStarted = expectation(description: "The Beta shell should wait for custom shortcut input")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { customReadStarted.fulfill() }
        wait(for: [customReadStarted], timeout: 2)
        let widthBeforeCustom = (betaColumn.value as? NSNumber)?.doubleValue ?? -1
        app.typeKey("x", modifierFlags: [.command, .option])
        XCTAssertEqual((betaColumn.value as? NSNumber)?.doubleValue ?? -1, widthBeforeCustom - 4, accuracy: 2)
        let customRead = expectation(
            for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: betaCustomInputURL.path) },
            evaluatedWith: NSNull()
        )
        wait(for: [customRead], timeout: 8)
        XCTAssertEqual(
            try? String(contentsOf: betaCustomInputURL, encoding: .utf8).trimmingCharacters(
                in: .whitespacesAndNewlines),
            "none"
        )

        app.buttons["tab-button-Resize Alpha"].firstMatch.click()
        waitFor(alphaColumn)
        waitFor(alphaGrid)
        waitFor(alphaRightColumn)
        waitFor(alphaRow)
        waitFor(alphaSecondRow)
        assertEqualTrackAllocations(
            grid: alphaGrid,
            firstColumnDivider: alphaColumn,
            secondColumnDivider: alphaRightColumn,
            firstRowDivider: alphaRow,
            secondRowDivider: alphaSecondRow
        )
        let notificationsTab = app.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-notifications").firstMatch
        app.typeKey(",", modifierFlags: .command)
        waitFor(notificationsTab)
        notificationsTab.click()
        let alwaysShow = app.checkBoxes["settings-always-show-notifications-bar-toggle"]
        waitFor(alwaysShow)
        if alwaysShow.value as? Int != 1 {
            alwaysShow.click()
        }
        app.typeKey(.escape, modifierFlags: [])
        let sidebarHandle = app.descendants(matching: .any)
            .matching(identifier: "notification-sidebar-resize-handle").firstMatch
        waitFor(sidebarHandle)
        let sidebarBefore = (sidebarHandle.value as? NSNumber)?.doubleValue ?? -1
        let sidebarStart = sidebarHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        sidebarStart.press(forDuration: 0.1, thenDragTo: sidebarStart.withOffset(CGVector(dx: 20, dy: 0)))
        XCTAssertEqual((sidebarHandle.value as? NSNumber)?.doubleValue ?? -1, sidebarBefore + 20, accuracy: 2)

        app.buttons["tab-button-Resize Beta"].firstMatch.click()
        waitFor(betaGrid)
        betaShellTerminal.click()
        resizeWindow(toWidth: 900, height: 600)
        let integratedMinimumFrame = window.frame
        typeTerminalCommand("stty size > '\(betaTTYAtMinimumURL.path)'; print -r -- 'INTEGRATED_MINIMUM_WINDOW_SHELL'")
        let betaMinimumTTYReady = expectation(
            for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: betaTTYAtMinimumURL.path) },
            evaluatedWith: NSNull()
        )
        wait(for: [betaMinimumTTYReady], timeout: 15)
        let betaTTYAtMinimum = try? String(contentsOf: betaTTYAtMinimumURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let minimumEvidence = XCTAttachment(
            string:
                "Integrated minimum window frame: \(integratedMinimumFrame); Alpha grid reset to equal tracks; Beta saved first column: \(betaSavedWidth); notification sidebar: \((sidebarHandle.value as? NSNumber)?.doubleValue ?? -1); Beta shell terminal size: \(betaTTYAtMinimum ?? "unavailable")"
        )
        minimumEvidence.name = "section-resizing-integrated-minimum-two-tab-dimensions"
        minimumEvidence.lifetime = .keepAlways
        add(minimumEvidence)
        screenshot("section-resizing-integrated-two-tab-minimum")
        resizeWindow(toWidth: largerFrame.width, height: largerFrame.height)
        typeTerminalCommand("stty size > '\(betaTTYAtLargerURL.path)'; print -r -- 'INTEGRATED_LARGER_WINDOW_SHELL'")
        let betaLargerTTYReady = expectation(
            for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: betaTTYAtLargerURL.path) },
            evaluatedWith: NSNull()
        )
        wait(for: [betaLargerTTYReady], timeout: 15)
        screenshot("section-resizing-integrated-two-tab-larger")
        let betaTTYAtLarger = try? String(contentsOf: betaTTYAtLargerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(betaTTYAtMinimum, betaTTYAtLarger)

        app.buttons["tab-button-Resize Beta"].firstMatch.click()
        waitFor(betaColumn)
        XCTAssertEqual(
            (betaColumn.value as? NSNumber)?.doubleValue ?? -1,
            betaSavedFraction * (betaGrid.frame.width - 12), accuracy: 3
        )
        betaShellTerminal.click()
        typeTerminalCommand(
            "print -r -- $$ > '\(betaPIDAfterResizeURL.path)'; stty size > '\(betaTTYAfterResizeURL.path)'; pwd > '\(betaContextAfterURL.path)'; print -r -- 'INTEGRATED_RESIZE_CONTINUED_$$'"
        )
        let betaResizeReady = expectation(
            for: NSPredicate { _, _ in
                FileManager.default.fileExists(atPath: betaPIDAfterResizeURL.path)
                    && FileManager.default.fileExists(atPath: betaTTYAfterResizeURL.path)
                    && FileManager.default.fileExists(atPath: betaContextAfterURL.path)
            },
            evaluatedWith: NSNull()
        )
        wait(for: [betaResizeReady], timeout: 15)
        XCTAssertEqual(
            try? String(contentsOf: betaPIDAfterResizeURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            betaPIDBefore
        )
        XCTAssertEqual(
            try? String(contentsOf: betaContextAfterURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            betaContextBefore
        )
        XCTAssertEqual(
            try? String(contentsOf: betaTTYAfterResizeURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            betaTTYAtLarger
        )
        betaShellTerminal.scroll(byDeltaX: 0, deltaY: 1200)
        betaShellTerminal.typeKey("a", modifierFlags: .command)
        betaShellTerminal.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(
            NSPasteboard.general.string(forType: .string)?.contains("INTEGRATED_RESIZE_SCROLLBACK_MARKER") == true
        )
        app.buttons["tab-button-Resize Alpha"].firstMatch.click()
        waitFor(alphaColumn)
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let restoredColumn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'column-divider-0'")).firstMatch
        let restoredGrid = app.descendants(matching: .any).matching(identifier: alphaGridIdentifier).firstMatch
        let restoredSecondColumn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'column-divider-1'")).firstMatch
        let restoredFirstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'row-divider-0'")).firstMatch
        let restoredSecondRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'row-divider-1'")).firstMatch
        let restoredSidebar = app.descendants(matching: .any)
            .matching(identifier: "notification-sidebar-resize-handle").firstMatch
        waitFor(restoredGrid)
        waitFor(restoredColumn)
        waitFor(restoredSecondColumn)
        waitFor(restoredFirstRow)
        waitFor(restoredSecondRow)
        waitFor(restoredSidebar)
        XCTAssertEqual((restoredSidebar.value as? NSNumber)?.doubleValue ?? -1, sidebarBefore + 20, accuracy: 2)
        assertEqualTrackAllocations(
            grid: restoredGrid,
            firstColumnDivider: restoredColumn,
            secondColumnDivider: restoredSecondColumn,
            firstRowDivider: restoredFirstRow,
            secondRowDivider: restoredSecondRow
        )
        app.buttons["tab-button-Resize Beta"].firstMatch.click()
        let restoredBetaColumn = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'column-divider-0'")).firstMatch
        waitFor(restoredBetaColumn)
        let restoredBetaGrid = app.scrollViews[betaGridIdentifier]
        waitFor(restoredBetaGrid)
        XCTAssertEqual(
            (restoredBetaColumn.value as? NSNumber)?.doubleValue ?? -1,
            betaSavedFraction * (restoredBetaGrid.frame.width - 12), accuracy: 3
        )
        app.typeKey(",", modifierFlags: .command)
        waitFor(shortcutSettings)
        shortcutSettings.click()
        waitFor(leftCapture)
        XCTAssertEqual(leftCapture.label, "⌘⌥X")
    }

    private func resizeWindow(toWidth width: CGFloat, height: CGFloat) {
        let window = app.windows.firstMatch
        let frame = window.frame
        let bottomRight = window.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.999))
        bottomRight.press(
            forDuration: 0.1,
            thenDragTo: bottomRight.withOffset(CGVector(dx: width - frame.width, dy: height - frame.height))
        )
    }
}
