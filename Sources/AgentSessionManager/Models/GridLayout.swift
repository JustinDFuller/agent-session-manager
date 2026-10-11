import Foundation

struct GridLayout {
    let columns: Int
    let rows: Int
    let paneCount: Int

    var totalCells: Int { columns * rows }
    var emptyCells: Int { totalCells - paneCount }
}

extension GridLayout {
    static func forPaneCount(_ count: Int) -> Self {
        switch count {
        case 0, 1: Self(columns: 1, rows: 1, paneCount: count)
        case 2: Self(columns: 2, rows: 1, paneCount: count)
        case 3, 4: Self(columns: 2, rows: 2, paneCount: count)
        case 5, 6: Self(columns: 3, rows: 2, paneCount: count)
        default: Self(columns: 3, rows: 3, paneCount: count)
        }
    }

    static func normalized(_ weights: [Double]) -> [Double] {
        guard !weights.isEmpty, weights.allSatisfy({ $0.isFinite && $0 > 0 }) else { return [] }
        let largest = weights.max() ?? 1
        let scaled = weights.map { max($0 / largest, Double.leastNormalMagnitude) }
        let sum = scaled.reduce(0, +)
        return scaled.map { $0 / sum }
    }

    static func sizes(weights: [Double], extent: Double, minima: [Double]) -> [Double] {
        guard !minima.isEmpty else { return [] }
        let minimum = minima.map { $0.isFinite ? max(0, $0) : 0 }
        let available = max(extent.isFinite ? extent : 0, minimum.reduce(0, +))
        let normalized = normalized(weights)
        let preferred =
            normalized.count == minimum.count
            ? normalized : Array(repeating: 1 / Double(minimum.count), count: minimum.count)
        var result = Array(repeating: 0.0, count: minimum.count)
        var remaining = Set(minimum.indices)
        var free = available
        while !remaining.isEmpty {
            let total = remaining.reduce(0.0) { $0 + preferred[$1] }
            let constrained = remaining.filter { free * preferred[$0] / total < minimum[$0] }
            if constrained.isEmpty {
                let sorted = remaining.sorted()
                for index in sorted.dropLast() { result[index] = free * preferred[index] / total }
                if let last = sorted.last { result[last] = free - sorted.dropLast().reduce(0.0) { $0 + result[$1] } }
                break
            }
            for index in constrained {
                result[index] = minimum[index]
                free -= minimum[index]
                remaining.remove(index)
            }
        }
        return result
    }

    static func adjusting(_ sizes: [Double], boundary: Int, delta: Double, minima: [Double]) -> [Double] {
        guard sizes.count == minima.count, boundary >= 0, boundary + 1 < sizes.count, delta.isFinite else {
            return sizes
        }
        let lower = minima[boundary] - sizes[boundary]
        let upper = sizes[boundary + 1] - minima[boundary + 1]
        guard lower <= upper else { return sizes }
        let movement = min(upper, max(lower, delta))
        var adjusted = sizes
        adjusted[boundary] += movement
        adjusted[boundary + 1] -= movement
        return adjusted
    }

    static func equalizingAdjacent(_ sizes: [Double], boundary: Int, minima: [Double]) -> [Double] {
        guard sizes.count == minima.count, boundary >= 0, boundary + 1 < sizes.count else { return sizes }
        let delta = (sizes[boundary + 1] - sizes[boundary]) / 2
        return adjusting(sizes, boundary: boundary, delta: delta, minima: minima)
    }

    func boundary(paneIndex: Int, direction: ResizeDirection) -> Int? {
        guard paneIndex >= 0, paneIndex < paneCount else { return nil }
        let count = direction.axis == .columns ? columns : rows
        guard count > 1 else { return nil }
        let track = direction.axis == .columns ? paneIndex % columns : paneIndex / columns
        if direction.sign < 0 { return track > 0 ? track - 1 : 0 }
        return track < count - 1 ? track : track - 1
    }
}
