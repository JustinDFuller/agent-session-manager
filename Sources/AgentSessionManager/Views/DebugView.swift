import SwiftUI

struct DebugView: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            Section("Debug") {
                SettingRow(
                    title: "Enable Debug Mode",
                    description: "Write OpenTelemetry traces and invariant violations to bounded JSONL files.",
                    defaultValue: "Off"
                ) {
                    Toggle("Enable Debug Mode", isOn: $appSettings.debugModeEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("settings-debug-mode-toggle")
                        .onChange(of: appSettings.debugModeEnabled) {
                            guard SettingsPersistence.saveDebugSettings(enabled: appSettings.debugModeEnabled) else {
                                return
                            }
                            TracingService.shared.configure(from: appSettings)
                            InvariantReporter.shared.configure(from: appSettings)
                        }
                }
            }
            Section("Dashboards") {
                Button("Open Trace Dashboard") {
                    AuxiliaryWindowRegistry.open(
                        .traceDashboard, tracesDirectory: appSettings.resolvedTracingDirectoryURL,
                        invariantsDirectory: appSettings.resolvedInvariantDirectoryURL)
                }
                .accessibilityIdentifier("settings-open-trace-dashboard-button")
                Button("Open Invariant Dashboard") {
                    AuxiliaryWindowRegistry.open(
                        .invariantDashboard, tracesDirectory: appSettings.resolvedTracingDirectoryURL,
                        invariantsDirectory: appSettings.resolvedInvariantDirectoryURL)
                }
                .accessibilityIdentifier("settings-open-invariant-dashboard-button")
            }
            Section {
                Text("Debug files use fixed 10 MB limits under Application Support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .pinnedFormBackground()
    }
}
