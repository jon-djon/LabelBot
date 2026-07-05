//
//  Fastener.swift
//  LabelBot
//
//  Drive and head types for screw/bolt labels, matching the common set on
//  Gridfinity label tools.
//

import Foundation

enum DriveType: String, CaseIterable, Identifiable, Sendable, Codable {
    case none, hex, torx, securityTorx, phillips, pozidriv, robertson, slotted, externalHex

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: "None"
        case .hex: "Hex / Allen"
        case .torx: "Torx"
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
    case none, countersunk, socketCap, pan, button, hex, flangeHex, grub

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
        }
    }
}

extension HeadType {
    /// Head styles offered for wood screws (always have a head).
    static let woodHeads: [HeadType] = [.countersunk, .pan, .button, .hex]
}

/// Top-level kind of fastener being labeled.
enum FastenerCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case screwBolt = "Screws / Bolts"
    case nutWasher = "Nuts & Washers"
    case insert = "Threaded Inserts"

    var id: String { rawValue }
    /// Whether drive / head / thread options apply.
    var isScrew: Bool { self == .screwBolt }
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

/// Fixed print lengths (mm) offered alongside the "Auto" (fit-to-content) option.
/// Lengths are stored in mm; Gridfinity sizes are just a convenience mapping.
enum LabelLength {
    static let auto: Double = 0   // sentinel: size to content
    static let presetsMM: [Double] = [15, 20, 25, 30, 40, 50, 60, 80, 100]

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
    case simple = "Simple"   // separate head side-profile + drive top view
    case bolt = "Bolt"       // one integrated bolt with the drive cut into the head

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

/// Standard fastener sizes for the guided pickers.
enum SizeTables {
    static let metricDiameters = ["M1.6", "M2", "M2.5", "M3", "M4", "M5", "M6", "M8", "M10", "M12"]
    static let imperialDiameters = ["#2", "#4", "#6", "#8", "#10", "#12", "1/4\"", "5/16\"", "3/8\"", "1/2\""]
    static let metricLengths = ["4", "5", "6", "8", "10", "12", "16", "20", "25", "30", "40", "50"]
    static let imperialLengths = ["1/4\"", "3/8\"", "1/2\"", "5/8\"", "3/4\"", "1\"", "1-1/4\"", "1-1/2\"", "2\""]
}
