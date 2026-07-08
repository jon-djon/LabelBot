//
//  ScrewIconGrids.swift
//  LabelBot
//

import SwiftUI

/// Drive-type and screw-type icon grids, with toggles to include each in the label.
struct ScrewIconGrids: View {
    @Bindable var printer: PrinterManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 16) {
                    Toggle("Include drive type", isOn: $printer.current.includeDrive)
                        .toggleStyle(.checkbox)
                    Toggle("Label", isOn: $printer.current.labelDrive)
                        .toggleStyle(.checkbox)
                        .disabled(printer.current.drive == .none)
                        .help("Print the drive name beneath the icon")
                    Spacer()
                }
                IconRow(options: DriveType.allCases.filter { $0 != .none },
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
                HStack(spacing: 8) {
                    Toggle("Include screw type", isOn: $printer.current.includeHead)
                        .toggleStyle(.checkbox)

                    RowDivider()
                    Toggle("Label", isOn: $printer.current.labelHead)
                        .toggleStyle(.checkbox)
                        .disabled(printer.current.head == .none)
                        .help("Print the screw-type name beneath the icon")

                    RowDivider()
                    FieldLabel("Orientation")
                    Picker("Orientation", selection: $printer.current.screwOrientation) {
                        ForEach(ScrewOrientation.allCases) { o in
                            Image(systemName: o.symbol).tag(o)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    RowDivider()
                    Toggle("Threads", isOn: $printer.current.threaded)
                        .toggleStyle(.checkbox)

                    if printer.current.screwOrientation == .horizontal {
                        RowDivider()
                        FieldLabel("Length")
                        Picker("Length", selection: $printer.current.screwLength) {
                            ForEach(ScrewLength.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Spacer()
                }
                Text("Machine screws").font(.caption).foregroundStyle(.secondary)
                IconRow(options: HeadType.allCases.filter { $0 != .none },
                        image: { h in
                            IconRenderer.swatch(key: "head-\(h.rawValue)-machine-\(printer.current.screwOrientation.rawValue)-\(printer.current.threaded)-\(printer.current.screwLength.rawValue)") {
                                IconRenderer.drawHead(h, threadKind: .machine, threaded: printer.current.threaded, orientation: printer.current.screwOrientation, length: printer.current.screwLength.factor, into: $0, rect: $1)
                            }
                        },
                        title: { $0.displayName },
                        selected: { printer.current.head == $0 && printer.current.threadKind == .machine },
                        select: {
                            var s = printer.current
                            s.head = $0; s.threadKind = .machine
                            printer.current = s
                        })
                Text("Wood screws").font(.caption).foregroundStyle(.secondary)
                IconRow(options: HeadType.woodHeads,
                        image: { h in
                            IconRenderer.swatch(key: "head-\(h.rawValue)-wood-\(printer.current.screwOrientation.rawValue)-\(printer.current.threaded)-\(printer.current.screwLength.rawValue)") {
                                IconRenderer.drawHead(h, threadKind: .wood, threaded: printer.current.threaded, orientation: printer.current.screwOrientation, length: printer.current.screwLength.factor, into: $0, rect: $1)
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
    }
}
