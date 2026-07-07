//
//  LabelSectionEditor.swift
//  LabelBot
//

import SwiftUI

/// Size (pickers or free text), insert dimensions, and custom text for one text section.
struct LabelSectionEditor: View {
    @Binding var section: TextSection
    let category: FastenerCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: entry mode.
            HStack(spacing: 8) {
                RowLabel("Mode")
                Picker("Size entry", selection: $section.sizeMode) {
                    ForEach(SizeEntryMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            // Pickers: units · size · length, each labeled and divided. Text: a field.
            if section.sizeMode == .pickers {
                HStack(spacing: 8) {
                    RowLabel("Units")
                    Picker("Units", selection: $section.unit) {
                        ForEach(UnitSystem.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    RowDivider()
                    FieldLabel("Size")
                    Picker("Size", selection: $section.diameter) {
                        ForEach(section.availableDiameters, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()

                    if category.hasLength {
                        RowDivider()
                        FieldLabel("Length")
                        Picker("Length", selection: $section.length) {
                            ForEach(section.availableLengths, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Spacer()
                }

                // Threaded inserts also carry a barrel diameter (drawn with a ↔)
                // and an optional internal diameter.
                if category == .insert {
                    HStack(spacing: 8) {
                        RowLabel("Diameter")
                        TextField("mm", text: $section.outerDiameter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)

                        RowDivider()
                        FieldLabel("Internal")
                        TextField("optional", text: $section.innerDiameter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Spacer()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    RowLabel("Size")
                    TextField("e.g. M3 × 8", text: $section.sizeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                RowLabel("Custom")
                TextField("Optional", text: $section.customText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                Spacer()
            }
        }
    }
}
