//
//  PreviewSection.swift
//  LabelBot
//

import SwiftUI

/// Live label preview with its printed height and length.
struct PreviewSection: View {
    let printer: PrinterManager

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: previewAlignment) {
                    RoundedRectangle(cornerRadius: Design.cornerRadius).fill(.white)
                    if let preview = printer.preview {
                        Image(nsImage: preview)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, alignment: previewAlignment)
                            .padding(6)
                    }
                }
                .frame(height: 64)
                .overlay {
                    RoundedRectangle(cornerRadius: Design.cornerRadius).stroke(.quaternary)
                }

                HStack(spacing: 6) {
                    Label("Height \(mmString(printer.previewHeightMM))", systemImage: "arrow.up.and.down")
                    Text("·").foregroundStyle(.tertiary)
                    Label("Length \(mmString(printer.previewLengthMM))", systemImage: "arrow.left.and.right")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } label: {
            SectionLabel("Preview")
        }
    }

    /// SwiftUI alignment mirroring the label's left/center/right setting.
    private var previewAlignment: Alignment {
        switch printer.current.alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// Formats a millimeter measurement, dropping a trailing ".0".
    private func mmString(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) mm"
    }
}
