//
//  BrowseSortSheet.swift
//  GuideStreamTV
//
//  Sort is a separate, compact control from filtering: one choice, applied on
//  tap, no confirm step. Four options do not deserve a full-screen sheet.
//

import SwiftUI

struct BrowseSortSheet: View {
    let sort: BrowseSort
    var onSelect: (BrowseSort) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            GsSheetHeader(title: "Sort by")
                .padding(.horizontal, 8)

            VStack(spacing: 0) {
                ForEach(BrowseSort.allCases, id: \.rawValue) { option in
                    Button {
                        onSelect(option)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(
                                        option == sort ? Color.orange : Color.white.opacity(0.35),
                                        lineWidth: 1.5
                                    )
                                    .frame(width: 20, height: 20)
                                if option == sort {
                                    Circle().fill(Color.orange).frame(width: 11, height: 11)
                                }
                            }

                            Text(option.label)
                                .scaledFont(size: 15)
                                .foregroundStyle(.white)

                            Spacer()
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option != BrowseSort.allCases.last {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        .sheetSurface(.base)
        .presentationDetents([.height(320)])
        .preferredColorScheme(.dark)
    }
}
