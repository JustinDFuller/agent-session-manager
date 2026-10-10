import AppKit
import XCTest

@testable import AgentSessionManager

@MainActor
final class AuxiliaryWindowRegistryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        InvariantReporter.shared.resetForTesting()
        TracingService.shared.resetForTesting()
        AuxiliaryWindowRegistry.resetForTesting()
    }

    override func tearDown() {
        InvariantReporter.shared.resetForTesting()
        TracingService.shared.resetForTesting()
        AuxiliaryWindowRegistry.resetForTesting()
        super.tearDown()
    }

    func testNoWindowsPasses() {
        InvariantReporter.shared.enableTestCapture()

        XCTAssertTrue(AuxiliaryWindowRegistry.check(openTitles: [], requestedIDs: []))
        XCTAssertTrue(InvariantReporter.shared.violationsForTesting.isEmpty)
    }

    func testMainWindowOnlyPasses() {
        InvariantReporter.shared.enableTestCapture()

        XCTAssertTrue(
            AuxiliaryWindowRegistry.check(openTitles: ["Agent Session Manager (Dev)"], requestedIDs: []))
        XCTAssertTrue(InvariantReporter.shared.violationsForTesting.isEmpty)
    }

    func testDashboardOpenWithoutRequestReportsViolationWithWindowTitle() {
        InvariantReporter.shared.enableTestCapture()

        XCTAssertFalse(
            AuxiliaryWindowRegistry.check(openTitles: ["Trace Dashboard"], requestedIDs: []))
        let violation = InvariantReporter.shared.violationsForTesting.first
        XCTAssertEqual(violation?.invariantID, "app.launch.auxiliary_windows_closed")
        XCTAssertEqual(violation?.context["window.title"], "Trace Dashboard")
        XCTAssertEqual(violation?.context["window.id"], "trace-dashboard")
    }

    func testDashboardOpenAfterMatchingRequestPasses() {
        InvariantReporter.shared.enableTestCapture()

        XCTAssertTrue(
            AuxiliaryWindowRegistry.check(
                openTitles: ["Invariant Dashboard"], requestedIDs: ["invariant-dashboard"]))
        XCTAssertTrue(InvariantReporter.shared.violationsForTesting.isEmpty)
    }

    func testTwoUnrequestedDashboardsOpenAtOnceReportsTwoViolations() {
        InvariantReporter.shared.enableTestCapture()

        XCTAssertFalse(
            AuxiliaryWindowRegistry.check(
                openTitles: ["Trace Dashboard", "Invariant Dashboard"], requestedIDs: []))
        let violations = InvariantReporter.shared.violationsForTesting
        XCTAssertEqual(violations.count, 2)
        XCTAssertEqual(Set(violations.map { $0.context["window.id"] }), ["trace-dashboard", "invariant-dashboard"])
    }

    func testCheckOpenWindowsRecordsThatItRan() {
        TracingService.shared.enableTestCapture()

        AuxiliaryWindowRegistry.checkOpenWindows()

        let recorded = TracingService.shared.recordedEventsForTesting.contains {
            $0.name == "app.launch.auxiliary_windows_checked"
        }
        XCTAssertTrue(recorded, "checkOpenWindows() must record that it ran, even on a quiet launch")
    }

    func testExplicitOpenCreatesNonRestorableDashboardsAndReusesClosedWindows() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "agent-session-manager-dashboard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        TracingService.shared.enableTestCapture()
        for dashboard in AuxiliaryWindow.allCases {
            AuxiliaryWindowRegistry.open(dashboard, tracesDirectory: directory, invariantsDirectory: directory)
            let window = try XCTUnwrap(NSApp.windows.first { $0.title == dashboard.title })
            XCTAssertFalse(window.isRestorable)
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(window.frame.size, NSSize(width: 900, height: 664))
            XCTAssertTrue(AuxiliaryWindowRegistry.checkOpenWindows())
            window.close()
            AuxiliaryWindowRegistry.open(dashboard, tracesDirectory: directory, invariantsDirectory: directory)
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(NSApp.windows.filter { $0.title == dashboard.title }.count, 1)
            let events = TracingService.shared.recordedEventsForTesting.filter {
                $0.name == "app.auxiliary_window.opened" && $0.attributes["window.id"] == dashboard.rawValue
            }
            XCTAssertEqual(events.count, 2)
        }
    }
}
