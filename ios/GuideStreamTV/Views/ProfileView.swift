//
//  ProfileView.swift
//  GuideStreamTV
//
//  Main Profile tab. Hosts the avatar / stats header and a list of
//  navigation rows (Account, Connected Services, Devices, iOS Widget,
//  Notifications, Profiles, Help & Feedback, Sign Out). All destinations
//  live in `ProfileDestinations.swift` and are reached through the
//  enclosing `NavigationStack`.
//

import SwiftUI
import UIKit
import Auth

/// Type-safe routes the Profile stack can push onto.
enum ProfileRoute: Hashable {
    case account
    case watchList
    case connectedServices
    case devices
    case widget
    case notifications
    case profiles
    case help
}

/// Sheets the Profile root can present without pushing a destination.
enum ProfileSheet: String, Identifiable {
    case diagnostics
    var id: String { rawValue }
}

// MARK: - ProfileView

struct ProfileView: View {
    @State private var auth = AuthViewModel.shared
    @State private var stats = ProfileStatsService.shared
    @State private var streams = StreamsViewModel.shared
    @State private var probe = SupabaseSchemaProbe.shared
    @State private var path: [ProfileRoute] = []
    @State private var showSignOutConfirm: Bool = false
    @State private var isSigningOut: Bool = false
    @State private var activeSheet: ProfileSheet?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.navy.ignoresSafeArea()

                // Subtle atmosphere — matches the rest of the app.
                GeometryReader { geo in
                    Circle()
                        .fill(Color.blue.opacity(0.14))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 90)
                        .offset(x: -geo.size.width * 0.4, y: -geo.size.height * 0.3)
                    Circle()
                        .fill(Color.orange.opacity(0.08))
                        .frame(width: geo.size.width * 0.7)
                        .blur(radius: 80)
                        .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.55)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        title

                        if probe.hasIssues, probe.lastProbedAt != nil {
                            supabaseSetupBanner
                        }

                        avatarSection
                            .padding(.top, 4)

                        statsRow

                        primaryCard
                            .padding(.top, 4)

                        secondaryCard

                        signOutCard
                            .padding(.top, 4)

                        versionLabel
                            .padding(.top, 8)

                        // Floating tab bar safe area
                        Color.clear.frame(height: 110)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .tracksTabBarVisibility()
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .account: AccountView()
                case .watchList: WatchListView()
                case .connectedServices: ConnectedServicesView()
                case .devices: DevicesView()
                case .widget: WidgetSetupView()
                case .notifications: NotificationsSettingsView()
                case .profiles: ProfilesView()
                case .help: HelpFeedbackView()
                }
            }
        }
        .tint(Color.orange)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .diagnostics:
                SupabaseDiagnosticsView()
            }
        }
        .task {
            await stats.refresh()
            await streams.fetchUserStreams()
            if auth.isAuthenticated {
                await auth.loadDisplayName()
            }
            if probe.lastProbedAt == nil {
                await probe.probeAll()
            }
        }
        .refreshable {
            await stats.refresh()
            await streams.fetchUserStreams()
            await probe.probeAll()
        }
        .confirmationDialog(
            signOutTitle,
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button(signOutCTALabel, role: .destructive) {
                Task { await performSignOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(signOutMessage)
        }
    }

    // MARK: - Header

    private var title: some View {
        HStack {
            Text("Profile")
                .scaledFont(size: 30, weight: .heavy)
                .foregroundStyle(.white)
            Spacer()
        }
    }

    // MARK: - Supabase setup banner

    /// Loud, tappable banner shown when schema probes have detected missing
    /// tables, missing columns, or row-level-security policies blocking
    /// writes. Tapping opens the diagnostics sheet which contains the
    /// one-tap SQL fix.
    private var supabaseSetupBanner: some View {
        Button(action: openDiagnostics) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .scaledFont(size: 16, weight: .bold)
                        .foregroundStyle(Color.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Supabase setup needed")
                        .scaledFont(size: 14, weight: .heavy)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(bannerSubtitle)
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .scaledFont(size: 12, weight: .bold)
                    .foregroundStyle(Color.orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.orange.opacity(0.40), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Supabase setup needed. Open diagnostics.")
    }

    private var bannerSubtitle: String {
        let failing = probe.checks.filter { $0.read.isFailure || $0.write.isFailure }.count
        if failing == 0 {
            return "Tap to open Diagnostics and run the schema setup SQL."
        }
        return "\(failing) of \(probe.totalCount) tables aren't ready. Tap to fix in one step."
    }

    private func openDiagnostics() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activeSheet = .diagnostics
    }

    private var avatarSection: some View {
        VStack(spacing: 14) {
            AvatarRing(initials: initials, size: 112)
                .accessibilityLabel("Profile avatar for \(displayName)")

            Text(displayName)
                .scaledFont(size: 22, weight: .heavy)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subtitle = subtitleLine {
                Text(subtitle)
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats pills

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatPill(value: "\(stats.servicesCount)", label: stats.servicesCount == 1 ? "Service" : "Services")
            StatPill(value: "\(stats.showsCount)", label: stats.showsCount == 1 ? "Show" : "Shows")
            StatPill(value: hoursLabel, label: "Watched")
        }
        .frame(maxWidth: .infinity)
    }

    private var hoursLabel: String {
        let hours = stats.hoursWatched
        if hours >= 100 { return "\(Int(hours.rounded()))h" }
        if hours >= 10 { return "\(Int(hours.rounded()))h" }
        if hours <= 0 { return "0h" }
        return String(format: "%.1fh", hours)
    }

    // MARK: - Cards

    private var primaryCard: some View {
        ProfileCard {
            ProfileRow(
                icon: "person.fill",
                iconTint: Color.blue,
                title: "Account",
                subtitle: accountSubtitle,
                onTap: { path.append(.account) }
            )
            ProfileRowDivider()
            ProfileRow(
                icon: "bookmark.fill",
                iconTint: Color.orange,
                title: "Watch List",
                subtitle: watchListSubtitle,
                onTap: { path.append(.watchList) }
            )
            ProfileRowDivider()
            ProfileRow(
                icon: "tv.fill",
                iconTint: Color(red: 0.95, green: 0.55, blue: 0.20),
                title: "Connected Services",
                subtitle: "\(stats.servicesCount) service\(stats.servicesCount == 1 ? "" : "s") connected",
                onTap: { path.append(.connectedServices) }
            )
            ProfileRowDivider()
            ProfileRow(
                icon: "iphone",
                iconTint: Color(red: 0.55, green: 0.40, blue: 0.95),
                title: "Devices",
                subtitle: "\(stats.devicesCount) device\(stats.devicesCount == 1 ? "" : "s") registered",
                onTap: { path.append(.devices) }
            )
            ProfileRowDivider()
            ProfileRow(
                icon: "square.text.square.fill",
                iconTint: Color(red: 0.95, green: 0.78, blue: 0.20),
                title: "iOS Widget",
                subtitle: "Next episodes on your Home Screen",
                onTap: { path.append(.widget) }
            )
            ProfileRowDivider()
            ProfileRow(
                icon: "bell.fill",
                iconTint: Color(red: 0.95, green: 0.45, blue: 0.55),
                title: "Notifications",
                subtitle: "Manage alerts and updates",
                onTap: { path.append(.notifications) }
            )
        }
    }

    /// Subtitle for the Watch List row. Differs by auth state so guests get a
    /// nudge to sign in while signed-in users see a live count of saved items.
    private var watchListSubtitle: String {
        if !auth.isAuthenticated {
            return "Sign in to save shows, movies & games"
        }
        let count = streams.userStreams.count
        if count == 0 { return "Save shows, movies & games for tonight" }
        return "\(count) saved · shows, movies & games"
    }

    private var secondaryCard: some View {
        ProfileCard {
            ProfileRow(
                icon: "person.2.fill",
                iconTint: Color(red: 0.40, green: 0.75, blue: 1.0),
                title: "Profiles",
                subtitle: "Switch or manage profiles",
                onTap: { path.append(.profiles) }
            )
            ProfileRowDivider()
            ProfileRow(
                icon: "questionmark.circle.fill",
                iconTint: Color(red: 0.62, green: 0.70, blue: 0.82),
                title: "Help & Feedback",
                subtitle: "Get help or send feedback",
                onTap: { path.append(.help) }
            )
        }
    }

    private var signOutCard: some View {
        ProfileCard {
            ProfileRow(
                icon: signOutIcon,
                iconTint: signOutTint,
                title: signOutCTALabel,
                subtitle: "",
                trailingHidden: true,
                titleColor: signOutTint,
                onTap: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showSignOutConfirm = true
                }
            )
        }
        .opacity(isSigningOut ? 0.55 : 1)
        .allowsHitTesting(!isSigningOut)
    }

    private var versionLabel: some View {
        Text("Version \(appVersion) (Build \(buildNumber))")
            .scaledFont(size: 12)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Derived strings

    private var displayName: String {
        // Prefer the explicit cached display name first (covers manual edits),
        // then compose from first/last so users who only filled in those
        // two fields during email sign-up still get a real name.
        if let cached = auth.displayName, !cached.isEmpty { return cached }
        let parts = [auth.firstName ?? "", auth.lastName ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if let email = auth.currentUser?.email, let local = email.split(separator: "@").first {
            return Self.titleCase(String(local))
        }
        if auth.isGuest { return "Guest" }
        return "Your Profile"
    }

    private var subtitleLine: String? {
        if auth.isAuthenticated {
            return auth.currentUser?.email
        }
        if auth.isGuest {
            return "Signed in as Guest"
        }
        return nil
    }

    private var initials: String {
        Self.initials(
            firstName: auth.firstName,
            lastName: auth.lastName,
            fallbackName: displayName,
            isGuest: auth.isGuest,
            isAuthenticated: auth.isAuthenticated
        )
    }

    private var accountSubtitle: String {
        if auth.isAuthenticated { return "Manage your account settings" }
        if auth.isGuest { return "Sign in to sync across devices" }
        return "Sign in or create an account"
    }

    private var signOutIcon: String {
        auth.isAuthenticated ? "rectangle.portrait.and.arrow.right" : "arrow.right.circle.fill"
    }

    private var signOutTint: Color {
        auth.isAuthenticated ? Color(red: 0.96, green: 0.32, blue: 0.32) : Color.orange
    }

    private var signOutCTALabel: String {
        auth.isAuthenticated ? "Sign Out" : (auth.isGuest ? "Exit Guest Mode" : "Sign In")
    }

    private var signOutTitle: String {
        auth.isAuthenticated ? "Sign out of GuideStream TV?" : "Exit guest mode?"
    }

    private var signOutMessage: String {
        if auth.isAuthenticated {
            return "You'll need to sign back in to see your synced shows and watch history."
        }
        return "You'll be sent back to the welcome screen so you can create an account or sign in."
    }

    // MARK: - Actions

    private func performSignOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await auth.signOut()
    }

    // MARK: - Bundle info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Helpers

    /// Title-cases an email-derived username so "mark.anthony" becomes
    /// "Mark Anthony" rather than the lowercase raw form.
    static func titleCase(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return cleaned
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// First letter of first name + first letter of last name. Used as the
    /// avatar monogram everywhere. Falls back to splitting `fallbackName`
    /// when the structured first/last aren't available.
    static func initials(
        firstName: String?,
        lastName: String?,
        fallbackName: String,
        isGuest: Bool,
        isAuthenticated: Bool
    ) -> String {
        if !isAuthenticated && !isGuest { return "?" }
        let first = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty || !last.isEmpty {
            let f = first.first.map { String($0) } ?? ""
            let l = last.first.map { String($0) } ?? ""
            let combined = (f + l).uppercased()
            if !combined.isEmpty { return combined }
        }
        // Legacy fallback — derive from the joined display name.
        return initials(from: fallbackName, isGuest: isGuest, isAuthenticated: isAuthenticated)
    }

    /// Legacy entry point preserved so internal callers and tests don't
    /// break. New callers should use the firstName/lastName variant.
    static func initials(from name: String, isGuest: Bool, isAuthenticated: Bool) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isAuthenticated && !isGuest { return "?" }
        guard !trimmed.isEmpty else { return isGuest ? "G" : "?" }
        let parts = trimmed.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if parts.isEmpty {
            return String(trimmed.prefix(1)).uppercased()
        }
        if parts.count == 1 {
            return String(parts[0].prefix(2)).uppercased()
        }
        let first = parts[0].first.map { String($0) } ?? ""
        let second = parts[parts.count - 1].first.map { String($0) } ?? ""
        return (first + second).uppercased()
    }
}

// MARK: - AvatarRing

/// Circular avatar with an angular blue→pink gradient stroke. Shows the
/// user's initials inside on a dark navy fill — same treatment shown in
/// the profile mockups.
struct AvatarRing: View {
    let initials: String
    var size: CGFloat = 112
    var fontWeight: Font.Weight = .bold

    var body: some View {
        ZStack {
            // Soft glow halo so the ring pops on the dark background.
            Circle()
                .fill(
                    AngularGradient(
                        colors: ringColors,
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    )
                )
                .frame(width: size + 14, height: size + 14)
                .blur(radius: 18)
                .opacity(0.35)

            // Gradient outline
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: ringColors,
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    lineWidth: 3
                )
                .frame(width: size, height: size)

            // Inner dark fill
            Circle()
                .fill(Color(red: 0.05, green: 0.07, blue: 0.12))
                .frame(width: size - 10, height: size - 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )

            // Initials
            Text(initials)
                .scaledFont(size: size * 0.34, weight: fontWeight)
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
        .frame(width: size + 14, height: size + 14)
    }

    private var ringColors: [Color] {
        [
            Color(red: 0.46, green: 0.55, blue: 1.00), // blue
            Color(red: 0.60, green: 0.42, blue: 0.96), // violet
            Color(red: 0.96, green: 0.38, blue: 0.72), // pink
            Color(red: 0.96, green: 0.52, blue: 0.50), // coral
            Color(red: 0.46, green: 0.55, blue: 1.00)  // loop back to blue
        ]
    }
}

// MARK: - StatPill

private struct StatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            Text("\(value) \(label)")
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - ProfileCard

/// Grouped-row container with the same glassy look used across the app.
struct ProfileCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 22))
    }
}

/// Inline hairline used between rows inside a `ProfileCard`. Indented to
/// align with the row text — the icon column is left clean so the divider
/// flows like a settings list.
struct ProfileRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 66)
    }
}

// MARK: - ProfileRow

/// Single tappable settings row. Supports an icon, title, optional subtitle,
/// and a chevron. Used for every entry in the Profile screen and reused on
/// some destinations as well.
struct ProfileRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String
    var trailingHidden: Bool = false
    var titleColor: Color = Color.white
    let onTap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                    Image(systemName: icon)
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(iconTint)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if !trailingHidden {
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProfileRowButtonStyle())
    }

    private func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap()
    }
}

struct ProfileRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.white.opacity(0.04) : Color.clear
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.navy.ignoresSafeArea()
        ProfileView()
    }
    .preferredColorScheme(.dark)
}
