//
//  IconOptionsRow.swift
//  LabelBot
//

import SwiftUI

/// Style / orientation / threads (screws), or a single caption toggle (other
/// categories), on one divided row. Screw captions live with their grids.
struct IconOptionsRow: View {
    @Bindable var printer: PrinterManager

    var body: some View {
        HStack(spacing: 8) {
            if printer.current.category.isScrew {
                FieldLabel("Style")
                Picker("Style", selection: $printer.current.iconStyle) {
                    ForEach(IconStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            } else {
                Toggle("Label icon", isOn: $printer.current.labelHead)
                    .toggleStyle(.checkbox)
                    .help("Print the icon's name beneath it")
            }
            Spacer()
        }
    }
}
