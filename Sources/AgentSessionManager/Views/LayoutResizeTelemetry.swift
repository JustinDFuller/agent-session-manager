import Foundation
import SwiftUI

@MainActor
struct LayoutResizeTelemetry {
    static func record(
        event: String, section: String, axis: ResizeAxis, source: String, before: Double,
        after: Double, result: String, tab: Tab? = nil, pane: Pane? = nil,
        boundary: Int? = nil, action: ResizeAction? = nil
    ) {
        var attributes = [
            "section": section, "axis": axis.rawValue, "source": source,
            "before": String(before), "after": String(after), "result": result,
        ]
        if let tab {
            attributes["tab.id"] = tab.id.uuidString
            attributes["tab.name"] = tab.name
        }
        if let pane {
            attributes["pane.id"] = pane.id.uuidString
            attributes["pane.name"] = pane.name
            if let owner = pane.tab {
                attributes["tab.id"] = owner.id.uuidString
                attributes["tab.name"] = owner.name
            }
        }
        if let boundary { attributes["boundary.index"] = String(boundary) }
        if let action {
            attributes["direction"] = action.direction.rawValue
            attributes["action"] = action.larger ? "larger_step" : "normal_step"
        }
        TracingService.shared.record("layout.resize.\(event)", attributes: attributes)
    }
}

struct LayoutMeasurementKey: PreferenceKey {
    static var defaultValue: [String: Double] { [:] }
    static func reduce(value: inout [String: Double], nextValue: () -> [String: Double]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
