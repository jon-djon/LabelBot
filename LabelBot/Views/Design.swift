//
//  Design.swift
//  LabelBot
//

import SwiftUI

/// Shared visual constants so the app's styling stays consistent and adjustable.
enum Design {
    /// Corner radius for the preview, queue thumbnails, and framed fields.
    static let cornerRadius: CGFloat = 4
    /// Corner radius for the selectable icon swatches.
    static let swatchCornerRadius: CGFloat = 8
    /// Fixed width of a row's leading label so controls align across rows.
    static let rowLabelWidth: CGFloat = 74
    /// Height of the short vertical dividers between in-row controls.
    static let rowDividerHeight: CGFloat = 22
}
