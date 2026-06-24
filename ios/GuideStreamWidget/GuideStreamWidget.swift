//
//  GuideStreamWidget.swift
//  GuideStreamWidget
//
//  Shows Leaving Soon titles, watchlist count, and new episode alerts
//  across small, medium, and large widget families. All data is read
//  from the App Group shared UserDefaults, written by the main app
//  whenever the user's watchlist or leaving-soon list changes.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

nonisolated struct WidgetEntry: TimelineEntry {
    let date: Date
    let payload: WidgetPayload?
}

// MARK: - Timeline Provider

nonisolated struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(
            date: Date(),
            payload: WidgetPayload(
                leavingSoon: [
                    LeavingSoonItem(
                        id: "ph1", title: "Stranger Things",
                        platform: "NETFLIX", platformColorHex: "#E50914",
                        posterUrl: nil, daysRemaining: 3, expireDate: "Jun 27"
                    ),
                    LeavingSoonItem(
                        id: "ph2", title: "The Crown",
                        platform: "NETFLIX", platformColorHex: "#E50914",
                        posterUrl: nil, daysRemaining: 5, expireDate: "Jun 29"
                    ),
                    LeavingSoonItem(
                        id: "ph3", title: "Game of Thrones",
                        platform: "HBO", platformColorHex: "#5A1FCB",
                        posterUrl: nil, daysRemaining: 7, expireDate: "Jul 1"
                    ),
                ],
                watchlistCount: 12,
                newEpisodeCount: 3,
                lastUpdated: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let payload = WidgetDataStore.load()
        completion(WidgetEntry(date: Date(), payload: payload))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let payload = WidgetDataStore.load()
        let entry = WidgetEntry(date: Date(), payload: payload)
        // Refresh every 15 minutes so the widget picks up new Leaving Soon data
        // and watchlist changes without waiting hours. The main app also calls
        // WidgetCenter.shared.reloadTimelines() on every data change.
        let nextUpdate = Date().addingTimeInterval(15 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Brand wordmark
            HStack(spacing: 0) {
                Text("Guide")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Stream")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255))
                Text("TV")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(red: 0x5B/255, green: 0xB0/255, blue: 0xFF/255))
                    .baselineOffset(4)
                    .padding(.leading, 1)
            }

            Spacer()

            // Watchlist count badge
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.payload?.watchlistCount ?? 0)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("in Watchlist")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                // Leaving Soon count ring
                if let soon = entry.payload?.leavingSoon.count, soon > 0 {
                    ZStack {
                        Circle()
                            .stroke(Color.orange.opacity(0.2), lineWidth: 3)
                            .frame(width: 44, height: 44)
                        Circle()
                            .trim(from: 0, to: min(CGFloat(soon) / 10.0, 1.0))
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                        Text("\(soon)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }
            }

            // New episodes badge
            if let newEp = entry.payload?.newEpisodeCount, newEp > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                    Text("\(newEp) new episode\(newEp == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(14)
        .containerBackground(Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255), for: .widget)
    }
}

struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 0) {
                Text("Guide")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Stream")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255))
                Text("TV")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color(red: 0x5B/255, green: 0xB0/255, blue: 0xFF/255))
                    .baselineOffset(3.5)
                    .padding(.leading, 1)

                Spacer()

                if let updated = entry.payload?.lastUpdated {
                    Text(updated, style: .relative)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        + Text(" ago")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            // Section title
            HStack(spacing: 5) {
                Text("LEAVING SOON")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                if let count = entry.payload?.leavingSoon.count, count > 0 {
                    Text("· \(count) title\(count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // Leaving Soon rows
            if let items = entry.payload?.leavingSoon, !items.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(items.prefix(3))) { item in
                        HStack(spacing: 8) {
                            // Platform pill
                            Text(item.platform)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color(hex: item.platformColorHex) ?? .gray)
                                )

                            // Title
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Spacer()

                            // Days remaining badge
                            Text("\(item.daysRemaining)d")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.orange.opacity(0.15))
                                )
                        }
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Text("No titles leaving soon")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Add shows to your watchlist to get alerts")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            // Bottom stats bar
            HStack(spacing: 16) {
                StatBadge(label: "Watchlist", value: entry.payload?.watchlistCount ?? 0, color: .blue)
                StatBadge(label: "New Episodes", value: entry.payload?.newEpisodeCount ?? 0, color: Color(red: 0x00/255, green: 0x9E/255, blue: 0x8A/255))
            }
        }
        .padding(14)
        .containerBackground(Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255), for: .widget)
    }
}

struct LargeWidgetView: View {
    let entry: WidgetEntry

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 0) {
                Text("Guide")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Stream")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255))
                Text("TV")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(red: 0x5B/255, green: 0xB0/255, blue: 0xFF/255))
                    .baselineOffset(4.5)
                    .padding(.leading, 1)

                Spacer()

                Text("Leaving Soon")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            }

            // Stats row
            HStack(spacing: 16) {
                StatBadge(label: "Watchlist", value: entry.payload?.watchlistCount ?? 0, color: .blue)
                StatBadge(label: "New Eps", value: entry.payload?.newEpisodeCount ?? 0, color: Color(red: 0x00/255, green: 0x9E/255, blue: 0x8A/255))
                StatBadge(label: "Expiring", value: entry.payload?.leavingSoon.count ?? 0, color: .orange)
            }

            // Grid of leaving-soon titles
            if let items = entry.payload?.leavingSoon, !items.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(items.prefix(8))) { item in
                        LeavingSoonCard(item: item)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 4) {
                    Text("Nothing expiring soon")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Add shows to your watchlist to see what's leaving")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(16)
        .containerBackground(Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255), for: .widget)
    }
}

// MARK: - Shared subviews

struct StatBadge: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

struct LeavingSoonCard: View {
    let item: LeavingSoonItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Platform badge
            Text(item.platform)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: item.platformColorHex) ?? .gray)
                )

            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text("\(item.daysRemaining)d left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                Spacer()
                Text(item.expireDate)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Color hex helper

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Widget Definition

struct GuideStreamWidget: Widget {
    let kind: String = "GuideStreamWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetContainer(entry: entry)
        }
        .configurationDisplayName("Guide Stream TV")
        .description("See what's leaving your streaming services and keep tabs on your watchlist.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetContainer: View {
    @Environment(\.widgetFamily) var family
    let entry: WidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}
