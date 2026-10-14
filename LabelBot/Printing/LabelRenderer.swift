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

    /// A measured dimensioned block — [size] [length ↕] [diameter over ↔]
    /// [internal] [optional custom text] — with the per-cell widths that the
    /// layout math and `drawDimensionBlock` both rely on.
    private struct DimBlock {
        var sizeLine: CTLine?, lenLine: CTLine?, diaLine: CTLine?, innerLine: CTLine?, customLine: CTLine?
        var sizeWidth: CGFloat = 0, lenWidth: CGFloat = 0, diaWidth: CGFloat = 0
        var innerWidth: CGFloat = 0, customWidth: CGFloat = 0, totalWidth: CGFloat = 0
    }

    /// Print resolution along the tape feed, used to convert a length in mm to dots.
    static let dotsPerMM = 180.0 / 25.4

    /// Oversampling factor for the render canvas. The printed raster is averaged
    /// back to the native 180-dpi grid, so this only sharpens the on-screen preview
    /// and the edge coverage used when thresholding — it never changes label size.
    static let supersample = 3

    /// Renders a full label spec onto the given (shared) tape. `highRes` doubles the
    /// resolution along the length for smoother print (Brother "high-resolution" mode).
    static func render(_ spec: LabelSpec, tape: TapeSize, highRes: Bool = false) -> RenderedLabel {
        let fixedLengthDots = spec.lengthMM > 0
            ? Int((spec.lengthMM * dotsPerMM).rounded())
            : nil
        // Threaded inserts with guided sizes get a dimensioned block: the size text,
        // the length (↕ beside), the barrel diameter (↔ below), and an optional
        // internal diameter — instead of plain size text. Each text section is
        // dimensioned independently.
        let dimensioned = spec.category == .insert && spec.text1.sizeMode == .pickers
        let dimensioned2 = spec.category == .insert && spec.text2.sizeMode == .pickers
        // The size (e.g. "M3 × 8") is drawn in a heavier weight than the custom
        // text. A dimensioned section draws its size/length/diameter separately, so
        // there the plain-text portion is only the trailing custom text and the size
        // gets its emphasis inside the dimension block instead.
        let size1 = spec.text1.sizeString(hasLength: spec.category.hasLength).trimmingCharacters(in: .whitespaces)
        let size2 = spec.text2.sizeString(hasLength: spec.category.hasLength).trimmingCharacters(in: .whitespaces)
        // `text` is always just the custom portion; the size is passed separately so
        // it can be weighted (plain path) or drawn in the dimension block.
        let mainText = spec.text1.customText.trimmingCharacters(in: .whitespaces)
        let secondText = spec.text2.customText.trimmingCharacters(in: .whitespaces)
        // Text-only labels print just the custom text: no size, no icons.
        let hasSize = spec.category.isFastener
        let mainSize = !hasSize || dimensioned || size1.isEmpty ? nil : size1
        let secondSize = !hasSize || dimensioned2 || size2.isEmpty ? nil : size2
        return render(text: mainText, text2: secondText,
                      sizeText: mainSize, sizeText2: secondSize, tape: tape, category: spec.category,
                      drive: spec.drive, head: spec.head, threadKind: spec.threadKind,
                      showIcons: spec.showIcons, iconStyle: spec.iconStyle,
                      threaded: spec.threaded, nutWasher: spec.nutWasher,
                      screwOrientation: spec.screwOrientation,
                      screwLength: spec.screwLength.factor,
                      spacing: spec.iconSpacing.factor, zoom: spec.zoom.factor,
                      iconScale: spec.iconSize.factor, border: spec.border,
                      sizeBorder: spec.sizeBorder, boldText: spec.boldText,
                      fixedLengthDots: fixedLengthDots,
                      paddingDots: CGFloat((spec.padding ?? .off).mm * dotsPerMM),
                      alignment: spec.alignment,
                      labelDrive: spec.labelDrive, labelHead: spec.labelHead,
                      textLayout: spec.textLayout,
                      dimensionSize: dimensioned ? spec.text1.diameter : nil,
                      dimensionLength: dimensioned ? spec.text1.length : nil,
                      dimensionDiameter: dimensioned ? spec.text1.outerDiameter : nil,
                      dimensionInner: dimensioned ? spec.text1.innerDiameter : nil,
                      dimensionSize2: dimensioned2 ? spec.text2.diameter : nil,
                      dimensionLength2: dimensioned2 ? spec.text2.length : nil,
                      dimensionDiameter2: dimensioned2 ? spec.text2.outerDiameter : nil,
                      dimensionInner2: dimensioned2 ? spec.text2.innerDiameter : nil,
                      highRes: highRes, fontName: spec.fontName)
    }

    static func render(text: String, text2: String? = nil,
                       sizeText: String? = nil, sizeText2: String? = nil, tape: TapeSize,
                       category: FastenerCategory = .screwBolt,
                       drive: DriveType = .none, head: HeadType = .none,
                       threadKind: ThreadKind = .machine,
                       showIcons: Bool = true,
                       iconStyle: IconStyle = .separate, threaded: Bool = true,
                       nutWasher: NutWasherType = .hexNut,
                       screwOrientation: ScrewOrientation = .vertical,
                       screwLength: Double = 1,
                       spacing: Double = 1,
                       zoom: Double = 1,
                       iconScale: Double = 1,
                       border: Bool = false,
                       sizeBorder: Bool = false,
                       boldText: Bool = false,
                       fixedLengthDots: Int? = nil,
                       paddingDots: CGFloat = 0,
                       alignment: LabelAlignment = .center,
                       labelDrive: Bool = false,
                       labelHead: Bool = false,
                       textLayout: TextLayout = .single,
                       dimensionSize: String? = nil,
                       dimensionLength: String? = nil,
                       dimensionDiameter: String? = nil,
                       dimensionInner: String? = nil,
                       dimensionSize2: String? = nil,
                       dimensionLength2: String? = nil,
                       dimensionDiameter2: String? = nil,
                       dimensionInner2: String? = nil,
                       highRes: Bool = false,
                       fontName: String? = nil) -> RenderedLabel {
        let height = tape.printablePins
        let verticalPadding: CGFloat = 2
        // Gap between icons and between the icon block and the text (user-scalable).
        let iconGap: CGFloat = 8 * CGFloat(spacing)
        // Margin at each end of the label (where the border sits), then the
        // user's padding inside it. Both count toward the length, so a fixed length
        // shrinks the content to make room rather than growing.
        let edgeMargin: CGFloat = 8
        let horizontalPadding: CGFloat = edgeMargin + max(0, paddingDots)
        // Geometry of a dimensioned insert block, as fractions of the font's em.
        // Kept tight so the size/length/diameter read as one group. Each value is
        // used by both `measure` and `drawDimensionBlock`, which must stay in sync.
        let dimCellGap: CGFloat = 0.22    // gap between cells
        let dimLenTail: CGFloat = 0.48    // length cell: number + this (room for the ↕)
        let dimLenArrow: CGFloat = 0.28   // ↕ sits this far right of the length number
        let dimDiaMin: CGFloat = 0.7      // diameter column min width (the ↔ span)
        // Size box (around e.g. "M3"), as fractions of the font's em. Shared by the
        // layout reservation in `measure` and the drawing in `strokeSizeBox`.
        let sizeBoxPad: CGFloat = 0.14    // padding between the size ink and the box
        let sizeBoxLine: CGFloat = 0.055  // box line width
        // Space to reserve on each side of a boxed size (box padding + half its line)
        // so the box clears its neighbours. Zero when the size box is off.
        func sizeBoxReserve(_ em: CGFloat) -> CGFloat {
            sizeBorder ? em * sizeBoxPad + max(1.5, em * sizeBoxLine) / 2 : 0
        }

        // Icons to draw, left-to-right, each with an optional caption underneath.
        // Captions toggle independently: `labelDrive` for the drive icon, `labelHead`
        // for the screw-type (head) icon; nut/washer and insert use `labelHead`.
        var icons: [(caption: String?, draw: (CGContext, CGRect) -> Void)] = []
        switch category {
        case _ where !showIcons, .text:
            break
        case .screwBolt where iconStyle == .combined:
            // One integrated bolt with the drive cut into the head.
            if head != .none || drive != .none {
                let parts = [labelHead && head != .none ? head.displayName : nil,
                             labelDrive && drive != .none ? drive.displayName : nil].compactMap { $0 }
                let caption = parts.isEmpty ? nil : parts.joined(separator: " ")
                icons.append((caption, { c, r in
                    IconRenderer.drawBolt(head: head, drive: drive, threadKind: threadKind,
                                          threaded: threaded,
                                          orientation: screwOrientation, length: screwLength,
                                          into: c, rect: r)
                }))
            }
        case .screwBolt:
            if head != .none {
                icons.append((labelHead ? head.displayName : nil, { c, r in
                    IconRenderer.drawHead(head, threadKind: threadKind, threaded: threaded,
                                          orientation: screwOrientation, length: screwLength,
                                          into: c, rect: r)
                }))
            }
            if drive != .none {
                icons.append((labelDrive ? drive.displayName : nil, { c, r in
                    IconRenderer.drawDrive(drive, into: c, rect: r)
                }))
            }
        case .nutWasher:
            icons.append((labelHead ? nutWasher.displayName : nil, { c, r in
                IconRenderer.drawNutWasher(nutWasher, into: c, rect: r)
            }))
        case .insert:
            icons.append((labelHead ? "Insert" : nil, { c, r in
                IconRenderer.drawInsert(into: c, rect: r)
            }))
        }
        let iconCount = icons.count
        // Reserve a caption band if any icon actually carries a caption.
        let captioned = icons.contains { $0.caption != nil }

        let usableHeight = CGFloat(height) - 2 * verticalPadding
        let textGap = iconGap
        let split = textLayout == .split

        // Dimensioned mode (threaded inserts): a size text, the length with a ↕
        // beside it, the barrel diameter with a ↔ below it, and an optional
        // internal diameter.
        let dimensioned = dimensionSize != nil
        // Section 2 only exists in split layout, so its block is measured/drawn there.
        let dimensioned2 = dimensionSize2 != nil && split
        let dimSize = dimensionSize ?? ""
        let dimLength = dimensionLength ?? ""
        let dimDiameter = dimensionDiameter ?? ""
        let dimInner = dimensionInner ?? ""
        let dimSize2 = dimensionSize2 ?? ""
        let dimLength2 = dimensionLength2 ?? ""
        let dimDiameter2 = dimensionDiameter2 ?? ""
        let dimInner2 = dimensionInner2 ?? ""

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
                capLines: [CTLine?], capAscent: CGFloat, capDescent: CGFloat,
                columnWidths: [CGFloat], iconsBlockWidth: CGFloat,
                captionBand: CGFloat, captionGap: CGFloat, iconBand: CGFloat,
                iconSide: CGFloat, usedHeight: CGFloat,
                block1: DimBlock, block2: DimBlock,
                sizeLine1: CTLine?, sizeLine2: CTLine?,
                inset1: CGFloat, inset2: CGFloat) {
            let contentHeight = usableHeight * scale
            // Dimensioned numbers are smaller so the ↔ arrow fits below the diameter.
            let fontHeight = (dimensioned || dimensioned2) ? contentHeight * 0.62 : contentHeight
            let fpx = baseSize * (fontHeight / max(1, baseHeight))
            // The size is always the heavier weight; `boldText` lifts the rest to match.
            let font = makeFont(fontName, size: fpx, heavier: boldText)
            let sizeFont = makeFont(fontName, size: fpx, heavier: true)
            func makeLine(_ s: String) -> CTLine {
                let display = s.isEmpty ? " " : s
                return CTLineCreateWithAttributedString(
                    NSAttributedString(string: display, attributes: [.font: font, .foregroundColor: NSColor.black]))
            }
            // Primary/secondary text: the size prefix (if any) in the heavier weight,
            // then the custom text in the regular weight.
            func makeSectionLine(size: String?, custom: String) -> CTLine {
                guard let size, !size.isEmpty else { return makeLine(custom) }
                let s = NSMutableAttributedString(
                    string: size, attributes: [.font: sizeFont, .foregroundColor: NSColor.black])
                if !custom.isEmpty {
                    s.append(NSAttributedString(string: "  " + custom,
                                                attributes: [.font: font, .foregroundColor: NSColor.black]))
                }
                return CTLineCreateWithAttributedString(s)
            }
            // The size on its own (for the optional box drawn around it). The plain
            // path's size is the leading run of `line`, so this aligns with it; the
            // dimensioned path boxes its size cell (`DimBlock.sizeLine`) directly.
            func sizeOnly(_ s: String?) -> CTLine? {
                guard let s, !s.isEmpty else { return nil }
                return CTLineCreateWithAttributedString(
                    NSAttributedString(string: s, attributes: [.font: sizeFont, .foregroundColor: NSColor.black]))
            }
            let sizeLine1 = sizeOnly(sizeText)
            let sizeLine2 = sizeOnly(sizeText2)
            let line = makeSectionLine(size: sizeText, custom: text)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            var textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let line2 = makeSectionLine(size: sizeText2, custom: text2 ?? text)
            var textWidth2 = CGFloat(CTLineGetTypographicBounds(line2, nil, nil, nil))

            // Dimensioned block: [size] [length ↕] [diameter over ↔] [internal]
            // [optional custom]. Its total width replaces the plain text width in
            // the layout below; every part scales with the font so the fit math
            // stays linear. Cell widths here must match drawDimensionBlock exactly.
            func makeDimBlock(size: String, length: String, diameter: String,
                              inner: String, custom: String) -> DimBlock {
                func lineWidth(_ s: String) -> (CTLine, CGFloat) {
                    let l = makeLine(s)
                    return (l, CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)))
                }
                let em = ascent + descent
                var b = DimBlock()
                var cellWidths: [CGFloat] = []
                if !size.isEmpty {
                    // The size sits in the heavier weight, like the plain-text path,
                    // and reserves room on each side for its optional box.
                    b.sizeLine = CTLineCreateWithAttributedString(
                        NSAttributedString(string: size, attributes: [.font: sizeFont, .foregroundColor: NSColor.black]))
                    b.sizeWidth = CGFloat(CTLineGetTypographicBounds(b.sizeLine!, nil, nil, nil))
                    cellWidths.append(b.sizeWidth + 2 * sizeBoxReserve(em))
                }
                if !length.isEmpty {
                    (b.lenLine, b.lenWidth) = lineWidth(length)
                    cellWidths.append(b.lenWidth + em * dimLenTail)   // text + gap + ↕
                }
                if !diameter.isEmpty {
                    (b.diaLine, b.diaWidth) = lineWidth(diameter)
                    cellWidths.append(max(b.diaWidth, em * dimDiaMin)) // ↔ spans this column
                }
                if !inner.isEmpty {
                    (b.innerLine, b.innerWidth) = lineWidth(inner)
                    cellWidths.append(b.innerWidth)
                }
                if !custom.trimmingCharacters(in: .whitespaces).isEmpty {
                    (b.customLine, b.customWidth) = lineWidth(custom)
                    cellWidths.append(b.customWidth)
                }
                let midGap = em * dimCellGap
                b.totalWidth = cellWidths.reduce(0, +) + max(0, CGFloat(cellWidths.count - 1)) * midGap
                return b
            }
            var block1 = DimBlock(), block2 = DimBlock()
            if dimensioned {
                block1 = makeDimBlock(size: dimSize, length: dimLength, diameter: dimDiameter,
                                      inner: dimInner, custom: text)
                textWidth = block1.totalWidth
            }
            if dimensioned2 {
                block2 = makeDimBlock(size: dimSize2, length: dimLength2, diameter: dimDiameter2,
                                      inner: dimInner2, custom: text2 ?? "")
                textWidth2 = block2.totalWidth
            }

            // Reserve room around a plain-path size box so it never overlaps the
            // icon or runs off the label. `sizeBoxInset` must match strokeSizeBox's
            // padding + half its line width. (Dimensioned sizes box inside the block
            // gaps, so they need no reservation — their sizeLine here is nil.)
            let sizeBoxInset = sizeBoxReserve(ascent + descent)
            let inset1: CGFloat = sizeLine1 != nil ? sizeBoxInset : 0
            let inset2: CGFloat = sizeLine2 != nil ? sizeBoxInset : 0
            textWidth += 2 * inset1
            textWidth2 += 2 * inset2

            // When captioning, split each icon column into an icon band (top) and a
            // caption band (bottom); the icons shrink to make room.
            let captionGap: CGFloat = captioned ? 3 : 0
            let captionBand = captioned ? max(1, contentHeight * 0.28) : 0
            let iconBand = captioned ? max(1, contentHeight - captionBand - captionGap) : contentHeight
            let iconSide = iconBand

            let capFontSize = captionBand * 0.9
            let capFont = NSFont.systemFont(ofSize: max(1, capFontSize), weight: boldText ? .bold : .regular)
            var capLines: [CTLine?] = []
            var capAscent: CGFloat = 0, capDescent: CGFloat = 0, capLeading: CGFloat = 0
            // The icon (and the column it reserves) may be shrunk relative to the
            // text; a caption still claims its own full width beneath.
            let scaledIcon = CGFloat(iconScale)
            var columnWidths: [CGFloat] = []
            for icon in icons {
                if captioned, let caption = icon.caption {
                    // Captioned icon shrinks into the icon band to make room below.
                    let l = CTLineCreateWithAttributedString(
                        NSAttributedString(string: caption, attributes: [.font: capFont, .foregroundColor: NSColor.black]))
                    let w = CGFloat(CTLineGetTypographicBounds(l, &capAscent, &capDescent, &capLeading))
                    capLines.append(l)
                    columnWidths.append(max(iconBand * scaledIcon, w))
                } else {
                    // Uncaptioned icon keeps the full height, unaffected by whether a
                    // sibling icon is captioned.
                    capLines.append(nil)
                    columnWidths.append(contentHeight * scaledIcon)
                }
            }
            // Icon block width (icons + inter-icon gaps, no trailing gap).
            let iconsBlockWidth = columnWidths.reduce(0, +) + max(0, CGFloat(iconCount - 1)) * iconGap
            let usedHeight = captioned ? (captionBand + captionGap + iconBand) : contentHeight
            return (line, line2, ascent, descent, textWidth, textWidth2, capLines,
                    capAscent, capDescent, columnWidths, iconsBlockWidth,
                    captionBand, captionGap, iconBand, iconSide, usedHeight,
                    block1, block2, sizeLine1, sizeLine2, inset1, inset2)
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
                let fitScale = (CGFloat(target) - fixed - 1) / scalable
                // Zoom enlarges the fitted content (the label grows past the fixed
                // length below to make room); the band still caps the height at 1.
                var scale = min(1, max(0.05, fitScale * CGFloat(zoom)))
                m = measure(scale)
                // Text width isn't exactly linear in font size (hinting, rounding,
                // box insets), so the fitted content can still overshoot by a dot
                // or two. Unless zoom deliberately enlarges past the length, nudge
                // the scale down until it fits.
                if zoom <= 1 {
                    for _ in 0..<6 {
                        let ideal = idealWidth(text: m.textWidth, text2: m.textWidth2, block: m.iconsBlockWidth)
                        guard ceil(ideal) > CGFloat(target), scale > 0.05, ideal > fixed else { break }
                        scale = max(0.05, scale * (CGFloat(target) - fixed - 1) / (ideal - fixed))
                        m = measure(scale)
                    }
                }
            }
        }

        let line = m.line
        let line2 = m.line2
        let ascent = m.ascent
        let descent = m.descent
        let textWidth = m.textWidth
        let textWidth2 = m.textWidth2
        let block1 = m.block1
        let block2 = m.block2
        let sizeLine1 = m.sizeLine1
        let sizeLine2 = m.sizeLine2
        let inset1 = m.inset1
        let inset2 = m.inset2
        let capLines = m.capLines
        let capAscent = m.capAscent
        let capDescent = m.capDescent
        let columnWidths = m.columnWidths
        let usedHeight = m.usedHeight
        let captionBand = m.captionBand
        let captionGap = m.captionGap
        let iconBand = m.iconBand
        let iconsSlot = iconCount > 0 ? m.iconsBlockWidth : 0
        // Top of the (possibly shrunk) content block, centred within the band.
        let captionBase = verticalPadding + (usableHeight - m.usedHeight) / 2

        let contentWidth = max(1, Int(ceil(idealWidth(text: textWidth, text2: textWidth2, block: m.iconsBlockWidth))))
        // A fixed length sets the label length, but zoomed content may be wider than
        // that — then the label grows so the enlarged content still fits. With no
        // fixed length the label always grows to fit its content.
        let width = fixedLengthDots.map { max(max(1, $0), contentWidth) } ?? contentWidth
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

        // High-resolution printing doubles the resolution along the length (feed)
        // direction only — "180 dpi high, 360 dpi wide" — so the raster carries twice
        // as many columns and the glyphs are drawn stretched 2× along the length,
        // which the printer squeezes back to square when it prints at 180×360 dpi.
        let lengthScale = highRes ? 2 : 1
        let rasterWidth = width * lengthScale

        // Render into a supersampled canvas (all drawing stays in native label
        // coordinates via the CTM scale) so text and icon edges have real detail;
        // the raster is area-averaged back down to the raster grid below, and the
        // preview keeps this higher-resolution image. Smoother without changing size.
        let ss = supersample
        let pxWidth = rasterWidth * ss, pxHeight = height * ss
        let grayscale = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: pxWidth, height: pxHeight, bitsPerComponent: 8,
                                  bytesPerRow: pxWidth, space: grayscale,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return RenderedLabel(rasterLines: [], preview: NSImage(), lengthDots: 0)
        }
        ctx.setFillColor(gray: 1, alpha: 1)                      // white background
        ctx.fill(CGRect(x: 0, y: 0, width: pxWidth, height: pxHeight))
        // Draw in native coordinates; x carries the extra length-resolution factor.
        ctx.scaleBy(x: CGFloat(ss * lengthScale), y: CGFloat(ss))
        ctx.setShouldAntialias(true)

        // Normalizes an icon and draws it as a square of `side`, centered at (cx, cy).
        // The icon bitmap is rendered at the supersampled resolution so it stays crisp.
        func placeIcon(centerX: CGFloat, centerY: CGFloat, side: CGFloat, draw: (CGContext, CGRect) -> Void) {
            guard let (image, aspect) = IconRenderer.normalizedIcon(side: height * ss, draw: draw) else { return }
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

        // A captioned icon shrinks into the icon band (centred above its caption);
        // an uncaptioned icon uses the full height, centred — so toggling one icon's
        // caption never changes another icon's size.
        let captionedCenterY = captionBase + captionBand + captionGap + iconBand / 2
        let fullCenterY = CGFloat(height) / 2

        // Draws the icon block (with optional captions) starting at `startX`.
        func drawIconBlock(startX: CGFloat) {
            var columnX = startX
            for (index, icon) in icons.enumerated() {
                let columnWidth = columnWidths[index]
                let hasCaption = capLines[index] != nil
                let side = (hasCaption ? iconBand : usedHeight) * CGFloat(iconScale)
                let centerY = hasCaption ? captionedCenterY : fullCenterY
                placeIcon(centerX: columnX + columnWidth / 2, centerY: centerY, side: side, draw: icon.draw)
                if let capLine = capLines[index] {
                    let capWidth = CGFloat(CTLineGetTypographicBounds(capLine, nil, nil, nil))
                    let capBaseline = captionBase + (captionBand - (capAscent + capDescent)) / 2 + capDescent
                    ctx.textPosition = CGPoint(x: columnX + (columnWidth - capWidth) / 2, y: capBaseline)
                    CTLineDraw(capLine, ctx)
                }
                columnX += columnWidth + iconGap
            }
        }

        // Draws a text line at the given baseline. The line's footprint (which may
        // reserve `inset` on each side for a size box) is centred in [x0, x1]; the
        // line itself sits `inset` in from that footprint. Returns the line's left
        // edge — where the size (its first run) begins.
        let baseline = (CGFloat(height) - (ascent + descent)) / 2 + descent
        @discardableResult
        func drawText(_ ctLine: CTLine, footprint: CGFloat, inset: CGFloat,
                      centeredIn x0: CGFloat, _ x1: CGFloat) -> CGFloat {
            let startX = x0 + ((x1 - x0) - footprint) / 2 + inset
            ctx.textPosition = CGPoint(x: startX, y: baseline)
            CTLineDraw(ctLine, ctx)
            return startX
        }

        // Optional box around just the size (e.g. "M3"), hugging its ink with a
        // little padding. `startX`/`baselineY` locate the size's text origin — for
        // the plain path that's the start of the line (the size is its first run).
        func strokeSizeBox(_ sizeLine: CTLine?, startX: CGFloat, baselineY: CGFloat) {
            guard sizeBorder, let sizeLine else { return }
            let w = CGFloat(CTLineGetTypographicBounds(sizeLine, nil, nil, nil))
            guard w > 0 else { return }
            let em = ascent + descent
            let pad = em * sizeBoxPad
            let lw = max(1.5, em * sizeBoxLine)
            // Sizes are caps/digits sitting on the baseline; box from there up to the
            // cap height (metrics-based, so it's independent of the drawing context).
            let capTop = baselineY + em * 0.72
            let rect = CGRect(x: startX - pad, y: baselineY - pad,
                              width: w + 2 * pad, height: (capTop - baselineY) + 2 * pad)
            ctx.setStrokeColor(gray: 0, alpha: 1)
            ctx.setLineWidth(lw)
            ctx.stroke(rect)
        }

        // Draws a dimensioned block: the size, then the length with a ↕ beside it,
        // then the diameter with a ↔ centred beneath it, an optional internal
        // diameter, then any custom text. Starts at `startX`.
        func drawDimensionBlock(_ block: DimBlock, startX: CGFloat) {
            let em = ascent + descent
            let cy = CGFloat(height) / 2
            let weight = max(1.2, em * 0.06)
            let midGap = em * dimCellGap

            // The diameter number sits over a ↔; centre the (number + gap + arrow)
            // group vertically so neither the number top nor the arrow clips. Every
            // number shares this raised baseline.
            let vgap = em * 0.12
            let hArrowH = em * 0.26
            let numBaseline = cy - (ascent - descent - (vgap + hArrowH)) / 2

            var x = startX
            func advance(_ w: CGFloat) { x += w + midGap }

            // Size (plain text, no arrow), inset within its reserved cell so the
            // optional box clears the neighbouring elements.
            if let sizeLine = block.sizeLine {
                let reserve = sizeBoxReserve(em)
                ctx.textPosition = CGPoint(x: x + reserve, y: numBaseline)
                CTLineDraw(sizeLine, ctx)
                strokeSizeBox(sizeLine, startX: x + reserve, baselineY: numBaseline)
                advance(block.sizeWidth + 2 * reserve)
            }
            // Length with a ↕ beside it.
            if let lenLine = block.lenLine {
                ctx.textPosition = CGPoint(x: x, y: numBaseline)
                CTLineDraw(lenLine, ctx)
                IconRenderer.drawVDoubleArrow(into: ctx, y0: numBaseline - descent, y1: numBaseline + ascent,
                                              x: x + block.lenWidth + em * dimLenArrow, weight: weight)
                advance(block.lenWidth + em * dimLenTail)
            }
            // Diameter with a ↔ centred beneath it.
            if let diaLine = block.diaLine {
                let column = max(block.diaWidth, em * dimDiaMin)
                ctx.textPosition = CGPoint(x: x + (column - block.diaWidth) / 2, y: numBaseline)
                CTLineDraw(diaLine, ctx)
                let arrowY = numBaseline - descent - vgap - hArrowH / 2
                IconRenderer.drawHDoubleArrow(into: ctx, x0: x, x1: x + column, y: arrowY, weight: weight)
                advance(column)
            }
            // Optional internal diameter (plain text).
            if let innerLine = block.innerLine {
                ctx.textPosition = CGPoint(x: x, y: numBaseline)
                CTLineDraw(innerLine, ctx)
                advance(block.innerWidth)
            }
            // Trailing custom text, if any.
            if let customLine = block.customLine {
                ctx.textPosition = CGPoint(x: x, y: numBaseline)
                CTLineDraw(customLine, ctx)
            }
        }

        if split {
            // text · icons · text, icons centred in the label.
            let iconsStart = CGFloat(width) / 2 - iconsSlot / 2
            if iconCount > 0 { drawIconBlock(startX: iconsStart) }
            let leftEnd = iconCount > 0 ? iconsStart - textGap : CGFloat(width) / 2
            let rightStart = iconCount > 0 ? iconsStart + iconsSlot + textGap : CGFloat(width) / 2
            // Each side is a dimensioned block (size, length ↕, diameter ↔) or plain
            // text; centre it (block width == textWidth) in its half.
            if dimensioned {
                let leftStart = CGFloat(horizontalPadding)
                drawDimensionBlock(block1, startX: leftStart + ((leftEnd - leftStart) - textWidth) / 2)
            } else {
                let sx = drawText(line, footprint: textWidth, inset: inset1,
                                  centeredIn: CGFloat(horizontalPadding), leftEnd)
                strokeSizeBox(sizeLine1, startX: sx, baselineY: baseline)
            }
            if dimensioned2 {
                let rightEnd = CGFloat(width) - CGFloat(horizontalPadding)
                drawDimensionBlock(block2, startX: rightStart + ((rightEnd - rightStart) - textWidth2) / 2)
            } else {
                let sx = drawText(line2, footprint: textWidth2, inset: inset2,
                                  centeredIn: rightStart, CGFloat(width) - CGFloat(horizontalPadding))
                strokeSizeBox(sizeLine2, startX: sx, baselineY: baseline)
            }
        } else {
            let blockX = CGFloat(horizontalPadding) + alignOffset
            if iconCount > 0 { drawIconBlock(startX: blockX) }
            let textX = blockX + iconsSlot + (iconCount > 0 ? textGap : 0)
            if dimensioned {
                drawDimensionBlock(block1, startX: textX)
            } else {
                // `textX` is the footprint start; the line (and its size box) sit
                // `inset1` in from it so the reserved box padding clears the icon.
                let sx = textX + inset1
                ctx.textPosition = CGPoint(x: sx, y: baseline)
                CTLineDraw(line, ctx)
                strokeSizeBox(sizeLine1, startX: sx, baselineY: baseline)
            }
        }

        // Optional box hugging the printable edges. Drawn last, over the padding
        // margins, so it never shrinks the text or icons. The left/right edges are
        // pulled in to the content margin so the printer's trailing cut (which
        // shaves a little off the very end of the tape) doesn't clip the box — the
        // content already survives at that margin. Top/bottom stay at the band edge
        // (the tape-width direction isn't affected by the length cut).
        if border {
            let lw = max(2, (CGFloat(height) * 0.035).rounded())
            let hInset = edgeMargin + lw / 2   // outer edge at the end margin, outside the padding
            ctx.setStrokeColor(gray: 0, alpha: 1)
            ctx.setLineWidth(lw)
            ctx.stroke(CGRect(x: hInset, y: lw / 2,
                              width: CGFloat(width) - 2 * hInset, height: CGFloat(height) - lw))
        }

        guard let raw = ctx.data else {
            return RenderedLabel(rasterLines: [], preview: NSImage(), lengthDots: 0)
        }
        let buffer = raw.bindMemory(to: UInt8.self, capacity: pxWidth * pxHeight)

        // One raster line per raster-grid column (2× the columns in high-res). Each
        // cell averages its ss×ss block of supersampled pixels, then thresholds —
        // coverage-based, so edges land more accurately than point-sampling. The
        // grayscale context is bottom-up, so native row 0 is the bottom of the image.
        let blockThreshold = 128 * ss * ss
        var rasterLines: [[UInt8]] = []
        rasterLines.reserveCapacity(rasterWidth)
        for column in 0..<rasterWidth {
            let x = reverseLength ? (rasterWidth - 1 - column) : column
            var raster = [UInt8](repeating: 0, count: RasterEncoder.bytesPerLine)
            for row in 0..<height {
                var sum = 0
                let baseX = x * ss
                for dy in 0..<ss {
                    let rowBase = (row * ss + dy) * pxWidth + baseX
                    for dx in 0..<ss { sum += Int(buffer[rowBase + dx]) }
                }
                if sum < blockThreshold {                        // mostly-dark cell → print
                    let placed = flipAcross ? (height - 1 - row) : row
                    RasterEncoder.setPin(&raster, tape.offset + placed)
                }
            }
            rasterLines.append(raster)
        }

        // Preview is displayed at the native (1:1) size, so the 2× length stretch is
        // squeezed back to the correct proportion. lengthDots stays in 180-dpi units
        // for the length readout; rasterLines carries the actual (2×) line count.
        let preview = ctx.makeImage().map {
            NSImage(cgImage: $0, size: NSSize(width: width, height: height))
        } ?? NSImage()
        return RenderedLabel(rasterLines: rasterLines, preview: preview, lengthDots: width)
    }

    private static func makeFont(_ family: String?, size: CGFloat, heavier: Bool = false) -> NSFont {
        // A chosen family renders at a bold (body) or heavy (size / bold-all) weight —
        // NSFontManager picks the closest available face, so fonts with fewer weights
        // degrade gracefully. Unknown families fall back to the system font.
        if let family {
            let weight = heavier ? 12 : 9   // NSFontManager 0–15 scale: 9 ≈ bold, 12 ≈ heavy
            if let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: weight, size: size) {
                return font
            }
        }
        return NSFont.systemFont(ofSize: size, weight: heavier ? .black : .bold)
    }

    /// Label-friendly font families offered in the UI, filtered to those installed.
    /// The system font (the default) is presented separately as "System".
    static let fontFamilies: [String] = {
        let candidates = ["Avenir Next", "Helvetica Neue", "Futura", "Gill Sans",
                          "Arial Rounded MT Bold", "Menlo", "Courier New",
                          "Georgia", "Times New Roman", "Impact", "Arial"]
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return candidates.filter(installed.contains)
    }()
}
