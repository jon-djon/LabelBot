//
//  TapeSection.swift
//  LabelBot
//

import SwiftUI

/// Tape width (shared) plus this label's length and alignment.
struct TapeSection: View {
    @Bindable var printer: PrinterManager

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: layout — tape, length, alignment, padding, spacing.
                HStack(spacing: 16) {
                    Picker("Tape", selection: $printer.tape) {
                        ForEach(TapeSize.all) { Text($0.label).tag($0) }
                    }
                    .frame(width: 130)
                    .help("Set from the loaded cassette on connect; if it differs at print time, you’re asked before it changes")

                    RowDivider()

                    FieldLabel("Length")
                    LengthField(lengthMM: $printer.current.lengthMM)

                    RowDivider()

                    Picker("Align", selection: $printer.current.alignment) {
                        ForEach(LabelAlignment.allCases) { align in
                            Image(systemName: align.symbol).tag(align)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)

                    RowDivider()

                    FieldLabel("Padding")
                    Picker("Padding", selection: Binding(
                        get: { printer.current.padding ?? .off },
                        set: { printer.current.padding = $0 }
                    )) {
                        ForEach(LabelPadding.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("Blank space before and after the text and icons")

                    RowDivider()

                    FieldLabel("Spacing")
                    Picker("Spacing", selection: $printer.current.iconSpacing) {
                        ForEach(IconSpacing.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Spacer()
                }

                // Row 2: appearance — font, zoom, borders, weight.
                HStack(spacing: 16) {
                    FieldLabel("Font")
                    Picker("Font", selection: $printer.current.fontName) {
                        Text("System").tag(String?.none)
                        ForEach(LabelRenderer.fontFamilies, id: \.self) { family in
                            Text(family).tag(String?.some(family))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)

                    RowDivider()

                    FieldLabel("Zoom")
                    Picker("Zoom", selection: $printer.current.zoom) {
                        ForEach(LabelZoom.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()

                    RowDivider()

                    Toggle("Border", isOn: $printer.current.border)
                        .toggleStyle(.checkbox)
                        .help("Draw a box around the whole label")

                    Toggle("Size box", isOn: $printer.current.sizeBorder)
                        .toggleStyle(.checkbox)
                        .help("Draw a box around just the size (e.g. M3)")

                    Toggle("Bold", isOn: $printer.current.boldText)
                        .toggleStyle(.checkbox)
                        .help("Bold every text, not just the size")

                    Spacer()
                }
            }
        } label: {
            HStack(spacing: 12) {
                SectionLabel("Tape options")
                if let loaded = printer.mismatchedLoadedTape {
                    HStack(spacing: 6) {
                        Label("Printer has \(loaded.label)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                        Button("Use \(loaded.label)") { printer.tape = loaded }
                            .controlSize(.small)
                    }
                    .help("The selected tape doesn't match the cassette in the printer")
                }
            }
        }
    }
}
