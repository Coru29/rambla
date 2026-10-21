import AppKit
import RamblaCore

/// Knows whether the left mouse button is down and which strip window the user is dragging.
/// Global monitors only see clicks; they cost nothing while the mouse is idle.
@MainActor
final class DragTracker {
    struct Drag {
        let window: WindowID
        let startFrame: CGRect
    }

    var onMouseUp: ((CGPoint) -> Void)?
    private var monitors: [Any] = []
    private var drag: Drag?

    var isMouseDown: Bool { CGEventSource.buttonState(.combinedSessionState, button: .left) }

    func setEnabled(_ enabled: Bool) {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        guard enabled else { return }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            let point = Displays.axPoint(NSEvent.mouseLocation)
            _ = event
            MainActor.assumeIsolated { self?.onMouseUp?(point) }
        }) {
            monitors.append(up)
        }
    }

    func began(_ window: WindowID, startFrame: CGRect) {
        if drag?.window != window { drag = Drag(window: window, startFrame: startFrame) }
    }

    func isFrozen(_ window: WindowID) -> Bool { drag?.window == window }

    func takeDrag() -> Drag? {
        defer { drag = nil }
        return drag
    }
}
