// Generates Packaging/AppIcon.icns: sunset over the Rambla of Montevideo (the promenade, a street lamp,
// the river) with a strip of windows above it. Full-bleed artwork; macOS 26 applies the squircle mask itself.
// Usage: swift scripts/make-icon.swift   (from the package root)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ stops: [(UInt32, CGFloat)], alpha: CGFloat = 1) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map { color($0.0, alpha) } as CFArray,
               locations: stops.map(\.1))!
}

/// CoreGraphics coordinates: origin bottom-left, 1024×1024. Seen from the promenade: the Rambla and a street
/// lamp in front, the Río de la Plata with the sun setting, and the strip of windows above.
func draw(_ ctx: CGContext) {
    let horizon: CGFloat = 418
    let shore: CGFloat = 214

    // Sky: dusk purple at the top, warm orange at the horizon.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: horizon, width: 1024, height: 1024 - horizon))
    ctx.drawLinearGradient(gradient([(0xFFB45E, 0), (0xF2785F, 0.2), (0xB0407A, 0.52), (0x3A1E63, 0.84), (0x1D1442, 1)]),
                           start: CGPoint(x: 512, y: horizon), end: CGPoint(x: 512, y: 1024), options: [])
    // Setting sun with a soft glow, half under the horizon.
    let sun = CGPoint(x: 512, y: horizon + 4)
    ctx.drawRadialGradient(gradient([(0xFFE3A1, 0), (0xFFB45E, 0.35), (0xF2785F, 1)], alpha: 0.55),
                           startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 320, options: [])
    ctx.setFillColor(color(0xFFE8B0))
    ctx.fillEllipse(in: CGRect(x: sun.x - 118, y: sun.y - 118, width: 236, height: 236))
    ctx.restoreGState()

    // Río de la Plata, with the sun's reflection.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: shore - 40, width: 1024, height: horizon - shore + 40))
    ctx.drawLinearGradient(gradient([(0x163A6B, 0), (0x255A93, 0.7), (0x3A76A8, 1)]),
                           start: CGPoint(x: 512, y: shore), end: CGPoint(x: 512, y: horizon), options: [])
    let streaks: [(y: CGFloat, w: CGFloat, a: CGFloat)] = [(388, 240, 0.85), (346, 176, 0.6), (304, 112, 0.4)]
    for s in streaks {
        let r = CGRect(x: 512 - s.w / 2, y: s.y, width: s.w, height: 11)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
        ctx.setFillColor(color(0xFFD08A, s.a))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // The promenade in front: a gently curved edge (the bay), the railing on top of the wall.
    func edge(_ x: CGFloat) -> CGFloat {
        // Quadratic Bézier from (0, shore+16) via (512, shore-36) to (1024, shore+16), as y(x).
        let t = x / 1024
        return (1 - t) * (1 - t) * (shore + 16) + 2 * (1 - t) * t * (shore - 36) + t * t * (shore + 16)
    }
    let promenade = CGMutablePath()
    promenade.move(to: CGPoint(x: -4, y: edge(0)))
    promenade.addQuadCurve(to: CGPoint(x: 1028, y: edge(1024)), control: CGPoint(x: 512, y: shore - 36))
    promenade.addLine(to: CGPoint(x: 1028, y: -4))
    promenade.addLine(to: CGPoint(x: -4, y: -4))
    promenade.closeSubpath()
    ctx.saveGState()
    ctx.addPath(promenade)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0x9E7E5E, 0), (0xC9AE88, 0.7), (0xE6D3B3, 1)]),
                           start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: shore + 16), options: [])
    ctx.restoreGState()

    // One street lamp (farola) on the promenade.
    for lampX: CGFloat in [168] {
        let base = edge(lampX) - 70
        ctx.setFillColor(color(0x24173F))
        ctx.fill(CGRect(x: lampX - 7, y: base, width: 14, height: 300))
        ctx.fill(CGRect(x: lampX - 18, y: base, width: 36, height: 16))
        let lamp = CGPoint(x: lampX, y: base + 318)
        ctx.drawRadialGradient(gradient([(0xFFE7A8, 0), (0xFFB45E, 1)], alpha: 0.75), startCenter: lamp, startRadius: 0,
                               endCenter: lamp, endRadius: 58, options: [])
        ctx.setFillColor(color(0xFFF1C9))
        ctx.fillEllipse(in: CGRect(x: lamp.x - 19, y: lamp.y - 19, width: 38, height: 38))
    }

    // The strip of windows over the river: the focused one in the middle, the right one scrolling off.
    let windows: [(CGRect, CGFloat)] = [
        (CGRect(x: 56, y: 598, width: 272, height: 300), 0.62),
        (CGRect(x: 366, y: 572, width: 324, height: 352), 0.97),
        (CGRect(x: 728, y: 598, width: 330, height: 300), 0.62),
    ]
    for (rect, alpha) in windows {
        let path = CGPath(roundedRect: rect, cornerWidth: 42, cornerHeight: 42, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 34, color: color(0x120A2A, 0.45))
        ctx.addPath(path)
        ctx.setFillColor(color(0xFFF8F0, alpha))
        ctx.fillPath()
        ctx.restoreGState()
        for i in 0..<3 {
            let dot = CGRect(x: rect.minX + 32 + CGFloat(i) * 32, y: rect.maxY - 54, width: 18, height: 18)
            ctx.setFillColor(color(0x8A3F6E, alpha * 0.45))
            ctx.fillEllipse(in: dot)
        }
    }
}

/// Menu bar template icon on an 18×18 pt canvas: three windows standing on the promenade (the focused one
/// filled) over a small wave of the river. Black on transparent; macOS tints template images for light and
/// dark menu bars.
func drawMenuBarIcon(_ ctx: CGContext) {
    let black = color(0x000000)
    ctx.setStrokeColor(black)
    ctx.setFillColor(black)
    ctx.setLineWidth(1.2)
    for rect in [CGRect(x: 1.1, y: 7.1, width: 4.6, height: 6.6), CGRect(x: 12.3, y: 7.1, width: 4.6, height: 6.6)] {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 1, cornerHeight: 1, transform: nil))
        ctx.strokePath()
    }
    ctx.addPath(CGPath(roundedRect: CGRect(x: 6.6, y: 6.5, width: 4.8, height: 9), cornerWidth: 1.1, cornerHeight: 1.1, transform: nil))
    ctx.fillPath()
    // The promenade the windows stand on, and the river's wave below it.
    ctx.setLineWidth(1.2)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 0.8, y: 5))
    ctx.addLine(to: CGPoint(x: 17.2, y: 5))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 1.2, y: 2.2))
    var x: CGFloat = 1.2
    while x <= 16.8 {
        ctx.addLine(to: CGPoint(x: x, y: 2.2 + 0.8 * sin((x - 1.2) / 15.6 * 4 * .pi)))
        x += 0.2
    }
    ctx.strokePath()
}

func templatePNG(points: CGFloat, scale: CGFloat) -> Data {
    let pixels = Int(points * scale)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    drawMenuBarIcon(ctx)
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
    CGImageDestinationFinalize(dest)
    return data as Data
}

func png(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(ctx)
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try fm.createDirectory(atPath: "Packaging", withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", "Packaging/AppIcon.icns", iconset.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
try png(size: 512).write(to: URL(fileURLWithPath: "Packaging/AppIcon-preview.png"))
try templatePNG(points: 18, scale: 1).write(to: URL(fileURLWithPath: "Packaging/MenuBarIcon.png"))
try templatePNG(points: 18, scale: 2).write(to: URL(fileURLWithPath: "Packaging/MenuBarIcon@2x.png"))
print("Packaging/AppIcon.icns")
