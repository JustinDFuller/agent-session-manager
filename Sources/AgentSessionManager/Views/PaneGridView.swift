import SwiftUI

private struct PaneGridPreview: Equatable {
    let axis: ResizeAxis
    let boundary: Int
    let sizes: [Double]
}

private struct PaneGridDivider: Hashable {
    let axis: ResizeAxis
    let boundary: Int
}

struct PaneGridView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var appSettings
    @State private var showingNewPane = false
    @State private var dragTargetPaneID: UUID?
    @State private var measurements: [String: Double] = [:]
    @State private var preview: PaneGridPreview?
    @State private var keyboardHighlight: PaneGridDivider?
    let tab: Tab
    let onClosePane: (Pane) -> Void
    let onRefreshPane: (Pane) -> Void
    let onViewPaneSettings: (Pane) -> Void

    var body: some View {
        Group {
            if tab.panes.isEmpty {
                tabEmptyState
            } else {
                panesGrid
            }
        }
        .sheet(
            isPresented: $showingNewPane,
            onDismiss: {
                appState.activePane?.terminalController?.focusTerminal()
            },
            content: {
                NewPaneSheet(tab: tab)
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .newPane)) { _ in
            showingNewPane = true
        }
    }

    private var panesGrid: some View {
        GeometryReader { geometry in
            let grid = GridLayout.forPaneCount(tab.panes.count)
            let minimumColumns = Array(repeating: 160.0, count: grid.columns)
            let minimumRows = (0..<grid.rows).map { row in
                tab.panes.enumerated()
                    .filter { $0.offset / grid.columns == row }
                    .map { _, pane in
                        return (measurements["header-\(pane.id.uuidString)"] ?? 28) + 1 + 64
                            + (measurements["status-min-\(pane.id.uuidString)"] ?? 0)
                    }
                    .max() ?? 64
            }
            let metrics = PaneGridMetrics(
                grid: grid,
                viewport: geometry.size,
                columnWeights: tab.gridSizePreferences.columnWeights,
                rowWeights: tab.gridSizePreferences.rowWeights,
                minimumHeights: minimumRows
            )
            let defaultColumnSizes = GridLayout.sizes(
                weights: Array(repeating: 1, count: grid.columns),
                extent: Double(geometry.size.width) - 8 - Double(max(0, grid.columns - 1)) * 4,
                minima: minimumColumns
            )
            let defaultRowSizes = GridLayout.sizes(
                weights: Array(repeating: 1, count: grid.rows),
                extent: Double(geometry.size.height) - 8 - Double(max(0, grid.rows - 1)) * 4,
                minima: minimumRows
            )
            let focusedPaneID = tab.focusedPaneID
            let focusedIndex = focusedPaneID.flatMap { focusedID in tab.panes.firstIndex { $0.id == focusedID } }
            let topologySignature = tab.panes.map { $0.id.uuidString }.joined(separator: ",")
            let activePaneID = appState.activePaneID?.uuidString ?? "none"
            let columns = preview?.axis == .columns ? preview!.sizes : metrics.columnSizes
            let rows = preview?.axis == .rows ? preview!.sizes : metrics.rowSizes
            let columnDividerPositions = PaneGridMetrics.dividerPositions(sizes: columns)
            let rowDividerPositions = PaneGridMetrics.dividerPositions(sizes: rows)
            let visibleSize = focusedIndex == nil ? metrics.contentSize : geometry.size
            let axes = {
                var axes: Axis.Set = []
                if focusedIndex == nil, metrics.contentSize.width > geometry.size.width + 0.5 {
                    axes.insert(.horizontal)
                }
                if focusedIndex == nil, metrics.contentSize.height > geometry.size.height + 0.5 {
                    axes.insert(.vertical)
                }
                return axes
            }()

            ScrollView(axes) {
                PaneGridLayout(
                    grid: grid,
                    columnSizes: columns,
                    rowSizes: rows,
                    viewport: geometry.size,
                    focusedPaneIndex: focusedIndex
                ) {
                    ForEach(tab.panes) { pane in
                        PaneGridCell(
                            dragTargetPaneID: $dragTargetPaneID,
                            pane: pane,
                            tab: tab,
                            isFocused: focusedPaneID == pane.id,
                            canFocus: tab.panes.count > 1,
                            onClosePane: onClosePane,
                            onRefreshPane: onRefreshPane,
                            onViewPaneSettings: onViewPaneSettings
                        )
                        .accessibilityHidden(focusedIndex != nil && focusedPaneID != pane.id)
                        .allowsHitTesting(focusedIndex == nil || focusedPaneID == pane.id)
                    }
                }
                .overlay {
                    GeometryReader { contentGeometry in
                        if focusedIndex == nil {
                            ForEach(0..<grid.columns - 1, id: \.self) { boundary in
                                let value = columns[boundary]
                                let maximum = columns[boundary] + columns[boundary + 1] - minimumColumns[boundary + 1]
                                ResizeHandle(
                                    axis: .columns,
                                    identifier: "pane-grid-\(tab.id.uuidString)-column-divider-\(boundary)",
                                    label: "Resize column divider \(boundary + 1)",
                                    value: value,
                                    minimum: minimumColumns[boundary],
                                    maximum: max(minimumColumns[boundary], maximum),
                                    focusTarget: appState.activePane?.terminalController?.terminalView,
                                    highlighted: keyboardHighlight
                                        == PaneGridDivider(axis: .columns, boundary: boundary),
                                    cancellationKey:
                                        "\(tab.id)-\(grid.columns)x\(grid.rows)-\(topologySignature)-\(focusedPaneID?.uuidString ?? "all")-\(activePaneID)-\(geometry.size.width)x\(geometry.size.height)",
                                    onPreview: { proposed in
                                        guard let proposed else {
                                            preview = nil
                                            return
                                        }
                                        preview = PaneGridPreview(
                                            axis: .columns,
                                            boundary: boundary,
                                            sizes: GridLayout.adjusting(
                                                metrics.columnSizes,
                                                boundary: boundary,
                                                delta: proposed - metrics.columnSizes[boundary],
                                                minima: minimumColumns
                                            )
                                        )
                                    },
                                    onCommit: { proposed, source in
                                        let adjusted = GridLayout.adjusting(
                                            metrics.columnSizes,
                                            boundary: boundary,
                                            delta: proposed - metrics.columnSizes[boundary],
                                            minima: minimumColumns
                                        )
                                        guard adjusted != metrics.columnSizes else { return }
                                        let before = metrics.columnSizes[boundary]
                                        tab.gridSizePreferences.columnWeights = GridLayout.normalized(adjusted)
                                        LayoutResizeTelemetry.record(
                                            event: "completed",
                                            section: "grid",
                                            axis: .columns,
                                            source: source,
                                            before: before,
                                            after: adjusted[boundary],
                                            result: "success",
                                            tab: tab,
                                            pane: appState.activePane,
                                            boundary: boundary
                                        )
                                        LayoutResizeTelemetry.saveSession(
                                            appState: appState, appSettings: appSettings, tab: tab,
                                            axis: .columns, source: source
                                        )
                                    },
                                    onReset: { source in
                                        let reset = GridLayout.equalizingAdjacent(
                                            metrics.columnSizes, boundary: boundary, minima: minimumColumns
                                        )
                                        tab.gridSizePreferences.columnWeights = GridLayout.normalized(reset)
                                        LayoutResizeTelemetry.record(
                                            event: "reset",
                                            section: "grid",
                                            axis: .columns,
                                            source: source,
                                            before: metrics.columnSizes[boundary],
                                            after: reset[boundary],
                                            result: "success",
                                            tab: tab,
                                            pane: appState.activePane,
                                            boundary: boundary
                                        )
                                        LayoutResizeTelemetry.saveSession(
                                            appState: appState, appSettings: appSettings, tab: tab,
                                            axis: .columns, source: source
                                        )
                                    },
                                    onCancel: {
                                        preview = nil
                                        LayoutResizeTelemetry.record(
                                            event: "canceled",
                                            section: "grid",
                                            axis: .columns,
                                            source: "pointer",
                                            before: metrics.columnSizes[boundary],
                                            after: metrics.columnSizes[boundary],
                                            result: "canceled",
                                            tab: tab,
                                            pane: appState.activePane,
                                            boundary: boundary
                                        )
                                    }
                                )
                                .frame(width: 8, height: contentGeometry.size.height)
                                .position(
                                    x: columnDividerPositions[boundary],
                                    y: contentGeometry.size.height / 2
                                )
                            }
                            ForEach(0..<grid.rows - 1, id: \.self) { boundary in
                                let value = rows[boundary]
                                let maximum = rows[boundary] + rows[boundary + 1] - minimumRows[boundary + 1]
                                ResizeHandle(
                                    axis: .rows,
                                    identifier: "pane-grid-\(tab.id.uuidString)-row-divider-\(boundary)",
                                    label: "Resize row divider \(boundary + 1)",
                                    value: value,
                                    minimum: minimumRows[boundary],
                                    maximum: max(minimumRows[boundary], maximum),
                                    focusTarget: appState.activePane?.terminalController?.terminalView,
                                    highlighted: keyboardHighlight == PaneGridDivider(axis: .rows, boundary: boundary),
                                    cancellationKey:
                                        "\(tab.id)-\(grid.columns)x\(grid.rows)-\(topologySignature)-\(focusedPaneID?.uuidString ?? "all")-\(activePaneID)-\(geometry.size.width)x\(geometry.size.height)",
                                    onPreview: { proposed in
                                        guard let proposed else {
                                            preview = nil
                                            return
                                        }
                                        preview = PaneGridPreview(
                                            axis: .rows,
                                            boundary: boundary,
                                            sizes: GridLayout.adjusting(
                                                metrics.rowSizes,
                                                boundary: boundary,
                                                delta: proposed - metrics.rowSizes[boundary],
                                                minima: minimumRows
                                            )
                                        )
                                    },
                                    onCommit: { proposed, source in
                                        let adjusted = GridLayout.adjusting(
                                            metrics.rowSizes,
                                            boundary: boundary,
                                            delta: proposed - metrics.rowSizes[boundary],
                                            minima: minimumRows
                                        )
                                        guard adjusted != metrics.rowSizes else { return }
                                        let before = metrics.rowSizes[boundary]
                                        tab.gridSizePreferences.rowWeights = GridLayout.normalized(adjusted)
                                        LayoutResizeTelemetry.record(
                                            event: "completed",
                                            section: "grid",
                                            axis: .rows,
                                            source: source,
                                            before: before,
                                            after: adjusted[boundary],
                                            result: "success",
                                            tab: tab,
                                            pane: appState.activePane,
                                            boundary: boundary
                                        )
                                        LayoutResizeTelemetry.saveSession(
                                            appState: appState, appSettings: appSettings, tab: tab,
                                            axis: .rows, source: source
                                        )
                                    },
                                    onReset: { source in
                                        let reset = GridLayout.equalizingAdjacent(
                                            metrics.rowSizes, boundary: boundary, minima: minimumRows
                                        )
                                        tab.gridSizePreferences.rowWeights = GridLayout.normalized(reset)
                                        LayoutResizeTelemetry.record(
                                            event: "reset",
                                            section: "grid",
                                            axis: .rows,
                                            source: source,
                                            before: metrics.rowSizes[boundary],
                                            after: reset[boundary],
                                            result: "success",
                                            tab: tab,
                                            pane: appState.activePane,
                                            boundary: boundary
                                        )
                                        LayoutResizeTelemetry.saveSession(
                                            appState: appState, appSettings: appSettings, tab: tab,
                                            axis: .rows, source: source
                                        )
                                    },
                                    onCancel: {
                                        preview = nil
                                        LayoutResizeTelemetry.record(
                                            event: "canceled",
                                            section: "grid",
                                            axis: .rows,
                                            source: "pointer",
                                            before: metrics.rowSizes[boundary],
                                            after: metrics.rowSizes[boundary],
                                            result: "canceled",
                                            tab: tab,
                                            pane: appState.activePane,
                                            boundary: boundary
                                        )
                                    }
                                )
                                .frame(width: contentGeometry.size.width, height: 8)
                                .position(
                                    x: contentGeometry.size.width / 2,
                                    y: rowDividerPositions[boundary]
                                )
                            }
                        }
                    }
                }
                .frame(width: visibleSize.width, height: visibleSize.height)
                .clipped()
            }
            .scrollIndicators(axes.isEmpty ? .hidden : .visible)
            .accessibilityIdentifier("pane-grid-\(tab.id.uuidString)")
            .onPreferenceChange(LayoutMeasurementKey.self) { next in
                measurements.merge(next, uniquingKeysWith: { _, newer in newer })
            }
            .onChange(of: topologySignature) { _, _ in
                preview = nil
                keyboardHighlight = nil
            }
            .onChange(of: geometry.size) { _, _ in
                preview = nil
                keyboardHighlight = nil
            }
            .onChange(of: appState.activePaneID) { _, _ in
                keyboardHighlight = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .paneResizeCommand)) { notification in
                guard
                    appState.activeTabID == tab.id,
                    focusedIndex == nil,
                    let paneID = notification.userInfo?["paneID"] as? UUID,
                    paneID == appState.activePaneID,
                    let action = notification.userInfo?["action"] as? ResizeAction,
                    preview == nil,
                    let paneIndex = tab.panes.firstIndex(where: { $0.id == paneID }),
                    let boundary = grid.boundary(paneIndex: paneIndex, direction: action.direction)
                else { return }
                let sizes = action.direction.axis == .columns ? metrics.columnSizes : metrics.rowSizes
                let minima = action.direction.axis == .columns ? minimumColumns : minimumRows
                keyboardHighlight = PaneGridDivider(axis: action.direction.axis, boundary: boundary)
                let adjusted = GridLayout.adjusting(
                    sizes,
                    boundary: boundary,
                    delta: action.direction.sign * action.step,
                    minima: minima
                )
                guard adjusted != sizes else { return }
                if action.direction.axis == .columns {
                    tab.gridSizePreferences.columnWeights = GridLayout.normalized(adjusted)
                } else {
                    tab.gridSizePreferences.rowWeights = GridLayout.normalized(adjusted)
                }
                LayoutResizeTelemetry.record(
                    event: "completed",
                    section: "grid",
                    axis: action.direction.axis,
                    source: "keyboard",
                    before: sizes[boundary],
                    after: adjusted[boundary],
                    result: "success",
                    tab: tab,
                    pane: tab.panes[paneIndex],
                    boundary: boundary,
                    action: action
                )
                LayoutResizeTelemetry.saveSession(
                    appState: appState, appSettings: appSettings, tab: tab,
                    axis: action.direction.axis, source: "keyboard"
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .paneResizeReleased)) { _ in
                keyboardHighlight = nil
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("Create Pane") {
                    showingNewPane = true
                }
                Button("Reset Pane Sizes") {
                    tab.gridSizePreferences = PaneGridSizePreferences()
                    LayoutResizeTelemetry.record(
                        event: "reset",
                        section: "grid",
                        axis: .columns,
                        source: "context_menu",
                        before: metrics.columnSizes[0],
                        after: defaultColumnSizes[0],
                        result: "success",
                        tab: tab,
                        pane: appState.activePane
                    )
                    LayoutResizeTelemetry.record(
                        event: "reset",
                        section: "grid",
                        axis: .rows,
                        source: "context_menu",
                        before: metrics.rowSizes[0],
                        after: defaultRowSizes[0],
                        result: "success",
                        tab: tab,
                        pane: appState.activePane
                    )
                    LayoutResizeTelemetry.saveSession(
                        appState: appState, appSettings: appSettings, tab: tab, axis: .columns,
                        source: "context_menu"
                    )
                }
                .accessibilityIdentifier("pane-reset-sizes")
            }
        }
    }

    private var tabEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("Press ⌘P to open a pane")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .accessibilityIdentifier("tab-empty-state-\(tab.name)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Create Pane") {
                showingNewPane = true
            }
        }
    }
}
