//
//  AppUpdateSheet.swift
//  GuideStreamTV
//
//  The three faces of AppUpdateGate (GUI-43). One view, because they share a
//  layout and differ only in whether the user can leave and what the button
//  does — building three of these would have meant three places to restyle.
//

import SwiftUI

struct AppUpdateSheet: View {
    let prompt: AppUpdatePrompt
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    private var isBlocking: Bool {
        if case .required = prompt { return true }
        return false
    }

    private var heading: String {
        switch prompt {
        case .required: return "Time to update"
        case .available: return "A new version is ready"
        case .whatsNew(_, let title, _): return title
        }
    }

    private var subheading: String {
        switch prompt {
        case .required:
            return "This version of GuideStream can no longer talk to our servers. Update to keep watching."
        case .available(let version, _, _):
            return "Version \(version) is on the App Store."
        case .whatsNew(let version, _, _):
            return "You're on version \(version)."
        }
    }

    private var notes: [String] {
        switch prompt {
        case .required: return []
        case .available(_, _, let n): return n
        case .whatsNew(_, _, let n): return n
        }
    }

    private var primaryLabel: String {
        switch prompt {
        case .required, .available: return "Update"
        case .whatsNew: return "Continue"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isBlocking {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .scaledFont(size: 14, weight: .bold)
                            .foregroundStyle(Color.white.opacity(0.65))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.bottom, 8)
            }

            Image(systemName: isBlocking ? "exclamationmark.arrow.circlepath" : "sparkles")
                .scaledFont(size: 34, weight: .semibold)
                .foregroundStyle(Color.orange)
                .padding(.bottom, 16)

            Text(heading)
                .scaledFont(size: 24, weight: .bold)
                .foregroundStyle(.white)

            Text(subheading)
                .scaledFont(size: 14)
                .foregroundStyle(Color.white.opacity(0.6))
                .padding(.top, 6)

            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(notes.prefix(5), id: \.self) { note in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(note)
                                .scaledFont(size: 15)
                                .foregroundStyle(Color.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 20)
            }

            Spacer(minLength: 24)

            Button {
                switch prompt {
                case .required(let url), .available(_, let url, _):
                    if let url { openURL(url) }
                    // A required update deliberately does not dismiss: the user
                    // comes back through a relaunch, having actually updated.
                    if !isBlocking { onDismiss() }
                case .whatsNew:
                    onDismiss()
                }
            } label: {
                Text(primaryLabel)
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(.plain)

            if case .available = prompt {
                Button(action: onDismiss) {
                    Text("Not now")
                        .scaledFont(size: 15, weight: .medium)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, isBlocking ? 40 : 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BrandBackground().ignoresSafeArea())
        .interactiveDismissDisabled(isBlocking)
        .preferredColorScheme(.dark)
    }
}
