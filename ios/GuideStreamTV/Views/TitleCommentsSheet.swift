//
//  TitleCommentsSheet.swift
//  GuideStreamTV
//
//  Reusable bottom sheet that shows the comment thread for any title
//  (episode, show, or sports game) using `SocialViewModel` as the source
//  of truth. Designed to mirror the visual language of the Reels
//  `TrailerCommentsSheet` so the experience is consistent regardless of
//  where comments are surfaced.
//
//  Public surface:
//  - `titleId`   — stable identifier used to scope likes & comments. For
//                  episodes/shows this is the TMDB id (as a string). For
//                  sports games it's the same slug used as `gameSaveId`.
//  - `title`     — human-readable title rendered in the header.
//  - `subtitle`  — short metadata line, e.g. "S1 · NETFLIX".
//  - `posterUrl` — optional thumbnail rendered to the left of the title.
//

import SwiftUI
import UIKit

struct TitleCommentsSheet: View {
    let titleId: String
    let title: String
    var subtitle: String? = nil
    var posterUrl: String? = nil
    var posterColors: [Color] = []
    /// Optional accent color for the avatar + send button. Falls back to
    /// the brand orange so it works across every surface.
    var accent: Color = Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255)

    @Environment(\.dismiss) private var dismiss
    @State private var social = SocialViewModel.shared
    @State private var auth = AuthViewModel.shared
    @State private var draft: String = ""
    @State private var didJustPost: Bool = false
    @FocusState private var inputFocused: Bool

    private var comments: [TitleComment] {
        social.thread(titleId)
    }

    private var commentCount: Int {
        social.commentTotal(titleId)
    }

    private var isLoading: Bool {
        social.loadingComments.contains(titleId)
    }

    private var isPosting: Bool {
        social.postingComment.contains(titleId)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting
    }

    private var myInitials: String {
        SocialViewModel.initials(
            firstName: auth.firstName,
            lastName: auth.lastName,
            displayName: auth.displayName
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.07))

            if isLoading && comments.isEmpty {
                loadingState
            } else if comments.isEmpty {
                emptyState
            } else {
                threadList
            }

            inputBar
        }
        .background(Color(red: 0x0A/255, green: 0x10/255, blue: 0x1A/255).ignoresSafeArea())
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .task {
            await social.loadComments(titleId: titleId)
            // Refresh counts in the background so the header total stays
            // in sync if the user hasn't opened the parent sheet yet.
            await social.refreshCounts(titleId: titleId)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if posterUrl != nil || !posterColors.isEmpty {
                Color.black
                    .frame(width: 44, height: 60)
                    .overlay {
                        RemoteImage(
                            urlString: posterUrl,
                            contentMode: .fill,
                            fallbackColors: posterColors
                        )
                        .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Comments")
                    .scaledFont(size: 17, weight: .heavy)
                    .foregroundStyle(.white)
                Text(title)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(formatCount(commentCount))
                .scaledFont(size: 12, weight: .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.10)))

            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: "xmark")
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close comments")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Loading comments…")
                .scaledFont(size: 13)
                .foregroundStyle(Color.white.opacity(0.6))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .scaledFont(size: 34, weight: .light)
                .foregroundStyle(accent)
            Text("Start the conversation")
                .scaledFont(size: 16, weight: .heavy)
                .foregroundStyle(.white)
            Text(didJustPost
                 ? "Sending your comment…"
                 : "Be the first to share what you think about \(title).")
                .scaledFont(size: 13)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var threadList: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(comments) { c in
                    TitleCommentRow(comment: c, accent: accent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.07))
            HStack(spacing: 10) {
                Circle()
                    .fill(accent)
                    .overlay(
                        Text(myInitials)
                            .scaledFont(size: 11, weight: .bold)
                            .foregroundStyle(.white)
                    )
                    .frame(width: 32, height: 32)

                TextField(
                    "",
                    text: $draft,
                    prompt: Text("Add a comment…")
                        .foregroundColor(Color.white.opacity(0.40))
                )
                .foregroundStyle(.white)
                .tint(accent)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { Task { await sendComment() } }

                Button {
                    Task { await sendComment() }
                } label: {
                    Group {
                        if isPosting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .scaledFont(size: 15, weight: .bold)
                                .foregroundStyle(canSend ? accent : Color.white.opacity(0.3))
                        }
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send comment")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.white.opacity(0.06))
            .overlay(
                Capsule()
                    .stroke(inputFocused ? accent.opacity(0.6) : Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(Capsule())
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
    }

    private func sendComment() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        draft = ""
        didJustPost = true
        let ok = await social.postComment(titleId: titleId, body: trimmed)
        didJustPost = false
        if !ok {
            // Restore the draft so the user can retry instead of losing what
            // they typed.
            await MainActor.run { draft = trimmed }
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Comment Row

private struct TitleCommentRow: View {
    let comment: TitleComment
    let accent: Color

    private var displayName: String {
        comment.displayName?.isEmpty == false ? comment.displayName! : "Someone"
    }

    private var initials: String {
        let raw = (comment.initials ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return String(raw.prefix(2)).uppercased() }
        let parts = displayName.split(whereSeparator: { $0.isWhitespace })
        if let first = parts.first?.first, let last = parts.dropFirst().last?.first {
            return "\(first)\(last)".uppercased()
        }
        if let first = parts.first?.first { return String(first).uppercased() }
        return "G"
    }

    private var stableColor: Color {
        // Deterministic from the author so the same person always gets the
        // same avatar tint across the thread.
        let seed = (comment.userId ?? comment.deviceId ?? displayName).hashValue
        let palette: [Color] = [
            accent,
            Color(red: 0x3D/255, green: 0xE0/255, blue: 0x6A/255),
            Color(red: 0x6A/255, green: 0x3F/255, blue: 0xE0/255),
            Color(red: 0xE0/255, green: 0x3F/255, blue: 0x9E/255),
            Color(red: 0x3F/255, green: 0x9F/255, blue: 0xE0/255),
            Color(red: 0xE0/255, green: 0xC2/255, blue: 0x3F/255)
        ]
        return palette[abs(seed) % palette.count]
    }

    private var timestamp: String {
        guard let date = comment.createdAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(stableColor)
                .overlay(
                    Text(initials)
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(.white)
                )
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(.white)
                    if !timestamp.isEmpty {
                        Text(timestamp)
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.white.opacity(0.40))
                    }
                }
                Text(comment.body)
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
