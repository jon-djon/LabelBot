//
//  PrinterConnection.swift
//  LabelBot
//
//  Owns the active transport and serializes all blocking wire I/O off the main
//  actor. `PrinterManager` (the @MainActor UI model) drives this and never touches
//  the transport directly, so connect / print / disconnect can never interleave.
//

import Foundation

actor PrinterConnection {
    private var transport: PrinterTransport?

    var isConnected: Bool { transport != nil }

    /// Opens the given transport and adopts it. Returns the device's display name.
    func connect(_ transport: PrinterTransport) throws -> String {
        try transport.connect()
        self.transport = transport
        return transport.displayName
    }

    func disconnect() {
        transport?.disconnect()
        transport = nil
    }

    /// Wakes the printer and reads its 32-byte status reply (empty if none arrives).
    /// A cold printer otherwise drops the first job silently, so this precedes `send`.
    func wakeAndReadStatus(wake: Data, statusRequest: Data,
                           log: @escaping @Sendable (String) -> Void) async throws -> Data {
        guard let transport else { throw TransportError.notConnected }
        log("Waking printer (\(wake.count) B)")
        try transport.send(wake)
        log("Requesting status")
        try transport.send(statusRequest)
        let reply = (try? transport.readStatus(maxLength: 32, timeout: 3)) ?? Data()
        log(reply.isEmpty ? "No status reply within 3 s"
                          : "Status: \(PrinterStatus.describe(reply))")
        try await Task.sleep(for: .milliseconds(200))   // settle time after waking
        return reply
    }

    /// Sends a print job. `pageEnds` (byte offsets past each label, from
    /// `RasterEncoder`) and `log` drive the progress lines shown in the log window.
    func send(payload: Data, pageEnds: [Int], log: @escaping @Sendable (String) -> Void) throws {
        guard let transport else { throw TransportError.notConnected }
        let total = payload.count
        let labelCount = pageEnds.count
        log("Sending job: \(labelCount) label\(labelCount == 1 ? "" : "s"), \(total) B")
        let start = ContinuousClock.now
        var lastProgress = start
        var labelsSent = 0
        var lastPercentLogged = 0

        do {
            try transport.send(payload, progress: { sent in
                let now = ContinuousClock.now
                // The printer NAKs while it prints/cuts, so a long gap here is it
                // working through earlier labels — or, if it never ends, the stall.
                let gap = now - lastProgress
                if gap > .seconds(2) {
                    log("Printer held off data for \(Self.seconds(gap)) (printing/cutting)")
                }
                lastProgress = now
                while labelsSent < labelCount, sent >= pageEnds[labelsSent] {
                    labelsSent += 1
                    log("Label \(labelsSent) of \(labelCount) sent to printer")
                }
                let percent = total > 0 ? sent * 100 / total : 100
                if percent >= lastPercentLogged + 25, percent < 100 {
                    lastPercentLogged = percent - percent % 25
                    log("Sent \(sent) / \(total) B (\(lastPercentLogged)%)")
                }
            }, received: { data in
                log("Printer sent \(data.count) B mid-job: \(PrinterStatus.describe(data))")
            })
        } catch {
            log("Send stopped after \(Self.seconds(ContinuousClock.now - start)), \(labelsSent) of \(labelCount) labels sent")
            throw error
        }
        log("Job sent in \(Self.seconds(ContinuousClock.now - start))")
    }

    private static func seconds(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow, fractionalPart: .show(length: 1)))
    }
}

/// Decodes the printer's 32-byte status reply for logging.
nonisolated enum PrinterStatus {
    /// Error reasons from bytes 8–9, or nil if there are none (or the reply is short).
    static func errors(_ status: Data) -> String? {
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

    /// Width of the loaded tape in mm (byte 10), or nil for a short reply. 0 means
    /// no tape is loaded.
    static func tapeWidthMM(_ status: Data) -> UInt8? {
        status.count >= 32 ? status[status.startIndex + 10] : nil
    }

    /// One-line summary: status type, phase, loaded tape width and any errors.
    static func describe(_ status: Data) -> String {
        guard status.count >= 32 else {
            return "\(status.count) B: " + status.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
        let byte = { (i: Int) in status[status.startIndex + i] }
        let type = switch byte(18) {
        case 0x00: "reply"
        case 0x01: "printing completed"
        case 0x02: "error"
        case 0x04: "turned off"
        case 0x05: "notification"
        case 0x06: "phase change"
        default: String(format: "type 0x%02X", byte(18))
        }
        let phase = byte(19) == 0x01 ? "printing" : "receiving"
        return "\(type), \(phase), tape \(byte(10)) mm, \(errors(status) ?? "no errors")"
    }
}
