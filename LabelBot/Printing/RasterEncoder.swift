//
//  RasterEncoder.swift
//  LabelBot
//
//  Builds Brother P-touch raster command streams.
//
//  Phase 0: only produces a fixed test pattern (a solid bar) to prove that a
//  transport can get bytes onto tape. Real text rendering arrives in Phase 1.
//
//  The PT-P710BT expects TIFF/PackBits-compressed raster data (compression mode
//  0x4D 0x02). Each printed line is `0x47 <len-LE16> <packbits>`; an all-zero line
//  is the single byte `0x5A`. Print head = 128 dots = 16 bytes per line.
//
//  Command reference (PT-E550W / P750W / P710BT):
//  https://download.brother.com/welcome/docp100064/cv_pte550wp750wp710bt_eng_raster_102.pdf
//  Sequence cross-checked against robby-cornelissen/pt-p710bt-label-maker.
//

import Foundation

nonisolated enum RasterEncoder {
    /// Bytes per raster line for the PT-P710BT print head (128 dots / 8).
    static let bytesPerLine = 16

    /// Total pins in the print head.
    static let headPins = 128

    /// Sets a single pin (0 = first byte's MSB) in a raster line buffer.
    static func setPin(_ line: inout [UInt8], _ pin: Int) {
        guard pin >= 0, pin < headPins else { return }
        line[pin >> 3] |= 0x80 >> (pin & 7)
    }

    /// Builds a test label: a bar running the length of the label, centered on the head.
    ///
    /// - Parameters:
    ///   - tapeWidthMM: physical tape width; sent in the print-info command. Must match
    ///     the loaded tape (the printer validates it). The PT-P710BT reports its loaded
    ///     width in the status reply (byte 10).
    ///   - lineCount: number of raster lines ≈ label length (~180 lines per inch).
    static func testPattern(tapeWidthMM: UInt8 = 24, lineCount: Int = 160) -> Data {
        // One raster line with the middle 64 dots set, so the bar shows on any tape.
        var line = [UInt8](repeating: 0x00, count: bytesPerLine)
        for i in 4..<12 { line[i] = 0xFF }
        let lines = [[UInt8]](repeating: line, count: lineCount)
        return job(lines: lines, tapeWidthMM: tapeWidthMM)
    }

    /// Wraps raster lines (each `bytesPerLine` long) in the full print-job command stream.
    static func job(lines: [[UInt8]], tapeWidthMM: UInt8) -> Data {
        var data = Data()

        // 1. Invalidate: 100 null bytes flush any half-finished command in the buffer.
        data.append(Data(repeating: 0x00, count: 100))

        // 2. Initialize (ESC @).
        data.append(contentsOf: [0x1B, 0x40])

        // 3. Enter raster mode (ESC i a, 0x01).
        data.append(contentsOf: [0x1B, 0x69, 0x61, 0x01])

        // 4. Turn off automatic status notifications (ESC i !, 0x00) so our explicit
        //    status request gets the real reply instead of phase-change spam.
        data.append(contentsOf: [0x1B, 0x69, 0x21, 0x00])

        // 5. Print information (ESC i z): flags 0x84, media type 0x00, width, length 0x00,
        //    4-byte little-endian raster-line count, then n9/n10.
        let n = UInt32(lines.count)
        data.append(contentsOf: [0x1B, 0x69, 0x7A,
            0x84,                       // valid flags (recover + length)
            0x00,                       // media type
            tapeWidthMM,                // media width (mm) — must match loaded tape
            0x00,                       // media length
            UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF),
            UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF),
            0x00,                       // n9
            0x00])                      // n10

        // 6. Mode settings (ESC i M): auto-cut on (0x40).
        data.append(contentsOf: [0x1B, 0x69, 0x4D, 0x40])

        // 7. Advanced mode (ESC i K): no chain printing (0x08).
        data.append(contentsOf: [0x1B, 0x69, 0x4B, 0x08])

        // 8. Feed / margin amount (ESC i d): zero.
        data.append(contentsOf: [0x1B, 0x69, 0x64, 0x00, 0x00])

        // 9. Compression mode (M): 0x02 = TIFF / PackBits.
        data.append(contentsOf: [0x4D, 0x02])

        // 10. Raster lines: 0x5A for an all-zero line, else 0x47 + LE16 length + packbits.
        for var raster in lines {
            if raster.count != bytesPerLine {
                raster = normalize(raster)
            }
            if raster.allSatisfy({ $0 == 0 }) {
                data.append(0x5A)
            } else {
                let packed = packBits(raster)
                data.append(0x47)
                data.append(UInt8(packed.count & 0xFF))
                data.append(UInt8((packed.count >> 8) & 0xFF))
                data.append(contentsOf: packed)
            }
        }

        // 11. Print and feed (Ctrl-Z).
        data.append(0x1A)

        return data
    }

    /// Pads or trims a line to exactly `bytesPerLine`.
    private static func normalize(_ line: [UInt8]) -> [UInt8] {
        if line.count == bytesPerLine { return line }
        if line.count > bytesPerLine { return Array(line.prefix(bytesPerLine)) }
        return line + [UInt8](repeating: 0, count: bytesPerLine - line.count)
    }

    /// TIFF PackBits run-length encoding.
    static func packBits(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var idx = 0
        let count = data.count
        while idx < count {
            // Measure a run of the same byte (max 128).
            var run = 1
            while idx + run < count, run < 128, data[idx + run] == data[idx] { run += 1 }
            if run > 1 {
                out.append(UInt8(bitPattern: Int8(-(run - 1)))) // 257 - run
                out.append(data[idx])
                idx += run
            } else {
                // Gather a literal run until the next repeat (max 128).
                var literal: [UInt8] = [data[idx]]
                idx += 1
                while idx < count, literal.count < 128 {
                    if idx + 1 < count, data[idx] == data[idx + 1] { break }
                    literal.append(data[idx])
                    idx += 1
                }
                out.append(UInt8(literal.count - 1))
                out.append(contentsOf: literal)
            }
        }
        return out
    }

    /// Status-request command (ESC i S) — asks for a 32-byte status reply.
    static var statusRequest: Data { Data([0x1B, 0x69, 0x53]) }
}
