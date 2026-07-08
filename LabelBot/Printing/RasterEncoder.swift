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

    /// Wraps a single label's raster lines in a full print job.
    static func job(lines: [[UInt8]], tapeWidthMM: UInt8) -> Data {
        batchJob(pages: [lines], tapeWidthMM: tapeWidthMM, cutBetween: true)
    }

    /// Builds one job that prints several labels ("pages") in order. With
    /// `cutBetween`, auto-cut fires after every label (print → cut → print → cut);
    /// pages other than the last end with the "print" command (0x0C) and the last
    /// ends with "print + feed" (0x1A).
    static func batchJob(pages: [[[UInt8]]], tapeWidthMM: UInt8, cutBetween: Bool) -> Data {
        var data = Data()

        // --- Job header (sent once) ---
        // Invalidate: 100 null bytes flush any half-finished command in the buffer.
        data.append(Data(repeating: 0x00, count: 100))
        data.append(contentsOf: [0x1B, 0x40])              // ESC @  initialize
        data.append(contentsOf: [0x1B, 0x69, 0x61, 0x01])  // ESC i a  raster mode
        data.append(contentsOf: [0x1B, 0x69, 0x21, 0x00])  // ESC i !  status notify off
        // ESC i M  mode: auto-cut on (0x40) when cutting between labels.
        data.append(contentsOf: [0x1B, 0x69, 0x4D, cutBetween ? 0x40 : 0x00])
        // ESC i K  advanced mode: no chain printing (0x08) — feed + cut after the last label.
        // (ESC i A "cut every n labels" is intentionally omitted: the PT-P710BT does not
        // support it, and auto-cut above already cuts each page.)
        data.append(contentsOf: [0x1B, 0x69, 0x4B, 0x08])

        // --- Pages ---
        for (index, lines) in pages.enumerated() {
            // ESC i z  print information: flags 0x84, media type, width, length,
            // 4-byte LE raster-line count, then n9/n10.
            // n9 = starting-page flag: 0 for the first page, 1 for every later page.
            // Sending 0 on every page makes the printer treat each label as a fresh job
            // and stall before the final feed/cut, so it must increment here.
            let n = UInt32(lines.count)
            let startingPage: UInt8 = index == 0 ? 0x00 : 0x01
            data.append(contentsOf: [0x1B, 0x69, 0x7A,
                0x84, 0x00, tapeWidthMM, 0x00,
                UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF),
                UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF),
                startingPage, 0x00])
            data.append(contentsOf: [0x1B, 0x69, 0x64, 0x00, 0x00])  // ESC i d  margin
            data.append(contentsOf: [0x4D, 0x02])                    // M  TIFF/PackBits

            appendRasterLines(lines, to: &data)

            // Last page prints + feeds/cuts (0x1A); earlier pages just print (0x0C).
            data.append(index == pages.count - 1 ? 0x1A : 0x0C)
        }

        return data
    }

    /// Appends raster lines: 0x5A for an all-zero line, else 0x47 + LE16 length + packbits.
    private static func appendRasterLines(_ lines: [[UInt8]], to data: inout Data) {
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

    /// Invalidate (100 null bytes) + initialize (ESC @). Sent on its own to wake a
    /// sleeping printer and clear its command buffer before the real job.
    static var initialize: Data { Data(repeating: 0x00, count: 100) + Data([0x1B, 0x40]) }
}
