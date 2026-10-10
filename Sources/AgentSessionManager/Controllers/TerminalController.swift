import AppKit
import Foundation
import SwiftTerm

final class BellCapturingTerminalView: LocalProcessTerminalView {
    var onAttention: ((PaneAttentionEvent) -> Void)?
    var onUserInput: (() -> Void)?
    var onSelectionChanged: ((Bool) -> Void)?
    var telemetryTabName: String = ""
    var telemetryTabUUID: UUID?
    var telemetryPaneName: String = ""
    var telemetryPaneUUID: UUID?
    private var osc777HookInstalled = false
    nonisolated(unsafe) private var keyEventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowMouseReporting = false
        installOsc777AttentionHookIfNeeded()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        allowMouseReporting = false
        installOsc777AttentionHookIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let currentCols = terminal?.cols ?? 0
        guard currentCols >= 2 else {
            super.setFrameSize(newSize)
            return
        }
        let currentWidth = frame.width
        guard currentWidth > 0 else {
            super.setFrameSize(newSize)
            return
        }
        let cellWidth = currentWidth / CGFloat(currentCols)
        let proposedCols = Int(newSize.width / cellWidth)
        if proposedCols < 2 {
            return
        }
        super.setFrameSize(newSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, keyEventMonitor == nil {
            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window?.firstResponder === self else { return event }
                self.onUserInput?()
                return event
            }
        } else if window == nil, let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    deinit {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func bell(source: Terminal) {
        super.bell(source: source)
        let event = PaneAttentionEvent.rawBell
        onAttention?(event)
        Task { @MainActor in
            var attrs: [String: String] = [
                "source": "bell",
                "reason": event.reason,
                "pane.name": self.telemetryPaneName,
                "tab.name": self.telemetryTabName,
            ]
            if let id = self.telemetryPaneUUID { attrs["pane.id"] = id.uuidString }
            if let id = self.telemetryTabUUID { attrs["tab.id"] = id.uuidString }
            TracingService.shared.record("terminal.attention.delivered", attributes: attrs)
        }
    }

    func installOsc777AttentionHookIfNeeded() {
        guard !osc777HookInstalled else { return }
        osc777HookInstalled = true
        getTerminal().registerOscHandler(code: 777) { [weak self] data in
            guard let self else { return }
            guard let text = String(bytes: data, encoding: .utf8) else { return }
            guard let event = PaneAttentionEvent.osc777(text) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onAttention?(event)
                Task { @MainActor in
                    var attrs: [String: String] = [
                        "source": "osc777",
                        "reason": event.reason,
                        "pane.name": self.telemetryPaneName,
                        "tab.name": self.telemetryTabName,
                    ]
                    if let id = self.telemetryPaneUUID { attrs["pane.id"] = id.uuidString }
                    if let id = self.telemetryTabUUID { attrs["tab.id"] = id.uuidString }
                    TracingService.shared.record("terminal.attention.delivered", attributes: attrs)
                }
            }
        }
    }

    override func selectionChanged(source: Terminal) {
        super.selectionChanged(source: source)
        let active = selectionActive
        if Thread.isMainThread {
            onSelectionChanged?(active)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onSelectionChanged?(active)
            }
        }
    }

    @discardableResult
    func copySelectionToPasteboard() -> Bool {
        guard let text = getSelection(), !text.isEmpty else {
            InvariantReporter.shared.violated(
                .terminalClipboardCopyRequiresSelection,
                context: telemetryContext()
            )
            return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        selectNone()
        TracingService.shared.record(
            "terminal.clipboard.copied",
            attributes: telemetryContext().merging(
                ["source": "context_menu", "chars": String(text.count)]
            ) { _, new in new }
        )
        return true
    }

    @discardableResult
    func pasteFromPasteboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return false
        }
        paste(self)
        onUserInput?()
        TracingService.shared.record(
            "terminal.clipboard.pasted",
            attributes: telemetryContext().merging(
                ["source": "context_menu", "chars": String(text.count)]
            ) { _, new in new }
        )
        return true
    }

    private func telemetryContext() -> [String: String] {
        var attrs: [String: String] = [
            "pane.name": telemetryPaneName,
            "tab.name": telemetryTabName,
        ]
        if let id = telemetryPaneUUID { attrs["pane.id"] = id.uuidString }
        if let id = telemetryTabUUID { attrs["tab.id"] = id.uuidString }
        return attrs
    }
}

@Observable
@MainActor
final class TerminalController: NSObject {
    let terminalView: BellCapturingTerminalView
    var processState: ProcessState = .idle
    var hasSelection: Bool = false
    var pendingCommandArgs: [String]?
    var pendingDirectory: String?
    var pendingEnvironment: [String]?
    var pendingShell: String?
    @ObservationIgnored var onAttention: ((PaneAttentionEvent) -> Void)?

    enum ProcessState: Equatable {
        case idle
        case running(pid: Int32)
        case exited(code: Int32?)
    }

    override init() {
        terminalView = BellCapturingTerminalView(frame: .zero)
        super.init()
        terminalView.setAccessibilityElement(true)
        terminalView.setAccessibilityRole(.group)
        terminalView.setAccessibilityLabel("Terminal")
        terminalView.processDelegate = self
        terminalView.onAttention = { [weak self] event in self?.onAttention?(event) }
        terminalView.onSelectionChanged = { [weak self] active in
            guard let self, self.hasSelection != active else { return }
            self.hasSelection = active
        }
    }

    func startProcess() {
        let shell = pendingShell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let commandArgs = pendingCommandArgs {
            let cmd = commandArgs.map { Self.shellQuote($0) }.joined(separator: " ")
            let args = ["-i", "-c", cmd]
            let env = ProcessEnvironment.sanitize(pendingEnvironment ?? [])
            let cwd = pendingDirectory
            terminalView.startProcess(
                executable: shell,
                args: args,
                environment: env,
                currentDirectory: cwd
            )
            recordProcessStarted(executable: shell, args: args, cwd: cwd)
        } else {
            let env = ProcessEnvironment.sanitize(pendingEnvironment ?? [])
            let cwd = pendingDirectory
            terminalView.startProcess(
                executable: shell,
                environment: env,
                currentDirectory: cwd
            )
            recordProcessStarted(executable: shell, args: [], cwd: cwd)
        }
        let pid = terminalView.process.shellPid
        if pid > 0 {
            processState = .running(pid: pid)
        }
    }

    private func recordProcessStarted(executable: String, args: [String], cwd: String?) {
        let tracePaneName = terminalView.telemetryPaneName
        let traceTabName = terminalView.telemetryTabName
        let tracePaneUUID = terminalView.telemetryPaneUUID
        let traceTabUUID = terminalView.telemetryTabUUID
        Task(priority: .utility) { @MainActor in
            var attrs: [String: String] = [
                "executable": executable,
                "args": args.joined(separator: " "),
                "working_directory": cwd ?? "",
                "pane.name": tracePaneName,
                "tab.name": traceTabName,
            ]
            if let id = tracePaneUUID { attrs["pane.id"] = id.uuidString }
            if let id = traceTabUUID { attrs["tab.id"] = id.uuidString }
            TracingService.shared.record("terminal.process.started", attributes: attrs)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var terminalContent: String {
        let terminal = terminalView.terminal
        guard let terminal, terminal.rows > 0, terminal.cols > 0 else { return "" }
        var lines: [String] = []
        for row in 0..<terminal.rows {
            var chars: [Character] = []
            for col in 0..<terminal.cols {
                if let ch = terminal.getCharacter(col: col, row: row) {
                    let safeChar: Character = ch.unicodeScalars.first?.value == 0 ? " " : ch
                    chars.append(safeChar)
                }
            }
            let line = String(chars).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            lines.append(line)
        }
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    func focusTerminal() {
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func terminate() {
        terminalView.terminate()
    }
}

extension TerminalController: LocalProcessTerminalViewDelegate {
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.processState = .exited(code: exitCode)
            var attrs: [String: String] = [
                "exit_code": exitCode.map(String.init) ?? "nil",
                "pane.name": self.terminalView.telemetryPaneName,
                "tab.name": self.terminalView.telemetryTabName,
            ]
            if let id = self.terminalView.telemetryPaneUUID { attrs["pane.id"] = id.uuidString }
            if let id = self.terminalView.telemetryTabUUID { attrs["tab.id"] = id.uuidString }
            TracingService.shared.record("terminal.process.exited", attributes: attrs)
        }
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
