#!/usr/bin/env swift
// Renders the WeightMe app icon (light, dark and tinted variants) as 1024×1024 PNGs.
// Usage: swift Scripts/make-icon.swift WeightMe/Resources/Assets.xcassets/AppIcon.appiconset
//        swift Scripts/make-icon.swift WeightMeWatch/Assets.xcassets/AppIcon.appiconset --watch
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
/// watchOS masks icons to a circle, so the drawing is pulled in from the edges.
let isWatch = CommandLine.arguments.contains("--watch")
let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The chart line in unit coordinates (0…1, y up): climbs to a bump early on, then works its way
/// down with a little wobble and ends lower than it started — what a real weight-loss chart looks like.
func curve(_ t: Double) -> Double {
    let bump = 0.34 * exp(-pow((t - 0.27) / 0.17, 2))
    return 0.46 + bump - 0.36 * t + 0.03 * sin(t * 15 + 0.6)
}

enum Variant { case light, dark, tinted }

func drawBackground(_ ctx: CGContext, _ variant: Variant) {
    let full = CGRect(x: 0, y: 0, width: size, height: size)
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
}

func render(_ variant: Variant) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!  // App Store rejects icons with alpha
    drawBackground(ctx, variant)

    // watchOS crops to a circle: draw everything smaller, around the center.
    if isWatch {
        ctx.translateBy(x: size / 2, y: size / 2)
        ctx.scaleBy(x: 0.74, y: 0.74)
        ctx.translateBy(x: -size / 2, y: -size / 2)
    }

    // MARK: Scale — a bathroom scale seen from above: a big rounded square with a display window.

    let platformRect = CGRect(x: 150, y: 150, width: 724, height: 724)
    let platformFill: CGColor = switch variant {
    case .light, .tinted: color(0xFFFFFF)
    case .dark: color(0x2A2D42)
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0x000000, variant == .light ? 0.25 : 0))
    ctx.addPath(CGPath(roundedRect: platformRect, cornerWidth: 170, cornerHeight: 170, transform: nil))
    ctx.setFillColor(platformFill)
    ctx.fillPath()
    ctx.restoreGState()

    // Display window near the far edge.
    let display = CGRect(x: size / 2 - 130, y: 700, width: 260, height: 82)
    ctx.addPath(CGPath(roundedRect: display, cornerWidth: 30, cornerHeight: 30, transform: nil))
    let displayColor: CGColor = switch variant {
    case .light: color(0x4F63E8)
    case .dark: color(0x0E0F18)
    case .tinted: color(0x000000)
    }
    ctx.setFillColor(displayColor)
    ctx.fillPath()

    // MARK: Chart, drawn on the platform

    let plot = CGRect(x: 250, y: 255, width: 524, height: 360)
    func point(_ t: Double, _ y: Double) -> CGPoint {
        CGPoint(x: plot.minX + t * plot.width, y: plot.minY + y * plot.height)
    }
    let lineColors: [CGColor] = switch variant {
    case .light: [color(0x5B5BF0), color(0x12A5B0)]
    case .dark: [color(0x7C83FF), color(0x2DD4BF)]
    case .tinted: [color(0x000000), color(0x000000)]
    }

    // Scattered "readings" around the line.
    var rng = UInt64(11)
    func rand() -> Double {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Double(rng >> 33) / Double(1 << 31)
    }
    let dotColor: CGColor = switch variant {
    case .light: color(0x5B5BF0, 0.28)
    case .dark: color(0x8EA2FF, 0.45)
    case .tinted: color(0x000000, 0.35)
    }
    ctx.setFillColor(dotColor)
    for i in 0..<13 {
        let t = (Double(i) + 0.5) / 13
        let y = curve(t) + (rand() - 0.5) * 0.22
        let p = point(t, y)
        ctx.fillEllipse(in: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24))
    }

    let path = CGMutablePath()
    let steps = 240
    for s in 0...steps {
        let t = Double(s) / Double(steps)
        let p = point(t, curve(t))
        if s == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(40)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: lineColors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: plot.minX, y: 0), end: CGPoint(x: plot.maxX, y: 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // End point: a ring in the line's end color.
    let end = point(1, curve(1))
    ctx.setFillColor(lineColors[1])
    ctx.fillEllipse(in: CGRect(x: end.x - 38, y: end.y - 38, width: 76, height: 76))
    ctx.setFillColor(platformFill)
    ctx.fillEllipse(in: CGRect(x: end.x - 17, y: end.y - 17, width: 34, height: 34))

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
if !isWatch {
    write(render(.dark), "AppIcon-Dark.png")
    write(render(.tinted), "AppIcon-Tinted.png")
}
