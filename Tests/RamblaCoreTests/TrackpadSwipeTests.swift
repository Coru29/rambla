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

// MARK: - Up and down in strips mode

@Test func shortSwipeDownChangesStripOnLift() {
    var v = TrackpadVertical(mode: .strips)
    #expect(v.moved(.down, dy: -0.12) == .armed(up: false))
    #expect(v.moved(.down, dy: -0.2) == nil)
    #expect(v.lifted(dy: -0.2) == .strip(up: false))
}

@Test func shortSwipeUpChangesStripOnLift() {
    var v = TrackpadVertical(mode: .strips)
    #expect(v.moved(.up, dy: 0.12) == .armed(up: true))
    #expect(v.lifted(dy: 0.15) == .strip(up: true))
}

@Test func longSwipeUpTogglesWidthOnce() {
    var v = TrackpadVertical(mode: .strips)
    _ = v.moved(.up, dy: 0.12)
    #expect(v.moved(.up, dy: 0.31) == .toggleWidth)
    #expect(v.moved(.up, dy: 0.5) == nil)
    #expect(v.lifted(dy: 0.5) == nil)
}

@Test func longSwipeDownOpensTheOverviewInStripsMode() {
    var v = TrackpadVertical(mode: .strips)
    _ = v.moved(.down, dy: -0.12)
    #expect(v.moved(.down, dy: -0.31) == .overview)
    #expect(v.lifted(dy: -0.4) == nil)
}

@Test func comingBackBeforeLiftingDoesNothing() {
    var v = TrackpadVertical(mode: .strips)
    _ = v.moved(.down, dy: -0.12)
    #expect(v.lifted(dy: -0.05) == nil)
}

@Test func aFastSwipeGoesStraightToTheLongCommand() {
    var v = TrackpadVertical(mode: .strips)
    #expect(v.moved(.up, dy: 0.35) == .toggleWidth)
}

@Test func aFastSwipeDownGoesStraightToTheOverview() {
    var v = TrackpadVertical(mode: .strips)
    #expect(v.moved(.down, dy: -0.35) == .overview)                                  // not .armed first
    #expect(v.moved(.down, dy: -0.4) == nil)
    #expect(v.lifted(dy: -0.4) == nil)                                               // and no strip change after it
}

@Test func aSwipeUpThatComesBackBeforeLiftingDoesNothing() {
    var v = TrackpadVertical(mode: .strips)
    _ = v.moved(.up, dy: 0.12)
    #expect(v.lifted(dy: 0.05) == nil)
}

@Test func theFirstMoveDecidesTheDirectionOfAStripsSwipe() {
    // Going on past where the fingers landed does not turn an up swipe into a down one, nor the other way round.
    var up = TrackpadVertical(mode: .strips)
    _ = up.moved(.up, dy: 0.12)
    #expect(up.moved(nil, dy: -0.35) == nil)                                         // not the overview
    #expect(up.lifted(dy: -0.2) == nil)                                              // not a strip down either
    var down = TrackpadVertical(mode: .strips)
    _ = down.moved(.down, dy: -0.12)
    #expect(down.moved(nil, dy: 0.35) == nil)                                        // not the full width
    #expect(down.lifted(dy: 0.2) == nil)
}

@Test func inStripsModeASwipeIsVerticalOnceItGoesUpOrDown() {
    var sideways = TrackpadVertical(mode: .strips)
    #expect(sideways.moved(.horizontal, dy: 0.01) == nil)
    #expect(sideways.moved(nil, dy: 0.05) == nil)                                    // too slanted to tell yet
    #expect(!sideways.isVertical)                                                    // the rest of it may still slide
    var up = TrackpadVertical(mode: .strips)
    _ = up.moved(.up, dy: 0.12)
    #expect(up.isVertical)
    var down = TrackpadVertical(mode: .strips)
    _ = down.moved(.down, dy: -0.12)
    #expect(down.isVertical)
    var long = TrackpadVertical(mode: .strips)
    _ = long.moved(.up, dy: 0.35)
    #expect(long.isVertical)                                                         // done, and still not a slide
}

@Test func aSwipeThatNeverWentUpOrDownChangesNoStripOnLift() {
    // Every swipe ends with a lift, a slide with some vertical drift included.
    var slide = TrackpadVertical(mode: .strips)
    #expect(slide.moved(.horizontal, dy: 0.15) == nil)
    #expect(slide.lifted(dy: 0.15) == nil)
    var undecided = TrackpadVertical(mode: .strips)
    #expect(undecided.moved(nil, dy: -0.15) == nil)
    #expect(undecided.lifted(dy: -0.15) == nil)
}

@Test func theNextStripsSwipeStartsOverInTheSameMode() {
    var v = TrackpadVertical(mode: .strips)
    _ = v.moved(.down, dy: -0.12)
    #expect(v.lifted(dy: -0.15) == .strip(up: false))
    #expect(!v.isVertical)
    // Still strips mode: armed again, not the full width at once.
    #expect(v.moved(.up, dy: 0.12) == .armed(up: true))
    #expect(v.moved(.up, dy: 0.31) == .toggleWidth)
    #expect(v.lifted(dy: 0.5) == nil)
    #expect(v.moved(.down, dy: -0.12) == .armed(up: false))
}

@Test func widthModeIsTheDefault() {
    #expect(TrackpadVertical() == TrackpadVertical(mode: .width))
    var v = TrackpadVertical(mode: .width)
    #expect(v.moved(.up, dy: 0.12) == .fullWidth)
}

@Test func theLongSwipeIsThirtyPercentAndTheOverviewDistanceIsTheSame() {
    #expect(TrackpadVertical.longStart == 0.3)
    #expect(TrackpadVertical.overviewStart == TrackpadVertical.longStart)
}
