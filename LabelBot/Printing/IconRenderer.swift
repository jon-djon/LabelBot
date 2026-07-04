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
        ctx.setFillColor(gray: 0, alpha: 1)

        switch type {
        case .none:
            break
        case .hex: // hex socket: black disc with a hexagonal hole
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(polygon(center: c, radius: r * 0.6, sides: 6, rotation: .pi / 6))
            ctx.fillPath()
        case .externalHex: // bolt head from the top: solid hexagon
            ctx.addPath(polygon(center: c, radius: r, sides: 6, rotation: .pi / 6))
            ctx.fillPath()
        case .torx:
            ctx.addPath(star(center: c, outer: r, inner: r * 0.7, points: 6, rotation: -.pi / 2))
            ctx.fillPath()
        case .securityTorx: // torx with a center pin
            ctx.addPath(star(center: c, outer: r, inner: r * 0.7, points: 6, rotation: -.pi / 2))
            ctx.fillPath()
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6))
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.14, y: c.y - r * 0.14, width: r * 0.28, height: r * 0.28))
        case .phillips:
            let t = r * 0.34
            ctx.fill(CGRect(x: c.x - t, y: c.y - r, width: 2 * t, height: 2 * r))
            ctx.fill(CGRect(x: c.x - r, y: c.y - t, width: 2 * r, height: 2 * t))
        case .pozidriv:
            let t = r * 0.30
            ctx.fill(CGRect(x: c.x - t, y: c.y - r, width: 2 * t, height: 2 * r))
            ctx.fill(CGRect(x: c.x - r, y: c.y - t, width: 2 * r, height: 2 * t))
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: .pi / 4)
            let s = r * 0.15
            ctx.fill(CGRect(x: -s, y: -r * 0.7, width: 2 * s, height: r * 1.4))
            ctx.fill(CGRect(x: -r * 0.7, y: -s, width: r * 1.4, height: 2 * s))
            ctx.restoreGState()
        case .robertson:
            let s = r * 0.8
            ctx.fill(CGRect(x: c.x - s, y: c.y - s, width: 2 * s, height: 2 * s))
        case .slotted:
            let h = r * 0.3
            ctx.fill(CGRect(x: c.x - r, y: c.y - h, width: 2 * r, height: 2 * h))
        }
    }

    // MARK: - Head icons (side profile)

    static func drawHead(_ type: HeadType, threadKind: ThreadKind = .machine,
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
        func shaft() {
            guard threadKind == .wood else {
                ctx.fill(CGRect(x: cx - shaftW / 2, y: bottom, width: shaftW, height: shaftTop - bottom))
                return
            }
            // Wood screw: taper the shaft to a point.
            let tip = (shaftTop - bottom) * 0.35
            ctx.fill(CGRect(x: cx - shaftW / 2, y: bottom + tip, width: shaftW, height: shaftTop - bottom - tip))
            let p = CGMutablePath()
            p.move(to: CGPoint(x: cx - shaftW / 2, y: bottom + tip))
            p.addLine(to: CGPoint(x: cx + shaftW / 2, y: bottom + tip))
            p.addLine(to: CGPoint(x: cx, y: bottom))
            p.closeSubpath()
            ctx.addPath(p)
            ctx.fillPath()
        }

        switch type {
        case .none:
            break
        case .grub: // headless set screw: a threaded cylinder
            ctx.fill(CGRect(x: cx - shaftW / 2, y: bottom, width: shaftW, height: h * 0.92))
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

    // MARK: - Category icons

    /// Hex nut, top view: a hexagon with a round hole.
    static func drawNut(into ctx: CGContext, rect: CGRect) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.addPath(polygon(center: c, radius: r, sides: 6, rotation: 0))
        ctx.fillPath()
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.5, width: r, height: r))
    }

    /// Threaded insert, side view: a barrel with a bore and knurl rings.
    static func drawInsert(into ctx: CGContext, rect: CGRect) {
        ctx.setFillColor(gray: 0, alpha: 1)
        let barrelW = rect.width * 0.62
        let x = rect.midX - barrelW / 2
        ctx.fill(CGRect(x: x, y: rect.minY, width: barrelW, height: rect.height))

        ctx.setFillColor(gray: 1, alpha: 1)
        let boreW = barrelW * 0.34
        ctx.fill(CGRect(x: rect.midX - boreW / 2, y: rect.minY + rect.height * 0.06,
                        width: boreW, height: rect.height * 0.88))
        let rings = 4
        for i in 0..<rings {
            let ly = rect.minY + rect.height * (0.14 + 0.72 * CGFloat(i) / CGFloat(rings - 1))
            ctx.fill(CGRect(x: x, y: ly, width: barrelW, height: rect.height * 0.05))
        }
    }

    // MARK: - Imported images

    /// Directory the user drops icon files into (png / pdf / svg), named e.g.
    /// `drive-hex.png` or `head-pan.png`.
    static var importDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LabelBot/Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Loads an imported icon by file stem (without extension), trying common formats.
    static func importedImage(stem: String) -> CGImage? {
        for ext in ["svg", "pdf", "png"] {
            let url = importDirectory.appendingPathComponent("\(stem).\(ext)")
            guard FileManager.default.fileExists(atPath: url.path),
                  let image = NSImage(contentsOf: url) else { continue }
            var rect = CGRect(origin: .zero, size: image.size)
            if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                return cg
            }
        }
        return nil
    }

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
