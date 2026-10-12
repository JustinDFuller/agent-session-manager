import SwiftUI

enum NotificationSidebarTheme {
    static let surfaceBackground = Theme.sidebarBackground
    static let containerBackground = surfaceBackground
    static let headerBackground = surfaceBackground
}

struct NotificationSidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appState = appState
        let priorityNotifications = appState.notifications.filter { $0.isPriority }
        let regularNotifications = appState.notifications.filter { !$0.isPriority }
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if appSettings.isPriorityNotificationsEnabled && !priorityNotifications.isEmpty {
                        sectionHeader("Priority")
                        ForEach(priorityNotifications) { notification in
                            notificationRow(notification)
                        }
                        if !regularNotifications.isEmpty {
                            Divider().padding(.vertical, 4)
                        }
                    }

                    let shown =
                        appSettings.isPriorityNotificationsEnabled ? regularNotifications : appState.notifications
                    if !shown.isEmpty {
                        if appSettings.isPriorityNotificationsEnabled && !priorityNotifications.isEmpty {
                            sectionHeader("Other")
                        }
                        ForEach(shown) { notification in
                            notificationRow(notification)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            clearAllButton
        }
        .frame(maxWidth: .infinity)
        .background(NotificationSidebarTheme.containerBackground)
        .accessibilityIdentifier("notification-sidebar")
    }

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NotificationSidebarTheme.headerBackground)
    }

    private var clearAllButton: some View {
        Button {
            appState.notifications.removeAll()
            SessionPersistence.save(appState: appState)
        } label: {
            Text("Clear All")
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityIdentifier("notification-clear-all")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func notificationRow(_ notification: PaneNotification) -> some View {
        Button {
            appState.acknowledgeNotification(id: notification.id)
        } label: {
            HStack(spacing: 8) {
                if notification.kind == .prMerged {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.purple)
                        .frame(width: 7, height: 7)
                        .padding(.top, 2)
                        .alignmentGuide(.firstTextBaseline) { dims in dims[.top] }
                } else {
                    Circle()
                        .fill(notification.isPriority ? Color.orange : Theme.accent)
                        .frame(width: 7, height: 7)
                        .padding(.top, 2)
                        .alignmentGuide(.firstTextBaseline) { dims in dims[.top] }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(notification.tabName) / \(notification.paneName)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(notification.displayReason)
                        .font(.system(size: 10))
                        .foregroundStyle(notification.kind == .prMerged ? Color.purple : Color.secondary)
                        .lineLimit(1)
                    Text(
                        {
                            let formatter = DateFormatter()
                            formatter.dateFormat =
                                Calendar.current.isDate(notification.timestamp, inSameDayAs: Date())
                                ? "HH:mm" : "MM/dd/yyyy"
                            return formatter.string(from: notification.timestamp)
                        }()
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .accessibilityIdentifier("notification-row-\(notification.paneName)")
    }
}
