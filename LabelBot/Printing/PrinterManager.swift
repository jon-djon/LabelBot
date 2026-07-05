//
//  PrinterManager.swift
//  LabelBot
//
//  Drives the connection lifecycle and printing. Owns the active transport, the
//  batch of labels being edited, and exposes observable state for the UI.
//  Blocking I/O runs off the main actor.
//

import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

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

    // Shared output settings (one physical tape feeds the whole batch).
    var tape: TapeSize = .tape24 { didSet { updatePreview() } }
    var cutBetween = true

    // The batch of labels and the one currently being edited.
    var labels: [LabelSpec] = [LabelSpec()] { didSet { updatePreview() } }
    var selection: LabelSpec.ID? { didSet { updatePreview() } }

    private(set) var preview: NSImage?
    /// Actual printed size of the current preview, in millimeters.
    private(set) var previewHeightMM = 0.0
    private(set) var previewLengthMM = 0.0
    private var transport: PrinterTransport?

    init() {
        selection = labels.first?.id
    }

    // MARK: - Selected label

    var selectedIndex: Int {
        labels.firstIndex { $0.id == selection } ?? 0
    }

    /// Total number of physical labels the batch will print (copies expanded).
    var totalLabels: Int {
        labels.reduce(0) { $0 + max(1, $1.copies) }
    }

    /// The label being edited. Setting it back keeps size selections valid and
    /// refreshes the preview.
    var current: LabelSpec {
        get {
            labels.indices.contains(selectedIndex) ? labels[selectedIndex] : LabelSpec()
        }
        set {
            guard labels.indices.contains(selectedIndex) else { return }
            var value = newValue
            let old = labels[selectedIndex]
            if value.text1.unit != old.text1.unit { value.text1.normalizeForUnit() }
            if value.text2.unit != old.text2.unit { value.text2.normalizeForUnit() }
            labels[selectedIndex] = value
        }
    }

    // MARK: - Queue editing

    func addLabel() {
        var spec = LabelSpec()
        spec.id = UUID()
        labels.append(spec)
        selection = spec.id
    }

    func duplicateSelected() {
        guard labels.indices.contains(selectedIndex) else { return }
        var copy = labels[selectedIndex]
        copy.id = UUID()
        labels.insert(copy, at: selectedIndex + 1)
        selection = copy.id
    }

    func deleteSelected() {
        guard labels.indices.contains(selectedIndex) else { return }
        let idx = selectedIndex
        labels.remove(at: idx)
        if labels.isEmpty { labels = [LabelSpec()] }
        selection = labels[min(idx, labels.count - 1)].id
    }

    func moveLabels(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().map { labels[$0] }
        var reordered = labels
        for index in offsets.sorted(by: >) { reordered.remove(at: index) }
        let adjusted = destination - offsets.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: max(0, min(adjusted, reordered.count)))
        labels = reordered
    }

    /// Creates one label per size in a comma/newline-separated list, using the
    /// currently-selected label as the template.
    func generateLabels(from text: String) {
        let tokens = text
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return }
        let template = current
        var new: [LabelSpec] = []
        for token in tokens {
            var spec = template
            spec.id = UUID()
            spec.text1.sizeMode = .text
            spec.text1.sizeText = token
            spec.copies = 1
            new.append(spec)
        }
        labels.append(contentsOf: new)
        selection = new.first?.id
        appendLog("Added \(new.count) label\(new.count == 1 ? "" : "s") from list")
    }

    // MARK: - Rendering

    func thumbnail(for spec: LabelSpec) -> NSImage {
        LabelRenderer.render(spec, tape: tape).preview
    }

    func updatePreview() {
        let rendered = LabelRenderer.render(current, tape: tape)
        preview = rendered.preview
        previewHeightMM = Double(tape.widthMM)
        previewLengthMM = Double(rendered.lengthDots) / LabelRenderer.dotsPerMM
    }

    // MARK: - Save / load

    func saveBatch() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "labels.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let batch = LabelBatch(tapeWidthMM: tape.widthMM, cutBetween: cutBetween, labels: labels)
        do {
            let data = try JSONEncoder().encode(batch)
            try data.write(to: url)
            appendLog("Saved \(labels.count) labels to \(url.lastPathComponent)")
        } catch {
            appendLog("Save error: \(error.localizedDescription)")
        }
    }

    func openBatch() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let batch = try JSONDecoder().decode(LabelBatch.self, from: Data(contentsOf: url))
            if let t = TapeSize.all.first(where: { $0.widthMM == batch.tapeWidthMM }) { tape = t }
            cutBetween = batch.cutBetween
            labels = batch.labels.isEmpty ? [LabelSpec()] : batch.labels
            selection = labels.first?.id
            appendLog("Opened \(labels.count) labels from \(url.lastPathComponent)")
        } catch {
            appendLog("Open error: \(error.localizedDescription)")
        }
    }

    // MARK: - Logging

    private func appendLog(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.append("[\(stamp)] \(line)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    // MARK: - Connection

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

    func disconnect() {
        transport?.disconnect()
        transport = nil
        isConnected = false
        statusText = "Not connected"
        appendLog("Disconnected")
    }

    // MARK: - Printing

    /// Prints the whole queue (respecting each label's copies), one job.
    func printAll() async {
        await printSpecs(labels.flatMap { Array(repeating: $0, count: max(1, $0.copies)) })
    }

    /// Prints just the selected label (respecting its copies).
    func printSelected() async {
        let spec = current
        await printSpecs(Array(repeating: spec, count: max(1, spec.copies)))
    }

    private func printSpecs(_ specs: [LabelSpec]) async {
        guard !isBusy else { return }
        guard let transport else {
            statusText = "Not connected"
            appendLog("Print skipped: not connected")
            return
        }
        isBusy = true
        defer { isBusy = false }

        let tape = self.tape
        let pages = specs
            .map { LabelRenderer.render($0, tape: tape).rasterLines }
            .filter { !$0.isEmpty }
        guard !pages.isEmpty else {
            appendLog("Nothing to print")
            return
        }
        let n = pages.count
        let plural = n == 1 ? "" : "s"
        let wake = RasterEncoder.initialize
        let statusRequest = RasterEncoder.statusRequest
        let payload = RasterEncoder.batchJob(pages: pages, tapeWidthMM: tape.widthMM, cutBetween: cutBetween)
        statusText = "Printing \(n) label\(plural)…"
        do {
            // Wake the printer and let it reach the ready state before the job.
            // A cold (just-connected) printer otherwise drops the first job silently.
            let status = try await Task.detached { () -> Data in
                try transport.send(wake)
                try transport.send(statusRequest)
                let reply = (try? transport.readStatus(maxLength: 32, timeout: 3)) ?? Data()
                try await Task.sleep(for: .milliseconds(200))   // settle time after waking
                try transport.send(payload)
                return reply
            }.value
            if let issue = Self.statusError(status) {
                appendLog("Printer reported: \(issue)")
            }
            appendLog("Printed \(n) label\(plural) — \(tape.label) (\(payload.count) B)")
            statusText = "Printed \(n) label\(plural)"
        } catch {
            appendLog("Print error: \(error.localizedDescription)")
            statusText = "Print failed"
        }
    }

    /// Decodes the error bytes (offsets 8–9) of a 32-byte status reply, if any.
    private static func statusError(_ status: Data) -> String? {
        guard status.count >= 10 else { return nil }
        let e1 = status[status.startIndex + 8]
        let e2 = status[status.startIndex + 9]
        guard e1 != 0 || e2 != 0 else { return nil }
        var reasons: [String] = []
        if e1 & 0x01 != 0 { reasons.append("no media") }
        if e1 & 0x04 != 0 { reasons.append("cut jam") }
        if e1 & 0x08 != 0 { reasons.append("weak batteries") }
        if e1 & 0x40 != 0 { reasons.append("high voltage adapter") }
        if e2 & 0x01 != 0 { reasons.append("wrong media") }
        if e2 & 0x10 != 0 { reasons.append("cover open") }
        if e2 & 0x20 != 0 { reasons.append("overheated") }
        if reasons.isEmpty { reasons.append(String(format: "error 0x%02X 0x%02X", e1, e2)) }
        return reasons.joined(separator: ", ")
    }
}
