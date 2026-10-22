import Testing
@testable import RamblaCore

// MARK: - Velocity

@Test func velocityNeedsTwoSamples() {
    var tracker = VelocityTracker()
    #expect(tracker.velocity(at: 0) == 0)
    tracker.add(10, at: 0)
    #expect(tracker.velocity(at: 0) == 0)
}

@Test func velocityOfASteadyMove() {
    var tracker = VelocityTracker()
    tracker.add(0, at: 0)
    tracker.add(10, at: 0.02)
    tracker.add(20, at: 0.04)
    #expect(abs(tracker.velocity(at: 0.04) - 500) < 1e-9)
}

@Test func velocityOnlyLooksAtTheLastMoments() {
    var tracker = VelocityTracker()
    tracker.add(0, at: 0)
    tracker.add(100, at: 0.5)      // a fast start…
    tracker.add(105, at: 0.55)     // …that slowed down before the release
    #expect(abs(tracker.velocity(at: 0.55) - 100) < 1e-9)
}

@Test func velocityIsZeroWhenTheMoveStoppedBeforeTheRelease() {
    var tracker = VelocityTracker()
    tracker.add(0, at: 0)
    tracker.add(10, at: 0.05)
    #expect(tracker.velocity(at: 0.3) == 0)
}

@Test func velocityResets() {
    var tracker = VelocityTracker()
    tracker.add(0, at: 0)
    tracker.add(10, at: 0.05)
    tracker.reset()
    #expect(tracker.velocity(at: 0.05) == 0)
}
