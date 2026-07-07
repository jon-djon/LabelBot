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
            HStack(spacing: 16) {
                Picker("Tape", selection: $printer.tape) {
                    ForEach(TapeSize.all) { Text($0.label).tag($0) }
                }
                .frame(width: 130)

                RowDivider()

                Picker("Length", selection: $printer.current.lengthMM) {
                    Text("Auto").tag(LabelLength.auto)
                    Section("Millimeters") {
                        ForEach(LabelLength.presetsMM, id: \.self) { Text("\(Int($0)) mm").tag($0) }
                    }
                    Section("Gridfinity") {
                        ForEach(LabelLength.gridfinityUnits, id: \.self) { units in
                            Text(LabelLength.gridfinityLabel(units))
                                .tag(LabelLength.mm(forGridfinity: units))
                        }
                    }
                }
                .frame(width: 150)

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

                FieldLabel("Spacing")
                Picker("Spacing", selection: $printer.current.iconSpacing) {
                    ForEach(IconSpacing.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()

                Spacer()
            }
        } label: {
            SectionLabel("Tape options")
        }
    }
}
