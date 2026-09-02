//
//  TVWatchOptionsSheet.swift
//  GuideStreamTVTV
//
//  "Where do you want to watch?" — shown only when the watch button cannot
//  pick for the viewer: two or more subscriptions they own, or, owning none,
//  two or more ways to pay.
//
//  A separate View, not a computed property on TVTitleSheet, and that is the
//  whole point: `@FocusState` is scoped to the view hierarchy that declares
//  it, and a `fullScreenCover` presents its content in a hierarchy of its
//  own. A focus binding declared on the presenting screen never reached the
//  rows here, so nothing in the sheet could take focus and it could not be
//  navigated at all — it was a dead end, not a styling problem.
//

import SwiftUI

struct TVWatchOptionsSheet: View {
    let title: String
    let options: [TVWatchmodeResolver.TVResolvedSource]
    let onPick: (TVWatchmodeResolver.TVResolvedSource) -> Void
    let onClose: () -> Void

    @FocusState private var focusedOption: Int?

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text(title.uppercased())
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(6)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("Where do you want to watch?")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 18)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, source in
                            row(for: source, index: index)
                        }
                    }
                    // A focused row lifts 1.04, and a ScrollView clips to its
                    // own bounds — without this the first row lost its ends.
                    .padding(.horizontal, 26)
                    .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 120)
            .padding(.vertical, 90)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .focusSection()
        }
        .onExitCommand(perform: onClose)
        // The cover has to finish presenting before a focus assignment takes.
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                focusedOption = 0
            }
        }
    }

    private func row(for source: TVWatchmodeResolver.TVResolvedSource,
                     index: Int) -> some View {
        let subscribed = AuthViewModel.shared.subscribesToService(named: source.name)
        let focused = focusedOption == index

        return Button {
            onPick(source)
        } label: {
            HStack(spacing: 22) {
                TVServiceBrandMark(providerName: source.name, size: 52)

                Text(displayName(for: source.name))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 24)

                Text(offerLabel(for: source, subscribed: subscribed))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .frame(maxWidth: 900, alignment: .leading)
            // Neutral, so the brand-coloured mark is the thing carrying the
            // service's identity. The side menu's plate marks focus.
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(focused ? 0.16 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(focused ? 0.85 : 0.10),
                            lineWidth: focused ? 2 : 1)
            )
            .scaleEffect(focused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(TVWatchOptionButtonStyle())
        .focusEffectDisabled()
        .focused($focusedOption, equals: index)
    }

    private func displayName(for raw: String) -> String {
        Platform.from(providerName: raw)?.displayName ?? raw
    }

    /// "Included" for something already paid for, otherwise "Rent $3.99" —
    /// and just "Rent" when the offer arrived without a price, which is what
    /// a TMDB-sourced fallback row looks like.
    private func offerLabel(for source: TVWatchmodeResolver.TVResolvedSource,
                            subscribed: Bool) -> String {
        let tier = source.type.lowercased()
        let name: String
        switch tier {
        case "rent": name = "Rent"
        case "buy", "purchase": name = "Buy"
        case "free": name = "Free"
        case "tve": name = "With TV provider"
        default: name = subscribed ? "Included" : "Subscription"
        }
        guard let price = source.price, price > 0 else { return name }
        return String(format: "%@ $%.2f", name, price)
    }
}

/// Draws nothing, so the row's own plate is the only focus cue.
private struct TVWatchOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
