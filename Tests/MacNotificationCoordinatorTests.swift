import UserNotifications
import XCTest

@testable import AgentSessionManager

@MainActor
final class NotificationCoordinatorNavigationTests: XCTestCase {
    private func makeState(tabs: [(name: String, paneNames: [String])]) -> (AppState, [[Pane]]) {
        let state = AppState()
        let url = URL(filePath: "/tmp")
        var allPanes: [[Pane]] = []
        for tabSpec in tabs {
            let tab = Tab(name: tabSpec.name, directory: url)
            let panes = tabSpec.paneNames.map { Pane(name: $0, tab: tab) }
            tab.panes = panes
            state.tabs.append(tab)
            allPanes.append(panes)
        }
        return (state, allPanes)
    }

    override func setUp() {
        super.setUp()
        MacNotificationCoordinator.shared.bind(appState: AppState(), appSettings: AppSettings())
    }

    func testTerminalBellNavigatesToCorrectPane() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a"]),
            (name: "tab2", paneNames: ["b"]),
        ])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][0].id
        MacNotificationCoordinator.shared.bind(appState: state, appSettings: AppSettings())

        MacNotificationCoordinator.shared.handleNotificationNavigation(
            paneIDStr: panes[1][0].id.uuidString,
            tabIDStr: state.tabs[1].id.uuidString,
            kind: nil
        )

        XCTAssertEqual(state.activeTabID, state.tabs[1].id)
        XCTAssertEqual(state.activePaneID, panes[1][0].id)
    }

    func testPRMergedNavigatesToCorrectPaneAndPostsAlert() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a"]),
            (name: "tab2", paneNames: ["b"]),
        ])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][0].id
        MacNotificationCoordinator.shared.bind(appState: state, appSettings: AppSettings())

        var alertPosted = false
        let obs = NotificationCenter.default.addObserver(
            forName: .prResolutionActionRequested, object: nil, queue: nil
        ) { _ in alertPosted = true }
        defer { NotificationCenter.default.removeObserver(obs) }

        MacNotificationCoordinator.shared.handleNotificationNavigation(
            paneIDStr: panes[1][0].id.uuidString,
            tabIDStr: state.tabs[1].id.uuidString,
            kind: NotificationKind.prMerged.rawValue
        )

        XCTAssertEqual(state.activeTabID, state.tabs[1].id)
        XCTAssertEqual(state.activePaneID, panes[1][0].id)
        XCTAssertTrue(alertPosted)
    }

    func testPRClosedNavigatesToCorrectPaneAndPostsAlert() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a"]),
            (name: "tab2", paneNames: ["b"]),
        ])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][0].id
        MacNotificationCoordinator.shared.bind(appState: state, appSettings: AppSettings())

        var alertPosted = false
        var receivedKind: String?
        let obs = NotificationCenter.default.addObserver(
            forName: .prResolutionActionRequested, object: nil, queue: nil
        ) { notif in
            alertPosted = true
            receivedKind = notif.userInfo?["kind"] as? String
        }
        defer { NotificationCenter.default.removeObserver(obs) }

        MacNotificationCoordinator.shared.handleNotificationNavigation(
            paneIDStr: panes[1][0].id.uuidString,
            tabIDStr: state.tabs[1].id.uuidString,
            kind: NotificationKind.prClosed.rawValue
        )

        XCTAssertEqual(state.activeTabID, state.tabs[1].id)
        XCTAssertEqual(state.activePaneID, panes[1][0].id)
        XCTAssertTrue(alertPosted)
        XCTAssertEqual(receivedKind, NotificationKind.prClosed.rawValue)
    }

    func testHandleNotificationResponseNavigationPathStillWorks() {
        let (state, panes) = makeState(tabs: [
            (name: "tab1", paneNames: ["a"]),
            (name: "tab2", paneNames: ["b"]),
        ])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][0].id
        MacNotificationCoordinator.shared.bind(appState: state, appSettings: AppSettings())

        MacNotificationCoordinator.shared.handleNotificationNavigation(
            paneIDStr: panes[1][0].id.uuidString,
            tabIDStr: state.tabs[1].id.uuidString,
            kind: nil
        )

        XCTAssertEqual(state.activeTabID, state.tabs[1].id)
        XCTAssertEqual(state.activePaneID, panes[1][0].id)
    }

    func testNavigationNoopsWhenIDsAreInvalid() {
        let (state, panes) = makeState(tabs: [(name: "tab1", paneNames: ["a"])])
        state.activeTabID = state.tabs[0].id
        state.activePaneID = panes[0][0].id
        MacNotificationCoordinator.shared.bind(appState: state, appSettings: AppSettings())

        MacNotificationCoordinator.shared.handleNotificationNavigation(
            paneIDStr: "not-a-uuid",
            tabIDStr: "also-not-a-uuid",
            kind: nil
        )

        XCTAssertEqual(state.activeTabID, state.tabs[0].id)
        XCTAssertEqual(state.activePaneID, panes[0][0].id)
    }
}

@MainActor
final class MacNotificationCoordinatorTests: XCTestCase {
    func testWillPresentIncludesBannerAndSoundWhenAppForeground() {
        let opts = MacNotificationCoordinator.willPresentPresentationOptions
        XCTAssertTrue(opts.contains(.banner))
        XCTAssertTrue(opts.contains(.sound))
    }

    func testPaneAttentionContentIncludesContextReasonAndEscapedPercent() {
        let content = MacNotificationCoordinator.makePaneAttentionContent(
            tabName: "Tab", paneName: "Pane", reason: "Build is 50% complete")
        XCTAssertEqual(content.title, "Tab")
        XCTAssertEqual(content.subtitle, "Pane")
        XCTAssertEqual(content.body, "Build is 50%% complete")
        XCTAssertTrue(content.attachments.isEmpty)
    }

    func testPRMergedContentIncludesContextTitleAndEscapedPercent() {
        let content = MacNotificationCoordinator.makePRMergedContent(
            tabName: "Tab", paneName: "Pane", prNumber: 42, prTitle: "Reach 100%")
        XCTAssertEqual(content.title, "Tab")
        XCTAssertEqual(content.subtitle, "Pane")
        XCTAssertEqual(content.body, "PR #42 merged: Reach 100%%")
        XCTAssertTrue(content.attachments.isEmpty)
    }

    func testPRClosedContentIncludesContextTitleAndEscapedPercent() {
        let content = MacNotificationCoordinator.makePRClosedContent(
            tabName: "Tab", paneName: "Pane", prNumber: 42, prTitle: "Reach 100%")
        XCTAssertEqual(content.title, "Tab")
        XCTAssertEqual(content.subtitle, "Pane")
        XCTAssertEqual(content.body, "PR #42 closed: Reach 100%%")
        XCTAssertTrue(content.attachments.isEmpty)
    }

    func testBundleAppIconMainBundleFallbackDoesNotCrash() {
        _ = MacNotificationCoordinator.bundleAppIcon()
        if NSApp != nil {
            XCTAssertNotNil(MacNotificationCoordinator.bundleAppIcon())
        }
    }

    func testBundleAppIconLoadsFromEmbeddedICNS() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetCatalog = repoRoot.appendingPathComponent("AppIcons/Assets.xcassets")
        guard FileManager.default.fileExists(atPath: assetCatalog.path) else {
            throw XCTSkip("Asset catalog not found at \(assetCatalog.path)")
        }

        let appBundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("asm-icon-fixture-\(UUID().uuidString).app", isDirectory: true)
        let resources = appBundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        let partial = appBundle.appendingPathComponent("partial.plist")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appBundle) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "actool", assetCatalog.path,
            "--compile", resources.path,
            "--app-icon", "AppIcon",
            "--standalone-icon-behavior", "all",
            "--output-partial-info-plist", partial.path,
            "--platform", "macosx",
            "--minimum-deployment-target", "26.0",
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCTSkip("actool failed with status \(process.terminationStatus)")
        }

        let info: [String: Any] = [
            "CFBundleIconFile": "AppIcon",
            "CFBundleIconName": "AppIcon",
        ]
        let infoURL = appBundle.appendingPathComponent("Contents/Info.plist")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: info, format: .xml, options: 0)
        try plistData.write(to: infoURL)

        guard let bundle = Bundle(path: appBundle.path) else {
            XCTFail("Could not create Bundle at \(appBundle.path)")
            return
        }
        XCTAssertNotNil(MacNotificationCoordinator.bundleAppIcon(in: bundle))

        let emptyBundleDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("asm-icon-empty-\(UUID().uuidString).app", isDirectory: true)
        let emptyContents = emptyBundleDir.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyContents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyBundleDir) }
        let emptyInfo: [String: Any] = ["CFBundleIconFile": "MissingIcon"]
        try PropertyListSerialization.data(fromPropertyList: emptyInfo, format: .xml, options: 0)
            .write(to: emptyContents.appendingPathComponent("Info.plist"))
        let emptyBundle = try XCTUnwrap(Bundle(path: emptyBundleDir.path))
        XCTAssertNil(MacNotificationCoordinator.bundleAppIcon(in: emptyBundle))
    }

    func testErrorAttributesAreBoundedAndIncludeNSErrorContext() {
        let longDomain = String(repeating: "x", count: 256)
        let attributes = MacNotificationCoordinator.errorAttributes(
            NSError(domain: longDomain, code: 104),
            result: "schedule_error")
        XCTAssertEqual(attributes["error.domain"]?.count, 128)
        XCTAssertEqual(attributes["error.code"], "104")
        XCTAssertEqual(attributes["result"], "schedule_error")
    }

    func testFreshPaneWithNoStateChimes() {
        let decision = MacNotificationCoordinator.decideCoalesce(
            now: Date(), cooldown: 6,
            lastChimeAt: nil, outstanding: nil,
            incomingSource: .claudeNotification, incomingReason: "Question"
        )
        XCTAssertFalse(decision.silent)
        XCTAssertEqual(decision.reason, "Question")
        XCTAssertTrue(decision.isSpecific)
    }

    func testOutstandingNotificationSuppressesChime() {
        let now = Date()
        let decision = MacNotificationCoordinator.decideCoalesce(
            now: now, cooldown: 6,
            lastChimeAt: now.addingTimeInterval(-10), outstanding: (reason: "Question", isSpecific: true),
            incomingSource: .claudeNotification, incomingReason: "Question again"
        )
        XCTAssertTrue(decision.silent)
    }

    func testWithinCooldownAndNoOutstandingSuppressesChime() {
        let now = Date()
        let decision = MacNotificationCoordinator.decideCoalesce(
            now: now, cooldown: 6,
            lastChimeAt: now.addingTimeInterval(-2), outstanding: nil,
            incomingSource: .rawBell, incomingReason: "Attention needed"
        )
        XCTAssertTrue(decision.silent)
    }

    func testPastCooldownAndNoOutstandingChimes() {
        let now = Date()
        let decision = MacNotificationCoordinator.decideCoalesce(
            now: now, cooldown: 6,
            lastChimeAt: now.addingTimeInterval(-10), outstanding: nil,
            incomingSource: .rawBell, incomingReason: "Attention needed"
        )
        XCTAssertFalse(decision.silent)
    }

    func testOutstandingSpecificReasonSurvivesIncomingGenericStop() {
        let decision = MacNotificationCoordinator.decideCoalesce(
            now: Date(), cooldown: 6,
            lastChimeAt: nil, outstanding: (reason: "Permission needed for Bash", isSpecific: true),
            incomingSource: .claudeStop, incomingReason: "Claude finished responding"
        )
        XCTAssertTrue(decision.silent)
        XCTAssertEqual(decision.reason, "Permission needed for Bash")
        XCTAssertTrue(decision.isSpecific)
    }

    func testOutstandingGenericUpgradesToIncomingSpecificReason() {
        let decision = MacNotificationCoordinator.decideCoalesce(
            now: Date(), cooldown: 6,
            lastChimeAt: nil, outstanding: (reason: "Claude finished responding", isSpecific: false),
            incomingSource: .claudePermissionRequest, incomingReason: "Permission needed for Bash"
        )
        XCTAssertTrue(decision.silent)
        XCTAssertEqual(decision.reason, "Permission needed for Bash")
        XCTAssertTrue(decision.isSpecific)
    }
}
