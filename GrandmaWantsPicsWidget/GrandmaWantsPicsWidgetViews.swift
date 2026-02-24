import SwiftUI
import WidgetKit

struct GrandmaWantsPicsWidgetView: View {
    let entry: GrandmaWantsPicsWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if let role = entry.widgetData.role {
                if !entry.widgetData.isPaired {
                    notPairedView
                } else if role == "adult" {
                    adultView
                } else {
                    grandmaView
                }
            } else {
                noRoleView
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Adult View

    private var adultView: some View {
        VStack(spacing: 6) {
            adultEmoji
            adultMessage
            if family != .systemSmall {
                adultDetail
            }
        }
        .padding()
        .widgetURL(URL(string: "\(AppGroupConstants.deepLinkScheme)://inbox"))
    }

    private var adultEmoji: some View {
        Group {
            if entry.widgetData.pendingRequestCount > 0 {
                Text("\u{1F97A}")
                    .font(.system(size: family == .systemSmall ? 36 : 44))
            } else if daysSince(entry.widgetData.lastFulfilledDate) > 7 {
                Text("\u{1F622}")
                    .font(.system(size: family == .systemSmall ? 36 : 44))
            } else {
                Text("\u{1F60A}")
                    .font(.system(size: family == .systemSmall ? 36 : 44))
            }
        }
    }

    private var adultMessage: some View {
        Group {
            if entry.widgetData.pendingRequestCount > 0 {
                VStack(spacing: 2) {
                    Text("Don't forget me!")
                        .font(.system(size: family == .systemSmall ? 14 : 16, weight: .bold))
                        .foregroundStyle(.pink)
                    Text("\(entry.widgetData.pendingRequestCount) request\(entry.widgetData.pendingRequestCount == 1 ? "" : "s") waiting")
                        .font(.system(size: family == .systemSmall ? 11 : 13))
                        .foregroundStyle(.secondary)
                }
            } else if let lastFulfilled = entry.widgetData.lastFulfilledDate {
                let days = daysSince(lastFulfilled)
                VStack(spacing: 2) {
                    Text(streakMessage(days: days))
                        .font(.system(size: family == .systemSmall ? 13 : 15, weight: .bold))
                        .foregroundStyle(days > 7 ? .orange : .green)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 0) {
                        Text(lastFulfilled, style: .relative)
                        Text(" ago")
                    }
                    .font(.system(size: family == .systemSmall ? 10 : 12))
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Send Grandma\na photo today!")
                    .font(.system(size: family == .systemSmall ? 13 : 15, weight: .bold))
                    .foregroundStyle(.pink)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var adultDetail: some View {
        Group {
            if let oldest = entry.widgetData.oldestPendingRequestDate {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                    HStack(spacing: 0) {
                        Text("Waiting since ")
                        Text(oldest, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Grandma View

    private var grandmaView: some View {
        VStack(spacing: 6) {
            if let lastReceived = entry.widgetData.lastPhotosReceivedDate {
                Text("\u{1F4F8}")
                    .font(.system(size: family == .systemSmall ? 36 : 44))
                Text("Last photos")
                    .font(.system(size: family == .systemSmall ? 11 : 13))
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    Text(lastReceived, style: .relative)
                    Text(" ago")
                }
                .font(.system(size: family == .systemSmall ? 14 : 16, weight: .bold))
                .foregroundStyle(.pink)
            } else {
                Text("\u{1F495}")
                    .font(.system(size: family == .systemSmall ? 36 : 44))
                Text("Tap to request\nphotos!")
                    .font(.system(size: family == .systemSmall ? 13 : 15, weight: .bold))
                    .foregroundStyle(.pink)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .widgetURL(URL(string: entry.widgetData.lastPhotosReceivedDate != nil
            ? "\(AppGroupConstants.deepLinkScheme)://gallery"
            : "\(AppGroupConstants.deepLinkScheme)://home"))
    }

    // MARK: - Fallback Views

    private var noRoleView: some View {
        VStack(spacing: 8) {
            Text("\u{1F495}")
                .font(.system(size: 36))
            Text("Open app\nto get started")
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .widgetURL(URL(string: "\(AppGroupConstants.deepLinkScheme)://"))
    }

    private var notPairedView: some View {
        VStack(spacing: 8) {
            Text("\u{1F517}")
                .font(.system(size: 36))
            Text("Pair with family\nto start sharing")
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .widgetURL(URL(string: "\(AppGroupConstants.deepLinkScheme)://pair"))
    }

    // MARK: - Helpers

    private func daysSince(_ date: Date?) -> Int {
        guard let date else { return 999 }
        return Calendar.current.dateComponents([.day], from: date, to: entry.date).day ?? 0
    }

    private func streakMessage(days: Int) -> String {
        switch days {
        case 0: return "Photos sent today!"
        case 1: return "Photos sent yesterday"
        case 2...3: return "Grandma misses you!"
        case 4...7: return "It's been a few days..."
        default: return "Don't forget\nGrandma!"
        }
    }
}
