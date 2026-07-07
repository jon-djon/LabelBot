//
//  QueueRow.swift
//  LabelBot
//

import SwiftUI

/// One row in the label queue: thumbnail, title/subtitle, and copy count.
struct QueueRow: View {
    let printer: PrinterManager
    let spec: LabelSpec

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: printer.thumbnail(for: spec))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 28)
                .background(.white)
                .clipShape(.rect(cornerRadius: Design.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.cornerRadius).stroke(.quaternary)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(spec.title).font(.callout).lineLimit(1)
                Text(spec.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if spec.copies > 1 {
                Text("×\(spec.copies)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .tag(spec.id)
    }
}
