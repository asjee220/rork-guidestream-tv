//
//  WatchingNowView.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit
import Supabase
import Auth

/// Onboarding step 4 — the "Seed Your List" show-picker. Loads top TV series
/// from the user's connected streaming services so they can tap every show
/// they follow. Selections are upserted into `user_streams` on continue.
struct WatchingNowView: View {
    let selectedServices: Set<String>
    let onContinue: ([UserStreamInsert]) -> Void
    let onSkip: () -> Void
    var onBack: () -> Void
    var onSkipAll: () -> Void
    let currentStep: Int
    let totalSteps: Int

    @State private var activeService: String = ""
    /// Selection keys are "owningServiceId|titleId" — never use activeService
    /// so picks made under "All" resolve correctly on continue.
    @State private var selections: Set<String> = []
    @State private var showsByService: [String: [TMDBResult]] = [:]
    /// Tracks which services have finished loading (for skeleton vs empty state).
    @State private var loadedServices: Set<String> = []
    @State private var isLoading = true

    private var totalSelected: Int { selections.count }

    /// Union of all shows across every loaded service, de-duplicated by show id,
    /// preserving popularity order via merge-sort across the per-service lists
    /// (each list is already popularity-desc from TMDB).
    private var allShows: [TMDBResult] {
        var seen = Set<Int>()
        var result: [TMDBResult] = []
        // Interleave: take one from each service in rotation so no single
        // service dominates the All view. Services are sorted for determinism.
        let sortedKeys = showsByService.keys.sorted()
        var indices: [String: Int] = [:]
        while true {
            var added = false
            for key in sortedKeys {
                let list = showsByService[key] ?? []
                var idx = indices[key, default: 0]
                while idx < list.count {
                    let show = list[idx]
                    idx += 1
                    indices[key] = idx
                    if seen.insert(show.id).inserted {
                        result.append(show)
                        added = true
                        break
                    }
                }
            }
            if !added { break }
        }
        return result
    }

    /// The list to render based on the active filter chip.
    private var displayShows: [TMDBResult] {
        if activeService.isEmpty {
            return allShows
        }
        return showsByService[activeService] ?? []
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            BrandBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    OnboardingHeader(currentStep: currentStep, totalSteps: totalSteps, onBack: onBack, onSkipAll: onSkipAll)

                    // Title section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What are you watching right now?")
                            .font(.custom("SF Pro Display", size: 24).weight(.bold))
                            .foregroundStyle(.white)
                        Text("We found top shows across your services — tap every one you follow.")
                            .font(.custom("SF Pro Text", size: 13))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                    // Value promises — quiet inline line, no chrome
                    promisesLine
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    // Filter rubric + service chips
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FILTER BY SERVICE")
                            .font(.custom("SF Pro Text", size: 10).weight(.semibold))
                            .tracking(1.1)
                            .foregroundStyle(Color.white.opacity(0.35))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        activeService = ""
                                    }
                                } label: {
                                    Text("All")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(activeService == "" ? .white : Color.textSecondary)
                                        .padding(.vertical, 7)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(activeService == "" ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .stroke(activeService == "" ? Color.white : Color.clear, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                ForEach(Array(selectedServices).sorted(), id: \.self) { serviceId in
                                    let svc = StreamingCatalog.service(for: serviceId)
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            activeService = serviceId
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if let svc {
                                                ServiceMiniIcon(service: svc, size: 18)
                                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                            }
                                            Text(svc?.name ?? serviceId.capitalized)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(activeService == serviceId ? .white : Color.textSecondary)
                                        }
                                        .padding(.vertical, 7)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(activeService == serviceId ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .stroke(activeService == serviceId ? Color.white : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 16)

                    // Show grid
                    if isLoading && displayShows.isEmpty {
                        // Skeletons while loading
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
                    } else if displayShows.isEmpty {
                        // Explicit empty state
                        emptyState
                            .padding(.horizontal, 20)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 8),
                                      GridItem(.flexible(), spacing: 8),
                                      GridItem(.flexible(), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(displayShows, id: \.id) { show in
                                // Find the owning service for this show.
                                // Under "All", a show may appear in multiple services;
                                // use the first service that contains it.
                                let owningService = activeService.isEmpty
                                    ? (showsByService.first { _, list in list.contains { $0.id == show.id } }?.key ?? "")
                                    : activeService
                                ShowPosterCard(
                                    show: show,
                                    serviceId: owningService,
                                    isSelected: selections.contains("\(owningService)|\(show.id)"),
                                    onTap: { toggleSelection(show: show, owningService: owningService) }
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
                    .foregroundStyle(Color.textSecondary)

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
                    .foregroundStyle(selections.isEmpty ? Color.white.opacity(0.35) : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        selections.isEmpty
                            ? AnyShapeStyle(Color.white.opacity(0.10))
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color.orange, Color.orange.opacity(0.85)],
                                startPoint: .top, endPoint: .bottom))
                    )
                    .clipShape(Capsule())
                    .shadow(color: selections.isEmpty ? .clear : Color.orange.opacity(0.45),
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
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                    Theme.surface
                }
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .task {
            // Use the shared provider map so the picker and home rails can't drift.
            let providerIdMap = StreamingCatalog.tmdbProviderIdMap
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
                        loadedServices.insert(service)
                    }
                }
            }
            await MainActor.run {
                // Default to "All" so the user sees the full union on load.
                activeService = ""
                isLoading = false
            }
        }
    }

    // MARK: - Selection

    private func toggleSelection(show: TMDBResult, owningService: String) {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        let key = "\(owningService)|\(show.id)"
        if selections.contains(key) {
            selections.remove(key)
        } else {
            selections.insert(key)
        }
    }

    private func buildInserts() -> [UserStreamInsert] {
        let userId = AuthViewModel.shared.currentUser?.id.uuidString
        let deviceId = DeviceIdentity.shared.deviceId
        return selections.compactMap { key -> UserStreamInsert? in
            let parts = key.split(separator: "|")
            guard parts.count == 2 else { return nil }
            let platform = String(parts[0])
            let titleId = String(parts[1])
            let show = showsByService[platform]?.first { String($0.id) == titleId }
            return UserStreamInsert(
                user_id: userId,
                device_id: deviceId,
                title_id: titleId,
                title: show?.displayName,
                poster_url: show?.posterUrl,
                platform: platform,
                is_tv: show?.isTV
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tv.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.white.opacity(0.3))
            Text(activeService.isEmpty
                 ? "No shows found for your services right now"
                 : "Nothing to show for \(StreamingCatalog.service(for: activeService)?.name ?? activeService.capitalized) right now")
                .font(.custom("SF Pro Text", size: 14).weight(.medium))
                .foregroundStyle(Color.textSecondary)
            Text("Try selecting different services, or skip to continue.")
                .font(.custom("SF Pro Text", size: 12))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Skeleton

    private var skeletonCard: some View {
        SkeletonCard()
    }
}

// MARK: - ShowPosterCard

private struct ShowPosterCard: View {
    let show: TMDBResult
    let serviceId: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let svc = StreamingCatalog.service(for: serviceId)
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    // Poster background
                    RemoteImage(urlString: show.posterUrl)
                        .aspectRatio(2.0 / 3.0, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    // Orange wash when selected
                    if isSelected {
                        Color.orange.opacity(0.15)
                    }

                    // Top-left service badge
                    VStack {
                        HStack {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(svc?.glow ?? Color.blue)
                                .frame(width: 13, height: 13)
                                .overlay(
                                    Text(svc != nil ? String((svc!.name).prefix(2)).uppercased() : serviceId.prefix(2).uppercased())
                                        .font(.system(size: 5, weight: .black))
                                        .foregroundStyle(.white)
                                )
                            Spacer()
                        }
                        .padding(.leading, 5)
                        .padding(.top, 5)
                        Spacer()
                    }

                    // Top-right selection check
                    VStack {
                        HStack {
                            Spacer()
                            if isSelected {
                                ZStack {
                                    Circle().fill(Color.orange)
                                        .frame(width: 18, height: 18)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold, design: .default))
                                        .foregroundStyle(.white)
                                }
                                .padding(5)
                            }
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

                // Title below poster
                Text(show.displayName)
                    .font(.system(size: 9, weight: .semibold, design: .default))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
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

private var promisesLine: some View {
        let items = ["Lands in My Watch List", "Instant episode alerts", "One-tap deep links"]
        var parts: [Text] = []
        for (i, item) in items.enumerated() {
            if i > 0 {
                parts.append(Text("  \u{00B7}  ").foregroundStyle(Color.white.opacity(0.18)))
            }
            parts.append(Text(Image(systemName: "checkmark")).foregroundStyle(Color.orange))
            parts.append(Text(" \(item)").foregroundStyle(Color.white.opacity(0.55)))
        }
        return parts.reduce(Text(""), +)
            .font(.custom("SF Pro Text", size: 11.5))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

#Preview {
    WatchingNowView(
        selectedServices: ["Netflix", "Max", "Paramount+"],
        onContinue: { _ in },
        onSkip: {},
        onBack: {},
        onSkipAll: {},
        currentStep: 2,
        totalSteps: 4
    )
    .preferredColorScheme(.dark)
}
