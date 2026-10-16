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
        if item.id == "pr" {
            Button {
                showPRPopover.toggle()
            } label: {
                content
            }
            .buttonStyle(.plain)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .popover(isPresented: $showPRPopover, arrowEdge: .bottom) {
                PRPopoverContent(
                    pr: data?.pr,
                    status: monitor.prTrackingStatus,
                    onRetry: { PRTrackingCoordinator.shared.retry(paneID: paneID) }
                )
                .padding()
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
            } else if item.id == "pr", monitor.prTrackingStatus.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
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
                    if monitor.prTrackingStatus.isStale {
                        Text("stale")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text(prTrackingValue)
                    .font(.caption)
                    .foregroundStyle(monitor.prTrackingStatus.isStale ? .orange : .secondary)
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

    private var prTrackingValue: String {
        switch monitor.prTrackingStatus {
        case .loading: "Checking…"
        case .current: "—"
        case .noPullRequest: "No PR"
        case .unavailable: "Unavailable"
        case .disabled: "Off"
        case .failed: "Unavailable"
        }
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
    let pr: PullRequest?
    let status: PRTrackingStatus
    let onRetry: () -> Void

    private static let maxVisibleChecks = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pr {
                HStack {
                    Circle()
                        .fill(pr.circleColor)
                        .frame(width: 8, height: 8)
                    Text("#\(pr.number)")
                        .font(.headline)
                        .fontDesign(.monospaced)
                    if status.isStale {
                        Text("Stale")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Text(pr.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            statusMessage

            if let pr, let reviewLabel = pr.reviewStateLabel {
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

            if let pr, pr.hasMergeConflicts {
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

            if pr != nil, !visibleChecks.isEmpty {
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

            if let commentCount = pr?.unresolvedCommentCount, commentCount > 0 {
                Divider()

                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 10))
                    Text("\(commentCount) unresolved \(commentCount == 1 ? "comment" : "comments")")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            if let pr {
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

            if case .failed = status {
                Button("Retry") { onRetry() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("pr-tracking-retry")
            }
        }
        .frame(width: 320)
        .textSelection(.enabled)
        .accessibilityIdentifier("pr-tracking-popover")
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch status {
        case .loading:
            Text(pr == nil ? "Checking GitHub for a pull request…" : "Checking for updates…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .current:
            EmptyView()
        case .noPullRequest:
            Text("No pull request was found for this branch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unavailable:
            Text("A supported GitHub repository and branch are required for pull-request tracking.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .disabled:
            Text("Pull-request tracking is off. Enable it in Settings → Status Line.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 4) {
                Text(failureMessage(failure))
                    .font(.caption)
                    .foregroundStyle(.orange)
                if pr != nil {
                    Text("The last pull-request result is shown as stale.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func failureMessage(_ failure: GitHubCLIFailure) -> String {
        switch failure {
        case .authentication:
            "GitHub CLI authentication failed. Authenticate the configured `gh`, then retry."
        case .missingExecutable:
            "GitHub CLI (`gh`) was not found through GH_PATH or the configured shell."
        case .network:
            "GitHub could not be reached. Check your connection, then retry."
        case .timeout:
            "The GitHub request timed out. Retry when the service is available."
        case .parse:
            "GitHub returned an unreadable pull-request response. Retry to check again."
        case .cancelled:
            "The GitHub request was cancelled. Retry to check again."
        case .launch, .stdinWrite, .api:
            "GitHub PR status could not be refreshed. Retry to check again."
        }
    }

    private var visibleChecks: [StatusCheck] {
        Array((pr?.failingChecks ?? []).prefix(Self.maxVisibleChecks))
    }

    private var hiddenCheckCount: Int {
        max(0, (pr?.failingChecks.count ?? 0) - Self.maxVisibleChecks)
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
