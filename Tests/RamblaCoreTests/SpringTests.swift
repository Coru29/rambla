import Testing
@testable import RamblaCore

@Test func springConverges() {
    let spring = Spring(response: 0.25)
    var x = 0.0, v = 0.0
    for _ in 0..<36 { spring.step(&x, &v, target: 100, dt: 1.0 / 60) }   // 0.6 s of 60 Hz frames
    #expect(Spring.settled(x, v, target: 100))
    #expect(abs(x - 100) < 0.5)
}

@Test func springIsStillMovingAfterAFewFrames() {
    let spring = Spring(response: 0.25)
    var x = 0.0, v = 0.0
    for _ in 0..<3 { spring.step(&x, &v, target: 100, dt: 1.0 / 60) }
    #expect(x > 0 && x < 100)
    #expect(v > 0)
    #expect(!Spring.settled(x, v, target: 100))
}

@Test func springNeverOvershootsFromRest() {
    let spring = Spring(response: 0.25)
    for (start, target) in [(0.0, 100.0), (100.0, 0.0), (-40.0, 250.0)] {
        var x = start, v = 0.0
        var previous = start
        let direction = target > start ? 1.0 : -1.0
        for _ in 0..<120 {
            spring.step(&x, &v, target: target, dt: 1.0 / 60)
            #expect((x - previous) * direction >= -1e-9, "moved away from the target")
            #expect((target - x) * direction >= -1e-9, "overshot the target")
            previous = x
        }
        #expect(Spring.settled(x, v, target: target))
    }
}

@Test func springSplitsLargeStepsIntoStableSubSteps() {
    let spring = Spring(response: 0.25)
    // One 1/30 s step is exactly two 1/60 s steps (both are 8 sub-steps of 1/240 s).
    var x1 = 0.0, v1 = 0.0
    spring.step(&x1, &v1, target: 100, dt: 1.0 / 30)
    var x2 = 0.0, v2 = 0.0
    spring.step(&x2, &v2, target: 100, dt: 1.0 / 60)
    spring.step(&x2, &v2, target: 100, dt: 1.0 / 60)
    #expect(abs(x1 - x2) < 1e-9)
    #expect(abs(v1 - v2) < 1e-9)
    // A stalled main thread can hand over a very long frame; it must not blow up.
    for dt in [0.6, 1.0, 5.0] {
        var x = 0.0, v = 0.0
        spring.step(&x, &v, target: 100, dt: dt)
        #expect(x.isFinite && v.isFinite)
        #expect(Spring.settled(x, v, target: 100), "dt \(dt)")
    }
    var x = 0.0, v = 0.0
    spring.step(&x, &v, target: 100, dt: 0.25)
    #expect(x > 90 && x < 100)
}

@Test func springIsFasterWithASmallerResponse() {
    func positionAfter150ms(response: Double) -> Double {
        var x = 0.0, v = 0.0
        for _ in 0..<9 { Spring(response: response).step(&x, &v, target: 100, dt: 1.0 / 60) }   // 0.15 s
        return x
    }
    let quick = positionAfter150ms(response: 0.1)
    let normal = positionAfter150ms(response: 0.25)
    let slow = positionAfter150ms(response: 0.4)
    #expect(quick > normal)
    #expect(normal > slow)
}

@Test func springKeepsItsStateWhenDtIsNotUsable() {
    let spring = Spring(response: 0.25)
    for dt in [0.0, -1.0 / 60, Double.nan, Double.infinity] {
        var x = 12.0, v = -3.0
        spring.step(&x, &v, target: 100, dt: dt)
        #expect(x == 12.0 && v == -3.0, "dt \(dt) must not move the spring")
    }
}

@Test func springWithoutResponseSnapsToTarget() {
    for response in [0.0, -1.0] {
        var x = 5.0, v = 200.0
        Spring(response: response).step(&x, &v, target: 80, dt: 1.0 / 60)
        #expect(x == 80)
        #expect(v == 0)
    }
}

@Test func springResponseIsAMutableProperty() {
    var spring = Spring(response: 0.25)
    #expect(spring.response == 0.25)
    spring.response = 0.5
    #expect(spring.response == 0.5)
}

@Test func settledThresholds() {
    #expect(Spring.settled(100, 0, target: 100))
    #expect(Spring.settled(100.49, 4.99, target: 100))
    #expect(Spring.settled(99.51, -4.99, target: 100))
    #expect(!Spring.settled(100.5, 0, target: 100))      // distance must be strictly below 0.5
    #expect(!Spring.settled(99.5, 0, target: 100))
    #expect(!Spring.settled(100, 5, target: 100))        // speed must be strictly below 5
    #expect(!Spring.settled(100, -5, target: 100))
    #expect(!Spring.settled(0, 0, target: 100))
}
