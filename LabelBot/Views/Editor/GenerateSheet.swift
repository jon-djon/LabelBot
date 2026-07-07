//
//  GenerateSheet.swift
//  LabelBot
//

import SwiftUI

/// Sheet for bulk-adding labels from a pasted list.
struct GenerateSheet: View {
    let printer: PrinterManager
    @Binding var isPresented: Bool
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add labels from a list").font(.headline)
            Text("One size per line, or comma-separated. Each becomes a label using the selected label's type and icons.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("One per line, or comma-separated", text: $text, axis: .vertical)
                .lineLimit(8...)
                .font(.body.monospaced())
                .textFieldStyle(.roundedBorder)
                .frame(width: 380)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Add labels", action: addLabels)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    private func addLabels() {
        printer.generateLabels(from: text)
        isPresented = false
    }
}
