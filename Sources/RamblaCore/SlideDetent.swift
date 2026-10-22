import Foundation

/// The ticks a slide by hand gives on the trackpad, like detents: one each time the column edge the strip would
/// settle on, let go there without speed, changes. Edges closer than `minimumStep` (the last columns, which share the
/// end of the strip) count as one, so a slide never buzzes.
public struct SlideDetent: Sendable {
    public static let minimumStep = 32.0

    private var stop: Double?

    public init() {}

    /// Whether the strip at `scroll` would settle on another edge than before (never on the first call, which only
    /// notes where the slide starts).
    public mutating func crossed(_ m: StripMetrics, scroll: Double) -> Bool {
        let target = Layout.settle(m, scroll: scroll).scroll
        guard let stop else {
            self.stop = target
            return false
        }
        guard abs(target - stop) >= Self.minimumStep else { return false }
        self.stop = target
        return true
    }
}
