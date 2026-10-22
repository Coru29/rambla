import Testing
@testable import RamblaCore

// MARK: - Scroll wheel

private typealias Event = WheelGesture.Event

/// A notch of a plain mouse wheel. Negative `deltaY` scrolls a document forward (down), which moves the strip right.
private func notch(_ deltaY: Double, deltaX: Double = 0, at time: Double, keys: Bool = true) -> Event {
    Event(time: time, modifiers: keys, continuous: false, phase: .none, momentum: .none, deltaX: deltaX, deltaY: deltaY)
}

/// One event of a Magic Mouse or trackpad swipe, in points.
private func swipe(_ phase: Event.Phase, _ deltaY: Double = 0, deltaX: Double = 0, at time: Double,
                   keys: Bool = true, momentum: Event.Momentum = .none) -> Event {
    Event(time: time, modifiers: keys, continuous: true, phase: phase, momentum: momentum, deltaX: deltaX, deltaY: deltaY)
}

@Test func wheelLeavesScrollingAloneWithoutTheKeys() {
    var wheel = WheelGesture()
    #expect(wheel.handle(notch(-1, at: 0, keys: false)) == .pass)
    #expect(wheel.handle(swipe(.began, -10, at: 1, keys: false)) == .pass)
    #expect(wheel.handle(swipe(.changed, -10, at: 1.01, keys: false)) == .pass)
    #expect(wheel.handle(swipe(.ended, at: 1.02, keys: false)) == .pass)
    #expect(wheel.handle(swipe(.none, -30, at: 1.03, keys: false, momentum: .began)) == .pass)
}

@Test func wheelNotchesStepOneColumnEach() {
    var wheel = WheelGesture()
    #expect(wheel.handle(notch(-1, at: 0)) == .step(1))
    #expect(wheel.handle(notch(3, at: 0.1)) == .step(-1))             // a fast spin is still one column
    #expect(wheel.handle(notch(0, deltaX: -1, at: 0.2)) == .step(1))  // tilting the wheel to the right
    #expect(wheel.handle(notch(0, at: 0.3)) == .swallow)              // nothing to move, but still not the app's
}

@Test func wheelStepsAreSpacedOut() {
    var wheel = WheelGesture()
    #expect(wheel.handle(notch(-1, at: 0)) == .step(1))
    #expect(wheel.handle(notch(-1, at: 0.03)) == .swallow)
    #expect(wheel.handle(notch(-1, at: 0.07)) == .step(1))
}

@Test func aSwipeSlidesTheStripAndReleasesWithItsSpeed() {
    var wheel = WheelGesture()
    #expect(wheel.handle(swipe(.began, -10, at: 0)) == .slide(10, first: true))
    #expect(wheel.handle(swipe(.changed, -10, at: 0.01)) == .slide(10, first: false))
    #expect(wheel.handle(swipe(.changed, -10, at: 0.02)) == .slide(10, first: false))
    guard case .release(let velocity) = wheel.handle(swipe(.ended, at: 0.03)) else {
        Issue.record("the end of the swipe should release the strip")
        return
    }
    #expect(abs(velocity - 1000) < 1e-9)
    // The momentum macOS adds after the fingers lift belongs to the same swipe: the app must not scroll with it.
    #expect(wheel.handle(swipe(.none, -40, at: 0.05, momentum: .began)) == .swallow)
    #expect(wheel.handle(swipe(.none, -20, at: 0.07, keys: false, momentum: .changed)) == .swallow)
    #expect(wheel.handle(swipe(.none, at: 0.09, keys: false, momentum: .ended)) == .swallow)
    #expect(wheel.handle(swipe(.began, -10, at: 1, keys: false)) == .pass)
}

@Test func aSwipeThatStartedWithoutTheKeysStaysTheApps() {
    var wheel = WheelGesture()
    #expect(wheel.handle(swipe(.began, -10, at: 0, keys: false)) == .pass)
    #expect(wheel.handle(swipe(.changed, -10, at: 0.01)) == .pass)
    #expect(wheel.handle(swipe(.ended, at: 0.02)) == .pass)
    #expect(wheel.handle(swipe(.none, -40, at: 0.04, momentum: .began)) == .pass)
    #expect(wheel.handle(swipe(.none, at: 0.06, momentum: .ended)) == .pass)
    #expect(wheel.handle(swipe(.began, -10, at: 1)) == .slide(10, first: true))
}

@Test func lettingGoOfTheKeysMidSwipeKeepsSliding() {
    var wheel = WheelGesture()
    #expect(wheel.handle(swipe(.began, -10, at: 0)) == .slide(10, first: true))
    #expect(wheel.handle(swipe(.changed, -10, at: 0.01, keys: false)) == .slide(10, first: false))
    guard case .release = wheel.handle(swipe(.ended, at: 0.02, keys: false)) else {
        Issue.record("the swipe should still release the strip")
        return
    }
}

@Test func aSwipeFollowsItsMainAxis() {
    var wheel = WheelGesture()
    #expect(wheel.handle(swipe(.began, 2, deltaX: -8, at: 0)) == .slide(8, first: true))
    #expect(wheel.handle(swipe(.changed, -1, deltaX: 3, at: 0.01)) == .slide(-3, first: false))
    #expect(wheel.handle(swipe(.changed, 6, deltaX: 1, at: 0.02)) == .slide(-6, first: false))
}

@Test func aCancelledSwipeReleasesTheStrip() {
    var wheel = WheelGesture()
    #expect(wheel.handle(swipe(.began, -10, at: 0)) == .slide(10, first: true))
    guard case .release = wheel.handle(swipe(.cancelled, at: 0.01)) else {
        Issue.record("a cancelled swipe should release the strip")
        return
    }
    #expect(wheel.handle(notch(-1, at: 1, keys: false)) == .pass)
}

@Test func touchingWithoutMovingIsSwallowedOnlyWithTheKeys() {
    var wheel = WheelGesture()
    #expect(wheel.handle(swipe(.mayBegin, at: 0)) == .swallow)
    #expect(wheel.handle(swipe(.mayBegin, at: 1, keys: false)) == .pass)
}

@Test func smoothScrollingWithoutPhasesEndsAfterAPause() {
    // Some mouse drivers send continuous scrolling with no phases: the slide ends once the events stop.
    var wheel = WheelGesture()
    #expect(wheel.handle(swipe(.none, -5, at: 0)) == .slide(5, first: true))
    #expect(wheel.handle(swipe(.none, -5, at: 0.02)) == .slide(5, first: false))
    #expect(wheel.idle(at: 0.1) == .pass)                              // still within the pause
    #expect(wheel.idle(at: 0.2) == .release(velocity: 0))             // the strip had stopped long before
    #expect(wheel.idle(at: 0.3) == .pass)
    #expect(wheel.handle(swipe(.none, -5, at: 1, keys: false)) == .pass)
}

@Test func idleDoesNothingWithoutASlide() {
    var wheel = WheelGesture()
    #expect(wheel.idle(at: 5) == .pass)
    #expect(wheel.nextIdleCheck == nil)
}

@Test func aSwipeThatLostItsEndIsReleasedAfterAPause() {
    // A phased swipe normally ends with its own event; if that event never comes (the tap was off for a moment,
    // the mouse dropped), every app's scrolling would stay Rambla's.
    var wheel = WheelGesture()
    #expect(wheel.handle(swipe(.began, -10, at: 6)) == .slide(10, first: true))
    #expect(wheel.nextIdleCheck == 6 + WheelGesture.stalledTimeout)
    #expect(wheel.idle(at: 6.3) == .pass)
    #expect(wheel.idle(at: 6.6) == .release(velocity: 0))
    // If the fingers were only resting, the rest of that swipe is still Rambla's: it must not scroll the app.
    #expect(wheel.handle(swipe(.changed, -10, at: 6.7)) == .swallow)
    #expect(wheel.handle(notch(-1, at: 7, keys: false)) == .pass)
}

@Test func aNewSwipeOrANotchEndsASwipeThatLostItsEnd() {
    var wheel = WheelGesture()
    #expect(wheel.handle(swipe(.began, -10, at: 0)) == .slide(10, first: true))
    let next = wheel.handle(swipe(.began, -5, at: 0.2, keys: false))
    #expect(next == .releaseThen(velocity: 0, next: .pass))
    #expect(next.passesEvent)
    #expect(wheel.handle(swipe(.changed, -5, at: 0.21, keys: false)) == .pass)

    var other = WheelGesture()
    #expect(other.handle(swipe(.began, -10, at: 0)) == .slide(10, first: true))
    #expect(other.handle(notch(-1, at: 0.1, keys: false)) == .releaseThen(velocity: 0, next: .pass))
    #expect(other.handle(swipe(.began, -10, at: 1)) == .slide(10, first: true))
    #expect(other.handle(swipe(.began, -10, at: 1.2)) == .releaseThen(velocity: 0, next: .slide(10, first: true)))
}

@Test func theNextIdleCheckFollowsTheKindOfSlide() {
    var wheel = WheelGesture()
    #expect(wheel.handle(swipe(.none, -5, at: 2)) == .slide(5, first: true))
    #expect(wheel.nextIdleCheck == 2 + WheelGesture.idleTimeout)
    #expect(wheel.idle(at: 2.2) == .release(velocity: 0))
    #expect(wheel.nextIdleCheck == nil)
}

@Test func cancelReleasesASlideAndForgetsTheSwipe() {
    var wheel = WheelGesture()
    #expect(wheel.cancel() == .pass)
    #expect(wheel.handle(swipe(.began, -10, at: 0)) == .slide(10, first: true))
    #expect(wheel.cancel() == .release(velocity: 0))
    #expect(wheel.cancel() == .pass)
    #expect(wheel.handle(swipe(.changed, -10, at: 0.01, keys: false)) == .pass)  // what was left of it is the app's
}
