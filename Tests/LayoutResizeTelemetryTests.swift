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
}
