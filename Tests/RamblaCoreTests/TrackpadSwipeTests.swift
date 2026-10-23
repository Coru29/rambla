import Testing
@testable import RamblaCore

// Finger movement as a fraction of the trackpad (y grows upward, like NSTouch.normalizedPosition).

@Test func swipeStaysUndecidedForTinyMoves() {
    #expect(TrackpadSwipe.kind(dx: 0.01, dy: 0.005) == nil)
    #expect(TrackpadSwipe.kind(dx: 0, dy: 0.05) == nil)       // vertical needs a longer move than horizontal
}

@Test func swipeSideways() {
    #expect(TrackpadSwipe.kind(dx: 0.02, dy: 0.01) == .horizontal)
    #expect(TrackpadSwipe.kind(dx: -0.03, dy: 0.02) == .horizontal)
}

@Test func swipeUpAndDown() {
    #expect(TrackpadSwipe.kind(dx: 0.01, dy: 0.12) == .up)
    #expect(TrackpadSwipe.kind(dx: -0.02, dy: -0.15) == .down)
}

@Test func aDiagonalSwipeIsNeither() {
    // Mostly upward but too slanted to be sure: wait for more movement rather than guess.
    #expect(TrackpadSwipe.kind(dx: 0.08, dy: 0.12) == nil)
}

@Test func touchlessGestureEventsAreIgnored() {
    // With macOS's own four-finger swipes off, a gesture event without touches comes between every two real ones.
    #expect(TrackpadSwipe.frame(touching: 0, total: 0, fingers: 4) == .ignore)
}

@Test func aSwipeEndsWhenTheFingersChange() {
    #expect(TrackpadSwipe.frame(touching: 4, total: 4, fingers: 4) == .track)
    #expect(TrackpadSwipe.frame(touching: 3, total: 4, fingers: 4) == .end)     // one finger lifted
    #expect(TrackpadSwipe.frame(touching: 0, total: 4, fingers: 4) == .end)     // all of them at once
    #expect(TrackpadSwipe.frame(touching: 2, total: 2, fingers: 4) == .end)     // a two-finger scroll
}

@Test func newFingersMeanTheLiftWentUnreported() {
    // Fingers by `NSTouch.identity`, which a finger keeps while it touches. All of them new: the others lifted in
    // between, and macOS never reported it.
    #expect(TrackpadSwipe.liftWentUnreported(before: [1, 2, 3, 4], now: [5, 6]))
    #expect(!TrackpadSwipe.liftWentUnreported(before: [1, 2, 3, 4], now: [1, 2]))     // lifting one by one
    #expect(!TrackpadSwipe.liftWentUnreported(before: [1], now: [1, 5, 6]))           // landing beside a resting one
    #expect(!TrackpadSwipe.liftWentUnreported(before: [], now: [5, 6]))               // the lift was reported
    #expect(!TrackpadSwipe.liftWentUnreported(before: [1, 2], now: []))               // the lift itself
}

// MARK: - Up and down

@Test func upGivesTheFullWidthAtOnce() {
    var swipe = TrackpadVertical()
    let first = swipe.moved(.up, dy: 0.12)
    let again = swipe.moved(.up, dy: 0.4)
    let lift = swipe.lifted(dy: 0.4)
    #expect(first == .fullWidth)
    #expect(again == nil)                                                            // one command per swipe
    #expect(lift == nil)
}

@Test func downIsDecidedWhenTheFingersLift() {
    var swipe = TrackpadVertical()
    let down = swipe.moved(.down, dy: -0.12)
    #expect(down == nil)
    #expect(swipe.isVertical)                                                        // the rest does not slide
    #expect(swipe.lifted(dy: -0.15) == .previousWidth)
    // Back up before lifting: nothing.
    var back = TrackpadVertical()
    _ = back.moved(.down, dy: -0.12)
    let up = back.moved(nil, dy: -0.02)
    #expect(up == nil)
    #expect(back.lifted(dy: -0.02) == nil)
}

@Test func downFarOpensTheOverview() {
    var swipe = TrackpadVertical()
    _ = swipe.moved(.down, dy: -0.12)
    let far = swipe.moved(nil, dy: -0.31)
    let further = swipe.moved(nil, dy: -0.5)
    #expect(far == .overview)
    #expect(further == nil)
    #expect(swipe.lifted(dy: -0.5) == nil)                                          // not the previous width too
    // The next swipe starts over.
    let next = swipe.moved(.up, dy: 0.12)
    #expect(next == .fullWidth)
}

@Test func sidewaysIsNotVertical() {
    var swipe = TrackpadVertical()
    let sideways = swipe.moved(.horizontal, dy: 0.01)
    #expect(sideways == nil)
    #expect(!swipe.isVertical)
}
