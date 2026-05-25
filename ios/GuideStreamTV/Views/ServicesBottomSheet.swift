//
//  ServicesBottomSheet.swift
//  GuideStreamTV
//
//  Bottom sheet that mirrors the onboarding "Which services do you have?"
//  step. Opened from the orange `ServicesPill` in the top bar so users can
//  edit their personalised feed at any time. Selections are persisted via
//  `AuthViewModel.setSelectedServices`, which also mirrors the change into
//  the `device_sessions` Supabase row.
//

import SwiftUI
import UIKit

struct ServicesBottomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared
    @State private var selected: Set<String>

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    init() {
        _selected = State(initialValue: AuthViewModel.shared.selectedServices)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.navy.ignoresSafeArea()

                // Atmosphere — keeps the sheet feeling like the same surface as the rest of the app.
                GeometryReader { geo in
                    Circle()
                        .fill(Color.blue.opacity(0.14))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 90)
                        .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.35)
                    Circle()
                        .fill(Color.orange.opacity(0.10))
                        .frame(width: geo.size.width * 0.7)
                        .blur(radius: 80)
                        .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.4)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Which services do you have?")
                                .font(.custom("SF Pro Display", size: 24).weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.top, 4)

                            Text("Edit to personalise what shows up on your feed")
                                .font(.custom("SF Pro Text", size: 14))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.bottom, 16)

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
                        .padding(.top, 4)
                    }
                    .presentationContentInteraction(.scrolls)

                    VStack(spacing: 12) {
                        Text("\(selected.count) service\(selected.count == 1 ? "" : "s") selected")
                            .font(.custom("SF Pro Text", size: 13))
                            .foregroundStyle(Color.textSecondary)

                        Button(action: save) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .scaledFont(size: 14, weight: .bold)
                                Text("Save")
                                    .font(.custom("SF Pro Text", size: 16).weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                LinearGradient(
                                    colors: [Color.orange, Color.orange.opacity(0.85)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color.orange.opacity(0.45), radius: 22, x: 0, y: 0)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("My Services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func toggle(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if selected.contains(id) {
                selected.remove(id)
            } else {
                selected.insert(id)
            }
        }
    }

    private func save() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        auth.setSelectedServices(selected)
        dismiss()
    }
}

#Preview {
    Color.navy.sheet(isPresented: .constant(true)) {
        ServicesBottomSheet()
    }
}
