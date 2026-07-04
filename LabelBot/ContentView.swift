//
//  ContentView.swift
//  LabelBot
//

import SwiftUI

struct ContentView: View {
    @State private var printer = PrinterManager()
    @State private var showLogs = false

    var body: some View {
        VSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewSection
                    categorySection
                    textSection
                    iconsSection
                }
                .padding(20)
                .onAppear { printer.updatePreview() }
            }
            .frame(minHeight: 260)

            if showLogs {
                logsSection
                    .padding(20)
                    .frame(minHeight: 140)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .toolbar { connectionToolbar }
    }

    // MARK: - Sections

    /// SwiftUI alignment mirroring the label's left/center/right setting.
    private var previewAlignment: Alignment {
        switch printer.alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// Tape width + live label preview.
    private var previewSection: some View {
        GroupBox("Preview") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Picker("Tape", selection: $printer.tape) {
                        ForEach(TapeSize.all) { Text($0.label).tag($0) }
                    }
                    .frame(width: 130)

                    Picker("Length", selection: $printer.lengthMM) {
                        Text("Auto").tag(LabelLength.auto)
                        ForEach(LabelLength.presetsMM, id: \.self) { Text("\($0) mm").tag($0) }
                    }
                    .frame(width: 150)

                    Picker("Align", selection: $printer.alignment) {
                        ForEach(LabelAlignment.allCases) { align in
                            Image(systemName: align.symbol).tag(align)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)

                    Spacer()
                }

                ZStack(alignment: previewAlignment) {
                    RoundedRectangle(cornerRadius: 4).fill(.white)
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
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.4)))
            }
        }
    }

    /// Top-level fastener category, above the text section.
    private var categorySection: some View {
        Picker("Type", selection: $printer.category) {
            ForEach(FastenerCategory.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// Everything that makes up the label text: size + custom text.
    private var textSection: some View {
        GroupBox("Text") {
            VStack(alignment: .leading, spacing: 10) {
                // Size: unit system + entry mode + the size value itself.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Size").font(.caption).foregroundStyle(.secondary)
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
                }

                // Custom text.
                TextField("Custom text (optional)", text: $printer.customText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    /// Icon on/off plus the drive/head pickers (screws only).
    private var iconsSection: some View {
        GroupBox("Icons") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show icons", isOn: $printer.showIcons)
                    .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 10) {
                    // Drive + head chosen from icon grids (screws only).
                    if printer.category.isScrew {
                        HStack {
                            Text("Style").font(.caption).foregroundStyle(.secondary)
                            Picker("Style", selection: $printer.iconStyle) {
                                ForEach(IconStyle.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 130)
                            Spacer()
                        }

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
                                        h == .none ? nil : IconRenderer.swatch(key: "head-\(h.rawValue)-machine-\(printer.screwOrientation.rawValue)-\(printer.threaded)") {
                                            IconRenderer.drawHead(h, threadKind: .machine, threaded: printer.threaded, orientation: printer.screwOrientation, into: $0, rect: $1)
                                        }
                                    },
                                    title: { $0.displayName },
                                    selected: { printer.head == $0 && printer.threadKind == .machine },
                                    select: { printer.head = $0; printer.threadKind = .machine })
                            Text("Wood screws").font(.caption2).foregroundStyle(.secondary)
                            iconRow(HeadType.woodHeads,
                                    image: { h in
                                        IconRenderer.swatch(key: "head-\(h.rawValue)-wood-\(printer.screwOrientation.rawValue)-\(printer.threaded)") {
                                            IconRenderer.drawHead(h, threadKind: .wood, threaded: printer.threaded, orientation: printer.screwOrientation, into: $0, rect: $1)
                                        }
                                    },
                                    title: { $0.displayName },
                                    selected: { printer.head == $0 && printer.threadKind == .wood },
                                    select: { printer.head = $0; printer.threadKind = .wood })
                        }

                        // Orientation + threads, under the head type section.
                        HStack(spacing: 16) {
                            HStack {
                                Text("Orientation").font(.caption).foregroundStyle(.secondary)
                                Picker("Orientation", selection: $printer.screwOrientation) {
                                    ForEach(ScrewOrientation.allCases) { o in
                                        Image(systemName: o.symbol).tag(o)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 100)
                            }
                            Toggle("Threads", isOn: $printer.threaded)
                            Spacer()
                        }
                    }

                    // Nut / washer chosen from an icon grid.
                    if printer.category == .nutWasher {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nut / washer").font(.caption).foregroundStyle(.secondary)
                            iconRow(NutWasherType.allCases,
                                    image: { t in
                                        IconRenderer.swatch(key: "nutwasher-\(t.rawValue)") {
                                            IconRenderer.drawNutWasher(t, into: $0, rect: $1)
                                        }
                                    },
                                    title: { $0.displayName },
                                    selected: { $0 == printer.nutWasher },
                                    select: { printer.nutWasher = $0 })
                        }
                    }
                }
                .disabled(!printer.showIcons)
            }
        }
    }

    /// Activity log with a copy button.
    private var logsSection: some View {
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
                Text("Logs")
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
            .padding(.horizontal, 12)
        }

        ToolbarItem(placement: .automatic) {
            Toggle(isOn: $showLogs) {
                Label("Logs", systemImage: "square.bottomthird.inset.filled")
            }
            .help(showLogs ? "Hide log" : "Show log")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if printer.isBusy { ProgressView().controlSize(.small) }

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

            Button {
                Task { await printer.printText() }
            } label: {
                Label("Print Label", systemImage: "printer")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("p", modifiers: .command)
            .disabled(!printer.isConnected || printer.isBusy)
            .help("Print the current label")
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
            HStack(alignment: .top, spacing: 8) {
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
            VStack(spacing: 4) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .interpolation(.high)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "nosign")
                            .font(.title3)
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

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

#Preview {
    ContentView()
}
