//
//  TVRemoteSwipe.swift
//  GuideStreamTVTV
//
//  Siri Remote touch-surface swipes, reported in the same vocabulary as
//  `.onMoveCommand`.
//
//  `.onMoveCommand` only sees *clicks* of the directional pad. A swipe across
//  the touch surface is handled by the focus engine, which moves focus between
//  focusable views and never produces a move command. Rails and grids are fine
//  — they are made of focusable cards, so the focus engine already does the
//  right thing. Screens that step their own content from a move command are
//  not: the hero carousel, Reels and the filter panel are all a single
//  focusable view, so a swipe has nowhere to move focus to and nothing happens.
//
//  Indirect (remote) touches travel the focused view's responder chain, and a
//  SwiftUI leaf is usually not in it, so the recognisers are installed on the
//  window. That makes them window-wide: `isEnabled` is what keeps one screen's
//  handler from firing while another holds focus. Always pass the view's own
//  focus state.
//

import SwiftUI
import UIKit

extension View {
    /// Calls `action` when the remote's touch surface is swiped, while
    /// `isEnabled` is true. Pair it with `.onMoveCommand(perform:)` and the
    /// same handler so clicks and swipes behave identically.
    func onRemoteSwipe(
        isEnabled: Bool,
        perform action: @escaping (MoveCommandDirection) -> Void
    ) -> some View {
        background(TVRemoteSwipeCatcher(isEnabled: isEnabled, action: action))
    }
}

private struct TVRemoteSwipeCatcher: UIViewRepresentable {
    let isEnabled: Bool
    let action: (MoveCommandDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, action: action)
    }

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: CatcherView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.action = action
        uiView.coordinator = context.coordinator
        uiView.attachIfNeeded()
    }

    static func dismantleUIView(_ uiView: CatcherView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled: Bool
        var action: (MoveCommandDirection) -> Void

        private var recognizers: [UISwipeGestureRecognizer] = []
        private weak var host: UIWindow?

        init(isEnabled: Bool, action: @escaping (MoveCommandDirection) -> Void) {
            self.isEnabled = isEnabled
            self.action = action
        }

        func attach(to window: UIWindow) {
            guard host !== window else { return }
            detach()

            let directions: [(UISwipeGestureRecognizer.Direction, MoveCommandDirection)] = [
                (.up, .up), (.down, .down), (.left, .left), (.right, .right)
            ]

            for (swipe, move) in directions {
                let recognizer = SwipeRecognizer(target: self, action: #selector(handle(_:)))
                recognizer.direction = swipe
                recognizer.move = move
                recognizer.delegate = self
                recognizer.allowedTouchTypes = [
                    NSNumber(value: UITouch.TouchType.indirect.rawValue)
                ]
                window.addGestureRecognizer(recognizer)
                recognizers.append(recognizer)
            }

            host = window
        }

        func detach() {
            for recognizer in recognizers {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizers.removeAll()
            host = nil
        }

        @objc private func handle(_ recognizer: UISwipeGestureRecognizer) {
            guard isEnabled, let move = (recognizer as? SwipeRecognizer)?.move else { return }
            action(move)
        }

        // Never take a swipe away from the focus engine or from any recogniser
        // UIKit installed itself.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            isEnabled
        }
    }

    /// Carries the move direction so one selector serves all four.
    final class SwipeRecognizer: UISwipeGestureRecognizer {
        var move: MoveCommandDirection = .right
    }

    /// Zero-size, non-interactive. Its only job is to tell the coordinator
    /// which window to hang the recognisers on, and when to let go.
    final class CatcherView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        func attachIfNeeded() {
            if let window {
                coordinator?.attach(to: window)
            } else {
                coordinator?.detach()
            }
        }
    }
}
