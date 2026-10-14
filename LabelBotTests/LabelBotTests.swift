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
    /// A batch job prints each page and cuts between them: pages before the last
    /// A batch job prints each page and cuts between them: pages before the last
    /// A batch job prints each page and cuts between them: pages before the last
    /// A batch job prints each page and cuts between them: pages before the last
    /// A batch job prints each page and cuts between them: pages before the last
    /// A batch job prints each page and cuts between them: pages before the last
    /// A batch job prints each page and cuts between them: pages before the last
    /// A batch job prints each page and cuts between them: pages before the last
    /// A batch job prints each page and cuts between them: pages before the last
    /// end with the "print" command (0x0C), the last ends with "print + feed" (0x1A).
    @Test func batchJobCutsBetweenPages() async throws {
        let page: [[UInt8]] = [[UInt8](repeating: 0xFF, count: RasterEncoder.bytesPerLine)]
        let data = RasterEncoder.batchJob(pages: [page, page, page], tapeWidthMM: 24, cutBetween: true)
        let bytes = [UInt8](data)

        // Exactly two "print" terminators and one final "print + feed".
        #expect(bytes.filter { $0 == 0x0C }.count == 2)
        #expect(bytes.last == 0x1A)

        // Auto-cut on (ESC i M) plus no-chain advanced mode (ESC i K) so the last
        // label feeds and cuts.
        #expect(containsSequence(bytes, [0x1B, 0x69, 0x4D, 0x40]))   // ESC i M 0x40
        #expect(containsSequence(bytes, [0x1B, 0x69, 0x4B, 0x08]))   // ESC i K 0x08

        // One print-info (ESC i z) per page.
        #expect(countSequence(bytes, [0x1B, 0x69, 0x7A]) == 3)
    }

    /// A text-only label prints just its text: no size prefix, and it renders.
    @Test func textOnlyLabelPrintsJustText() async throws {
        var spec = LabelSpec()
        spec.category = .text
        spec.text1.customText = "Spare parts"
        #expect(spec.title == "Spare parts")
        #expect(!LabelRenderer.render(spec, tape: .tape24).rasterLines.isEmpty)
    }

    /// Padding lengthens an auto-length label by about the padding at each end, but
    /// a fixed length stays fixed (the content shrinks instead).
    @Test func paddingRespectsFixedLength() async throws {
        var spec = LabelSpec()
        let auto = LabelRenderer.render(spec, tape: .tape24).lengthDots
        spec.padding = .large
        let padded = LabelRenderer.render(spec, tape: .tape24).lengthDots
        let expected = Int((2 * LabelPadding.large.mm * LabelRenderer.dotsPerMM).rounded())
        #expect(abs((padded - auto) - expected) <= 2)

        var unpadded = spec
        unpadded.padding = nil
        unpadded.lengthMM = 40
        #expect(LabelRenderer.render(unpadded, tape: .tape24).lengthDots == 283)
        spec.lengthMM = 40
        let fixed = LabelRenderer.render(spec, tape: .tape24).lengthDots
        #expect(fixed == Int((40 * LabelRenderer.dotsPerMM).rounded()))
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
