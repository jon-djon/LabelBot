//
//  ContentView.swift
//  LabelBot
//

import SwiftUI

struct ContentView: View {
    @State private var printer = PrinterManager()
    @State private var showLogs = false
    @State private var showGenerate = false
    @State private var generateText = ""

    var body: some View {
        NavigationSplitView {
            LabelSidebar(printer: printer, showGenerate: $showGenerate, generateText: $generateText)
        } detail: {
            VSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        PreviewSection(printer: printer)
                        Divider()
                        TapeSection(printer: printer)
                        Divider()
                        CategorySection(printer: printer)
                        Divider()
                        TextEditorSection(printer: printer)
                        Divider()
                        IconsSection(printer: printer)
                    }
                    .padding(20)
                }
                .frame(minWidth: 380, minHeight: 300)

                if showLogs {
                    LogsSection(printer: printer)
                        .padding(20)
                        .frame(minHeight: 140)
                }
            }
        }
        .frame(minWidth: 880, minHeight: 500)
        .toolbar {
            ConnectionToolbar(printer: printer, showLogs: $showLogs,
                              showGenerate: $showGenerate, generateText: $generateText)
        }
        .sheet(isPresented: $showGenerate) {
            GenerateSheet(printer: printer, isPresented: $showGenerate, text: $generateText)
        }
        .onAppear { printer.updatePreview() }
    }
}

#Preview {
    ContentView()
}
