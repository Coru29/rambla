import Foundation

/// How fast a value was moving in the last moments of a gesture: the speed a released strip carries into `settle`.
public struct VelocityTracker: Sendable {
    /// Only samples this recent (seconds) count, so a swipe that slowed down before the release is slow.
    public static let window = 0.1

    private var samples: [(time: Double, value: Double)] = []

    public init() {}

    public mutating func add(_ value: Double, at time: Double) {
        samples.append((time, value))
        samples.removeAll { $0.time < time - Self.window }
    }

    public mutating func reset() {
        samples.removeAll()
    }

    /// Units per second over the recent samples. Zero with fewer than two of them, and when the release at `time`
    /// came more than a window after the last movement (the fingers stopped before lifting).
    public func velocity(at time: Double) -> Double {
        guard let first = samples.first, let last = samples.last, last.time > first.time,
              time - last.time <= Self.window else { return 0 }
        return (last.value - first.value) / (last.time - first.time)
    }
}
