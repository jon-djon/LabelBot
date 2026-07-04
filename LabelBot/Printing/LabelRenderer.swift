//
//  LabelRenderer.swift
//  LabelBot
//
//  Phase 1: render a single line of text into Brother raster lines.
//
//  Geometry: the tape feeds lengthwise past a vertical 128-pin head. Each raster
//  line is one column across the tape width; the sequence of lines is the label
//  length. So we render text into an image `labelLength` wide × `printablePins`
//  tall, then emit one raster line per image column.
//

import Foundation
import CoreGraphics
import CoreText
import AppKit

/// A supported TZe tape width and how many of the 128 head pins it prints.
/// Values from ptouch-print for 180 dpi / 128-pin P-touch models; content is
/// centered, so the pin offset is (128 − printablePins) / 2.
struct TapeSize: Identifiable, Hashable, Sendable {
    let widthMM: UInt8
    let printablePins: Int

    var id: UInt8 { widthMM }
    var label: String { "\(widthMM) mm" }
    var offset: Int { (RasterEncoder.headPins - printablePins) / 2 }

    static let all: [TapeSize] = [
        .init(widthMM: 6, printablePins: 32),
        .init(widthMM: 9, printablePins: 50),
        .init(widthMM: 12, printablePins: 70),
        .init(widthMM: 18, printablePins: 112),
        .init(widthMM: 24, printablePins: 128),
    ]
    static let tape24 = all.last!
}

struct RenderedLabel {
    let rasterLines: [[UInt8]]   // each `RasterEncoder.bytesPerLine` long
    let preview: NSImage
    let lengthDots: Int
}

enum LabelRenderer {
    // Orientation flags — flip these once we see how the first print comes out.
    static let reverseLength = false   // reverse the feed order of columns
    static let flipAcross = false      // mirror across the tape width

    /// Print resolution along the tape feed, used to convert a length in mm to dots.
    static let dotsPerMM = 180.0 / 25.4

    static func render(text: String, tape: TapeSize,
                       category: FastenerCategory = .screwBolt,
                       drive: DriveType = .none, head: HeadType = .none,
                       threadKind: ThreadKind = .machine,
                       source: IconSource = .drawn, showIcons: Bool = true,
                       iconStyle: IconStyle = .simple, threaded: Bool = true,
                       nutWasher: NutWasherType = .hexNut,
                       screwOrientation: ScrewOrientation = .vertical,
                       fixedLengthDots: Int? = nil,
                       alignment: LabelAlignment = .center,
                       fontName: String? = nil) -> RenderedLabel {
        let pins = tape.printablePins
        let verticalPadding = 2
        let contentHeight = max(1, pins - 2 * verticalPadding)

        // Size the font so the text height fills the printable band.
        let baseSize: CGFloat = 100
        let baseFont = makeFont(fontName, size: baseSize)
        let baseHeight = CTFontGetAscent(baseFont as CTFont) + CTFontGetDescent(baseFont as CTFont)
        let fontSize = baseSize * (CGFloat(contentHeight) / max(1, baseHeight))
        let font = makeFont(fontName, size: fontSize)

        let display = text.isEmpty ? " " : text
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: display, attributes: attributes))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        // Icons occupy square cells on the left, at the full printable height.
        let height = pins
        let iconSide = CGFloat(height)
        let iconGap: CGFloat = 8
        let horizontalPadding = 8
        // Which icons to draw, left-to-right, depending on category (unless icons off).
        var iconDraws: [(CGContext, CGRect) -> Void] = []
        switch category {
        case _ where !showIcons:
            break
        case .screwBolt where iconStyle == .bolt && source == .drawn:
            // One integrated bolt with the drive cut into the head.
            if head != .none || drive != .none {
                iconDraws.append { c, r in
                    IconRenderer.drawBolt(head: head, drive: drive, threadKind: threadKind,
                                          threaded: threaded,
                                          orientation: screwOrientation, into: c, rect: r)
                }
            }
        case .screwBolt:
            if head != .none {
                iconDraws.append { c, r in
                    if source == .imported, let image = IconRenderer.importedImage(stem: "head-\(head.rawValue)") {
                        IconRenderer.drawImage(image, into: c, rect: r)
                    } else {
                        IconRenderer.drawHead(head, threadKind: threadKind, threaded: threaded,
                                              orientation: screwOrientation, into: c, rect: r)
                    }
                }
            }
            if drive != .none {
                iconDraws.append { c, r in
                    if source == .imported, let image = IconRenderer.importedImage(stem: "drive-\(drive.rawValue)") {
                        IconRenderer.drawImage(image, into: c, rect: r)
                    } else {
                        IconRenderer.drawDrive(drive, into: c, rect: r)
                    }
                }
            }
        case .nutWasher:
            iconDraws.append { c, r in
                if source == .imported, let image = IconRenderer.importedImage(stem: "category-\(nutWasher.rawValue)") {
                    IconRenderer.drawImage(image, into: c, rect: r)
                } else {
                    IconRenderer.drawNutWasher(nutWasher, into: c, rect: r)
                }
            }
        case .insert:
            iconDraws.append { c, r in
                if source == .imported, let image = IconRenderer.importedImage(stem: "category-insert") {
                    IconRenderer.drawImage(image, into: c, rect: r)
                } else {
                    IconRenderer.drawInsert(into: c, rect: r)
                }
            }
        }

        let iconCount = iconDraws.count
        let iconsWidth = CGFloat(iconCount) * (iconSide + iconGap)

        // Natural width from content, then grow to a fixed length if requested.
        let contentWidth = max(1, horizontalPadding + Int(ceil(iconsWidth)) + Int(ceil(textWidth)) + horizontalPadding)
        let width = max(contentWidth, fixedLengthDots ?? 0)
        let slack = CGFloat(width - contentWidth)
        let alignOffset: CGFloat = {
            switch alignment {
            case .leading: return 0
            case .center: return slack / 2
            case .trailing: return slack
            }
        }()

        let grayscale = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width, space: grayscale,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return RenderedLabel(rasterLines: [], preview: NSImage(), lengthDots: 0)
        }
        ctx.setFillColor(gray: 1, alpha: 1)                      // white background
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setShouldAntialias(true)

        // Draw icons left-to-right: head first, then drive. Each is normalized to a
        // common height and centered on the tape's vertical midline.
        let iconTargetHeight = CGFloat(height) * 0.9

        func placeIcon(cellX: CGFloat, draw: @escaping (CGContext, CGRect) -> Void) {
            guard let (image, aspect) = IconRenderer.normalizedIcon(side: height, draw: draw) else { return }
            var drawHeight = iconTargetHeight
            var drawWidth = drawHeight * aspect
            if drawWidth > iconSide {                       // very wide symbol: fit the cell width instead
                drawWidth = iconSide
                drawHeight = drawWidth / aspect
            }
            let rect = CGRect(x: cellX + (iconSide - drawWidth) / 2,
                              y: (CGFloat(height) - drawHeight) / 2,
                              width: drawWidth, height: drawHeight)
            IconRenderer.drawImage(image, into: ctx, rect: rect)
        }

        var iconX = CGFloat(horizontalPadding) + alignOffset
        for draw in iconDraws {
            placeIcon(cellX: iconX, draw: draw)
            iconX += iconSide + iconGap
        }

        let textX = CGFloat(horizontalPadding) + alignOffset + iconsWidth
        let baseline = (CGFloat(height) - (ascent + descent)) / 2 + descent
        ctx.textPosition = CGPoint(x: textX, y: baseline)
        CTLineDraw(line, ctx)

        guard let raw = ctx.data else {
            return RenderedLabel(rasterLines: [], preview: NSImage(), lengthDots: 0)
        }
        let buffer = raw.bindMemory(to: UInt8.self, capacity: width * height)

        // One raster line per image column. Note: the grayscale context is
        // bottom-up, so buffer row 0 is the bottom of the image.
        var rasterLines: [[UInt8]] = []
        rasterLines.reserveCapacity(width)
        for column in 0..<width {
            let x = reverseLength ? (width - 1 - column) : column
            var raster = [UInt8](repeating: 0, count: RasterEncoder.bytesPerLine)
            for row in 0..<height where buffer[row * width + x] < 128 {   // dark pixel → print
                let placed = flipAcross ? (height - 1 - row) : row
                RasterEncoder.setPin(&raster, tape.offset + placed)
            }
            rasterLines.append(raster)
        }

        let preview = ctx.makeImage().map {
            NSImage(cgImage: $0, size: NSSize(width: width, height: height))
        } ?? NSImage()
        return RenderedLabel(rasterLines: rasterLines, preview: preview, lengthDots: width)
    }

    private static func makeFont(_ name: String?, size: CGFloat) -> NSFont {
        if let name, let font = NSFont(name: name, size: size) { return font }
        return NSFont.boldSystemFont(ofSize: size)
    }
}
