//
//  TVHeroCarousel.swift
//  GuideStreamTVTV
//
//  Cinematic backdrop hero shown at the top of Home. Rotates through the
//  top trending titles every ~6 seconds, with the focus-aware "Add to
//  Watch List" CTA pinned at the bottom-left. The image fades softly into
//  the rails below to create depth.
//

import SwiftUI

struct TVHeroCarousel: View {
    let items: [TVTMDBResult]
    let onToggleSave: (TVTMDBResult) -> Void
    let isSaved: (TVTMDBResult) -> Bool

    @State private var index: Int = 0
    @State private var rotationTask: Task<Void, Never>?

    @FocusState private var isCTAFocused: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop layer
            ZStack {
                ForEach(items.indices, id: \.self) { i in
                    if i == index {
                        TVRemoteImage(urlString: items[i].backdropUrl, contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .overlay {
                                LinearGradient(
                                    colors: [
                                        Color.clear,
                                        TVTheme.bg.opacity(0.55),
                                        TVTheme.bg
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                            .overlay {
                                LinearGradient(
                                    colors: [
                                        TVTheme.bg.opacity(0.75),
                                        Color.clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .center
                                )
                            }
                            .transition(.opacity)
                    }
                }
            }
            .frame(height: 640)
            .frame(maxWidth: .infinity)
            .clipped()

            // Foreground content
            if !items.isEmpty {
                let item = items[index]
                VStack(alignment: .leading, spacing: 18) {
                    Text(item.isTV ? "TRENDING SHOW" : "TRENDING MOVIE")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(TVTheme.orange)
                        .tracking(2)
                    Text(item.displayName)
                        .font(.system(size: 54, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(TVTheme.textSecondary)
                            .lineLimit(3)
                            .frame(maxWidth: 820, alignment: .leading)
                    }

                    Button {
                        onToggleSave(item)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: isSaved(item) ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.system(size: 28, weight: .bold))
                            Text(isSaved(item) ? "Saved to Watch List" : "Add to Watch List")
                                .font(.system(size: 22, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.card)
                    .focused($isCTAFocused)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 56)
                .animation(.easeOut(duration: 0.5), value: index)
            }
        }
        .frame(height: 640)
        .onAppear { startRotation() }
        .onDisappear { rotationTask?.cancel() }
        .onChange(of: items.count) { _, _ in
            index = 0
            startRotation()
        }
    }

    private func startRotation() {
        rotationTask?.cancel()
        guard items.count > 1 else { return }
        rotationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                if Task.isCancelled { break }
                // Pause auto-rotation while the user is interacting with
                // the CTA so the highlight doesn't change under them.
                if isCTAFocused { continue }
                withAnimation(.easeInOut(duration: 0.6)) {
                    index = (index + 1) % max(items.count, 1)
                }
            }
        }
    }
}
