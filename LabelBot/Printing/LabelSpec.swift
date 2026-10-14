//
//  LabelSpec.swift
//  LabelBot
//
//  A single label's full configuration — the unit of work for batch printing.
//  Tape width is deliberately NOT part of the spec: it's the physically loaded
//  tape, shared by every label in a batch.
//

import Foundation

/// One text region of a label: a size (from pickers or free text) plus custom text.
struct TextSection: Equatable, Codable, Sendable {
    var unit: UnitSystem = .metric
    var sizeMode: SizeEntryMode = .pickers
    var diameter = SizeTables.metricDiameters[3]   // M3 (thread size)
    var length = SizeTables.metricLengths[3]       // 8
    var sizeText = "M3 × 8"
    var customText = ""

    // Threaded-insert extras: the barrel diameter (drawn with a ↔) and an
    // optional internal / bore diameter.
    var outerDiameter = ""
    var innerDiameter = ""

    var availableDiameters: [String] { unit == .metric ? SizeTables.metricDiameters : SizeTables.imperialDiameters }
    var availableLengths: [String] { unit == .metric ? SizeTables.metricLengths : SizeTables.imperialLengths }

    /// The size portion of the text, from pickers or the free-text field.
    func sizeString(hasLength: Bool) -> String {
        switch sizeMode {
        case .text:
            return sizeText.trimmingCharacters(in: .whitespaces)
        case .pickers:
            if hasLength {
                return length.isEmpty ? diameter : "\(diameter) × \(length)"
            }
            return diameter
        }
    }

    /// Full text: size plus any custom text.
    func text(hasLength: Bool) -> String {
        [sizeString(hasLength: hasLength), customText]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    /// Keeps the diameter/length selections valid after a unit switch.
    mutating func normalizeForUnit() {
        if !availableDiameters.contains(diameter) { diameter = availableDiameters.first ?? "" }
        if !availableLengths.contains(length) { length = availableLengths.first ?? "" }
    }
}

struct LabelSpec: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()

    // Length + alignment + section layout.
    var lengthMM: Double = LabelLength.auto     // 0 = auto/fit
    var alignment: LabelAlignment = .center
    var iconSpacing: IconSpacing = .normal      // gap between icons and text
    var zoom: LabelZoom = .fit                  // enlarge content past the fit-to-length
    // Blank space before and after the content. Optional so batches saved before
    // it existed still decode; nil means none.
    var padding: LabelPadding? = nil
    var border = false                          // draw a box around the whole label
    var sizeBorder = false                       // draw a box around just the size (e.g. M3)
    var boldText = false                         // bold every text, not just the size
    var fontName: String? = nil                  // font family; nil = system font
    var textLayout: TextLayout = .single

    // Fastener type + icon options.
    var category: FastenerCategory = .screwBolt
    var drive: DriveType = .hex
    var head: HeadType = .pan
    var threadKind: ThreadKind = .machine
    var screwOrientation: ScrewOrientation = .vertical
    var screwLength: ScrewLength = .standard    // horizontal-only shaft length
    var iconStyle: IconStyle = .separate
    var iconSize: IconSize = .normal            // shrink icons relative to the text
    var threaded = true
    var nutWasher: NutWasherType = .hexNut
    var showIcons = true
    // Caption icons with their names — independently for the drive icon and the
    // screw-type (head) icon. Nut/washer and insert use `labelHead`.
    var labelDrive = false
    var labelHead = false

    // Text: one section (single) or two (split, one on each side of the icons).
    var text1 = TextSection()
    var text2 = TextSection()

    // Batch.
    var copies = 1

    /// Whether the drive icon is shown; toggling off clears it, on restores a default.
    var includeDrive: Bool {
        get { drive != .none }
        set { drive = newValue ? .hex : .none }
    }
    /// Whether the screw-type (head) icon is shown.
    var includeHead: Bool {
        get { head != .none }
        set { head = newValue ? .pan : .none }
    }

    /// The primary (left / only) text.
    var leftText: String { text(of: text1) }
    /// The second (right) text, used only in split layout.
    var rightText: String { text(of: text2) }

    /// A section's full text; text-only labels have no size, just the custom text.
    private func text(of section: TextSection) -> String {
        category.isFastener
            ? section.text(hasLength: category.hasLength)
            : section.customText.trimmingCharacters(in: .whitespaces)
    }

    /// Title shown in the queue row.
    var title: String {
        let t = leftText
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
        case .text:
            return "Text"
        }
    }
}

/// A saved/loaded batch: the shared tape plus its labels.
struct LabelBatch: Codable {
    var tapeWidthMM: UInt8 = TapeSize.tape24.widthMM
    var cutBetween = true
    var labels: [LabelSpec] = []
}
