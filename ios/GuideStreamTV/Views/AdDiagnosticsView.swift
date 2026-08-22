//
//  AdDiagnosticsView.swift
//  GuideStreamTV
//
//  Read-only inspector for the ad stack, reachable from Help & Feedback.
//  Exists so a TestFlight tester can tell us *why* ads aren't rendering
//  (consent blocked, SDK never started, no-fill, wrong ad unit) without a
//  cable and Console.app.
//

import SwiftUI
import UIKit

struct AdDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    /// Observed so counters and errors update live while the sheet is open.
    @ObservedObject private var adManager = AdManager.shared

    /// Bumped by the Refresh button to force a fresh snapshot read.
    @State private var refreshTick: Int = 0
    @State private var didCopy: Bool = false

    private var snapshot: AdDiagnostics {
        _ = refreshTick
        return adManager.diagnosticsSnapshot
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        summaryCard
                        statusCard
                        unitsCard
                        countersCard
                        errorsCard
                        actionsRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle("Ad Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.navy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.orange)
                }
            }
        }
    }

    // MARK: - Cards

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY")
                .scaledFont(size: 11, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)

            Text(snapshot.summary)
                .scaledFont(size: 14)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var statusCard: some View {
        section("PIPELINE") {
            DiagnosticRow(label: "SDK linked", state: snapshot.sdkLinked)
            DiagnosticRow(label: "SDK initialized", state: snapshot.didInitializeSDK)
            DiagnosticRow(label: "Startup in flight", value: snapshot.startInFlight ? "Yes" : "No")
            DiagnosticRow(label: "Consent status", value: snapshot.consentStatus)
            DiagnosticRow(label: "Can request ads", state: snapshot.canRequestAds)
            DiagnosticRow(label: "Privacy options required", value: snapshot.privacyOptionsRequired ? "Yes" : "No")
            DiagnosticRow(label: "Tracking authorization", value: snapshot.trackingAuthorization)
        }
    }

    private var unitsCard: some View {
        section("AD UNITS") {
            DiagnosticRow(label: "Native unit", value: snapshot.nativeAdUnitID, monospaced: true)
            DiagnosticRow(label: "From remote config", state: snapshot.remoteConfigHasNativeUnit)
            DiagnosticRow(label: "Interstitial unit", value: snapshot.interstitialAdUnitID, monospaced: true)
        }
    }

    private var countersCard: some View {
        section("THIS SESSION") {
            DiagnosticRow(label: "Native pool count", value: "\(snapshot.nativePoolCount)")
            DiagnosticRow(label: "Native load attempts", value: "\(snapshot.nativeLoadAttempts)")
            DiagnosticRow(label: "Native ads received", value: "\(snapshot.nativeAdsReceived)")
            DiagnosticRow(label: "Interstitial ready", state: snapshot.hasInterstitial)
        }
    }

    @ViewBuilder
    private var errorsCard: some View {
        if snapshot.lastNativeError != nil || snapshot.lastInterstitialError != nil {
            section("LAST ERRORS") {
                if let error = snapshot.lastNativeError {
                    DiagnosticRow(label: "Native", value: error, tint: Color(hex: "FF3B30"))
                }
                if let error = snapshot.lastInterstitialError {
                    DiagnosticRow(label: "Interstitial", value: error, tint: Color(hex: "FF3B30"))
                }
            }
        }
    }

    private var actionsRow: some View {
        VStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                adManager.retryFromDiagnostics()
                refreshTick += 1
            } label: {
                Text("Retry ad load")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange)
                    )
            }

            Button {
                UIPasteboard.general.string = snapshot.plainText
                didCopy = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Text(didCopy ? "Copied" : "Copy report")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.10))
                    )
            }

            Button {
                refreshTick += 1
            } label: {
                Text("Refresh")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .scaledFont(size: 11, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
    }
}

/// One label/value line in the diagnostics sheet. Boolean rows render a green
/// check or red cross so the failing stage is scannable at a glance.
private struct DiagnosticRow: View {
    let label: String
    var value: String?
    var state: Bool?
    var monospaced: Bool = false
    var tint: Color?

    init(label: String, value: String, monospaced: Bool = false, tint: Color? = nil) {
        self.label = label
        self.value = value
        self.state = nil
        self.monospaced = monospaced
        self.tint = tint
    }

    init(label: String, state: Bool) {
        self.label = label
        self.value = nil
        self.state = state
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .scaledFont(size: 13)
                .foregroundStyle(Color.textSecondary)

            Spacer(minLength: 12)

            if let state {
                Image(systemName: state ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(state ? Color(hex: "34C759") : Color(hex: "FF3B30"))
            } else if let value {
                Text(value)
                    .scaledFont(size: 13, weight: .medium)
                    .monospaced(monospaced)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(tint ?? Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
