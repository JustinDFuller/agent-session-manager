import AppKit
import XCTest

@testable import AgentSessionManager

final class ResizeShortcutValidationTests: XCTestCase {
    func testResizeActionStepSizesAndLabelsCoverNormalAndLargerActions() {
        for direction in ResizeDirection.allCases {
            let normal = ResizeAction(direction: direction, larger: false)
            let larger = ResizeAction(direction: direction, larger: true)
            XCTAssertEqual(normal.step, 4)
            XCTAssertEqual(normal.label, "Resize \(direction.rawValue.capitalized)")
            XCTAssertEqual(larger.step, 16)
            XCTAssertEqual(larger.label, "Resize \(direction.rawValue.capitalized) (Larger Step)")
        }
    }

    func testResizeBindingDisplayUsesCanonicalModifierOrder() {
        XCTAssertEqual(ResizeKeyBinding(key: "x", modifiers: [.command, .option]).display, "⌘⌥X")
        XCTAssertEqual(
            ResizeKeyBinding(key: "x", modifiers: [.command, .option, .shift, .control]).display,
            "⌘⌥⇧⌃X"
        )
    }

    func testResizeKeyExtractionMapsArrowKeycodesAndCharacterFallback() throws {
        let expected: [(UInt16, String)] = [(123, "←"), (124, "→"), (125, "↓"), (126, "↑")]
        for (keyCode, key) in expected {
            let event = try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [.command, .option],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: key,
                    charactersIgnoringModifiers: key,
                    isARepeat: false,
                    keyCode: keyCode
                )
            )
            XCTAssertEqual(ResizeKeyBinding.key(for: event), key)
        }
        let letter = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .option],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "X",
                charactersIgnoringModifiers: "X",
                isARepeat: false,
                keyCode: 7
            )
        )
        XCTAssertEqual(ResizeKeyBinding.key(for: letter), "x")
    }

    func testResizeActionsRequireAnExactModifierCombination() {
        let action = ResizeAction(direction: .left, larger: false)
        var bindings = PaneResizeShortcutBindings()
        bindings.setBinding(ResizeKeyBinding(key: "x", modifiers: [.command, .option]), for: action)

        XCTAssertEqual(bindings.action(key: "X", modifiers: [.command, .option]), action)
        XCTAssertNil(bindings.action(key: "x", modifiers: .command))
        XCTAssertNil(bindings.action(key: "x", modifiers: [.command, .option, .shift]))
        XCTAssertNil(bindings.action(key: "x", modifiers: [.command, .option, .control]))
    }

    func testResizeBindingRejectsExactAppShortcutConflict() {
        let binding = ResizeKeyBinding(key: "t", modifiers: .command)
        let result = ResizeShortcutValidation.validateResizeBinding(
            binding,
            action: ResizeAction(direction: .left, larger: false),
            bindings: PaneResizeShortcutBindings(),
            appBindings: [binding]
        )

        XCTAssertEqual(result, "That key is already assigned to an app shortcut.")
    }

    func testResizeBindingAllowsSameKeyWithDifferentModifiers() {
        let binding = ResizeKeyBinding(key: "t", modifiers: [.command, .option])
        let result = ResizeShortcutValidation.validateResizeBinding(
            binding,
            action: ResizeAction(direction: .left, larger: false),
            bindings: PaneResizeShortcutBindings(),
            appBindings: ResizeKeyBinding.appBindings()
        )

        XCTAssertNil(result)
    }

    func testResizeBindingRejectsExactResizeConflictOnly() {
        let action = ResizeAction(direction: .left, larger: false)
        let otherAction = ResizeAction(direction: .right, larger: false)
        let binding = ResizeKeyBinding(key: "x", modifiers: [.command, .option])
        var bindings = PaneResizeShortcutBindings()
        bindings.setBinding(binding, for: otherAction)

        let result = ResizeShortcutValidation.validateResizeBinding(
            binding,
            action: action,
            bindings: bindings,
            appBindings: []
        )

        XCTAssertEqual(result, "That key is already assigned to another pane resize shortcut.")
    }

    func testResizeBindingRequiresCommand() {
        let binding = ResizeKeyBinding(key: "x", modifiers: .option)
        let result = ResizeShortcutValidation.validateResizeBinding(
            binding,
            action: ResizeAction(direction: .left, larger: false),
            bindings: PaneResizeShortcutBindings(),
            appBindings: []
        )

        XCTAssertEqual(result, "Use one letter, number, or arrow key with Command.")
    }

    func testAppShortcutRejectsExactResizeConflict() {
        let binding = ResizeKeyBinding(key: "x", modifiers: [.command, .option])
        var bindings = PaneResizeShortcutBindings()
        bindings.setBinding(binding, for: ResizeAction(direction: .left, larger: false))

        XCTAssertEqual(
            ResizeShortcutValidation.validateAppBinding(binding, resizeBindings: bindings),
            "This key is assigned to a pane resize shortcut."
        )
    }

    func testAppShortcutAllowsSameKeyWithDifferentModifiers() {
        let resizeBinding = ResizeKeyBinding(key: "x", modifiers: [.command, .option])
        let appBinding = ResizeKeyBinding(key: "x", modifiers: .command)
        var bindings = PaneResizeShortcutBindings()
        bindings.setBinding(resizeBinding, for: ResizeAction(direction: .left, larger: false))

        XCTAssertNil(ResizeShortcutValidation.validateAppBinding(appBinding, resizeBindings: bindings))
    }
}
