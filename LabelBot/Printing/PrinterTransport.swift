//
//  PrinterTransport.swift
//  LabelBot
//
//  A transport-agnostic byte pipe to the label printer. USB and Bluetooth both
//  conform, so everything above this layer is unaware of how bytes get there.
//

import Foundation

/// A byte pipe to the label printer.
///
/// Implementations run their blocking I/O off the main thread, so they are marked
/// `nonisolated` and manage their own internal synchronization.
nonisolated protocol PrinterTransport: AnyObject, Sendable {
    /// Human-readable name of the connected device (for the UI).
    var displayName: String { get }

    /// Opens the connection. Throws `TransportError` on failure.
    func connect() throws

    /// Sends the full payload, chunking as needed for the transport.
    func send(_ data: Data) throws

    /// Reads up to `maxLength` bytes of status reply, waiting up to `timeout` seconds.
    /// Returns whatever arrived (possibly empty) rather than throwing on timeout.
    func readStatus(maxLength: Int, timeout: TimeInterval) throws -> Data

    /// Closes the connection. Safe to call more than once.
    func disconnect()
}

enum TransportError: LocalizedError {
    case deviceNotFound(String)
    case connectionFailed(String)
    case writeFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let s): return "Printer not found: \(s)"
        case .connectionFailed(let s): return "Connection failed: \(s)"
        case .writeFailed(let s): return "Write failed: \(s)"
        case .notConnected: return "Printer is not connected."
        }
    }
}
