//
//  LogsSection.swift
//  LabelBot
//

import SwiftUI

/// Activity log with a copy button.
struct LogsSection: View {
    let printer: PrinterManager

    var body: some View {
        GroupBox {
            ScrollView {
                Text(printer.log.isEmpty ? "—" : printer.log.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } label: {
            HStack {
                SectionLabel("Logs")
                Spacer()
                Button(action: copyLog) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(printer.log.isEmpty)
            }
        }
    }

    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(printer.log.joined(separator: "\n"), forType: .string)
    }
}
