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
private final class NativeAdContainer: UIView {

    var onDismiss: (() -> Void)?

    private let adView = NativeAdView()
    private let bgEffect = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let navyOverlay = UIView()
    private let iconTile = UIView()
    private let iconImageView = UIImageView()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let ctaButton = UIButton(type: .system)
    private let advertiserLabel = UILabel()
    private let adBadge = UILabel()
    private let dismissButton = UIButton(type: .system)
    private let adChoicesContainer = UIView()

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

        // GADNativeAdView — contains the clickable asset views
        adView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(adView)

        // Icon tile (52pt rounded square)
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconTile.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        iconTile.layer.cornerRadius = 8
        iconTile.layer.borderWidth = 0.5
        iconTile.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        iconTile.clipsToBounds = true
        adView.addSubview(iconTile)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.clipsToBounds = true
        iconTile.addSubview(iconImageView)

        // Headline (11pt heavy, white, 2 lines)
        headlineLabel.font = .systemFont(ofSize: 11, weight: .heavy)
        headlineLabel.textColor = .white
        headlineLabel.numberOfLines = 2
        headlineLabel.lineBreakMode = .byTruncatingTail
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(headlineLabel)

        // Body (10pt regular, 62% white, 3 lines)
        bodyLabel.font = .systemFont(ofSize: 10, weight: .regular)
        bodyLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        bodyLabel.numberOfLines = 3
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(bodyLabel)

        // CTA button (orange pill)
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        ctaButton.titleLabel?.font = .systemFont(ofSize: 10, weight: .bold)
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.backgroundColor = UIColor(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255, alpha: 1)
        ctaButton.layer.cornerRadius = 4
        ctaButton.isUserInteractionEnabled = false
        ctaButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        adView.addSubview(ctaButton)

        // Advertiser (9pt, 45% white)
        advertiserLabel.font = .systemFont(ofSize: 9, weight: .regular)
        advertiserLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        advertiserLabel.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(advertiserLabel)

        // AdChoices container (bottom-right)
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

            // Ad view inset (matches SponsoredAffiliateCard padding)
            adView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            adView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            adView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            adView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            // Icon tile
            iconTile.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            iconTile.topAnchor.constraint(equalTo: adView.topAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 52),
            iconTile.heightAnchor.constraint(equalToConstant: 52),

            iconImageView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 40),
            iconImageView.heightAnchor.constraint(equalToConstant: 40),

            // Headline — right of icon, full remaining width
            headlineLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 10),
            headlineLabel.topAnchor.constraint(equalTo: adView.topAnchor),
            headlineLabel.trailingAnchor.constraint(equalTo: adView.trailingAnchor),

            // Body — below headline
            bodyLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 3),
            bodyLabel.trailingAnchor.constraint(equalTo: adView.trailingAnchor),

            // Advertiser — below body
            advertiserLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            advertiserLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 3),
            advertiserLabel.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor),

            // CTA — bottom-right
            ctaButton.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            ctaButton.bottomAnchor.constraint(equalTo: adView.bottomAnchor),
            ctaButton.heightAnchor.constraint(equalToConstant: 24),
            ctaButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            // AdChoices — bottom-right, above CTA
            adChoicesContainer.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            adChoicesContainer.bottomAnchor.constraint(equalTo: ctaButton.topAnchor, constant: -4),
            adChoicesContainer.widthAnchor.constraint(equalToConstant: 16),
            adChoicesContainer.heightAnchor.constraint(equalToConstant: 16),

            // Ad badge
            adBadge.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            adBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
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
        adView.iconView = iconImageView
        adView.callToActionView = ctaButton
        adView.advertiserView = advertiserLabel
        adView.adChoicesView = adChoicesContainer

        // Populate with ad assets
        headlineLabel.text = ad.headline
        bodyLabel.text = ad.body
        bodyLabel.isHidden = (ad.body == nil)
        advertiserLabel.text = ad.advertiser
        advertiserLabel.isHidden = (ad.advertiser == nil)
        ctaButton.setTitle(ad.callToAction, for: .normal)
        ctaButton.isHidden = (ad.callToAction == nil)

        if let icon = ad.icon?.image {
            iconImageView.image = icon
            iconImageView.isHidden = false
        } else {
            iconImageView.isHidden = true
        }

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
