import SwiftUI

private struct WorktreeCloseAlerts: ViewModifier {
    let flow: WorktreeCloseFlow

    func body(content: Content) -> some View {
        content
            .alert(
                flow.askPrompt?.title ?? "",
                isPresented: Binding(get: { flow.askPrompt != nil }, set: { _ in })
            ) {
                if let prompt = flow.askPrompt {
                    Button(prompt.keepLabel) { flow.answer(WorktreeAskChoice.keep) }
                    Button(prompt.deleteLabel, role: .destructive) { flow.answer(WorktreeAskChoice.delete) }
                    Button("Cancel", role: .cancel) { flow.answer(WorktreeAskChoice.cancel) }
                }
            } message: {
                Text(flow.askPrompt?.message ?? "")
            }
            .alert(
                flow.unsavedPrompt?.title ?? "",
                isPresented: Binding(get: { flow.unsavedPrompt != nil }, set: { _ in })
            ) {
                if let prompt = flow.unsavedPrompt {
                    Button(prompt.keepLabel) { flow.answer(WorktreeUnsavedChoice.keep) }
                    Button("Delete Anyway", role: .destructive) { flow.answer(WorktreeUnsavedChoice.deleteAnyway) }
                    Button("Cancel", role: .cancel) { flow.answer(WorktreeUnsavedChoice.cancel) }
                }
            } message: {
                Text(flow.unsavedPrompt?.message ?? "")
            }
            .alert(
                flow.notice?.title ?? "",
                isPresented: Binding(get: { flow.notice != nil }, set: { _ in })
            ) {
                Button("OK", role: .cancel) { flow.dismissNotice() }
            } message: {
                Text(flow.notice?.message ?? "")
            }
    }
}

extension View {
    func worktreeCloseAlerts(_ flow: WorktreeCloseFlow) -> some View {
        modifier(WorktreeCloseAlerts(flow: flow))
    }
}
