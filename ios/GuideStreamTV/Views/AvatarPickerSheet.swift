//
//  AvatarPickerSheet.swift
//  GuideStreamTV
//
//  Lets a signed-in viewer change the picture in their profile header: upload
//  one from the photo library, pick one of the built-in presets, or clear back
//  to the initials monogram.
//
//  Guests get the presets but not the upload. `users.avatar_url` is keyed on
//  the auth uuid and the avatars bucket's RLS policies scope writes to
//  `avatars/<auth.uid()>/…`, so there is nowhere for a guest's file to go and
//  nothing to attach it to — offering the button and failing at the end would
//  be worse than not offering it.
//

import SwiftUI
import PhotosUI

struct AvatarPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthViewModel.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var errorText: String?

    let initials: String

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            GsSheetHeader(title: "Profile Picture") {
                Button("Done") { dismiss() }
                    .foregroundStyle(Color.textSecondary)
            }

            ScrollView {
                VStack(spacing: 24) {
                    AvatarRing(initials: initials, size: 96, avatar: auth.avatar)
                        .padding(.top, 8)
                        .overlay {
                            if isUploading {
                                ProgressView().tint(.white)
                            }
                        }

                    if auth.isAuthenticated {
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            Label("Upload a photo", systemImage: "photo.on.rectangle.angled")
                                .scaledFont(size: 15, weight: .semibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    Capsule().fill(Color.orange)
                                )
                        }
                        .disabled(isUploading)
                        .padding(.horizontal, 20)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Or pick one")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(AvatarPreset.all) { preset in
                                Button {
                                    Task { await auth.setAvatar(preset.storageValue) }
                                } label: {
                                    AvatarRing(
                                        initials: initials,
                                        size: 56,
                                        avatar: .preset(preset.id)
                                    )
                                    .overlay {
                                        if auth.avatarUrl == preset.storageValue {
                                            Circle()
                                                .strokeBorder(Color.orange, lineWidth: 3)
                                                .frame(width: 62, height: 62)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(preset.id)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Button {
                        Task { await auth.setAvatar(nil) }
                    } label: {
                        Text("Use my initials")
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)

                    if let errorText {
                        Text(errorText)
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    Color.clear.frame(height: 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheetSurface(.base)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    /// Loads the picked photo, downscales it, and hands the JPEG to the
    /// uploader. Downscaling matters: a modern iPhone photo is several
    /// megabytes and the avatars bucket caps objects at 5 MB, so uploading the
    /// original would fail for exactly the users most likely to try it. 512pt
    /// is comfortably more than the 112pt the largest avatar draws at.
    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        errorText = nil
        defer { isUploading = false; photoItem = nil }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorText = "That image couldn't be read."
            return
        }
        guard let jpeg = Self.downscaledJPEG(image, maxDimension: 512) else {
            errorText = "That image couldn't be prepared."
            return
        }
        let url = await auth.uploadAvatar(data: jpeg, fileExtension: "jpg", contentType: "image/jpeg")
        if url == nil {
            errorText = "Upload failed. Check your connection and try again."
        }
    }

    /// Aspect-preserving downscale to `maxDimension` on the longest side,
    /// re-encoded as JPEG at 0.85. Returns nil only if rendering fails.
    private static func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
