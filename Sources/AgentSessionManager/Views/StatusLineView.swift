import AppKit
import SwiftUI

struct StatusLineView: View {
    let monitor: StatusLineMonitor
    let config: StatusLineConfig
    let paneID: UUID
    var viewportHeight: Double?
    var viewportWidth: Double?
    var profileName: String?

    @State private var showPRPopover = false

    private var nonEmptyRows: [StatusLineRow] {
        config.rows.compactMap { row in
            let supportedItems = row.items.filter { config.supports($0, on: monitor.harness) }
            guard !supportedItems.isEmpty else { return nil }
            var supportedRow = row
            supportedRow.items = supportedItems
            return supportedRow
        }
    }

    private var maxRowItemCount: Int {
        nonEmptyRows.map(\.items.count).max() ?? 0
    }

    var body: some View {
        Group {
            if !nonEmptyRows.isEmpty {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(nonEmptyRows) { row in
                            switch config.rowAlignment {
                            case .leading:
                                HStack(spacing: 12) {
                                    ForEach(row.items) { item in
                                        factView(item: item, data: monitor.currentData)
                                    }
                                    Spacer(minLength: 0)
                                }
                            case .spaceBetween:
                                HStack(spacing: 0) {
                                    ForEach(row.items) { item in
                                        factView(item: item, data: monitor.currentData)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    ForEach(0..<(maxRowItemCount - row.items.count), id: \.self) { _ in
                                        Spacer()
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minWidth: viewportWidth.map { CGFloat($0) }, alignment: .leading)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: LayoutMeasurementKey.self,
                                value: ["status-content-\(paneID.uuidString)": geometry.size.height]
                            )
                        }
                    }
                    .accessibilityIdentifier("status-line-row")
                }
                .frame(height: viewportHeight.map { CGFloat($0) })
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.windowBackground)
                .accessibilityIdentifier("status-line-viewport-\(paneID.uuidString)")
                .accessibilityLabel("Status line for pane")
            }
        }
        .task(id: config.customFields) {
            monitor.profileName = profileName
            monitor.setCustomFields(config.customFields)
        }
    }

    @ViewBuilder
    private func factView(item: StatusLineItem, data: StatusLineData?) -> some View {
        let content = HStack(spacing: 4) {
            factIconView(item: item, data: data)
            factLabelView(item: item)
            factValueView(item: item, data: data)
        }
        .fixedSize(horizontal: true, vertical: false)
        if item.id == "pr", data?.pr != nil {
            Button {
                showPRPopover.toggle()
            } label: {
                content
            }
            .buttonStyle(.plain)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .popover(isPresented: $showPRPopover, arrowEdge: .bottom) {
                if let pr = data?.pr {
                    PRPopoverContent(pr: pr)
                        .padding()
                }
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func factIconView(item: StatusLineItem, data: StatusLineData?) -> some View {
        if config.factLabelStyle != .labelOnly {
            if item.id == "pr", let pr = data?.pr {
                Image(systemName: pr.stateIconName)
                    .font(.system(size: 10))
                    .foregroundStyle(AnyShapeStyle(prCircleColor(pr: pr)))
            } else if item.id.hasPrefix("custom:") {
                let custom = data?.customFields?[item.id]
                Image(
                    systemName: StatusLineConfig.renderedCustomFieldSymbol(
                        scriptOverride: custom?.icon,
                        configuredSymbol: item.sfSymbol
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(customFieldIconStyle(custom?.tint))
            } else {
                Image(systemName: item.sfSymbol)
                    .font(.system(size: 10))
                    .foregroundStyle(
                        item.id == "exceeds200k" && data?.exceeds200kTokens == true
                            ? AnyShapeStyle(.orange)
                            : AnyShapeStyle(.tertiary)
                    )
            }
        }
    }

    @ViewBuilder
    private func factLabelView(item: StatusLineItem) -> some View {
        if config.factLabelStyle == .symbolAndLabel || config.factLabelStyle == .labelOnly {
            Text(item.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func percentageValue(value: Double, label: String, tint: Color, barWidth: CGFloat) -> some View {
        if config.showPercentagesAsText {
            Text(label).font(.caption).foregroundStyle(.secondary)
        } else {
            RateProgressView(value: value, barWidth: barWidth, label: label, tint: tint)
        }
    }

    @ViewBuilder
    private func factValueView(item: StatusLineItem, data: StatusLineData?) -> some View {
        switch item.id {
        case "context":
            if let pct = data?.contextWindow?.usedPercentage {
                percentageValue(value: Double(pct), label: "\(pct)%", tint: progressTint(pct), barWidth: 44)
            } else {
                Text("—").font(.caption).foregroundStyle(.secondary)
            }
        case "contextRemaining":
            if let pct = data?.contextWindow?.remainingPercentage {
                percentageValue(value: Double(pct), label: "\(pct)%", tint: progressTint(100 - pct), barWidth: 44)
            } else {
                Text("—").font(.caption).foregroundStyle(.secondary)
            }
        case "rate5h":
            if let pct = data?.rateLimits?.fiveHour?.usedPercentage {
                percentageValue(
                    value: pct, label: String(format: "%.0f%%", pct),
                    tint: progressTint(Int(pct)), barWidth: 32)
            } else {
                Text("—").font(.caption).foregroundStyle(.secondary)
            }
        case "rate7d":
            if let pct = data?.rateLimits?.sevenDay?.usedPercentage {
                percentageValue(
                    value: pct, label: String(format: "%.0f%%", pct),
                    tint: progressTint(Int(pct)), barWidth: 32)
            } else {
                Text("—").font(.caption).foregroundStyle(.secondary)
            }
        case "exceeds200k":
            Text(data?.exceeds200kTokens == true ? "200k+" : "—")
                .font(.caption)
                .foregroundStyle(
                    data?.exceeds200kTokens == true ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        case "pr":
            if let pr = data?.pr {
                HStack(spacing: 4) {
                    Circle()
                        .fill(prCircleColor(pr: pr))
                        .frame(width: 6, height: 6)
                    Text("#\(pr.number) (\(pr.displayState))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            if item.id.hasPrefix("custom:"), let percent = data?.customFields?[item.id]?.percent {
                let tint = customFieldTintColor(data?.customFields?[item.id]?.tint) ?? progressTint(Int(percent))
                percentageValue(value: percent, label: String(format: "%.0f%%", percent), tint: tint, barWidth: 44)
            } else {
                Text(factText(for: item.id, data: data))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func customFieldIconStyle(_ tint: CustomFieldTint?) -> AnyShapeStyle {
        switch tint {
        case .good: return AnyShapeStyle(Color.green)
        case .warning: return AnyShapeStyle(Color.orange)
        case .critical: return AnyShapeStyle(Color.red)
        case .normal, .none: return AnyShapeStyle(.tertiary)
        }
    }

    private func customFieldTintColor(_ tint: CustomFieldTint?) -> Color? {
        switch tint {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        case .normal, .none: return nil
        }
    }

    private func factText(for itemID: String, data: StatusLineData?) -> String {
        if itemID.hasPrefix("custom:") {
            return data?.customFields?[itemID]?.text ?? "—"
        }
        switch itemID {
        case "model": return data?.model?.displayName ?? data?.model?.id ?? "—"
        case "worktree": return data?.worktree?.factText ?? "—"
        case "cost": return data?.cost?.totalCostUsd.map { String(format: "$%.4f", $0) } ?? "—"
        case "effort": return data?.effort?.level ?? "—"
        case "thinking": return data?.thinking?.enabled == true ? "on" : "off"
        case "vimMode": return data?.vim?.mode ?? "—"
        case "agentName": return data?.agent?.name ?? "—"
        case "sessionName": return data?.sessionName ?? "—"
        case "linesAdded": return data?.cost?.totalLinesAdded.map { "+\($0)" } ?? "—"
        case "linesRemoved": return data?.cost?.totalLinesRemoved.map { "-\($0)" } ?? "—"
        case "duration": return data?.cost?.totalDurationMs.map(formatDuration) ?? "—"
        case "inputTokens": return data?.contextWindow?.totalInputTokens.map { "\($0)" } ?? "—"
        case "outputTokens": return data?.contextWindow?.totalOutputTokens.map { "\($0)" } ?? "—"
        case "rate5hReset": return data?.rateLimits?.fiveHour?.resetsAt.map(formatResetTime) ?? "—"
        case "rate7dReset": return data?.rateLimits?.sevenDay?.resetsAt.map(formatResetTime) ?? "—"
        case "version": return data?.version ?? "—"
        case "outputStyle": return data?.outputStyle?.name ?? "—"
        case "profileName": return profileName ?? "—"
        case "repo": return data?.repo.map { "\($0.owner)/\($0.name)" } ?? "—"
        case "contextSize": return data?.contextWindow?.contextWindowSize.map(formatTokenCount) ?? "—"
        case "cacheRead": return data?.contextWindow?.currentUsage?.cacheReadInputTokens.map { "\($0)" } ?? "—"
        case "cacheCreation":
            return data?.contextWindow?.currentUsage?.cacheCreationInputTokens.map { "\($0)" } ?? "—"
        case "apiDuration": return data?.cost?.totalApiDurationMs.map(formatDuration) ?? "—"
        default: return "—"
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        count >= 1000 ? "\(count / 1000)k" : "\(count)"
    }

    private func formatDuration(_ ms: Double) -> String {
        let seconds = Int(ms / 1000)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes < 60 { return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m" }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }

    private func prCircleColor(pr: PullRequest) -> Color {
        pr.circleColor
    }

    private func progressTint(_ pct: Int) -> Color {
        pct < 70 ? .green : pct < 90 ? .orange : .red
    }

    private func formatResetTime(_ timestamp: Int) -> String {
        let remaining = TimeInterval(timestamp) - Date().timeIntervalSince1970
        guard remaining > 0 else { return "now" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }
}

private struct RateProgressView: View {
    let value: Double
    let barWidth: CGFloat
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            ProgressView(value: value, total: 100)
                .progressViewStyle(.linear)
                .frame(width: barWidth)
                .tint(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PRPopoverContent: View {
    let pr: PullRequest

    private static let maxVisibleChecks = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(pr.circleColor)
                    .frame(width: 8, height: 8)
                Text("#\(pr.number)")
                    .font(.headline)
                    .fontDesign(.monospaced)
            }

            Text(pr.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let reviewLabel = pr.reviewStateLabel {
                Divider()

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(reviewLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if pr.hasMergeConflicts {
                Divider()

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text("Merge conflicts")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !visibleChecks.isEmpty {
                Divider()

                Text("Failing Checks")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleChecks) { check in
                        CheckRow(check: check)
                    }
                    if hiddenCheckCount > 0 {
                        Text("and \(hiddenCheckCount) more failing checks...")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let commentCount = pr.unresolvedCommentCount, commentCount > 0 {
                Divider()

                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 10))
                    Text("\(commentCount) unresolved \(commentCount == 1 ? "comment" : "comments")")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                if let url = URL(string: pr.url) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open Pull Request", systemImage: "arrow.up.forward.square")
                            .font(.caption)
                    }
                }
            }
        }
        .frame(width: 320)
        .textSelection(.enabled)
    }

    private var visibleChecks: [StatusCheck] {
        Array(pr.failingChecks.prefix(Self.maxVisibleChecks))
    }

    private var hiddenCheckCount: Int {
        max(0, pr.failingChecks.count - Self.maxVisibleChecks)
    }

    private struct CheckRow: View {
        let check: StatusCheck

        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                Text(check.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if let url = URL(string: check.detailsUrl ?? "") {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.square")
                            .font(.system(size: 9))
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20, minHeight: 20)
                    .contentShape(Rectangle())
                }
            }
        }
    }
}
