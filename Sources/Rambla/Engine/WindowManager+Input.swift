import AppKit
import RamblaCore

/// Trackpad swipes and focus-follows-mouse.
extension WindowManager {
    func gestureBegan() {
        guard isRunning, !isPaused else { return }
        let mouse = Displays.axPoint(NSEvent.mouseLocation)
        let display = enabledDisplays.first { $0.frame.contains(mouse) }
        gestureKey = display.flatMap(currentKey) ?? activeStripKey()
        if let key = gestureKey { strips[key]?.allWindows.forEach(animator.cancel) }
    }

    func gestureChanged(_ dx: Double) {
        guard let key = gestureKey, var strip = strips[key], let width = results[key]?.metrics.area.width else { return }
        let direction: Double = prefs.trackpad.natural ? 1 : -1
        strip.scroll -= dx * width * 1.5 * prefs.trackpad.sensitivity * direction
        strips[key] = strip
        apply(key, animate: false, verify: false)
        indicatorHook?(key, nil)
    }

    /// Settles on the nearest column edge and focuses the most visible column, without another scroll.
    func gestureEnded() {
        guard let key = gestureKey else { return }
        gestureKey = nil
        guard var strip = strips[key], let display = display(for: key) else { return }
        let metrics = Layout.metrics(layoutInput(for: key, strip: strip, display: display))
        let settled = Layout.settle(metrics, scroll: strip.scroll)
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

    func hover(at point: CGPoint) {
        guard isRunning, !isPaused, prefs.focusFollowsMouse, gestureKey == nil else { return }
        for key in currentKeys {
            guard let result = results[key], let display = display(for: key) else { continue }
            for (id, placement) in result.placements {
                guard case .visible(let frame) = placement, frame.contains(point),
                      display.frame.contains(frame), id != focusedWindow else { continue }
                strips[key]?.focus(window: id)
                focusWithoutScrolling(id)
                return
            }
        }
    }

    /// Gives keyboard focus without scrolling the strip when macOS reports the change back.
    func focusWithoutScrolling(_ id: WindowID) {
        revealSuppressedFor = id
        focusedWindow = id
        worker(for: id)?.focus(id)
        overlayHook?()
    }
}
