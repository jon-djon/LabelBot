//
//  RowLabel.swift
//  LabelBot
//

import SwiftUI

/// A row's leading label — fixed width so every row's first control starts at the
/// same x. Controls use `.fixedSize()` so their bezels sit at the leading edge
/// (a framed segmented control centers its content and looks misaligned).
struct RowLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
            .frame(width: Design.rowLabelWidth, alignment: .leading)
    }
}
