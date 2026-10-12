import Foundation
struct PaneGridMetrics {
    let grid: GridLayout
    let viewport: CGSize
    let columnWeights: [Double]
    let rowWeights: [Double]
    let minimumHeights: [Double]

    var columnSizes: [Double] {
        GridLayout.sizes(
            weights: columnWeights,
            extent: Double(viewport.width) - 8 - Double(max(0, grid.columns - 1)) * 4,
            minima: Array(repeating: 160, count: grid.columns)
        )
    }

    var rowSizes: [Double] {
        GridLayout.sizes(
            weights: rowWeights,
            extent: Double(viewport.height) - 8 - Double(max(0, grid.rows - 1)) * 4,
            minima: minimumHeights
        )
    }

    var contentSize: CGSize {
        CGSize(
            width: columnSizes.reduce(0, +) + 8 + Double(max(0, grid.columns - 1)) * 4,
            height: rowSizes.reduce(0, +) + 8 + Double(max(0, grid.rows - 1)) * 4
        )
    }

    var columnOffsets: [Double] {
        columnSizes.indices.map { index in
            4 + columnSizes.prefix(index).reduce(0, +) + Double(index) * 4
        }
    }

    var rowOffsets: [Double] {
        rowSizes.indices.map { index in
            4 + rowSizes.prefix(index).reduce(0, +) + Double(index) * 4
        }
    }

    static func maximumStatusHeight(paneHeight: Double, headerHeight: Double) -> Double {
        min(256, max(24, paneHeight - headerHeight - 1 - 8 - 64))
    }

    static func effectiveStatusHeight(
        preferredHeight: Double?, naturalHeight: Double, paneHeight: Double, headerHeight: Double
    ) -> Double {
        let desired = preferredHeight ?? naturalHeight
        let bounded = desired.isFinite ? max(24, desired) : 24
        return min(bounded, maximumStatusHeight(paneHeight: paneHeight, headerHeight: headerHeight))
    }
}
