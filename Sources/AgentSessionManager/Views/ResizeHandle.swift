import AppKit
import SwiftUI

struct ResizeHandle: NSViewRepresentable {
    let axis: ResizeAxis
    let identifier: String
    let label: String
    let value: Double
    let minimum: Double
    let maximum: Double
    var focusTarget: NSResponder?
    var movementSign = 1.0
    var highlighted = false
    let cancellationKey: String
    let onPreview: (Double?) -> Void
    let onCommit: (Double, String) -> Void
    let onReset: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ResizeHandleNativeView {
        let view = ResizeHandleNativeView()
        view.configure(
            axis: axis,
            identifier: identifier,
            label: label,
            value: value,
            minimum: minimum,
            maximum: maximum,
            focusTarget: focusTarget,
            movementSign: movementSign,
            highlighted: highlighted,
            cancellationKey: cancellationKey,
            onPreview: onPreview,
            onCommit: onCommit,
            onReset: onReset,
            onCancel: onCancel
        )
        return view
    }

    func updateNSView(_ nsView: ResizeHandleNativeView, context: Context) {
        nsView.configure(
            axis: axis,
            identifier: identifier,
            label: label,
            value: value,
            minimum: minimum,
            maximum: maximum,
            focusTarget: focusTarget,
            movementSign: movementSign,
            highlighted: highlighted,
            cancellationKey: cancellationKey,
            onPreview: onPreview,
            onCommit: onCommit,
            onReset: onReset,
            onCancel: onCancel
        )
    }

    static func dismantleNSView(_ nsView: ResizeHandleNativeView, coordinator: ()) {
        nsView.cancelInteraction()
    }
}

struct ResizeHandleInteraction {
    private(set) var startValue: Double?
    private(set) var minimum = 0.0
    private(set) var maximum = 0.0

    var isActive: Bool { startValue != nil }

    mutating func begin(value: Double, minimum: Double, maximum: Double) {
        self.minimum = minimum
        self.maximum = maximum
        startValue = min(max(value, minimum), maximum)
    }

    func preview(translation: Double) -> Double? {
        guard let startValue else { return nil }
        return min(max(startValue + translation, minimum), maximum)
    }

    mutating func finish() -> Double? {
        defer { startValue = nil }
        return startValue
    }

    mutating func cancel() {
        startValue = nil
    }

    static func value(from value: Double, delta: Double, minimum: Double, maximum: Double) -> Double {
        min(max(value + delta, minimum), maximum)
    }

    static func physicalTranslation(
        axis: ResizeAxis, from start: CGPoint, to current: CGPoint, movementSign: Double = 1
    ) -> Double {
        let translation: Double
        switch axis {
        case .columns: translation = current.x - start.x
        case .rows: translation = start.y - current.y
        }
        return translation * movementSign
    }

    static func arrowDelta(axis: ResizeAxis, keyCode: UInt16, shifted: Bool) -> Double? {
        let direction: Double
        switch (axis, keyCode) {
        case (.columns, 123), (.rows, 126): direction = -1
        case (.columns, 124), (.rows, 125): direction = 1
        default: return nil
        }
        return direction * (shifted ? 16 : 4)
    }
}

final class ResizeHandleNativeView: NSView {
    private(set) var interaction = ResizeHandleInteraction()
    private var axis: ResizeAxis = .columns
    private var handleIdentifier = ""
    private var handleLabel = ""
    private var value = 0.0
    private var minimum = 0.0
    private var maximum = 0.0
    private var focusTarget: NSResponder?
    private var movementSign = 1.0
    private var isExternallyHighlighted = false
    private var cancellationKey = ""
    private var isHovered = false
    private var isFocused = false
    private var dragStart = CGPoint.zero
    private var didDrag = false
    private var priorFirstResponder: NSResponder?
    private var trackingArea: NSTrackingArea?
    private var onPreview: (Double?) -> Void = { _ in }
    private var onCommit: (Double, String) -> Void = { _, _ in }
    private var onReset: (String) -> Void = { _ in }
    private var onCancel: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(true)
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        axis == .columns
            ? NSSize(width: effectiveThickness, height: NSView.noIntrinsicMetric)
            : NSSize(width: NSView.noIntrinsicMetric, height: effectiveThickness)
    }

    var visibleThickness: CGFloat { 1 }
    var effectiveThickness: CGFloat { 8 }

    func configure(
        axis: ResizeAxis,
        identifier: String,
        label: String,
        value: Double,
        minimum: Double,
        maximum: Double,
        focusTarget: NSResponder?,
        movementSign: Double,
        highlighted: Bool,
        cancellationKey: String,
        onPreview: @escaping (Double?) -> Void,
        onCommit: @escaping (Double, String) -> Void,
        onReset: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let focusTargetChanged = self.focusTarget !== focusTarget
        let cancellationChanged =
            self.axis != axis || handleIdentifier != identifier
            || self.cancellationKey != cancellationKey
            || self.minimum != minimum || self.maximum != maximum || focusTargetChanged
        if cancellationChanged, interaction.isActive {
            if focusTargetChanged { priorFirstResponder = nil }
            self.focusTarget = focusTarget
            cancelInteraction()
        }
        self.axis = axis
        handleIdentifier = identifier
        handleLabel = label
        self.minimum = minimum
        self.maximum = maximum
        self.focusTarget = focusTarget
        self.movementSign = movementSign
        isExternallyHighlighted = highlighted
        self.cancellationKey = cancellationKey
        self.onPreview = onPreview
        self.onCommit = onCommit
        self.onReset = onReset
        self.onCancel = onCancel
        if !interaction.isActive {
            self.value = value
        }
        setAccessibilityIdentifier(identifier)
        setAccessibilityLabel(label)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color =
            isHovered || isFocused || isExternallyHighlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.8)
            : NSColor.separatorColor
        color.setFill()
        if axis == .columns {
            NSRect(x: (bounds.width - visibleThickness) / 2, y: 0, width: visibleThickness, height: bounds.height)
                .fill()
        } else {
            NSRect(x: 0, y: (bounds.height - visibleThickness) / 2, width: bounds.width, height: visibleThickness)
                .fill()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        cursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if priorFirstResponder == nil, let firstResponder = window?.firstResponder, firstResponder !== self {
            priorFirstResponder = firstResponder
        }
        let accepted = super.becomeFirstResponder()
        isFocused = accepted
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { priorFirstResponder = nil }
        isFocused = false
        needsDisplay = true
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        if let firstResponder = window?.firstResponder, firstResponder !== self {
            priorFirstResponder = firstResponder
        }
        didDrag = false
        if event.clickCount == 2 {
            onReset("pointer")
            restorePriorFirstResponder()
            return
        }
        window?.makeFirstResponder(self)
        interaction.begin(value: value, minimum: minimum, maximum: maximum)
        dragStart = event.locationInWindow
        onPreview(value)
    }

    override func mouseDragged(with event: NSEvent) {
        guard interaction.isActive else { return }
        didDrag = true
        let current = event.locationInWindow
        onPreview(
            interaction.preview(
                translation: ResizeHandleInteraction.physicalTranslation(
                    axis: axis, from: dragStart, to: current, movementSign: movementSign
                )
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard interaction.isActive else { return }
        let current = event.locationInWindow
        let shouldRestorePriorFirstResponder = didDrag
        let previewValue =
            didDrag
            ? interaction.preview(
                translation: ResizeHandleInteraction.physicalTranslation(
                    axis: axis, from: dragStart, to: current, movementSign: movementSign
                )
            ) ?? value
            : value
        _ = interaction.finish()
        if previewValue != value {
            value = previewValue
            onCommit(previewValue, "pointer")
        }
        onPreview(nil)
        didDrag = false
        if shouldRestorePriorFirstResponder {
            restorePriorFirstResponder()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let firstResponder = window?.firstResponder, firstResponder !== self {
            priorFirstResponder = firstResponder
        }
        window?.makeFirstResponder(self)
        NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
        restorePriorFirstResponder()
    }

    override func otherMouseDown(with event: NSEvent) {
        mouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            if interaction.isActive {
                cancelInteraction()
            } else {
                restorePriorFirstResponder()
            }
            return
        }
        guard
            let delta = ResizeHandleInteraction.arrowDelta(
                axis: axis,
                keyCode: event.keyCode,
                shifted: event.modifierFlags.contains(.shift)
            )
        else {
            super.keyDown(with: event)
            return
        }
        let adjusted = ResizeHandleInteraction.value(
            from: value, delta: delta * movementSign, minimum: minimum, maximum: maximum
        )
        guard adjusted != value else { return }
        value = adjusted
        onCommit(adjusted, "keyboard")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, interaction.isActive { cancelInteraction() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .splitter }
    override func accessibilityLabel() -> String? { handleLabel }
    override func accessibilityValue() -> Any? { value }
    override func accessibilityMinValue() -> Any? { minimum }
    override func accessibilityMaxValue() -> Any? { maximum }
    override func accessibilityOrientation() -> NSAccessibilityOrientation {
        axis == .columns ? .vertical : .horizontal
    }

    override func accessibilityPerformIncrement() -> Bool { performAccessibleAdjustment(delta: 16) }
    override func accessibilityPerformDecrement() -> Bool { performAccessibleAdjustment(delta: -16) }

    private var cursor: NSCursor {
        axis == .columns ? .resizeLeftRight : .resizeUpDown
    }

    private var contextMenu: NSMenu {
        let menu = NSMenu(title: "Resize \(handleLabel)")
        menu.addItem(withTitle: "Increase \(handleLabel) Size", action: #selector(increaseFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Decrease \(handleLabel) Size", action: #selector(decreaseFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reset \(handleLabel) Size", action: #selector(resetFromMenu), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func increaseFromMenu() { performMenuAdjustment(delta: 16) }
    @objc private func decreaseFromMenu() { performMenuAdjustment(delta: -16) }
    @objc private func resetFromMenu() { onReset("menu") }

    private func performMenuAdjustment(delta: Double) {
        let adjusted = ResizeHandleInteraction.value(from: value, delta: delta, minimum: minimum, maximum: maximum)
        guard adjusted != value else { return }
        value = adjusted
        onCommit(adjusted, "menu")
    }

    private func performAccessibleAdjustment(delta: Double) -> Bool {
        let adjusted = ResizeHandleInteraction.value(from: value, delta: delta, minimum: minimum, maximum: maximum)
        guard adjusted != value else { return false }
        value = adjusted
        onCommit(adjusted, "accessibility")
        return true
    }

    fileprivate func cancelInteraction() {
        guard interaction.isActive else { return }
        interaction.cancel()
        onCancel()
        onPreview(nil)
        restorePriorFirstResponder()
    }

    private func restorePriorFirstResponder() {
        if let priorFirstResponder,
            priorFirstResponder !== self,
            let window,
            !(priorFirstResponder is NSView) || (priorFirstResponder as? NSView)?.window === window,
            window.makeFirstResponder(priorFirstResponder)
        {
            self.priorFirstResponder = nil
            return
        }
        if let focusTarget,
            let focusView = focusTarget as? NSView,
            let window,
            focusView.window === window
        {
            window.makeFirstResponder(focusTarget)
        }
        self.priorFirstResponder = nil
    }
}
