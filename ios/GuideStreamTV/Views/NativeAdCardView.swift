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
//  When `compact` is true the card uses a 56pt icon square instead of the
//  120pt media square, hides the body label, and anchors the text column
//  to the icon — matching the row-card layout used by inline ad slots and
//  the Reels carousel.
//
//  When `feedStyle` is also true the card renders the 88pt inline-feed chip
//  row instead: opaque Theme.surface, 60pt icon, orange AD badge above the
//  headline, orange pill CTA, no dismiss X. `feedStyle` alone (without
//  `compact`) changes nothing.
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
    var compact: Bool = false
    var feedStyle: Bool = false
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> NativeAdContainer {
        let container = NativeAdContainer(compact: compact, feedStyle: feedStyle)
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

    let compact: Bool
    let feedStyle: Bool

    /// True only for the inline-feed chip (compact + feedStyle). Gates every
    /// style and layout difference below so all pre-existing appearances —
    /// including the Reels carousel's compact card — are untouched.
    private var isFeedChip: Bool { compact && feedStyle }

    private let adView = NativeAdView()
    private let bgEffect = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let navyOverlay = UIView()
    private let mediaView = MediaView()
    private let iconView = UIImageView()
    private let textStack = UIStackView()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let ctaButton = UIButton(type: .system)
    private let advertiserLabel = UILabel()
    private let adBadge = UILabel()
    private let dismissButton = UIButton(type: .system)
    private let adChoicesContainer = AdChoicesView()

    /// Text-stack leading constraint anchored to the icon — swappeable in
    /// configure() when the ad has no icon image.
    private var textStackLeadingWithIcon: NSLayoutConstraint?
    private var textStackLeadingNoIcon: NSLayoutConstraint?

    init(compact: Bool, feedStyle: Bool) {
        self.compact = compact
        self.feedStyle = feedStyle
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Setup

    private func setupViews() {
        if isFeedChip {
            // Feed chip: opaque Theme.surface — no blur, no navy tint.
            backgroundColor = UIColor(red: 0x0B/255, green: 0x12/255, blue: 0x1C/255, alpha: 1)
            layer.cornerRadius = 14
            layer.borderWidth = 1
            layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
            clipsToBounds = true
        } else {
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
        }

        // GADNativeAdView — fills the card edge-to-edge so every registered
        // asset view lies fully inside the native ad view (validator requirement).
        // Manually framed (translatesAutoresizingMaskIntoConstraints = true) so
        // layoutSubviews() can pin it to integral bounds — the AdMob validator's
        // "assets outside native ad view" check is a known false-positive when the
        // ad view or its asset frames land on sub-pixel point values.
        adView.translatesAutoresizingMaskIntoConstraints = true
        adView.clipsToBounds = true
        addSubview(adView)

        if !compact {
            // Media view (120pt square) — shows the ad's main image/video and is
            // registered as adView.mediaView. Sized to 120x120 so the AdMob native
            // ad validator's "media view too small for video" check passes.
            // Aspect-fit so non-square creatives are letterboxed within the box
            // and the media content never overflows the ad view (validator).
            mediaView.translatesAutoresizingMaskIntoConstraints = false
            mediaView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
            mediaView.contentMode = .scaleAspectFit
            mediaView.layer.cornerRadius = 8
            mediaView.layer.borderWidth = 0.5
            mediaView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
            mediaView.clipsToBounds = true
            adView.addSubview(mediaView)
        } else if isFeedChip {
            // Feed chip: 60pt icon square, radius 10, aspect-fill.
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.contentMode = .scaleAspectFill
            iconView.layer.cornerRadius = 10
            iconView.clipsToBounds = true
            adView.addSubview(iconView)
        } else {
            // Compact: 56pt icon square instead of the 120pt media square.
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
            iconView.contentMode = .scaleAspectFit
            iconView.layer.cornerRadius = 8
            iconView.layer.borderWidth = 0.5
            iconView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
            iconView.clipsToBounds = true
            adView.addSubview(iconView)
        }

        // Headline (12pt heavy, white, 2 lines — 13pt on the feed chip)
        headlineLabel.font = .systemFont(ofSize: isFeedChip ? 13 : 12, weight: .heavy)
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

        // Advertiser (9pt, 45% white — 9.5pt on the feed chip)
        advertiserLabel.font = .systemFont(ofSize: isFeedChip ? 9.5 : 9, weight: .regular)
        advertiserLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        advertiserLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Text column — vertically centered between media/icon and CTA
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .fill
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(headlineLabel)
        textStack.addArrangedSubview(bodyLabel)
        textStack.addArrangedSubview(advertiserLabel)
        adView.addSubview(textStack)

        // CTA button (orange pill) — trailing edge, vertically centered.
        // Feed chip: radius 12, 11pt bold text, 12×6 content insets, sized by
        // content instead of a fixed height.
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        ctaButton.titleLabel?.font = .systemFont(ofSize: isFeedChip ? 11 : 10, weight: .bold)
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.backgroundColor = UIColor(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255, alpha: 1)
        ctaButton.layer.cornerRadius = isFeedChip ? 12 : 4
        ctaButton.clipsToBounds = true
        ctaButton.isUserInteractionEnabled = false
        if isFeedChip {
            ctaButton.directionalContentEdgeInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        } else {
            ctaButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        }
        ctaButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        ctaButton.setContentHuggingPriority(.required, for: .horizontal)
        adView.addSubview(ctaButton)

        // AdChoices container — top-trailing corner of the ad view, clear of
        // every other registered asset and unobscured so it stays tappable.
        adChoicesContainer.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(adChoicesContainer)

        // "Ad" attribution badge — a subview of adView (so the validator sees
        // it inside the native ad view) positioned at the top of the text
        // column, above the headline, clear of media/text/CTA/AdChoices.
        if isFeedChip {
            // Feed chip: orange "AD" badge pill, pinned directly above the
            // headline at the head of the text column.
            adBadge.text = "AD"
            adBadge.font = .systemFont(ofSize: 9, weight: .bold)
            adBadge.textColor = UIColor(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255, alpha: 1)
            adBadge.backgroundColor = UIColor(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255, alpha: 0.18)
        } else {
            adBadge.text = "Ad"
            adBadge.font = .systemFont(ofSize: 9, weight: .bold)
            adBadge.textColor = UIColor.white.withAlphaComponent(0.85)
            adBadge.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        }
        adBadge.layer.cornerRadius = 4
        adBadge.clipsToBounds = true
        adBadge.textAlignment = .center
        adBadge.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(adBadge)

        // Dismiss X — sits to the left of AdChoices in the top-trailing area so
        // it never covers the AdChoices control. Decorative (not a registered
        // asset), so it stays on the container view. Not rendered on the feed
        // chip — the caller's dismissal closure stays wired, just unused.
        if !isFeedChip {
            dismissButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            dismissButton.tintColor = UIColor.white.withAlphaComponent(0.40)
            dismissButton.translatesAutoresizingMaskIntoConstraints = false
            dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
            addSubview(dismissButton)
        }

        // Build constraints — common ones always active, media/icon and
        // chip-specific ones branched on compact / isFeedChip.
        var constraints: [NSLayoutConstraint] = []

        if !isFeedChip {
            // Background fills container
            constraints.append(contentsOf: [
                bgEffect.topAnchor.constraint(equalTo: topAnchor),
                bgEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
                bgEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
                bgEffect.trailingAnchor.constraint(equalTo: trailingAnchor),

                navyOverlay.topAnchor.constraint(equalTo: topAnchor),
                navyOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
                navyOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
                navyOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        // Note: adView is manually framed in layoutSubviews() with integral
        // bounds (see override below), so no Auto Layout pins are activated
        // here. Asset constraints relative to adView remain unchanged.

        // AdChoices — top-trailing corner of the ad view, clear of all
        // other assets and unobscured so it stays tappable. Always rendered —
        // the SDK draws its own marker when no adChoicesView is registered.
        // Containment clamps keep the asset fully inside adView (validator).
        constraints.append(contentsOf: [
            adChoicesContainer.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -8),
            adChoicesContainer.topAnchor.constraint(equalTo: adView.topAnchor, constant: 8),
            adChoicesContainer.widthAnchor.constraint(equalToConstant: isFeedChip ? 14 : 16),
            adChoicesContainer.heightAnchor.constraint(equalToConstant: isFeedChip ? 14 : 16),
            adChoicesContainer.leadingAnchor.constraint(greaterThanOrEqualTo: adView.leadingAnchor, constant: 8),
            adChoicesContainer.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -8),
        ])

        // CTA — trailing edge, vertically centered. Containment clamps keep
        // the asset fully inside adView (validator). The feed chip sizes the
        // pill from its content insets instead of a fixed height.
        constraints.append(contentsOf: [
            ctaButton.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),
            ctaButton.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            ctaButton.topAnchor.constraint(greaterThanOrEqualTo: adView.topAnchor, constant: 8),
            ctaButton.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -8),
            ctaButton.leadingAnchor.constraint(greaterThanOrEqualTo: adView.leadingAnchor, constant: 8),
        ])
        if !isFeedChip {
            constraints.append(ctaButton.heightAnchor.constraint(equalToConstant: 24))
        }

        // Text column — vertically centered; on the feed chip it shifts down
        // 8.5pt so the badge + column block centers as a unit. Trailing
        // containment clamp keeps the stack inside adView (validator).
        constraints.append(contentsOf: [
            textStack.trailingAnchor.constraint(equalTo: ctaButton.leadingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: adView.centerYAnchor, constant: isFeedChip ? 8.5 : 0),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: adView.topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -8),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: adView.trailingAnchor, constant: -8),
        ])

        // Ad attribution badge — required attribution. Containment clamps
        // keep the badge fully inside adView (validator). Feed chip: a fixed
        // 28×15 pill sitting directly above the headline at the head of the
        // text column. Otherwise: top of the text-column region, as before.
        if isFeedChip {
            constraints.append(contentsOf: [
                adBadge.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
                adBadge.bottomAnchor.constraint(equalTo: textStack.topAnchor, constant: -2),
                adBadge.heightAnchor.constraint(equalToConstant: 15),
                adBadge.widthAnchor.constraint(equalToConstant: 28),
                adBadge.topAnchor.constraint(greaterThanOrEqualTo: adView.topAnchor, constant: 8),
            ])
        } else {
            constraints.append(contentsOf: [
                adBadge.topAnchor.constraint(equalTo: adView.topAnchor, constant: 10),
                adBadge.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
                adBadge.heightAnchor.constraint(equalToConstant: 16),
                adBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
                adBadge.trailingAnchor.constraint(lessThanOrEqualTo: adView.trailingAnchor, constant: -8),
                adBadge.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -8),
            ])
        }

        // Dismiss — immediately to the left of AdChoices, top of card, so it
        // never covers the AdChoices control. Decorative (container view);
        // not rendered on the feed chip.
        if !isFeedChip {
            constraints.append(contentsOf: [
                dismissButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                dismissButton.trailingAnchor.constraint(equalTo: adChoicesContainer.leadingAnchor, constant: -4),
                dismissButton.widthAnchor.constraint(equalToConstant: 28),
                dismissButton.heightAnchor.constraint(equalToConstant: 28),
            ])
        }

        if !compact {
            // Media — 120pt square, leading, vertically centered. Sized so the
            // validator's "media view too small for video" check passes.
            // Containment clamps keep the asset fully inside adView (validator).
            constraints.append(contentsOf: [
                mediaView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
                mediaView.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
                mediaView.widthAnchor.constraint(equalToConstant: 120),
                mediaView.heightAnchor.constraint(equalToConstant: 120),
                mediaView.topAnchor.constraint(greaterThanOrEqualTo: adView.topAnchor, constant: 8),
                mediaView.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -8),

                // Text column leading — anchored to media trailing.
                textStack.leadingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: 10),
            ])
        } else {
            // Icon — 56pt square (60pt on the feed chip), leading, vertically
            // centered.
            constraints.append(contentsOf: [
                iconView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
                iconView.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: isFeedChip ? 60 : 56),
                iconView.heightAnchor.constraint(equalToConstant: isFeedChip ? 60 : 56),
                iconView.topAnchor.constraint(greaterThanOrEqualTo: adView.topAnchor, constant: 8),
                iconView.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -8),
            ])
            // Text column leading — anchored to icon trailing by default;
            // swapped to adView leading + 12 in configure() when no icon image.
            textStackLeadingWithIcon = textStack.leadingAnchor.constraint(
                equalTo: iconView.trailingAnchor, constant: 10
            )
            textStackLeadingNoIcon = textStack.leadingAnchor.constraint(
                equalTo: adView.leadingAnchor, constant: 12
            )
            constraints.append(textStackLeadingWithIcon!)
        }

        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Configure

    func configure(with ad: NativeAd) {
        // Register asset views on the GADNativeAdView so the SDK can
        // track impressions and handle clicks.
        adView.headlineView = headlineLabel
        adView.bodyView = bodyLabel
        adView.callToActionView = ctaButton
        adView.advertiserView = advertiserLabel
        adView.adChoicesView = adChoicesContainer

        if !compact {
            adView.mediaView = mediaView

            // Main media asset — shown through the MediaView (validator requirement).
            mediaView.mediaContent = ad.mediaContent
        } else {
            adView.iconView = iconView

            // Populate icon from the ad's icon image. If the ad has no icon,
            // hide the icon view and re-anchor textStack to adView leading.
            if let iconImage = ad.icon?.image {
                iconView.image = iconImage
                iconView.isHidden = false
                textStackLeadingWithIcon?.isActive = true
                textStackLeadingNoIcon?.isActive = false
            } else {
                iconView.isHidden = true
                textStackLeadingWithIcon?.isActive = false
                textStackLeadingNoIcon?.isActive = true
            }
        }

        // Populate with ad assets
        headlineLabel.text = ad.headline
        bodyLabel.text = ad.body
        if compact {
            bodyLabel.isHidden = true
        } else {
            bodyLabel.isHidden = (ad.body == nil)
        }
        advertiserLabel.text = ad.advertiser
        advertiserLabel.isHidden = (ad.advertiser == nil)
        ctaButton.setTitle(ad.callToAction, for: .normal)
        ctaButton.isHidden = (ad.callToAction == nil)

        // Associate the ad — must be the last step, after all asset
        // views are populated and registered.
        adView.nativeAd = ad
    }

    // MARK: - Layout

    /// Pixel-aligns `adView` and every registered asset to integral frame
    /// rects so the AdMob native ad validator's "assets outside native ad
    /// view" check (a known false-positive on sub-pixel frames) passes.
    /// Purely a rounding pass — visually imperceptible. No setNeedsLayout /
    /// setNeedsUpdateConstraints to avoid a layout loop.
    override func layoutSubviews() {
        super.layoutSubviews()

        // Frame adView to fill the card with whole-number width/height.
        adView.frame = CGRect(x: 0,
                              y: 0,
                              width: bounds.width.rounded(.down),
                              height: bounds.height.rounded(.down))
        adView.layoutIfNeeded()

        // Snap every registered asset view to an integral rect strictly inside
        // adView. Frames in adView's coordinate space:
        if compact {
            for view in [iconView, ctaButton, adChoicesContainer, adBadge, textStack] {
                view.frame = integralRect(view.frame)
            }
        } else {
            for view in [mediaView, ctaButton, adChoicesContainer, adBadge, textStack] {
                view.frame = integralRect(view.frame)
            }
        }
        // Frames in textStack's coordinate space:
        for view in [headlineLabel, bodyLabel, advertiserLabel] {
            view.frame = integralRect(view.frame)
        }
    }

    /// Rounds a rect's origin to the nearest whole point and floors its size,
    /// yielding an integral-pixel frame that never exceeds the original.
    private func integralRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x.rounded(),
               y: rect.origin.y.rounded(),
               width: rect.width.rounded(.down),
               height: rect.height.rounded(.down))
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
    var compact: Bool = false
    var feedStyle: Bool = false
    var onDismiss: () -> Void
    var body: some View { EmptyView() }
}
#endif
