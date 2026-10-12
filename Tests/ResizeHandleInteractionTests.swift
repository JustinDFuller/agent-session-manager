import AppKit
import XCTest

@testable import AgentSessionManager

final class ResizeHandleInteractionTests: XCTestCase {
    func testDragPreviewUsesSnapshotAndStopsAtBounds() {
        var interaction = ResizeHandleInteraction()
        interaction.begin(value: 40, minimum: 24, maximum: 72)

        XCTAssertEqual(interaction.preview(translation: 12), 52)
        XCTAssertEqual(interaction.preview(translation: 64), 72)
        XCTAssertEqual(interaction.preview(translation: -24), 24)
        XCTAssertEqual(interaction.finish(), 40)
        XCTAssertFalse(interaction.isActive)
    }

    func testDragSnapshotIsClampedToLimits() {
        var interaction = ResizeHandleInteraction()
        interaction.begin(value: 5, minimum: 24, maximum: 72)

        XCTAssertEqual(interaction.preview(translation: 4), 28)
        XCTAssertEqual(interaction.finish(), 24)
    }

    func testCancelDropsUncommittedDragSnapshot() {
        var interaction = ResizeHandleInteraction()
        interaction.begin(value: 40, minimum: 24, maximum: 72)
        interaction.cancel()

        XCTAssertNil(interaction.preview(translation: 12))
        XCTAssertNil(interaction.finish())
        XCTAssertFalse(interaction.isActive)
    }

    func testPhysicalTranslationFollowsColumnAndRowDirections() {
        XCTAssertEqual(
            ResizeHandleInteraction.physicalTranslation(
                axis: .columns,
                from: CGPoint(x: 10, y: 20),
                to: CGPoint(x: 18, y: 28)
            ),
            8
        )
        XCTAssertEqual(
            ResizeHandleInteraction.physicalTranslation(
                axis: .rows,
                from: CGPoint(x: 10, y: 20),
                to: CGPoint(x: 18, y: 28)
            ),
            -8
        )
        XCTAssertEqual(
            ResizeHandleInteraction.physicalTranslation(
                axis: .columns,
                from: CGPoint(x: 10, y: 20),
                to: CGPoint(x: 2, y: 28),
                movementSign: -1
            ),
            8
        )
    }

    func testArrowKeysUseFourAndSixteenPointPhysicalSteps() {
        XCTAssertEqual(ResizeHandleInteraction.arrowDelta(axis: .columns, keyCode: 123, shifted: false), -4)
        XCTAssertEqual(ResizeHandleInteraction.arrowDelta(axis: .columns, keyCode: 124, shifted: true), 16)
        XCTAssertEqual(ResizeHandleInteraction.arrowDelta(axis: .rows, keyCode: 126, shifted: false), -4)
        XCTAssertEqual(ResizeHandleInteraction.arrowDelta(axis: .rows, keyCode: 125, shifted: true), 16)
        XCTAssertNil(ResizeHandleInteraction.arrowDelta(axis: .columns, keyCode: 125, shifted: false))
        XCTAssertNil(ResizeHandleInteraction.arrowDelta(axis: .rows, keyCode: 123, shifted: false))
    }

    func testAdjustmentClampsMenuAndAccessibleStepsToBounds() {
        XCTAssertEqual(
            ResizeHandleInteraction.value(from: 40, delta: 16, minimum: 24, maximum: 48),
            48
        )
        XCTAssertEqual(
            ResizeHandleInteraction.value(from: 40, delta: -16, minimum: 32, maximum: 72),
            32
        )
    }

    func testResizeKeyRoutesOnlyFromTheFocusedMainTerminalWithoutASheet() {
        let bindings = PaneResizeShortcutBindings()
        let action = ResizeCommandRouting.action(
            key: "→",
            modifiers: [.command, .option],
            bindings: bindings,
            isMainWindow: true,
            terminalHasFocus: true,
            hasAttachedSheet: false
        )

        XCTAssertEqual(action, ResizeAction(direction: .right, larger: false))
    }

    func testResizeKeyRemainsAvailableOutsideTheFocusedMainTerminal() {
        let bindings = PaneResizeShortcutBindings()
        XCTAssertNil(
            ResizeCommandRouting.action(
                key: "→",
                modifiers: [.command, .option],
                bindings: bindings,
                isMainWindow: false,
                terminalHasFocus: true,
                hasAttachedSheet: false
            )
        )
        XCTAssertNil(
            ResizeCommandRouting.action(
                key: "→",
                modifiers: [.command, .option],
                bindings: bindings,
                isMainWindow: true,
                terminalHasFocus: false,
                hasAttachedSheet: false
            )
        )
        XCTAssertNil(
            ResizeCommandRouting.action(
                key: "→",
                modifiers: [.command, .option],
                bindings: bindings,
                isMainWindow: true,
                terminalHasFocus: true,
                hasAttachedSheet: true
            )
        )
    }

    func testSingleTrackResizeBindingStillProducesAConsumableCommand() {
        let action = ResizeCommandRouting.action(
            key: "←",
            modifiers: [.command, .option],
            bindings: PaneResizeShortcutBindings(),
            isMainWindow: true,
            terminalHasFocus: true,
            hasAttachedSheet: false
        )

        XCTAssertEqual(action, ResizeAction(direction: .left, larger: false))
    }
}

@MainActor
final class ResizeHandleFocusTests: XCTestCase {
    func testInterruptedDragCancelsOldCallbacksAndRestoresTheNewTerminal() throws {
        let firstController = TerminalController()
        let secondController = TerminalController()
        let firstTerminal = firstController.terminalView
        let secondTerminal = secondController.terminalView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        firstTerminal.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        secondTerminal.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        window.contentView?.addSubview(firstTerminal)
        window.contentView?.addSubview(secondTerminal)
        let handle = ResizeHandleNativeView(frame: NSRect(x: 640, y: 0, width: 8, height: 480))
        var oldPreviewValues: [Double?] = []
        var newPreviewValues: [Double?] = []
        var oldCancelCount = 0
        var newCancelCount = 0
        var commits: [Double] = []
        handle.configure(
            axis: .columns, identifier: "focus-interrupted-drag", label: "Resize", value: 320,
            minimum: 160, maximum: 640, focusTarget: firstTerminal, movementSign: 1,
            highlighted: false, cancellationKey: "first-pane",
            onPreview: { oldPreviewValues.append($0) },
            onCommit: { value, _ in commits.append(value) }, onReset: { _ in },
            onCancel: { oldCancelCount += 1 }
        )
        window.contentView?.addSubview(handle)
        XCTAssertTrue(window.makeFirstResponder(firstTerminal))
        let down = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: 644, y: 240), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )
        )
        let dragged = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDragged, location: NSPoint(x: 654, y: 240), modifierFlags: [],
                timestamp: 0.5, windowNumber: window.windowNumber, context: nil,
                eventNumber: 2, clickCount: 1, pressure: 1
            )
        )
        handle.mouseDown(with: down)
        handle.mouseDragged(with: dragged)

        handle.configure(
            axis: .columns, identifier: "focus-interrupted-drag", label: "Resize", value: 320,
            minimum: 160, maximum: 640, focusTarget: secondTerminal, movementSign: 1,
            highlighted: false, cancellationKey: "second-pane",
            onPreview: { newPreviewValues.append($0) },
            onCommit: { value, _ in commits.append(value) }, onReset: { _ in },
            onCancel: { newCancelCount += 1 }
        )

        XCTAssertFalse(handle.interaction.isActive)
        XCTAssertEqual(oldCancelCount, 1)
        XCTAssertEqual(newCancelCount, 0)
        XCTAssertEqual(oldPreviewValues.count, 3)
        XCTAssertEqual(oldPreviewValues.last, .some(nil))
        XCTAssertTrue(newPreviewValues.isEmpty)
        XCTAssertTrue(commits.isEmpty)
        XCTAssertTrue(window.firstResponder === secondTerminal)
    }

    func testDoubleClickResetRestoresCurrentTerminalAfterEarlierKeyboardFocus() throws {
        let firstController = TerminalController()
        let secondController = TerminalController()
        let firstTerminal = firstController.terminalView
        let secondTerminal = secondController.terminalView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.contentView?.addSubview(firstTerminal)
        window.contentView?.addSubview(secondTerminal)
        let handle = ResizeHandleNativeView(frame: NSRect(x: 640, y: 0, width: 8, height: 480))
        var resetSources: [String] = []
        handle.configure(
            axis: .columns, identifier: "focus-reset", label: "Resize", value: 320,
            minimum: 160, maximum: 640, focusTarget: secondTerminal, movementSign: 1,
            highlighted: false, cancellationKey: "stable", onPreview: { _ in },
            onCommit: { _, _ in }, onReset: { resetSources.append($0) }, onCancel: {}
        )
        window.contentView?.addSubview(handle)
        XCTAssertTrue(window.makeFirstResponder(firstTerminal))
        XCTAssertTrue(handle.becomeFirstResponder())
        XCTAssertTrue(window.makeFirstResponder(handle))
        XCTAssertTrue(window.makeFirstResponder(secondTerminal))
        XCTAssertTrue(window.makeFirstResponder(handle))
        let down = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: 644, y: 240), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 2, pressure: 1
            )
        )
        handle.mouseDown(with: down)
        XCTAssertEqual(resetSources, ["pointer"])
        _ = handle.perform(NSSelectorFromString("resetFromMenu"))
        XCTAssertEqual(resetSources, ["pointer", "menu"])
        XCTAssertTrue(window.firstResponder === secondTerminal)
    }

    func testDragRestoresTerminalWhenAppKitFocusedHandleBeforeMouseDown() throws {
        let controller = TerminalController()
        let terminal = controller.terminalView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        terminal.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        window.contentView?.addSubview(terminal)
        let handle = ResizeHandleNativeView(frame: NSRect(x: 640, y: 0, width: 8, height: 480))
        handle.configure(
            axis: .columns, identifier: "focus-resize", label: "Resize", value: 320,
            minimum: 160, maximum: 640, focusTarget: terminal, movementSign: 1, highlighted: false,
            cancellationKey: "stable", onPreview: { _ in }, onCommit: { _, _ in },
            onReset: { _ in }, onCancel: {}
        )
        window.contentView?.addSubview(handle)
        XCTAssertTrue(window.makeFirstResponder(terminal))
        XCTAssertTrue(window.makeFirstResponder(handle))
        let down = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: 644, y: 240), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )
        )
        let dragged = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDragged, location: NSPoint(x: 668, y: 240), modifierFlags: [],
                timestamp: 0.5, windowNumber: window.windowNumber, context: nil,
                eventNumber: 2, clickCount: 1, pressure: 1
            )
        )
        let up = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp, location: dragged.locationInWindow, modifierFlags: [],
                timestamp: 1, windowNumber: window.windowNumber, context: nil,
                eventNumber: 3, clickCount: 1, pressure: 0
            )
        )
        handle.mouseDown(with: down)
        XCTAssertTrue(window.firstResponder === handle)
        handle.mouseDragged(with: dragged)
        handle.mouseUp(with: up)
        XCTAssertTrue(window.firstResponder === terminal)
    }

    func testClickFocusesHandleForArrowAdjustmentAndEscapeRestoresTerminal() throws {
        let controller = TerminalController()
        let terminal = controller.terminalView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        terminal.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        window.contentView?.addSubview(terminal)
        let handle = ResizeHandleNativeView(frame: NSRect(x: 640, y: 0, width: 8, height: 480))
        var committedValue: Double?
        handle.configure(
            axis: .rows, identifier: "focus-click", label: "Resize", value: 40,
            minimum: 24, maximum: 72, focusTarget: terminal, movementSign: 1,
            highlighted: false, cancellationKey: "stable", onPreview: { _ in },
            onCommit: { value, source in
                XCTAssertEqual(source, "keyboard")
                committedValue = value
            }, onReset: { _ in }, onCancel: {}
        )
        window.contentView?.addSubview(handle)
        XCTAssertTrue(window.makeFirstResponder(terminal))
        let down = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: 644, y: 240), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )
        )
        let up = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp, location: down.locationInWindow, modifierFlags: [],
                timestamp: 1, windowNumber: window.windowNumber, context: nil,
                eventNumber: 2, clickCount: 1, pressure: 0
            )
        )
        handle.mouseDown(with: down)
        handle.mouseUp(with: up)
        XCTAssertTrue(window.firstResponder === handle)

        let arrow = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 2,
                windowNumber: window.windowNumber, context: nil,
                characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
                isARepeat: false, keyCode: 125
            )
        )
        window.sendEvent(arrow)
        XCTAssertEqual(committedValue, 44)
        XCTAssertTrue(window.firstResponder === handle)

        let escape = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 3,
                windowNumber: window.windowNumber, context: nil,
                characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false, keyCode: 53
            )
        )
        window.sendEvent(escape)
        XCTAssertTrue(window.firstResponder === terminal)
    }

    func testClickWithMouseUpDriftRetainsHandleFocusWithoutResizing() throws {
        let controller = TerminalController()
        let terminal = controller.terminalView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        terminal.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        window.contentView?.addSubview(terminal)
        let handle = ResizeHandleNativeView(frame: NSRect(x: 640, y: 0, width: 8, height: 480))
        var previews: [Double?] = []
        var committedValues: [Double] = []
        handle.configure(
            axis: .columns, identifier: "focus-click-drift", label: "Resize", value: 40,
            minimum: 24, maximum: 72, focusTarget: terminal, movementSign: 1, highlighted: false,
            cancellationKey: "stable", onPreview: { previews.append($0) },
            onCommit: { value, _ in committedValues.append(value) }, onReset: { _ in }, onCancel: {}
        )
        window.contentView?.addSubview(handle)
        XCTAssertTrue(window.makeFirstResponder(terminal))
        let down = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: 644, y: 240), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )
        )
        let up = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp, location: NSPoint(x: 644.25, y: 240), modifierFlags: [],
                timestamp: 1, windowNumber: window.windowNumber, context: nil,
                eventNumber: 2, clickCount: 1, pressure: 0
            )
        )

        handle.mouseDown(with: down)
        handle.mouseUp(with: up)

        XCTAssertEqual(previews.count, 2)
        XCTAssertEqual(previews[0], 40)
        XCTAssertNil(previews[1])
        XCTAssertTrue(committedValues.isEmpty)
        XCTAssertTrue(window.firstResponder === handle)
    }
}
