import AppKit
import RamblaCore

private let mouseButtonCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let session = Unmanaged<MouseButtonTracker.Session>.fromOpaque(userInfo).takeUnretainedValue()
    return session.handle(proxy: proxy, type: type, event: event)
}

/// "Botones del mouse": moving the mouse with the chosen buttons held slides the strip, a move up gives the focused
/// column the full width, and a move down gives back its width when the buttons are let go, or opens the overview when
/// it goes further (`MouseButtonGesture` decides which presses and moves are Rambla's). It also records a new
/// combination for the settings.
///
/// The taps sit where the mouse's events enter the window server, ahead of the other apps' taps (Mac Mouse Fix has
/// its own there), so a chord of buttons that another app also uses on their own reaches Rambla first. A press that is
/// not Rambla's goes on to them, late by at most `MouseButtonGesture.chordWindow`. Like the wheel's, the taps run on
/// their own thread and exist only while the feature is on (or a combination is being recorded); the one for pointer
/// moves and wheel turns is enabled only while a button of the chord is held.
final class MouseButtonTracker: @unchecked Sendable {
    struct Handlers {
        let slideBegan: @MainActor () -> Void
        /// Pointer points sideways (positive: right).
        let slide: @MainActor (Double) -> Void
        /// Release speed in pointer points per second.
        let slideEnded: @MainActor (Double) -> Void
        let vertical: @MainActor (_ up: Bool) -> Void
        let overview: @MainActor () -> Void
    }

    /// The settings' recorder: told the buttons down so far, then the whole combination once they are all released.
    /// Meanwhile those presses reach no app.
    final class Recording: @unchecked Sendable {
        let changed: @MainActor ([Int]) -> Void
        let finished: @MainActor ([Int]) -> Void

        init(changed: @escaping @MainActor ([Int]) -> Void, finished: @escaping @MainActor ([Int]) -> Void) {
            self.changed = changed
            self.finished = finished
        }
    }

    /// Marks the presses Rambla gives back, so its own tap lets them through.
    fileprivate static let replayMark: Int64 = 0x5241_4D42   // "RAMB"

    private let handlers: Handlers
    private let lock = NSLock()
    /// Guarded by `lock`: the tap thread reads it on every press.
    private var recording: Recording?
    /// Guarded by `lock`: engine calls waiting for the main thread, consecutive slides merged into one (a mouse can
    /// report a thousand moves a second, many more than the strip needs to be laid out).
    private var queued: [MouseButtonGesture.Command] = []
    // Main thread only.
    private var session: Session?
    private var enabled = false
    private var buttons: [Int] = []
    private let retry = TapRetry(name: "Mouse button taps")

    init(handlers: Handlers) {
        self.handlers = handlers
    }

    @MainActor
    func configure(enabled: Bool, buttons: [Int]) {
        let changed = enabled != self.enabled || buttons != self.buttons
        self.enabled = enabled
        self.buttons = buttons
        update(restart: changed)
        if changed, enabled {
            Log.info("Mouse buttons \(buttons.map(String.init).joined(separator: " + ")) drive the strip")
        }
    }

    /// Puts the taps back in front of the others': an app that started after Rambla (Mac Mouse Fix restarting, say)
    /// put its own ahead. Not while a press is held or a combination is being recorded: the new taps would know
    /// nothing about them.
    @MainActor
    func renew() -> TapRenewal {
        guard let session else { return .off }
        guard !session.isBusy, currentRecording == nil else { return .busy }
        update(restart: true)
        return .renewed
    }

    @MainActor
    func startRecording(_ recording: Recording) {
        lock.withLock { self.recording = recording }
        update(restart: false)
    }

    @MainActor
    func stopRecording() {
        lock.withLock { recording = nil }
        update(restart: false)
    }

    fileprivate var currentRecording: Recording? { lock.withLock { recording } }

    /// Whether the taps exist (the feature is on, or a combination is being recorded).
    @MainActor
    var isOn: Bool { session != nil }

    /// The session needs to run for the gestures, and for a recording even with them off.
    @MainActor
    private func update(restart: Bool) {
        let wanted = enabled || currentRecording != nil
        if !wanted { retry.reset() }
        if let session, restart || !wanted {
            self.session = nil
            session.stop()
        }
        if wanted, session == nil, !retry.isWaiting {
            // With the gestures off, an empty chord: every press stays the apps' (only a recording is Rambla's).
            let session = Session(tracker: self, buttons: enabled ? buttons : [])
            self.session = session
            session.start()
        }
    }

    /// Runs the engine calls on the main thread, in order.
    fileprivate func perform(_ commands: [MouseButtonGesture.Command]) {
        guard !commands.isEmpty else { return }
        let first = lock.withLock { () -> Bool in
            let wasEmpty = queued.isEmpty
            for command in commands {
                if case .slide(let dx) = command, case .slide(let before)? = queued.last {
                    queued[queued.count - 1] = .slide(before + dx)
                } else {
                    queued.append(command)
                }
            }
            return wasEmpty
        }
        guard first else { return }   // the call already on its way takes these too
        let handlers = handlers
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let commands = self.lock.withLock { () -> [MouseButtonGesture.Command] in
                    defer { self.queued.removeAll() }
                    return self.queued
                }
                for command in commands {
                    switch command {
                    case .slideBegan: handlers.slideBegan()
                    case .slide(let dx): handlers.slide(dx)
                    case .slideEnded(let velocity): handlers.slideEnded(velocity)
                    case .vertical(let up): handlers.vertical(up)
                    case .overview: handlers.overview()
                    }
                }
            }
        }
    }

    /// Reported by a session's thread: whether its taps could be created.
    fileprivate func sessionStarted(_ started: Session, ok: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard self.session === started else { return }
                if ok {
                    self.retry.reset()
                    return
                }
                self.session = nil
                self.retry.failed { [weak self] in self?.update(restart: false) }
            }
        }
    }

    fileprivate func recordingChanged(_ recording: Recording, _ buttons: [Int]) {
        DispatchQueue.main.async { MainActor.assumeIsolated { recording.changed(buttons) } }
    }

    /// Ends `recording` (unless it was stopped meanwhile) and drops a session that only existed for it.
    fileprivate func recordingFinished(_ recording: Recording, _ buttons: [Int]) {
        let current = lock.withLock { () -> Bool in
            guard self.recording === recording else { return false }
            self.recording = nil
            return true
        }
        guard current else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                recording.finished(buttons)
                self.update(restart: false)
            }
        }
    }

    /// The taps on their own thread and run loop. Everything but `start`, `stop` and `isBusy` runs on that thread.
    final class Session: @unchecked Sendable {
        private unowned let tracker: MouseButtonTracker
        private let lock = NSLock()
        /// Guarded by `lock`: `stop` can come before the thread has its run loop.
        private var loop: CFRunLoop?
        private var stopped = false
        /// Guarded by `lock`: Rambla holds a press, so replacing the taps now would cut the gesture short.
        private var busy = false
        // Tap thread only.
        private var buttonTap: CFMachPort?
        private var motionTap: CFMachPort?
        private var motionEnabled = false
        private var timer: CFRunLoopTimer?
        private var gesture: MouseButtonGesture
        /// The presses held back from the apps, kept to give them back when they turn out not to be Rambla's.
        private var heldEvents: [Int: CGEvent] = [:]
        /// Presses the timer did not give back because the button was already up: their releases are kept from the
        /// apps too, which never saw them pressed.
        private var dropped: Set<Int> = []
        /// The recording being made, the buttons down for it and the most that were down at once.
        private var recording: Recording?
        private var recordingDown: Set<Int> = []
        private var recordingBest: Set<Int> = []
        /// Presses a recording kept from the apps: their releases are kept too, even after it ends.
        private var recordingSwallowed: Set<Int> = []

        init(tracker: MouseButtonTracker, buttons: [Int]) {
            self.tracker = tracker
            gesture = MouseButtonGesture(buttons: buttons)
        }

        var isBusy: Bool { lock.withLock { busy } }

        func start() {
            let thread = Thread { [self] in run() }
            thread.name = "Rambla mouse buttons"
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
            let pressMask = CGEventMask(1) << CGEventType.otherMouseDown.rawValue
                | CGEventMask(1) << CGEventType.otherMouseUp.rawValue
            let moveMask = CGEventMask(1) << CGEventType.otherMouseDragged.rawValue
                | CGEventMask(1) << CGEventType.mouseMoved.rawValue
                | CGEventMask(1) << CGEventType.scrollWheel.rawValue
            let userInfo = Unmanaged.passUnretained(self).toOpaque()
            // At the head of the HID taps, and the presses' tap ahead of the moves' one (each new tap goes first).
            // A tap starts enabled: the moves' one is turned off at once, or every pointer move would wait for this
            // thread until its run loop runs.
            guard let motionTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                                    eventsOfInterest: moveMask, callback: mouseButtonCallback,
                                                    userInfo: userInfo) else {
                tracker.sessionStarted(self, ok: false)
                return
            }
            CGEvent.tapEnable(tap: motionTap, enable: false)
            guard let buttonTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                                    eventsOfInterest: pressMask, callback: mouseButtonCallback,
                                                    userInfo: userInfo) else {
                CFMachPortInvalidate(motionTap)
                tracker.sessionStarted(self, ok: false)
                return
            }
            tracker.sessionStarted(self, ok: true)
            let loop = CFRunLoopGetCurrent()!
            let sources = [buttonTap, motionTap].map { CFMachPortCreateRunLoopSource(nil, $0, 0)! }
            sources.forEach { CFRunLoopAddSource(loop, $0, .commonModes) }
            let never = Date.distantFuture.timeIntervalSinceReferenceDate
            let timer = CFRunLoopTimerCreateWithHandler(nil, never, never, 0, 0) { [weak self] _ in
                self?.expire()
            }
            CFRunLoopAddTimer(loop, timer, .commonModes)
            self.buttonTap = buttonTap
            self.motionTap = motionTap
            self.timer = timer
            let proceed = lock.withLock { () -> Bool in
                self.loop = loop
                return !stopped
            }
            if proceed {
                CGEvent.tapEnable(tap: buttonTap, enable: true)
                CFRunLoopRun()
            }
            CGEvent.tapEnable(tap: buttonTap, enable: false)
            CGEvent.tapEnable(tap: motionTap, enable: false)
            tracker.perform(gesture.cancel())
            CFRunLoopTimerInvalidate(timer)
            sources.forEach { CFRunLoopRemoveSource(loop, $0, .commonModes) }
            CFMachPortInvalidate(buttonTap)
            CFMachPortInvalidate(motionTap)
        }

        /// Returns the event to pass it on, or nil to keep it from the apps.
        fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // macOS turned a tap off (Rambla was too slow once), or Rambla did (the moves' tap after a press):
                // turn back on what should be on. Never turn a tap off here: that is reported again, and answering
                // each report with another one keeps the thread busy forever.
                if let buttonTap, !CGEvent.tapIsEnabled(tap: buttonTap) { CGEvent.tapEnable(tap: buttonTap, enable: true) }
                if motionEnabled, let motionTap, !CGEvent.tapIsEnabled(tap: motionTap) {
                    CGEvent.tapEnable(tap: motionTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            guard event.getIntegerValueField(.eventSourceUserData) != MouseButtonTracker.replayMark else {
                return Unmanaged.passUnretained(event)   // a press the timer gave back
            }
            let input: MouseButtonGesture.Input
            var swallowRelease = false
            switch type {
            case .otherMouseDown, .otherMouseUp:
                // CG counts from 0 (left), mouse apps from 1.
                let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
                if type == .otherMouseDown {
                    dropped.remove(button)   // a new press: whatever was missed of the last one is over
                    if let recording = tracker.currentRecording {
                        recordingSwallowed.insert(button)
                        record(button, down: true, for: recording)
                        return nil
                    }
                    input = .down(button)
                } else {
                    if recordingSwallowed.remove(button) != nil {
                        if let recording = tracker.currentRecording { record(button, down: false, for: recording) }
                        return nil
                    }
                    swallowRelease = dropped.remove(button) != nil
                    input = .up(button)
                }
            case .otherMouseDragged:
                input = .drag(dx: event.getDoubleValueField(.mouseEventDeltaX),
                              dy: event.getDoubleValueField(.mouseEventDeltaY))
            case .mouseMoved:
                // Moving without a button down: what Rambla held was released while it was not looking. Unless macOS
                // says one of them is still down (something else moved the pointer).
                guard !gesture.heldButtons.contains(where: Self.isDown) else { return Unmanaged.passUnretained(event) }
                input = .released
            case .scrollWheel:
                // The glide after a swipe is not someone turning the wheel.
                guard event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else {
                    return Unmanaged.passUnretained(event)
                }
                input = .scroll
            default:
                return Unmanaged.passUnretained(event)
            }
            let output = gesture.handle(input, at: ProcessInfo.processInfo.systemUptime)
            giveBack(output.replay, proxy: proxy)
            if case .down(let button) = input, !output.passes, let copy = event.copy() {
                heldEvents[button] = copy
            }
            tracker.perform(output.commands)
            sync()
            return output.passes && !swallowRelease ? Unmanaged.passUnretained(event) : nil
        }

        /// Whether macOS has `button` (numbered from 1) down, whatever the taps did with its events.
        private static func isDown(_ button: Int) -> Bool {
            guard let cgButton = CGMouseButton(rawValue: UInt32(button - 1)) else { return false }
            return CGEventSource.buttonState(.hidSystemState, button: cgButton)
        }

        /// Posts held-back presses, oldest first, where the pointer is now (a click's press and release land on the
        /// same spot). From inside a tap callback they go just before the event it returns, and only the taps after
        /// Rambla's see them. From the timer they go where the mouse's events come in, so they carry a mark to get
        /// through Rambla's own tap again.
        private func giveBack(_ buttons: [Int], proxy: CGEventTapProxy?) {
            let pointer = CGEvent(source: nil)?.location
            for button in buttons {
                guard let event = heldEvents.removeValue(forKey: button) else { continue }
                if let pointer { event.location = pointer }
                if let proxy {
                    event.tapPostEvent(proxy)
                } else {
                    event.setIntegerValueField(.eventSourceUserData, value: MouseButtonTracker.replayMark)
                    event.post(tap: .cghidEventTap)
                }
            }
        }

        /// The moves' tap runs only while a button is held, and the timer wakes up when the chord's window ends.
        private func sync() {
            let holding = gesture.holdsButtons
            lock.withLock { busy = holding }
            if holding != motionEnabled, let motionTap {
                CGEvent.tapEnable(tap: motionTap, enable: holding)
                motionEnabled = holding
            }
            if !holding { heldEvents.removeAll() }
            guard let timer else { return }
            if let deadline = gesture.deadline {
                let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime) + 0.005
                CFRunLoopTimerSetNextFireDate(timer, CFAbsoluteTimeGetCurrent() + delay)
            } else {
                CFRunLoopTimerSetNextFireDate(timer, Date.distantFuture.timeIntervalSinceReferenceDate)
            }
        }

        /// The rest of the chord did not come in time: its presses so far go to the apps. A button already released
        /// is not given back: its release may be on its way to the apps already, and a press posted now would reach
        /// them after it and leave the button down for them.
        private func expire() {
            let due = gesture.expire(at: ProcessInfo.processInfo.systemUptime)
            for button in due where !Self.isDown(button) {
                dropped.insert(button)
                heldEvents[button] = nil
            }
            giveBack(due.filter { !dropped.contains($0) }, proxy: nil)
            sync()
        }

        /// Keeps every press from the apps and reports the combination: the most buttons that were down at once,
        /// once all of them are released.
        private func record(_ button: Int, down: Bool, for recording: Recording) {
            if recording !== self.recording {
                self.recording = recording
                recordingDown = []
                recordingBest = []
            }
            if down {
                recordingDown.insert(button)
                if recordingDown.count > recordingBest.count { recordingBest = recordingDown }
            } else {
                recordingDown.remove(button)
            }
            if recordingDown.isEmpty, !recordingBest.isEmpty {
                tracker.recordingFinished(recording, recordingBest.sorted())
                self.recording = nil
            } else {
                tracker.recordingChanged(recording, recordingDown.sorted())
            }
        }
    }
}
