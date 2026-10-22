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
    /// touch. Fingers on the trackpad report about every 10 ms, even resting.
    public static let liftTimeout = 0.15

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

    /// Nil while the movement is too small or too slanted to tell.
    public static func kind(dx: Double, dy: Double) -> TrackpadSwipe? {
        if abs(dx) > horizontalStart, abs(dx) > abs(dy) { return .horizontal }
        if abs(dy) > verticalStart, abs(dy) > 2 * abs(dx) { return dy > 0 ? .up : .down }
        return nil
    }
}
