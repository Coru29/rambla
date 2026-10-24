import AppKit
import RamblaCore

/// Trackpad swipes, the mouse wheel, mouse button drags and focus-follows-mouse.
extension WindowManager {
    /// Scroll-area widths the strip travels when the fingers cross the whole trackpad, at sensitivity 1×:
    /// a comfortable four-finger swipe (about a quarter of the trackpad) moves a bit more than half a screen.
    static let trackpadGain = 2.5
    /// Strip points per point the pointer moves with the mouse buttons held, at sensitivity 1×: a short drag (or a
    /// flick, which carries its speed) reaches the next column.
    static let mouseDragGain = 2.0

    /// A slide starts on the strip under the pointer (the trackpad and the mouse wheel both act where you look).
    /// `onTrackpad`: the fingers are on the trackpad, so it can tap each column the strip passes.
    func gestureBegan(onTrackpad: Bool) {
        guard isRunning, !isPaused else { return }
        gestureKey = stripKeyUnderPointer()
        slideDetent = onTrackpad && prefs.trackpad.haptics ? SlideDetent() : nil
        if let key = gestureKey { strips[key]?.allWindows.forEach(animator.cancel) }
    }

    /// Fingers moved `dx` on the trackpad (a fraction of its width).
    func gestureChanged(_ dx: Double) {
        guard let width = gestureKey.flatMap({ results[$0]?.metrics.area.width }) else { return }
        slide(by: -dx * width * trackpadScale)
    }

    /// The fingers lifted, moving at `velocity` trackpad widths per second.
    func gestureEnded(velocity: Double) {
        let width = gestureKey.flatMap { results[$0]?.metrics.area.width } ?? 0
        slideEnded(velocity: -velocity * width * trackpadScale)
    }

    /// The pointer moved `dx` points sideways (positive: right) with the mouse buttons held.
    func mouseDragged(_ dx: Double) {
        slide(by: -dx * mouseDragScale)
    }

    /// The mouse buttons were released, the pointer moving at `velocity` points per second.
    func mouseDragEnded(velocity: Double) {
        slideEnded(velocity: -velocity * mouseDragScale)
    }

    /// Moves the strip being slid by `points` toward later columns.
    func slide(by points: Double) {
        guard let key = gestureKey, var strip = strips[key] else { return }
        strip.scroll += points
        strips[key] = strip
        apply(key, animate: false, verify: false)
        if let metrics = results[key]?.metrics,
           slideDetent?.moved(by: points, to: strip.scroll, in: metrics, at: ProcessInfo.processInfo.systemUptime) == true {
            Haptics.detent()
        }
        indicatorHook?(key, nil)
    }

    /// Settles on a column edge (carrying the release `velocity`, in points per second, so a flick reaches the next
    /// column) and focuses the column it lands on, without another scroll.
    func slideEnded(velocity: Double) {
        guard let key = gestureKey else { return }
        gestureKey = nil
        slideDetent = nil
        guard var strip = strips[key], let display = display(for: key) else { return }
        let metrics = Layout.metrics(layoutInput(for: key, strip: strip, display: display))
        let settled = Layout.settle(metrics, scroll: strip.scroll, velocity: velocity, focused: strip.focused)
        let width = max(Double(metrics.area.width), 1)
        Log.info(String(format: "Slide released at %.2f widths/s: %.2f → %.2f widths", velocity / width,
                        strip.scroll / width, settled.scroll / width))
        strip.scroll = settled.scroll
        if let column = settled.column, let window = strip.columns[column].activeWindow {
            strip.focused = column
            focusWithoutScrolling(window)
        }
        strips[key] = strip
        // Next to a pinned column the settled one can still poke under the pin (and be parked):
        // a minimal reveal keeps the focused window on screen.
        reveal(key, animate: true, mode: .never)
        onStateChanged?()
    }

    /// Width mode (`VerticalGesture.width`), swipe up (on the trackpad, or dragging with the mouse buttons): the
    /// focused column takes the full width of the screen (without macOS's full screen); swipe down: back to the width it
    /// had. On the trackpad it taps once.
    func verticalSwipe(up: Bool, onTrackpad: Bool) {
        guard isRunning, !isPaused, gestureKey == nil, let key = activeStripKey(), var strip = strips[key] else { return }
        Log.info("Swipe \(up ? "up: full width" : "down: previous width")")
        strip.setFullWidth(up)
        strips[key] = strip
        if onTrackpad, prefs.trackpad.haptics { Haptics.gesture() }
        reveal(key)
        indicatorHook?(key, nil)
        onStateChanged?()
    }

    /// A short vertical swipe: the fingers (or the pointer) went up when `fingersUp`. With the device's natural direction
    /// the content follows them, so going down shows the strip above. Acts on the stack under the pointer.
    func stripSwipe(fingersUp: Bool, onTrackpad: Bool) {
        guard isRunning, !isPaused, gestureKey == nil, let stack = stackUnderPointer() else { return }
        let natural = onTrackpad ? prefs.trackpad.natural : prefs.mouseButtons.natural
        let up = StripLevels.stripAbove(fingersUp: fingersUp, natural: natural)
        Log.info("Swipe \(fingersUp ? "up" : "down"): strip \(up ? "above" : "below")")
        // At either end of the stack nothing happens, and nothing more is needed.
        stepLevel(up: up, on: stack)
    }

    /// The swipe just became a short vertical one: a haptic tap when there is a strip that way (trackpad, haptics on).
    func stripSwipeArmed(fingersUp: Bool) {
        guard isRunning, !isPaused, gestureKey == nil, prefs.trackpad.haptics, let stack = stackUnderPointer() else { return }
        let up = StripLevels.stripAbove(fingersUp: fingersUp, natural: prefs.trackpad.natural)
        guard StripLevels.target(from: activeLevel(of: stack), up: up, top: topLevel(of: stack),
                                 occupied: occupiedLevels(of: stack)) != nil else { return }
        Haptics.gesture()
    }

    /// A long swipe up: the focused column's full width, or back to its width (like ⌃⌘M). On a strip without a focused
    /// column (a new empty one in view) nothing happens, not even the tap.
    func toggleWidthBySwipe(onTrackpad: Bool) {
        guard isRunning, !isPaused, gestureKey == nil, let key = activeStripKey(), var strip = strips[key],
              strip.focusedColumn != nil else { return }
        strip.toggleFullWidth()
        // The toggle keeps the width to go back to only while the column has the full width.
        Log.info("Swipe up: \(strip.focusedColumn?.widthBeforeFull != nil ? "full width" : "previous width")")
        strips[key] = strip
        if onTrackpad, prefs.trackpad.haptics { Haptics.gesture() }
        reveal(key)
        indicatorHook?(key, nil)
        onStateChanged?()
    }

    /// One notch of the mouse wheel with the chosen keys held: focus the next column (`direction` > 0) or the
    /// previous one of the strip under the pointer, like the keyboard shortcuts do.
    func wheelStep(_ direction: Int) {
        guard isRunning, !isPaused, gestureKey == nil, let key = stripKeyUnderPointer(), var strip = strips[key] else { return }
        Log.info("Wheel step \(direction > 0 ? "right" : "left")")
        let before = strip.focusedWindow
        strip.focusColumn(direction > 0 ? .right : .left, hidden: hidden[key] ?? [])
        strips[key] = strip
        if let target = strip.focusedWindow, target != before || target != focusedWindow {
            focus(window: target, in: key)
        } else {
            reveal(key)
        }
        indicatorHook?(key, nil)
        onStateChanged?()
    }

    /// A long move down, on the trackpad or with the mouse buttons held: the overview of the strip under the pointer.
    /// On the trackpad it taps once.
    func showOverviewUnderPointer(onTrackpad: Bool) {
        guard isRunning, !isPaused, gestureKey == nil, let key = stripKeyUnderPointer() else { return }
        overviewHook?(key)
        if onTrackpad, prefs.trackpad.haptics { Haptics.gesture() }
    }

    func hover(at point: CGPoint) {
        guard isRunning, !isPaused, prefs.focusFollowsMouse, gestureKey == nil else { return }
        for key in currentKeys {
            guard let result = results[key], let display = display(for: key) else { continue }
            for (id, placement) in result.placements {
                guard case .visible(let frame) = placement, frame.contains(point),
                      display.frame.contains(frame), id != focusedWindow else { continue }
                // Only the window actually on top there: not the strip window under a floating one, a menu, the Dock
                // or Rambla's own settings.
                let ownWindows = Set(NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }.map(\.windowNumber))
                guard Self.frontWindow(at: point, ownWindows: ownWindows) == id else { return }
                strips[key]?.focus(window: id)
                focusWithoutScrolling(id)
                return
            }
        }
    }

    /// The window macOS shows on top at `point` (global top-left coordinates, like AX), or nil when it is not an
    /// ordinary window (a menu, the Dock, the menu bar). Rambla's own overlays (border, dimming, indicator) let the
    /// pointer through and are skipped; its titled windows (`ownWindows`: settings, welcome) count like any other.
    private static func frontWindow(at point: CGPoint, ownWindows: Set<Int>) -> WindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let own = ProcessInfo.processInfo.processIdentifier
        for info in list {
            let number = info[kCGWindowNumber as String] as? Int ?? 0
            let isOverlay = (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == own && !ownWindows.contains(number)
            guard !isOverlay,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.contains(point) else { continue }
            guard (info[kCGWindowLayer as String] as? Int ?? 0) == 0 else { return nil }
            return (info[kCGWindowNumber as String] as? Int).map(WindowID.init)
        }
        return nil
    }

    /// Gives keyboard focus without scrolling the strip when macOS reports the change back. A window that already has
    /// the focus gets no report, so nothing is suppressed for it (a leftover would keep a later ⌘Tab from revealing it).
    func focusWithoutScrolling(_ id: WindowID) {
        revealSuppressedFor = id == focusedWindow ? nil : id
        focusedWindow = id
        worker(for: id)?.focus(id)
        overlayHook?()
    }

    // MARK: - Helpers

    /// Strip points per trackpad width: the gain, the user's sensitivity and the direction (natural: the strip
    /// follows the fingers, so fingers moving left scroll toward later columns).
    private var trackpadScale: Double {
        Self.trackpadGain * prefs.trackpad.sensitivity * (prefs.trackpad.natural ? 1 : -1)
    }

    /// Strip points per pointer point, the same way: natural, the strip follows the pointer.
    private var mouseDragScale: Double {
        Self.mouseDragGain * prefs.mouseButtons.sensitivity * (prefs.mouseButtons.natural ? 1 : -1)
    }

    /// The strip of the display under the pointer, or the active one when the pointer is on no managed display.
    private func stripKeyUnderPointer() -> StripKey? {
        let mouse = Displays.axPoint(NSEvent.mouseLocation)
        let display = enabledDisplays.first { $0.frame.contains(mouse) }
        return display.flatMap(currentKey) ?? activeStripKey()
    }
}
