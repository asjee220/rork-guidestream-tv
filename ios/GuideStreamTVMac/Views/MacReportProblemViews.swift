//
//  MacReportProblemViews.swift
//  GuideStreamTVMac
//
//  "Report a problem" on Mac — see MacContentReport.swift.
//

import SwiftUI

/// A / D — the inline link.
struct MacReportProblemLink: View {
    var prompt: LocalizedStringKey = "Wrong service or link?"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "flag").font(.system(size: 11, weight: .semibold))
                Text(prompt).font(.system(size: 12))
                Text("Report it").font(.system(size: 12, weight: .semibold)).foregroundStyle(MacColor.orange)
            }
            .foregroundStyle(MacColor.text2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Report a problem with this listing")
    }
}

struct MacReportProblemSheet: View {
    let context: ReportContext
    let onClose: () -> Void

    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var sending = false
    @State private var sent = false
    @State private var failed = false

    init(context: ReportContext, onClose: @escaping () -> Void) {
        self.context = context
        self.onClose = onClose
        _reason = State(initialValue: context.preselected)
    }

    var body: some View {
        Group {
            if sent { thanks } else { form }
        }
        .padding(24)
        .frame(width: 460)
        .background(MacColor.sheet)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Report a problem").font(.system(size: 20, weight: .bold))
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(context.titleName).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                if let p = context.providerName, !p.isEmpty {
                    Text(p).font(.system(size: 12)).foregroundStyle(MacColor.text2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(MacColor.elevated, in: RoundedRectangle(cornerRadius: 10))

            Text("WHAT'S WRONG?").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(MacColor.text3)
            VStack(spacing: 0) {
                ForEach(ReportReason.options(for: context.kind)) { option in
                    Button { reason = option } label: {
                        HStack(spacing: 10) {
                            Image(systemName: reason == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(reason == option ? MacColor.orange : MacColor.text2)
                            Text(option.label).font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(reason == option ? Color.white.opacity(0.06) : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(MacColor.elevated, in: RoundedRectangle(cornerRadius: 10))

            TextField("Anything else? (optional)", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            if failed {
                Text("Couldn’t send. Check your connection and try again.")
                    .font(.system(size: 12)).foregroundStyle(MacColor.orange)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button(sending ? "Sending…" : "Send report", action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(reason == nil || sending)
            }
        }
    }

    private var thanks: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(MacColor.orange)
            Text("Thanks — we’re on it").font(.system(size: 18, weight: .bold))
            Text(context.providerName.map { "We’ll check \(context.titleName) on \($0) and fix it for everyone." }
                 ?? "We’ll check \(context.titleName) and fix it for everyone.")
                .font(.system(size: 13)).foregroundStyle(MacColor.text2).multilineTextAlignment(.center)
            Button("Done", action: onClose).keyboardShortcut(.defaultAction).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func send() {
        guard let reason, !sending else { return }
        sending = true
        failed = false
        Task {
            let ok = await ContentReportService.submit(context, reason: reason, note: note)
            sending = false
            if ok { sent = true } else { failed = true }
        }
    }
}

/// C — inline banner on the title sheet when the viewer comes back.
struct MacReturnCheckBanner: View {
    let pending: DeepLinkReturnCheck.Pending
    let onYes: () -> Void
    let onNo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Did \(pending.platform) open \(pending.title)?").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("Helps us keep links accurate").font(.system(size: 11)).foregroundStyle(MacColor.text2)
            }
            Spacer()
            Button("Yes, it worked", action: onYes)
            Button("No, report it", action: onNo).tint(MacColor.orange).buttonStyle(.borderedProminent)
            Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).help("Dismiss")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(MacColor.sheet, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MacColor.hairline))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .frame(maxWidth: 640)
    }
}
