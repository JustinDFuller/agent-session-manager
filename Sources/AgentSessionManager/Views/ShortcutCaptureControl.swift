import AppKit
import SwiftUI

enum ShortcutCaptureResult {
    case binding(ResizeKeyBinding)
    case cancelled
    case invalid(String)
}

enum ResizeShortcutValidation {
    static func validateResizeBinding(
        _ binding: ResizeKeyBinding,
        action: ResizeAction,
        bindings: PaneResizeShortcutBindings,
        appBindings: Set<ResizeKeyBinding>
    ) -> String? {
        guard binding.isValid else {
            return "Use one letter, number, or arrow key with Command."
        }
        guard !appBindings.contains(binding) else {
            return "That key is already assigned to an app shortcut."
        }
        let conflictsWithResize = ResizeAction.allCases.contains { candidate in
            candidate != action && bindings.binding(for: candidate) == binding
        }
        return conflictsWithResize ? "That key is already assigned to another pane resize shortcut." : nil
    }

    static func validateAppBinding(
        _ binding: ResizeKeyBinding,
        resizeBindings: PaneResizeShortcutBindings
    ) -> String? {
        resizeBindings.entries.values.contains(binding)
            ? "This key is assigned to a pane resize shortcut."
            : nil
    }
}

struct ShortcutCaptureControl: View {
    let action: ResizeAction
    let binding: ResizeKeyBinding?
    @Binding var isCapturing: Bool
    let onCapture: (ResizeKeyBinding) -> Void
    let onCancel: () -> Void
    let onInvalid: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(isCapturing ? "Press a Key…" : binding?.display ?? "Disabled") {
                isCapturing = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("settings-resize-shortcut-capture-\(action.id)")

            if isCapturing {
                ShortcutCaptureView { result in
                    isCapturing = false
                    switch result {
                    case .binding(let binding): onCapture(binding)
                    case .cancelled: onCancel()
                    case .invalid(let message): onInvalid(message)
                    }
                }
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onResult: (ShortcutCaptureResult) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onResult = onResult
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onResult = onResult
        if nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class ShortcutCaptureNSView: NSView {
    var onResult: ((ShortcutCaptureResult) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        capture(event)
    }

    private func capture(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            onResult?(.cancelled)
            return true
        }
        let key = ResizeKeyBinding.key(for: event)
        guard key.count == 1, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onResult?(.invalid("Choose a letter, number, or arrow key."))
            return true
        }
        let binding = ResizeKeyBinding(
            key: key,
            modifiers: event.modifierFlags.intersection([.command, .option, .shift, .control])
        )
        guard binding.isValid else {
            onResult?(.binding(binding))
            return true
        }
        onResult?(.binding(binding))
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if modifiers.isEmpty {
            onResult?(.invalid("Choose a key after pressing a modifier."))
        }
    }
}
