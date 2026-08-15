//
//  OnboardingFlow.swift
//  GuideStreamTV
//

import SwiftUI
import AuthenticationServices
import UserNotifications
import UIKit
import Supabase

// MARK: - Coordinator

struct OnboardingFlow: View {
    var startStep: Int = 0
    var onFinish: () -> Void
    var onWidgetSettings: () -> Void = {}

    @State private var step: Int = 0
    @State private var selectedServices: Set<String> = AuthViewModel.shared.selectedServices
    @State private var pushOn: Bool = AuthViewModel.shared.notifyPushEnabled
    @State private var showEmailAuth: Bool = false
    @State private var followedShowPosters: [String] = []
    @State private var followedShowsCount: Int = 0
    @State private var followedCreatorsCount: Int = 0
    @State private var showWidgetSheet: Bool = false

    var body: some View {
        ZStack {
            BrandBackground()

            Group {
                switch step {
                case 0:
                    WelcomeOnboardingView(
                        onContinue: { advance() },
                        onEmailAuth: { showEmailAuth = true },
                        onGuest: {
                            AuthViewModel.shared.continueAsGuest()
                            advance()
                        }
                    )
                case 1:
                    ConnectServicesView(
                        selected: $selectedServices,
                        onContinue: {
                            AuthViewModel.shared.setSelectedServices(selectedServices)
                            advance()
                        },
                        onSkip: {
                            AuthViewModel.shared.setSelectedServices(selectedServices)
                            advance()
                        }
                    )
                case 2:
                    WatchingNowView(
                        selectedServices: selectedServices,
                        onContinue: { inserts in
                            followedShowsCount = inserts.count
                            followedShowPosters = inserts.compactMap { $0.poster_url }
                            commitInserts(inserts) { advance() }
                        },
                        onSkip: { advance() },
                        onBack: { goBack() },
                        onSkipAll: { finishOnboarding() },
                        currentStep: 2,
                        totalSteps: OnboardingHeader.stepNames.count
                    )
                case 3:
                    FollowCreatorsOnboardingView(
                        onContinue: { inserts in
                            followedCreatorsCount = inserts.count
                            commitInserts(inserts) { advance() }
                        },
                        onSkip: { finishOnboarding() },
                        onBack: { goBack() },
                        onSkipAll: { finishOnboarding() },
                        currentStep: 3,
                        totalSteps: OnboardingHeader.stepNames.count
                    )
                default:
                    StayNotifiedView(
                        pushOn: $pushOn,
                        onContinue: {
                            AuthViewModel.shared.setNotificationPreferences(push: pushOn, sms: false)
                            if !AuthViewModel.shared.isSignedIn {
                                AuthViewModel.shared.continueAsGuest()
                            }
                            finishOnboarding()
                        },
                        onBack: { goBack() },
                        onWidgetSettings: { showWidgetSheet = true },
                        currentStep: 4,
                        totalSteps: OnboardingHeader.stepNames.count,
                        posterUrls: followedShowPosters,
                        showCount: followedShowsCount,
                        creatorCount: followedCreatorsCount
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showWidgetSheet) {
            WidgetInstructionSheet(onDismiss: { showWidgetSheet = false })
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView(
                onAuthenticated: {
                    showEmailAuth = false
                    if !AuthViewModel.shared.hasCompletedOnboarding {
                        advance()
                    }
                },
                onClose: { showEmailAuth = false }
            )
        }
        .onChange(of: AuthViewModel.shared.selectedServices) { _, newValue in
            selectedServices = newValue
        }
        .onAppear {
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

    private func goBack() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            step -= 1
        }
    }

    private func finishOnboarding() {
        if !AuthViewModel.shared.isSignedIn {
            AuthViewModel.shared.continueAsGuest()
        }
        AuthViewModel.shared.completeOnboarding()
        onFinish()
    }

    private func commitInserts(_ inserts: [UserStreamInsert], completion: @escaping () -> Void) {
        guard !inserts.isEmpty else { completion(); return }
        let isGuest = !AuthViewModel.shared.isAuthenticated
        let conflictTarget = isGuest ? "device_id,title_id" : "user_id,title_id"
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("user_streams")
                    .upsert(inserts, onConflict: conflictTarget)
                    .execute()
            } catch {
                print("[GuideStream] ⚠️ seed upsert failed (conflict: \(conflictTarget)): \(error)")
            }
            await MainActor.run { completion() }
        }
    }
}

// MARK: - Welcome

struct WelcomeOnboardingView: View {
    var onContinue: () -> Void
    var onEmailAuth: () -> Void
    var onGuest: () -> Void

    @State private var auth = AuthViewModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DriftingPosterWall(reduceMotion: reduceMotion)
            welcomeContent
            VStack {
                HStack {
                    Spacer()
                    ChannelChip()
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80)

            GuideStreamLogo()
                .frame(height: 120)
                .overlay {
                    if !reduceMotion {
                        TuningShimmer()
                            .allowsHitTesting(false)
                    }
                }
                .padding(.bottom, 8)

            LinearGradient(
                colors: [Color.blue.opacity(0.0), Color.blue, Color.orange, Color.orange.opacity(0.0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 2)
            .frame(maxWidth: 260)
            .padding(.bottom, 32)

            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Every show. Every service.")
                        .font(.custom("SF Pro Text", size: 13))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("What are you watching now?")
                        .font(.custom("SF Pro Display", size: 15).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 4)

                SignInWithAppleButton(.signIn) { request in
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task {
                        await auth.handleAppleCompletion(result)
                        if auth.isSignedIn { onContinue() }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                        Text("Sign in with Google")
                            .font(.custom("SF Pro Text", size: 16).weight(.semibold))
                            .foregroundStyle(Color(red: 0.24, green: 0.24, blue: 0.26))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(auth.isAuthenticating)

                HStack(spacing: 10) {
                    Color.white.opacity(0.1)
                        .frame(height: 1)
                    Text("or")
                        .font(.custom("SF Pro Text", size: 12))
                        .foregroundStyle(Color.textSecondary)
                    Color.white.opacity(0.1)
                        .frame(height: 1)
                }

                Button(action: onEmailAuth) {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .scaledFont(size: 14, weight: .medium)
                            .foregroundStyle(Color(red: 0.96, green: 0.51, blue: 0.12).opacity(0.6))
                        Text("Sign in with email")
                            .font(.custom("SF Pro Text", size: 14).weight(.medium))
                            .foregroundStyle(Color(red: 0.96, green: 0.51, blue: 0.12).opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(red: 0.96, green: 0.51, blue: 0.12).opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onGuest) {
                    Text("Continue as guest")
                        .font(.custom("SF Pro Text", size: 14).weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                if let err = auth.lastError {
                    Text(err)
                        .font(.custom("SF Pro Text", size: 11))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                }

                legalLinksLine
                    .padding(.top, 2)
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

    private var legalLinksLine: some View {
        var attr = AttributedString("By continuing, you agree to our Privacy Policy and Terms of Service.")
        attr.foregroundColor = Color.textTertiary
        if let ppRange = attr.range(of: "Privacy Policy") {
            attr[ppRange].foregroundColor = Color.blue
            attr[ppRange].link = URL(string: "https://guidestream.tv/privacy")
        }
        if let tosRange = attr.range(of: "Terms of Service") {
            attr[tosRange].foregroundColor = Color.blue
            attr[tosRange].link = URL(string: "https://guidestream.tv/terms")
        }
        return Text(attr)
            .font(.custom("SF Pro Text", size: 13))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct GuideStreamLogo: View {
    var body: some View {
        BrandWordmark(wordmarkSize: .large)
    }
}

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

// MARK: - Welcome decorative layers

private struct DriftingPosterWall: View {
    let reduceMotion: Bool
    @State private var animate = false

    private let columns = 4
    private let gap: CGFloat = 8

    private static let tileColors: [Color] = [
        Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255),
        Color(red: 0x1A/255, green: 0x6F/255, blue: 0xE8/255),
        Color(red: 0x00/255, green: 0xA8/255, blue: 0xE1/255),
        Color(red: 0x5B/255, green: 0x2A/255, blue: 0x86/255),
        Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255),
        Color(red: 0x0F/255, green: 0x79/255, blue: 0xAF/255),
        Color(red: 0x77/255, green: 0x2C/255, blue: 0xE8/255),
        Color(red: 0xE4/255, green: 0xA1/255, blue: 0x1B/255),
        Color(red: 0x1D/255, green: 0xB9/255, blue: 0x54/255),
        Color(red: 0x2E/255, green: 0x51/255, blue: 0xA2/255),
    ]

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let tileW = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let tileH = tileW * 3.0 / 2.0
            let rowH = tileH + gap
            let rowsPerCopy = max(1, Int(ceil(height / rowH)) + 1)
            let copyStride = CGFloat(rowsPerCopy) * rowH

            VStack(spacing: gap) {
                tileSet(rows: rowsPerCopy, tileW: tileW, tileH: tileH)
                tileSet(rows: rowsPerCopy, tileW: tileW, tileH: tileH)
            }
            .frame(width: width, alignment: .top)
            .offset(y: animate ? -copyStride : 0)
            .animation(
                reduceMotion ? nil : .linear(duration: 22).repeatForever(autoreverses: false),
                value: animate
            )
            .frame(width: width, height: height, alignment: .top)
            .clipped()
        }
        .ignoresSafeArea()
        .blur(radius: 7)
        .saturation(0.85)
        .opacity(0.30)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.22),
                    .init(color: .black, location: 0.55),
                    .init(color: .clear, location: 0.92),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
        .onAppear { if !reduceMotion { animate = true } }
    }

    private func tileSet(rows: Int, tileW: CGFloat, tileH: CGFloat) -> some View {
        VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<columns, id: \.self) { col in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(gradient(for: row * columns + col))
                            .frame(width: tileW, height: tileH)
                    }
                }
            }
        }
    }

    private func gradient(for index: Int) -> LinearGradient {
        let base = Self.tileColors[index % Self.tileColors.count]
        return LinearGradient(
            colors: [base, Color.black.opacity(0.55)],
            startPoint: UnitPoint(x: 0.933, y: 0.25),
            endPoint: UnitPoint(x: 0.067, y: 0.75)
        )
    }
}

private struct TuningShimmer: View {
    private struct ShimmerPhase {
        var offsetY: CGFloat = -32
        var opacity: Double = 0
    }

    var body: some View {
        LinearGradient(
            colors: [.white.opacity(0.0), .white.opacity(0.28), .white.opacity(0.0)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .keyframeAnimator(initialValue: ShimmerPhase(), repeating: true) { content, value in
            content
                .offset(y: value.offsetY)
                .opacity(value.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.offsetY) {
                LinearKeyframe(32, duration: 3.4)
            }
            KeyframeTrack(\.opacity) {
                CubicKeyframe(1.0, duration: 1.7)
                CubicKeyframe(0.0, duration: 1.7)
            }
        }
    }
}

private struct ChannelChip: View {
    private static let brandOrange = Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255)

    var body: some View {
        Text("CH 01")
            .font(.custom("SF Pro Text", size: 11).weight(.bold))
            .tracking(1.0)
            .foregroundStyle(Self.brandOrange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Self.brandOrange.opacity(0.5), lineWidth: 1)
            )
    }
}

// MARK: - Onboarding header + step indicator

struct OnboardingHeader: View {
    static let stepNames = ["Services", "Watching", "Creators", "Notify"]

    let currentStep: Int
    let totalSteps: Int
    var onBack: (() -> Void)? = nil
    var onSkipAll: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onBack, currentStep > 1 {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }

                Spacer()

                BrandWordmark(wordmarkSize: .nav)

                Spacer()

                if let onSkipAll {
                    Button {
                        onSkipAll()
                    } label: {
                        Text("Skip all")
                            .font(.custom("SF Pro Text", size: 13).weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 36)
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 14)
            .background(Color.white.opacity(0.04).ignoresSafeArea(edges: .top))

            OnboardingStepIndicator(
                currentStep: currentStep,
                totalSteps: totalSteps
            )
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }
}

private struct OnboardingStepIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ScaledMetric private var nodeSize: CGFloat = 26
    @ScaledMetric private var ringSize: CGFloat = 34

    private static let completedBlue = Color(red: 0x1A/255, green: 0x6F/255, blue: 0xE8/255)
    private static let currentOrange = Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    let stepNum = i + 1

                    if i > 0 {
                        connector(behindCompleted: i < currentStep)
                    }

                    node(stepNum: stepNum)
                        .frame(width: ringSize, height: ringSize)
                }
            }

            HStack(spacing: 0) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    if i > 0 {
                        Spacer().frame(width: 20)
                    }
                    Text(OnboardingHeader.stepNames[i])
                        .font(.custom("SF Pro Text", size: 10))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(differentiateWithoutColor ? 0.6 : 0.35))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(currentStep) of \(totalSteps), \(OnboardingHeader.stepNames[currentStep - 1])")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currentStep)
    }

    @ViewBuilder
    private func node(stepNum: Int) -> some View {
        let isCompleted = stepNum < currentStep
        let isCurrent = stepNum == currentStep
        let isUpcoming = stepNum > currentStep

        ZStack {
            if isCurrent {
                Circle()
                    .stroke(
                        Color.white.opacity(differentiateWithoutColor ? 0.25 : 0.14),
                        lineWidth: 2.5
                    )
                    .frame(width: ringSize, height: ringSize)
                Circle()
                    .trim(from: 0, to: 1.0)
                    .stroke(
                        Self.currentOrange,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(-90))
            }

            Circle()
                .fill(isCompleted
                      ? Self.completedBlue.opacity(differentiateWithoutColor ? 1.0 : 0.9)
                      : isCurrent
                        ? Self.currentOrange
                        : Color.clear)
                .frame(width: nodeSize, height: nodeSize)

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else if isCurrent {
                Text("\(stepNum)")
                    .font(.custom("SF Pro Text", size: 12).weight(.bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(stepNum)")
                    .font(.custom("SF Pro Text", size: 12).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(differentiateWithoutColor ? 0.6 : 0.35))
            }

            if isUpcoming {
                Circle()
                    .stroke(
                        Color.white.opacity(differentiateWithoutColor ? 0.3 : 0.18),
                        lineWidth: 1.5
                    )
                    .frame(width: nodeSize, height: nodeSize)
            }
        }
    }

    @ViewBuilder
    private func connector(behindCompleted: Bool) -> some View {
        Capsule()
            .fill(behindCompleted
                  ? Self.completedBlue.opacity(differentiateWithoutColor ? 0.9 : 0.75)
                  : Color.white.opacity(differentiateWithoutColor ? 0.25 : 0.15))
            .frame(height: 1.5)
            .padding(.horizontal, 2)
    }
}

// MARK: - Connect Services (hybrid layout)

struct ConnectServicesView: View {
    @Binding var selected: Set<String>
    var onContinue: () -> Void
    var onSkip: () -> Void

    @State private var serviceQuery: String = ""
    @FocusState private var isSearchFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var filteredPopular: [StreamingService] {
        let q = serviceQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return StreamingCatalog.popular }
        return StreamingCatalog.popular.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var filteredAll: [StreamingService] {
        let q = serviceQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return StreamingCatalog.alphabetical }
        return StreamingCatalog.alphabetical.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Color.textSecondary)
            TextField(
                "",
                text: $serviceQuery,
                prompt: Text("Search all services").foregroundStyle(Color.textSecondary)
            )
            .font(.custom("SF Pro Text", size: 15))
            .foregroundStyle(.white)
            .focused($isSearchFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(
            Capsule().stroke(
                isSearchFocused ? Color.orange : Color.white.opacity(0.10),
                lineWidth: 1
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(currentStep: 1, totalSteps: OnboardingHeader.stepNames.count)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Which services do you have?")
                        .font(.custom("SF Pro Display", size: 28).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.top, 24)

                    Text("Pick every service you have — each one sharpens your feed")
                        .font(.custom("SF Pro Text", size: 15))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.bottom, 18)

                    searchField
                        .padding(.bottom, 16)

                    if filteredPopular.isEmpty && filteredAll.isEmpty {
                        Text("No services match")
                            .font(.custom("SF Pro Text", size: 14))
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        if !filteredPopular.isEmpty {
                            Text("Most popular")
                                .font(.custom("SF Pro Text", size: 13).weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.bottom, 12)

                            LazyVGrid(columns: columns, spacing: 22) {
                                ForEach(filteredPopular) { svc in
                                    ServiceTile(
                                        service: svc,
                                        isSelected: selected.contains(svc.id),
                                        onTap: { toggle(svc.id) }
                                    )
                                }
                            }
                            .padding(.bottom, 24)
                        }

                        if !filteredAll.isEmpty {
                            Text("All services · A–Z")
                                .font(.custom("SF Pro Text", size: 13).weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.bottom, 8)

                            VStack(spacing: 0) {
                                ForEach(Array(filteredAll.enumerated()), id: \.element.id) { idx, svc in
                                    ServiceToggleRow(
                                        service: svc,
                                        isSelected: selected.contains(svc.id),
                                        onTap: { toggle(svc.id) }
                                    )
                                    if idx < filteredAll.count - 1 {
                                        Divider()
                                            .background(Color.white.opacity(0.06))
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.bottom, 24)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            VStack(spacing: 14) {
                Text("\(DisplayFormatting.services(selected.count)) selected")
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
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.orange.opacity(0.45), radius: 24, x: 0, y: 0)
                }
                .buttonStyle(.plain)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.custom("SF Pro Text", size: 14).weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .background(
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                    Theme.surface
                }
                .ignoresSafeArea(edges: .bottom)
            )
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

private struct ServiceToggleRow: View {
    let service: StreamingService
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ServiceMiniIcon(service: service, size: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(service.name)
                    .font(.custom("SF Pro Text", size: 15))
                    .foregroundStyle(.white)

                Spacer()

                ZStack {
                    Capsule()
                        .fill(isSelected ? Color.orange : Color.white.opacity(0.15))
                        .frame(width: 44, height: 26)
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .offset(x: isSelected ? 8 : -8)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stay Notified (last step)

struct StayNotifiedView: View {
    @Binding var pushOn: Bool
    var onContinue: () -> Void
    var onBack: () -> Void
    var onWidgetSettings: () -> Void
    let currentStep: Int
    let totalSteps: Int
    let posterUrls: [String]
    let showCount: Int
    let creatorCount: Int

    @Environment(\.scenePhase) private var scenePhase
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(currentStep: currentStep, totalSteps: totalSteps, onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if !posterUrls.isEmpty {
                        PosterStackHero(
                            posterUrls: posterUrls,
                            newCount: showCount
                        )
                        .padding(.top, 20)
                    } else {
                        Spacer().frame(height: 24)
                    }

                    VStack(spacing: 8) {
                        Text("Never miss an episode.")
                            .font(.custom("SF Pro Display", size: 28).weight(.bold))
                            .foregroundStyle(.white)
                        Text(notifySubtitle)
                            .font(.custom("SF Pro Text", size: 15))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { i in
                            NotifyBenefitRow(
                                posterUrl: posterUrls.indices.contains(i) ? posterUrls[i] : nil,
                                title: benefitTitle(i),
                                subtitle: benefitSubtitle(i)
                            )
                            if i < 2 {
                                Divider().background(Color.white.opacity(0.06))
                            }
                        }
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

                    Button(action: onWidgetSettings) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color(red: 0.55, green: 0.40, blue: 0.95).opacity(0.18))
                                Image(systemName: "iphone")
                                    .scaledFont(size: 16, weight: .semibold)
                                    .foregroundStyle(Color(red: 0.65, green: 0.50, blue: 1.0))
                            }
                            .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add the home screen widget")
                                    .font(.custom("SF Pro Text", size: 15).weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("Show tonight's episodes without opening the app")
                                    .font(.custom("SF Pro Text", size: 12))
                                    .foregroundStyle(Color.textSecondary)
                                Text("Takes about 15 seconds — we'll show you how")
                                    .font(.custom("SF Pro Text", size: 11))
                                    .foregroundStyle(Color.textTertiary)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .scaledFont(size: 14, weight: .semibold)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    Color.clear.frame(height: 90)
                }
            }

            VStack(spacing: 12) {
                switch authStatus {
                case .authorized, .provisional, .ephemeral:
                    Button {
                        pushOn = true
                        UIApplication.shared.registerForRemoteNotifications()
                        onContinue()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Alerts are on")
                                .font(.custom("SF Pro Text", size: 16).weight(.bold))
                            Image(systemName: "checkmark.circle.fill")
                                .scaledFont(size: 14, weight: .bold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.20, green: 0.66, blue: 0.33), Color(red: 0.20, green: 0.66, blue: 0.33).opacity(0.85)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 0.20, green: 0.66, blue: 0.33).opacity(0.35), radius: 28, x: 0, y: 0)
                    }
                    .buttonStyle(.plain)

                case .denied:
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Open settings")
                                .font(.custom("SF Pro Text", size: 16).weight(.bold))
                            Image(systemName: "gearshape.fill")
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
                        .shadow(color: Color.orange.opacity(0.45), radius: 28, x: 0, y: 0)
                    }
                    .buttonStyle(.plain)

                default: // .notDetermined
                    Button {
                        requestPermission()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Allow notifications")
                                .font(.custom("SF Pro Text", size: 16).weight(.bold))
                            Image(systemName: "bell.fill")
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
                        .shadow(color: Color.orange.opacity(0.45), radius: 28, x: 0, y: 0)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    pushOn = false
                    onContinue()
                } label: {
                    Text("Not now")
                        .font(.custom("SF Pro Text", size: 14).weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .background(
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                    Theme.surface
                }
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authStatus = settings.authorizationStatus
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    let settings = await UNUserNotificationCenter.current().notificationSettings()
                    authStatus = settings.authorizationStatus
                }
            }
        }
    }

    private var notifySubtitle: String {
        var parts: [String] = []
        if showCount > 0 {
            parts.append(DisplayFormatting.shows(showCount))
        }
        if creatorCount > 0 {
            parts.append(DisplayFormatting.creators(creatorCount))
        }
        if parts.isEmpty {
            return "Turn on alerts so you never miss a new episode."
        }
        return "You're following \(parts.joined(separator: " and ")). Turn on alerts so you never miss a new episode."
    }

    private func benefitTitle(_ i: Int) -> String {
        switch i {
        case 0: return "New episode alerts"
        case 1: return "Watch list updates"
        default: return "Deep links"
        }
    }

    private func benefitSubtitle(_ i: Int) -> String {
        switch i {
        case 0: return "Know the moment a new episode drops"
        case 1: return "See when your shows have new content"
        default: return "One tap straight to the episode"
        }
    }

    private func requestPermission() {
        Task { @MainActor in
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                if granted {
                    pushOn = true
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    pushOn = false
                }
            } catch {
                pushOn = false
            }
            onContinue()
        }
    }
}

private struct PosterStackHero: View {
    let posterUrls: [String]
    let newCount: Int

    var body: some View {
        ZStack {
            let display = Array(posterUrls.prefix(5))
            let count = display.count
            ForEach(0..<count, id: \.self) { i in
                let mid = Double(count - 1) / 2.0
                let angle = (Double(i) - mid) * 7.0
                let xOffset = (CGFloat(i) - CGFloat(mid)) * 16

                RemoteImage(urlString: display[i])
                    .frame(width: 76, height: 114)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
                    .rotationEffect(.degrees(angle))
                    .offset(x: xOffset)
                    .zIndex(Double(count - i))
            }
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "bell.fill")
                .font(.custom("SF Pro Text", size: 14).weight(.bold))
                .foregroundStyle(Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255))
                .offset(x: 20, y: -10)
        }
        .frame(height: 130)
    }
}

private struct NotifyBenefitRow: View {
    let posterUrl: String?
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            if let url = posterUrl, !url.isEmpty {
                RemoteImage(urlString: url)
                    .aspectRatio(2.0 / 3.0, contentMode: .fill)
                    .frame(width: 36, height: 54)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 36, height: 54)
                    .overlay(
                        Image(systemName: title == "New episode alerts" ? "tv.fill" : title == "Watch list updates" ? "list.bullet.rectangle.fill" : "link")
                            .scaledFont(size: 16, weight: .regular)
                            .foregroundStyle(Color.white.opacity(0.25))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("SF Pro Text", size: 15).weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.custom("SF Pro Text", size: 12))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Widget Instruction Sheet (H3)

private struct WidgetInstructionSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GsSheetHeader(title: "Add the home screen widget") {
                Button("Done") { onDismiss() }
                    .foregroundStyle(Color.textSecondary)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Widget preview
                    WidgetPreviewCard()
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    VStack(spacing: 14) {
                        WidgetStep(number: 1, text: "Touch and hold anywhere on your Home Screen until the icons jiggle")
                        WidgetStep(number: 2, text: "Tap the + button in the top-left corner")
                        WidgetStep(number: 3, text: "Search \"GuideStream\", pick a size, then tap Add Widget")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        Button { onDismiss() } label: {
                            Text("Remind me later")
                                .font(.custom("SF Pro Text", size: 15).weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)

                        Button { onDismiss() } label: {
                            Text("Got it")
                                .font(.custom("SF Pro Text", size: 15).weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    LinearGradient(
                                        colors: [Color.orange, Color.orange.opacity(0.85)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .sheetSurface(.base)
    }
}

private struct WidgetStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.custom("SF Pro Text", size: 13).weight(.bold))
                    .foregroundStyle(Color.orange)
            }
            Text(text)
                .font(.custom("SF Pro Text", size: 15))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct WidgetPreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GuideStream")
                    .font(.custom("SF Pro Display", size: 14).weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("TONIGHT")
                    .font(.custom("SF Pro Text", size: 9).weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(Color.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: 24, height: 36)
                    Text("New episode · The Last of Us")
                        .font(.custom("SF Pro Text", size: 11))
                        .foregroundStyle(Color.textSecondary)
                }
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: 24, height: 36)
                    Text("Season finale · Severance")
                        .font(.custom("SF Pro Text", size: 11))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Welcome") {
    OnboardingFlow(onFinish: {})
}

#Preview("Services") {
    OnboardingFlow(startStep: 1, onFinish: {})
}

#Preview("Notify") {
    OnboardingFlow(startStep: 4, onFinish: {})
}
