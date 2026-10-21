import AppKit
import RamblaCore

/// Dims everything behind the focused window: one click-through black window per screen, translucent, ordered
/// directly below the focused window so that window and everything above it stay untouched.
///
/// `update` runs on every animation frame; the windows are created on first use and kept.
@MainActor
final class DimmerController {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]

    func update(focused: WindowID?, screens: [NSScreen], prefs: DimPrefs) {
        let amount = CGFloat(min(max(prefs.amount, 0), 1))
        guard prefs.enabled, amount > 0, let focused else {
            for window in windows.values where window.isVisible { window.orderOut(nil) }
            return
        }
        var live: Set<CGDirectDisplayID> = []
        for screen in screens {
            guard let id = Self.displayID(of: screen) else { continue }
            live.insert(id)
            let window = windows[id] ?? makeWindow(for: id)
            if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
            if window.alphaValue != amount { window.alphaValue = amount }
            // Re-asserted on every update: the focused window can be raised again without any event reaching us.
            window.order(.below, relativeTo: Int(focused))
        }
        // A display that was unplugged takes its window with it.
        for id in Array(windows.keys) where !live.contains(id) {
            windows.removeValue(forKey: id)?.close()
        }
    }

    private func makeWindow(for displayID: CGDirectDisplayID) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        // Black through the window's own alpha, so changing the amount never redraws anything.
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Same level as the windows it dims: only then can it sit directly below the focused one.
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        windows[displayID] = window
        return window
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
