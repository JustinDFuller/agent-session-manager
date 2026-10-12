import XCTest

@testable import AgentSessionManager

@MainActor
final class PaneGridMetricsTests: XCTestCase {
    func testAutomaticGridShapesKeepEveryTrackIncludingEmptyCells() {
        let expected: [(Int, GridLayout)] = [
            (1, GridLayout(columns: 1, rows: 1, paneCount: 1)),
            (2, GridLayout(columns: 2, rows: 1, paneCount: 2)),
            (3, GridLayout(columns: 2, rows: 2, paneCount: 3)),
            (4, GridLayout(columns: 2, rows: 2, paneCount: 4)),
            (5, GridLayout(columns: 3, rows: 2, paneCount: 5)),
            (6, GridLayout(columns: 3, rows: 2, paneCount: 6)),
            (7, GridLayout(columns: 3, rows: 3, paneCount: 7)),
        ]
        for (paneCount, expectedLayout) in expected {
            let grid = GridLayout.forPaneCount(paneCount)
            XCTAssertEqual(grid.columns, expectedLayout.columns)
            XCTAssertEqual(grid.rows, expectedLayout.rows)
            XCTAssertEqual(grid.totalCells, expectedLayout.totalCells)
            XCTAssertEqual(grid.emptyCells, expectedLayout.emptyCells)
        }
    }

    func testGridMetricsIncludeGuttersAndTrackOffsets() {
        let metrics = PaneGridMetrics(
            grid: GridLayout(columns: 3, rows: 2, paneCount: 5),
            viewport: CGSize(width: 1_000, height: 700),
            columnWeights: [0.5, 0.3, 0.2],
            rowWeights: [0.6, 0.4],
            minimumHeights: [100, 120]
        )
        XCTAssertEqual(metrics.columnSizes.reduce(0, +) + 16, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(metrics.rowSizes.reduce(0, +) + 12, 700, accuracy: 0.000_001)
        XCTAssertEqual(metrics.columnOffsets[0], 4)
        XCTAssertEqual(metrics.columnOffsets[1], 4 + metrics.columnSizes[0] + 4)
        XCTAssertEqual(metrics.rowOffsets[1], 4 + metrics.rowSizes[0] + 4)
        XCTAssertEqual(metrics.contentSize, CGSize(width: 1_000, height: 700))
    }

    func testPaneMinimaCreateScrollableOverflowWithoutChangingPreferredWeights() {
        let preferences = PaneGridSizePreferences(columnWeights: [0.5, 0.3, 0.2], rowWeights: [0.7, 0.3])
        let metrics = PaneGridMetrics(
            grid: GridLayout(columns: 3, rows: 2, paneCount: 5),
            viewport: CGSize(width: 420, height: 260),
            columnWeights: preferences.columnWeights,
            rowWeights: preferences.rowWeights,
            minimumHeights: [180, 120]
        )
        XCTAssertEqual(metrics.columnSizes, [160, 160, 160])
        XCTAssertGreaterThan(metrics.contentSize.width, metrics.viewport.width)
        XCTAssertEqual(metrics.rowSizes[0], 180)
        XCTAssertEqual(metrics.rowSizes[1], 120)
        XCTAssertGreaterThan(metrics.contentSize.height, metrics.viewport.height)
        XCTAssertEqual(preferences.columnWeights, [0.5, 0.3, 0.2])
        XCTAssertEqual(preferences.rowWeights, [0.7, 0.3])
    }

    func testEqualizingDividerPreservesAdjacentExtentAndOtherTracks() {
        let sizes = [420.0, 300.0, 180.0]
        let adjusted = GridLayout.equalizingAdjacent(sizes, boundary: 0, minima: [160, 160, 160])
        XCTAssertEqual(adjusted[0], 360, accuracy: 0.000_001)
        XCTAssertEqual(adjusted[1], 360, accuracy: 0.000_001)
        XCTAssertEqual(adjusted[0] + adjusted[1], sizes[0] + sizes[1], accuracy: 0.000_001)
        XCTAssertEqual(adjusted[2], sizes[2], accuracy: 0.000_001)
        XCTAssertEqual(adjusted.reduce(0, +), sizes.reduce(0, +), accuracy: 0.000_001)
    }

    func testFocusedLayoutUsesViewportWhileRetainingGridTracks() {
        let layout = GridLayout.forPaneCount(4)
        let metrics = PaneGridMetrics(
            grid: layout,
            viewport: CGSize(width: 800, height: 600),
            columnWeights: [0.65, 0.35],
            rowWeights: [0.7, 0.3],
            minimumHeights: [100, 100]
        )
        XCTAssertEqual(metrics.contentSize, CGSize(width: 800, height: 600))
        XCTAssertEqual(metrics.columnSizes[0] / metrics.columnSizes[1], 0.65 / 0.35, accuracy: 0.000_001)
        XCTAssertEqual(metrics.rowSizes[0] / metrics.rowSizes[1], 0.7 / 0.3, accuracy: 0.000_001)
    }

    func testStatusViewportClampsToProtectTerminalAndPreservesPreferredHeight() {
        XCTAssertEqual(
            PaneGridMetrics.effectiveStatusHeight(
                preferredHeight: 220, naturalHeight: 80, paneHeight: 180, headerHeight: 28
            ),
            79
        )
        XCTAssertEqual(
            PaneGridMetrics.effectiveStatusHeight(
                preferredHeight: nil, naturalHeight: 300, paneHeight: 900, headerHeight: 28
            ),
            256
        )
        XCTAssertEqual(
            PaneGridMetrics.effectiveStatusHeight(
                preferredHeight: nil, naturalHeight: 300, paneHeight: 100, headerHeight: 28
            ),
            24
        )
        XCTAssertEqual(PaneGridMetrics.maximumStatusHeight(paneHeight: 180, headerHeight: 28), 79)
    }
}
