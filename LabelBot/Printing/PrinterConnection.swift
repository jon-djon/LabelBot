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

    /// Wakes the printer, reads its status, then sends the payload — a cold printer
    /// otherwise drops the first job silently. Returns the raw status reply.
    func run(wake: Data, statusRequest: Data, payload: Data) async throws -> Data {
        guard let transport else { throw TransportError.notConnected }
        try transport.send(wake)
        try transport.send(statusRequest)
        let reply = (try? transport.readStatus(maxLength: 32, timeout: 3)) ?? Data()
        try await Task.sleep(for: .milliseconds(200))   // settle time after waking
        try transport.send(payload)
        return reply
    }
}
