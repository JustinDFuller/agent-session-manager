import SwiftUI

struct OptionState {
    var enabled: Bool
    var value: String
    var values: [String] = []
}

struct PaneCreationOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedHarness: Harness
    let visibleCLIOptions: [CLIOptionConfig]
    let hiddenCLIOptions: [CLIOptionConfig]
    let visibleEnvVars: [EnvVarConfig]
    let hiddenEnvVarOptions: [EnvVarConfig]
    @Binding var optionStates: [String: OptionState]
    @Binding var envVarStates: [String: OptionState]
    let onAddCLIOptionToGlobal: (CLIOptionConfig) -> Void
    let onAddEnvVarToGlobal: (EnvVarConfig) -> Void

    @State private var showHiddenOptions = false
    @State private var showHiddenEnvVars = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("CLI Options")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !visibleCLIOptions.isEmpty {
                        visibleCLIOptionsSection
                    }

                    if !hiddenCLIOptions.isEmpty {
                        hiddenCLIOptionsSection
                    }

                    if selectedHarness == .claude || selectedHarness == .opencode {
                        if !visibleEnvVars.isEmpty {
                            visibleEnvVarsSection
                        }
                        if !hiddenEnvVarOptions.isEmpty {
                            hiddenEnvVarsSection
                        }
                    }

                    if visibleCLIOptions.isEmpty && hiddenCLIOptions.isEmpty
                        && visibleEnvVars.isEmpty && hiddenEnvVarOptions.isEmpty
                    {
                        Text("This harness has no configurable pane options.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("new-pane-cli-options-content-scroll-view")

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("new-pane-cli-options-done-button")
            }
        }
        .padding(24)
        .frame(width: 620, height: 560, alignment: .topLeading)
        .pinnedSheetBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("new-pane-cli-options-sheet")
    }

    @ViewBuilder
    private var visibleCLIOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Options shown for this pane")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleCLIOptions) { option in
                    CLIOptionToggleRow(option: option, state: stateBinding(for: option))
                }
            }
        }
    }

    @ViewBuilder
    private var hiddenCLIOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showHiddenOptions.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showHiddenOptions ? "chevron.down" : "chevron.right")
                    Text(showHiddenOptions ? "Fewer options" : "Show all options")
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("new-pane-show-hidden-options-button")

            if showHiddenOptions {
                Text("Options not shown by default are still applied when enabled in the selected profile.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(hiddenCLIOptions) { option in
                        HiddenCLIOptionToggleRow(
                            option: option,
                            state: stateBinding(for: option),
                            onAddToGlobal: option.isAvailable ? nil : { onAddCLIOptionToGlobal(option) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var visibleEnvVarsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Environment Variables")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleEnvVars) { envVar in
                    EnvVarToggleRow(envVar: envVar, state: envVarStateBinding(for: envVar))
                }
            }
        }
    }

    @ViewBuilder
    private var hiddenEnvVarsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showHiddenEnvVars.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showHiddenEnvVars ? "chevron.down" : "chevron.right")
                    Text(showHiddenEnvVars ? "Fewer environment variables" : "Show all environment variables")
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("new-pane-show-hidden-env-vars-button")

            if showHiddenEnvVars {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(hiddenEnvVarOptions) { envVar in
                        HiddenEnvVarToggleRow(
                            envVar: envVar,
                            state: envVarStateBinding(for: envVar),
                            onAddToGlobal: envVar.isAvailable ? nil : { onAddEnvVarToGlobal(envVar) }
                        )
                    }
                }
            }
        }
    }

    private func stateBinding(for option: CLIOptionConfig) -> Binding<OptionState> {
        Binding(
            get: { optionStates[option.id] ?? OptionState(enabled: option.isDefaultEnabled, value: "") },
            set: { optionStates[option.id] = $0 }
        )
    }

    private func envVarStateBinding(for envVar: EnvVarConfig) -> Binding<OptionState> {
        Binding(
            get: {
                envVarStates[envVar.id]
                    ?? OptionState(enabled: envVar.isDefaultEnabled, value: envVar.defaultValue)
            },
            set: { envVarStates[envVar.id] = $0 }
        )
    }
}

private struct CLIOptionToggleRow: View {
    let option: CLIOptionConfig
    @Binding var state: OptionState

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(isOn: $state.enabled) {
                Text(option.id)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CLIOptionValueField(option: option, value: $state.value, values: $state.values, enabled: state.enabled)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct EnvVarToggleRow: View {
    let envVar: EnvVarConfig
    @Binding var state: OptionState

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(isOn: $state.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(envVar.id)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    if envVar.isAppControlled {
                        Text("Controlled by Agent Session Manager")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(envVar.isAppControlled)
            TextField("Value", text: $state.value)
                .textFieldStyle(.roundedBorder)
                .disabled(!state.enabled || envVar.isAppControlled)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct HiddenCLIOptionToggleRow: View {
    let option: CLIOptionConfig
    @Binding var state: OptionState
    let onAddToGlobal: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(isOn: $state.enabled) {
                Text(option.id)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CLIOptionValueField(option: option, value: $state.value, values: $state.values, enabled: state.enabled)
                .frame(maxWidth: .infinity)
            if state.enabled, let onAddToGlobal {
                Button("Show in all profiles", action: onAddToGlobal)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

private struct HiddenEnvVarToggleRow: View {
    let envVar: EnvVarConfig
    @Binding var state: OptionState
    let onAddToGlobal: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(isOn: $state.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(envVar.id)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    if envVar.isAppControlled {
                        Text("Controlled by Agent Session Manager")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(envVar.isAppControlled)
            TextField("Value", text: $state.value)
                .textFieldStyle(.roundedBorder)
                .disabled(!state.enabled || envVar.isAppControlled)
                .frame(maxWidth: .infinity)
            if state.enabled && !envVar.isAppControlled, let onAddToGlobal {
                Button("Show in all profiles", action: onAddToGlobal)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
