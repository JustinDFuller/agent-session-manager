import SwiftUI

struct RefreshPaneSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pane: Pane
    let onQuickRefresh: (Pane) -> Void
    let onRefreshWithSettings: (Pane) -> Void

    var continuationDescription: String {
        guard pane.harness == .codex else { return "Restart with the same settings and --continue" }
        switch pane.codexContinuationRecovery {
        case .identityNotRecorded:
            return "Codex has not reported a conversation to continue."
        case .exactSessionUnavailable:
            return "The saved Codex conversation is unavailable. Choose Retry or start a new conversation."
        case nil:
            return pane.codexSessionID == nil
                ? "Codex has not reported a conversation to continue."
                : "Resume this pane's exact foreground conversation."
        }
    }

    var settingsDescription: String {
        pane.harness == .codex
            ? "Start a fresh Codex conversation with reconfigured options."
            : "Reconfigure CLI options before restarting"
    }

    var isContinuationDisabled: Bool {
        pane.harness == .codex
            && (pane.codexSessionID == nil || pane.codexContinuationRecovery != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Refresh Pane")
                .font(.headline)

            Text("Restart \"\(pane.name)\" with a fresh environment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Button {
                    onQuickRefresh(pane)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Refresh and Continue")
                                .fontWeight(.medium)
                            Text(continuationDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("refresh-pane-quick")
                .disabled(isContinuationDisabled)

                Button {
                    onRefreshWithSettings(pane)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Refresh with New Settings\u{2026}")
                                .fontWeight(.medium)
                            Text(settingsDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("refresh-pane-settings")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("refresh-pane-cancel")
            }
        }
        .padding(24)
        .frame(width: 320)
        .pinnedSheetBackground()
    }
}
