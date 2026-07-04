//
//  IconRenderer.swift
//  LabelBot
//
//  Draws fastener drive/head icons as vector shapes into a Core Graphics context,
//  or draws user-supplied images from the "Imported" icons folder.
//
//  All drawing happens in the bottom-up coordinate space of the label's grayscale
//  context (same space text is drawn in): +y is up, so head profiles sit with the
//  shaft at the bottom of the rect and the head at the top.
//

import Foundation
import CoreGraphics
import AppKit

enum IconRenderer {

    // MARK: - Drive icons (top view)

    static func drawDrive(_ type: DriveType, into ctx: CGContext, rect: CGRect) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2

        switch type {
        case .none:
            return
        case .externalHex: // bolt head from the top: solid hexagon, no head disc
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.addPath(polygon(center: c, radius: r, sides: 6, rotation: .pi / 6))
            ctx.fillPath()
        default:
            // Screw head seen from the top: a black disc with the drive recess cut
            // out in white.
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            let recess = r * 0.6
            fillDriveCut(type, center: c, radius: recess, cutRadius: r / recess, into: ctx)
        }
    }

    // MARK: - Head icons (side profile)

    static func drawHead(_ type: HeadType, threadKind: ThreadKind = .machine,
                         threaded: Bool = true,
                         orientation: ScrewOrientation = .vertical,
                         into ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // Horizontal: rotate the whole profile 90° about the cell center so the
        // head lies on the left and the tip points right.
        if orientation == .horizontal {
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: .pi / 2)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
        }
        ctx.setFillColor(gray: 0, alpha: 1)
        let cx = rect.midX
        let bottom = rect.minY
        let top = rect.maxY
        let h = rect.height
        let shaftW = rect.width * 0.34
        let headW = rect.width * 0.82
        let shaftTop = bottom + h * 0.5
        // A shaft column: a plain rectangle, or a triangle-threaded (sawtooth-edged)
        // column when `threaded`. Crests reach the full width, roots pull inward.
        func column(from yb: CGFloat, to yt: CGFloat, width w: CGFloat) {
            ctx.setFillColor(gray: 0, alpha: 1)
            guard threaded else {
                ctx.fill(CGRect(x: cx - w / 2, y: yb, width: w, height: yt - yb))
                return
            }
            let half = w / 2
            let root = half - w * 0.14
            let n = max(4, Int(((yt - yb) / (w * 0.30)).rounded()))
            let pitch = (yt - yb) / CGFloat(n)
            var right: [CGPoint] = [CGPoint(x: cx + root, y: yb)]
            for i in 0..<n {
                let y0 = yb + CGFloat(i) * pitch
                right.append(CGPoint(x: cx + half, y: y0 + pitch / 2))
                right.append(CGPoint(x: cx + root, y: y0 + pitch))
            }
            let path = CGMutablePath()
            path.move(to: right[0])
            for p in right.dropFirst() { path.addLine(to: p) }
            for p in right.reversed() { path.addLine(to: CGPoint(x: 2 * cx - p.x, y: p.y)) }
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        }
        func shaft() {
            guard threadKind == .wood else {
                column(from: bottom, to: shaftTop, width: shaftW)
                return
            }
            // Wood screw: threaded (or plain) column above a pointed tip.
            let tip = (shaftTop - bottom) * 0.35
            column(from: bottom + tip, to: shaftTop, width: shaftW)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: cx - shaftW / 2, y: bottom + tip))
            p.addLine(to: CGPoint(x: cx + shaftW / 2, y: bottom + tip))
            p.addLine(to: CGPoint(x: cx, y: bottom))
            p.closeSubpath()
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.addPath(p)
            ctx.fillPath()
        }

        switch type {
        case .none:
            break
        case .grub: // headless set screw: a threaded cylinder
            column(from: bottom, to: bottom + h * 0.92, width: shaftW)
        case .socketCap:
            shaft()
            ctx.fill(CGRect(x: cx - headW * 0.4, y: shaftTop, width: headW * 0.8, height: top - shaftTop))
        case .pan:
            shaft()
            ctx.addPath(dome(cx: cx, base: shaftTop, halfWidth: headW / 2, height: top - shaftTop, fullness: 0.85))
            ctx.fillPath()
        case .button:
            shaft()
            ctx.addPath(dome(cx: cx, base: shaftTop, halfWidth: headW / 2, height: (top - shaftTop) * 0.7, fullness: 1.0))
            ctx.fillPath()
        case .countersunk: // cone: wide flat top tapering into the shaft
            let p = CGMutablePath()
            p.move(to: CGPoint(x: cx - headW / 2, y: top))
            p.addLine(to: CGPoint(x: cx + headW / 2, y: top))
            p.addLine(to: CGPoint(x: cx + shaftW / 2, y: shaftTop))
            p.addLine(to: CGPoint(x: cx - shaftW / 2, y: shaftTop))
            p.closeSubpath()
            ctx.addPath(p)
            ctx.fillPath()
            shaft()
        case .hex:
            shaft()
            let hw = headW * 0.5
            let chamfer = (top - shaftTop) * 0.3
            let p = CGMutablePath()
            p.move(to: CGPoint(x: cx - hw, y: shaftTop))
            p.addLine(to: CGPoint(x: cx + hw, y: shaftTop))
            p.addLine(to: CGPoint(x: cx + hw, y: top - chamfer))
            p.addLine(to: CGPoint(x: cx + hw * 0.6, y: top))
            p.addLine(to: CGPoint(x: cx - hw * 0.6, y: top))
            p.addLine(to: CGPoint(x: cx - hw, y: top - chamfer))
            p.closeSubpath()
            ctx.addPath(p)
            ctx.fillPath()
        case .flangeHex:
            shaft()
            let flangeH = (top - shaftTop) * 0.22
            ctx.fill(CGRect(x: cx - headW / 2, y: shaftTop, width: headW, height: flangeH))
            let hw = headW * 0.42
            let base = shaftTop + flangeH
            ctx.fill(CGRect(x: cx - hw, y: base, width: 2 * hw, height: top - base))
        }
    }

    // MARK: - Integrated bolt icon (gflabel "webbolt" style)

    /// A single bolt silhouette: a zig-zag threaded body on one side and a head
    /// on the other, with the drive shape cut into the head face. Proportions and
    /// layout follow ndevenish/gflabel's `webbolt` fragment (BSD-3), reimplemented
    /// here in Core Graphics. Drawn lengthwise (head trailing); `orientation`
    /// rotates it upright.
    static func drawBolt(head: HeadType, drive: DriveType, threadKind: ThreadKind = .machine,
                         threaded: Bool = true,
                         orientation: ScrewOrientation = .horizontal,
                         into ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if orientation == .vertical {
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: .pi / 2)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
        }

        // gflabel: 15 wide for 12 tall → width = 1.456 * height.
        let gH = min(rect.height, rect.width / 1.456) * 0.98
        let width = 1.456 * gH
        let bodyW = 0.856 * gH
        let headW = width - bodyW
        let threadDepth = 0.0707 * gH
        let nThreads = 6
        let x0 = -width / 2
        let xHead = bodyW - width / 2
        let pitch = bodyW / CGFloat(nThreads)
        let tip = gH / 4 + threadDepth
        let hh = gH / 2
        let cx = rect.midX, cy = rect.midY
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x, y: cy + y) }

        // Upper outline, left end → body → head, ending on the axis at the right.
        var top: [CGPoint]
        if threaded {
            top = [P(x0, 0)]   // pointed thread start
            for i in 0..<nThreads {
                let xi = x0 + CGFloat(i) * pitch
                top.append(P(xi, tip - threadDepth))
                top.append(P(xi + pitch / 2, tip))
            }
            top.append(P(xHead, tip - threadDepth))
        } else {
            let bodyHalf = tip - threadDepth / 2   // smooth cylinder at the mean radius
            top = [P(x0, bodyHalf), P(xHead, bodyHalf)]
        }

        switch head {
        case .countersunk:
            top.append(P(width / 2, hh))
            top.append(P(width / 2, 0))
        case .socketCap, .hex, .flangeHex:
            top.append(P(xHead, hh))
            top.append(P(width / 2, hh))
            top.append(P(width / 2, 0))
        case .pan:
            let r = 0.167 * gH
            top.append(P(xHead, hh))
            top.append(P(width / 2 - r, hh))
            appendArc(&top, center: P(width / 2 - r, hh - r), radius: r, from: .pi / 2, to: 0)
            top.append(P(width / 2, 0))
        case .button:
            top.append(P(xHead, hh))
            appendArc(&top, center: P(width / 2 - hh, 0), radius: hh, from: .pi / 2, to: 0)
            top.append(P(width / 2, 0))
        case .grub, .none:
            top.append(P(xHead, 0))
        }

        // Close by mirroring across the centerline (the left/right ends on the axis
        // just add harmless zero-length segments; the smooth end closes vertically).
        let path = CGMutablePath()
        path.move(to: top[0])
        for p in top.dropFirst() { path.addLine(to: p) }
        for p in top.reversed() {
            path.addLine(to: CGPoint(x: p.x, y: 2 * cy - p.y))
        }
        path.closeSubpath()
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.addPath(path)
        ctx.fillPath()

        // Cut the drive into the head face (white on black).
        let hasHead = head != .none && head != .grub
        if hasHead {
            let fudge = threadDepth / 2
            let center = P(width / 2 - headW / 2 - fudge, 0)
            let r = headW * 0.9 / 2
            let cutRadius = (headW / 2) / (headW * 0.9 / 2)   // slot overshoot to reach the edge
            fillDriveCut(drive, center: center, radius: r, cutRadius: cutRadius, into: ctx)
        }
    }

    /// Fills the drive recess as white shapes over the black head. Geometry mirrors
    /// gflabel's `drive_shape` (unit shapes scaled by the head diameter).
    private static func fillDriveCut(_ drive: DriveType, center c: CGPoint,
                                     radius r: CGFloat, cutRadius: CGFloat, into ctx: CGContext) {
        let d = 2 * r
        switch drive {
        case .none, .externalHex:
            break
        case .phillips:
            fillRect(ctx, c, d, 0.2 * d, 0)
            fillRect(ctx, c, 0.2 * d, d, 0)
            fillRect(ctx, c, 0.4 * d, 0.4 * d, .pi / 4)
        case .pozidriv:
            fillRect(ctx, c, d, 0.2 * d, 0)
            fillRect(ctx, c, 0.2 * d, d, 0)
            fillRect(ctx, c, 0.4 * d, 0.4 * d, .pi / 4)
            fillRect(ctx, c, d, 0.1 * d, .pi / 4)
            fillRect(ctx, c, d, 0.1 * d, -.pi / 4)
        case .slotted:
            fillRect(ctx, c, cutRadius * d, 0.2 * d, 0)
        case .hex:
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(polygon(center: c, radius: 0.5 * d, sides: 6, rotation: 0))
            ctx.fillPath()
        case .robertson:
            fillRect(ctx, c, 0.6 * d, 0.6 * d, .pi / 4)
        case .torx:
            fillTorx(ctx, center: c, radius: r)
        case .securityTorx:
            fillTorx(ctx, center: c, radius: r)
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: c.x - 0.14 * d, y: c.y - 0.14 * d, width: 0.28 * d, height: 0.28 * d))
        }
    }

    private static func fillTorx(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat) {
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.addPath(star(center: c, outer: r, inner: 0.58 * r, points: 6, rotation: -.pi / 2))
        ctx.fillPath()
    }

    /// Fills a white rectangle centered at `c`, rotated by `rot` radians.
    private static func fillRect(_ ctx: CGContext, _ c: CGPoint, _ w: CGFloat, _ h: CGFloat, _ rot: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: rot)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
    }

    private static func appendArc(_ pts: inout [CGPoint], center: CGPoint, radius: CGFloat,
                                  from: CGFloat, to: CGFloat, steps: Int = 6) {
        for i in 0...steps {
            let a = from + (to - from) * CGFloat(i) / CGFloat(steps)
            pts.append(CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)))
        }
    }

    // MARK: - Category icons

    /// Hex nut, top view: a flat-top hexagon with a round hole. Hole radius 0.4× the
    /// outer radius, matching gflabel's `hexnut`.
    static func drawNut(into ctx: CGContext, rect: CGRect) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.addPath(polygon(center: c, radius: r, sides: 6, rotation: 0))
        ctx.fillPath()
        ctx.setFillColor(gray: 1, alpha: 1)
        let hole = r * 0.4
        ctx.fillEllipse(in: CGRect(x: c.x - hole, y: c.y - hole, width: 2 * hole, height: 2 * hole))
    }

    /// Flat washer, top view: a ring. Hole radius 0.55× the outer radius, matching
    /// gflabel's `washer`.
    static func drawWasher(into ctx: CGContext, rect: CGRect) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.setFillColor(gray: 1, alpha: 1)
        let hole = r * 0.55
        ctx.fillEllipse(in: CGRect(x: c.x - hole, y: c.y - hole, width: 2 * hole, height: 2 * hole))
    }

    /// Square nut, top view: a square with a round hole (gflabel `squarenut`).
    static func drawSquareNut(into ctx: CGContext, rect: CGRect) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let side = min(rect.width, rect.height)
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side))
        ctx.setFillColor(gray: 1, alpha: 1)
        let hole = side / 2 * 0.55
        ctx.fillEllipse(in: CGRect(x: c.x - hole, y: c.y - hole, width: 2 * hole, height: 2 * hole))
    }

    /// Lock washer, top view: a ring with a diagonal split cut (gflabel `lockwasher`).
    static func drawLockWasher(into ctx: CGContext, rect: CGRect) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.setFillColor(gray: 1, alpha: 1)
        let hole = r * 0.55
        ctx.fillEllipse(in: CGRect(x: c.x - hole, y: c.y - hole, width: 2 * hole, height: 2 * hole))
        // Split gap, subtracted as a slim rotated bar.
        fillRect(ctx, CGPoint(x: c.x + 0.2 * r, y: c.y + 0.775 * r), 0.275 * r, 1.55 * r, .pi / 4)
    }

    /// T-nut, side profile: a tall rounded barrel with a bore (gflabel `tnut`).
    static func drawTNut(into ctx: CGContext, rect: CGRect) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let hgt = min(rect.width, rect.height)
        let w = 0.6 * hgt
        ctx.setFillColor(gray: 0, alpha: 1)
        let barrel = CGPath(roundedRect: CGRect(x: c.x - w / 2, y: c.y - hgt / 2, width: w, height: hgt),
                            cornerWidth: hgt / 7, cornerHeight: hgt / 7, transform: nil)
        ctx.addPath(barrel)
        ctx.fillPath()
        ctx.setFillColor(gray: 1, alpha: 1)
        let hole = 0.2 * hgt
        ctx.fillEllipse(in: CGRect(x: c.x - hole, y: c.y - hole, width: 2 * hole, height: 2 * hole))
    }

    /// Dispatches to the selected nut / washer drawing.
    static func drawNutWasher(_ type: NutWasherType, into ctx: CGContext, rect: CGRect) {
        switch type {
        case .hexNut: drawNut(into: ctx, rect: rect)
        case .squareNut: drawSquareNut(into: ctx, rect: rect)
        case .washer: drawWasher(into: ctx, rect: rect)
        case .lockWasher: drawLockWasher(into: ctx, rect: rect)
        case .tNut: drawTNut(into: ctx, rect: rect)
        }
    }

    /// Threaded insert, side view: two knurled flanges around a waist, with a
    /// barrel below. Reimplements ndevenish/gflabel's `threaded_insert` fragment
    /// (BSD-3) in Core Graphics — geometry borrowed, no code copied.
    static func drawInsert(into ctx: CGContext, rect: CGRect) {
        // gflabel model space: x in [-4, 4], y in [-6.26, 3.75].
        let gW: CGFloat = 8, gH: CGFloat = 10.01
        let s = min(rect.width / gW, rect.height / gH) * 0.98
        let gcy: CGFloat = (3.75 - 6.26) / 2   // model bbox y-center
        func M(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + x * s, y: rect.midY + (y - gcy) * s)
        }

        // Spool + barrel silhouette: top flange, waist, bottom flange, barrel.
        let outline = [
            M(-4, 3.75), M(4, 3.75),
            M(4, 1.25), M(3, 1.25), M(3, -1.25), M(4, -1.25),
            M(4, -3.75), M(3, -3.75), M(3, -6.26),
            M(-3, -6.26), M(-3, -3.75), M(-4, -3.75),
            M(-4, -1.25), M(-3, -1.25), M(-3, 1.25), M(-4, 1.25),
        ]
        let path = CGMutablePath()
        path.addLines(between: outline)
        path.closeSubpath()
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.addPath(path)
        ctx.fillPath()

        // Knurl: slanted parallelogram cuts across each flange (white).
        let trap: [(CGFloat, CGFloat)] = [(-1.074, 0.65), (-0.226, 0.65), (1.074, -0.65), (0.226, -0.65)]
        let cols: [CGFloat] = [-2.4375, -0.8125, 0.8125, 2.4375]
        ctx.setFillColor(gray: 1, alpha: 1)
        for row in [-2.5, 2.5] as [CGFloat] {
            for col in cols {
                let p = CGMutablePath()
                p.addLines(between: trap.map { M($0.0 + col, $0.1 + row) })
                p.closeSubpath()
                ctx.addPath(p)
                ctx.fillPath()
            }
        }
    }

    // MARK: - Image placement

    /// Draws a CGImage into the bottom-up context, flipped so its top stays up.
    static func drawImage(_ image: CGImage, into ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    // MARK: - UI swatches

    private static var swatchCache: [String: NSImage] = [:]

    /// A cached, centered black-on-white icon swatch for use in the picker grids.
    static func swatch(key: String, draw: (CGContext, CGRect) -> Void) -> NSImage {
        if let cached = swatchCache[key] { return cached }
        let image = renderSwatch(px: 96, draw: draw)
        swatchCache[key] = image
        return image
    }

    private static func renderSwatch(px: Int, draw: (CGContext, CGRect) -> Void) -> NSImage {
        guard let (icon, aspect) = normalizedIcon(side: 128, draw: draw) else { return NSImage() }
        let gray = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                  bytesPerRow: px, space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return NSImage() }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
        let target = CGFloat(px) * 0.74
        var w = target, h = target
        if aspect >= 1 { h = target / aspect } else { w = target * aspect }
        let rect = CGRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h)
        drawImage(icon, into: ctx, rect: rect)
        return ctx.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: px / 2, height: px / 2)) } ?? NSImage()
    }

    // MARK: - Normalization

    /// Renders a drawing closure to a scratch bitmap, then crops to the tight black
    /// bounding box. Lets the caller place every icon at a common height, centered,
    /// regardless of how much of its cell each shape naturally fills.
    /// Returns the cropped image and its width/height aspect ratio.
    static func normalizedIcon(side: Int, draw: (CGContext, CGRect) -> Void) -> (image: CGImage, aspect: CGFloat)? {
        let gray = CGColorSpaceCreateDeviceGray()
        let full = CGRect(x: 0, y: 0, width: side, height: side)
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side, space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(full)
        ctx.setShouldAntialias(true)
        draw(ctx, full)
        guard let image = ctx.makeImage() else { return nil }

        // Measure the black bounding box (top-left origin).
        var buffer = [UInt8](repeating: 0, count: side * side)
        let measured = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let scan = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                       bytesPerRow: side, space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            scan.setFillColor(gray: 1, alpha: 1)
            scan.fill(full)
            scan.draw(image, in: full)
            return true
        }
        guard measured else { return nil }

        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            let row = y * side
            for x in 0..<side where buffer[row + x] < 128 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let bbox = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = image.cropping(to: bbox) else { return nil }
        return (cropped, bbox.width / bbox.height)
    }

    // MARK: - Shape helpers

    private static func polygon(center c: CGPoint, radius r: CGFloat, sides: Int, rotation: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<sides {
            let a = rotation + CGFloat(i) * 2 * .pi / CGFloat(sides)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }

    private static func star(center c: CGPoint, outer: CGFloat, inner: CGFloat, points: Int, rotation: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let n = points * 2
        for i in 0..<n {
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = rotation + CGFloat(i) * .pi / CGFloat(points)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }

    private static func dome(cx: CGFloat, base: CGFloat, halfWidth: CGFloat, height: CGFloat, fullness: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - halfWidth, y: base))
        path.addCurve(to: CGPoint(x: cx + halfWidth, y: base),
                      control1: CGPoint(x: cx - halfWidth, y: base + height * 1.3 * fullness),
                      control2: CGPoint(x: cx + halfWidth, y: base + height * 1.3 * fullness))
        path.closeSubpath()
        return path
    }
}
