//
//  TVSchemeDiagnosticView.swift
//  GuideStreamTVTV
//
//  TEMPORARY throwaway QA screen. Tests the exact deep-link URLs
//  TVOSDeepLinker.resolve produces for each of the twelve streaming
//  services, and lets a tester open each URL in isolation via
//  UIApplication.shared.open — no openChain, no isLaunchable filtering.
//  Remove after testing.
//

import SwiftUI
import UIKit

struct TVSchemeDiagnosticView: View {

    struct DiagnosticRow: Identifiable {
        let id: String
        let serviceName: String
        let serviceColor: Color
        var titleName: String?
        var contentURLString: String?
        var playURL: URL?
        var appHomeURL: URL?
        var unavailableReason: String?
        var openAppResult: Bool?
        var playTitleResult: Bool?
    }

    @State private var rows: [DiagnosticRow] = []
    @State private var isLoading: Bool = false
    @Environment(\.dismiss) private var dismiss

    /// Duplicated from TVHomeView.swift so TVHomeView is not modified.
    private let tmdbProviderIdMap: [String: Int] = [
        "netflix": 8,
        "prime": 9,
        "disney": 337,
        "max": 1899,
        "hulu": 15,
        "appletv": 350,
        "paramount": 2303,
        "peacock": 386,
        "starz": 43,
        "showtime": 37,
        "crunchyroll": 283,
        "youtube": 192,
    ]

    var body: some View {
        ZStack {
            TVTheme.backgroundGradient

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if isLoading && rows.isEmpty {
                        HStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Resolving titles for all 12 services\u{2026}")
                                .font(.system(size: 20))
                                .foregroundStyle(TVTheme.textSecondary)
                        }
                        .padding(.horizontal, 80)
                    }

                    ForEach($rows) { $row in
                        rowView(for: $row)
                    }

                    Color.clear.frame(height: 60)
                }
                .padding(.bottom, 40)
            }
        }
        .task { await loadAll() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scheme Diagnostics")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.white)
                Text("Throwaway QA — each button calls UIApplication.shared.open once, no fallback.")
                    .font(.system(size: 16))
                    .foregroundStyle(TVTheme.textTertiary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.card)
        }
        .padding(.horizontal, 80)
        .padding(.top, 24)
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(for row: Binding<DiagnosticRow>) -> some View {
        let r = row.wrappedValue

        VStack(alignment: .leading, spacing: 14) {
            // Service name
            HStack(spacing: 12) {
                Circle()
                    .fill(r.serviceColor)
                    .frame(width: 14, height: 14)
                Text(r.serviceName)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
            }

            if let reason = r.unavailableReason {
                Text(reason)
                    .font(.system(size: 16))
                    .foregroundStyle(TVTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Title: \(r.titleName ?? "\u{2014}")")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TVTheme.textPrimary)
                    .lineLimit(2)

                urlLabel("contentURL", r.contentURLString)
                urlLabel("playURL", r.playURL?.absoluteString)
                urlLabel("appHomeURL", r.appHomeURL?.absoluteString)

                HStack(spacing: 20) {
                    Button {
                        openURL(r.appHomeURL, binding: row, keyPath: \.openAppResult)
                    } label: {
                        resultButtonLabel("Open app", result: r.openAppResult, enabled: r.appHomeURL != nil)
                    }
                    .buttonStyle(.card)
                    .disabled(r.appHomeURL == nil)

                    Button {
                        openURL(r.playURL, binding: row, keyPath: \.playTitleResult)
                    } label: {
                        resultButtonLabel("Play title", result: r.playTitleResult, enabled: r.playURL != nil)
                    }
                    .buttonStyle(.card)
                    .disabled(r.playURL == nil)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TVTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TVTheme.hairline, lineWidth: 1)
                }
        )
        .padding(.horizontal, 80)
    }

    // MARK: - URL label

    @ViewBuilder
    private func urlLabel(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label):")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TVTheme.textTertiary)
            Text(value ?? "nil")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(value != nil ? TVTheme.blue : TVTheme.textTertiary)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }

    // MARK: - Button label

    @ViewBuilder
    private func resultButtonLabel(_ title: String, result: Bool?, enabled: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(enabled ? .white : TVTheme.textTertiary)
            if let result {
                Text(result ? "PASS" : "FAIL")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(result ? Color.green : Color.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(result ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    )
            }
        }
    }

    // MARK: - Open URL (direct, no openChain)

    private func openURL(
        _ url: URL?,
        binding: Binding<DiagnosticRow>,
        keyPath: WritableKeyPath<DiagnosticRow, Bool?>
    ) {
        guard let url else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            binding.wrappedValue[keyPath: keyPath] = success
        }
    }

    // MARK: - Loading

    private func loadAll() async {
        isLoading = true
        rows = []
        let allServices = StreamingCatalog.all
        let allIds = allServices.map(\.id)

        for service in allServices {
            var row = DiagnosticRow(
                id: service.id,
                serviceName: service.name,
                serviceColor: service.color,
                titleName: nil,
                contentURLString: nil,
                playURL: nil,
                appHomeURL: nil,
                unavailableReason: nil
            )

            guard let providerId = tmdbProviderIdMap[service.id] else {
                row.unavailableReason = "No TMDB provider id mapped for \u{201c}\(service.id)\u{201d}"
                rows.append(row)
                continue
            }

            let popular = await TVTMDBService.shared.getPopularOnService(tmdbProviderId: providerId)
            guard let firstResult = popular.first else {
                row.unavailableReason = "getPopularOnService(providerId: \(providerId)) returned no results"
                rows.append(row)
                continue
            }

            row.titleName = firstResult.displayName

            let resolved = await TVWatchmodeResolver.shared.resolve(
                tmdbId: firstResult.id,
                isTV: true,
                season: nil,
                episode: nil,
                subscribedServices: allIds,
                episodePlatformHint: nil
            )

            guard let resolved else {
                row.unavailableReason = "TVWatchmodeResolver returned nil for tmdbId \(firstResult.id)"
                rows.append(row)
                continue
            }

            // Find the source matching this service by catalog id.
            let matchingSource = resolved.usSources.first { source in
                Platform.from(providerName: source.name)?.catalogId == service.id
            } ?? resolved.primarySource.flatMap { primary in
                guard Platform.from(providerName: primary.name)?.catalogId == service.id else { return nil as TVWatchmodeResolver.TVResolvedSource? }
                return primary
            }

            guard let source = matchingSource else {
                let names = resolved.usSources.map(\.name).joined(separator: ", ")
                row.unavailableReason = "No resolved source matching \u{201c}\(service.name)\u{201d}. Sources: [\(names)]"
                rows.append(row)
                continue
            }

            let contentURL = source.webUrl.flatMap { URL(string: $0) }
            row.contentURLString = source.webUrl ?? "nil"

            let target = TVOSDeepLinker.resolve(
                platform: source.name,
                title: firstResult.displayName,
                contentURL: contentURL
            )

            row.playURL = target.playURL
            row.appHomeURL = target.appHomeURL

            if target.playURL == nil && target.appHomeURL == nil {
                row.unavailableReason = "TVOSDeepLinker.resolve returned nil for both playURL and appHomeURL"
            }

            rows.append(row)
        }

        isLoading = false
    }
}
