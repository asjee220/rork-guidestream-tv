//
//  PlayOnBottomSheet.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit

enum PlayOnDeviceType {
    case iphone
    case appleTv
    case tv
}

struct PlayOnDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let sublabel: String
    let type: PlayOnDeviceType
}

enum PlayOnRowState: Equatable {
    case `default`
    case selected
    case connecting
}

struct PlayOnBottomSheet: View {
    let isOpen: Bool
    let onClose: () -> Void
    let showTitle: String
    let showSubtitle: String
    let thumbnailUrl: String?
    var tmdbId: Int? = nil
    var isTV: Bool = true
    var initialSelectedDevice: String = "living-room"
    let onDeviceSelected: (String) -> Void

    // Content shown in the redesigned sheet. Values are illustrative and match
    // the reference design provided by the user.
    private let yearsLabel: String = "2018–2023 · 4 Seasons · TV-MA"
    private let platformLabel: String = "HBO MAX"
    private let platformColor: Color = Color(red: 0x6A/255, green: 0x3F/255, blue: 0xE0/255)
    private let genreLabel: String = "Drama"
    private let rating: Double = 9.6
    private let likeCount: String = "2.4K"
    private let commentCount: String = "183"
    private let aboutText: String = "Four adult children of a media mogul compete for control of their father's empire as his health fails. One of the greatest dramas ever made."
    private let whereToWatchLabel: String = "HBO Max"
    private let availabilityLabel: String = "Available with subscription"
    private let watchCTAColor: Color = Color.orange

    @State private var isLiked: Bool = false
    @State private var isNotifying: Bool = true
    @State private var showCastSheet: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(isOpen ? 0.55 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(isOpen)
                    .onTapGesture { close() }
                    .animation(.easeOut(duration: 0.2), value: isOpen)

                sheetContent(maxHeight: geo.size.height * 0.86)
                    .offset(y: isOpen ? 0 : geo.size.height)
                    .animation(.interpolatingSpring(stiffness: 280, damping: 26), value: isOpen)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCastSheet) {
            CastToTVSheet(
                isPresented: $showCastSheet,
                showTitle: showTitle,
                platform: whereToWatchLabel,
                tmdbId: tmdbId
            )
        }
    }

    private func close() { onClose() }

    // MARK: - Sheet body

    private func sheetContent(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 44, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 20)

                    actionsRow
                        .padding(.horizontal, 20)
                        .padding(.vertical, 22)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 20)

                    aboutSection
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    whereToWatchSection
                        .padding(.horizontal, 20)
                        .padding(.top, 22)

                    watchButton
                        .padding(.horizontal, 20)
                        .padding(.top, 22)

                    viewFullDetailsButton
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28), style: .continuous)
                .fill(Color(red: 0x06/255, green: 0x0C/255, blue: 0x18/255))
        )
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28), style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 28, y: -10)
    }

    // MARK: - Header row (poster + meta)

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            posterThumbnail
                .frame(width: 110, height: 150)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text(showTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(yearsLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(spacing: 8) {
                    Text(platformLabel)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(platformColor))

                    Text(genreLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .padding(.top, 2)

                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0xFF/255, green: 0xC4/255, blue: 0x3D/255))
                    }
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                }
                .padding(.top, 2)

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.orange)
                        Text(likeCount)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Likes")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Text("·")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.4))
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text(commentCount)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Comments")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private var posterThumbnail: some View {
        ZStack {
            if let urlString = thumbnailUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        posterFallback
                    }
                }
            } else {
                posterFallback
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text("HBO")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(platformColor))
                .padding(8)
        }
    }

    private var posterFallback: some View {
        LinearGradient(
            colors: [
                Color(red: 0xB8/255, green: 0x86/255, blue: 0x2C/255),
                Color(red: 0x6A/255, green: 0x4A/255, blue: 0x10/255)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Actions row

    private var actionsRow: some View {
        HStack(spacing: 0) {
            actionButton(
                icon: isLiked ? "heart.fill" : "heart",
                label: "Like",
                tint: isLiked ? Color.orange : .white,
                showDot: false
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isLiked.toggle() }
            }
            .frame(maxWidth: .infinity)

            actionButton(
                icon: "bell.fill",
                label: "Notify",
                tint: .white,
                showDot: isNotifying
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isNotifying.toggle() }
            }
            .frame(maxWidth: .infinity)

            actionButton(
                icon: "tv",
                label: "Send to TV",
                tint: .white,
                showDot: false
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showCastSheet = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func actionButton(icon: String, label: String, tint: Color, showDot: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 54, height: 54)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(tint)
                    if showDot {
                        Circle()
                            .fill(Color(red: 0x3D/255, green: 0xE0/255, blue: 0x6A/255))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(red: 0x06/255, green: 0x0C/255, blue: 0x18/255), lineWidth: 2))
                            .offset(x: 16, y: -16)
                    }
                }
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ABOUT")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(aboutText)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Where to watch

    private var whereToWatchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE TO WATCH")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.45))

            HStack(spacing: 10) {
                Text(whereToWatchLabel)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(platformColor))
            }

            Text(availabilityLabel)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CTA

    private var watchButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            WatchIntentLogger.shared.log(
                eventType: .playOnDeviceChosen,
                titleId: WatchIntentLogger.titleSlug(showTitle),
                metadata: ["device_id": "watch-on-platform", "platform": whereToWatchLabel]
            )
            StreamingDeepLinker.open(
                platform: whereToWatchLabel,
                title: showTitle,
                tmdbId: tmdbId,
                isTV: isTV
            )
            onDeviceSelected("watch-on-platform")
        } label: {
            Text("Watch on \(whereToWatchLabel)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule().fill(watchCTAColor)
                )
                .shadow(color: watchCTAColor.opacity(0.55), radius: 22, y: 0)
        }
        .buttonStyle(.plain)
    }

    private var viewFullDetailsButton: some View {
        Button(action: close) {
            HStack(spacing: 6) {
                Text("View Full Details")
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.navy.ignoresSafeArea()
        PlayOnBottomSheet(
            isOpen: true,
            onClose: {},
            showTitle: "Succession",
            showSubtitle: "S4 E7 · Tailgate Party",
            thumbnailUrl: nil,
            onDeviceSelected: { _ in }
        )
    }
}
