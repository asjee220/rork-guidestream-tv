//
//  IdentifiableString.swift
//  GuideStreamTV
//
//  Wrapper that makes a String conform to Identifiable so it can
//  be used with SwiftUI's fullScreenCover(item:) API.
//

import Foundation

struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }

    init(_ value: String) { self.value = value }
}
