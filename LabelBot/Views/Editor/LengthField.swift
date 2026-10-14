//
//  LengthField.swift
//  LabelBot
//

import SwiftUI

/// Label length as a combo box: type any length in mm, or pick Auto, a mm preset
/// or a Gridfinity size from the attached menu. An empty field means Auto.
struct LengthField: View {
    /// Length in mm; `LabelLength.auto` (0) sizes the label to its content.
    @Binding var lengthMM: Double

    /// Typed lengths are clamped to this range (mm).
    private static let range: ClosedRange<Double> = 5...500

    var body: some View {
        HStack(spacing: 4) {
            TextField("Length", value: typedLength,
                      format: .number.precision(.fractionLength(0...1)), prompt: Text("Auto"))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .labelsHidden()
                .help("Type a length in mm, or leave empty for Auto")

            Text("mm")
                .font(.callout)
                .foregroundStyle(.secondary)

            Menu {
                choice("Auto", mm: LabelLength.auto)
                Section("Millimeters") {
                    ForEach(LabelLength.presetsMM, id: \.self) { choice("\(Int($0)) mm", mm: $0) }
                }
                Section("Gridfinity") {
                    ForEach(LabelLength.gridfinityUnits, id: \.self) { units in
                        let mm = LabelLength.mm(forGridfinity: units)
                        choice("\(LabelLength.gridfinityLabel(units))  (\(mm.formatted()) mm)", mm: mm)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose Auto, a preset length or a Gridfinity size")

            if let units = gridfinityUnits {
                Text("= \(LabelLength.gridfinityLabel(units))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The field's value: nil shows the "Auto" prompt; clearing it (or entering 0)
    /// returns to Auto, and anything else is clamped to `range`.
    private var typedLength: Binding<Double?> {
        Binding(
            get: { lengthMM > 0 ? lengthMM : nil },
            set: { value in
                guard let value, value > 0 else { lengthMM = LabelLength.auto; return }
                lengthMM = min(Self.range.upperBound, max(Self.range.lowerBound, value))
            }
        )
    }

    /// The Gridfinity size matching the current length, if any.
    private var gridfinityUnits: Double? {
        LabelLength.gridfinityUnits.first { LabelLength.mm(forGridfinity: $0) == lengthMM }
    }

    private func choice(_ title: String, mm: Double) -> some View {
        Button {
            lengthMM = mm
        } label: {
            if lengthMM == mm {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
