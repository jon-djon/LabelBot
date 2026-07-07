//
//  NutWasherGrid.swift
//  LabelBot
//

import SwiftUI

/// Nut / washer icon grid.
struct NutWasherGrid: View {
    @Bindable var printer: PrinterManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nut / washer").font(.caption).foregroundStyle(.secondary)
            IconRow(options: NutWasherType.allCases,
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
