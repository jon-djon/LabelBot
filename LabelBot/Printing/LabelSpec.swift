//
//  LabelSpec.swift
//  LabelBot
//
//  A single label's full configuration — the unit of work for batch printing.
//  Tape width is deliberately NOT part of the spec: it's the physically loaded
//  tape, shared by every label in a batch.
//

import Foundation

struct LabelSpec: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()

    // Length + alignment.
    var lengthMM: Double = LabelLength.auto     // 0 = auto/fit
    var alignment: LabelAlignment = .center

    // Fastener type + icon options.
    var category: FastenerCategory = .screwBolt
    var drive: DriveType = .hex
    var head: HeadType = .pan
    var threadKind: ThreadKind = .machine
    var screwOrientation: ScrewOrientation = .vertical
    var iconStyle: IconStyle = .simple
    var threaded = true
    var nutWasher: NutWasherType = .hexNut
    var showIcons = true

    // Size + text.
    var unit: UnitSystem = .metric
    var sizeMode: SizeEntryMode = .pickers
    var diameter = SizeTables.metricDiameters[3]   // M3
    var length = SizeTables.metricLengths[3]       // 8
    var sizeText = "M3 × 8"
    var customText = ""

    // Batch.
    var copies = 1

    var availableDiameters: [String] { unit == .metric ? SizeTables.metricDiameters : SizeTables.imperialDiameters }
    var availableLengths: [String] { unit == .metric ? SizeTables.metricLengths : SizeTables.imperialLengths }

    /// The size portion of the label, from pickers or the free-text field.
    var sizeString: String {
        switch sizeMode {
        case .text:
            return sizeText.trimmingCharacters(in: .whitespaces)
        case .pickers:
            if category.isScrew {
                return length.isEmpty ? diameter : "\(diameter) × \(length)"
            }
            return diameter
        }
    }

    /// Full label text: size plus any custom text.
    var labelText: String {
        [sizeString, customText]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    /// Title shown in the queue row.
    var title: String {
        let t = labelText
        return t.isEmpty ? "Untitled" : t
    }

    /// One-line detail shown under the title in the queue row.
    var subtitle: String {
        switch category {
        case .screwBolt:
            let parts = [head == .none ? nil : head.displayName,
                         drive == .none ? nil : drive.displayName].compactMap { $0 }
            return parts.isEmpty ? "Screw / bolt" : parts.joined(separator: " · ")
        case .nutWasher:
            return nutWasher.displayName
        case .insert:
            return "Threaded insert"
        }
    }

    /// Keeps the diameter/length selections valid after a unit switch.
    mutating func normalizeForUnit() {
        if !availableDiameters.contains(diameter) { diameter = availableDiameters.first ?? "" }
        if !availableLengths.contains(length) { length = availableLengths.first ?? "" }
    }
}

/// A saved/loaded batch: the shared tape plus its labels.
struct LabelBatch: Codable {
    var tapeWidthMM: UInt8 = TapeSize.tape24.widthMM
    var cutBetween = true
    var labels: [LabelSpec] = []
}
