import AppKit

/// "Focus follows mouse": reports where the pointer rested for 120 ms. The monitor exists only while on.
@MainActor
final class MouseFocus {
    private let onHover: (CGPoint) -> Void
    private var monitor: Any?
    private var pending: DispatchWorkItem?

    init(onHover: @escaping (CGPoint) -> Void) {
        self.onHover = onHover
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                MainActor.assumeIsolated { self?.moved() }
            }
        } else if !enabled, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            pending?.cancel()
        }
    }

    private func moved() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if CGEventSource.buttonState(.combinedSessionState, button: .left) { return }
                self.onHover(Displays.axPoint(NSEvent.mouseLocation))
            }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }
}
