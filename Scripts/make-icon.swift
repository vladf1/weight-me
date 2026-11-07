#!/usr/bin/env swift
// Renders the WeightMe app icon (light, dark and tinted variants) as 1024×1024 PNGs.
// Usage: swift Scripts/make-icon.swift WeightMe/Resources/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Smooth descending curve with a little wobble, in unit coordinates (0…1, y up).
func curve(_ t: Double) -> Double {
    0.70 - 0.42 * t + 0.035 * sin(t * 11) + 0.02 * sin(t * 23 + 1)
}

enum Variant { case light, dark, tinted }

func render(_ variant: Variant) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Background
    switch variant {
    case .light:
        let g = CGGradient(colorsSpace: space, colors: [color(0x5B5BF0), color(0x12A5B0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    case .dark:
        let g = CGGradient(colorsSpace: space, colors: [color(0x1B1D2E), color(0x0B0C14)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    case .tinted:
        ctx.setFillColor(color(0x000000))
        ctx.fill(full)
    }

    let inset = 170.0
    let plot = full.insetBy(dx: inset, dy: inset)
    func point(_ t: Double, _ y: Double) -> CGPoint {
        CGPoint(x: plot.minX + t * plot.width, y: plot.minY + y * plot.height)
    }

    // Faint grid lines
    let gridColor: CGColor = variant == .light ? color(0xFFFFFF, 0.16) : color(0xFFFFFF, 0.08)
    ctx.setStrokeColor(gridColor)
    ctx.setLineWidth(6)
    for i in 0...3 {
        let y = plot.minY + Double(i) / 3 * plot.height
        ctx.move(to: CGPoint(x: plot.minX - 30, y: y))
        ctx.addLine(to: CGPoint(x: plot.maxX + 30, y: y))
    }
    ctx.strokePath()

    // Scattered "readings"
    var rng = UInt64(7)
    func rand() -> Double {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Double(rng >> 33) / Double(1 << 31)
    }
    let dotColor: CGColor = switch variant {
    case .light: color(0xFFFFFF, 0.55)
    case .dark: color(0x8EA2FF, 0.55)
    case .tinted: color(0xFFFFFF, 0.45)
    }
    ctx.setFillColor(dotColor)
    for i in 0..<16 {
        let t = (Double(i) + 0.5) / 16
        let y = curve(t) + (rand() - 0.5) * 0.16
        let p = point(t, y)
        ctx.fillEllipse(in: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26))
    }

    // Trend line
    let path = CGMutablePath()
    let steps = 200
    for s in 0...steps {
        let t = Double(s) / Double(steps)
        let p = point(t, curve(t))
        if s == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    if variant == .dark {
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        let g = CGGradient(colorsSpace: space, colors: [color(0x7C83FF), color(0x2DD4BF)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: plot.minX, y: 0), end: CGPoint(x: plot.maxX, y: 0), options: [])
    } else {
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x000000, variant == .light ? 0.18 : 0))
        ctx.setStrokeColor(color(0xFFFFFF))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // End point
    let end = point(1, curve(1))
    let ring: CGColor = variant == .dark ? color(0x2DD4BF) : color(0xFFFFFF)
    ctx.setFillColor(ring)
    ctx.fillEllipse(in: CGRect(x: end.x - 44, y: end.y - 44, width: 88, height: 88))
    ctx.setFillColor(variant == .light ? color(0x12A5B0) : color(0x0B0C14))
    ctx.fillEllipse(in: CGRect(x: end.x - 22, y: end.y - 22, width: 44, height: 44))

    return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}

write(render(.light), "AppIcon.png")
write(render(.dark), "AppIcon-Dark.png")
write(render(.tinted), "AppIcon-Tinted.png")
