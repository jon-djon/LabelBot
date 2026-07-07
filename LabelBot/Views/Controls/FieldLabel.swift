//
//  FieldLabel.swift
//  LabelBot
//

import SwiftUI

/// Inline caption label (natural width) before a mid-row control.
struct FieldLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
