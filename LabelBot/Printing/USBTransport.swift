//
//  USBTransport.swift
//  LabelBot
//
//  Direct USB transport for the PT-P710BT via IOUSBHost.
//
//  RISK (flagged in plan.md): macOS may bind its USB printing class driver to the
//  device, which can block raw access ("exclusive access" / open errors). This is
//  the Phase 0 unknown to confirm on hardware. `scan()` works regardless and is how
//  we verify the exact product id and endpoint layout of the real unit.
//

import Foundation
import IOKit
import IOKit.usb
import IOUSBHost

nonisolated final class USBTransport: PrinterTransport, @unchecked Sendable {

    /// Brother Industries USB vendor id.
    static let brotherVendorID = 0x04F9

    private var interface: IOUSBHostInterface?
    private var outPipe: IOUSBHostPipe?
    private var inPipe: IOUSBHostPipe?
    private var connectedName = "Brother USB"

    var displayName: String { connectedName }

    // MARK: - Enumeration

    /// Lists Brother USB devices with their vendor/product ids and product names.
    /// Used to confirm the PT-P710BT's product id and presence before connecting.
    ///
    /// Note: on the modern IOUSBHost stack a top-level `idVendor` key in the matching
    /// dictionary matches nothing, so we enumerate the device class and filter in code.
    static func scan() -> [String] {
        var results: [String] = []
        for service in matchingServices("IOUSBHostDevice") {
            defer { IOObjectRelease(service) }
            guard intProperty(service, "idVendor") == brotherVendorID else { continue }
            let pid = intProperty(service, "idProduct")
            let name = stringProperty(service, "USB Product Name") ?? "Brother device"
            results.append(String(format: "%@ — VID 0x%04X PID 0x%04X", name, brotherVendorID, pid))
        }
        return results.isEmpty ? ["No Brother USB devices found (VID 0x04F9)"] : results
    }

    /// All services of the given IOKit class. Caller must `IOObjectRelease` each.
    private static func matchingServices(_ className: String) -> [io_service_t] {
        guard let matching = IOServiceMatching(className) else { return [] }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        var services: [io_service_t] = []
        var service = IOIteratorNext(iter)
        while service != 0 {
            services.append(service)
            service = IOIteratorNext(iter)
        }
        return services
    }

    private static func intProperty(_ service: io_service_t, _ key: String) -> Int {
        (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.intValue ?? 0
    }

    private static func stringProperty(_ service: io_service_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    /// Returns the first pipe that opens among the candidate endpoint addresses.
    private static func firstPipe(_ iface: IOUSBHostInterface, addresses: [Int]) -> IOUSBHostPipe? {
        for address in addresses {
            if let pipe = try? iface.copyPipe(withAddress: address) { return pipe }
        }
        return nil
    }

    // MARK: - PrinterTransport

    func connect() throws {
        // Enumerate USB interfaces and pick the Brother printer-class one.
        let interfaces = Self.matchingServices("IOUSBHostInterface")
        defer { interfaces.forEach { IOObjectRelease($0) } }

        let brotherInterfaces = interfaces.filter { Self.intProperty($0, "idVendor") == Self.brotherVendorID }
        // Prefer the printer-class interface (class 7); fall back to any Brother interface.
        guard let service = brotherInterfaces.first(where: { Self.intProperty($0, "bInterfaceClass") == 7 })
            ?? brotherInterfaces.first else {
            throw TransportError.deviceNotFound("no Brother USB interface (VID 0x04F9) — is it plugged in?")
        }
        connectedName = Self.stringProperty(service, "USB Product Name") ?? "Brother USB"

        let iface: IOUSBHostInterface
        do {
            iface = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
        } catch {
            throw TransportError.connectionFailed(
                "could not open USB interface (\(error.localizedDescription)) — another app (e.g. Chrome/WebUSB) or a driver may be holding it")
        }
        self.interface = iface

        // Discover the bulk pipes rather than assuming fixed endpoint addresses.
        self.outPipe = Self.firstPipe(iface, addresses: [0x02, 0x01, 0x03, 0x04])
        self.inPipe = Self.firstPipe(iface, addresses: [0x81, 0x82, 0x83, 0x84])
        guard outPipe != nil else {
            throw TransportError.connectionFailed("opened the interface but found no bulk OUT pipe")
        }
    }

    /// Bytes per bulk-OUT request. A whole multi-label batch cannot go in one request:
    /// the transfer only completes once the printer has accepted every byte, but the
    /// printer NAKs input while it physically prints and cuts each label, so a big job
    /// blows past a single timeout mid-print (kIOReturnTimeout) and the trailing bytes —
    /// including the final cut command — never arrive. Sending in chunks lets each
    /// transfer complete as buffer space frees up. 2 KB = 4 × the 512-byte bulk packet;
    /// small chunks keep any one request from spanning more than one label's print.
    private static let chunkSize = 2048

    /// Seconds one chunk may wait for the printer to accept it. The printer only
    /// takes more data once earlier labels have printed and cut, which at 360 dpi
    /// (half feed speed) runs well past 15 s for a pair of long labels. Hitting this
    /// aborts the transfer and leaves the printer waiting mid-label, so it must only
    /// fire when the printer has genuinely stopped.
    private static let chunkTimeout: TimeInterval = 90

    func send(_ data: Data, progress: (Int) -> Void, received: @escaping @Sendable (Data) -> Void) throws {
        guard let outPipe else { throw TransportError.notConnected }
        // Keep the bulk IN pipe drained while sending: any status reply the printer
        // pushes mid-job must be read, or it stops accepting data part-way through.
        startDraining(received)
        defer { stopDraining() }
        var offset = 0
        while offset < data.count {
            let end = min(offset + Self.chunkSize, data.count)
            let chunk = NSMutableData(data: data.subdata(in: offset..<end))
            let semaphore = DispatchSemaphore(value: 0)
            var result: IOReturn = kIOReturnSuccess

            // Completions fire on the interface's internal queue; block until done.
            // Timeout is per chunk, so total transfer time scales with the batch.
            do {
                try outPipe.enqueueIORequest(with: chunk, completionTimeout: Self.chunkTimeout) { status, _ in
                    result = status
                    semaphore.signal()
                }
            } catch {
                throw TransportError.writeFailed(error.localizedDescription)
            }
            semaphore.wait()
            guard result == kIOReturnSuccess else {
                let reason = result == kIOReturnTimeout
                    ? "printer accepted no data for \(Int(Self.chunkTimeout)) s (kIOReturnTimeout)"
                    : String(format: "bulk OUT returned 0x%08X", UInt32(bitPattern: result))
                throw TransportError.writeFailed("\(reason) at offset \(offset)")
            }
            offset = end
            progress(offset)
        }
    }

    /// Continuously reads bulk IN data, handing each read to `received`, until
    /// `stopDraining()`. Each completion re-enqueues the next read; the abort in
    /// `stopDraining()` ends the loop.
    private func startDraining(_ received: @escaping @Sendable (Data) -> Void) {
        guard let inPipe else { return }
        func enqueueRead() {
            // Only read in the completion, after the transfer has finished writing it.
            guard let readBuffer = NSMutableData(length: 64) else { return }
            nonisolated(unsafe) let buffer = readBuffer
            try? inPipe.enqueueIORequest(with: buffer, completionTimeout: 0) { status, count in
                guard status == kIOReturnSuccess else { return }
                if count > 0 { received(Data(Data(referencing: buffer).prefix(count))) }
                enqueueRead()
            }
        }
        enqueueRead()
    }

    private func stopDraining() {
        try? inPipe?.__abort(with: .synchronous)
    }

    func readStatus(maxLength: Int, timeout: TimeInterval) throws -> Data {
        guard let inPipe, let buffer = NSMutableData(length: maxLength) else { return Data() }
        let semaphore = DispatchSemaphore(value: 0)
        var result: IOReturn = kIOReturnSuccess
        var transferred = 0
        do {
            try inPipe.enqueueIORequest(with: buffer, completionTimeout: timeout) { status, count in
                result = status
                transferred = count
                semaphore.signal()
            }
        } catch {
            return Data() // status is best-effort during the spike
        }
        _ = semaphore.wait(timeout: .now() + timeout + 1)
        guard result == kIOReturnSuccess, transferred > 0 else { return Data() }
        return Data(Data(referencing: buffer).prefix(transferred))
    }

    func disconnect() {
        outPipe = nil
        inPipe = nil
        interface = nil
    }
}
