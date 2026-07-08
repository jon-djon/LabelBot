//
//  IconsSection.swift
//  LabelBot
//

import SwiftUI

/// Icon on/off plus the drive/head/orientation controls and category icon grids.
struct IconsSection: View {
    @Bindable var printer: PrinterManager

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show icons", isOn: $printer.current.showIcons)
                    .toggleStyle(.checkbox)

                IconOptionsRow(printer: printer)
                    .disabled(!printer.current.showIcons)

                VStack(alignment: .leading, spacing: 10) {
                    if printer.current.category.isScrew {
                        ScrewIconGrids(printer: printer)
                    }
                    if printer.current.category == .nutWasher {
                        NutWasherGrid(printer: printer)
                    }
                }
                .disabled(!printer.current.showIcons)
            }
        } label: {
            SectionLabel("Icons")
        }
    }
}
