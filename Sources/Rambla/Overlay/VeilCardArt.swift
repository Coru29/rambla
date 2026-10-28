import AppKit
import QuartzCore

/// How a window looks on the veil while the strips change (`LevelTransitionController`): a card the size of the window,
/// in its app's color, with a title bar and the app's icon and name in the middle, as the overview draws its
/// miniatures. Plain layers, so that Core Animation moves them.
enum VeilCardArt {
    static let radius: CGFloat = 14
    static let titleBar: CGFloat = 28

    /// A card of `size` points, its icon and text drawn for `scale` pixels per point.
    static func layer(size: CGSize, app: String, title: String, icon: NSImage?, tint: NSColor,
                      scale: CGFloat) -> CALayer {
        let bounds = CGRect(origin: .zero, size: size)
        let card = CALayer()
        card.bounds = bounds
        card.shadowColor = NSColor.black.cgColor
        card.shadowOpacity = 0.4
        card.shadowRadius = 24
        card.shadowOffset = CGSize(width: 0, height: -12)
        card.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)

        let body = CALayer()
        body.frame = bounds
        body.cornerRadius = radius
        body.cornerCurve = .continuous
        body.masksToBounds = true
        body.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
        // Drawn over the sublayers.
        body.borderWidth = 1
        body.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
        card.addSublayer(body)

        let color = CAGradientLayer()
        color.frame = bounds
        color.colors = [tint.cgColor, tint.withAlphaComponent(0.62).cgColor]
        color.startPoint = CGPoint(x: 0.5, y: 1)
        color.endPoint = CGPoint(x: 0.5, y: 0)
        body.addSublayer(color)

        let bar = CALayer()
        bar.frame = CGRect(x: 0, y: size.height - titleBar, width: size.width, height: titleBar)
        bar.backgroundColor = NSColor(white: 0, alpha: 0.32).cgColor
        body.addSublayer(bar)
        let lights = [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                      NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                      NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)]
        for (index, color) in lights.enumerated() {
            let light = CALayer()
            light.frame = CGRect(x: 12 + CGFloat(index) * 20, y: (titleBar - 12) / 2, width: 12, height: 12)
            light.cornerRadius = 6
            light.backgroundColor = color.cgColor
            bar.addSublayer(light)
        }
        if size.width > 200 {
            let name = text(title.isEmpty ? app : title, size: 13, weight: .medium, alpha: 0.88, scale: scale)
            name.frame = CGRect(x: 76, y: (titleBar - 17) / 2, width: size.width - 152, height: 17)
            bar.addSublayer(name)
        }

        // The icon, and the app's name under it when there is room, in the middle of what is under the title bar.
        let room = CGSize(width: size.width, height: max(0, size.height - titleBar))
        let side = max(0, min(128, room.width * 0.3, room.height * 0.3))
        let label: CGFloat = 20, spacing: CGFloat = 12
        let named = !app.isEmpty && room.height > side + spacing + label + 40 && room.width > 120
        let top = (room.height + side + (named ? spacing + label : 0)) / 2
        if let icon, side > 0, let image = bitmap(of: icon, side: side, scale: scale) {
            let picture = CALayer()
            picture.frame = CGRect(x: (size.width - side) / 2, y: top - side, width: side, height: side)
            picture.contents = image
            picture.contentsScale = scale
            picture.contentsGravity = .resizeAspect
            picture.shadowColor = NSColor.black.cgColor
            picture.shadowOpacity = 0.35
            picture.shadowRadius = 8
            picture.shadowOffset = CGSize(width: 0, height: -4)
            body.addSublayer(picture)
        }
        if named {
            let name = text(app, size: 15, weight: .semibold, alpha: 1, scale: scale)
            name.frame = CGRect(x: 16, y: top - side - spacing - label, width: size.width - 32, height: label)
            body.addSublayer(name)
        }
        return card
    }

    /// `icon` drawn `side` points wide for `scale` pixels per point, from its pictures that size or larger: an app's
    /// icon comes 32 points wide, and Core Animation would stretch that one.
    private static func bitmap(of icon: NSImage, side: CGFloat, scale: CGFloat) -> CGImage? {
        let pixels = max(1, Int((side * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.interpolationQuality = .high
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1,
                  respectFlipped: false, hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
        NSGraphicsContext.current = previous
        return context.makeImage()
    }

    private static func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat,
                             scale: CGFloat) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(white: 1, alpha: alpha),
        ])
        layer.alignmentMode = .center
        layer.truncationMode = .end
        layer.isWrapped = false
        layer.contentsScale = scale
        return layer
    }
}
