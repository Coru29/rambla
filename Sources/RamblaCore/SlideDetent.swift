import Foundation

/// The taps a slide by hand gives on the trackpad, like detents: one each time the column the strip would land on,
/// let go now, changes. The landing counts the speed (`Layout.settle`), so a quick flick taps as soon as it would
/// reach the next column, while the fingers are still on the trackpad; a slow slide taps halfway between columns.
public struct SlideDetent: Sendable {
    /// Landing edges closer than this (the last columns, which share the end of the strip) count as one.
    public static let minimumStep = 32.0
    /// Taps closer than this (seconds) would buzz, as when a speed right at the flick threshold flips the landing
    /// back and forth.
    public static let minimumInterval = 0.08

    private var landing: Double?
    private var lastTap = -Double.infinity
    private var travel = 0.0
    private var speed = VelocityTracker()

    public init() {}

    /// The strip moved `points` to `scroll` at `time` (seconds). Whether to tap: let go now, it would land on another
    /// column than at the last tap (never on the first move, which notes where the slide starts).
    public mutating func moved(by points: Double, to scroll: Double, in m: StripMetrics, at time: Double) -> Bool {
        travel += points
        speed.add(travel, at: time)
        let target = Layout.settle(m, scroll: scroll, velocity: speed.velocity(at: time)).scroll
        guard let landing else {
            self.landing = target
            return false
        }
        guard abs(target - landing) >= Self.minimumStep, time - lastTap >= Self.minimumInterval else { return false }
        self.landing = target
        lastTap = time
        return true
    }
}
