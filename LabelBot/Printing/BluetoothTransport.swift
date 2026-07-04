//
//  BluetoothTransport.swift
//  LabelBot
//
//  Bluetooth Classic (SPP / RFCOMM) transport for the PT-P710BT.
//  The printer must already be paired in System Settings > Bluetooth.
//
//  Note: the PT-P710BT uses Bluetooth *Classic* Serial Port Profile, so this uses
//  IOBluetooth (not CoreBluetooth, which is BLE only).
//

import Foundation
import IOBluetooth

nonisolated final class BluetoothTransport: NSObject, PrinterTransport, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {

    /// Substring matched (case-insensitively) against paired device names.
    private let nameMatch: String

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?

    /// Guards `incoming` and lets `readStatus` wait for delegate callbacks.
    private let incomingLock = NSCondition()
    private var incoming = Data()

    init(nameMatch: String = "PT-P710BT") {
        self.nameMatch = nameMatch
        super.init()
    }

    var displayName: String { device?.name ?? nameMatch }

    func connect() throws {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        guard let dev = paired.first(where: {
            ($0.name ?? "").localizedCaseInsensitiveContains(nameMatch)
        }) else {
            throw TransportError.deviceNotFound(
                "no paired device matching \"\(nameMatch)\" — pair it in System Settings first")
        }
        self.device = dev

        // Look up the RFCOMM channel advertised for Serial Port Profile.
        // 0x1101 = Serial Port Profile service class UUID.
        let sppUUID = IOBluetoothSDPUUID(uuid16: 0x1101)
        guard let record = dev.getServiceRecord(for: sppUUID) else {
            throw TransportError.connectionFailed("device does not advertise a serial port service")
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            throw TransportError.connectionFailed("could not read RFCOMM channel ID")
        }

        var ch: IOBluetoothRFCOMMChannel?
        let result = dev.openRFCOMMChannelSync(&ch, withChannelID: channelID, delegate: self)
        guard result == kIOReturnSuccess, let opened = ch else {
            throw TransportError.connectionFailed("openRFCOMMChannel returned \(result)")
        }
        self.channel = opened
    }

    func send(_ data: Data) throws {
        guard let channel else { throw TransportError.notConnected }
        let mtu = Int(channel.getMTU())
        var bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let chunk = min(mtu, bytes.count - offset)
            let result = bytes.withUnsafeMutableBytes { raw -> IOReturn in
                let base = raw.baseAddress!.advanced(by: offset)
                return channel.writeSync(base, length: UInt16(chunk))
            }
            guard result == kIOReturnSuccess else {
                throw TransportError.writeFailed("writeSync returned \(result) at offset \(offset)")
            }
            offset += chunk
        }
    }

    func readStatus(maxLength: Int, timeout: TimeInterval) throws -> Data {
        incomingLock.lock()
        defer { incomingLock.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while incoming.count < maxLength, Date() < deadline {
            _ = incomingLock.wait(until: deadline)
        }
        let out = incoming
        incoming.removeAll()
        return out
    }

    func disconnect() {
        channel?.close()
        channel = nil
        device?.closeConnection()
        device = nil
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                           data dataPointer: UnsafeMutableRawPointer!,
                           length dataLength: Int) {
        incomingLock.lock()
        incoming.append(Data(bytes: dataPointer, count: dataLength))
        incomingLock.signal()
        incomingLock.unlock()
    }
}
