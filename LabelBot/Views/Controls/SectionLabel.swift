//
//  SectionLabel.swift
//  LabelBot
//

import SwiftUI

/// A prominent header for the editor section group boxes.
struct SectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }
}
