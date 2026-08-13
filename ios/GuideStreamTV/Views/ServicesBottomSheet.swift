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
    @State private var serviceQuery: String = ""
    @FocusState private var isSearchFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    init() {
        _selected = State(initialValue: AuthViewModel.shared.selectedServices)
    }

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
        NavigationStack {
            ZStack {
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
                    GsSheetHeader(
                        title: "Which services do you have?",
                        subtitle: "Edit to personalise what shows up on your feed"
                    )

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            searchField
                                .padding(.bottom, 14)

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
                                            serviceToggleRow(svc)
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
        .sheetSurface(.base)
        .onChange(of: auth.selectedServices) { _, newValue in
            selected = newValue
        }
    }

    private func serviceToggleRow(_ svc: StreamingService) -> some View {
        Button {
            toggle(svc.id)
        } label: {
            HStack(spacing: 12) {
                ServiceMiniIcon(service: svc, size: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(svc.name)
                    .font(.custom("SF Pro Text", size: 15))
                    .foregroundStyle(.white)

                Spacer()

                ZStack {
                    Capsule()
                        .fill(selected.contains(svc.id) ? Color.orange : Color.white.opacity(0.15))
                        .frame(width: 44, height: 26)
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .offset(x: selected.contains(svc.id) ? 8 : -8)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected.contains(svc.id))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
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
