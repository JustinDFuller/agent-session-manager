import SwiftUI

struct PaneGridCell: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var appSettings
    @Binding var dragTargetPaneID: UUID?
    let pane: Pane
    let tab: Tab
    let isFocused: Bool
    let canFocus: Bool
    let onClosePane: (Pane) -> Void
    let onRefreshPane: (Pane) -> Void
    let onViewPaneSettings: (Pane) -> Void

    var body: some View {
        PaneView(
            pane: pane,
            isFocused: isFocused,
            canFocus: canFocus,
            onClosePane: onClosePane,
            onRefreshPane: onRefreshPane,
            onViewPaneSettings: onViewPaneSettings
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane-\(pane.name)")
        .overlay(
            dragTargetPaneID == pane.id
                ? RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.6), lineWidth: 2)
                : nil
        )
        .dropDestination(for: String.self) { items, _ in
            guard
                let droppedID = items.first,
                let droppedUUID = UUID(uuidString: droppedID),
                let from = tab.panes.firstIndex(where: { $0.id == droppedUUID }),
                let to = tab.panes.firstIndex(where: { $0.id == pane.id }),
                from != to
            else { return false }
            tab.movePane(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
            LayoutResizeTelemetry.saveSession(appState: appState, appSettings: appSettings, tab: tab)
            return true
        } isTargeted: { isTargeted in
            dragTargetPaneID = isTargeted ? pane.id : nil
        }
    }
}

struct PaneGridLayout: Layout {
    let grid: GridLayout
    let columnSizes: [Double]
    let rowSizes: [Double]
    let viewport: CGSize
    let focusedPaneIndex: Int?

    var contentSize: CGSize {
        CGSize(
            width: columnSizes.reduce(0, +) + 8 + Double(max(0, grid.columns - 1)) * 4,
            height: rowSizes.reduce(0, +) + 8 + Double(max(0, grid.rows - 1)) * 4
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        focusedPaneIndex == nil ? contentSize : viewport
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for (index, subview) in subviews.enumerated() {
            if let focusedPaneIndex {
                let focused = index == focusedPaneIndex
                let origin =
                    focused
                    ? CGPoint(x: bounds.minX + 4, y: bounds.minY + 4)
                    : CGPoint(x: bounds.maxX + 16, y: bounds.minY + 4)
                let size =
                    focused
                    ? CGSize(width: max(1, bounds.width - 8), height: max(1, bounds.height - 8))
                    : CGSize(width: max(1, bounds.width - 8), height: max(1, bounds.height - 8))
                subview.place(at: origin, proposal: ProposedViewSize(size))
            } else {
                let column = index % grid.columns
                let row = index / grid.columns
                let x = bounds.minX + 4 + columnSizes.prefix(column).reduce(0, +) + Double(column) * 4
                let y = bounds.minY + 4 + rowSizes.prefix(row).reduce(0, +) + Double(row) * 4
                subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: columnSizes[column], height: rowSizes[row])
                )
            }
        }
    }
}
