//
//  CategorySection.swift
//  LabelBot
//

import SwiftUI

/// Fastener category selector plus per-label copy count.
struct CategorySection: View {
    @Bindable var printer: PrinterManager

    var body: some View {
        HStack(spacing: 12) {
            Picker("Type", selection: $printer.current.category) {
                ForEach(FastenerCategory.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Stepper(value: $printer.current.copies, in: 1...99) {
                Text("Copies: \(printer.current.copies)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
    }
}
