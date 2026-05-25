//
//  SupabaseDiagnosticsView.swift
//  GuideStreamTV
//
//  Self-service diagnostics screen. Auto-runs schema probes on appear so the
//  user can see *exactly* which Supabase tables are missing, which RLS
//  policies are blocking writes, and which columns the live schema lacks —
//  plus a single copy-paste SQL script that provisions the whole thing.
//

import SwiftUI
import Auth

struct SupabaseDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared
    @State private var logger = WatchIntentLogger.shared
    @State private var session = DeviceSessionService.shared
    @State private var probe = SupabaseSchemaProbe.shared
    @State private var testStatus: TestStatus = .idle
    @State private var sessionStatus: TestStatus = .idle
    @State private var copyFlash: Bool = false
    @State private var sqlCopied: Bool = false

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
                    if probe.hasIssues || probe.lastProbedAt == nil {
                        setupCallout
                    } else {
                        successCallout
                    }
                    schemaCard
                    setupSQLCard
                    summaryCard
                    deviceSessionCard
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
        .task {
            if probe.lastProbedAt == nil {
                await probe.probeAll()
            }
        }
    }

    // MARK: - Callouts

    private var setupCallout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.orange)
                Text("Supabase setup needed")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
            }
            Text("Your Supabase project is rejecting writes — either the tables don't exist, columns are missing, or row-level-security policies are blocking inserts. Tap **Copy SQL** below, paste it into the Supabase SQL Editor, click Run, then come back and tap **Re-test**.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.80))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.orange.opacity(0.4), lineWidth: 1)
        )
    }

    private var successCallout: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("All tables online")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("Reads & writes are landing in Supabase.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Schema status

    private var schemaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Schema status")
                Spacer()
                Button(action: rerunProbe) {
                    HStack(spacing: 6) {
                        if probe.isProbing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(probe.isProbing ? "Testing…" : "Re-test")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.orange))
                }
                .buttonStyle(.plain)
                .disabled(probe.isProbing)
            }

            HStack(spacing: 6) {
                Text("\(probe.passingCount) of \(probe.totalCount) tables ready")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                if let date = probe.lastProbedAt {
                    Text("· \(timeAgo(date))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }

            VStack(spacing: 8) {
                ForEach(probe.checks) { check in
                    schemaRow(check)
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    @ViewBuilder
    private func schemaRow(_ check: SupabaseSchemaProbe.TableCheck) -> some View {
        let combined = combinedState(read: check.read, write: check.write, writeProbe: check.writeProbe)
        HStack(alignment: .top, spacing: 12) {
            statusBadge(state: combined)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(check.name)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(statusLabel(state: combined))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusTint(combined))
                }
                Text(check.purpose)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = detailMessage(read: check.read, write: check.write) {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - SQL setup card

    private var setupSQLCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("One-tap fix")
                Spacer()
                Text("SQL")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.orange.opacity(0.18)))
                    .foregroundStyle(Theme.orange)
            }

            Text("This script creates every missing table, adds any missing columns, and installs the row-level-security policies the app needs. Safe to re-run.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.vertical) {
                Text(SupabaseSetupSQL.script)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 220)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button(action: copySQL) {
                    HStack(spacing: 8) {
                        Image(systemName: sqlCopied ? "checkmark" : "doc.on.doc.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(sqlCopied ? "Copied" : "Copy SQL")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        LinearGradient(
                            colors: sqlCopied
                                ? [Color.green, Color.green.opacity(0.85)]
                                : [Theme.orange, Theme.orange.opacity(0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: openSQLEditor) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Open Editor")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            instructionsRow
        }
        .padding(18)
        .background(cardBackground)
    }

    private var instructionsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            instructionLine(num: 1, text: "Tap **Copy SQL** above.")
            instructionLine(num: 2, text: "Tap **Open Editor** to launch the Supabase SQL Editor.")
            instructionLine(num: 3, text: "Paste (⌘V), then click **Run**.")
            instructionLine(num: 4, text: "Come back here and tap **Re-test** at the top.")
        }
        .padding(.top, 6)
    }

    private func instructionLine(num: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(num)")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.orange.opacity(0.7)))
            Text(.init(text))
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
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

    // MARK: - Device session

    private var deviceSessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Device session row")

            Text("One row per install in `device_sessions`, keyed on `device_id`. Updated on launch, sign-in/out, onboarding, and any service or notification change — the guest \"profile\" equivalent.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            row(label: "Session #", value: "\(session.sessionCount)")
            row(
                label: "Upserts",
                value: "\(session.totalSuccesses) / \(session.totalUpserts)",
                tint: session.totalSuccesses > 0 ? Color.green : Color.white.opacity(0.6)
            )
            if let reason = session.lastReason {
                row(label: "Last reason", value: reason)
            }
            if let lastSuccess = session.lastSuccessAt {
                row(
                    label: "Last ok",
                    value: timeAgo(lastSuccess),
                    tint: Color.green.opacity(0.9)
                )
            }
            if let lastError = session.lastError {
                Text(lastError)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                runSessionSync()
            } label: {
                HStack(spacing: 8) {
                    if sessionStatus == .running {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: sessionStatusIcon)
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(sessionButtonLabel)
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(sessionButtonBackground)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sessionStatus == .running)
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

    private func runSessionSync() {
        sessionStatus = .running
        Task {
            let error = await DeviceSessionService.shared.upsertNowReturningError(
                reason: "diagnostic"
            )
            if let error {
                sessionStatus = .failure(error)
            } else {
                sessionStatus = .success
            }
        }
    }

    private func rerunProbe() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await probe.probeAll() }
    }

    private func copySQL() {
        UIPasteboard.general.string = SupabaseSetupSQL.script
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            sqlCopied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { sqlCopied = false }
            }
        }
    }

    private func openSQLEditor() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let url = SupabaseSetupSQL.sqlEditorURL() {
            UIApplication.shared.open(url)
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

    private var sessionStatusIcon: String {
        switch sessionStatus {
        case .idle: return "arrow.triangle.2.circlepath"
        case .running: return "hourglass"
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    private var sessionButtonLabel: String {
        switch sessionStatus {
        case .idle: return "Sync device row"
        case .running: return "Syncing…"
        case .success: return "Synced — sync again"
        case .failure: return "Retry sync"
        }
    }

    private var sessionButtonBackground: some ShapeStyle {
        switch sessionStatus {
        case .success:
            return AnyShapeStyle(Color.green.opacity(0.85))
        case .failure:
            return AnyShapeStyle(Color.red.opacity(0.85))
        default:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Theme.blue, Theme.blue.opacity(0.85)],
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

    // MARK: - Schema state helpers

    /// Reduces the read+write state pair into a single status for the row.
    /// Write failure dominates because a missing insert policy is the most
    /// common (and most user-impacting) issue.
    private func combinedState(
        read: SupabaseSchemaProbe.CheckState,
        write: SupabaseSchemaProbe.CheckState,
        writeProbe: Bool
    ) -> SupabaseSchemaProbe.CheckState {
        if writeProbe, case .ok = read, case .ok = write { return .ok }
        if !writeProbe, case .ok = read { return .ok }
        if case .tableMissing = read { return .tableMissing }
        if case .tableMissing = write { return .tableMissing }
        if case .columnMissing(let c) = write { return .columnMissing(c) }
        if case .columnMissing(let c) = read { return .columnMissing(c) }
        if case .rlsBlocked = write { return .rlsBlocked }
        if case .rlsBlocked = read { return .rlsBlocked }
        if case .error(let m) = write { return .error(m) }
        if case .error(let m) = read { return .error(m) }
        if case .checking = read { return .checking }
        if case .checking = write { return .checking }
        return .unknown
    }

    private func statusBadge(state: SupabaseSchemaProbe.CheckState) -> some View {
        let (symbol, tint) = badgeStyle(state)
        return ZStack {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 24, height: 24)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
        }
    }

    private func badgeStyle(_ state: SupabaseSchemaProbe.CheckState) -> (String, Color) {
        switch state {
        case .ok: return ("checkmark", .green)
        case .checking: return ("hourglass", .blue)
        case .unknown: return ("questionmark", .gray)
        case .tableMissing: return ("xmark", .red)
        case .rlsBlocked: return ("lock.fill", Theme.orange)
        case .columnMissing: return ("minus", Theme.orange)
        case .error: return ("exclamationmark", .red)
        }
    }

    private func statusLabel(state: SupabaseSchemaProbe.CheckState) -> String {
        switch state {
        case .ok: return "OK"
        case .checking: return "Testing…"
        case .unknown: return "—"
        case .tableMissing: return "Missing"
        case .rlsBlocked: return "Blocked"
        case .columnMissing: return "Columns"
        case .error: return "Error"
        }
    }

    private func statusTint(_ state: SupabaseSchemaProbe.CheckState) -> Color {
        switch state {
        case .ok: return .green
        case .checking: return .blue
        case .unknown: return Color.white.opacity(0.5)
        default: return Theme.orange
        }
    }

    private func detailMessage(
        read: SupabaseSchemaProbe.CheckState,
        write: SupabaseSchemaProbe.CheckState
    ) -> String? {
        for state in [write, read] {
            switch state {
            case .tableMissing:
                return "Table doesn't exist yet. Run the SQL below."
            case .rlsBlocked:
                return "RLS is on but no policy allows this user to write. Run the SQL below."
            case .columnMissing(let column):
                return "Missing column `\(column)`. Run the SQL below."
            case .error(let message):
                return message
            default:
                continue
            }
        }
        return nil
    }
}

#Preview {
    SupabaseDiagnosticsView()
}
