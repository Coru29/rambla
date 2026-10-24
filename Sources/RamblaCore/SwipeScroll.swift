import Foundation

/// While the trackpad's swipe fingers are on it, macOS sends their movement to the app under the pointer as scrolling
/// (Rambla turned macOS's own swipes with that many fingers off), and a glide after they lift. Decides which trackpad
/// scroll events belong to such a swipe, so Rambla can keep them from the app.
///
/// The app feeds it every touch report and asks about every continuous scroll event. A swipe starts when its fingers
/// touch, and lasts while two or more of them do: as they lift unevenly, macOS starts a new scroll with the ones still
/// down, and that one is the swipe's too. With one finger left or none, the swipe glides. Everything the trackpad
/// sends then is the swipe's, phases included: with the last finger, macOS sends a `mayBegin`, and the glide comes
/// right after it. The glide ends only when it stops, `glideLimit` after the lift, or when two fingers or more land:
/// that is the user starting a scroll of their own, and the report of their fingers comes about 60 ms before macOS's
/// scroll. Another app's scrolling (Mac Mouse Fix smoothing the user's wheel, say) is the swipe's only while its
/// fingers are down. One finger makes no scroll, so a thumb resting on the trackpad never holds a swipe, and
/// two-finger scrolling never reaches the finger count, so it is left alone.
///
/// A scroll or a glide the app saw begin still gets its end, though the swipe's: the fourth finger's report came late,
/// say, or four fingers landed while the app glided. An end carries no movement, and without it the app would keep
/// the scroll open (Safari leaves an overscroll stretched).
public struct SwipeScroll: Sendable {
    /// Seconds without a touch report after which the fingers count as lifted (a lift can come without one).
    public static let staleAfter = 0.3
    /// The longest glide kept from the app after a swipe: the recorded ones lasted 0.4 to 0.5 s.
    public static let glideLimit = 1.5

    private enum State: Sendable {
        case idle
        /// The swipe's fingers landed; some may have lifted since, but two or more still touch.
        case swiping
        /// Down to one finger or none at `since`: what the trackpad sends is the swipe's, until the glide stops,
        /// `glideLimit` passes or new fingers land.
        case gliding(since: Double)
    }

    private let fingers: Int
    private var state = State.idle
    /// When the trackpad last reported its fingers.
    private var lastReport = -Double.infinity
    /// The app got a scroll's `began`, `mayBegin` or `changed`, and not yet its `ended` or `cancelled`.
    private var appScrollOpen = false
    /// The app got a glide's `began` or `changed`, and not yet its `ended`.
    private var appMomentumOpen = false

    public init(fingers: Int) {
        self.fingers = fingers
    }

    /// A touch report: `touching` fingers are on the trackpad at `time` (seconds, any steady clock).
    public mutating func touched(_ touching: Int, at time: Double) {
        endLostSwipe(at: time)
        lastReport = time
        if touching >= fingers {
            state = .swiping
        } else if case .swiping = state {
            // Two or more still down keep the swipe going while they lift; one left, or none, and it glides.
            if touching <= 1 { state = .gliding(since: time) }
        } else if case .gliding = state, touching >= 2 {
            // New fingers: the user starts a scroll of their own, and this report comes before macOS's scroll.
            state = .idle
        }
        // One finger landing, or a resting thumb, changes nothing.
    }

    /// A continuous scroll event (trackpad or Magic Mouse; its phases as `WheelGesture.Event` reads them) at `time`:
    /// true when it belongs to a swipe and must not reach the app. `fromHardware`: no app posted it. The phases decide
    /// nothing about the swipe (macOS sends one with its last finger, right before the glide). They tell which scroll
    /// and glide the app saw begin, so that their ends still reach it.
    public mutating func swallows(phase: WheelGesture.Event.Phase, momentum: WheelGesture.Event.Momentum,
                                  fromHardware: Bool, at time: Double) -> Bool {
        endLostSwipe(at: time)
        var swallowed = belongsToSwipe(momentum: momentum, fromHardware: fromHardware, at: time)
        // An end the app waits for still reaches it (a glide's end still ends the swipe's glide).
        if swallowed, appScrollOpen, phase == .ended || phase == .cancelled { swallowed = false }
        if swallowed, appMomentumOpen, momentum == .ended { swallowed = false }
        if !swallowed { appGot(phase: phase, momentum: momentum) }
        return swallowed
    }

    /// Whether a swipe or its glide is under way at `time`, even if no event came yet to end it: a new tap would let
    /// some of it through.
    public func isBusy(at time: Double) -> Bool {
        switch state {
        case .idle: return false
        // Gone stale, the swipe glides from its last report.
        case .swiping: return time - lastReport < Self.glideLimit
        case .gliding(let since): return time - since < Self.glideLimit
        }
    }

    private mutating func belongsToSwipe(momentum: WheelGesture.Event.Momentum, fromHardware: Bool,
                                         at time: Double) -> Bool {
        switch state {
        case .idle:
            return false
        case .swiping:
            return true
        case .gliding(let since):
            if time - since >= Self.glideLimit {
                state = .idle
                return false
            }
            // Another app's scrolling is not the glide's, and leaves it alone.
            guard fromHardware else { return false }
            // Everything else is, phases included; the end of the glide closes it.
            if momentum == .ended { state = .idle }
            return true
        }
    }

    /// Follows the scroll and the glide the app saw begin and not end, from an event that reached it.
    private mutating func appGot(phase: WheelGesture.Event.Phase, momentum: WheelGesture.Event.Momentum) {
        switch phase {
        case .began, .mayBegin, .changed: appScrollOpen = true
        case .ended, .cancelled: appScrollOpen = false
        case .none: break
        }
        switch momentum {
        case .began, .changed: appMomentumOpen = true
        case .ended: appMomentumOpen = false
        case .none: break
        }
    }

    /// The reports stopped without one for the lift: the swipe ends as if the fingers had lifted at their last report.
    private mutating func endLostSwipe(at time: Double) {
        guard case .swiping = state, time - lastReport > Self.staleAfter else { return }
        state = .gliding(since: lastReport)
    }
}
