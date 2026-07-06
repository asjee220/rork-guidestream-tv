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
    @State private var smsOn: Bool = AuthViewModel.shared.notifySMSEnabled
    @State private var showEmailAuth: Bool = false


    var body: some View {
        ZStack {
            BrandBackground()

            Group {
                switch step {
                case 0:
                    WelcomeOnboardingView(
                        onContinue: { advance() },
                        onEmailAuth: { showEmailAuth = true }
                    )
                case 1:
                    ConnectServicesView(
                        selected: $selectedServices,
                        onContinue: {
                            AuthViewModel.shared.setSelectedServices(selectedServices)
                            advance()
                        }
                    )
                case 2:
                    StayNotifiedView(
                        pushOn: $pushOn,
                        smsOn: $smsOn,
                        onContinue: {
                            AuthViewModel.shared.setNotificationPreferences(push: pushOn, sms: false) // SMS opt-in disabled
                            advance()
                        },
                        onWidgetSettings: onWidgetSettings
                    )
                case 3:
                    SeedPromptView(
                        selectedServices: selectedServices,
                        onContinue: { advance() },
                        onSkip: { onFinish() }
                    )
                case 4:
                    WatchingNowView(
                        selectedServices: selectedServices,
                        onContinue: { inserts in
                            commitInserts(inserts) { advance() }
                        },
                        onSkip: { advance() }
                    )
                default:
                    FollowCreatorsOnboardingView(
                        onContinue: { inserts in
                            commitInserts(inserts) { onFinish() }
                        },
                        onSkip: { onFinish() }
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView(
                onAuthenticated: {
                    showEmailAuth = false
                    // First time email user — proceed to services step.
                    // Returning users (hasCompletedOnboarding already true)
                    // are handled by ContentView and skip this flow entirely.
                    advance()
                },
                onClose: { showEmailAuth = false }
            )
        }
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

    private func commitInserts(_ inserts: [UserStreamInsert], completion: @escaping () -> Void) {
        guard !inserts.isEmpty else { completion(); return }
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("user_streams")
                    .upsert(inserts, onConflict: "user_id,title_id")
                    .execute()
            } catch {
                print("[GuideStream] seed upsert failed: \(error)")
            }
            await MainActor.run { completion() }
        }
    }
}

// MARK: - Welcome

struct WelcomeOnboardingView: View {
    var onContinue: () -> Void
    var onEmailAuth: () -> Void

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
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Every show. Every service.")
                        .font(.custom("SF Pro Text", size: 15))
                        .foregroundStyle(Color.textSecondary)
                    Text("What are you watching now?")
                        .font(.custom("SF Pro Display", size: 18).weight(.bold))
                        .foregroundStyle(.white)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 4)

                // 1. Sign in with Apple — full width
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

                // 2. Sign in with Google — full width
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
                            .foregroundStyle(Color(red: 0.24, green: 0.25, blue: 0.26))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(auth.isAuthenticating)

                // Divider — "or"
                HStack(spacing: 10) {
                    Color.white.opacity(0.1)
                        .frame(height: 1)
                    Text("or")
                        .font(.custom("SF Pro Text", size: 12))
                        .foregroundStyle(Color.textSecondary)
                    Color.white.opacity(0.1)
                        .frame(height: 1)
                }

                // 3. Sign in with email — outlined
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

                if let err = auth.lastError {
                    Text(err)
                        .font(.custom("SF Pro Text", size: 11))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                }

                // Legal disclosure — links open in browser via Markdown
                Text("By continuing, you agree to our [Privacy Policy](https://guidestream.tv/privacy) and [Terms of Service](https://guidestream.tv/terms).")
                    .font(.custom("SF Pro Text", size: 11))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .tint(Color.blue)
                    .fixedSize(horizontal: false, vertical: true)
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
}

struct GuideStreamLogo: View {
    var body: some View {
        BrandWordmark(wordmarkSize: .large)
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

struct OnboardingHeader: View {
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

            BrandWordmark(wordmarkSize: .nav)

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

/// Onboarding step where the user picks every streaming service they have so
/// the home-screen feed is personalised. Uses the shared `StreamingCatalog`
/// (top ~50 worldwide) and `ServiceTile` so the same brand artwork is reused
/// by the `ServicesBottomSheet` accessed from the header pill.
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

                    Text("Pick from the top 50 worldwide — every selection sharpens your feed")
                        .font(.custom("SF Pro Text", size: 15))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.bottom, 18)

                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(StreamingCatalog.all) { svc in
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

// MARK: - Stay Notified

struct StayNotifiedView: View {
    @Binding var pushOn: Bool
    @Binding var smsOn: Bool
    var onContinue: () -> Void
    var onWidgetSettings: () -> Void
    // SMS episode-recap opt-in disabled — kept for later re-enablement.
    // @State private var phoneDraft: String = AuthViewModel.formatUSPhoneDisplay(AuthViewModel.shared.phoneNumber ?? "")
    // @State private var isSavingPhone: Bool = false
    // @State private var phoneSaved: Bool = false
    // @State private var phoneSaveFailed: Bool = false

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

    // SMS episode-recap opt-in disabled — kept for later re-enablement.
    // private func savePhoneNumber() {
    //     Task {
    //         isSavingPhone = true
    //         defer { isSavingPhone = false }
    //         let ok = await AuthViewModel.shared.updatePhoneNumber(phoneDraft)
    //         if ok {
    //             UINotificationFeedbackGenerator().notificationOccurred(.success)
    //             withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
    //                 phoneSaved = true
    //                 phoneSaveFailed = false
    //             }
    //             try? await Task.sleep(for: .seconds(1.6))
    //             withAnimation(.easeOut(duration: 0.25)) { phoneSaved = false }
    //         } else {
    //             UINotificationFeedbackGenerator().notificationOccurred(.error)
    //             withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
    //                 phoneSaveFailed = true
    //                 phoneSaved = false
    //             }
    //         }
    //     }
    // }
    //
    // @ViewBuilder
    // private var saveFeedbackBanners: some View {
    //     if phoneSaved {
    //         HStack(spacing: 8) {
    //             Image(systemName: "checkmark.circle.fill")
    //                 .font(.custom("SF Pro Text", size: 13).weight(.semibold))
    //             Text("Saved")
    //                 .font(.custom("SF Pro Text", size: 13).weight(.semibold))
    //         }
    //         .foregroundStyle(Color.green)
    //         .padding(.horizontal, 14)
    //         .padding(.vertical, 8)
    //         .background(
    //             Capsule().fill(Color.green.opacity(0.12))
    //         )
    //         .transition(.opacity)
    //     }
    //
    //     if phoneSaveFailed {
    //         HStack(spacing: 8) {
    //             Image(systemName: "exclamationmark.triangle.fill")
    //                 .font(.custom("SF Pro Text", size: 13).weight(.semibold))
    //             Text("Couldn't save — check your connection")
    //                 .font(.custom("SF Pro Text", size: 13).weight(.semibold))
    //         }
    //         .foregroundStyle(Color.red.opacity(0.9))
    //         .padding(.horizontal, 14)
    //         .padding(.vertical, 8)
    //         .background(
    //             Capsule().fill(Color.red.opacity(0.12))
    //         )
    //         .transition(.opacity)
    //     }
    // }

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
                // SMS episode-recap opt-in disabled — kept for later re-enablement.
                // Divider().background(Color.white.opacity(0.06))
                // NotifyRow(
                //     icon: "message.fill",
                //     iconBg: Color.blue.opacity(0.18),
                //     iconTint: Color.blue,
                //     title: "Episode synopsis by text",
                //     subtitle: "SMS",
                //     trailing: .toggle($smsOn, tint: Color.blue)
                // )
                // .onChange(of: smsOn) { _, newValue in
                //     withAnimation(.easeInOut(duration: 0.28)) { }
                // }
                //
                // if smsOn {
                //     VStack(alignment: .leading, spacing: 10) {
                //         Text("Mobile number")
                //             .font(.custom("SF Pro Text", size: 11).weight(.semibold))
                //             .tracking(0.8)
                //             .foregroundStyle(Color.textTertiary)
                //
                //         HStack(spacing: 0) {
                //             Text("+1")
                //                 .font(.custom("SF Pro Text", size: 15).weight(.medium))
                //                 .foregroundStyle(Color.textSecondary)
                //                 .padding(.leading, 14)
                //             TextField("", text: $phoneDraft)
                //                 .keyboardType(.phonePad)
                //                 .textContentType(.telephoneNumber)
                //                 .textInputAutocapitalization(.never)
                //                 .font(.custom("SF Pro Text", size: 15).weight(.medium))
                //                 .foregroundStyle(.white)
                //                 .tint(Color.orange)
                //                 .padding(.leading, 4)
                //                 .padding(.vertical, 12)
                //         }
                //         .background(
                //             RoundedRectangle(cornerRadius: 10, style: .continuous)
                //                 .fill(Color.white.opacity(0.05))
                //         )
                //         .overlay(
                //             RoundedRectangle(cornerRadius: 10, style: .continuous)
                //                 .stroke(Color.white.opacity(0.08), lineWidth: 1)
                //         )
                //         .onChange(of: phoneDraft) { _, newValue in
                //             phoneDraft = AuthViewModel.formatUSPhoneDisplay(newValue)
                //             phoneSaved = false
                //             phoneSaveFailed = false
                //         }
                //
                //         if !phoneDraft.isEmpty && AuthViewModel.normalizeUSPhone(phoneDraft) == nil {
                //             Text("Enter a valid 10-digit US mobile number.")
                //                 .font(.custom("SF Pro Text", size: 11))
                //                 .foregroundStyle(Color(red: 0.96, green: 0.32, blue: 0.32))
                //         }
                //
                //         Text("We'll text recaps to this number. Reply STOP to opt out; msg & data rates may apply.")
                //             .font(.custom("SF Pro Text", size: 11))
                //             .foregroundStyle(Color.textTertiary)
                //             .fixedSize(horizontal: false, vertical: true)
                //
                //         Button(action: savePhoneNumber) {
                //             HStack(spacing: 6) {
                //                 if isSavingPhone {
                //                     ProgressView()
                //                         .progressViewStyle(.circular)
                //                         .tint(.white)
                //                 }
                //                 Text("Save number")
                //                     .font(.custom("SF Pro Text", size: 13).weight(.semibold))
                //             }
                //             .foregroundStyle(.white)
                //             .frame(maxWidth: .infinity)
                //             .frame(height: 40)
                //             .background(
                //                 RoundedRectangle(cornerRadius: 10, style: .continuous)
                //                     .fill(AuthViewModel.normalizeUSPhone(phoneDraft) != nil ? Color.blue : Color.blue.opacity(0.35))
                //             )
                //         }
                //         .buttonStyle(.plain)
                //         .disabled(AuthViewModel.normalizeUSPhone(phoneDraft) == nil || isSavingPhone)
                //
                //         saveFeedbackBanners
                //     }
                //     .padding(.horizontal, 16)
                //     .padding(.vertical, 14)
                //     .transition(.opacity.combined(with: .move(edge: .top)))
                // }

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

            Button(action: {
                // SMS episode-recap opt-in disabled — kept for later re-enablement.
                // if smsOn {
                //     guard AuthViewModel.normalizeUSPhone(phoneDraft) != nil else { return }
                //     Task {
                //         _ = await AuthViewModel.shared.updatePhoneNumber(phoneDraft)
                //         await MainActor.run { onContinue() }
                //     }
                // } else {
                //     onContinue()
                // }
                onContinue()
            }) {
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
