//
//  TVRemoteSwipe.swift
//  GuideStreamTVTV
//
//  Remote directional input that *observes* instead of taking over.
//
//  `.onMoveCommand` consumes every direction while its view or any descendant
//  holds focus — up and down included, whether or not the handler acts on
//  them. That is what made the hero a focus trap: eight downs in a row never
//  reached the focus engine, so focus could not leave it for the rails, and
//  left never reached the side menu.
//
//  These recognisers sit alongside the focus engine rather than in front of
//  it: they report the direction and let UIKit move focus as it normally
//  would. A screen can therefore act on one direction (the hero steps its
//  carousel on right) while the other three keep working as navigation.
//
//  Both input styles are covered, because the Siri Remote produces two:
//  a swipe across the touch surface (an indirect touch) and a click of the
//  directional ring (an arrow press).
//
//  Indirect touches and presses travel the focused view's responder chain,
//  and a SwiftUI leaf is usually not in it, so the recognisers are installed
//  on the window. That makes them window-wide: `isEnabled` is what keeps one
//  screen's handler from firing while another holds focus. Always pass the
//  view's own focus state.
//

import SwiftUI
import UIKit

extension View {
    /// Reports remote swipes and directional-pad clicks as
    /// `MoveCommandDirection`, without consuming them.
    ///
    /// Use this in place of `.onMoveCommand` wherever the view acts on some
    /// directions but must let the focus engine keep the rest.
    func onRemoteDirection(
        isEnabled: Bool,
        perform action: @escaping (MoveCommandDirection) -> Void
    ) -> some View {
        background(TVRemoteDirectionCatcher(isEnabled: isEnabled, action: action))
    }
}

private struct TVRemoteDirectionCatcher: UIViewRepresentable {
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

        private var recognizers: [UIGestureRecognizer] = []
        private weak var host: UIWindow?

        init(isEnabled: Bool, action: @escaping (MoveCommandDirection) -> Void) {
            self.isEnabled = isEnabled
            self.action = action
        }

        private static let directions: [(
            swipe: UISwipeGestureRecognizer.Direction,
            press: UIPress.PressType,
            move: MoveCommandDirection
        )] = [
            (.up, .upArrow, .up),
            (.down, .downArrow, .down),
            (.left, .leftArrow, .left),
            (.right, .rightArrow, .right)
        ]

        func attach(to window: UIWindow) {
            guard host !== window else { return }
            detach()

            for entry in Self.directions {
                let swipe = SwipeRecognizer(target: self, action: #selector(handle(_:)))
                swipe.direction = entry.swipe
                swipe.move = entry.move
                swipe.delegate = self
                swipe.allowedTouchTypes = [
                    NSNumber(value: UITouch.TouchType.indirect.rawValue)
                ]
                window.addGestureRecognizer(swipe)
                recognizers.append(swipe)

                let press = PressRecognizer(target: self, action: #selector(handle(_:)))
                press.move = entry.move
                press.delegate = self
                press.allowedPressTypes = [NSNumber(value: entry.press.rawValue)]
                press.allowedTouchTypes = []
                window.addGestureRecognizer(press)
                recognizers.append(press)
            }

            host = window
            TVNavLog.log("remote direction recognisers attached")
        }

        func detach() {
            for recognizer in recognizers {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizers.removeAll()
            host = nil
        }

        @objc private func handle(_ recognizer: UIGestureRecognizer) {
            let move: MoveCommandDirection?
            switch recognizer {
            case let swipe as SwipeRecognizer: move = swipe.move
            case let press as PressRecognizer: move = press.move
            default: move = nil
            }
            guard let move else { return }
            TVNavLog.log("remote \(recognizer is SwipeRecognizer ? "swipe" : "press") "
                         + "\(move) enabled=\(isEnabled)")
            guard isEnabled else { return }
            action(move)
        }

        // Never take an input away from the focus engine or from any
        // recogniser UIKit installed itself. This modifier only listens.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }

    /// Both carry the move direction so one selector serves all eight.
    final class SwipeRecognizer: UISwipeGestureRecognizer {
        var move: MoveCommandDirection = .right
    }

    final class PressRecognizer: UITapGestureRecognizer {
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
