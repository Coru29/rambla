import AppKit

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tracker = Unmanaged<GestureTracker>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated { tracker.handle(type: type, event: event) }
    return Unmanaged.passUnretained(event)
}

/// Horizontal N-finger swipes on the trackpad, read from a listen-only event tap of gesture events
/// (it never blocks or alters input). The tap exists only while the feature is on.
@MainActor
final class GestureTracker {
    private let onBegin: () -> Void
    private let onChange: (_ dx: Double) -> Void
    private let onEnd: () -> Void

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var fingers = 4
    private var start: CGPoint?
    private var last: CGPoint?
    private var active = false

    init(onBegin: @escaping () -> Void, onChange: @escaping (_ dx: Double) -> Void, onEnd: @escaping () -> Void) {
        self.onBegin = onBegin
        self.onChange = onChange
        self.onEnd = onEnd
    }

    func configure(enabled: Bool, fingers: Int) {
        self.fingers = fingers
        if enabled, tap == nil { install() }
        if !enabled { uninstall() }
    }

    private func install() {
        let mask = CGEventMask(1) << 29 // NSEvent.EventType.gesture
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.error("Trackpad gesture tap could not be created")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        reset()
    }

    private func reset() {
        if active { onEnd() }
        active = false
        start = nil
        last = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .gesture else { return }
        let touching = nsEvent.touches(matching: .touching, in: nil)
        guard touching.count == fingers else {
            reset()
            return
        }
        let count = Double(touching.count)
        let mean = CGPoint(x: touching.reduce(0) { $0 + $1.normalizedPosition.x } / count,
                           y: touching.reduce(0) { $0 + $1.normalizedPosition.y } / count)
        guard let start else {
            self.start = mean
            last = mean
            return
        }
        if !active {
            let dx = mean.x - start.x
            let dy = mean.y - start.y
            guard abs(dx) > 0.015, abs(dx) > abs(dy) else { return }
            active = true
            onBegin()
        }
        if let last { onChange(mean.x - last.x) }
        last = mean
    }
}
