//
//  WatchingNowView.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit

/// Onboarding step 4 — the "Seed Your List" show-picker. Loads top TV series
/// from the user's connected streaming services so they can tap every show
/// they follow. Selections are upserted into `user_streams` on continue.
struct WatchingNowView: View {
    let selectedServices: Set<String>
    let onContinue: ([UserStreamInsert]) -> Void
    let onSkip: () -> Void

    @State private var activeService: String = ""
    @State private var selections: Set<String> = [] // "platform|titleId"
    @State private var showsByService: [String: [TMDBResult]] = [:]
    @State private var isLoading = true

    private var totalSelected: Int { selections.count }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.navy.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    OnboardingHeader(progress: 1.0)

                    // Title section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What are you watching?")
                            .font(.custom("SF Pro Display", size: 24).weight(.bold))
                            .foregroundStyle(.white)
                        Text("Tap every show you follow — we'll alert you the moment new episodes drop")
                            .font(.custom("SF Pro Text", size: 13))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                    // Service tab bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedServices.sorted(), id: \.self) { service in
                                serviceTab(service)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 16)

                    // Show grid
                    if isLoading {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 8),
                                      GridItem(.flexible(), spacing: 8),
                                      GridItem(.flexible(), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(0..<6, id: \.self) { _ in
                                skeletonCard
                            }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 8),
                                      GridItem(.flexible(), spacing: 8),
                                      GridItem(.flexible(), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(showsByService[activeService] ?? [], id: \.id) { show in
                                ShowPosterCard(
                                    show: show,
                                    platform: activeService,
                                    isSelected: selections.contains("\(activeService)|\(show.id)"),
                                    brandColor: serviceBrandColor(activeService),
                                    onTap: { toggleSelection(show: show) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Bottom spacer to clear sticky bar
                    Color.clear.frame(height: 90)
                }
            }

            // Sticky bottom bar
            VStack(spacing: 10) {
                Text("\(totalSelected) show\(totalSelected == 1 ? "" : "s") selected")
                    .font(.custom("SF Pro Text", size: 12))
                    .foregroundStyle(Color.orange)

                Button {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    onContinue(buildInserts())
                } label: {
                    HStack(spacing: 8) {
                        Text("Add to My List")
                            .font(.custom("SF Pro Text", size: 16).weight(.bold))
                        Image(systemName: "arrow.right")
                            .scaledFont(size: 14, weight: .bold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .opacity(selections.isEmpty ? 0.4 : 1.0)
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.orange.opacity(selections.isEmpty ? 0.0 : 0.45),
                            radius: 24, x: 0, y: 0)
                }
                .buttonStyle(.plain)
                .disabled(selections.isEmpty)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.custom("SF Pro Text", size: 14).weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.navy.opacity(0), Color.navy],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 28)
                    Color.navy
                }
            )
        }
        .task {
            let providerIdMap: [String: Int] = [
                "Netflix": 8,
                "Hulu": 15,
                "Paramount+": 531,
                "Max": 1899,
                "HBO Max": 1899,
                "Disney+": 337,
                "Apple TV+": 350,
                "Peacock": 386,
                "Prime Video": 9
            ]
            await withTaskGroup(of: (String, [TMDBResult]).self) { group in
                for service in selectedServices {
                    group.addTask {
                        guard let providerId = providerIdMap[service] else { return (service, []) }
                        do {
                            let results = try await TMDBService.shared.discoverByProvider(providerId: providerId)
                            return (service, results)
                        } catch {
                            print("[GuideStream] TMDB discoverByProvider failed for \(service): \(error)")
                            return (service, [])
                        }
                    }
                }
                for await (service, results) in group {
                    await MainActor.run {
                        showsByService[service] = results
                    }
                }
            }
            await MainActor.run {
                activeService = selectedServices.sorted().first ?? ""
                isLoading = false
            }
        }
    }

    // MARK: - Selection

    private func toggleSelection(show: TMDBResult) {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        let key = "\(activeService)|\(show.id)"
        if selections.contains(key) {
            selections.remove(key)
        } else {
            selections.insert(key)
        }
    }

    private func buildInserts() -> [UserStreamInsert] {
        let userId = AuthViewModel.shared.currentUserId
        return selections.compactMap { key -> UserStreamInsert? in
            let parts = key.split(separator: "|")
            guard parts.count == 2 else { return nil }
            let platform = String(parts[0])
            let titleId = String(parts[1])
            let show = showsByService[platform]?.first { String($0.id) == titleId }
            return UserStreamInsert(
                user_id: userId,
                title_id: titleId,
                title: show?.displayName,
                poster_url: show?.posterUrl,
                platform: platform
            )
        }
    }

    // MARK: - Helpers

    private func serviceShortName(_ name: String) -> String {
        switch name {
        case "Paramount+": return "Paramount+"
        case "Apple TV+": return "Apple TV+"
        case "Disney+": return "Disney+"
        default: return name
        }
    }

    private func serviceBrandColor(_ name: String) -> Color {
        switch name {
        case "Netflix": return Color(hex: "E50914")
        case "Paramount+": return Color(hex: "0064FF")
        case "Max": return Color(hex: "5822B4")
        case "Hulu": return Color(hex: "1CE783")
        case "Disney+": return Color(hex: "0B3D91")
        case "Apple TV+": return .black
        case "Peacock": return Color(hex: "F5821F")
        default: return .blue
        }
    }

    private func serviceBrandAbbreviation(_ name: String) -> String {
        switch name {
        case "Netflix": return "N"
        case "Paramount+": return "P+"
        case "Max": return "MAX"
        case "Hulu": return "H"
        case "Disney+": return "D+"
        case "Apple TV+": return "TV+"
        case "Peacock": return "P"
        default: return String(name.prefix(1))
        }
    }

    // MARK: - Service tab

    private func serviceTab(_ service: String) -> some View {
        let isActive = activeService == service
        let color = serviceBrandColor(service)
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                activeService = service
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(serviceShortName(service))
                    .font(.custom("SF Pro Text", size: 12).weight(.semibold))
                    .foregroundStyle(isActive ? .white : Color.textSecondary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(isActive ? color : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Skeleton

    private var skeletonCard: some View {
        SkeletonCard()
    }
}

// MARK: - ShowPosterCard

private struct ShowPosterCard: View {
    let show: TMDBResult
    let platform: String
    let isSelected: Bool
    let brandColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Poster background
                RemoteImage(urlString: show.posterUrl)
                    .aspectRatio(2.0 / 3.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                // Bottom gradient overlay
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [Color.black.opacity(0.9), Color.clear],
                        startPoint: .bottom, endPoint: .top
                    )
                    .frame(height: 55) // relative, handled by aspect ratio
                }

                // Bottom-left service badge
                VStack {
                    Spacer()
                    HStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(brandColor)
                            .frame(width: 13, height: 13)
                            .overlay(
                                Text(serviceAbbreviation(platform))
                                    .font(.system(size: 5, weight: .bold, design: .default))
                                    .foregroundStyle(.white)
                            )
                        Spacer()
                    }
                    .padding(.leading, 5)
                    .padding(.bottom, 5)
                }

                // Bottom text
                VStack {
                    Spacer()
                    Text(show.displayName)
                        .font(.system(size: 9, weight: .bold, design: .default))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 5)
                        .padding(.bottom, 5)
                }

                // Top-right selection checkmark
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(isSelected ? Color.orange : Color.clear)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.5), lineWidth: 1.5)
                                )
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold, design: .default))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(5)
                    }
                    Spacer()
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func serviceAbbreviation(_ name: String) -> String {
        switch name {
        case "Netflix": return "N"
        case "Paramount+": return "P+"
        case "Max": return "MAX"
        case "Hulu": return "H"
        case "Disney+": return "D+"
        case "Apple TV+": return "TV+"
        case "Peacock": return "P"
        default: return String(name.prefix(1))
        }
    }
}

// MARK: - SkeletonCard

private struct SkeletonCard: View {
    @State private var opacity: Double = 0.08

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    opacity = 0.18
                }
            }
    }
}

#Preview {
    WatchingNowView(
        selectedServices: ["Netflix", "Max", "Paramount+"],
        onContinue: { _ in },
        onSkip: {}
    )
    .preferredColorScheme(.dark)
}
