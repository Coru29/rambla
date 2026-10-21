import Foundation

/// A critically damped spring, used to animate window positions and the strip scroll.
/// `response` is the period of the underlying oscillator in seconds (ω = 2π / response); there is no overshoot
/// when the spring starts at rest. The state lives in the caller (`x`, `v`), so retargeting mid-flight keeps the
/// current position and velocity.
public struct Spring: Equatable, Sendable {
    public var response: Double

    public init(response: Double) {
        self.response = response
    }

    /// Longest integration sub-step: 1/240 s keeps semi-implicit Euler stable and smooth at these stiffnesses.
    private static let maxSubstep = 1.0 / 240

    /// Advances `x` and `v` by `dt` seconds towards `target`. Longer steps are split into equal sub-steps of at most
    /// 1/240 s. Non-positive or non-finite `dt` does nothing; a non-positive `response` jumps straight to the target.
    public func step(_ x: inout Double, _ v: inout Double, target: Double, dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        guard response > 0 else {
            x = target
            v = 0
            return
        }
        let omega = 2 * Double.pi / response
        // The epsilon keeps a step of exactly k/240 s at k sub-steps even when the division rounds up a hair.
        let count = max(1, Int((dt / Spring.maxSubstep - 1e-9).rounded(.up)))
        let h = dt / Double(count)
        for _ in 0..<count {
            let acceleration = -omega * omega * (x - target) - 2 * omega * v   // critical damping: c = 2ω
            v += acceleration * h
            x += v * h
        }
    }

    /// Close enough to stop animating: within half a point of the target and slower than 5 pt/s.
    public static func settled(_ x: Double, _ v: Double, target: Double) -> Bool {
        abs(x - target) < 0.5 && abs(v) < 5
    }
}
