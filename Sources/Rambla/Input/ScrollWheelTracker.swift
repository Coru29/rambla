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
/// It also keeps the trackpad swipe's scrolling from the apps. With macOS's own swipes off for the gesture's fingers,
/// macOS sends their movement to the app under the pointer as scrolling, and a glide after they lift: reading an
/// article, a swipe down would scroll it. `GestureTracker` reports every touch here, and `SwipeScroll` decides which
/// scroll events belong to a swipe; those reach neither the app nor `WheelGesture`.
///
/// Keeping those events from the app takes an active event tap, which every scroll of every app passes through.
/// It sits where the mouse's events enter the window server, ahead of other apps' taps: Mac Mouse Fix, for one, turns
/// ⌘ + wheel into zoom there, and Rambla would never see the wheel. It runs on its own thread, so a busy main thread
/// never makes anybody's scrolling stutter, and it exists only while the wheel or the trackpad gesture is on. The
/// engine is driven on the main thread, in event order.
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
    /// Which scroll events belong to a trackpad swipe, while the trackpad gesture is on. Guarded by `lock`: the main
    /// thread reports the touches, and the tap thread asks about every continuous scroll event.
    private var swipe: SwipeScroll?
    /// The running tap, if any. Main thread only.
    private var session: Session?
    // Main thread only.
    private var enabled = false
    private var wheel = false
    private var swipeFingers: Int?
    private let retry = TapRetry(name: "Scroll wheel tap")

    init(handlers: Handlers) {
        self.handlers = handlers
    }

    /// The tap exists while either feature needs it: `wheel`, the chosen keys and the wheel move the strip; or the
    /// trackpad gesture, on with `swipeFingers` fingers (nil while it is off), whose scrolling the apps must not get.
    @MainActor
    func configure(wheel: Bool, modifiers: Modifiers, swipeFingers: Int?) {
        lock.withLock {
            self.modifiers = modifiers
            // Settings change many times a second: the same finger count keeps a swipe under way.
            if swipeFingers != self.swipeFingers { swipe = swipeFingers.map { SwipeScroll(fingers: $0) } }
        }
        // A session reads the wheel or leaves it alone for good: a change takes a new one (the old one lets go of
        // its slide, if any).
        let restart = wheel != self.wheel
        if wheel, restart { Log.info("Scroll wheel moves the strip while \(modifiers.symbols) is held") }
        if let swipeFingers, swipeFingers != self.swipeFingers {
            Log.info("Trackpad swipes with \(swipeFingers) fingers do not scroll the apps")
        }
        self.wheel = wheel
        self.swipeFingers = swipeFingers
        enabled = wheel || swipeFingers != nil
        if !enabled { retry.reset() }
        if let session, restart || !enabled {
            self.session = nil
            session.stop()
        }
        if enabled, session == nil, !retry.isWaiting { startSession() }
    }

    /// A report of the fingers on the trackpad, sent by `GestureTracker` for every gesture event that carries
    /// touches: `touching` of them at `time` (the event's, seconds since startup like `ProcessInfo.systemUptime`).
    func touched(_ touching: Int, at time: TimeInterval) {
        lock.withLock { swipe?.touched(touching, at: time) }
    }

    /// Puts the tap back in front of the others': an app that started after Rambla (Mac Mouse Fix restarting, say)
    /// put its own ahead.
    /// Not while a slide or its glide is under way: the new tap would hand the rest of it to the app. Nor while a
    /// trackpad swipe or its glide is: its events would slip through between the old tap and the new one.
    @MainActor
    func renew() -> TapRenewal {
        guard let session else { return .off }
        guard !session.isBusy, !swipeIsBusy else { return .busy }
        session.stop()
        startSession()
        return .renewed
    }

    /// A trackpad swipe or its glide is under way (`SwipeScroll.isBusy`).
    @MainActor
    private var swipeIsBusy: Bool {
        lock.withLock { swipe?.isBusy(at: ProcessInfo.processInfo.systemUptime) ?? false }
    }

    /// Whether the tap exists (the wheel or the trackpad gesture is on).
    @MainActor
    var isOn: Bool { session != nil }

    @MainActor
    private func startSession() {
        let session = Session(tracker: self, wheel: wheel)
        self.session = session
        session.start()
    }

    fileprivate var wantedModifiers: Modifiers { lock.withLock { modifiers } }

    /// Whether a continuous scroll event belongs to a trackpad swipe (`SwipeScroll`). Tap thread.
    fileprivate func swipeSwallows(phase: WheelGesture.Event.Phase, momentum: WheelGesture.Event.Momentum,
                                   fromHardware: Bool, at time: TimeInterval) -> Bool {
        lock.withLock {
            swipe?.swallows(phase: phase, momentum: momentum, fromHardware: fromHardware, at: time) ?? false
        }
    }

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
                    self.startSession()
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
        /// The wheel moves the strip. Without it the tap is there for the trackpad swipe, and every event it does not
        /// swallow passes untouched.
        private let wheel: Bool
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

        init(tracker: ScrollWheelTracker, wheel: Bool) {
            self.tracker = tracker
            self.wheel = wheel
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
            let time = ProcessInfo.processInfo.systemUptime
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let phase = Self.phase(event.getIntegerValueField(.scrollWheelEventScrollPhase))
            let momentum = Self.momentum(event.getIntegerValueField(.scrollWheelEventMomentumPhase))
            // A trackpad swipe's scrolling is nobody's: not the app's, and not the wheel's to slide the strip with
            // (the gesture already moves it). An event another app posted (Mac Mouse Fix's smooth scrolling, say)
            // names that app's process; the hardware's name none.
            if continuous {
                let fromHardware = event.getIntegerValueField(.eventSourceUnixProcessID) == 0
                if tracker.swipeSwallows(phase: phase, momentum: momentum, fromHardware: fromHardware, at: time) {
                    return nil
                }
            }
            guard wheel else { return Unmanaged.passUnretained(event) }
            let wanted = tracker.wantedModifiers
            let held = Modifiers(cocoa: UInt(event.flags.rawValue))
            let input = WheelGesture.Event(
                time: time,
                modifiers: !wanted.isEmpty && held == wanted,
                continuous: continuous,
                phase: phase,
                momentum: momentum,
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
