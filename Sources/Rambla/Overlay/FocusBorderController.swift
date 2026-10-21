import AppKit
import RamblaCore

/// A rounded outline around the focused window: one transparent, click-through window, created on first use and
/// kept, ordered directly above the window it surrounds. The stroke lies outside the window, so it never covers
/// its content (the gap between columns has room for it).
///
/// `update` runs on every animation frame; a frame that only moved just moves the window.
@MainActor
final class FocusBorderController {
    /// Radius of the stroke's center line.
    private static let cornerRadius: CGFloat = 12
    private static let maxWidth = 24.0
    /// Below this fraction on screen (a window parked at the edge of the display) there is nothing to outline.
    private static let minimumVisibleFraction: CGFloat = 0.1
    private static let fallbackColor = NSColor(srgbRed: 0x0A / 255, green: 0x84 / 255, blue: 1, alpha: 1)

    private var overlay: (window: NSWindow, view: FocusBorderView)?
    /// The color and width the view currently draws, to re-parse and redraw only when they change.
    private var drawn: (colorHex: String, width: CGFloat)?

    func update(frame: CGRect?, windowID: WindowID?, prefs: FocusBorderPrefs) {
        let width = CGFloat(min(max(prefs.width, 0), Self.maxWidth))
        guard prefs.enabled, width > 0, let frame, let windowID, Self.isMostlyOnScreen(frame) else {
            if let window = overlay?.window, window.isVisible { window.orderOut(nil) }
            return
        }
        let (window, view) = overlay ?? makeOverlay()
        if drawn?.colorHex != prefs.colorHex || drawn?.width != width {
            drawn = (prefs.colorHex, width)
            view.configure(color: Self.color(fromHex: prefs.colorHex) ?? Self.fallbackColor, lineWidth: width,
                           cornerRadius: Self.cornerRadius)
        }
        // Whole points, like the window itself (the animator writes rounded positions).
        let axFrame = CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(),
                             width: frame.width.rounded(), height: frame.height.rounded())
        let target = Displays.cocoaRect(axFrame).insetBy(dx: -view.outset, dy: -view.outset)
        if window.frame != target { window.setFrame(target, display: false) }
        // Re-asserted on every update: the focused window can be raised again without any event reaching us.
        window.order(.above, relativeTo: Int(windowID))
    }

    private func makeOverlay() -> (window: NSWindow, view: FocusBorderView) {
        let view = FocusBorderView()
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Same level as the window it follows: only then can it sit directly above it.
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        overlay = (window, view)
        return (window, view)
    }

    private static func isMostlyOnScreen(_ axFrame: CGRect) -> Bool {
        let area = axFrame.width * axFrame.height
        guard area > 0 else { return false }
        let shown = NSScreen.screens.reduce(CGFloat(0)) { total, screen in
            let overlap = Displays.axRect(screen.frame).intersection(axFrame)
            return overlap.isNull ? total : total + overlap.width * overlap.height
        }
        return shown >= area * minimumVisibleFraction
    }

    /// "#RRGGBB" or "#RRGGBBAA" (the "#" is optional); nil for anything else.
    private static func color(fromHex hex: String) -> NSColor? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        func channel(_ shift: UInt64) -> CGFloat { CGFloat((value >> shift) & 0xFF) / 255 }
        return NSColor(srgbRed: channel(hasAlpha ? 24 : 16), green: channel(hasAlpha ? 16 : 8),
                       blue: channel(hasAlpha ? 8 : 0), alpha: hasAlpha ? channel(0) : 1)
    }
}

/// Draws the stroke. The view is larger than the window it surrounds by `outset`, and the stroke's inner edge
/// touches the window's edge.
private final class FocusBorderView: NSView {
    private var color = NSColor.systemBlue
    private var lineWidth: CGFloat = 3
    private var cornerRadius: CGFloat = 12

    /// Whole points, so the window frame stays on the pixel grid.
    var outset: CGFloat { lineWidth.rounded(.up) }

    override var isOpaque: Bool { false }

    func configure(color: NSColor, lineWidth: CGFloat, cornerRadius: CGFloat) {
        self.color = color
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // The window is transparent: clear what an earlier, differently sized stroke left behind.
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let inset = outset - lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }
}
