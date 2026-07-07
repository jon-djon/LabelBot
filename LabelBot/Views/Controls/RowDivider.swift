//
//  RowDivider.swift
//  LabelBot
//

import SwiftUI

/// A short vertical divider separating controls within a row.
struct RowDivider: View {
    var body: some View {
        Divider().frame(height: Design.rowDividerHeight)
    }
}
