import AppKit
import Foundation
import SwiftUI

enum AuxiliaryWindow: String, CaseIterable {
    case traceDashboard = "trace-dashboard"
    case invariantDashboard = "invariant-dashboard"

    var title: String {
        switch self {
        case .traceDashboard: "Trace Dashboard"
        case .invariantDashboard: "Invariant Dashboard"
        }
    }
}

enum AuxiliaryWindowRegistry {
    static let auxiliaryWindowIDsByTitle: [String: String] = Dictionary(
        uniqueKeysWithValues: AuxiliaryWindow.allCases.map { ($0.title, $0.rawValue) }
    )

    @discardableResult
    static func check(openTitles: [String], requestedIDs: Set<String>) -> Bool {
        var passed = true
        for title in openTitles {
            guard let id = auxiliaryWindowIDsByTitle[title] else { continue }
            let requested = InvariantReporter.shared.check(
                .appLaunchAuxiliaryWindowsClosed,
                requestedIDs.contains(id),
                context: ["window.title": title, "window.id": id]
            )
            if !requested { passed = false }
        }
        return passed
    }
}

extension AuxiliaryWindowRegistry {
    @MainActor
    private static var requestedWindowIDs: Set<String> = []

    @MainActor
    private static var windowControllers: [AuxiliaryWindow: NSWindowController] = [:]

    @MainActor
    static func open(_ window: AuxiliaryWindow, tracesDirectory: URL, invariantsDirectory: URL) {
        requestedWindowIDs.insert(window.rawValue)
        if windowControllers[window] == nil {
            let content: AnyView
            switch window {
            case .traceDashboard:
                content = AnyView(TraceDashboardView(tracesDirectory: tracesDirectory))
            case .invariantDashboard:
                content = AnyView(InvariantDashboardView(directory: invariantsDirectory))
            }
            let hosting = NSHostingController(rootView: content.preferredColorScheme(.dark).tint(Theme.accent))
            let nativeWindow = NSWindow(contentViewController: hosting)
            nativeWindow.title = window.title
            nativeWindow.identifier = NSUserInterfaceItemIdentifier(window.rawValue)
            nativeWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            nativeWindow.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
            nativeWindow.isReleasedWhenClosed = false
            nativeWindow.isRestorable = false
            Theme.configure(window: nativeWindow, using: Theme.dashboardWindowChrome)
            nativeWindow.setFrame(NSRect(x: 0, y: 0, width: 900, height: 664), display: false)
            nativeWindow.center()
            windowControllers[window] = NSWindowController(window: nativeWindow)
        }
        NSApp.activate(ignoringOtherApps: true)
        windowControllers[window]?.showWindow(nil)
        windowControllers[window]?.window?.makeKeyAndOrderFront(nil)
        TracingService.shared.record("app.auxiliary_window.opened", attributes: ["window.id": window.rawValue])
    }

    @MainActor
    static func resetForTesting() {
        for controller in windowControllers.values {
            controller.close()
        }
        windowControllers = [:]
        requestedWindowIDs = []
    }

    @MainActor
    @discardableResult
    static func checkOpenWindows() -> Bool {
        let openTitles = NSApp?.windows.filter(\.isVisible).map(\.title) ?? []
        TracingService.shared.record(
            "app.launch.auxiliary_windows_checked",
            attributes: [
                "window.titles": openTitles.joined(separator: ","),
                "window.requested_ids": requestedWindowIDs.sorted().joined(separator: ","),
            ]
        )
        return check(openTitles: openTitles, requestedIDs: requestedWindowIDs)
    }
}
