// Generates Packaging/AppIcon.icns and the menu bar icon. Uruguay's colors: a celeste sky, white windows
// in a row (like the flag's stripes) on the line of the rambla, and the golden Sol de Mayo rising behind
// the focused one. Full-bleed artwork; macOS 26 applies the squircle mask itself.
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

/// CoreGraphics coordinates: origin bottom-left, 1024×1024.
func draw(_ ctx: CGContext) {
    let celeste: UInt32 = 0x4FADE3, celesteDeep: UInt32 = 0x3593D2, white: UInt32 = 0xFFFFFF, gold: UInt32 = 0xFCD116

    // Celeste sky, barely deeper at the bottom.
    ctx.drawLinearGradient(gradient([(celesteDeep, 0), (celeste, 1)]),
                           start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: 1024), options: [])

    // Sol de Mayo: a disc with sixteen rays, alternating long and short, rising behind the focused window.
    let sun = CGPoint(x: 512, y: 676)
    ctx.setFillColor(color(gold))
    for i in 0..<16 {
        let angle = CGFloat(i) * .pi / 8
        let length: CGFloat = i % 2 == 0 ? 178 : 146
        let half: CGFloat = 0.075
        let base: CGFloat = 96
        ctx.move(to: CGPoint(x: sun.x + cos(angle - half) * base, y: sun.y + sin(angle - half) * base))
        ctx.addLine(to: CGPoint(x: sun.x + cos(angle) * length, y: sun.y + sin(angle) * length))
        ctx.addLine(to: CGPoint(x: sun.x + cos(angle + half) * base, y: sun.y + sin(angle + half) * base))
        ctx.closePath()
    }
    ctx.fillPath()
    ctx.fillEllipse(in: CGRect(x: sun.x - 104, y: sun.y - 104, width: 208, height: 208))

    // Three white windows in a row; the right one runs off the edge, like the strip.
    let windows: [(CGRect, CGFloat)] = [
        (CGRect(x: 76, y: 288, width: 254, height: 312), 0.74),
        (CGRect(x: 366, y: 262, width: 292, height: 362), 1.0),
        (CGRect(x: 694, y: 288, width: 380, height: 312), 0.74),
    ]
    for (rect, alpha) in windows {
        let path = CGPath(roundedRect: rect, cornerWidth: 40, cornerHeight: 40, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x175E96, 0.28))
        ctx.addPath(path)
        ctx.setFillColor(color(white, alpha))
        ctx.fillPath()
        ctx.restoreGState()
        for i in 0..<3 {
            let dot = CGRect(x: rect.minX + 30 + CGFloat(i) * 30, y: rect.maxY - 50, width: 17, height: 17)
            ctx.setFillColor(color(celesteDeep, 0.55 * alpha))
            ctx.fillEllipse(in: dot)
        }
    }

    // The rambla: one white line under the windows.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 76, y: 184, width: 872, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(color(white, 0.92))
    ctx.fillPath()
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
