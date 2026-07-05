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
            labelSidebar
        } detail: {
            VSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        previewSection
                        Divider()
                        tapeSection
                        Divider()
                        categorySection
                        Divider()
                        textSection
                        Divider()
                        iconsSection
                    }
                    .padding(20)
                }
                .frame(minWidth: 380, minHeight: 300)

                if showLogs {
                    logsSection
                        .padding(20)
                        .frame(minHeight: 140)
                }
            }
        }
        .frame(minWidth: 880, minHeight: 500)
        .toolbar { connectionToolbar }
        .sheet(isPresented: $showGenerate) { generateSheet }
        .onAppear { printer.updatePreview() }
    }

    // MARK: - Label queue

    private var labelSidebar: some View {
        List(selection: $printer.selection) {
            ForEach(printer.labels) { spec in
                queueRow(spec)
            }
            .onMove { printer.moveLabels(from: $0, to: $1) }
        }
        .navigationTitle("Labels")
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 4) {
                    Button { printer.addLabel() } label: { Image(systemName: "plus") }
                        .help("Add label")
                    Button { printer.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                        .help("Duplicate label")
                    Button { printer.deleteSelected() } label: { Image(systemName: "trash") }
                        .help("Delete label")
                        .disabled(printer.labels.count <= 1)
                    Spacer()
                    Button { generateText = ""; showGenerate = true } label: { Image(systemName: "text.badge.plus") }
                        .help("Add many labels from a list")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                Divider()
                Toggle("Cut between labels", isOn: $printer.cutBetween)
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .background(.bar)
        }
    }

    private func queueRow(_ spec: LabelSpec) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: printer.thumbnail(for: spec))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 28)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))

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

    // MARK: - Editor sections

    /// SwiftUI alignment mirroring the label's left/center/right setting.
    private var previewAlignment: Alignment {
        switch printer.current.alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// A prominent header for the section GroupBoxes.
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }

    /// Live label preview.
    private var previewSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
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

                HStack(spacing: 6) {
                    Label("Height \(mmString(printer.previewHeightMM))", systemImage: "arrow.up.and.down")
                    Text("·").foregroundStyle(.tertiary)
                    Label("Length \(mmString(printer.previewLengthMM))", systemImage: "arrow.left.and.right")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } label: {
            sectionLabel("Preview")
        }
    }

    /// Formats a millimeter measurement, dropping a trailing ".0".
    private func mmString(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let number = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
        return "\(number) mm"
    }

    /// Tape width (shared) + this label's length and alignment.
    private var tapeSection: some View {
        GroupBox {
            HStack(spacing: 16) {
                Picker("Tape", selection: $printer.tape) {
                    ForEach(TapeSize.all) { Text($0.label).tag($0) }
                }
                .frame(width: 130)

                rowDivider

                Picker("Length", selection: $printer.current.lengthMM) {
                    Text("Auto").tag(LabelLength.auto)
                    Section("Millimeters") {
                        ForEach(LabelLength.presetsMM, id: \.self) { Text("\(Int($0)) mm").tag($0) }
                    }
                    Section("Gridfinity") {
                        ForEach(LabelLength.gridfinityUnits, id: \.self) { units in
                            Text(LabelLength.gridfinityLabel(units))
                                .tag(LabelLength.mm(forGridfinity: units))
                        }
                    }
                }
                .frame(width: 150)

                rowDivider

                Picker("Align", selection: $printer.current.alignment) {
                    ForEach(LabelAlignment.allCases) { align in
                        Image(systemName: align.symbol).tag(align)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)

                Spacer()
            }
        } label: {
            sectionLabel("Tape options")
        }
    }

    /// Fastener category + copies, above the text section.
    private var categorySection: some View {
        HStack(spacing: 12) {
            Picker("Type", selection: $printer.current.category) {
                ForEach(FastenerCategory.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Stepper(value: $printer.current.copies, in: 1...99) {
                Text("Copies: \(printer.current.copies)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
    }

    /// Everything that makes up the label text: 1 or 2 sections, each with its own
    /// size + custom text.
    private var textSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Sections count, at the top.
                HStack(spacing: 8) {
                    rowLabel("Sections")
                    Picker("Sections", selection: $printer.current.textLayout) {
                        ForEach(TextLayout.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }

                if printer.current.textLayout == .split {
                    Text("Left").font(.caption2).foregroundStyle(.secondary)
                    textEditor($printer.current.text1)
                    Divider()
                    Text("Right").font(.caption2).foregroundStyle(.secondary)
                    textEditor($printer.current.text2)
                } else {
                    textEditor($printer.current.text1)
                }
            }
        } label: {
            sectionLabel("Text")
        }
    }

    /// Inline caption label (natural width) before a mid-row control.
    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    /// A row's leading label — fixed width so every row's first control starts at the
    /// same x. Controls use `.fixedSize()` so their bezels sit at the leading edge
    /// (a framed segmented control centers its content and looks misaligned).
    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
            .frame(width: 74, alignment: .leading)
    }

    private var rowDivider: some View {
        Divider().frame(height: 22)
    }

    /// Size (pickers or free text) + custom text for one text section.
    @ViewBuilder
    private func textEditor(_ section: Binding<TextSection>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: entry mode.
            HStack(spacing: 8) {
                rowLabel("Mode")
                Picker("Size entry", selection: section.sizeMode) {
                    ForEach(SizeEntryMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            // Pickers: units · size · length, each labeled and divided. Text: a field.
            if section.wrappedValue.sizeMode == .pickers {
                HStack(spacing: 8) {
                    rowLabel("Units")
                    Picker("Units", selection: section.unit) {
                        ForEach(UnitSystem.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    rowDivider
                    fieldLabel("Size")
                    Picker("Size", selection: section.diameter) {
                        ForEach(section.wrappedValue.availableDiameters, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()

                    if printer.current.category.isScrew {
                        rowDivider
                        fieldLabel("Length")
                        Picker("Length", selection: section.length) {
                            ForEach(section.wrappedValue.availableLengths, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    rowLabel("Size")
                    TextField("e.g. M3 × 8", text: section.sizeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                rowLabel("Custom")
                TextField("Optional", text: section.customText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                Spacer()
            }
        }
    }

    /// Icon on/off plus the drive/head pickers (screws only).
    private var iconsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show icons", isOn: $printer.current.showIcons)
                    .toggleStyle(.switch)

                // Style / label / orientation / threads on one row, divided like the Text section.
                HStack(spacing: 8) {
                    if printer.current.category.isScrew {
                        fieldLabel("Style")
                        Picker("Style", selection: $printer.current.iconStyle) {
                            ForEach(IconStyle.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()

                        rowDivider
                    }

                    Toggle("Label icons", isOn: $printer.current.labelIcons)
                        .toggleStyle(.switch)
                        .help("Print each icon's name beneath it")

                    if printer.current.category.isScrew {
                        rowDivider
                        fieldLabel("Orientation")
                        Picker("Orientation", selection: $printer.current.screwOrientation) {
                            ForEach(ScrewOrientation.allCases) { o in
                                Image(systemName: o.symbol).tag(o)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()

                        rowDivider
                        Toggle("Threads", isOn: $printer.current.threaded)
                            .toggleStyle(.switch)
                    }
                    Spacer()
                }
                .disabled(!printer.current.showIcons)

                VStack(alignment: .leading, spacing: 10) {
                    // Drive + screw type chosen from icon grids (screws only).
                    if printer.current.category.isScrew {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Include drive type", isOn: Binding(
                                get: { printer.current.drive != .none },
                                set: { printer.current.drive = $0 ? .hex : .none }
                            ))
                            .toggleStyle(.checkbox)
                            iconRow(DriveType.allCases.filter { $0 != .none },
                                    image: { d in
                                        IconRenderer.swatch(key: "drive-\(d.rawValue)") {
                                            IconRenderer.drawDrive(d, into: $0, rect: $1)
                                        }
                                    },
                                    title: { $0.displayName },
                                    selected: { $0 == printer.current.drive },
                                    select: { printer.current.drive = $0 })
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Include screw type", isOn: Binding(
                                get: { printer.current.head != .none },
                                set: { printer.current.head = $0 ? .pan : .none }
                            ))
                            .toggleStyle(.checkbox)
                            Text("Machine screws").font(.caption2).foregroundStyle(.secondary)
                            iconRow(HeadType.allCases.filter { $0 != .none },
                                    image: { h in
                                        IconRenderer.swatch(key: "head-\(h.rawValue)-machine-\(printer.current.screwOrientation.rawValue)-\(printer.current.threaded)") {
                                            IconRenderer.drawHead(h, threadKind: .machine, threaded: printer.current.threaded, orientation: printer.current.screwOrientation, into: $0, rect: $1)
                                        }
                                    },
                                    title: { $0.displayName },
                                    selected: { printer.current.head == $0 && printer.current.threadKind == .machine },
                                    select: {
                                        var s = printer.current
                                        s.head = $0; s.threadKind = .machine
                                        printer.current = s
                                    })
                            Text("Wood screws").font(.caption2).foregroundStyle(.secondary)
                            iconRow(HeadType.woodHeads,
                                    image: { h in
                                        IconRenderer.swatch(key: "head-\(h.rawValue)-wood-\(printer.current.screwOrientation.rawValue)-\(printer.current.threaded)") {
                                            IconRenderer.drawHead(h, threadKind: .wood, threaded: printer.current.threaded, orientation: printer.current.screwOrientation, into: $0, rect: $1)
                                        }
                                    },
                                    title: { $0.displayName },
                                    selected: { printer.current.head == $0 && printer.current.threadKind == .wood },
                                    select: {
                                        var s = printer.current
                                        s.head = $0; s.threadKind = .wood
                                        printer.current = s
                                    })
                        }
                    }

                    // Nut / washer chosen from an icon grid.
                    if printer.current.category == .nutWasher {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nut / washer").font(.caption).foregroundStyle(.secondary)
                            iconRow(NutWasherType.allCases,
                                    image: { t in
                                        IconRenderer.swatch(key: "nutwasher-\(t.rawValue)") {
                                            IconRenderer.drawNutWasher(t, into: $0, rect: $1)
                                        }
                                    },
                                    title: { $0.displayName },
                                    selected: { $0 == printer.current.nutWasher },
                                    select: { printer.current.nutWasher = $0 })
                        }
                    }
                }
                .disabled(!printer.current.showIcons)
            }
        } label: {
            sectionLabel("Icons")
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
                sectionLabel("Logs")
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

    // MARK: - Add-from-list sheet

    private var generateSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add labels from a list").font(.headline)
            Text("One size per line, or comma-separated. Each becomes a label using the selected label's type and icons.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $generateText)
                .font(.body.monospaced())
                .frame(width: 380, height: 170)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button("Cancel") { showGenerate = false }
                Button("Add labels") {
                    printer.generateLabels(from: generateText)
                    showGenerate = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(generateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    // MARK: - Toolbar

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
            Menu {
                Button("Open batch…") { printer.openBatch() }
                Button("Save batch…") { printer.saveBatch() }
                Divider()
                Button("Add from list…") { generateText = ""; showGenerate = true }
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
