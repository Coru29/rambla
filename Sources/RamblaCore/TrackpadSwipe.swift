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

    /// Nil while the movement is too small or too slanted to tell.
    public static func kind(dx: Double, dy: Double) -> TrackpadSwipe? {
        if abs(dx) > horizontalStart, abs(dx) > abs(dy) { return .horizontal }
        if abs(dy) > verticalStart, abs(dy) > 2 * abs(dx) { return dy > 0 ? .up : .down }
        return nil
    }
}
