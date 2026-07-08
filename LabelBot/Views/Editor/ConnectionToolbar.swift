//
//  ConnectionToolbar.swift
//  LabelBot
//

import SwiftUI

/// The window toolbar: transport picker, status, batch menu, log toggle, and connect/print.
struct ConnectionToolbar: ToolbarContent {
    @Bindable var printer: PrinterManager
    @Binding var showLogs: Bool
    @Binding var showGenerate: Bool
    @Binding var generateText: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Transport", selection: $printer.selectedTransport) {
                ForEach(PrinterManager.TransportKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .help("Connection transport")
        }

        ToolbarItem(placement: .navigation) {
            if printer.isConnected {
                Button(role: .destructive) {
                    printer.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "cable.connector.slash")
                }
            } else {
                Button {
                    Task { await printer.connect() }
                } label: {
                    Label("Connect", systemImage: "cable.connector")
                }
                .disabled(printer.isBusy)
            }
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Circle()
                    .fill(printer.isConnected ? Color.green : Color.secondary)
                    .frame(width: 9, height: 9)
                Text(printer.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Button("Open batch…") { printer.openBatch() }
                Button("Save batch…") { printer.saveBatch() }
                Divider()
                Button("Add from list…") { showGenerateSheet() }
            } label: {
                Label("Batch", systemImage: "ellipsis.circle")
            }
            .help("Open, save, or bulk-add labels")
        }

        ToolbarItem(placement: .automatic) {
            Toggle(isOn: $showLogs) {
                Label("Logs", systemImage: "square.bottomthird.inset.filled")
            }
            .help(showLogs ? "Hide log" : "Show log")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if printer.isBusy { ProgressView().controlSize(.small) }

            Button {
                Task { await printer.printAll() }
            } label: {
                Label("Print all · \(printer.totalLabels)", systemImage: "printer")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("p", modifiers: .command)
            .disabled(!printer.isConnected || printer.isBusy)
            .help("Print every label in the queue")
        }
    }

    private func showGenerateSheet() {
        generateText = ""
        showGenerate = true
    }
}
