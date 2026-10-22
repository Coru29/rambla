import AppKit
import RamblaCore

private let wheelCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let session = Unmanaged<ScrollWheelTracker.Session>.fromOpaque(userInfo).takeUnretainedValue()
    return session.handle(type: type, event: event)
}

/// The mouse half of "Trackpad y mouse": while the chosen keys are held, wheel notches and Magic Mouse swipes move
/// the strip instead of the app under the pointer (`WheelGesture` decides which events are Rambla's).
///
/// Keeping those events from the app takes an active event tap, which every scroll of every app passes through.
/// It sits where the mouse's events enter the window server, ahead of other apps' taps: Mac Mouse Fix, for one, turns
/// ⌘ + wheel into zoom there, and Rambla would never see the wheel. It runs on its own thread, so a busy main thread
/// never makes anybody's scrolling stutter, and it exists only while the feature is on. The engine is driven on the
/// main thread, in event order.
final class ScrollWheelTracker: @unchecked Sendable {
    struct Handlers {
        /// A wheel notch: focus the column this many places to the right (negative: left).
        let step: @MainActor (Int) -> Void
        let slideBegan: @MainActor () -> Void
        /// Points toward later columns.
        let slide: @MainActor (Double) -> Void
        /// Release speed in points per second.
        let slideEnded: @MainActor (Double) -> Void
    }

    private let handlers: Handlers
    private let lock = NSLock()
    /// The keys that must be held, exactly. Guarded by `lock`: the tap thread reads it on every event.
    private var modifiers: Modifiers = []
    /// The running tap, if any. Main thread only.
    private var session: Session?
    // Main thread only.
    private var enabled = false
    private let retry = TapRetry(name: "Scroll wheel tap")

    init(handlers: Handlers) {
        self.handlers = handlers
    }

    @MainActor
    func configure(enabled: Bool, modifiers: Modifiers) {
        lock.withLock { self.modifiers = modifiers }
        self.enabled = enabled
        if !enabled { retry.reset() }
        if enabled, session == nil, !retry.isWaiting {
            let session = Session(tracker: self)
            self.session = session
            session.start()
            Log.info("Scroll wheel moves the strip while \(modifiers.symbols) is held")
        } else if !enabled, let session {
            self.session = nil
            session.stop()
        }
    }

    /// Puts the tap back in front of the others': an app that started after Rambla (Mac Mouse Fix restarting, say)
    /// put its own ahead.
    /// Not while a slide or its glide is under way: the new tap would hand the rest of it to the app.
    @MainActor
    func renew() -> TapRenewal {
        guard let session else { return .off }
        guard !session.isBusy else { return .busy }
        session.stop()
        let fresh = Session(tracker: self)
        self.session = fresh
        fresh.start()
        return .renewed
    }

    /// Whether the tap exists (the feature is on).
    @MainActor
    var isOn: Bool { session != nil }

    fileprivate var wantedModifiers: Modifiers { lock.withLock { modifiers } }

    /// Reported by a session's thread: whether its tap could be created.
    fileprivate func sessionStarted(_ started: Session, ok: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard self.session === started else { return }
                if ok {
                    self.retry.reset()
                    return
                }
                self.session = nil
                self.retry.failed { [weak self] in
                    guard let self, self.enabled, self.session == nil else { return }
                    let session = Session(tracker: self)
                    self.session = session
                    session.start()
                }
            }
        }
    }

    /// Runs the engine call on the main thread. Blocks run in the order they were sent, so a slide never
    /// overtakes its own start or end.
    fileprivate func perform(_ output: WheelGesture.Output) {
        let handlers = handlers
        let call: (@MainActor () -> Void)?
        switch output {
        case .pass, .swallow: call = nil
        case .step(let columns): call = { handlers.step(columns) }
        case .slide(let points, let first):
            call = {
                if first { handlers.slideBegan() }
                handlers.slide(points)
            }
        case .release(let velocity): call = { handlers.slideEnded(velocity) }
        case .releaseThen(let velocity, let next):
            perform(.release(velocity: velocity))
            perform(next)
            return
        }
        guard let call else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated(call) }
    }

    /// One tap on its own thread and run loop. Everything but `start`, `stop` and `isBusy` runs on that thread.
    final class Session: @unchecked Sendable {
        private unowned let tracker: ScrollWheelTracker
        private let lock = NSLock()
        /// Guarded by `lock`: `stop` can come before the thread has its run loop.
        private var loop: CFRunLoop?
        private var stopped = false
        /// Guarded by `lock`: a slide or its glide is under way (`WheelGesture.isBusy`).
        private var busy = false
        // Tap thread only.
        private var tap: CFMachPort?
        private var gesture = WheelGesture()
        private var idleTimer: CFRunLoopTimer?

        init(tracker: ScrollWheelTracker) {
            self.tracker = tracker
        }

        var isBusy: Bool { lock.withLock { busy } }

        func start() {
            let thread = Thread { [self] in run() }
            thread.name = "Rambla scroll wheel"
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        func stop() {
            let loop: CFRunLoop? = lock.withLock {
                stopped = true
                return self.loop
            }
            if let loop {
                CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
                CFRunLoopWakeUp(loop)
            }
        }

        private func run() {
            let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
            guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: wheelCallback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                tracker.sessionStarted(self, ok: false)
                return
            }
            tracker.sessionStarted(self, ok: true)
            let loop = CFRunLoopGetCurrent()!
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(loop, source, .commonModes)
            let never = Date.distantFuture.timeIntervalSinceReferenceDate
            let timer = CFRunLoopTimerCreateWithHandler(nil, never, never, 0, 0) { [weak self] _ in
                self?.idle()
            }
            CFRunLoopAddTimer(loop, timer, .commonModes)
            self.tap = tap
            idleTimer = timer
            let proceed = lock.withLock { () -> Bool in
                self.loop = loop
                return !stopped
            }
            if proceed {
                CGEvent.tapEnable(tap: tap, enable: true)
                CFRunLoopRun()
            }
            CGEvent.tapEnable(tap: tap, enable: false)
            tracker.perform(gesture.cancel())
            CFRunLoopTimerInvalidate(timer)
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFMachPortInvalidate(tap)
        }

        /// Returns the event to pass it on, or nil to keep it from the app.
        fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // Events went by while the tap was off, maybe the end of a swipe: start clean.
                tracker.perform(gesture.cancel())
                armIdleTimer()
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
            let wanted = tracker.wantedModifiers
            let held = Modifiers(cocoa: UInt(event.flags.rawValue))
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let input = WheelGesture.Event(
                time: ProcessInfo.processInfo.systemUptime,
                modifiers: !wanted.isEmpty && held == wanted,
                continuous: continuous,
                phase: Self.phase(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
                momentum: Self.momentum(event.getIntegerValueField(.scrollWheelEventMomentumPhase)),
                deltaX: continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
                                   : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                deltaY: continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                                   : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)))
            let output = gesture.handle(input)
            tracker.perform(output)
            armIdleTimer()
            return output.passesEvent ? Unmanaged.passUnretained(event) : nil
        }

        /// Publishes whether a slide is under way and, while one is, wakes up when it would time out (see
        /// `WheelGesture.nextIdleCheck`).
        private func armIdleTimer() {
            let busy = gesture.isBusy
            lock.withLock { self.busy = busy }
            guard let idleTimer, let deadline = gesture.nextIdleCheck else { return }
            let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime) + 0.01
            CFRunLoopTimerSetNextFireDate(idleTimer, CFAbsoluteTimeGetCurrent() + delay)
        }

        private func idle() {
            tracker.perform(gesture.idle(at: ProcessInfo.processInfo.systemUptime))
            armIdleTimer()
        }

        /// `kCGScrollWheelEventScrollPhase`: 1 began, 2 changed, 4 ended, 8 cancelled, 128 may begin.
        private static func phase(_ raw: Int64) -> WheelGesture.Event.Phase {
            switch raw {
            case 1: return .began
            case 2: return .changed
            case 4: return .ended
            case 8: return .cancelled
            case 128: return .mayBegin
            default: return .none
            }
        }

        /// `kCGScrollWheelEventMomentumPhase`: 1 begin, 2 continue, 3 end.
        private static func momentum(_ raw: Int64) -> WheelGesture.Event.Momentum {
            switch raw {
            case 1: return .began
            case 2: return .changed
            case 3: return .ended
            default: return .none
            }
        }
    }
}
