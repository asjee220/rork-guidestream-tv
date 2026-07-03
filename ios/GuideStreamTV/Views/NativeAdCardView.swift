//
//  NativeAdCardView.swift
//  GuideStreamTV
//
//  UIViewRepresentable that renders a loaded GADNativeAd inside a
//  GADNativeAdView with all required assets registered (headline, body,
//  icon, call-to-action, advertiser, AdChoices). Styled to match the
//  SponsoredAffiliateCard glass aesthetic. Only compiled when the Google
//  Mobile Ads SDK is linked and the build targets a real device.
//

#if canImport(GoogleMobileAds) && !targetEnvironment(simulator)
import GoogleMobileAds
import SwiftUI
import UIKit

/// SwiftUI bridge for a native ad card. The `GADNativeAdView` is the root
/// view so the SDK can track impressions and clicks on the registered
/// asset subviews.
struct NativeAdCardView: UIViewRepresentable {
    let nativeAd: NativeAd
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> NativeAdContainer {
        let container = NativeAdContainer()
        container.onDismiss = onDismiss
        container.configure(with: nativeAd)
        return container
    }

    func updateUIView(_ view: NativeAdContainer, context: Context) {
        view.onDismiss = onDismiss
    }
}

/// Container view that hosts the `GADNativeAdView` and all asset subviews,
/// plus the "Ad" badge, dismiss button, and AdChoices marker. Laid out with
/// AutoLayout so text of varying lengths clips gracefully.
final class NativeAdContainer: UIView {

    var onDismiss: (() -> Void)?

    private let adView = NativeAdView()
    private let bgEffect = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let navyOverlay = UIView()
    private let mediaView = MediaView()
    private let textStack = UIStackView()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let ctaButton = UIButton(type: .system)
    private let advertiserLabel = UILabel()
    private let adBadge = UILabel()
    private let dismissButton = UIButton(type: .system)
    private let adChoicesContainer = AdChoicesView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Setup

    private func setupViews() {
        // Glass background
        bgEffect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bgEffect)

        navyOverlay.backgroundColor = UIColor(red: 8/255, green: 14/255, blue: 24/255, alpha: 0.19)
        navyOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(navyOverlay)

        layer.cornerRadius = 14
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.11).cgColor
        clipsToBounds = true

        // GADNativeAdView — fills the card edge-to-edge so every registered
        // asset view lies fully inside the native ad view (validator requirement).
        adView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(adView)

        // Media view (56pt square) — shows the ad's main image/video and is
        // registered as adView.mediaView. Replaces the old icon tile.
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        mediaView.contentMode = .scaleAspectFill
        mediaView.layer.cornerRadius = 8
        mediaView.layer.borderWidth = 0.5
        mediaView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        mediaView.clipsToBounds = true
        adView.addSubview(mediaView)

        // Headline (12pt heavy, white, 2 lines)
        headlineLabel.font = .systemFont(ofSize: 12, weight: .heavy)
        headlineLabel.textColor = .white
        headlineLabel.numberOfLines = 2
        headlineLabel.lineBreakMode = .byTruncatingTail
        headlineLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Body (10pt regular, 62% white, 2 lines)
        bodyLabel.font = .systemFont(ofSize: 10, weight: .regular)
        bodyLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        bodyLabel.numberOfLines = 2
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Advertiser (9pt, 45% white)
        advertiserLabel.font = .systemFont(ofSize: 9, weight: .regular)
        advertiserLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        advertiserLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Text column — vertically centered between media and CTA
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .fill
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(headlineLabel)
        textStack.addArrangedSubview(bodyLabel)
        textStack.addArrangedSubview(advertiserLabel)
        adView.addSubview(textStack)

        // CTA button (orange pill) — trailing edge, vertically centered
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        ctaButton.titleLabel?.font = .systemFont(ofSize: 10, weight: .bold)
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.backgroundColor = UIColor(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255, alpha: 1)
        ctaButton.layer.cornerRadius = 4
        ctaButton.clipsToBounds = true
        ctaButton.isUserInteractionEnabled = false
        ctaButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        ctaButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        ctaButton.setContentHuggingPriority(.required, for: .horizontal)
        adView.addSubview(ctaButton)

        // AdChoices container — media's top-right corner
        adChoicesContainer.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(adChoicesContainer)

        // "Ad" badge (top-left, our own decoration)
        adBadge.text = "AD"
        adBadge.font = .systemFont(ofSize: 7, weight: .heavy)
        adBadge.textColor = UIColor.white.withAlphaComponent(0.55)
        adBadge.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        adBadge.layer.cornerRadius = 4
        adBadge.clipsToBounds = true
        adBadge.textAlignment = .center
        adBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(adBadge)

        // Dismiss X (top-right)
        dismissButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        dismissButton.tintColor = UIColor.white.withAlphaComponent(0.40)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            // Background fills container
            bgEffect.topAnchor.constraint(equalTo: topAnchor),
            bgEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
            bgEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            bgEffect.trailingAnchor.constraint(equalTo: trailingAnchor),

            navyOverlay.topAnchor.constraint(equalTo: topAnchor),
            navyOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            navyOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            navyOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Ad view fills the card edge-to-edge so every registered asset
            // view lies fully inside the native ad view (validator requirement).
            adView.topAnchor.constraint(equalTo: topAnchor),
            adView.bottomAnchor.constraint(equalTo: bottomAnchor),
            adView.leadingAnchor.constraint(equalTo: leadingAnchor),
            adView.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Media — 56pt square, leading, vertically centered
            mediaView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
            mediaView.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            mediaView.widthAnchor.constraint(equalToConstant: 56),
            mediaView.heightAnchor.constraint(equalToConstant: 56),

            // AdChoices — media's top-right corner
            adChoicesContainer.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            adChoicesContainer.topAnchor.constraint(equalTo: mediaView.topAnchor),
            adChoicesContainer.widthAnchor.constraint(equalToConstant: 15),
            adChoicesContainer.heightAnchor.constraint(equalToConstant: 15),

            // CTA — trailing edge, vertically centered
            ctaButton.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),
            ctaButton.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            ctaButton.heightAnchor.constraint(equalToConstant: 24),

            // Text column — between media and CTA, vertically centered
            textStack.leadingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: ctaButton.leadingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: adView.topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -8),

            // Ad badge — top-left over the media corner
            adBadge.topAnchor.constraint(equalTo: mediaView.topAnchor, constant: 2),
            adBadge.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor, constant: 2),
            adBadge.heightAnchor.constraint(equalToConstant: 14),
            adBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),

            // Dismiss
            dismissButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            dismissButton.widthAnchor.constraint(equalToConstant: 28),
            dismissButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    // MARK: - Configure

    func configure(with ad: NativeAd) {
        // Register asset views on the GADNativeAdView so the SDK can
        // track impressions and handle clicks.
        adView.headlineView = headlineLabel
        adView.bodyView = bodyLabel
        adView.mediaView = mediaView
        adView.callToActionView = ctaButton
        adView.advertiserView = advertiserLabel
        adView.adChoicesView = adChoicesContainer

        // Main media asset — shown through the MediaView (validator requirement).
        mediaView.mediaContent = ad.mediaContent

        // Populate with ad assets
        headlineLabel.text = ad.headline
        bodyLabel.text = ad.body
        bodyLabel.isHidden = (ad.body == nil)
        advertiserLabel.text = ad.advertiser
        advertiserLabel.isHidden = (ad.advertiser == nil)
        ctaButton.setTitle(ad.callToAction, for: .normal)
        ctaButton.isHidden = (ad.callToAction == nil)

        // Associate the ad — must be the last step, after all asset
        // views are populated and registered.
        adView.nativeAd = ad
    }

    // MARK: - Actions

    @objc private func dismissTapped() {
        onDismiss?()
    }
}
#else
// Simulator / no-SDK: provide an empty stub so SponsoredSlotView's #else
// branch compiles. This type is never instantiated on simulator because
// AdManager.nextNativeAd() always returns nil there.
import SwiftUI

struct NativeAdCardView: View {
    var onDismiss: () -> Void
    var body: some View { EmptyView() }
}
#endif
