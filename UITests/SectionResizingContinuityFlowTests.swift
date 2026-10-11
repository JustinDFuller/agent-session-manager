import AppKit
import XCTest

final class SectionResizingContinuityFlowTests: BaseTestCase {
    override var appLaunchArguments: [String] { ["--uitesting-skip-restore"] + additionalLaunchArguments }

    func testRealShellContinuesAfterPointerAndKeyboardResizing() throws {
        createTab(named: "Resize Continuity")
        createPane(named: "resize-shell-source")
        let sourceIdleIndicator = app.descendants(matching: .any)
            .matching(identifier: "pane-activity-idle-resize-shell-source").firstMatch
        waitFor(sourceIdleIndicator, timeout: 15)

        let shellName = openShellHere(from: "resize-shell-source")
        let terminal = app.descendants(matching: .any)
            .matching(identifier: "pane-terminal-\(shellName)").firstMatch
        waitFor(terminal)

        app.typeKey(",", modifierFlags: .command)
        let settingsWindow = app.windows["AgentSessionManager Settings"]
        waitFor(settingsWindow)
        let debugTab = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings-sidebar-debug").firstMatch
        waitFor(debugTab)
        debugTab.click()
        let debugToggle = settingsWindow.checkBoxes["settings-debug-mode-toggle"]
        waitFor(debugToggle)
        if debugToggle.value as? Int != 1 {
            debugToggle.click()
        }
        XCTAssertEqual(debugToggle.value as? Int, 1)
        app.typeKey("w", modifierFlags: .command)
        waitForDisappear(settingsWindow)

        let proofURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "agent-session-manager-resize-\(UUID().uuidString)")
        let pidBeforeURL = proofURL.appending(path: "pid-before")
        let ttyBeforeURL = proofURL.appending(path: "tty-before")
        let pidAfterPointerURL = proofURL.appending(path: "pid-after-pointer")
        let ttyAfterPointerURL = proofURL.appending(path: "tty-after-pointer")
        let leakURL = proofURL.appending(path: "shortcut-input")
        let pidAfterKeyboardURL = proofURL.appending(path: "pid-after-keyboard")
        let ttyAfterKeyboardURL = proofURL.appending(path: "tty-after-keyboard")
        let followupURL = proofURL.appending(path: "followup")
        let subsequentURL = proofURL.appending(path: "subsequent")
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
        defer { try? FileManager.default.removeItem(at: proofURL) }
        try? FileManager.default.createDirectory(at: proofURL, withIntermediateDirectories: true)

        terminal.click()
        typeTerminalCommand(
            "print -r -- $$ > '\(pidBeforeURL.path)'; stty size > '\(ttyBeforeURL.path)'"
        )
        let shellReady = expectation(
            for: NSPredicate { _, _ in
                FileManager.default.fileExists(atPath: pidBeforeURL.path)
                    && FileManager.default.fileExists(atPath: ttyBeforeURL.path)
            },
            evaluatedWith: NSNull()
        )
        wait(for: [shellReady], timeout: 15)
        let pidBefore = try? String(contentsOf: pidBeforeURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ttyBefore = try? String(contentsOf: ttyBeforeURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotNil(pidBefore)
        XCTAssertNotNil(ttyBefore)

        typeTerminalCommand(
            "print -r -- 'RESIZE_SCROLLBACK_MARKER'; for i in {1..80}; do print -r -- \"RESIZE_SCROLLBACK_$i\"; done"
        )
        terminal.scroll(byDeltaX: 0, deltaY: 1200)

        let divider = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS 'column-divider-0'")).firstMatch
        waitFor(divider)
        XCTAssertTrue(divider.identifier.hasPrefix("pane-grid-"))
        let tabIDFromUI = String(
            divider.identifier.dropFirst("pane-grid-".count)
                .components(separatedBy: "-column-divider-").first ?? ""
        )
        let initialWidth = (divider.value as? NSNumber)?.doubleValue ?? -1
        let dividerStart = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        dividerStart.press(forDuration: 0.1, thenDragTo: dividerStart.withOffset(CGVector(dx: 24, dy: 0)))
        XCTAssertEqual((divider.value as? NSNumber)?.doubleValue ?? -1, initialWidth + 24, accuracy: 2)

        typeTerminalCommand(
            "print -r -- $$ > '\(pidAfterPointerURL.path)'; stty size > '\(ttyAfterPointerURL.path)'"
        )
        let pointerMeasurementReady = expectation(
            for: NSPredicate { _, _ in
                FileManager.default.fileExists(atPath: pidAfterPointerURL.path)
                    && FileManager.default.fileExists(atPath: ttyAfterPointerURL.path)
            },
            evaluatedWith: NSNull()
        )
        wait(for: [pointerMeasurementReady], timeout: 15)
        let pidAfterPointer = try? String(contentsOf: pidAfterPointerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ttyAfterPointer = try? String(contentsOf: ttyAfterPointerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(pidAfterPointer, pidBefore)
        XCTAssertNotEqual(ttyAfterPointer, ttyBefore)

        typeTerminalCommand(
            "stty -icanon -echo; read -r -k 1 -t 4 shortcutInput; stty sane; print -r -- \"${shortcutInput:-none}\" > '\(leakURL.path)'"
        )
        let readStarted = expectation(description: "The shell should begin waiting for keyboard input")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { readStarted.fulfill() }
        wait(for: [readStarted], timeout: 2)
        let widthBeforeKeyboard = (divider.value as? NSNumber)?.doubleValue ?? -1
        app.typeKey(.leftArrow, modifierFlags: [.command, .option, .shift])
        XCTAssertEqual((divider.value as? NSNumber)?.doubleValue ?? -1, widthBeforeKeyboard - 16, accuracy: 2)
        let shortcutRead = expectation(
            for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: leakURL.path) },
            evaluatedWith: NSNull()
        )
        wait(for: [shortcutRead], timeout: 8)
        let shortcutInput = try? String(contentsOf: leakURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(shortcutInput, "none")

        typeTerminalCommand(
            "print -r -- $$ > '\(pidAfterKeyboardURL.path)'; stty size > '\(ttyAfterKeyboardURL.path)'; print -r -- 'RESIZE_CONTINUED_$$'; print -r -- ok > '\(followupURL.path)'"
        )
        let followupReady = expectation(
            for: NSPredicate { _, _ in
                FileManager.default.fileExists(atPath: pidAfterKeyboardURL.path)
                    && FileManager.default.fileExists(atPath: ttyAfterKeyboardURL.path)
                    && FileManager.default.fileExists(atPath: followupURL.path)
            },
            evaluatedWith: NSNull()
        )
        wait(for: [followupReady], timeout: 15)
        let pidAfterKeyboard = try? String(contentsOf: pidAfterKeyboardURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ttyAfterKeyboard = try? String(contentsOf: ttyAfterKeyboardURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(pidAfterKeyboard, pidBefore)
        XCTAssertNotEqual(ttyAfterKeyboard, ttyAfterPointer)
        XCTAssertEqual(
            try? String(contentsOf: followupURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            "ok"
        )

        typeTerminalCommand("print -r -- 'RESIZE_INPUT_OK' > '\(subsequentURL.path)'")
        let subsequentInput = expectation(
            for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: subsequentURL.path) },
            evaluatedWith: NSNull()
        )
        wait(for: [subsequentInput], timeout: 10)
        terminal.scroll(byDeltaX: 0, deltaY: 1200)
        terminal.typeKey("a", modifierFlags: .command)
        terminal.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains("RESIZE_SCROLLBACK_MARKER") == true)
        XCTAssertEqual(
            try? String(contentsOf: subsequentURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            "RESIZE_INPUT_OK"
        )
        XCTAssertTrue(sourceIdleIndicator.exists)

        let tracesDirectory = UITestAppSupport.directory.appending(path: "traces")
        let boundedResizeKeys: Set<String> = [
            "section", "axis", "source", "before", "after", "result", "tab.id", "tab.name", "pane.id",
            "pane.name", "boundary.index", "direction", "action",
        ]
        let readResizeRecords = { () -> [[String: Any]] in
            guard
                let files = FileManager.default.enumerator(
                    at: tracesDirectory,
                    includingPropertiesForKeys: [.isRegularFileKey])
            else {
                return []
            }
            var records: [[String: Any]] = []
            for case let fileURL as URL in files where fileURL.pathExtension == "jsonl" {
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                var metadata: [String: Any]?
                for line in content.split(whereSeparator: \.isNewline) {
                    guard
                        let row = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
                    else {
                        continue
                    }
                    if row["_type"] as? String == "metadata" {
                        if row["tabName"] as? String == "Resize Continuity",
                            row["tabId"] as? String == tabIDFromUI,
                            row["paneName"] as? String == shellName
                        {
                            metadata = row
                        }
                        continue
                    }
                    guard
                        let metadata,
                        row["name"] as? String == "layout.resize.completed",
                        let attributes = row["attributes"] as? [String: String],
                        attributes["section"] == "grid",
                        attributes["axis"] == "columns"
                    else {
                        continue
                    }
                    records.append([
                        "name": row["name"] as? String ?? "",
                        "metadataTabID": metadata["tabId"] as? String ?? "",
                        "metadataPaneID": metadata["paneId"] as? String ?? "",
                        "metadataPaneName": metadata["paneName"] as? String ?? "",
                        "attributes": attributes.filter { boundedResizeKeys.contains($0.key) },
                    ])
                }
            }
            return records
        }
        let resizeTelemetryReady = expectation(
            for: NSPredicate { _, _ in
                let records = readResizeRecords()
                return records.contains {
                    ($0["attributes"] as? [String: String])?["source"] == "pointer"
                }
                    && records.contains {
                        ($0["attributes"] as? [String: String])?["source"] == "keyboard"
                    }
            },
            evaluatedWith: NSNull()
        )
        wait(for: [resizeTelemetryReady], timeout: 10)
        let resizeRecords = readResizeRecords()
        let pointerRecord = try XCTUnwrap(
            resizeRecords.first { ($0["attributes"] as? [String: String])?["source"] == "pointer" })
        let keyboardRecord = try XCTUnwrap(
            resizeRecords.first { ($0["attributes"] as? [String: String])?["source"] == "keyboard" })
        let pointerAttributes = try XCTUnwrap(pointerRecord["attributes"] as? [String: String])
        let keyboardAttributes = try XCTUnwrap(keyboardRecord["attributes"] as? [String: String])
        let pointerKeys: Set<String> = [
            "section", "axis", "source", "before", "after", "result", "tab.id", "tab.name", "pane.id",
            "pane.name", "boundary.index",
        ]
        let keyboardKeys = pointerKeys.union(["direction", "action"])
        XCTAssertEqual(Set(pointerAttributes.keys), pointerKeys)
        XCTAssertEqual(Set(keyboardAttributes.keys), keyboardKeys)
        for (record, attributes) in [(pointerRecord, pointerAttributes), (keyboardRecord, keyboardAttributes)] {
            XCTAssertEqual(attributes["section"], "grid")
            XCTAssertEqual(attributes["axis"], "columns")
            XCTAssertEqual(attributes["result"], "success")
            XCTAssertEqual(attributes["tab.id"], tabIDFromUI)
            XCTAssertEqual(attributes["tab.name"], "Resize Continuity")
            XCTAssertEqual(attributes["pane.name"], shellName)
            XCTAssertEqual(record["metadataTabID"] as? String, tabIDFromUI)
            XCTAssertEqual(record["metadataPaneName"] as? String, shellName)
            XCTAssertEqual(attributes["pane.id"], record["metadataPaneID"] as? String)
            XCTAssertNotNil(UUID(uuidString: attributes["pane.id"] ?? ""))
            XCTAssertNotEqual(attributes["before"], attributes["after"])
        }
        XCTAssertEqual(pointerAttributes["source"], "pointer")
        XCTAssertEqual(pointerAttributes["boundary.index"], "0")
        XCTAssertEqual(keyboardAttributes["source"], "keyboard")
        XCTAssertEqual(keyboardAttributes["boundary.index"], "0")
        XCTAssertEqual(keyboardAttributes["direction"], "left")
        XCTAssertEqual(keyboardAttributes["action"], "larger_step")
        let telemetryAttachmentRows = [pointerRecord, keyboardRecord].map { record in
            ["name": record["name"] as? String ?? "", "attributes": record["attributes"] ?? [:]]
        }
        let telemetryAttachmentData = try JSONSerialization.data(
            withJSONObject: telemetryAttachmentRows,
            options: [.prettyPrinted, .sortedKeys]
        )
        let telemetryAttachment = XCTAttachment(
            string: String(data: telemetryAttachmentData, encoding: .utf8) ?? "[]")
        telemetryAttachment.name = "section-resize-bounded-runtime-telemetry"
        telemetryAttachment.lifetime = .keepAlways
        add(telemetryAttachment)
        screenshot("section-resizing-live-shell-continuity")
    }
}
