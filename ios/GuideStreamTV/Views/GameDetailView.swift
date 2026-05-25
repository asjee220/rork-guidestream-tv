//
//  GameDetailView.swift
//  GuideStreamTV
//

import SwiftUI

struct GameDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "04090F").ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    backNav
                    scoreHero
                    whereToWatch
                    whileYouWait
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .padding(.top, 12)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Back

    private var backNav: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("← Sports")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Score hero

    private var scoreHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "E50914"))
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color(hex: "E50914"))
                badge("NBA", bg: Color(hex: "1D428A"), fg: .white)
                badge("EC Finals · G4", bg: Color.white.opacity(0.1), fg: Color.white.opacity(0.6))
                Spacer()
            }

            HStack {
                heroTeam(abbrev: "NYK", name: "Knicks", score: "87", color: Color(hex: "006BB6"), scoreColor: .white)
                Spacer()
                VStack(spacing: 4) {
                    Text("3rd Qtr")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.2))
                    Text("8:42")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                Spacer()
                heroTeam(abbrev: "MIA", name: "Heat", score: "82", color: Color(hex: "CE1141"), scoreColor: Color.white.opacity(0.5))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Color(hex: "161B27"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(hex: "F5821F").opacity(0.25), lineWidth: 1)
        )
    }

    private func badge(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(bg))
    }

    private func heroTeam(abbrev: String, name: String, score: String, color: Color, scoreColor: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(abbrev)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                )
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(score)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(scoreColor)
        }
    }

    // MARK: - Where to watch

    private var whereToWatch: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WHERE TO WATCH — YOUR SUBS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(hex: "5BA8FF"))
                .padding(.bottom, 8)

            // Row 1 — subscribed
            HStack {
                Text("ESPN+")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: "CC0000")))
                Text("Subscribed")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "4DD68C"))
                Spacer()
                Button {
                    // deep link placeholder
                } label: {
                    Text("Open ↗")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: "F5821F")))
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
            .padding(.bottom, 8)

            // Row 2 — not subscribed
            HStack {
                Text("Hulu Live")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                Text("Not subscribed")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.3))
                Spacer()
                Text("Add +")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "1A6FE8"))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color(hex: "1A6FE8").opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "1A6FE8").opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - While you wait

    private var whileYouWait: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("While you wait · docs for Knicks fans")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)

            docRow(title: "The Last Dance", subtitle: "Netflix · NBA Documentary")
            docRow(title: "30 for 30 · All Seasons", subtitle: "ESPN+ · Sports Documentary")
        }
    }

    private func docRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))
                .frame(width: 34, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            Spacer()
            Button {
                // no-op
            } label: {
                Text("+ List")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color(hex: "161B27"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        GameDetailView()
    }
    .preferredColorScheme(.dark)
}
