import AppKit
import SwiftTerm
import XCTest

@testable import AgentSessionManager

@MainActor
final class TerminalControlReturnTests: XCTestCase {
    private final class RecordingDelegate: TerminalViewDelegate {
        var sent: [[UInt8]] = []

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(Array(data)) }
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    private final class SpyResponder: NSResponder {
        var contextMenuEvents = 0

        override func contextMenuKeyDown(_ event: NSEvent) {
            contextMenuEvents += 1
        }
    }

    private struct KeyCase {
        let name: String
        let keyCode: UInt16
        let characters: String
        let modifiers: NSEvent.ModifierFlags
    }

    private func makeView() -> (BellCapturingTerminalView, RecordingDelegate) {
        let view = BellCapturingTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let delegate = RecordingDelegate()
        view.terminalDelegate = delegate
        recordedDelegates.append(delegate)
        return (view, delegate)
    }

    private var recordedDelegates: [RecordingDelegate] = []

    private func keyDownEvent(
        keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 1,
                windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            )
        )
    }

    func testControlReturnWithKeyboardReportingSendsControlModifiedReturn() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Requires macOS 15") }
        let (view, delegate) = makeView()
        view.feed(text: "\u{1b}[>1u")
        XCTAssertFalse(view.terminal.keyboardEnhancementFlags.isEmpty)
        let event = try keyDownEvent(keyCode: 36, characters: "\r", modifiers: .control)

        view.contextMenuKeyDown(event)

        XCTAssertEqual(delegate.sent, [[0x1b, 0x5b, 0x31, 0x33, 0x3b, 0x35, 0x75]])
    }

    func testControlReturnWithoutKeyboardReportingSendsCarriageReturn() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Requires macOS 15") }
        let (view, delegate) = makeView()
        XCTAssertTrue(view.terminal.keyboardEnhancementFlags.isEmpty)
        let event = try keyDownEvent(keyCode: 36, characters: "\r", modifiers: .control)

        view.contextMenuKeyDown(event)

        XCTAssertEqual(delegate.sent, [[0x0d]])
    }

    func testControlReturnIgnoresCapsLockAndFunctionBits() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Requires macOS 15") }
        let (view, delegate) = makeView()
        let event = try keyDownEvent(
            keyCode: 36, characters: "\r", modifiers: [.control, .capsLock, .function])

        view.contextMenuKeyDown(event)

        XCTAssertEqual(delegate.sent, [[0x0d]])
    }

    func testControlReturnWithoutKeyboardReportingClearsSelection() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Requires macOS 15") }
        let (view, _) = makeView()
        view.feed(text: "hello world\n")
        view.selectAll()
        XCTAssertTrue(view.selectionActive)
        let event = try keyDownEvent(keyCode: 36, characters: "\r", modifiers: .control)

        view.contextMenuKeyDown(event)

        XCTAssertFalse(view.selectionActive)
    }

    func testContextMenuKeyDownForOtherKeysSendsNothing() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Requires macOS 15") }
        let cases = [
            KeyCase(name: "Return", keyCode: 36, characters: "\r", modifiers: []),
            KeyCase(name: "Shift-Return", keyCode: 36, characters: "\r", modifiers: .shift),
            KeyCase(
                name: "Control-Shift-Return", keyCode: 36, characters: "\r",
                modifiers: [.control, .shift]),
            KeyCase(
                name: "Control-Option-Return", keyCode: 36, characters: "\r",
                modifiers: [.control, .option]),
            KeyCase(name: "Control-Space", keyCode: 49, characters: " ", modifiers: .control),
            KeyCase(name: "Control-A", keyCode: 0, characters: "a", modifiers: .control),
        ]
        for withFlags in [false, true] {
            for keyCase in cases {
                let (view, delegate) = makeView()
                if withFlags { view.feed(text: "\u{1b}[>1u") }
                let event = try keyDownEvent(
                    keyCode: keyCase.keyCode, characters: keyCase.characters,
                    modifiers: keyCase.modifiers)

                view.contextMenuKeyDown(event)

                XCTAssertEqual(
                    delegate.sent, [], "\(keyCase.name) must reach super and send nothing (flags: \(withFlags))")
            }
        }
    }

    func testControlReturnDoesNotReachTheResponderChainButOtherKeysDo() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Requires macOS 15") }
        let cases = [
            KeyCase(name: "Control-Return", keyCode: 36, characters: "\r", modifiers: .control),
            KeyCase(name: "Return", keyCode: 36, characters: "\r", modifiers: []),
            KeyCase(
                name: "Control-Shift-Return", keyCode: 36, characters: "\r",
                modifiers: [.control, .shift]),
            KeyCase(name: "Control-A", keyCode: 0, characters: "a", modifiers: .control),
        ]
        for withFlags in [false, true] {
            for keyCase in cases {
                let (view, _) = makeView()
                let spy = SpyResponder()
                view.nextResponder = spy
                if withFlags { view.feed(text: "\u{1b}[>1u") }
                let event = try keyDownEvent(
                    keyCode: keyCase.keyCode, characters: keyCase.characters,
                    modifiers: keyCase.modifiers)

                view.contextMenuKeyDown(event)

                let expected = keyCase.name == "Control-Return" ? 0 : 1
                XCTAssertEqual(
                    spy.contextMenuEvents, expected,
                    "\(keyCase.name) responder-chain delivery (flags: \(withFlags))")
            }
        }
    }
}
