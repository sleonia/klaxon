// Renders Resources/AppIcon.icns from the Klaxon logo (same artwork as site/favicon.svg):
// a white stroked horn on flat #FF2D1A, framed in the standard macOS 824/1024 icon grid.
// Usage: swift Scripts/make-appicon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

import AppKit
import CoreGraphics

let red = CGColor(red: 1.0, green: 0x2D / 255.0, blue: 0x1A / 255.0, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

func hornPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 4, y: 14))
    p.addLine(to: CGPoint(x: 13, y: 6))
    p.addLine(to: CGPoint(x: 13, y: 20))
    p.addLine(to: CGPoint(x: 4, y: 16))
    p.closeSubpath()
    p.move(to: CGPoint(x: 17, y: 9))
    p.addCurve(to: CGPoint(x: 17, y: 15), control1: CGPoint(x: 19, y: 11), control2: CGPoint(x: 19, y: 13))
    p.move(to: CGPoint(x: 20, y: 6))
    p.addCurve(to: CGPoint(x: 20, y: 18), control1: CGPoint(x: 23, y: 9), control2: CGPoint(x: 23, y: 15))
    return p
}

func render(pixels: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let s = CGFloat(pixels) / 1024

    let box = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil))
    ctx.setFillColor(red)
    ctx.fillPath()

    // Glyph bounding box in SVG units (paths + stroke): x 2.9…23.6, y 4.9…21.1.
    // Scale so the glyph spans 66% of the tile width, centered on the tile.
    let glyphCenter = CGPoint(x: 13.25, y: 13)
    let unit = box.width * 0.66 / 20.7
    ctx.saveGState()
    ctx.translateBy(x: box.midX, y: box.midY)
    ctx.scaleBy(x: unit, y: -unit)
    ctx.translateBy(x: -glyphCenter.x, y: -glyphCenter.y)
    ctx.addPath(hornPath())
    ctx.setStrokeColor(white)
    ctx.setLineWidth(2.2)
    ctx.setLineCap(.square)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

let iconsetURL = URL(fileURLWithPath: "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for entry in entries {
    let image = render(pixels: entry.pixels)
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: entry.pixels, height: entry.pixels)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: iconsetURL.appendingPathComponent("\(entry.name).png"))
}
print("Wrote \(entries.count) PNGs to \(iconsetURL.path)")
