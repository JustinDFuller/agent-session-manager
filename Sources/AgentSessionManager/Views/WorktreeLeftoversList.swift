import SwiftUI

struct WorktreeLeftoversList: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var appSettings
    @State private var model = WorktreeLeftoversModel()

    var body: some View {
        Group {
            header
            if model.leftovers.isEmpty {
                Text(model.hasScanned ? "No leftover worktrees." : "Scanning for leftover worktrees…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-leftovers-empty")
            } else {
                ForEach(model.leftovers) { leftover in
                    WorktreeLeftoverRow(
                        leftover: leftover, model: model,
                        reason: model.reason(for: leftover, launchCleanupEnabled: appSettings.cleanUpLeftoversAtLaunch))
                }
            }
        }
        .task { await model.scan(appState: appState, appSettings: appSettings) }
        .modifier(WorktreeLeftoverAlerts(model: model))
    }

    private var header: some View {
        LabeledContent {
            HStack {
                Button("Refresh") {
                    Task { await model.scan(appState: appState, appSettings: appSettings) }
                }
                .disabled(model.isScanning)
                .accessibilityIdentifier("settings-leftovers-refresh")
                Button("Delete Selected", role: .destructive) {
                    model.requestDelete(appState: appState, appSettings: appSettings)
                }
                .disabled(model.selection.isEmpty)
                .accessibilityIdentifier("settings-leftovers-delete")
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Leftover Worktrees")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text(
                    "Worktrees Agent Session Manager created that no pane is using. "
                        + "Deleting one removes its folder and, when Delete Branch With Worktree is on, its local branch."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .pinnedListRowBackground()
    }
}

private struct WorktreeLeftoverRow: View {
    let leftover: WorktreeLeftover
    let model: WorktreeLeftoversModel
    let reason: String

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { model.selection.contains(leftover.id) },
                set: { isOn in
                    if isOn {
                        model.selection.insert(leftover.id)
                    } else {
                        model.selection.remove(leftover.id)
                    }
                })
        ) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(leftover.name)
                        .font(.system(.body, design: .monospaced))
                    if !leftover.isRegistered {
                        Text("Not a git worktree")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(leftover.repository.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("settings-leftover-\(leftover.name)")
        .task { await model.loadSize(of: leftover) }
        .pinnedListRowBackground()
    }

    private var sizeText: String {
        guard let size = model.sizes[leftover.id] else { return "Calculating size…" }
        return size.formatted(.byteCount(style: .file))
    }
}

private struct WorktreeLeftoverAlerts: ViewModifier {
    let model: WorktreeLeftoversModel

    func body(content: Content) -> some View {
        content
            .alert(
                model.unsavedPrompt?.title ?? "",
                isPresented: Binding(get: { model.unsavedPrompt != nil }, set: { _ in })
            ) {
                if let prompt = model.unsavedPrompt {
                    Button(prompt.keepLabel) { model.answer(.keep) }
                    Button("Delete Anyway", role: .destructive) { model.answer(.deleteAnyway) }
                    Button("Cancel", role: .cancel) { model.answer(.cancel) }
                }
            } message: {
                Text(model.unsavedPrompt?.message ?? "")
            }
            .alert(
                model.folderPrompt?.title ?? "",
                isPresented: Binding(get: { model.folderPrompt != nil }, set: { _ in })
            ) {
                if let prompt = model.folderPrompt {
                    Button(prompt.deleteLabel, role: .destructive) { model.confirmFolders(true) }
                    Button("Cancel", role: .cancel) { model.confirmFolders(false) }
                }
            } message: {
                Text(model.folderPrompt?.message ?? "")
            }
            .alert(
                model.notice?.title ?? "",
                isPresented: Binding(get: { model.notice != nil }, set: { _ in })
            ) {
                Button("OK", role: .cancel) { model.dismissNotice() }
            } message: {
                Text(model.notice?.message ?? "")
            }
    }
}
