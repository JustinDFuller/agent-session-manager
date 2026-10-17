import AppKit
import SwiftUI

struct PaneView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var appSettings
    let pane: Pane
    let isFocused: Bool
    let canFocus: Bool
    let onClosePane: (Pane) -> Void
    let onRefreshPane: (Pane) -> Void
    let onViewPaneSettings: (Pane) -> Void
    @State private var scrollbackEditor: PaneScrollbackPresentation?
    @State private var pendingScrollback: ScrollbackLimit?
    @State private var showsScrollbackReductionWarning = false
    @State private var naturalStatusHeight = 24.0
    @State private var statusPreviewHeight: Double?
    @State private var paneHeight = 0.0
    @State private var paneWidth = 0.0
    @State private var measuredHeaderHeight = 28.0

    var body: some View {
        @Bindable var appState = appState
        let isActive = appState.activePaneID == pane.id
        ZStack {
            VStack(spacing: 0) {
                paneHeader
                Divider()
                terminalBody
                statusLine
            }

            if pane.terminalController != nil, case .failed(let error) = pane.setupState {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Button("Dismiss") { pane.setupState = nil }
                        .buttonStyle(.bordered)
                }
                .padding(16)
                .background(Theme.overlayMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                .accessibilityIdentifier("pane-refresh-error-\(pane.name)")
            }
            if case .exited(let code) = pane.terminalController?.processState,
                appSettings.exitBehavior == .prompt
            {
                VStack(spacing: 12) {
                    Text("Process exited\(code.map { " (code \($0))" } ?? "")")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Button("Restart") { pane.tab?.restartPane(pane, appSettings: appSettings) }
                        Button("Open Shell") { pane.tab?.openShellInPane(pane) }
                        Button("Close") { onClosePane(pane) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(Theme.overlayMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                .accessibilityIdentifier("pane-exit-prompt-\(pane.name)")
            }

            if let recovery = pane.codexContinuationRecovery {
                VStack(spacing: 12) {
                    Text(
                        recovery == .identityNotRecorded
                            ? "Codex has not reported a conversation to continue."
                            : "The saved Codex conversation is unavailable."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Button("Retry") {
                            pane.tab?.refreshPane(pane)
                        }
                        .accessibilityIdentifier("codex-continuation-retry")
                        Button("Start New Conversation") {
                            pane.tab?.refreshPane(
                                pane,
                                extraArgs: pane.extraArgs,
                                harness: .codex,
                                extraEnvVars: pane.extraEnvVars,
                                profileID: .some(pane.profileID),
                                appSettings: appSettings)
                        }
                        .accessibilityIdentifier("codex-continuation-start-new")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(Theme.overlayMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                .accessibilityIdentifier("codex-continuation-recovery")
            }

            if let notice = pane.codexContinuationNotice {
                VStack(spacing: 8) {
                    Text(notice)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Button("Dismiss") { pane.codexContinuationNotice = nil }
                        .buttonStyle(.bordered)
                }
                .padding(16)
                .background(Theme.overlayMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                .accessibilityIdentifier("codex-continuation-notice")
            }
        }
        .background(Theme.paneBackground)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: LayoutMeasurementKey.self,
                    value: [
                        "pane-height-\(pane.id.uuidString)": geometry.size.height,
                        "pane-width-\(pane.id.uuidString)": geometry.size.width,
                    ]
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isActive ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.1),
                    lineWidth: isActive ? 3 : 1
                )
        )
        .onChange(of: pane.terminalController?.processState) { _, newState in
            guard case .exited = newState else { return }
            if pane.harness == .codex { pane.statusLineMonitor?.codexProcessExited() }
            switch appSettings.exitBehavior {
            case .prompt:
                break
            case .autoShell:
                pane.tab?.openShellInPane(pane)
            case .close:
                onClosePane(pane)
            }
        }
        .contextMenu {
            Button("Copy") {
                pane.terminalController?.terminalView.copySelectionToPasteboard()
            }
            .disabled(!canCopy)
            Button("Paste") {
                appState.setActivePane(id: pane.id)
                pane.terminalController?.terminalView.pasteFromPasteboard()
            }
            Divider()
            if isFocused {
                Button("Show All Panes") {
                    showAllPanes(reason: "context_menu")
                }
                Divider()
            } else if canFocus {
                Button("Focus This Pane") {
                    focusPane(reason: "context_menu")
                }
                Divider()
            }
            Button("Close This Pane") {
                onClosePane(pane)
            }
            if pane.harness != .shell {
                Button("Refresh Pane\u{2026}") {
                    onRefreshPane(pane)
                }
            }
            Button("View Pane Settings\u{2026}") {
                onViewPaneSettings(pane)
            }
            Button("Create Pane") {
                NotificationCenter.default.post(name: .newPane, object: nil)
            }
            Button("Open Shell Here") {
                pane.tab?.openShellPane(activePane: pane, appState: appState, appSettings: appSettings)
            }
            if pane.statusLineHeight != nil {
                Button("Reset Status Height") {
                    let before = effectiveStatusHeight
                    pane.statusLineHeight = nil
                    LayoutResizeTelemetry.record(
                        event: "reset", section: "status", axis: .rows, source: "context_menu",
                        before: before,
                        after: min(naturalStatusHeight, effectiveMaximumStatusHeight),
                        result: "success",
                        tab: pane.tab,
                        pane: pane
                    )
                    LayoutResizeTelemetry.saveSession(
                        appState: appState, appSettings: appSettings, tab: pane.tab, pane: pane, axis: .rows,
                        source: "context_menu"
                    )
                }
                .accessibilityIdentifier("pane-reset-status-height-\(pane.id.uuidString)")
            }
            if let pr = pane.statusLineMonitor?.currentData?.pr, let url = URL(string: pr.url) {
                Button("Go to Pull Request") {
                    NSWorkspace.shared.open(url)
                }
            }
            if appSettings.isPriorityNotificationsEnabled {
                Toggle(
                    "Priority Pane",
                    isOn: Binding(
                        get: { pane.isPriority },
                        set: { newValue in
                            pane.isPriority = newValue
                            SessionPersistence.save(appState: appState)
                        }
                    )
                )
            }
            Menu("Scrollback History") {
                Button {
                    requestScrollbackChange(nil)
                } label: {
                    if pane.scrollbackOverride == nil {
                        Label(
                            "Use Global Default (\(appSettings.defaultScrollback.resolvedLines.formatted()) lines)",
                            systemImage: "checkmark"
                        )
                    } else {
                        Text("Use Global Default (\(appSettings.defaultScrollback.resolvedLines.formatted()) lines)")
                    }
                }
                .accessibilityIdentifier("pane-scrollback-use-global")
                Divider()
                ForEach([1_000, 5_000, 10_000], id: \.self) { lines in
                    Button {
                        requestScrollbackChange(.finite(lines))
                    } label: {
                        if pane.scrollbackOverride == .finite(lines) {
                            Label("\(lines.formatted()) Lines", systemImage: "checkmark")
                        } else {
                            Text("\(lines.formatted()) Lines")
                        }
                    }
                }
                Button {
                    requestScrollbackChange(.unlimited)
                } label: {
                    if pane.scrollbackOverride == .unlimited {
                        Label("Unlimited (50,000-line cap)", systemImage: "checkmark")
                    } else {
                        Text("Unlimited (50,000-line cap)")
                    }
                }
                Divider()
                Button("Custom\u{2026}") {
                    scrollbackEditor = PaneScrollbackPresentation(
                        limit: pane.scrollbackOverride ?? .finite(appSettings.defaultScrollback.resolvedLines)
                    )
                }
            }
        }
        .sheet(item: $scrollbackEditor) { presentation in
            PaneScrollbackEditorSheet(value: presentation.limit, inheritedValue: appSettings.defaultScrollback) {
                requestScrollbackChange($0)
            }
        }
        .alert(
            "Reduce Scrollback History?",
            isPresented: $showsScrollbackReductionWarning
        ) {
            Button("Reduce History", role: .destructive) {
                applyScrollbackChange(pendingScrollback)
                pendingScrollback = nil
            }
            Button("Cancel", role: .cancel) {
                pendingScrollback = nil
            }
        } message: {
            Text("Oldest retained terminal lines are discarded immediately and cannot be recovered.")
        }
        .onTapGesture {
            appState.setActivePane(id: pane.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentSessionManagerPRTrackingSettingChanged)) { _ in
            if pane.harness == .claude {
                pane.statusLineMonitor?.writeSettingsFile()
            }
        }
        .onPreferenceChange(LayoutMeasurementKey.self) { values in
            if let height = values["pane-height-\(pane.id.uuidString)"], height.isFinite, height > 0 {
                paneHeight = height
            }
            if let width = values["pane-width-\(pane.id.uuidString)"], width.isFinite, width > 0 {
                paneWidth = width
            }
            if let height = values["header-\(pane.id.uuidString)"], height.isFinite, height > 0 {
                measuredHeaderHeight = height
            }
            if let height = values["status-content-\(pane.id.uuidString)"], height.isFinite, height > 0 {
                naturalStatusHeight = height
            }
        }
        .preference(
            key: LayoutMeasurementKey.self,
            value: ["status-min-\(pane.id.uuidString)": statusHasContent ? 32 : 0]
        )
        .accessibilityElement(children: .contain)
    }

    private func requestScrollbackChange(_ override: ScrollbackLimit?) {
        let currentLines = (pane.scrollbackOverride ?? appSettings.defaultScrollback).resolvedLines
        let requestedLines = (override ?? appSettings.defaultScrollback).resolvedLines
        if requestedLines < currentLines {
            pendingScrollback = override
            showsScrollbackReductionWarning = true
        } else {
            applyScrollbackChange(override)
        }
    }

    private func applyScrollbackChange(_ override: ScrollbackLimit?) {
        pane.scrollbackOverride = override
        SessionPersistence.save(appState: appState)
    }

    private var paneHeader: some View {
        return HStack(spacing: 0) {
            paneHeaderLabel

            if isFocused {
                Button {
                    showAllPanes(reason: "header_button")
                } label: {
                    Label("Show All Panes", systemImage: "rectangle.split.2x2")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Show all panes")
                .accessibilityIdentifier("pane-show-all-\(pane.name)")
                .accessibilityLabel("Show all panes")
                .padding(.trailing, 6)
            }

            Button {
                appState.clearNotification(paneID: pane.id)
                onClosePane(pane)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .accessibilityIdentifier("pane-close-\(pane.name)")
            .accessibilityLabel("close-\(pane.name)")
        }
        .background(Theme.windowBackground)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: LayoutMeasurementKey.self,
                    value: ["header-\(pane.id.uuidString)": geometry.size.height]
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane-header-\(pane.name)")
    }

    @ViewBuilder
    private var paneHeaderLabel: some View {
        let pendingNotification = appState.notifications.first { $0.paneID == pane.id }
        let label = HStack(spacing: 6) {
            let hasNotification = pendingNotification != nil
            let activityState =
                pane.uiTestActivityStateOverride
                ?? paneActivityState(
                    processState: pane.terminalController?.processState,
                    isWorking: (pane.statusLineMonitor?.isClaudeWorking ?? false)
                        || (pane.statusLineMonitor?.isCursorWorking ?? false)
                        || (pane.statusLineMonitor?.isOpenCodeWorking ?? false)
                        || (pane.statusLineMonitor?.isCodexWorking ?? false),
                    isStopped: (pane.statusLineMonitor?.isClaudeStopped ?? false)
                        || (pane.statusLineMonitor?.isCursorStopped ?? false)
                        || (pane.statusLineMonitor?.isCodexStopped ?? false),
                    sessionState: pane.statusLineMonitor?.currentData?.sessionStatus?.state,
                    hasNotification: hasNotification
                )
            ActivityIndicatorView(
                state: activityState,
                enabled: appSettings.paneActivityIndicatorsEnabled,
                prefix: "pane",
                name: pane.name,
                isPriority: pendingNotification?.isPriority ?? false
            )

            Text(pane.name)
                .accessibilityIdentifier("pane-name-\(pane.name)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if isFocused {
                showAllPanes(reason: "header_double_click")
            } else if canFocus {
                focusPane(reason: "header_double_click")
            }
        }

        if isFocused {
            label
        } else {
            label
                .onHover { isHovering in
                    if isHovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                }
                .draggable(pane.id.uuidString) {
                    Text(pane.name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.overlayMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
        }
    }

    var canCopy: Bool {
        pane.terminalController?.hasSelection ?? false
    }

    private func focusPane(reason: String) {
        appState.setActivePane(id: pane.id)
        pane.tab?.setFocusedPane(id: pane.id, reason: reason)
    }

    private func showAllPanes(reason: String) {
        pane.tab?.setFocusedPane(id: nil, reason: reason)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let monitor = pane.statusLineMonitor, statusHasContent {
            ResizeHandle(
                axis: .rows,
                identifier: "pane-status-resize-\(pane.id.uuidString)",
                label: "Resize status line for \(pane.name)",
                value: statusPreviewHeight ?? effectiveStatusHeight,
                minimum: 24,
                maximum: effectiveMaximumStatusHeight,
                focusTarget: appState.activePane?.terminalController?.terminalView,
                movementSign: -1,
                cancellationKey: statusResizeCancellationKey,
                onPreview: { statusPreviewHeight = $0 },
                onCommit: { height, source in
                    let before = effectiveStatusHeight
                    pane.statusLineHeight = height
                    statusPreviewHeight = nil
                    LayoutResizeTelemetry.record(
                        event: "completed", section: "status", axis: .rows, source: source,
                        before: before, after: height, result: "success", tab: pane.tab, pane: pane
                    )
                    LayoutResizeTelemetry.saveSession(
                        appState: appState, appSettings: appSettings, tab: pane.tab, pane: pane, axis: .rows,
                        source: source
                    )
                },
                onReset: { source in
                    let before = effectiveStatusHeight
                    pane.statusLineHeight = nil
                    statusPreviewHeight = nil
                    LayoutResizeTelemetry.record(
                        event: "reset", section: "status", axis: .rows, source: source,
                        before: before,
                        after: min(naturalStatusHeight, effectiveMaximumStatusHeight),
                        result: "success",
                        tab: pane.tab,
                        pane: pane
                    )
                    LayoutResizeTelemetry.saveSession(
                        appState: appState, appSettings: appSettings, tab: pane.tab, pane: pane, axis: .rows,
                        source: source
                    )
                },
                onCancel: {
                    statusPreviewHeight = nil
                    LayoutResizeTelemetry.record(
                        event: "canceled", section: "status", axis: .rows, source: "pointer",
                        before: effectiveStatusHeight,
                        after: effectiveStatusHeight,
                        result: "canceled", tab: pane.tab, pane: pane
                    )
                }
            )
            .frame(height: 8)
            let config = resolvedStatusLineConfig
            StatusLineView(
                monitor: monitor,
                config: config,
                paneID: pane.id,
                viewportHeight: statusPreviewHeight ?? effectiveStatusHeight,
                viewportWidth: paneWidth,
                profileName: resolvedProfileName
            )
        }
    }

    private var statusHasContent: Bool {
        resolvedStatusLineConfig.rows.contains { row in
            row.items.contains { resolvedStatusLineConfig.supports($0, on: pane.harness) }
        }
    }

    private var effectiveMaximumStatusHeight: Double {
        PaneGridMetrics.maximumStatusHeight(paneHeight: paneHeight, headerHeight: measuredHeaderHeight)
    }

    private var statusResizeCancellationKey: String {
        let topology = pane.tab?.panes.map { $0.id.uuidString }.joined(separator: ",") ?? ""
        return
            "\(appState.activeTabID?.uuidString ?? "")-\(pane.tab?.id.uuidString ?? "")-\(topology)-\(pane.tab?.focusedPaneID?.uuidString ?? "all")-\(appState.activePaneID?.uuidString ?? "none")-\(paneWidth)x\(paneHeight)-\(measuredHeaderHeight)"
    }

    private var effectiveStatusHeight: Double {
        PaneGridMetrics.effectiveStatusHeight(
            preferredHeight: pane.statusLineHeight,
            naturalHeight: naturalStatusHeight,
            paneHeight: paneHeight,
            headerHeight: measuredHeaderHeight
        )
    }

    private var resolvedStatusLineConfig: StatusLineConfig {
        if let profileID = pane.profileID,
            let profile = appSettings.profiles.first(where: { $0.id == profileID })
        {
            return profile.resolvedStatusLineConfig(inheriting: appSettings.statusLineConfig)
        }
        return appSettings.statusLineConfig
    }

    private var resolvedProfileName: String? {
        guard let profileID = pane.profileID else { return nil }
        return appSettings.profiles.first { $0.id == profileID }?.name
    }

    @ViewBuilder
    private var terminalBody: some View {
        let isActive = appState.activePaneID == pane.id
        if let controller = pane.terminalController {
            TerminalRepresentable(
                controller: controller,
                isActive: isActive,
                scrollbackLimit: pane.effectiveScrollback,
                scrollbackSource: pane.scrollbackOverride == nil ? "global" : "pane_override",
                paneID: pane.id.uuidString,
                paneName: pane.name,
                tabID: pane.tab?.id.uuidString ?? "",
                tabName: pane.tab?.name ?? ""
            )
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            .id(pane.restartToken)
            .accessibilityIdentifier("pane-terminal-\(pane.name)")
        } else if let recovery = pane.codexContinuationRecovery {
            Text(
                recovery == .identityNotRecorded
                    ? "Codex has not reported a conversation to continue."
                    : "The saved Codex conversation is unavailable."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .failed(let error) = pane.setupState {
            VStack(spacing: 12) {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Button("Remove Pane") { onClosePane(pane) }
                    .buttonStyle(.bordered)
            }
            .padding(16)
            .background(Theme.overlayMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("pane-error-overlay-\(pane.name)")
        } else if case .loading = pane.setupState {
            paneLoadingView
        } else {
            Theme.paneBackground
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var paneLoadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Setting up workspace\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Theme.overlayMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("pane-loading-overlay-\(pane.name)")
    }
}

private struct PaneScrollbackPresentation: Identifiable {
    let id = UUID()
    let limit: ScrollbackLimit
}

private struct PaneScrollbackEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var value: ScrollbackLimit?
    let inheritedValue: ScrollbackLimit
    let onApply: (ScrollbackLimit?) -> Void
    @State private var linesText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pane Scrollback History").font(.headline)
            ScrollbackLimitEditor(
                value: value,
                allowsInheritance: true,
                inheritedValue: inheritedValue,
                accessibilityPrefix: "pane-scrollback",
                onChange: { value = $0 },
                finiteLinesText: $linesText
            )
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply") {
                    let committed: ScrollbackLimit?
                    if case .finite? = value, let lines = Int(linesText) {
                        committed = ScrollbackLimit(finiteLines: lines)
                    } else {
                        committed = value
                    }
                    dismiss()
                    onApply(committed)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .pinnedSheetBackground()
    }
}
