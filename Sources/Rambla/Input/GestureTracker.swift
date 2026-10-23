import AppKit
import RamblaCore

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tracker = Unmanaged<GestureTracker>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated { tracker.handle(type: type, event: event) }
    return Unmanaged.passUnretained(event)
}

/// N-finger swipes on the trackpad, read from a listen-only event tap of gesture events (it never blocks or alters
/// input). The tap exists only while the feature is on. Sideways slides the strip: positions are the fingers' mean x
/// on the trackpad, from 0 (left edge) to 1 (right edge), and the release velocity is in those units per second.
/// Up and down give one command per swipe (`TrackpadSwipe` tells them apart, `TrackpadVertical` decides): up the full
/// width, down when the fingers lift the previous width, and further down the overview.
@MainActor
final class GestureTracker {
    private let onBegin: () -> Void
    private let onChange: (_ dx: Double) -> Void
    private let onEnd: (_ velocity: Double) -> Void
    private let onVertical: (_ up: Bool) -> Void
    private let onOverview: () -> Void

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var enabled = false
    private let retry = TapRetry(name: "Trackpad gesture tap")
    private var fingers = 4
    private var vertical = true
    /// Up or down: once a swipe is one, the rest of it does not slide the strip.
    private var verticalSwipe = TrackpadVertical()
    private var start: CGPoint?
    private var last: CGPoint?
    /// Where the fingers are now (`last` follows only a slide).
    private var current: CGPoint?
    private var active = false
    private var velocity = VelocityTracker()
    /// When the swipe's fingers last reported (event time), and the one check that ends the swipe there once
    /// `TrackpadSwipe.liftTimeout` passes without another report: its lift came without touches.
    private var lastTouch: TimeInterval?
    private var liftCheck: DispatchWorkItem?

    init(onBegin: @escaping () -> Void, onChange: @escaping (_ dx: Double) -> Void,
         onEnd: @escaping (_ velocity: Double) -> Void, onVertical: @escaping (_ up: Bool) -> Void,
         onOverview: @escaping () -> Void) {
        self.onBegin = onBegin
        self.onChange = onChange
        self.onEnd = onEnd
        self.onVertical = onVertical
        self.onOverview = onOverview
    }

    func configure(enabled: Bool, fingers: Int, vertical: Bool) {
        self.fingers = fingers
        self.vertical = vertical
        self.enabled = enabled
        if enabled, tap == nil, !retry.isWaiting { install() }
        if !enabled {
            retry.reset()
            uninstall()
        }
    }

    private func install() {
        let mask = CGEventMask(1) << 29 // NSEvent.EventType.gesture
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            retry.failed { [weak self] in
                guard let self, self.enabled, self.tap == nil else { return }
                self.install()
            }
            return
        }
        retry.reset()
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
        reset(at: ProcessInfo.processInfo.systemUptime)
    }

    /// Ends the swipe (if one was under way) at `time`, the moment the fingers lifted or changed in number.
    private func reset(at time: TimeInterval) {
        liftCheck?.cancel()
        liftCheck = nil
        lastTouch = nil
        if active { onEnd(velocity.velocity(at: time)) }
        if let start, let current, let command = verticalSwipe.lifted(dy: current.y - start.y) { perform(command) }
        verticalSwipe = TrackpadVertical()
        active = false
        start = nil
        last = nil
        current = nil
        velocity.reset()
    }

    private func perform(_ command: TrackpadVertical.Command) {
        switch command {
        case .fullWidth: onVertical(true)
        case .previousWidth: onVertical(false)
        case .overview: onOverview()
        case .toggleWidth, .strip, .armed: break   // strips mode: a later task wires them
        }
    }

    /// Ends the swipe at its last touch, so it keeps the speed it had, once `liftTimeout` has passed since; until then
    /// it looks again. One check at a time, however many events come.
    private func scheduleLiftCheck() {
        guard liftCheck == nil, let lastTouch else { return }
        let check = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.liftCheck != nil, let touch = self.lastTouch else { return }
                self.liftCheck = nil
                if ProcessInfo.processInfo.systemUptime - touch >= TrackpadSwipe.liftTimeout {
                    self.reset(at: touch)
                } else {
                    self.scheduleLiftCheck()
                }
            }
        }
        liftCheck = check
        let wait = lastTouch + TrackpadSwipe.liftTimeout - ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + max(wait, 0.01), execute: check)
    }

    /// `defaults write io.github.coru29.Rambla debugGestures -bool true` logs every touch event (read at launch).
    private static let debug = UserDefaults.standard.bool(forKey: "debugGestures")

    private func logTouches(_ event: NSEvent, _ touching: Set<NSTouch>) {
        let all = event.touches(matching: .any, in: nil)
        let resting = all.filter(\.isResting).count
        let phases = all.map { touch -> String in
            switch touch.phase {
            case .began: return "b"
            case .moved: return "m"
            case .stationary: return "s"
            case .ended: return "e"
            case .cancelled: return "c"
            default: return "?"
            }
        }.sorted().joined()
        let count = Double(max(touching.count, 1))
        let x = touching.reduce(0) { $0 + $1.normalizedPosition.x } / count
        let y = touching.reduce(0) { $0 + $1.normalizedPosition.y } / count
        Log.info(String(format: "touches %d touching %d resting %d [%@] x %.3f y %.3f %@", all.count, touching.count,
                        resting, phases, x, y, active ? "sliding" : (verticalSwipe.isVertical ? "vertical" : "-")))
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .gesture else { return }
        let touching = nsEvent.touches(matching: .touching, in: nil)
        if Self.debug { logTouches(nsEvent, touching) }
        switch TrackpadSwipe.frame(touching: touching.count, total: nsEvent.touches(matching: .any, in: nil).count,
                                   fingers: fingers) {
        case .ignore:
            // Between two real events, or the lift itself: if no touch follows soon, the fingers are gone.
            scheduleLiftCheck()
            return
        case .end:
            reset(at: nsEvent.timestamp)
            return
        case .track:
            lastTouch = nsEvent.timestamp
        }
        let count = Double(touching.count)
        let mean = CGPoint(x: touching.reduce(0) { $0 + $1.normalizedPosition.x } / count,
                           y: touching.reduce(0) { $0 + $1.normalizedPosition.y } / count)
        guard let start else {
            self.start = mean
            last = mean
            current = mean
            return
        }
        current = mean
        if !active {
            let kind = TrackpadSwipe.kind(dx: mean.x - start.x, dy: mean.y - start.y)
            if vertical, let command = verticalSwipe.moved(kind, dy: mean.y - start.y) { perform(command) }
            guard !verticalSwipe.isVertical, kind == .horizontal else { return }
            active = true
            onBegin()
        }
        if let last { onChange(mean.x - last.x) }
        last = mean
        velocity.add(mean.x, at: nsEvent.timestamp)
    }
}
