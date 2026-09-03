//
//  TVTitleRoute.swift
//  GuideStreamTVTV
//
//  How a card asks for the title screen.
//
//  The title screen used to be presented — .sheet, later .fullScreenCover —
//  by whichever view owned the card that was selected. That made it a modal,
//  and a modal on tvOS owns all of the focus, which cost more than it bought:
//  the side rail was visible behind it but unreachable, so left did nothing;
//  @FocusState could not cross the presentation boundary, so the offer sheet
//  could not be navigated until it became its own view; and the presentation
//  inset the screen and rounded its corners.
//
//  It is now a route on the shell. TVMainView renders it in place of the
//  current tab, inside the same focus section the tabs use, so the rail stays
//  a sibling and the focus engine reaches it the ordinary way.
//
//  Views ask through the environment rather than owning a presentation.
//

import SwiftUI

private struct TVShowTitleDetailKey: EnvironmentKey {
    static let defaultValue: (TVTitleDetail) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Opens the title screen on the shell. Injected by TVMainView.
    var showTitleDetail: (TVTitleDetail) -> Void {
        get { self[TVShowTitleDetailKey.self] }
        set { self[TVShowTitleDetailKey.self] = newValue }
    }
}

extension View {
    /// Bridges a screen's existing `pendingDetail` state to the shell route.
    ///
    /// The presenters set `pendingDetail` from a dozen call sites between
    /// them, and every one of those assignments still reads naturally. Rather
    /// than rewrite them all, the state becomes a one-shot outbox: anything
    /// put in it is handed to the shell and cleared. New code should call
    /// `showTitleDetail` directly.
    func routesTitleDetail(_ pending: Binding<TVTitleDetail?>) -> some View {
        modifier(TVTitleDetailRouting(pending: pending))
    }
}

private struct TVTitleDetailRouting: ViewModifier {
    @Binding var pending: TVTitleDetail?
    @Environment(\.showTitleDetail) private var showTitleDetail

    func body(content: Content) -> some View {
        content.onChange(of: pending) { _, new in
            guard let new else { return }
            pending = nil
            showTitleDetail(new)
        }
    }
}
