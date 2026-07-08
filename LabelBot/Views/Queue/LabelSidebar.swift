//
//  LabelSidebar.swift
//  LabelBot
//

import SwiftUI

/// The label queue list plus its add/duplicate/delete/generate controls and cut toggle.
struct LabelSidebar: View {
    @Bindable var printer: PrinterManager
    @Binding var showGenerate: Bool
    @Binding var generateText: String

    var body: some View {
        List(selection: $printer.selection) {
            ForEach(printer.labels) { spec in
                QueueRow(printer: printer, spec: spec)
            }
            .onMove { printer.moveLabels(from: $0, to: $1) }
        }
        .navigationTitle("Labels")
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 4) {
                    Button("Add label", systemImage: "plus", action: printer.addLabel)
                        .help("Add label")
                    Button("Duplicate label", systemImage: "plus.square.on.square", action: printer.duplicateSelected)
                        .help("Duplicate label")
                    Button("Delete label", systemImage: "trash", action: printer.deleteSelected)
                        .disabled(printer.labels.count <= 1)
                        .help("Delete label")
                    Spacer()
                    Button("Add many labels from a list", systemImage: "text.badge.plus", action: showGenerateSheet)
                        .help("Add many labels from a list")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                Divider()
                Toggle("Cut between labels", isOn: $printer.cutBetween)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .background(.bar)
        }
    }

    private func showGenerateSheet() {
        generateText = ""
        showGenerate = true
    }
}
