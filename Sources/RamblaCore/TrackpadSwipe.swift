import Foundation

/// Which way a trackpad swipe goes, from how far the fingers moved since they landed (fractions of the trackpad,
/// y growing upward like `NSTouch.normalizedPosition`). Sideways slides the strip; up and down are one-shot
/// commands, so they need a longer and clearly vertical move before they count.
public enum TrackpadSwipe: Equatable, Sendable {
    case horizontal, up, down

    /// Sideways movement that starts a slide.
    public static let horizontalStart = 0.015
    /// Vertical movement that counts as a swipe up or down.
    public static let verticalStart = 0.1
    /// Seconds without an event that has touches after which a swipe is over: macOS can report the fingers lifting
    /// with an event that carries none, and the swipe would otherwise stay open (and the wheel blocked) until the next
    /// touch. Fingers on the trackpad report about every 10 ms, even resting; the margin keeps a pause from ending a
    /// swipe if they ever do not.
    public static let liftTimeout = 0.2

    /// What a gesture event means for a swipe with `fingers` fingers.
    public enum Frame: Equatable, Sendable {
        /// An event without touches: it says nothing about the fingers.
        case ignore
        /// The swipe's fingers are all down: follow them.
        case track
        /// Fingers were lifted or added: the swipe is over.
        case end
    }

    /// `touching` counts the fingers down, `total` every touch the event carries (including the ones just lifted).
    /// With macOS's own four-finger swipes turned off, a gesture event without touches comes between every two
    /// real ones; reading it as "the fingers lifted" would restart the swipe on every event.
    public static func frame(touching: Int, total: Int, fingers: Int) -> Frame {
        if total == 0 { return .ignore }
        return touching == fingers ? .track : .end
    }

    /// Whether the fingers touching now (by `NSTouch.identity`, which a finger keeps while it touches) are all new
    /// since the last report that had some: those lifted in between, and macOS never reported the lift.
    public static func liftWentUnreported<Finger: Hashable>(before: Set<Finger>, now: Set<Finger>) -> Bool {
        !before.isEmpty && !now.isEmpty && before.isDisjoint(with: now)
    }

    /// Nil while the movement is too small or too slanted to tell.
    public static func kind(dx: Double, dy: Double) -> TrackpadSwipe? {
        if abs(dx) > horizontalStart, abs(dx) > abs(dy) { return .horizontal }
        if abs(dy) > verticalStart, abs(dy) > 2 * abs(dx) { return dy > 0 ? .up : .down }
        return nil
    }
}

/// Up and down on the trackpad, like with the mouse buttons. One command per swipe, and a long swipe down opens the
/// overview in both modes; the rest depends on `mode`:
/// - Width mode: up gives the full width at once; down is decided when the fingers lift (back to the previous width),
///   unless they go down `longStart` first; back up before lifting, nothing.
/// - Strips mode: the first move up or down arms a short swipe, which changes strip when the fingers lift (back below
///   the short distance before lifting, nothing); a long swipe up gives the focused column the full width (or gives it
///   back) at once.
public struct TrackpadVertical: Equatable, Sendable {
    public enum Command: Equatable, Sendable {
        /// Width mode: the focused column takes the full width.
        case fullWidth
        /// Width mode: the focused column goes back to its previous width.
        case previousWidth
        /// A long swipe down, in both modes.
        case overview
        /// Strips mode: a long swipe up gives the focused column the full width, or gives it back.
        case toggleWidth
        /// Strips mode: a short swipe, decided when the fingers lift: change strip. `up`: the fingers went up.
        case strip(up: Bool)
        /// Strips mode: the swipe just became a short vertical one, so lifting now changes strip (the cue for a haptic
        /// tap). `up`: the fingers went up.
        case armed(up: Bool)
    }

    /// How far (a fraction of the trackpad's height) a long swipe goes: down opens the overview, and in strips mode up
    /// gives the full width.
    public static let longStart = 0.3
    /// How far down opens the overview: the long swipe's distance.
    public static let overviewStart = longStart

    private let mode: VerticalGesture
    private var goingUp = false
    private var goingDown = false
    private var done = false

    public init(mode: VerticalGesture = .width) {
        self.mode = mode
    }

    /// The swipe went up or down: the rest of it does not slide the strip.
    public var isVertical: Bool { goingUp || goingDown || done }

    /// The fingers are `dy` from where they landed (a fraction of the trackpad's height, up positive), and the swipe
    /// reads as `kind` so far.
    public mutating func moved(_ kind: TrackpadSwipe?, dy: Double) -> Command? {
        guard !done else { return nil }
        if mode == .strips { return movedInStripsMode(kind, dy: dy) }
        if !goingDown {
            if kind == .up {
                done = true
                return .fullWidth
            }
            guard kind == .down else { return nil }
            goingDown = true
        }
        guard dy <= -Self.overviewStart else { return nil }
        done = true
        return .overview
    }

    /// The fingers lifted `dy` from where they landed; the next swipe starts over, in the same mode.
    public mutating func lifted(dy: Double) -> Command? {
        defer { self = TrackpadVertical(mode: mode) }
        switch mode {
        case .width:
            return goingDown && !done && dy <= -TrackpadSwipe.verticalStart ? .previousWidth : nil
        case .strips:
            guard !done else { return nil }
            if goingUp, dy >= TrackpadSwipe.verticalStart { return .strip(up: true) }
            if goingDown, dy <= -TrackpadSwipe.verticalStart { return .strip(up: false) }
            return nil
        }
    }

    /// Strips mode: the first move that reads as up or down arms a short swipe (or acts at once when it is already
    /// long). The direction is then fixed, and only going far enough that way acts: going on past where the fingers
    /// landed is neither the full width nor the overview.
    private mutating func movedInStripsMode(_ kind: TrackpadSwipe?, dy: Double) -> Command? {
        var arming = false
        if !goingUp, !goingDown {
            switch kind {
            case .up?: goingUp = true
            case .down?: goingDown = true
            default: return nil
            }
            arming = true
        }
        if goingUp, dy >= Self.longStart {
            done = true
            return .toggleWidth
        }
        if goingDown, dy <= -Self.longStart {
            done = true
            return .overview
        }
        return arming ? .armed(up: goingUp) : nil
    }
}
