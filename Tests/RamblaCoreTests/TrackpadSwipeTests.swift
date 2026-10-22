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
