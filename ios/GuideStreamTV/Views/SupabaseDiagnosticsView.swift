//
//  SupabaseDiagnosticsView.swift
//  GuideStreamTV
//

import SwiftUI
import Auth

/// In-app debugging surface for the analytics pipeline. Shows the device id,
/// auth state, recent Supabase write errors, and lets the user fire a test
/// event so they can confirm rows are actually landing in their Supabase
/// `watch_intent_events` table.
struct SupabaseDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared
    @State private var logger = WatchIntentLogger.shared
    @State private var testStatus: TestStatus = .idle
    @State private var copyFlash: Bool = false

    private let deviceId: String = DeviceIdentity.shared.deviceId
    private let supabaseHost: String = SupabaseConfig.url

    enum TestStatus: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard
                    actionsCard
                    errorsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Identity")

            row(
                label: "Device ID",
                value: deviceId,
                monospaced: true,
                copyable: true
            )
            row(
                label: "Auth state",
                value: authStateLabel,
                tint: auth.isAuthenticated ? Theme.blue : (auth.isGuest ? Theme.orange : Color.white.opacity(0.65))
            )
            if let userId = auth.currentUser?.id.uuidString {
                row(
                    label: "User ID",
                    value: userId,
                    monospaced: true,
                    copyable: true
                )
            }
            if let email = auth.currentUser?.email, !email.isEmpty {
                row(label: "Email", value: email)
            }

            Divider().background(Color.white.opacity(0.08))

            sectionTitle("Supabase")
            row(label: "Project", value: supabaseHost, monospaced: true)
            row(label: "Attempts", value: "\(logger.totalAttempts)")
            row(
                label: "Successes",
                value: "\(logger.totalSuccesses)",
                tint: logger.totalSuccesses > 0 ? Color.green : Color.white.opacity(0.6)
            )
            row(
                label: "Failures",
                value: "\(logger.totalAttempts - logger.totalSuccesses)",
                tint: (logger.totalAttempts - logger.totalSuccesses) > 0 ? Color.red.opacity(0.9) : Color.white.opacity(0.6)
            )
        }
        .padding(18)
        .background(cardBackground)
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Test write")

            Text("Send a `diagnostic_ping` row to `watch_intent_events`. If it fails, the error appears below — most often this is an RLS policy blocking inserts.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                runTestPing()
            } label: {
                HStack(spacing: 8) {
                    if testStatus == .running {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: testStatusIcon)
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(testButtonLabel)
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(testButtonBackground)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(testStatus == .running)

            if case .failure(let message) = testStatus {
                Text(message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if case .success = testStatus {
                Text("Row inserted successfully. Check your Supabase table.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.green.opacity(0.9))
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    // MARK: - Errors

    private var errorsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Recent errors")
                Spacer()
                if !logger.recentErrors.isEmpty {
                    Text("\(logger.recentErrors.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(0.8)))
                }
            }

            if logger.recentErrors.isEmpty {
                Text("No failed writes captured. If you still don't see rows, double-check the Supabase RLS policies on `watch_intent_events`.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(logger.recentErrors) { err in
                    errorRow(err)
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private func errorRow(_ err: LoggerError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(err.eventType)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.orange)
                Spacer()
                Text(timeAgo(err.timestamp))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Text(err.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    private func runTestPing() {
        testStatus = .running
        Task {
            let error = await WatchIntentLogger.shared.logTestEvent()
            if let error {
                testStatus = .failure(error)
            } else {
                testStatus = .success
            }
        }
    }

    private var authStateLabel: String {
        if auth.isAuthenticated { return "Signed in" }
        if auth.isGuest { return "Guest" }
        return "Not signed in"
    }

    private var testStatusIcon: String {
        switch testStatus {
        case .idle: return "paperplane.fill"
        case .running: return "hourglass"
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    private var testButtonLabel: String {
        switch testStatus {
        case .idle: return "Send test event"
        case .running: return "Sending…"
        case .success: return "Sent — send another"
        case .failure: return "Retry test event"
        }
    }

    private var testButtonBackground: some ShapeStyle {
        switch testStatus {
        case .success:
            return AnyShapeStyle(Color.green.opacity(0.85))
        case .failure:
            return AnyShapeStyle(Color.red.opacity(0.85))
        default:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Theme.orange, Theme.orange.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Color.white.opacity(0.5))
    }

    private func row(
        label: String,
        value: String,
        monospaced: Bool = false,
        copyable: Bool = false,
        tint: Color = .white
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 88, alignment: .leading)
            if monospaced {
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(tint)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .truncationMode(.middle)
            } else {
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                    copyFlash = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copyFlash = false
                    }
                } label: {
                    Image(systemName: copyFlash ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func timeAgo(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3600))h ago"
    }
}

#Preview {
    SupabaseDiagnosticsView()
}
