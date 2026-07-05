//
//  LabelBotTests.swift
//  LabelBotTests
//
//  Created by Jon on 7/4/26.
//

import Testing
@testable import LabelBot

struct LabelBotTests {

    /// A batch job prints each page and cuts between them: pages before the last
    /// end with the "print" command (0x0C), the last ends with "print + feed" (0x1A).
    @Test func batchJobCutsBetweenPages() async throws {
        let page: [[UInt8]] = [[UInt8](repeating: 0xFF, count: RasterEncoder.bytesPerLine)]
        let data = RasterEncoder.batchJob(pages: [page, page, page], tapeWidthMM: 24, cutBetween: true)
        let bytes = [UInt8](data)

        // Exactly two "print" terminators and one final "print + feed".
        #expect(bytes.filter { $0 == 0x0C }.count == 2)
        #expect(bytes.last == 0x1A)

        // Auto-cut on and "cut every 1 label" present.
        #expect(containsSequence(bytes, [0x1B, 0x69, 0x4D, 0x40]))   // ESC i M 0x40
        #expect(containsSequence(bytes, [0x1B, 0x69, 0x41, 0x01]))   // ESC i A 0x01

        // One print-info (ESC i z) per page.
        #expect(countSequence(bytes, [0x1B, 0x69, 0x7A]) == 3)
    }

    @Test func singleJobEndsWithFeed() async throws {
        let page: [[UInt8]] = [[UInt8](repeating: 0xFF, count: RasterEncoder.bytesPerLine)]
        let data = RasterEncoder.job(lines: page[0].isEmpty ? [] : page, tapeWidthMM: 24)
        let bytes = [UInt8](data)
        #expect(bytes.last == 0x1A)
        #expect(!bytes.contains(0x0C))   // no inter-page terminator for a single label
    }

    private func containsSequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        countSequence(haystack, needle) > 0
    }

    private func countSequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Int {
        guard !needle.isEmpty, haystack.count >= needle.count else { return 0 }
        var count = 0
        for i in 0...(haystack.count - needle.count) where Array(haystack[i..<i+needle.count]) == needle {
            count += 1
        }
        return count
    }

}
