//
//  TVRemoteImage.swift
//  GuideStreamTVTV
//
//  Couch-friendly remote image loader. Slightly heavier shimmer than
//  the phone app so the focus pulse on tvOS reads from a distance,
//  and the in-memory cache is bumped because tvOS posters are big.
//

import SwiftUI
import UIKit

final class TVImageCacheManager: @unchecked Sendable {
    static let shared = TVImageCacheManager()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 160 * 1024 * 1024 // ~160MB for the 4K-ish posters
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }
}

struct TVShimmer: View {
    @State private var phase: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0x0D / 255, green: 0x16 / 255, blue: 0x23 / 255)
                LinearGradient(
                    colors: [
                        Color(red: 0x0D / 255, green: 0x16 / 255, blue: 0x23 / 255),
                        Color(red: 0x1A / 255, green: 0x25 / 255, blue: 0x35 / 255),
                        Color(red: 0x0D / 255, green: 0x16 / 255, blue: 0x23 / 255)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 1.8)
                .offset(x: phase * geo.size.width)
            }
            .clipped()
        }
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

struct TVRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    init(urlString: String?, contentMode: ContentMode = .fill) {
        self.url = urlString.flatMap { URL(string: $0) }
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let url {
                if let cached = TVImageCacheManager.shared.image(for: url) {
                    Image(uiImage: cached)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                                .onAppear { Self.cache(url: url) }
                        case .failure:
                            TVImageFallback()
                        case .empty:
                            TVShimmer()
                        @unknown default:
                            TVImageFallback()
                        }
                    }
                }
            } else {
                TVImageFallback()
            }
        }
    }

    private static func cache(url: URL) {
        Task.detached {
            if TVImageCacheManager.shared.image(for: url) != nil { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let ui = UIImage(data: data) else { return }
            TVImageCacheManager.shared.store(ui, for: url)
        }
    }
}

struct TVImageFallback: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0x2D / 255, green: 0x14 / 255, blue: 0x54 / 255),
                Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
