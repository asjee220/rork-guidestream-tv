//
//  GuideStreamWidget.swift
//  GuideStreamWidget
//
//  Shows the unified "Next Up" feed — live now, new for you, dropping soon,
//  and out now — across small, medium, and large widget families. All data
//  is read from the App Group shared container, written by the main app
//  whenever the home feed loads. Each row is tappable via a guidestream://
//  deep link that opens the app on that title's detail screen.
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
                items: [
                    WidgetFeedItem(id: "ph1", kind: "live", title: "Live Channel Demo", subtitle: "Just Chatting", badge: "Live now", platform: "TWITCH", platformColorHex: "#FF3B30", posterUrl: nil, deepLink: nil),
                    WidgetFeedItem(id: "ph2", kind: "new", title: "New Show Example", subtitle: "Season 3 just dropped", badge: "S3 E1", platform: "NETFLIX", platformColorHex: "#009E8A", posterUrl: nil, deepLink: nil),
                    WidgetFeedItem(id: "ph3", kind: "soon", title: "Coming Soon Demo", subtitle: "Arrives this week", badge: "in 3d", platform: "PRIME", platformColorHex: "#1A6FE8", posterUrl: nil, deepLink: nil),
                ],
                watchlistCount: 12,
                newEpisodeCount: 3,
                liveCount: 1,
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
        // Refresh every 30 minutes. The main app calls
        // WidgetCenter.shared.reloadTimelines() on every data change, so a
        // short interval here only burns the widget refresh budget.
        let nextUpdate = Date().addingTimeInterval(30 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Kind colours

private let kindLiveColor  = Color(red: 0xFF/255, green: 0x3B/255, blue: 0x30/255)
private let kindNewColor   = Color(red: 0x00/255, green: 0x9E/255, blue: 0x8A/255)
private let kindSoonColor  = Color(red: 0x1A/255, green: 0x6F/255, blue: 0xE8/255)
private let kindOutColor   = Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255)

private func kindColor(_ kind: String) -> Color {
    switch kind {
    case "live": return kindLiveColor
    case "new":  return kindNewColor
    case "soon": return kindSoonColor
    case "out":  return kindOutColor
    default:     return kindOutColor
    }
}

private func kindLabel(_ kind: String) -> String {
    switch kind {
    case "live": return "live now"
    case "new":  return "new for you"
    case "soon": return "dropping soon"
    case "out":  return "out now"
    default:     return "next up"
    }
}

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: WidgetEntry

    private var items: [WidgetFeedItem] { entry.payload?.items ?? [] }
    private var leadKind: String { items.first?.kind ?? "soon" }
    private var leadColor: Color { kindColor(leadKind) }

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

            // Total item count in a large bold numeral coloured by the lead kind
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(items.count)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(leadColor)
                    Text(kindLabel(leadKind))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }

            // Live indicator
            if let liveCount = entry.payload?.liveCount, liveCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(kindLiveColor)
                        .frame(width: 6, height: 6)
                        .modifier(PulsingDot())
                    Text("\(liveCount) live now")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(kindLiveColor)
                }
            }
        }
        .padding(14)
        .containerBackground(Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255), for: .widget)
        .widgetURL(items.first?.deepLink.flatMap { URL(string: $0) })
    }
}

struct MediumWidgetView: View {
    let entry: WidgetEntry

    private var items: [WidgetFeedItem] { entry.payload?.items ?? [] }
    private var leadKind: String { items.first?.kind ?? "soon" }
    private var eyebrowColor: Color { leadKind == "live" ? kindLiveColor : kindOutColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header — wordmark + NEXT UP eyebrow
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

                if let updated = entry.payload?.lastUpdated,
                   Date().timeIntervalSince(updated) < 24 * 60 * 60 {
                    Text(updated, style: .relative)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        + Text(" ago")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            // Eyebrow — NEXT UP with count suffix
            HStack(spacing: 5) {
                if leadKind == "live" {
                    Circle()
                        .fill(kindLiveColor)
                        .frame(width: 5, height: 5)
                }
                Text("NEXT UP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(eyebrowColor)
                if !items.isEmpty {
                    Text("· \(items.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // Rows — first 3 items
            if !items.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(items.prefix(3))) { item in
                        FeedRow(item: item)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Text("Nothing dropping right now")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Follow a show to fill this in")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            // Bottom stats bar
            HStack(spacing: 16) {
                StatBadge(label: "Watchlist", value: entry.payload?.watchlistCount ?? 0, color: .blue)
                StatBadge(label: "New Episodes", value: entry.payload?.newEpisodeCount ?? 0, color: kindNewColor)
            }
        }
        .padding(14)
        .containerBackground(Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255), for: .widget)
    }
}

struct LargeWidgetView: View {
    let entry: WidgetEntry

    private var items: [WidgetFeedItem] { entry.payload?.items ?? [] }
    private var leadKind: String { items.first?.kind ?? "soon" }
    private var eyebrowColor: Color { leadKind == "live" ? kindLiveColor : kindOutColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

                if leadKind == "live" {
                    Circle()
                        .fill(kindLiveColor)
                        .frame(width: 5, height: 5)
                }
                Text("NEXT UP")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(eyebrowColor)
                if !items.isEmpty {
                    Text("· \(items.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // Stats row
            HStack(spacing: 16) {
                StatBadge(label: "Watchlist", value: entry.payload?.watchlistCount ?? 0, color: .blue)
                StatBadge(label: "New Eps", value: entry.payload?.newEpisodeCount ?? 0, color: kindNewColor)
                if let liveCount = entry.payload?.liveCount, liveCount > 0 {
                    StatBadge(label: "Live", value: liveCount, color: kindLiveColor)
                }
            }

            // Rows — first 7 items as a vertical list
            if !items.isEmpty {
                VStack(spacing: 7) {
                    ForEach(Array(items.prefix(7))) { item in
                        FeedRow(item: item)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 4) {
                    Text("Nothing dropping right now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Follow a show to fill this in")
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

/// One feed row: 3pt wide rounded platform colour bar, title (12.5pt semibold
/// white, one line, truncated), spacer, badge (9.5pt bold in its kind colour
/// on a 13% opacity background of the same colour). Wrapped in a `Link` when
/// the item has a parseable deep link so tapping the row opens the app on
/// that title's detail screen.
struct FeedRow: View {
    let item: WidgetFeedItem

    private var badgeColor: Color { kindColor(item.kind) }

    var body: some View {
        Group {
            if let deepLink = item.deepLink, let url = URL(string: deepLink) {
                Link(destination: url) { rowContent }
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            // Platform colour bar — 3pt wide rounded rectangle
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(hex: item.platformColorHex) ?? badgeColor)
                .frame(width: 3, height: 18)

            // Title — 12.5pt semibold white, one line, truncated
            Text(item.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            // Badge — 9.5pt bold in kind colour on 13% opacity background
            Text(item.badge)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(badgeColor.opacity(0.13))
                )
                .lineLimit(1)
                .fixedSize()
        }
    }
}

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

/// Pulsing red dot for the small widget's live indicator.
struct PulsingDot: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
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
        .description("See what's live, what just dropped, and what's coming to your services.")
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
