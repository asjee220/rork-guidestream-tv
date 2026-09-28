//
//  MacMainView.swift
//  GuideStreamTVMac
//
//  The shell: a 200pt sidebar that collapses to a 76pt icon rail (⌃⌘S, or
//  the toggle in the top bar; the choice is remembered), a top bar, and the
//  current page. The wordmark becomes the app icon when collapsed.
//

import SwiftUI

enum MacPage: String, CaseIterable, Identifiable {
    case home, search, watchlist, reels, sports, schedule, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .watchlist: return "Watchlist"
        case .sports: return "Sports"
        case .reels: return "Reels"
        case .schedule: return "Schedule"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .watchlist: return "bookmark"
        case .sports: return "sportscourt"
        case .reels: return "play.rectangle"
        case .schedule: return "calendar"
        case .profile: return "person.crop.circle"
        }
    }

    var selectedIcon: String { self == .search || self == .schedule ? icon : icon + ".fill" }
}

struct MacMainView: View {
    @AppStorage("gs.mac.sidebarCollapsed") private var collapsed = false
    @State private var page: MacPage = .home
    @State private var openRef: MacTitleRef?
    @State private var showAsk = false
    @State private var openGameItem: TVSportsGame?
    @State private var openCreatorRef: MacCreatorRef?
    @State private var auth = AuthViewModel.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: collapsed ? MacLayout.railWidth : MacLayout.sidebarWidth)
            Divider().overlay(MacColor.hairline)
            VStack(spacing: 0) {
                topBar
                pageView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: collapsed)
        .environment(\.openTitle) { openRef = $0 }
        .environment(\.openGame) { openGameItem = $0 }
        .environment(\.openCreator) { openCreatorRef = MacCreatorRef(titleId: $0) }
        .sheet(item: $openRef) { ref in MacTitleSheet(ref: ref) }
        .sheet(item: $openGameItem) { game in MacGameSheet(game: game) }
        .sheet(item: $openCreatorRef) { ref in MacCreatorSheet(ref: ref) }
        .sheet(isPresented: $showAsk) { MacAskSheet(onOpenTitle: { openRef = $0 }) }
        .task {
            // Prewarm Reels behind Home, like the phone's trailer prefetch,
            // so the tab opens on a playable reel.
            try? await Task.sleep(for: .seconds(3))
            await TVReelsViewModel.shared.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: MacCommand.name)) { note in
            guard let value = note.object as? String else { return }
            if value == "sidebar" { collapsed.toggle() }
            else if value == "ask" { showAsk = true }
            else if value.hasPrefix("go:"), let p = MacPage(rawValue: String(value.dropFirst(3))) { page = p }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: collapsed ? .center : .leading, spacing: 4) {
            Group {
                if collapsed {
                    Image("AppMark")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(MacColor.hairline, lineWidth: 1))
                } else {
                    MacWordmark(size: 19).padding(.leading, 8)
                }
            }
            .frame(height: 40)
            .padding(.top, 34) // clears the traffic lights
            .padding(.bottom, 12)

            ForEach([MacPage.home, .search, .watchlist, .reels, .sports, .schedule]) { p in navRow(p) }

            Spacer()

            Button { showAsk = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold))
                    if !collapsed {
                        Text("Ask").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("⌘K").font(.system(size: 11, weight: .medium)).opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: collapsed ? 48 : .infinity)
                .background(MacColor.orange, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ask GuideStream (⌘K)")

            Button { page = .profile } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [MacColor.blue, Color(red: 0.36, green: 0.69, blue: 1)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text(auth.initials).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(width: 28, height: 28)
                    if !collapsed {
                        Text(auth.displayName ?? (auth.isGuest ? "Guest" : "Profile"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(page == .profile ? MacColor.orange : MacColor.text2)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Profile & services")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity)
        .background(MacColor.surface.opacity(0.92))
    }

    private func navRow(_ p: MacPage) -> some View {
        let selected = page == p
        return Button { page = p } label: {
            HStack(spacing: 11) {
                Image(systemName: selected ? p.selectedIcon : p.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                if !collapsed {
                    Text(p.title).font(.system(size: 13.5, weight: .medium))
                    Spacer()
                }
            }
            .foregroundStyle(selected ? MacColor.orange : MacColor.text2)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: collapsed ? 48 : .infinity)
            .background(selected ? MacColor.orange.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(p.title)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { collapsed.toggle() } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(collapsed ? MacColor.orange : MacColor.text2)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(collapsed ? "Expand sidebar (⌃⌘S)" : "Collapse sidebar (⌃⌘S)")

            Text(page.title).font(.system(size: 17, weight: .semibold))
            Spacer()
            servicesPill
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(MacColor.navy.opacity(0.72))
        .overlay(alignment: .bottom) { Rectangle().fill(MacColor.hairline).frame(height: 1) }
    }

    private var servicesPill: some View {
        let services = StreamingCatalog.ordered(from: auth.selectedServices)
        return Button { page = .profile } label: {
            HStack(spacing: -6) {
                ForEach(services.prefix(3)) { s in
                    TVServiceBrandMark(providerName: s.name, size: 24, catalogId: s.id)
                        .overlay(Circle().stroke(MacColor.navy, lineWidth: 2))
                }
                Text(services.isEmpty ? "Add services" : "\(services.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacColor.orange)
                    .padding(.leading, 14)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(MacColor.orange, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Your streaming services")
    }

    // MARK: - Pages

    @ViewBuilder private var pageView: some View {
        switch page {
        case .home: MacHomeView(onSearch: { page = .search })
        case .search: MacSearchView()
        case .watchlist: MacWatchlistView()
        case .reels: MacReelsView()
        case .sports: MacSportsView()
        case .schedule: MacScheduleView()
        case .profile: MacProfileView()
        }
    }
}
