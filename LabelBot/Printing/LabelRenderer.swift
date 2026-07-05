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

    /// Renders a full label spec onto the given (shared) tape.
    static func render(_ spec: LabelSpec, tape: TapeSize) -> RenderedLabel {
        let fixedLengthDots = spec.lengthMM > 0
            ? Int((spec.lengthMM * dotsPerMM).rounded())
            : nil
        return render(text: spec.leftText, text2: spec.rightText, tape: tape, category: spec.category,
                      drive: spec.drive, head: spec.head, threadKind: spec.threadKind,
                      showIcons: spec.showIcons, iconStyle: spec.iconStyle,
                      threaded: spec.threaded, nutWasher: spec.nutWasher,
                      screwOrientation: spec.screwOrientation,
                      fixedLengthDots: fixedLengthDots, alignment: spec.alignment,
                      labelIcons: spec.labelIcons, textLayout: spec.textLayout)
    }

    static func render(text: String, text2: String? = nil, tape: TapeSize,
                       category: FastenerCategory = .screwBolt,
                       drive: DriveType = .none, head: HeadType = .none,
                       threadKind: ThreadKind = .machine,
                       showIcons: Bool = true,
                       iconStyle: IconStyle = .separate, threaded: Bool = true,
                       nutWasher: NutWasherType = .hexNut,
                       screwOrientation: ScrewOrientation = .vertical,
                       fixedLengthDots: Int? = nil,
                       alignment: LabelAlignment = .center,
                       labelIcons: Bool = false,
                       textLayout: TextLayout = .single,
                       fontName: String? = nil) -> RenderedLabel {
        let height = tape.printablePins
        let verticalPadding: CGFloat = 2
        let iconGap: CGFloat = 8
        let horizontalPadding: CGFloat = 8

        // Icons to draw, left-to-right, each with the caption to show underneath.
        var icons: [(caption: String, draw: (CGContext, CGRect) -> Void)] = []
        switch category {
        case _ where !showIcons:
            break
        case .screwBolt where iconStyle == .combined:
            // One integrated bolt with the drive cut into the head.
            if head != .none || drive != .none {
                let caption = [head == .none ? nil : head.displayName,
                               drive == .none ? nil : drive.displayName]
                    .compactMap { $0 }.joined(separator: " ")
                icons.append((caption, { c, r in
                    IconRenderer.drawBolt(head: head, drive: drive, threadKind: threadKind,
                                          threaded: threaded,
                                          orientation: screwOrientation, into: c, rect: r)
                }))
            }
        case .screwBolt:
            if head != .none {
                icons.append((head.displayName, { c, r in
                    IconRenderer.drawHead(head, threadKind: threadKind, threaded: threaded,
                                          orientation: screwOrientation, into: c, rect: r)
                }))
            }
            if drive != .none {
                icons.append((drive.displayName, { c, r in
                    IconRenderer.drawDrive(drive, into: c, rect: r)
                }))
            }
        case .nutWasher:
            icons.append((nutWasher.displayName, { c, r in
                IconRenderer.drawNutWasher(nutWasher, into: c, rect: r)
            }))
        case .insert:
            icons.append(("Insert", { c, r in
                IconRenderer.drawInsert(into: c, rect: r)
            }))
        }
        let iconCount = icons.count
        let captioned = labelIcons && iconCount > 0

        let usableHeight = CGFloat(height) - 2 * verticalPadding
        let textGap = iconGap
        let split = textLayout == .split

        // Base font metrics; the content font is this scaled to the printable band.
        let baseSize: CGFloat = 100
        let baseFont = makeFont(fontName, size: baseSize)
        let baseHeight = CTFontGetAscent(baseFont as CTFont) + CTFontGetDescent(baseFont as CTFont)

        // Measures the text + icon columns at a given fraction of the printable
        // height. Everything that carries visual weight scales with `scale`; the
        // paddings and gaps between elements stay fixed.
        func measure(_ scale: CGFloat)
            -> (line: CTLine, line2: CTLine, ascent: CGFloat, descent: CGFloat,
                textWidth: CGFloat, textWidth2: CGFloat,
                capLines: [CTLine], capAscent: CGFloat, capDescent: CGFloat,
                columnWidths: [CGFloat], iconsBlockWidth: CGFloat,
                captionBand: CGFloat, captionGap: CGFloat, iconBand: CGFloat,
                iconSide: CGFloat, usedHeight: CGFloat) {
            let contentHeight = usableHeight * scale
            let font = makeFont(fontName, size: baseSize * (contentHeight / max(1, baseHeight)))
            func makeLine(_ s: String) -> CTLine {
                let display = s.isEmpty ? " " : s
                return CTLineCreateWithAttributedString(
                    NSAttributedString(string: display, attributes: [.font: font, .foregroundColor: NSColor.black]))
            }
            let line = makeLine(text)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let line2 = makeLine(text2 ?? text)
            let textWidth2 = CGFloat(CTLineGetTypographicBounds(line2, nil, nil, nil))

            // When captioning, split each icon column into an icon band (top) and a
            // caption band (bottom); the icons shrink to make room.
            let captionGap: CGFloat = captioned ? 3 : 0
            let captionBand = captioned ? max(1, contentHeight * 0.28) : 0
            let iconBand = captioned ? max(1, contentHeight - captionBand - captionGap) : contentHeight
            let iconSide = iconBand

            let capFontSize = captionBand * 0.9
            let capFont = NSFont.systemFont(ofSize: max(1, capFontSize))
            var capLines: [CTLine] = []
            var capAscent: CGFloat = 0, capDescent: CGFloat = 0, capLeading: CGFloat = 0
            var columnWidths: [CGFloat] = []
            for icon in icons {
                if captioned {
                    let l = CTLineCreateWithAttributedString(
                        NSAttributedString(string: icon.caption, attributes: [.font: capFont, .foregroundColor: NSColor.black]))
                    let w = CGFloat(CTLineGetTypographicBounds(l, &capAscent, &capDescent, &capLeading))
                    capLines.append(l)
                    columnWidths.append(max(iconSide, w))
                } else {
                    columnWidths.append(iconSide)
                }
            }
            // Icon block width (icons + inter-icon gaps, no trailing gap).
            let iconsBlockWidth = columnWidths.reduce(0, +) + max(0, CGFloat(iconCount - 1)) * iconGap
            let usedHeight = captioned ? (captionBand + captionGap + iconBand) : contentHeight
            return (line, line2, ascent, descent, textWidth, textWidth2, capLines,
                    capAscent, capDescent, columnWidths, iconsBlockWidth,
                    captionBand, captionGap, iconBand, iconSide, usedHeight)
        }

        // Ideal (unclamped) content width. Single: icons then text. Split:
        // text · icons · text with equal halves (icons stay centred).
        func idealWidth(text tw: CGFloat, text2 tw2: CGFloat, block: CGFloat) -> CGFloat {
            let iconsSlot = iconCount > 0 ? block : 0
            if split {
                return 2 * horizontalPadding + 2 * max(tw, tw2)
                    + (iconCount > 0 ? iconsSlot + 2 * textGap : textGap)
            }
            return 2 * horizontalPadding + iconsSlot + (iconCount > 0 ? textGap : 0) + tw
        }

        var m = measure(1)

        // If a fixed length is requested and the natural content is too wide, scale
        // the text + icons down uniformly so they fit (leaving vertical whitespace).
        if let target = fixedLengthDots, target > 0,
           idealWidth(text: m.textWidth, text2: m.textWidth2, block: m.iconsBlockWidth) > CGFloat(target) {
            let interIconGaps = max(0, CGFloat(iconCount - 1)) * iconGap
            let sumColumnWidths = iconCount > 0 ? m.iconsBlockWidth - interIconGaps : 0
            // idealWidth is affine in scale: fixed + scale · scalable.
            let fixed: CGFloat
            let scalable: CGFloat
            if split {
                fixed = 2 * horizontalPadding + (iconCount > 0 ? interIconGaps + 2 * textGap : textGap)
                scalable = 2 * max(m.textWidth, m.textWidth2) + sumColumnWidths
            } else {
                fixed = 2 * horizontalPadding + (iconCount > 0 ? interIconGaps + textGap : 0)
                scalable = m.textWidth + sumColumnWidths
            }
            if scalable > 0 {
                // 1px safety so rounding never nudges the content past the length.
                let scale = (CGFloat(target) - fixed - 1) / scalable
                m = measure(min(1, max(0.05, scale)))
            }
        }

        let line = m.line
        let line2 = m.line2
        let ascent = m.ascent
        let descent = m.descent
        let textWidth = m.textWidth
        let textWidth2 = m.textWidth2
        let capLines = m.capLines
        let capAscent = m.capAscent
        let capDescent = m.capDescent
        let columnWidths = m.columnWidths
        let iconSide = m.iconSide
        let captionBand = m.captionBand
        let captionGap = m.captionGap
        let iconBand = m.iconBand
        let iconsSlot = iconCount > 0 ? m.iconsBlockWidth : 0
        // Top of the (possibly shrunk) content block, centred within the band.
        let captionBase = verticalPadding + (usableHeight - m.usedHeight) / 2

        let contentWidth = max(1, Int(ceil(idealWidth(text: textWidth, text2: textWidth2, block: m.iconsBlockWidth))))
        // A fixed length is honored exactly (content is shrunk above to fit within
        // it); with no fixed length the label grows to fit its content.
        let width = fixedLengthDots.map { max(1, $0) } ?? contentWidth
        let slack = max(0, CGFloat(width - contentWidth))
        // In split mode the icons are centred, so alignment does not apply.
        let alignOffset: CGFloat = {
            if split { return 0 }
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

        // Normalizes an icon and draws it as a square of `side`, centered at (cx, cy).
        func placeIcon(centerX: CGFloat, centerY: CGFloat, side: CGFloat, draw: (CGContext, CGRect) -> Void) {
            guard let (image, aspect) = IconRenderer.normalizedIcon(side: height, draw: draw) else { return }
            var drawHeight = side * 0.92
            var drawWidth = drawHeight * aspect
            if drawWidth > side {                       // very wide symbol: fit the cell width instead
                drawWidth = side
                drawHeight = drawWidth / aspect
            }
            IconRenderer.drawImage(image, into: ctx,
                                   rect: CGRect(x: centerX - drawWidth / 2, y: centerY - drawHeight / 2,
                                                width: drawWidth, height: drawHeight))
        }

        let iconCenterY = captioned ? (captionBase + captionBand + captionGap + iconBand / 2)
                                    : CGFloat(height) / 2

        // Draws the icon block (with optional captions) starting at `startX`.
        func drawIconBlock(startX: CGFloat) {
            var columnX = startX
            for (index, icon) in icons.enumerated() {
                let columnWidth = columnWidths[index]
                placeIcon(centerX: columnX + columnWidth / 2, centerY: iconCenterY, side: iconSide, draw: icon.draw)
                if captioned {
                    let capWidth = CGFloat(CTLineGetTypographicBounds(capLines[index], nil, nil, nil))
                    let capBaseline = captionBase + (captionBand - (capAscent + capDescent)) / 2 + capDescent
                    ctx.textPosition = CGPoint(x: columnX + (columnWidth - capWidth) / 2, y: capBaseline)
                    CTLineDraw(capLines[index], ctx)
                }
                columnX += columnWidth + iconGap
            }
        }

        // Draws a text line with its baseline centred, horizontally centred in [x0, x1].
        let baseline = (CGFloat(height) - (ascent + descent)) / 2 + descent
        func drawText(_ ctLine: CTLine, width lineWidth: CGFloat, centeredIn x0: CGFloat, _ x1: CGFloat) {
            ctx.textPosition = CGPoint(x: x0 + ((x1 - x0) - lineWidth) / 2, y: baseline)
            CTLineDraw(ctLine, ctx)
        }

        if split {
            // text · icons · text, icons centred in the label.
            let iconsStart = CGFloat(width) / 2 - iconsSlot / 2
            if iconCount > 0 { drawIconBlock(startX: iconsStart) }
            let leftEnd = iconCount > 0 ? iconsStart - textGap : CGFloat(width) / 2
            let rightStart = iconCount > 0 ? iconsStart + iconsSlot + textGap : CGFloat(width) / 2
            drawText(line, width: textWidth, centeredIn: CGFloat(horizontalPadding), leftEnd)
            drawText(line2, width: textWidth2, centeredIn: rightStart, CGFloat(width) - CGFloat(horizontalPadding))
        } else {
            let blockX = CGFloat(horizontalPadding) + alignOffset
            if iconCount > 0 { drawIconBlock(startX: blockX) }
            let textX = blockX + iconsSlot + (iconCount > 0 ? textGap : 0)
            ctx.textPosition = CGPoint(x: textX, y: baseline)
            CTLineDraw(line, ctx)
        }

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
