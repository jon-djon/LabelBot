//
//  PrinterManager.swift
//  LabelBot
//
//  Drives the connection lifecycle and printing. Owns the active transport and
//  exposes observable state for the UI. Blocking I/O runs off the main actor.
//

import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class PrinterManager {

    enum TransportKind: String, CaseIterable, Identifiable {
        case bluetooth = "Bluetooth"
        case usb = "USB"
        var id: String { rawValue }
    }

    var selectedTransport: TransportKind = .bluetooth
    var statusText = "Not connected"
    var isConnected = false
    var isBusy = false
    private(set) var log: [String] = []

    // Label composition.
    var tape: TapeSize = .tape24 { didSet { updatePreview() } }
    var lengthMM: Int = LabelLength.auto { didSet { updatePreview() } }   // 0 = auto/fit
    var alignment: LabelAlignment = .center { didSet { updatePreview() } }
    var category: FastenerCategory = .screwBolt { didSet { updatePreview() } }
    var drive: DriveType = .hex { didSet { updatePreview() } }
    var head: HeadType = .pan { didSet { updatePreview() } }
    var threadKind: ThreadKind = .machine { didSet { updatePreview() } }
    var screwOrientation: ScrewOrientation = .vertical { didSet { updatePreview() } }
    var iconStyle: IconStyle = .simple { didSet { updatePreview() } }
    var threaded = true { didSet { updatePreview() } }
    var nutWasher: NutWasherType = .hexNut { didSet { updatePreview() } }
    var unit: UnitSystem = .metric { didSet { unitChanged() } }
    var sizeMode: SizeEntryMode = .pickers { didSet { updatePreview() } }
    var diameter = SizeTables.metricDiameters[3] { didSet { updatePreview() } }   // M3
    var length = SizeTables.metricLengths[3] { didSet { updatePreview() } }       // 8
    var sizeText = "M3 × 8" { didSet { updatePreview() } }
    var customText = "" { didSet { updatePreview() } }
    var showIcons = true { didSet { updatePreview() } }
    var iconSource: IconSource = .drawn { didSet { updatePreview() } }
    private(set) var preview: NSImage?

    private var transport: PrinterTransport?

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

    private func unitChanged() {
        if !availableDiameters.contains(diameter) { diameter = availableDiameters.first ?? "" }
        if !availableLengths.contains(length) { length = availableLengths.first ?? "" }
        updatePreview()
    }

    private func renderLabel() -> RenderedLabel {
        let fixedLengthDots = lengthMM > 0
            ? Int((Double(lengthMM) * LabelRenderer.dotsPerMM).rounded())
            : nil
        return LabelRenderer.render(text: labelText, tape: tape, category: category,
                                    drive: drive, head: head, threadKind: threadKind,
                                    source: iconSource, showIcons: showIcons,
                                    iconStyle: iconStyle, threaded: threaded,
                                    nutWasher: nutWasher,
                                    screwOrientation: screwOrientation,
                                    fixedLengthDots: fixedLengthDots, alignment: alignment)
    }

    func updatePreview() {
        preview = renderLabel().preview
    }

    /// Opens the folder where "Imported" icon files should be placed.
    func revealIconFolder() {
        let url = IconRenderer.importDirectory
        appendLog("Imported icons folder: \(url.path)")
        NSWorkspace.shared.open(url)
    }

    private func appendLog(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.append("[\(stamp)] \(line)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    /// Enumerates Brother USB devices so we can confirm the real product id / layout.
    func scanUSB() {
        appendLog("USB scan:")
        USBTransport.scan().forEach { appendLog("  • \($0)") }
    }

    func connect() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let newTransport: PrinterTransport =
            selectedTransport == .bluetooth ? BluetoothTransport() : USBTransport()
        do {
            try await Task.detached { try newTransport.connect() }.value
            transport = newTransport
            isConnected = true
            statusText = "Connected to \(newTransport.displayName)"
            appendLog("Connected via \(selectedTransport.rawValue): \(newTransport.displayName)")
        } catch {
            isConnected = false
            statusText = "Connect failed"
            appendLog("Connect error: \(error.localizedDescription)")
        }
    }

    func printTestLabel() async {
        guard !isBusy else { return }
        guard let transport else {
            statusText = "Not connected"
            appendLog("Print skipped: not connected")
            return
        }
        isBusy = true
        defer { isBusy = false }

        let payload = RasterEncoder.testPattern()
        let statusRequest = RasterEncoder.statusRequest
        do {
            let statusBytes = try await Task.detached { () -> Data in
                try transport.send(payload)
                try transport.send(statusRequest)
                return try transport.readStatus(maxLength: 32, timeout: 3)
            }.value
            appendLog("Sent test pattern (\(payload.count) bytes)")
            if statusBytes.isEmpty {
                appendLog("No status reply (expected in Phase 0 — needs a run loop / IN pipe)")
            } else {
                let hex = statusBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                appendLog("Status (\(statusBytes.count) B): \(hex)")
            }
            statusText = "Printed test label"
        } catch {
            statusText = "Print failed"
            appendLog("Print error: \(error.localizedDescription)")
        }
    }

    func printText() async {
        guard !isBusy else { return }
        guard let transport else {
            statusText = "Not connected"
            appendLog("Print skipped: not connected")
            return
        }
        isBusy = true
        defer { isBusy = false }

        let rendered = renderLabel()
        preview = rendered.preview
        guard !rendered.rasterLines.isEmpty else {
            appendLog("Nothing to print")
            return
        }
        let payload = RasterEncoder.job(lines: rendered.rasterLines, tapeWidthMM: tape.widthMM)
        do {
            try await Task.detached { try transport.send(payload) }.value
            appendLog("Printed \"\(labelText)\" — \(rendered.lengthDots) dots long, \(tape.label) (\(payload.count) B)")
            statusText = "Printed label"
        } catch {
            appendLog("Print error: \(error.localizedDescription)")
            statusText = "Print failed"
        }
    }

    func disconnect() {
        transport?.disconnect()
        transport = nil
        isConnected = false
        statusText = "Not connected"
        appendLog("Disconnected")
    }
}
