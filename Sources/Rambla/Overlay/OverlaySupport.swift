import AppKit
import SwiftUI

/// A borderless panel for the overlays that take clicks (strip indicator, tab bars, overview).
///
/// It never activates Rambla and never becomes key or main, so showing it or clicking it leaves keyboard
/// focus exactly where it was (only the overview's panel takes the keyboard). Click-through overlays (focus border,
/// dimming) are plain borderless windows.
class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(level: NSWindow.Level, collectionBehavior: NSWindow.CollectionBehavior) {
        // `.nonactivatingPanel` only takes effect when it is part of the style mask at creation.
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        self.level = level
        self.collectionBehavior = collectionBehavior
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Rambla is never the active app, and panels hide on deactivation by default.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }
}

/// Hosts SwiftUI content in an overlay panel. The mouse goes to closures (in this view's coordinates) instead
/// of SwiftUI's gesture system, so a click works the first time on a panel that is never the key window.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The whole view takes the mouse, including the transparent padding SwiftUI would let through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?(location(of: event)) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(location(of: event)) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(location(of: event)) }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }
}

enum OverlayStyle {
    /// A stretchable rounded rectangle for `NSVisualEffectView.maskImage`: clips the blur and, on the content
    /// view of a window, the window shadow too.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
