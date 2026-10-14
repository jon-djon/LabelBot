//
//  Fastener.swift
//  LabelBot
//
//  Drive and head types for screw/bolt labels, matching the common set on
//  Gridfinity label tools.
//

import Foundation

enum DriveType: String, CaseIterable, Identifiable, Sendable, Codable {
    case none, hex, torx, torx15, torx25, torx30, securityTorx, phillips, pozidriv, robertson, slotted, externalHex

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: "None"
        case .hex: "Hex / Allen"
        case .torx: "Torx"
        case .torx15: "T-15"
        case .torx25: "T-25"
        case .torx30: "T-30"
        case .securityTorx: "Security Torx"
        case .phillips: "Phillips"
        case .pozidriv: "Pozidriv"
        case .robertson: "Robertson"
        case .slotted: "Slotted"
        case .externalHex: "External Hex"
        }
    }
}

enum HeadType: String, CaseIterable, Identifiable, Sendable, Codable {
    case none, countersunk, socketCap, pan, button, hex, flangeHex, grub, flat

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: "None"
        case .countersunk: "Countersunk"
        case .socketCap: "Socket Cap"
        case .pan: "Pan"
        case .button: "Button"
        case .hex: "Hex"
        case .flangeHex: "Flange Hex"
        case .grub: "Grub / Set"
        case .flat: "Flat"
        }
    }
}

extension HeadType {
    /// Head styles offered for wood screws (always have a head).
    static let woodHeads: [HeadType] = [.countersunk, .flat, .pan, .button, .hex]
    /// Head styles offered for machine screws (flat is wood-only).
    static let machineHeads: [HeadType] = allCases.filter { $0 != .none && $0 != .flat }
}

/// Top-level kind of fastener being labeled.
enum FastenerCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case screwBolt = "Screws / Bolts"
    case nutWasher = "Nuts & Washers"
    case insert = "Threaded Inserts"
    case text = "Text Only"

    var id: String { rawValue }
    /// Whether the label carries fastener icons and a size (everything but text-only).
    var isFastener: Bool { self != .text }
    /// Whether drive / head / thread options apply.
    var isScrew: Bool { self == .screwBolt }
    /// Whether a length / depth dimension applies (screws and inserts).
    var hasLength: Bool { self == .screwBolt || self == .insert }
}

/// Screw thread style (affects the shaft profile).
enum ThreadKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case machine = "Machine"
    case wood = "Wood"
    var id: String { rawValue }
}

enum UnitSystem: String, CaseIterable, Identifiable, Sendable, Codable {
    case metric = "Metric"
    case imperial = "Imperial"
    var id: String { rawValue }
}

/// How the size is chosen: guided dropdowns or free text.
enum SizeEntryMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case pickers = "Pickers"
    case text = "Text"
    var id: String { rawValue }
}

/// How many text sections the label has.
enum TextLayout: String, CaseIterable, Identifiable, Sendable, Codable {
    case single = "1"   // icons on the left, text to the right
    case split = "2"    // icons in the middle, the same text on both sides

    var id: String { rawValue }
}

/// Horizontal alignment of the label content (icons + text) within the tape length.
enum LabelAlignment: String, CaseIterable, Identifiable, Sendable, Codable {
    case leading = "Left"
    case center = "Center"
    case trailing = "Right"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }
}

/// Extra spacing between the label's elements (icons and text).
enum IconSpacing: String, CaseIterable, Identifiable, Sendable, Codable {
    case normal = "Default"
    case wide = "Wide"
    case wider = "Wider"
    case widest = "Widest"

    var id: String { rawValue }
    /// Multiple applied to the gaps between icons and between icons and text.
    var factor: Double {
        switch self {
        case .normal: 1
        case .wide: 2
        case .wider: 3
        case .widest: 4
        }
    }
}

/// Size of the label's icon(s) relative to the default band-filling size, so the
/// icon can be made smaller than the text. Applies to every category.
enum IconSize: String, CaseIterable, Identifiable, Sendable, Codable {
    case normal = "Default"
    case small = "Small"
    case smaller = "Smaller"

    var id: String { rawValue }
    /// Multiple applied to the drawn icon and its column.
    var factor: Double {
        switch self {
        case .normal: 1
        case .small: 0.8
        case .smaller: 0.62
        }
    }
}

/// Enlarges the label content past the automatic fit. With a fixed length the
/// content is normally shrunk to fit the tape, which can leave the text small and
/// the band half-empty; a higher zoom scales the text + icons back up (up to
/// filling the tape width) and lets the label grow longer than requested.
enum LabelZoom: String, CaseIterable, Identifiable, Sendable, Codable {
    case fit = "Fit"
    case large = "1.5×"
    case larger = "2×"
    case max = "Max"

    var id: String { rawValue }
    /// Multiple applied to the fitted content scale; clamped to the tape band when
    /// rendered. `.max` is large enough to always fill the band.
    var factor: Double {
        switch self {
        case .fit: 1
        case .large: 1.5
        case .larger: 2
        case .max: 100
        }
    }
}

/// Blank space added before and after the label's content (icons + text). With a
/// fixed length the content shrinks to make room, so the length still holds.
enum LabelPadding: String, CaseIterable, Identifiable, Sendable, Codable {
    case off = "None"   // not `.none`, which collides with Optional.none
    case small = "2 mm"
    case medium = "5 mm"
    case large = "10 mm"
    case extraLarge = "15 mm"

    var id: String { rawValue }
    var mm: Double {
        switch self {
        case .off: 0
        case .small: 2
        case .medium: 5
        case .large: 10
        case .extraLarge: 15
        }
    }
}

/// Fixed print lengths (mm) offered alongside the "Auto" (fit-to-content) option.
/// Lengths are stored in mm; Gridfinity sizes are just a convenience mapping.
enum LabelLength {
    static let auto: Double = 0   // sentinel: size to content
    static let presetsMM: [Double] = [15, 20, 25, 30, 40, 50, 60, 80, 100, 120, 140, 160, 180, 200]

    /// One Gridfinity unit is 35 mm.
    static let gridfinityMM: Double = 35
    static let gridfinityUnits: [Double] = [0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 5, 6]

    /// Millimeter length for a Gridfinity size (in 0.5-unit steps).
    static func mm(forGridfinity units: Double) -> Double { units * gridfinityMM }

    /// Menu label for a Gridfinity size, e.g. "1 GU" or "0.5 GU".
    static func gridfinityLabel(_ units: Double) -> String {
        let value = units.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(units))" : "\(units)"
        return "\(value) GU"
    }
}

/// Selectable nut / washer icons.
enum NutWasherType: String, CaseIterable, Identifiable, Sendable, Codable {
    case hexNut, squareNut, washer, lockWasher, tNut

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .hexNut: "Hex Nut"
        case .squareNut: "Square Nut"
        case .washer: "Washer"
        case .lockWasher: "Lock Washer"
        case .tNut: "T-Nut"
        }
    }
}

/// How screw icons are drawn.
enum IconStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case separate = "Separate"   // separate head side-profile + drive top view
    case combined = "Combined"   // one integrated bolt with the drive cut into the head

    var id: String { rawValue }
}

/// Orientation of the screw side-profile (head) icon.
enum ScrewOrientation: String, CaseIterable, Identifiable, Sendable, Codable {
    case vertical = "Vertical"
    case horizontal = "Horizontal"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .vertical: "arrow.up.and.down"
        case .horizontal: "arrow.left.and.right"
        }
    }
}

/// Relative shaft length for a horizontally-oriented screw icon.
enum ScrewLength: String, CaseIterable, Identifiable, Sendable, Codable {
    case standard = "Default"
    case x2 = "2"
    case x3 = "3"
    case x4 = "4"

    var id: String { rawValue }
    /// Length multiple applied to the drawn shaft (1 = default proportions).
    var factor: Double {
        switch self {
        case .standard: 1
        case .x2: 2
        case .x3: 3
        case .x4: 4
        }
    }
}

/// Standard fastener sizes for the guided pickers.
enum SizeTables {
    static let metricDiameters = ["M1.6", "M2", "M2.5", "M3", "M4", "M5", "M6", "M8", "M10", "M12"]
    static let imperialDiameters = (1...20).map { "#\($0)" } + ["1/4\"", "5/16\"", "3/8\"", "1/2\""]
    static let metricLengths = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "12", "16", "20", "25", "30", "40", "50"]
    /// Every whole inch up to 10", each followed by its 1/8" steps (stopping at 10").
    static let imperialLengths: [String] = {
        let fractions = ["1/8", "1/4", "3/8", "1/2", "5/8", "3/4", "7/8"]
        var lengths: [String] = []
        for inch in 0...10 {
            if inch > 0 { lengths.append("\(inch)\"") }
            guard inch < 10 else { break }
            lengths += fractions.map { inch == 0 ? "\($0)\"" : "\(inch)-\($0)\"" }
        }
        return lengths
    }()
}
