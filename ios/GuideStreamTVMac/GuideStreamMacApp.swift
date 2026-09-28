//
//  GuideStreamMacApp.swift
//  GuideStreamTVMac
//
//  Native macOS app. Same Supabase project, same services and the same
//  Watch Graph events as iPhone and Apple TV; the shell is Mac-first
//  (sidebar, windows, keyboard) with Home in the phone's rail order.
//  No ads on Mac in this release (decided 28 Sep 2026).
//

import SwiftUI
import Supabase

@main
struct GuideStreamMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacRootView()
                .preferredColorScheme(.dark)
                .task {
                    await TVProviderBrandMapService.shared.refresh()
                    DeviceSessionService.shared.incrementSessionAndUpsert()
                }
                .onOpenURL { url in
                    guard url.scheme == "guidestream" else { return }
                    Task { try? await SupabaseManager.shared.client.auth.session(from: url) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)
        .commands { MacCommands() }
    }
}

/// Menu-bar commands. Each posts a notification MacMainView listens for.
struct MacCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") { MacCommand.post(.toggleSidebar) }
                .keyboardShortcut("s", modifiers: [.control, .command])
        }
        CommandMenu("Go") {
            Button("Home") { MacCommand.post(.go("home")) }.keyboardShortcut("1")
            Button("Search") { MacCommand.post(.go("search")) }.keyboardShortcut("f")
            Button("Watchlist") { MacCommand.post(.go("watchlist")) }.keyboardShortcut("2")
            Button("Sports") { MacCommand.post(.go("sports")) }.keyboardShortcut("3")
            Divider()
            Button("Ask GuideStream") { MacCommand.post(.ask) }.keyboardShortcut("k")
        }
    }
}

enum MacCommand {
    case toggleSidebar, ask, go(String)
    static let name = Notification.Name("gs.mac.command")

    static func post(_ c: MacCommand) {
        let value: String
        switch c {
        case .toggleSidebar: value = "sidebar"
        case .ask: value = "ask"
        case .go(let s): value = "go:\(s)"
        }
        NotificationCenter.default.post(name: name, object: value)
    }
}

struct MacRootView: View {
    @State private var auth = MacAuthViewModel.shared
    @State private var restored = false

    var body: some View {
        ZStack {
            MacBackground()
            if !restored {
                ProgressView().controlSize(.large)
            } else if auth.isSignedIn {
                MacMainView().transition(.opacity)
            } else {
                MacSignInView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isSignedIn)
        .task {
            await AuthViewModel.shared.restoreSession()
            restored = true
        }
    }
}
