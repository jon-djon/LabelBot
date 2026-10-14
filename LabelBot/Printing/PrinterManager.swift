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

    var selectedTransport: TransportKind = .usb
    var statusText = "Not connected"
    var isConnected = false
    var isBusy = false
    private(set) var log: [String] = []
    /// Width of the cassette in the printer, from the last status reply (0 = none
    /// loaded); nil when not connected or never read. Updated on connect and before
    /// each print, so a cassette swapped while idle shows up at the next print.
    private(set) var loadedTapeMM: UInt8?

    /// The loaded tape, when it's a supported width that differs from the setting.
    var mismatchedLoadedTape: TapeSize? {
        guard isConnected, let loadedTapeMM, loadedTapeMM != tape.widthMM else { return nil }
        return TapeSize.all.first { $0.widthMM == loadedTapeMM }
    }

    // Shared output settings (one physical tape feeds the whole batch).
    var tape: TapeSize = .tape24 { didSet { updatePreview() } }
    var cutBetween = true
    /// Print at 360 dpi along the length (smoother edges, ~2× data/time).
    var highRes = true { didSet { updatePreview() } }

    // The batch of labels and the one currently being edited.
    var labels: [LabelSpec] = [LabelSpec()] { didSet { updatePreview() } }
    var selection: LabelSpec.ID? { didSet { updatePreview() } }

    private(set) var preview: NSImage?
    /// Actual printed size of the current preview, in millimeters.
    private(set) var previewHeightMM = 0.0
    private(set) var previewLengthMM = 0.0
    /// Owns the transport and runs all blocking I/O off the main actor.
    private let connection = PrinterConnection()

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
            if spec.category.isFastener {
                spec.text1.sizeMode = .text
                spec.text1.sizeText = token
            } else {
                spec.text1.customText = token
            }
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
        let rendered = LabelRenderer.render(current, tape: tape, highRes: highRes)
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

    func connect() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let newTransport: PrinterTransport =
            selectedTransport == .bluetooth ? BluetoothTransport() : USBTransport()
        do {
            let name = try await connection.connect(newTransport)
            isConnected = true
            statusText = "Connected to \(name)"
            appendLog("Connected via \(selectedTransport.rawValue): \(name)")
            if let status = try? await connection.wakeAndReadStatus(
                wake: RasterEncoder.initialize, statusRequest: RasterEncoder.statusRequest, log: logger) {
                _ = matchLoadedTape(status, askBeforeSwitching: false)
            }
        } catch {
            isConnected = false
            statusText = "Connect failed"
            appendLog("Connect error: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        // Reflect the change immediately; the actual teardown runs off-main and, being
        // serialized on the connection actor, waits for any in-flight job to finish.
        isConnected = false
        loadedTapeMM = nil
        statusText = "Not connected"
        appendLog("Disconnected")
        Task { await connection.disconnect() }
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
        guard isConnected else {
            statusText = "Not connected"
            appendLog("Print skipped: not connected")
            return
        }
        isBusy = true
        defer { isBusy = false }

        // Check the loaded tape before rendering: a job whose width doesn't match the
        // cassette is rejected by the printer (red light), so adopt the real width.
        let log = logger
        let status: Data
        do {
            status = try await connection.wakeAndReadStatus(
                wake: RasterEncoder.initialize, statusRequest: RasterEncoder.statusRequest, log: log)
        } catch {
            await Self.flushMainQueue()
            appendLog("Print error: \(error.localizedDescription)")
            statusText = "Print failed"
            return
        }
        await Self.flushMainQueue()
        switch matchLoadedTape(status, askBeforeSwitching: true) {
        case .ok:
            break
        case .cancelled:
            statusText = "Print cancelled"
            return
        case .unprintable:
            statusText = "Print stopped — check tape"
            return
        }

        let tape = self.tape
        let highRes = self.highRes
        appendLog("Print requested: \(specs.count) label\(specs.count == 1 ? "" : "s") on \(tape.label), "
                  + "high-res \(highRes ? "on" : "off"), cut between \(cutBetween ? "on" : "off")")
        var pages: [[[UInt8]]] = []
        for (index, spec) in specs.enumerated() {
            let rendered = LabelRenderer.render(spec, tape: tape, highRes: highRes)
            guard !rendered.rasterLines.isEmpty else {
                appendLog("Skipping label \(index + 1) (\(spec.title)): nothing to print")
                continue
            }
            let lengthMM = Double(rendered.lengthDots) / LabelRenderer.dotsPerMM
            appendLog("Rendered label \(pages.count + 1): \(spec.title) — "
                      + "\(lengthMM.formatted(.number.precision(.fractionLength(1)))) mm, \(rendered.rasterLines.count) lines")
            pages.append(rendered.rasterLines)
        }
        guard !pages.isEmpty else {
            appendLog("Nothing to print")
            return
        }
        let n = pages.count
        let plural = n == 1 ? "" : "s"
        let (payload, pageEnds) = RasterEncoder.batchJobWithPageEnds(
            pages: pages, tapeWidthMM: tape.widthMM, cutBetween: cutBetween, highRes: highRes)
        statusText = "Printing \(n) label\(plural)…"
        do {
            try await connection.send(payload: payload, pageEnds: pageEnds, log: log)
            await Self.flushMainQueue()
            appendLog("Printed \(n) label\(plural) — \(tape.label) (\(payload.count) B)")
            statusText = "Printed \(n) label\(plural)"
        } catch {
            await Self.flushMainQueue()
            appendLog("Print error: \(error.localizedDescription)")
            statusText = "Print failed"
        }
    }

    /// Progress lines come from the connection actor; this hops them to the main
    /// queue (FIFO, so they stay in order) and appends them to the log.
    private var logger: @Sendable (String) -> Void {
        { [weak self] line in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.appendLog(line) } }
        }
    }

    enum TapeCheck { case ok, cancelled, unprintable }

    /// Checks a status reply against the tape setting. On a width mismatch it switches
    /// to the loaded tape — silently on connect, or after asking when
    /// `askBeforeSwitching` (before a print). Returns `.unprintable` (after logging why)
    /// for a printer error, no tape, or a width this app can't print. With no reply the
    /// current setting is kept.
    private func matchLoadedTape(_ status: Data, askBeforeSwitching: Bool) -> TapeCheck {
        if let width = PrinterStatus.tapeWidthMM(status) { loadedTapeMM = width }
        if let issue = PrinterStatus.errors(status) {
            appendLog("Printer reported: \(issue)")
            return .unprintable
        }
        guard let width = PrinterStatus.tapeWidthMM(status) else {
            appendLog("Couldn't read the loaded tape width — using the \(tape.label) setting")
            return .ok
        }
        guard width != 0 else {
            appendLog("No tape cassette loaded")
            return .unprintable
        }
        guard let loaded = TapeSize.all.first(where: { $0.widthMM == width }) else {
            appendLog("Loaded tape is \(width) mm, which LabelBot can't print")
            return .unprintable
        }
        guard loaded != tape else { return .ok }

        if askBeforeSwitching {
            let alert = NSAlert()
            alert.messageText = "Tape size doesn't match"
            alert.informativeText = "The printer has \(loaded.label) tape loaded, but the labels are set up "
                + "for \(tape.label). Switch to \(loaded.label) and print, or cancel to change the tape?"
            alert.addButton(withTitle: "Switch to \(loaded.label) and Print")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                appendLog("Print cancelled: loaded tape is \(loaded.label), labels set for \(tape.label)")
                return .cancelled
            }
        }
        appendLog("Loaded tape is \(loaded.label) — switched from \(tape.label)")
        tape = loaded
        return .ok
    }

    /// Waits for already-queued main-queue log lines so the summary lands after them.
    private static func flushMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
