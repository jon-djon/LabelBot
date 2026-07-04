//
//  ContentView.swift
//  LabelBot
//

import SwiftUI

struct ContentView: View {
    @State private var printer = PrinterManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Label") {
                VStack(alignment: .leading, spacing: 10) {
                    // Tape size + live preview.
                    HStack {
                        Picker("Tape", selection: $printer.tape) {
                            ForEach(TapeSize.all) { Text($0.label).tag($0) }
                        }
                        .frame(width: 120)
                        Spacer()
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 4).fill(.white)
                        if let preview = printer.preview {
                            Image(nsImage: preview)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .padding(6)
                        }
                    }
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.4)))

                    Divider()

                    // 1. Category.
                    Picker("Type", selection: $printer.category) {
                        ForEach(FastenerCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    // 2/3. Drive + head chosen from icon grids (screws only).
                    if printer.category.isScrew {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Drive type").font(.caption).foregroundStyle(.secondary)
                            iconRow(DriveType.allCases,
                                    image: { d in
                                        d == .none ? nil : IconRenderer.swatch(key: "drive-\(d.rawValue)") {
                                            IconRenderer.drawDrive(d, into: $0, rect: $1)
                                        }
                                    },
                                    title: { $0.displayName },
                                    selected: { $0 == printer.drive },
                                    select: { printer.drive = $0 })
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Head type").font(.caption).foregroundStyle(.secondary)
                            Text("Machine screws").font(.caption2).foregroundStyle(.secondary)
                            iconRow(HeadType.allCases,
                                    image: { h in
                                        h == .none ? nil : IconRenderer.swatch(key: "head-\(h.rawValue)-machine") {
                                            IconRenderer.drawHead(h, threadKind: .machine, into: $0, rect: $1)
                                        }
                                    },
                                    title: { $0.displayName },
                                    selected: { printer.head == $0 && printer.threadKind == .machine },
                                    select: { printer.head = $0; printer.threadKind = .machine })
                            Text("Wood screws").font(.caption2).foregroundStyle(.secondary)
                            iconRow(HeadType.woodHeads,
                                    image: { h in
                                        IconRenderer.swatch(key: "head-\(h.rawValue)-wood") {
                                            IconRenderer.drawHead(h, threadKind: .wood, into: $0, rect: $1)
                                        }
                                    },
                                    title: { $0.displayName },
                                    selected: { printer.head == $0 && printer.threadKind == .wood },
                                    select: { printer.head = $0; printer.threadKind = .wood })
                        }
                    }

                    // 4. Units + size-entry mode.
                    HStack {
                        Picker("Units", selection: $printer.unit) {
                            ForEach(UnitSystem.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 180)
                        Picker("Size entry", selection: $printer.sizeMode) {
                            ForEach(SizeEntryMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 160)
                        Spacer()
                    }

                    // Size input: guided pickers or free text.
                    if printer.sizeMode == .pickers {
                        HStack {
                            Picker("Size", selection: $printer.diameter) {
                                ForEach(printer.availableDiameters, id: \.self) { Text($0).tag($0) }
                            }
                            if printer.category.isScrew {
                                Picker("Length", selection: $printer.length) {
                                    ForEach(printer.availableLengths, id: \.self) { Text($0).tag($0) }
                                }
                            }
                        }
                    } else {
                        TextField("Size (e.g. M3 × 8)", text: $printer.sizeText)
                            .textFieldStyle(.roundedBorder)
                    }

                    // 5. Custom text.
                    TextField("Custom text (optional)", text: $printer.customText)
                        .textFieldStyle(.roundedBorder)

                    // Icon source.
                    HStack {
                        Picker("Icons", selection: $printer.iconSource) {
                            ForEach(IconSource.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 160)
                        if printer.iconSource == .imported {
                            Button("Icons Folder…") { printer.revealIconFolder() }
                                .controlSize(.small)
                        }
                        Spacer()
                    }

                    Button {
                        Task { await printer.printText() }
                    } label: {
                        Label("Print Label", systemImage: "printer")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!printer.isConnected || printer.isBusy)
                }
            }
            .onAppear { printer.updatePreview() }

            GroupBox {
                ScrollView {
                    Text(printer.log.isEmpty ? "—" : printer.log.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 180)
            } label: {
                HStack {
                    Text("Log")
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(printer.log.joined(separator: "\n"), forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .disabled(printer.log.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 440)
        .toolbar { connectionToolbar }
    }

    /// Connection controls, hoisted into the window toolbar.
    @ToolbarContentBuilder
    private var connectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Transport", selection: $printer.selectedTransport) {
                ForEach(PrinterManager.TransportKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .help("Connection transport")
        }

        if printer.selectedTransport == .usb {
            ToolbarItem(placement: .navigation) {
                Button {
                    printer.scanUSB()
                } label: {
                    Label("Scan USB", systemImage: "magnifyingglass")
                }
                .help("Scan for Brother USB devices")
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
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if printer.isBusy { ProgressView().controlSize(.small) }

            Button {
                Task { await printer.printTestLabel() }
            } label: {
                Label("Test", systemImage: "testtube.2")
            }
            .disabled(!printer.isConnected || printer.isBusy)
            .help("Print the hardcoded test pattern")

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
    }
}

extension ContentView {
    /// A horizontally-scrolling row of selectable icon buttons.
    @ViewBuilder
    func iconRow<Option: Identifiable & Hashable>(
        _ options: [Option],
        image: @escaping (Option) -> NSImage?,
        title: @escaping (Option) -> String,
        selected: @escaping (Option) -> Bool,
        select: @escaping (Option) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    IconChoiceButton(image: image(option), title: title(option), selected: selected(option)) {
                        select(option)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct IconChoiceButton: View {
    let image: NSImage?
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("None")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

#Preview {
    ContentView()
}
