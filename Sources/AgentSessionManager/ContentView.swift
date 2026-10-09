import AppKit
import SwiftUI

@main
struct AgentSessionManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var cleanupService: TraceCleanupService?

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands { AppCommands(appState: appDelegate.appState, appSettings: appDelegate.appSettings) }
    }
}

private struct AppCommands: Commands {
    let appState: AppState
    let appSettings: AppSettings
    @AppStorage("keyBinding.newTabKey") var newTabKey = "t"
    @AppStorage("keyBinding.newPaneKey") var newPaneKey = "p"
    @AppStorage("keyBinding.closeTabKey") var closeTabKey = "k"
    @AppStorage("keyBinding.openShellHereKey") var openShellHereKey = "s"
    @AppStorage("keyBinding.viewPaneSettingsKey") var viewPaneSettingsKey = "i"

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings\u{2026}") {
                NotificationCenter.default.post(name: .toggleSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .windowSize) {
            Button("Open Trace Dashboard") {
                AuxiliaryWindowRegistry.open(
                    .traceDashboard, tracesDirectory: appSettings.resolvedTracingDirectoryURL,
                    invariantsDirectory: appSettings.resolvedInvariantDirectoryURL)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Open Invariant Dashboard") {
                AuxiliaryWindowRegistry.open(
                    .invariantDashboard, tracesDirectory: appSettings.resolvedTracingDirectoryURL,
                    invariantsDirectory: appSettings.resolvedInvariantDirectoryURL)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                NotificationCenter.default.post(name: .newTab, object: nil)
            }
            .keyboardShortcut(KeyEquivalent(Character(newTabKey)), modifiers: .command)

            Button("New Pane in Current Tab") {
                NotificationCenter.default.post(name: .newPane, object: nil)
            }
            .keyboardShortcut(KeyEquivalent(Character(newPaneKey)), modifiers: .command)
            .disabled(appState.tabs.isEmpty)

            Button("Open Shell Here") {
                NotificationCenter.default.post(name: .openShellHere, object: nil)
            }
            .keyboardShortcut(KeyEquivalent(Character(openShellHereKey)), modifiers: [.command, .shift])
            .disabled(appState.tabs.isEmpty)

            Button("View Pane Settings") {
                NotificationCenter.default.post(name: .viewPaneSettings, object: nil)
            }
            .keyboardShortcut(KeyEquivalent(Character(viewPaneSettingsKey)), modifiers: .command)
            .disabled(appState.activeTab?.panes.isEmpty ?? true)

            Divider()

            Button("Close Tab") {
                NotificationCenter.default.post(name: .closeTab, object: nil)
            }
            .keyboardShortcut(KeyEquivalent(Character(closeTabKey)), modifiers: .command)
            .disabled(appState.tabs.isEmpty)
        }
    }
}

extension Notification.Name {
    static let toggleSettings = Notification.Name("toggleSettings")
    static let newTab = Notification.Name("newTab")
    static let newPane = Notification.Name("newPane")
    static let closeTab = Notification.Name("closeTab")
    static let prResolutionActionRequested = Notification.Name("prResolutionActionRequested")
    static let openShellHere = Notification.Name("openShellHere")
    static let viewPaneSettings = Notification.Name("viewPaneSettings")
    static let agentSessionManagerPRTrackingSettingChanged = Notification.Name(
        "agentSessionManagerPRTrackingSettingChanged")
    static let agentSessionManagerCursorNotificationSettingChanged = Notification.Name(
        "agentSessionManagerCursorNotificationSettingChanged")
    static let showSettingsSection = Notification.Name("showSettingsSection")
}

extension AgentSessionManagerApp {
    static var isUITesting: Bool {
        CommandLine.arguments.contains("--uitesting")
    }
}
