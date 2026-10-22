import Foundation

/// Turns scroll events into strip movement while the chosen keys are held: a mouse wheel moves one column per
/// notch, and a continuous swipe (Magic Mouse, or two fingers on a trackpad) slides the strip and lets it settle,
/// like the trackpad gesture. Everything else stays the app's: scrolling without the keys, and a swipe that began
/// without them, even if they are pressed halfway through. The app feeds it every scroll event and acts on the result.
public struct WheelGesture: Sendable {
    public struct Event: Equatable, Sendable {
        /// `kCGScrollWheelEventScrollPhase` of a continuous device.
        public enum Phase: Sendable { case none, mayBegin, began, changed, ended, cancelled }
        /// `kCGScrollWheelEventMomentumPhase`: the glide macOS adds after the fingers lift.
        public enum Momentum: Sendable { case none, began, changed, ended }

        /// Seconds, on any steady clock.
        public var time: Double
        /// The chosen keys, and only those, are held.
        public var modifiers: Bool
        /// A Magic Mouse or trackpad (points), rather than a wheel that clicks (lines).
        public var continuous: Bool
        public var phase: Phase
        public var momentum: Momentum
        /// Like `NSEvent.scrollingDeltaX/Y`: negative values scroll a document forward (right, down), with the
        /// user's scrolling direction already applied by macOS.
        public var deltaX: Double
        public var deltaY: Double

        public init(time: Double, modifiers: Bool, continuous: Bool, phase: Phase, momentum: Momentum,
                    deltaX: Double, deltaY: Double) {
            self.time = time
            self.modifiers = modifiers
            self.continuous = continuous
            self.phase = phase
            self.momentum = momentum
            self.deltaX = deltaX
            self.deltaY = deltaY
        }
    }

    public enum Output: Equatable, Sendable {
        /// Not Rambla's: the app under the pointer scrolls as usual.
        case pass
        /// Rambla's, with nothing to do (keeps the app from scrolling).
        case swallow
        /// Focus the column this many places to the right (negative: left).
        case step(Int)
        /// Slide the strip this many points toward later columns; `first` starts a slide.
        case slide(Double, first: Bool)
        /// The slide ended: let the strip settle, carrying this speed (points per second).
        case release(velocity: Double)
        /// The previous slide lost its end event and this event ended it: release it, then act on `next`.
        indirect case releaseThen(velocity: Double, next: Output)

        /// Whether the app under the pointer should still get the event.
        public var passesEvent: Bool {
            switch self {
            case .pass: return true
            case .releaseThen(_, let next): return next.passesEvent
            default: return false
            }
        }
    }

    /// The shortest time between two wheel steps, so a spun wheel does not fly over the whole strip.
    public static let stepInterval = 0.06
    /// A continuous scroll without phases (some mouse drivers) ends after this long without events.
    public static let idleTimeout = 0.15
    /// A phased swipe whose end event never came (the tap was off for a moment, the mouse dropped) is released after
    /// this long without events, so the other apps get their scrolling back.
    public static let stalledTimeout = 0.5

    private enum State: Sendable {
        case idle
        /// Rambla's slide: `phased` swipes end with their own event, the others after `idleTimeout`.
        case sliding(phased: Bool)
        /// The momentum after a Rambla slide: it is swallowed until it ends.
        case gliding
        /// A swipe (or its momentum) that began without the keys: left alone until it ends.
        case foreign
    }

    private var state = State.idle
    private var position = 0.0
    private var velocity = VelocityTracker()
    private var lastStep = -Double.infinity
    private var lastSlide = 0.0

    public init() {}

    public mutating func handle(_ e: Event) -> Output {
        switch state {
        case .sliding(let phased):
            return slide(e, phased: phased)
        case .gliding:
            if e.momentum == .none, e.phase == .none || e.phase == .began || e.phase == .mayBegin {
                state = .idle
                return handle(e)
            }
            if e.momentum == .ended { state = .idle }
            return .swallow
        case .foreign:
            if e.phase == .began || e.phase == .mayBegin || (e.phase == .none && e.momentum == .none) {
                state = .idle
                return handle(e)
            }
            if e.momentum == .ended || (e.momentum == .none && (e.phase == .ended || e.phase == .cancelled)) {
                state = .idle
            }
            return .pass
        case .idle:
            return start(e)
        }
    }

    /// A slide or the glide after it is under way: the app must not replace its tap now, or the rest would go to the
    /// app under the pointer.
    public var isBusy: Bool {
        switch state {
        case .sliding, .gliding: return true
        case .idle, .foreign: return false
        }
    }

    /// When the app should call `idle(at:)` next: while a slide is under way, the moment it would time out.
    public var nextIdleCheck: Double? {
        guard case .sliding(let phased) = state else { return nil }
        return lastSlide + (phased ? Self.stalledTimeout : Self.idleTimeout)
    }

    /// Ends a slide once its events have stopped: `idleTimeout` for one without phases (that is how it ends), and
    /// `stalledTimeout` for a phased one whose end event got lost. The app calls it from a timer.
    public mutating func idle(at time: Double) -> Output {
        guard let deadline = nextIdleCheck, time >= deadline else { return .pass }
        // A stalled phased swipe goes on gliding: if the fingers were only resting, the rest of it is still Rambla's,
        // and the next swipe or notch starts over.
        return release(at: time)
    }

    /// Drops whatever was under way (the feature was turned off): a slide is released without speed.
    public mutating func cancel() -> Output {
        defer {
            state = .idle
            velocity.reset()
        }
        if case .sliding = state { return .release(velocity: 0) }
        return .pass
    }

    // MARK: - States

    private mutating func start(_ e: Event) -> Output {
        guard e.continuous else {
            guard e.modifiers else { return .pass }
            let delta = Self.stripDelta(e)
            guard delta != 0, e.time - lastStep >= Self.stepInterval else { return .swallow }
            lastStep = e.time
            return .step(delta > 0 ? 1 : -1)
        }
        switch (e.phase, e.momentum) {
        case (.mayBegin, _):
            return e.modifiers ? .swallow : .pass
        case (.began, _), (.none, .none):
            guard e.modifiers else {
                if e.phase == .began { state = .foreign }
                return .pass
            }
            state = .sliding(phased: e.phase == .began)
            position = 0
            velocity.reset()
            return move(e, first: true)
        default:
            // The middle or the momentum of a swipe that started before the keys were held.
            if !(e.momentum == .ended || e.phase == .ended || e.phase == .cancelled) { state = .foreign }
            return .pass
        }
    }

    private mutating func slide(_ e: Event, phased: Bool) -> Output {
        if phased, e.phase == .ended || e.phase == .cancelled {
            return release(at: e.time)
        }
        if phased, e.phase == .began || e.phase == .mayBegin || !e.continuous {
            // A new swipe or a wheel notch while a swipe is still open: its end event got lost. Close it and let
            // this event start over (the app gets it if it is not Rambla's).
            _ = release(at: e.time)
            state = .idle
            return .releaseThen(velocity: 0, next: handle(e))
        }
        if !phased, e.phase == .began || e.momentum != .none {
            // A phased swipe after a phaseless one: close the first slide and treat this one as new.
            _ = release(at: e.time)
            state = .idle
            return handle(e)
        }
        guard e.continuous else { return .swallow }
        return move(e, first: false)
    }

    private mutating func move(_ e: Event, first: Bool) -> Output {
        let delta = Self.stripDelta(e)
        position += delta
        velocity.add(position, at: e.time)
        lastSlide = e.time
        return .slide(delta, first: first)
    }

    private mutating func release(at time: Double) -> Output {
        let speed = velocity.velocity(at: time)
        if case .sliding(phased: true) = state { state = .gliding } else { state = .idle }
        velocity.reset()
        return .release(velocity: speed)
    }

    /// Strip points (or wheel lines) toward later columns: the event's main axis, flipped because a negative
    /// delta scrolls a document forward.
    private static func stripDelta(_ e: Event) -> Double {
        abs(e.deltaX) > abs(e.deltaY) ? -e.deltaX : -e.deltaY
    }
}
