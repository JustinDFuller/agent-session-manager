import SwiftUI

struct PaneAdvancedSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var appSettings

    @Binding var isPriority: Bool
    @Binding var agentControlInjectionEnabled: Bool
    @Binding var scrollbackOverride: ScrollbackLimit?
    @Binding var scrollbackLinesText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("More Settings")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if appSettings.isPriorityNotificationsEnabled {
                        prioritySection
                    }
                    agentControlSection
                    scrollbackSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("new-pane-advanced-settings-content-scroll-view")

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("new-pane-advanced-settings-done-button")
            }
        }
        .padding(24)
        .frame(width: 420, height: 520, alignment: .topLeading)
        .pinnedSheetBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("new-pane-advanced-settings-sheet")
    }

    private var prioritySection: some View {
        Toggle(isOn: $isPriority) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Priority Pane")
                    .font(.subheadline)
                Text("Priority notifications jump to the top of the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("new-pane-priority-toggle")
    }

    private var agentControlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Control")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if appSettings.agentControlInjectionPolicy.isAskPolicy {
                Toggle(isOn: $agentControlInjectionEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Agent Session Manager control")
                        Text("Allow this pane to use the app-owned control surface.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("new-pane-agent-control-toggle")
            } else {
                Text(
                    appSettings.agentControlInjectionPolicy == .always
                        ? "Agent Session Manager control will be enabled."
                        : "Agent Session Manager control will be disabled."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("new-pane-agent-control-policy-status")
            }
            Text("Scope: \(appSettings.agentControlScope.displayName)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var scrollbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scrollback History")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollbackLimitEditor(
                value: scrollbackOverride,
                allowsInheritance: true,
                inheritedValue: appSettings.defaultScrollback,
                accessibilityPrefix: "new-pane-scrollback",
                onChange: { scrollbackOverride = $0 },
                finiteLinesText: $scrollbackLinesText
            )
        }
    }
}
