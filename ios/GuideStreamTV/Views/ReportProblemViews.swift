//
//  ReportProblemViews.swift
//  GuideStreamTV
//
//  UI for in-app "Report a problem" — see ContentReportService.swift.
//

import SwiftUI

/// A / D — the quiet inline link. Title surfaces use the default copy; the
/// sports sheet passes "Wrong channel or time?".
struct ReportProblemLink: View {
    let context: ReportContext
    var prompt: LocalizedStringKey = "Wrong service or link?"

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            ReportPresenter.presentReport(context)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "flag")
                    .scaledFont(size: 12, weight: .semibold)
                Text(prompt)
                    .scaledFont(size: 13)
                Text("Report it")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color.orange)
            }
            .foregroundStyle(Color.textSecondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Report a problem with this listing"))
    }
}

struct ReportProblemSheet: View {
    let context: ReportContext
    let onClose: () -> Void

    @State private var reason: ReportReason?
    @State private var note: String = ""
    @State private var sending = false
    @State private var sent = false
    @State private var failed = false
    @FocusState private var noteFocused: Bool

    init(context: ReportContext, onClose: @escaping () -> Void) {
        self.context = context
        self.onClose = onClose
        _reason = State(initialValue: context.preselected)
    }

    var body: some View {
        ZStack {
            Color.navy.ignoresSafeArea()
            if sent { thanks } else { form }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Report a problem")
                        .scaledFont(size: 22, weight: .bold)
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .scaledFont(size: 15, weight: .bold)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Close"))
                }

                HStack(spacing: 12) {
                    Image(systemName: context.kind == .sports ? "sportscourt.fill" : "film.fill")
                        .scaledFont(size: 18)
                        .foregroundStyle(Color.orange)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.titleName)
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let p = context.providerName, !p.isEmpty {
                            Text(p)
                                .scaledFont(size: 13)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))

                Text("WHAT'S WRONG?")
                    .scaledFont(size: 12, weight: .bold)
                    .tracking(1.2)
                    .foregroundStyle(Color.textTertiary)

                VStack(spacing: 0) {
                    let options = ReportReason.options(for: context.kind)
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { Divider().overlay(Color.white.opacity(0.08)) }
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            reason = option
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().stroke(reason == option ? Color.orange : Color.white.opacity(0.3), lineWidth: 2)
                                        .frame(width: 20, height: 20)
                                    if reason == option {
                                        Circle().fill(Color.orange).frame(width: 10, height: 10)
                                    }
                                }
                                Text(option.label)
                                    .scaledFont(size: 15)
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(reason == option ? Color.white.opacity(0.06) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(reason == option ? .isSelected : [])
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Anything else? (optional)")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.textSecondary)
                    TextField("", text: $note, prompt: Text(context.kind == .sports ? "e.g. It’s on ESPN, not FOX" : "e.g. It’s on Netflix now").foregroundStyle(Color.textTertiary), axis: .vertical)
                        .lineLimit(3...5)
                        .focused($noteFocused)
                        .scaledFont(size: 15)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1)))
                }

                if failed {
                    Text("Couldn’t send. Check your connection and try again.")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.orange)
                }

                Button(action: send) {
                    ZStack {
                        if sending {
                            ProgressView().tint(.black)
                        } else {
                            Text("Send report")
                                .scaledFont(size: 16, weight: .bold)
                        }
                    }
                    .foregroundStyle(reason == nil ? Color.textSecondary : Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 14).fill(reason == nil ? Color.white.opacity(0.1) : Color.orange))
                }
                .buttonStyle(.plain)
                .disabled(reason == nil || sending)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var thanks: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark")
                .scaledFont(size: 28, weight: .bold)
                .foregroundStyle(.black)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.orange))
            Text("Thanks — we’re on it")
                .scaledFont(size: 22, weight: .bold)
                .foregroundStyle(.white)
            Text(context.providerName.map { "We’ll check \(context.titleName) on \($0) and fix it for everyone." }
                 ?? "We’ll check \(context.titleName) and fix it for everyone.")
                .scaledFont(size: 15)
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button(action: onClose) {
                Text("Done")
                    .scaledFont(size: 16, weight: .bold)
                    .foregroundStyle(.black)
                    .frame(width: 200, height: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }

    private func send() {
        guard let reason, !sending else { return }
        noteFocused = false
        sending = true
        failed = false
        Task {
            let ok = await ContentReportService.submit(context, reason: reason, note: note)
            await MainActor.run {
                sending = false
                if ok {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeOut(duration: 0.2)) { sent = true }
                } else {
                    failed = true
                }
            }
        }
    }
}

/// C — the card shown on return from a streaming app.
struct DeepLinkReturnCard: View {
    let pending: DeepLinkReturnCheck.Pending
    let onYes: () -> Void
    let onNo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.navy.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Did \(pending.platform) open \(pending.title)?")
                            .scaledFont(size: 17, weight: .semibold)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("Helps us keep links accurate")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .scaledFont(size: 14, weight: .bold)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Dismiss"))
                }
                HStack(spacing: 10) {
                    Button(action: onYes) {
                        Text("Yes, it worked")
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    Button(action: onNo) {
                        Text("No, report it")
                            .scaledFont(size: 15, weight: .bold)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
    }
}
