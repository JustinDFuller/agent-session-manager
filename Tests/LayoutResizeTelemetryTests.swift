import XCTest

@testable import AgentSessionManager

@MainActor
final class LayoutResizeTelemetryTests: XCTestCase {
    private var traceDirectory: URL!
    private var appSettings: AppSettings!

    override func setUp() async throws {
        try await super.setUp()
        let subdirectory = "layout-resize-telemetry-\(UUID().uuidString)"
        PersistenceHelpers.overrideAppSupportSubdirectory = subdirectory
        traceDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: subdirectory, directoryHint: .isDirectory)
            .appending(path: "traces", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: traceDirectory, withIntermediateDirectories: true)
        appSettings = AppSettings()
        appSettings.debugModeEnabled = true
        TracingService.shared.configure(from: appSettings)
    }

    override func tearDown() async throws {
        appSettings.debugModeEnabled = false
        TracingService.shared.configure(from: appSettings)
        TracingService.shared.resetForTesting()
        if let traceDirectory {
            try? FileManager.default.removeItem(at: traceDirectory.deletingLastPathComponent())
        }
        PersistenceHelpers.overrideAppSupportSubdirectory = nil
        try await super.tearDown()
    }

    func testGlobalSectionResizeRecordsBoundedContext() throws {
        LayoutResizeTelemetry.record(
            event: "completed",
            section: "tab_bar",
            axis: .rows,
            source: "settings",
            before: 44,
            after: 48,
            result: "saved"
        )

        let traceWritten = expectation(description: "resize event written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { traceWritten.fulfill() }
        wait(for: [traceWritten], timeout: 2)

        let globalTrace = traceDirectory.appending(path: "_global").appending(path: "global.jsonl")
        let content = try String(contentsOf: globalTrace, encoding: .utf8)
        XCTAssertTrue(content.contains("layout.resize.completed"))
        XCTAssertTrue(content.contains("\"section\":\"tab_bar\""))
        XCTAssertTrue(content.contains("\"axis\":\"rows\""))
        XCTAssertTrue(content.contains("\"source\":\"settings\""))
        XCTAssertTrue(content.contains("\"before\":\"44.0\""))
        XCTAssertTrue(content.contains("\"after\":\"48.0\""))
        XCTAssertTrue(content.contains("\"result\":\"saved\""))
    }

    func testResizeEventsSerializeScopeAndKeyboardBoundaryContext() throws {
        let tab = Tab(name: "Resize Telemetry", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "telemetry-pane", tab: tab, harness: .codex)
        let normalAction = ResizeAction(direction: .right, larger: false)
        let largerAction = ResizeAction(direction: .left, larger: true)

        LayoutResizeTelemetry.record(
            event: "completed",
            section: "grid",
            axis: .columns,
            source: "keyboard",
            before: 420,
            after: 424,
            result: "success",
            tab: tab,
            pane: pane,
            boundary: 1,
            action: normalAction
        )
        LayoutResizeTelemetry.record(
            event: "completed",
            section: "grid",
            axis: .columns,
            source: "keyboard",
            before: 424,
            after: 408,
            result: "success",
            tab: tab,
            pane: pane,
            boundary: 0,
            action: largerAction
        )
        LayoutResizeTelemetry.record(
            event: "canceled",
            section: "grid",
            axis: .rows,
            source: "pointer",
            before: 300,
            after: 300,
            result: "canceled",
            tab: tab,
            pane: pane,
            boundary: 0
        )
        LayoutResizeTelemetry.record(
            event: "reset",
            section: "status",
            axis: .rows,
            source: "menu",
            before: 96,
            after: 24,
            result: "success",
            tab: tab,
            pane: pane
        )

        let traceWritten = expectation(description: "resize events written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { traceWritten.fulfill() }
        wait(for: [traceWritten], timeout: 2)

        let traceFiles = try XCTUnwrap(
            FileManager.default.enumerator(at: traceDirectory, includingPropertiesForKeys: nil)
        ).compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
        let records = try traceFiles.flatMap { fileURL in
            try String(contentsOf: fileURL, encoding: .utf8).split(whereSeparator: \.isNewline).compactMap {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
            }
        }
        let resizeEvents = records.filter { ($0["name"] as? String)?.hasPrefix("layout.resize.") == true }
        let completed = resizeEvents.filter { $0["name"] as? String == "layout.resize.completed" }
        XCTAssertEqual(completed.count, 2)
        let normal = try XCTUnwrap(
            completed.first { ($0["attributes"] as? [String: String])?["action"] == "normal_step" }?["attributes"]
                as? [String: String]
        )
        let larger = try XCTUnwrap(
            completed.first { ($0["attributes"] as? [String: String])?["action"] == "larger_step" }?["attributes"]
                as? [String: String]
        )
        let expectedKeyboardKeys: Set<String> = [
            "section", "axis", "source", "before", "after", "result", "tab.id", "tab.name", "pane.id",
            "pane.name", "boundary.index", "direction", "action",
        ]
        for attributes in [normal, larger] {
            XCTAssertEqual(Set(attributes.keys), expectedKeyboardKeys)
            XCTAssertEqual(attributes["section"], "grid")
            XCTAssertEqual(attributes["axis"], "columns")
            XCTAssertEqual(attributes["source"], "keyboard")
            XCTAssertEqual(attributes["result"], "success")
            XCTAssertEqual(attributes["tab.id"], tab.id.uuidString)
            XCTAssertEqual(attributes["tab.name"], tab.name)
            XCTAssertEqual(attributes["pane.id"], pane.id.uuidString)
            XCTAssertEqual(attributes["pane.name"], pane.name)
        }
        XCTAssertEqual(normal["boundary.index"], "1")
        XCTAssertEqual(normal["direction"], "right")
        XCTAssertEqual(normal["action"], "normal_step")
        XCTAssertEqual(larger["boundary.index"], "0")
        XCTAssertEqual(larger["direction"], "left")
        XCTAssertEqual(larger["action"], "larger_step")

        let canceled = try XCTUnwrap(resizeEvents.first { $0["name"] as? String == "layout.resize.canceled" })
        let canceledAttributes = try XCTUnwrap(canceled["attributes"] as? [String: String])
        XCTAssertEqual(canceledAttributes["section"], "grid")
        XCTAssertEqual(canceledAttributes["axis"], "rows")
        XCTAssertEqual(canceledAttributes["source"], "pointer")
        XCTAssertEqual(canceledAttributes["boundary.index"], "0")
        XCTAssertEqual(canceledAttributes["before"], "300.0")
        XCTAssertEqual(canceledAttributes["after"], "300.0")
        XCTAssertEqual(canceledAttributes["result"], "canceled")
        XCTAssertEqual(canceledAttributes["tab.id"], tab.id.uuidString)
        XCTAssertEqual(canceledAttributes["pane.id"], pane.id.uuidString)

        let reset = try XCTUnwrap(resizeEvents.first { $0["name"] as? String == "layout.resize.reset" })
        let resetAttributes = try XCTUnwrap(reset["attributes"] as? [String: String])
        XCTAssertEqual(resetAttributes["section"], "status")
        XCTAssertEqual(resetAttributes["axis"], "rows")
        XCTAssertEqual(resetAttributes["source"], "menu")
        XCTAssertEqual(resetAttributes["result"], "success")
        XCTAssertEqual(resetAttributes["tab.id"], tab.id.uuidString)
        XCTAssertEqual(resetAttributes["tab.name"], tab.name)
        XCTAssertEqual(resetAttributes["pane.id"], pane.id.uuidString)
        XCTAssertEqual(resetAttributes["pane.name"], pane.name)
    }

    func testSessionSaveFailureSerializesBoundedResizeContext() throws {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let blockedName = "agent-session-manager-resize-telemetry-blocked-\(UUID().uuidString)"
        let blocked = supportDirectory.appending(path: blockedName)
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try Data("blocked".utf8).write(to: blocked)
        let previousOverride = PersistenceHelpers.overrideAppSupportSubdirectory
        PersistenceHelpers.overrideAppSupportSubdirectory = blockedName
        defer {
            PersistenceHelpers.overrideAppSupportSubdirectory = previousOverride
            try? fileManager.removeItem(at: blocked)
        }

        let tab = Tab(name: "Resize Telemetry Failure", directory: URL(filePath: "/tmp"))
        let pane = Pane(name: "failure-pane", tab: tab, harness: .codex)
        LayoutResizeTelemetry.saveSession(
            appState: AppState(), appSettings: appSettings, tab: tab, pane: pane, axis: .rows, source: "pointer"
        )
        XCTAssertNotNil(appSettings.layoutSaveError)

        let traceWritten = expectation(description: "resize failure event written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { traceWritten.fulfill() }
        wait(for: [traceWritten], timeout: 2)

        let traceFiles = try XCTUnwrap(
            FileManager.default.enumerator(at: traceDirectory, includingPropertiesForKeys: nil)
        ).compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
        let records = try traceFiles.flatMap { fileURL in
            try String(contentsOf: fileURL, encoding: .utf8).split(whereSeparator: \.isNewline).compactMap {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
            }
        }
        let failure = try XCTUnwrap(records.first { $0["name"] as? String == "layout.resize.persistence_failed" })
        let attributes = try XCTUnwrap(failure["attributes"] as? [String: String])
        XCTAssertEqual(
            Set(attributes.keys),
            ["section", "axis", "source", "before", "after", "result", "tab.id", "tab.name", "pane.id", "pane.name"]
        )
        XCTAssertEqual(attributes["section"], "status")
        XCTAssertEqual(attributes["axis"], "rows")
        XCTAssertEqual(attributes["source"], "pointer")
        XCTAssertEqual(attributes["result"], "failed")
        XCTAssertEqual(attributes["tab.id"], tab.id.uuidString)
        XCTAssertEqual(attributes["tab.name"], tab.name)
        XCTAssertEqual(attributes["pane.id"], pane.id.uuidString)
        XCTAssertEqual(attributes["pane.name"], pane.name)
        XCTAssertFalse(attributes.values.contains("blocked"))
    }
}
