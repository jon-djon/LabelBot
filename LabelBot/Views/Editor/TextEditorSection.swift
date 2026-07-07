//
//  TextEditorSection.swift
//  LabelBot
//

import SwiftUI

/// The label's text: one or two independent sections, each with its own size + custom text.
struct TextEditorSection: View {
    @Bindable var printer: PrinterManager

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Sections count, at the top.
                HStack(spacing: 8) {
                    RowLabel("Sections")
                    Picker("Sections", selection: $printer.current.textLayout) {
                        ForEach(TextLayout.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }

                if printer.current.textLayout == .split {
                    Text("Left").font(.caption).foregroundStyle(.secondary)
                    LabelSectionEditor(section: $printer.current.text1, category: printer.current.category)
                    Divider()
                    Text("Right").font(.caption).foregroundStyle(.secondary)
                    LabelSectionEditor(section: $printer.current.text2, category: printer.current.category)
                } else {
                    LabelSectionEditor(section: $printer.current.text1, category: printer.current.category)
                }
            }
        } label: {
            SectionLabel("Text")
        }
    }
}
