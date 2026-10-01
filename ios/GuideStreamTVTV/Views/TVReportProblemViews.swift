//
//  TVReportProblemViews.swift
//  GuideStreamTVTV
//
//  "Report a problem" on Apple TV — see TVContentReport.swift. Remote-first:
//  no note field (typing on a TV is not worth it for this), every control is
//  a focusable button with the house thin-outline focus, Menu closes.
//

import SwiftUI

/// A / D — the entry-point button.
struct TVReportProblemButton: View {
    var label: LocalizedStringKey = "Report a problem"
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "flag")
                    .font(.system(size: 22, weight: .semibold))
                Text(label)
                    .font(.system(size: 24, weight: .semibold))
            }
            .foregroundStyle(focused ? .white : TVTheme.textSecondary)
            .padding(.horizontal, 28)
            .frame(height: 64)
            .background(Capsule().fill(Color.white.opacity(focused ? 0.12 : 0.06)))
            .overlay(Capsule().stroke(Color.white, lineWidth: focused ? 2 : 0))
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focused)
    }
}

private struct TVReportRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(selected ? TVTheme.orange : Color.white.opacity(0.4), lineWidth: 3)
                        .frame(width: 30, height: 30)
                    if selected { Circle().fill(TVTheme.orange).frame(width: 14, height: 14) }
                }
                Text(title).font(.system(size: 28, weight: .medium)).foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 32)
            .frame(width: 900, height: 76)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(selected ? 0.10 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white, lineWidth: focused ? 2 : 0))
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focused)
    }
}

private struct TVReportPill: View {
    let title: LocalizedStringKey
    var primary = false
    var enabled = true
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(primary && enabled ? .black : .white)
                .padding(.horizontal, 48)
                .frame(minWidth: 320, minHeight: 80)
                .background(Capsule().fill(primary ? (enabled ? TVTheme.orange : Color.white.opacity(0.15)) : Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white, lineWidth: focused ? 3 : 0))
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focused)
        .disabled(!enabled)
    }
}

struct TVReportProblemScreen: View {
    let context: ReportContext
    let onClose: () -> Void

    @State private var reason: ReportReason?
    @State private var sending = false
    @State private var sent = false
    @State private var failed = false

    init(context: ReportContext, onClose: @escaping () -> Void) {
        self.context = context
        self.onClose = onClose
        _reason = State(initialValue: context.preselected)
    }

    var body: some View {
        ZStack {
            TVTheme.bg.opacity(0.97).ignoresSafeArea()
            if sent {
                VStack(spacing: 28) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 104, height: 104).background(Circle().fill(TVTheme.orange))
                    Text("Thanks — we’re on it").font(.system(size: 44, weight: .bold)).foregroundStyle(.white)
                    Text(context.providerName.map { "We’ll check \(context.titleName) on \($0) and fix it for everyone." }
                         ?? "We’ll check \(context.titleName) and fix it for everyone.")
                        .font(.system(size: 26)).foregroundStyle(TVTheme.textSecondary)
                    TVReportPill(title: "Done", primary: true, action: onClose)
                }
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Report a problem").font(.system(size: 52, weight: .bold)).foregroundStyle(.white)
                    Text(context.providerName.map { "\(context.titleName) · \($0)" } ?? context.titleName)
                        .font(.system(size: 26, weight: .medium)).foregroundStyle(TVTheme.textSecondary)
                    VStack(spacing: 14) {
                        ForEach(ReportReason.options(for: context.kind)) { option in
                            TVReportRow(title: option.label, selected: reason == option) { reason = option }
                        }
                    }
                    .focusSection()
                    if failed {
                        Text("Couldn’t send. Try again.").font(.system(size: 24)).foregroundStyle(TVTheme.orange)
                    }
                    HStack(spacing: 24) {
                        TVReportPill(title: sending ? "Sending…" : "Send report", primary: true, enabled: reason != nil && !sending, action: send)
                        TVReportPill(title: "Cancel", action: onClose)
                    }
                    .focusSection()
                }
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
        .onExitCommand { onClose() }
    }

    private func send() {
        guard let reason, !sending else { return }
        sending = true
        failed = false
        Task {
            let ok = await ContentReportService.submit(context, reason: reason, note: "")
            sending = false
            if ok { sent = true } else { failed = true }
        }
    }
}

/// C — "Did <service> open <title>?" on return from the streaming app.
struct TVReturnCheckScreen: View {
    let pending: DeepLinkReturnCheck.Pending
    let onYes: () -> Void
    let onNo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 32) {
                Text("Did \(pending.platform) open \(pending.title)?")
                    .font(.system(size: 44, weight: .bold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).frame(maxWidth: 1200)
                Text("Helps us keep links accurate").font(.system(size: 26)).foregroundStyle(TVTheme.textSecondary)
                HStack(spacing: 24) {
                    // Secondary left, primary right.
                    TVReportPill(title: "No, report it", action: onNo)
                    TVReportPill(title: "Yes, it worked", primary: true, action: onYes)
                }
                .focusSection()
            }
            .padding(64)
            .background(RoundedRectangle(cornerRadius: 32).fill(TVTheme.surfaceElevated))
        }
        .onExitCommand { onDismiss() }
    }
}
