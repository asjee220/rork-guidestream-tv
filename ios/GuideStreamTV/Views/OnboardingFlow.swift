//
//  OnboardingFlow.swift
//  GuideStreamTV
//

import SwiftUI
import AuthenticationServices
import UserNotifications
import UIKit

// MARK: - Coordinator

struct OnboardingFlow: View {
    var startStep: Int = 0
    var onFinish: () -> Void
    var onWidgetSettings: () -> Void = {}

    @State private var step: Int = 0
    @State private var selectedServices: Set<String> = AuthViewModel.shared.selectedServices
    @State private var pushOn: Bool = AuthViewModel.shared.notifyPushEnabled
    @State private var smsOn: Bool = AuthViewModel.shared.notifySMSEnabled

    var body: some View {
        ZStack {
            Color.navy.ignoresSafeArea()

            // Atmosphere
            GeometryReader { geo in
                Circle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: geo.size.width * 0.9)
                    .blur(radius: 90)
                    .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.35)
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: geo.size.width * 0.7)
                    .blur(radius: 80)
                    .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Group {
                switch step {
                case 0:
                    WelcomeOnboardingView(
                        onContinue: { advance() },
                        onSignIn: { advance() }
                    )
                case 1:
                    ConnectServicesView(
                        selected: $selectedServices,
                        onContinue: {
                            AuthViewModel.shared.setSelectedServices(selectedServices)
                            advance()
                        }
                    )
                default:
                    StayNotifiedView(
                        pushOn: $pushOn,
                        smsOn: $smsOn,
                        onContinue: {
                            AuthViewModel.shared.setNotificationPreferences(push: pushOn, sms: smsOn)
                            onFinish()
                        },
                        onWidgetSettings: onWidgetSettings
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Skip welcome if user is already authenticated
            if step == 0 && startStep > 0 {
                step = startStep
            }
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            step += 1
        }
    }
}

// MARK: - Welcome

struct WelcomeOnboardingView: View {
    var onContinue: () -> Void
    var onSignIn: () -> Void

    @State private var auth = AuthViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80)

            GuideStreamLogo()
                .frame(height: 120)
                .padding(.bottom, 8)

            // Gradient hairline underline
            LinearGradient(
                colors: [Color.blue.opacity(0.0), Color.blue, Color.orange, Color.orange.opacity(0.0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 2)
            .frame(maxWidth: 260)
            .padding(.bottom, 32)

            // Card with copy + auth options
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("Every show. Every service.")
                        .font(.custom("SF Pro Text", size: 15))
                        .foregroundStyle(Color.textSecondary)
                    Text("One place to rule them all.")
                        .font(.custom("SF Pro Display", size: 18).weight(.bold))
                        .foregroundStyle(.white)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 4)

                // Apple / Google row
                HStack(spacing: 10) {
                    SignInWithAppleButton(.signIn) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        Task {
                            await auth.handleAppleCompletion(result)
                            if auth.isSignedIn { onContinue() }
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(auth.isAuthenticating)

                    Button {
                        Task {
                            await auth.signInWithGoogle()
                            if auth.isSignedIn { onContinue() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            GoogleGlyph()
                                .frame(width: 18, height: 18)
                            Text("Google")
                                .font(.custom("SF Pro Text", size: 15).weight(.semibold))
                                .foregroundStyle(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(auth.isAuthenticating)
                }

                // Primary CTA
                Button {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    auth.continueAsGuest()
                    onContinue()
                } label: {
                    HStack(spacing: 8) {
                        Text("Get Started Free")
                            .font(.custom("SF Pro Text", size: 16).weight(.bold))
                        Image(systemName: "arrow.right")
                            .scaledFont(size: 15, weight: .bold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.50, blue: 0.96), Color.blue],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.blue.opacity(0.55), radius: 22, x: 0, y: 0)
                }
                .buttonStyle(.plain)

                Button(action: onSignIn) {
                    Text("Sign in to existing account")
                        .font(.custom("SF Pro Text", size: 13))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)

                if let err = auth.lastError {
                    Text(err)
                        .font(.custom("SF Pro Text", size: 11))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GuideStreamLogo: View {
    var body: some View {
        Image("GuideStreamLogo")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 280)
            .accessibilityLabel("GuideStream TV")
    }
}

/// Multi-color "G" glyph for the Google button.
private struct GoogleGlyph: View {
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
                let lineWidth: CGFloat = size.width * 0.22
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let radius = rect.width / 2 - lineWidth / 2

                func arc(_ start: Double, _ end: Double, _ color: Color) {
                    var path = Path()
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(start),
                        endAngle: .degrees(end),
                        clockwise: false
                    )
                    ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }

                arc(-50, 60, Color(red: 0.92, green: 0.26, blue: 0.21))
                arc(60, 150, Color(red: 0.98, green: 0.74, blue: 0.02))
                arc(150, 230, Color(red: 0.20, green: 0.66, blue: 0.33))
                arc(230, 310, Color(red: 0.26, green: 0.52, blue: 0.96))

                let barRect = CGRect(
                    x: center.x,
                    y: center.y - lineWidth * 0.35,
                    width: rect.width / 2 - lineWidth * 0.2,
                    height: lineWidth * 0.7
                )
                ctx.fill(Path(barRect), with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)))
            }
        }
    }
}

// MARK: - Onboarding header

private struct OnboardingHeader: View {
    let progress: CGFloat // 0...1
    var onClose: (() -> Void)?

    var body: some View {
        HStack {
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .opacity(onClose == nil ? 0 : 1)
            .disabled(onClose == nil)

            Spacer()

            Text("GuideStream Prototype")
                .font(.custom("SF Pro Text", size: 16).weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Image(systemName: "ellipsis")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .opacity(0.0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .background(Color.white.opacity(0.04).ignoresSafeArea(edges: .top))

        // Split progress bar — blue (done) + orange (current)
        HStack(spacing: 6) {
            Capsule()
                .fill(LinearGradient(colors: [Color.blue.opacity(0.6), Color.blue],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 3)
            Capsule()
                .fill(progress >= 1.0
                      ? AnyShapeStyle(LinearGradient(colors: [Color.orange.opacity(0.6), Color.orange],
                                                    startPoint: .leading, endPoint: .trailing))
                      : AnyShapeStyle(Color.white.opacity(0.12)))
                .frame(height: 3)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }
}

// MARK: - Connect Services

private struct ServiceItem: Identifiable {
    let id: String
    let name: String
    let bg: Color
    let glow: Color
    let display: ServiceDisplay
}

private enum ServiceDisplay {
    case text(String, Color, fontWeight: Font.Weight, design: Font.Design)
    case symbol(String, Color) // SF symbol
    case symbolText(String, String, Color) // symbol + suffix
    case star
}

private let services: [ServiceItem] = [
    .init(id: "netflix", name: "Netflix",
          bg: .black, glow: Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255),
          display: .text("N", Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255), fontWeight: .black, design: .serif)),
    .init(id: "prime", name: "Prime",
          bg: Color(red: 0x1A/255, green: 0x20/255, blue: 0x2C/255),
          glow: Color(red: 0x00/255, green: 0xA8/255, blue: 0xE1/255),
          display: .text("prime\nvideo", Color.white, fontWeight: .bold, design: .default)),
    .init(id: "hulu", name: "Hulu",
          bg: Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255),
          glow: Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255),
          display: .text("hulu", Color.black, fontWeight: .black, design: .rounded)),
    .init(id: "disney", name: "Disney+",
          bg: Color(red: 0x0E/255, green: 0x29/255, blue: 0x3F/255),
          glow: Color(red: 0x11/255, green: 0x3C/255, blue: 0xCF/255),
          display: .text("Disney+", Color.white, fontWeight: .semibold, design: .serif)),
    .init(id: "hbo", name: "HBO",
          bg: Color(red: 0x00/255, green: 0x1E/255, blue: 0xE0/255),
          glow: Color(red: 0x00/255, green: 0x55/255, blue: 0xFF/255),
          display: .text("max", Color.white, fontWeight: .black, design: .default)),
    .init(id: "peacock", name: "Peacock",
          bg: .black, glow: Color(red: 0xFF/255, green: 0x66/255, blue: 0x00/255),
          display: .text("PEACOCK", Color.white, fontWeight: .bold, design: .default)),
    .init(id: "appletv", name: "Apple TV+",
          bg: .black, glow: Color.white,
          display: .symbolText("applelogo", "tv+", Color.white)),
    .init(id: "paramount", name: "Paramount+",
          bg: Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255),
          glow: Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255),
          display: .text("PARAMOUNT+", Color.white, fontWeight: .black, design: .default)),
    .init(id: "amc", name: "AMC+",
          bg: .black, glow: Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255),
          display: .text("amc+", Color.white, fontWeight: .black, design: .default)),
    .init(id: "tubi", name: "Tubi",
          bg: Color(red: 0xD3/255, green: 0x14/255, blue: 0x21/255),
          glow: Color(red: 0xFF/255, green: 0x40/255, blue: 0x40/255),
          display: .text("tubi", Color.white, fontWeight: .black, design: .rounded)),
    .init(id: "starz", name: "Starz",
          bg: Color(red: 0x14/255, green: 0x05/255, blue: 0x20/255),
          glow: Color(red: 0xFF/255, green: 0xC8/255, blue: 0x1E/255),
          display: .star),
    .init(id: "espn", name: "ESPN",
          bg: Color(red: 0x00/255, green: 0x1A/255, blue: 0x70/255),
          glow: Color(red: 0xD0/255, green: 0x21/255, blue: 0x31/255),
          display: .text("ESPN", Color.white, fontWeight: .black, design: .default))
]

struct ConnectServicesView: View {
    @Binding var selected: Set<String>
    var onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(progress: 1.0)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Which services do you have?")
                        .font(.custom("SF Pro Display", size: 28).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.top, 24)

                    Text("Select all that apply to personalise your feed")
                        .font(.custom("SF Pro Text", size: 15))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.bottom, 18)

                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(services) { svc in
                            ServiceTile(
                                service: svc,
                                isSelected: selected.contains(svc.id),
                                onTap: { toggle(svc.id) }
                            )
                        }
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }

            VStack(spacing: 14) {
                Text("\(selected.count) service\(selected.count == 1 ? "" : "s") selected")
                    .font(.custom("SF Pro Text", size: 13))
                    .foregroundStyle(Color.textSecondary)

                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text("Build My Feed")
                            .font(.custom("SF Pro Text", size: 16).weight(.bold))
                        Image(systemName: "arrow.right")
                            .scaledFont(size: 14, weight: .bold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .opacity(selected.isEmpty ? 0.35 : 1.0)
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.orange.opacity(selected.isEmpty ? 0.0 : 0.45),
                            radius: 24, x: 0, y: 0)
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggle(_ id: String) {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        }
    }
}

private struct ServiceTile: View {
    let service: ServiceItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(service.bg)

                    content
                        .padding(8)
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isSelected ? service.glow : Color.white.opacity(0.06),
                                lineWidth: isSelected ? 3 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        ZStack {
                            Circle().fill(service.glow)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .scaledFont(size: 11, weight: .black)
                                .foregroundStyle(service.bg == .black ? .white : .black)
                        }
                        .offset(x: 6, y: -6)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(color: isSelected ? service.glow.opacity(0.55) : .clear,
                        radius: 18, x: 0, y: 0)

                Text(service.name)
                    .font(.custom("SF Pro Text", size: 12).weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch service.display {
        case .text(let str, let color, let weight, let design):
            Text(str)
                .scaledFont(size: textSize(for: str), weight: weight, design: design)
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
        case .symbol(let name, let color):
            Image(systemName: name)
                .scaledFont(size: 32, weight: .bold)
                .foregroundStyle(color)
        case .symbolText(let symbol, let suffix, let color):
            HStack(spacing: 2) {
                Image(systemName: symbol)
                    .scaledFont(size: 22, weight: .bold)
                Text(suffix)
                    .scaledFont(size: 18, weight: .bold)
            }
            .foregroundStyle(color)
        case .star:
            Image(systemName: "star.fill")
                .scaledFont(size: 36)
                .foregroundStyle(Color(red: 0xFF/255, green: 0xC8/255, blue: 0x1E/255))
        }
    }

    private func textSize(for str: String) -> CGFloat {
        if str.count <= 1 { return 36 }
        if str.count <= 4 { return 26 }
        if str.contains("\n") { return 16 }
        return 14
    }
}

// MARK: - Stay Notified

struct StayNotifiedView: View {
    @Binding var pushOn: Bool
    @Binding var smsOn: Bool
    var onContinue: () -> Void
    var onWidgetSettings: () -> Void

    private func handlePushToggle(_ newValue: Bool) {
        guard newValue else { return }
        Task { @MainActor in
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    pushOn = false
                }
            } catch {
                pushOn = false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(progress: 1.0)

            Spacer(minLength: 24)

            // Bell hero
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 220, height: 220)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.36, green: 0.42, blue: 0.96),
                                     Color(red: 0.62, green: 0.40, blue: 0.95)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)
                    .shadow(color: Color(red: 0.45, green: 0.40, blue: 0.95).opacity(0.55),
                            radius: 30, x: 0, y: 0)
                Image(systemName: "bell.fill")
                    .scaledFont(size: 38, weight: .semibold)
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("Never miss an episode.")
                    .font(.custom("SF Pro Display", size: 30).weight(.bold))
                    .foregroundStyle(.white)
                Text("Stay updated with your favorite shows")
                    .font(.custom("SF Pro Text", size: 15))
                    .foregroundStyle(Color.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 16)
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            // Notification options card
            VStack(spacing: 0) {
                NotifyRow(
                    icon: "bell.fill",
                    iconBg: Color.orange.opacity(0.18),
                    iconTint: Color.orange,
                    title: "New episode alerts",
                    subtitle: "Push notification",
                    trailing: .toggle($pushOn, tint: Color.orange)
                )
                .onChange(of: pushOn) { _, newValue in
                    handlePushToggle(newValue)
                }
                Divider().background(Color.white.opacity(0.06))
                NotifyRow(
                    icon: "message.fill",
                    iconBg: Color.blue.opacity(0.18),
                    iconTint: Color.blue,
                    title: "Episode synopsis by text",
                    subtitle: "SMS",
                    trailing: .toggle($smsOn, tint: Color.blue)
                )
                Divider().background(Color.white.opacity(0.06))
                NotifyRow(
                    icon: "iphone",
                    iconBg: Color(red: 0.55, green: 0.40, blue: 0.95).opacity(0.18),
                    iconTint: Color(red: 0.65, green: 0.50, blue: 1.0),
                    title: "Home screen widget",
                    subtitle: "Configure size, content & appearance",
                    trailing: .chevron(action: onWidgetSettings)
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)

            Spacer(minLength: 24)

            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text("I'm all set")
                        .font(.custom("SF Pro Text", size: 16).weight(.bold))
                    Image(systemName: "arrow.right")
                        .scaledFont(size: 14, weight: .bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.orange.opacity(0.55), radius: 28, x: 0, y: 0)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum NotifyTrailingKind {
    case toggle(Binding<Bool>, tint: Color)
    case chevron(action: () -> Void)
}

private struct NotifyRow: View {
    let icon: String
    let iconBg: Color
    let iconTint: Color
    let title: String
    let subtitle: String
    let trailing: NotifyTrailingKind

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(iconBg)
                Image(systemName: icon)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(iconTint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("SF Pro Text", size: 15).weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.custom("SF Pro Text", size: 12))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 8)

            switch trailing {
            case .toggle(let binding, let tint):
                Toggle("", isOn: binding)
                    .labelsHidden()
                    .tint(tint)
            case .chevron(let action):
                Button(action: action) {
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview("Welcome") {
    OnboardingFlow(onFinish: {})
}

#Preview("Services") {
    OnboardingFlow(startStep: 1, onFinish: {})
}

#Preview("Notify") {
    OnboardingFlow(startStep: 2, onFinish: {})
}
