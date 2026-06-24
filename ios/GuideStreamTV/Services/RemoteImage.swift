//
//  RemoteImage.swift
//  GuideStreamTV
//
//  Centralised remote image loading with in-memory cache, shimmer skeleton,
//  and gradient fallback. Use `RemoteImage(url:)` everywhere instead of
//  bare AsyncImage so loading + failure states are consistent across the app.
//

import SwiftUI
import UIKit

// MARK: - Cache

final class ImageCacheManager: @unchecked Sendable {
    static let shared = ImageCacheManager()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 80 * 1024 * 1024 // ~80MB
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }
}

// MARK: - Shimmer

struct ShimmerView: View {
    @State private var phase: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0x0D/255, green: 0x16/255, blue: 0x23/255)
                LinearGradient(
                    colors: [
                        Color(red: 0x0D/255, green: 0x16/255, blue: 0x23/255),
                        Color(red: 0x1A/255, green: 0x25/255, blue: 0x35/255),
                        Color(red: 0x0D/255, green: 0x16/255, blue: 0x23/255)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 1.6)
                .offset(x: phase * geo.size.width)
            }
            .clipped()
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

// MARK: - Gradient Fallback

struct GradientFallbackView: View {
    let colors: [Color]

    init(colors: [Color] = [
        Color(red: 0x2D/255, green: 0x14/255, blue: 0x54/255),
        Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255)
    ]) {
        self.colors = colors
    }

    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - RemoteImage

/// Drop-in replacement for `AsyncImage` that adds:
///  - shimmer skeleton while loading
///  - gradient fallback on failure / nil URL
///  - in-memory cache to avoid re-downloading the same poster across screens
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var fallbackColors: [Color] = [
        Color(red: 0x2D/255, green: 0x14/255, blue: 0x54/255),
        Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255)
    ]

    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        fallbackColors: [Color] = [
            Color(red: 0x2D/255, green: 0x14/255, blue: 0x54/255),
            Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255)
        ]
    ) {
        self.url = url
        self.contentMode = contentMode
        self.fallbackColors = fallbackColors
    }

    init(
        urlString: String?,
        contentMode: ContentMode = .fill,
        fallbackColors: [Color] = [
            Color(red: 0x2D/255, green: 0x14/255, blue: 0x54/255),
            Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255)
        ]
    ) {
        self.url = urlString.flatMap { URL(string: $0) }
        self.contentMode = contentMode
        self.fallbackColors = fallbackColors
    }

    @State private var loadedImage: Image?
    @State private var loadFailed: Bool = false

    var body: some View {
        Group {
            if let url {
                if let cached = ImageCacheManager.shared.image(for: url) {
                    Image(uiImage: cached)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    ZStack {
                        // Stable base — shimmer while loading, fallback on failure
                        if loadFailed {
                            GradientFallbackView(colors: fallbackColors)
                        } else {
                            ShimmerView()
                        }

                        // Image fades in over the base when it arrives
                        if let image = loadedImage {
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                                .opacity(loadFailed ? 0 : 1)
                                .animation(.easeOut(duration: 0.5), value: loadedImage)
                        }
                    }
                    .task {
                        loadedImage = nil
                        loadFailed = false
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            if let ui = UIImage(data: data) {
                                ImageCacheManager.shared.store(ui, for: url)
                                // Brief delay so shimmer has time to appear before crossfade
                                try? await Task.sleep(for: .milliseconds(80))
                                withAnimation(.easeOut(duration: 0.5)) {
                                    loadedImage = Image(uiImage: ui)
                                }
                            } else {
                                loadFailed = true
                            }
                        } catch {
                            loadFailed = true
                        }
                    }
                }
            } else {
                GradientFallbackView(colors: fallbackColors)
            }
        }
    }
}
