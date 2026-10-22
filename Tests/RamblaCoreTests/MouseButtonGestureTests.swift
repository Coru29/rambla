import Testing
@testable import RamblaCore

// Pointer movement in points, y growing downward (like screen coordinates). Buttons are numbered like mouse apps
// number them: 3 is the middle button, 4 and 5 the side ones.

private typealias Output = MouseButtonGesture.Output

/// The event goes on to the apps, with nothing replayed and nothing to do.
private let passes = Output(passes: true)
/// Rambla's, with nothing to do.
private let swallowed = Output(passes: false)

private func isSlideEnd(_ output: Output) -> Bool {
    guard case .slideEnded? = output.commands.first else { return false }
    return output.commands.count == 1
}

// MARK: - One button

@Test func draggingSidewaysWithTheButtonSlidesTheStrip() {
    var gesture = MouseButtonGesture(buttons: [3])
    #expect(gesture.handle(.down(3), at: 0) == swallowed)
    #expect(gesture.holdsButtons)
    #expect(gesture.deadline == nil)                                              // nothing else to wait for
    #expect(gesture.handle(.drag(dx: -5, dy: 1), at: 0.01) == swallowed)          // not enough yet
    // The slide starts where the pointer already is.
    #expect(gesture.handle(.drag(dx: -5, dy: 0), at: 0.02) == Output(passes: false, commands: [.slideBegan, .slide(-10)]))
    #expect(gesture.handle(.drag(dx: -10, dy: 3), at: 0.03) == Output(passes: false, commands: [.slide(-10)]))
    let end = gesture.handle(.up(3), at: 0.04)
    #expect(end.passes == false && end.replay.isEmpty)
    guard case .slideEnded(let velocity)? = end.commands.first else {
        Issue.record("letting go should end the slide")
        return
    }
    #expect(abs(velocity + 1000) < 1e-6)                                          // 10 points left every 10 ms
    #expect(!gesture.holdsButtons)
}

@Test func stoppingBeforeLettingGoReleasesWithoutSpeed() {
    var gesture = MouseButtonGesture(buttons: [3])
    _ = gesture.handle(.down(3), at: 0)
    _ = gesture.handle(.drag(dx: 20, dy: 0), at: 0.01)
    _ = gesture.handle(.drag(dx: 20, dy: 0), at: 0.02)
    #expect(gesture.handle(.up(3), at: 0.5) == Output(passes: false, commands: [.slideEnded(velocity: 0)]))
}

@Test func aClickOfTheButtonStillReachesTheApps() {
    var gesture = MouseButtonGesture(buttons: [3])
    #expect(gesture.handle(.down(3), at: 0) == swallowed)
    #expect(gesture.handle(.drag(dx: 2, dy: -3), at: 0.05) == swallowed)          // a hand never holds perfectly still
    #expect(gesture.handle(.up(3), at: 0.1) == Output(replay: [3], passes: true))
    #expect(!gesture.holdsButtons)
}

@Test func aPressThatDecidedNothingIsStillAClick() {
    // Pressing the wheel moves the mouse: whatever did not become a gesture is the click the hand meant.
    var gesture = MouseButtonGesture(buttons: [3])
    _ = gesture.handle(.down(3), at: 0)
    #expect(gesture.handle(.drag(dx: 7, dy: 0), at: 0.03) == swallowed)           // sideways, but not a slide yet
    #expect(gesture.handle(.drag(dx: -3, dy: 30), at: 0.05) == swallowed)         // down, but not far enough
    #expect(gesture.handle(.up(3), at: 0.1) == Output(replay: [3], passes: true))
}

@Test func turningTheWheelWithTheButtonHeldHandsItOn() {
    // Holding the button and turning the wheel is the app's (or Mac Mouse Fix's) business: no click afterwards.
    var gesture = MouseButtonGesture(buttons: [4])
    _ = gesture.handle(.down(4), at: 0)
    #expect(gesture.handle(.scroll, at: 0.4) == Output(replay: [4], passes: true))
    #expect(gesture.handle(.drag(dx: 30, dy: 0), at: 0.5) == passes)
    #expect(gesture.handle(.up(4), at: 0.6) == passes)
}

@Test func upAndDownAreOneCommandPerPress() {
    var gesture = MouseButtonGesture(buttons: [3])
    _ = gesture.handle(.down(3), at: 0)
    #expect(gesture.handle(.drag(dx: 2, dy: -25), at: 0.02) == swallowed)
    #expect(gesture.handle(.drag(dx: 1, dy: -20), at: 0.04) == Output(passes: false, commands: [.vertical(up: true)]))
    #expect(gesture.handle(.drag(dx: 0, dy: -50), at: 0.06) == swallowed)         // the rest of that press
    #expect(gesture.handle(.drag(dx: 90, dy: 0), at: 0.08) == swallowed)          // even sideways
    #expect(gesture.handle(.up(3), at: 0.1) == swallowed)
    // Down waits for the release: a longer move down is the overview.
    _ = gesture.handle(.down(3), at: 1)
    #expect(gesture.handle(.drag(dx: -3, dy: 45), at: 1.02) == swallowed)
    #expect(gesture.handle(.up(3), at: 1.1) == Output(passes: false, commands: [.vertical(up: false)]))
}

@Test func aLongMoveDownOpensTheOverview() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    _ = gesture.handle(.down(5), at: 0.01)
    #expect(gesture.handle(.drag(dx: 2, dy: 60), at: 0.03) == swallowed)          // the width, if released now
    #expect(gesture.handle(.drag(dx: -4, dy: 110), at: 0.06) == Output(passes: false, commands: [.overview]))
    #expect(gesture.handle(.drag(dx: 0, dy: 80), at: 0.08) == swallowed)          // once per press
    #expect(gesture.handle(.up(4), at: 0.2) == swallowed)
    #expect(gesture.handle(.up(5), at: 0.21) == swallowed)
}

@Test func comingBackUpBeforeLettingGoChangesNothing() {
    var gesture = MouseButtonGesture(buttons: [3])
    _ = gesture.handle(.down(3), at: 0)
    _ = gesture.handle(.drag(dx: 0, dy: 60), at: 0.03)
    #expect(gesture.handle(.drag(dx: 0, dy: -45), at: 0.06) == swallowed)         // back near where it started
    #expect(gesture.handle(.up(3), at: 0.2) == swallowed)                         // neither the width nor a click
}

@Test func aMoveDownThatLosesItsReleaseDoesNothing() {
    var gesture = MouseButtonGesture(buttons: [3])
    _ = gesture.handle(.down(3), at: 0)
    _ = gesture.handle(.drag(dx: 0, dy: 60), at: 0.03)
    #expect(gesture.handle(.released, at: 0.1) == passes)                         // no width change on a guess
}

@Test func aSlantedDragWaitsForAClearerOne() {
    var gesture = MouseButtonGesture(buttons: [3])
    _ = gesture.handle(.down(3), at: 0)
    #expect(gesture.handle(.drag(dx: 30, dy: -45), at: 0.02) == swallowed)        // mostly up, but too slanted
    #expect(gesture.handle(.drag(dx: 20, dy: 0), at: 0.04) == Output(passes: false, commands: [.slideBegan, .slide(50)]))
}

// MARK: - Several buttons

@Test func pressingTheSideButtonsTogetherAndDraggingSlidesTheStrip() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    #expect(gesture.handle(.down(4), at: 0) == swallowed)
    #expect(gesture.deadline == MouseButtonGesture.chordWindow)
    #expect(gesture.handle(.down(5), at: 0.05) == swallowed)
    #expect(gesture.deadline == nil)
    #expect(gesture.handle(.drag(dx: 12, dy: 2), at: 0.07) == Output(passes: false, commands: [.slideBegan, .slide(12)]))
    let end = gesture.handle(.up(5), at: 0.1)
    #expect(isSlideEnd(end) && !end.passes)
    #expect(gesture.handle(.drag(dx: 30, dy: 0), at: 0.11) == swallowed)          // 4 is still down: still Rambla's
    #expect(gesture.handle(.up(4), at: 0.12) == swallowed)
    #expect(!gesture.holdsButtons)
}

@Test func theOrderOfTheButtonsDoesNotMatter() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    #expect(gesture.handle(.down(5), at: 0) == swallowed)
    #expect(gesture.handle(.down(4), at: 0.1) == swallowed)
    #expect(gesture.handle(.drag(dx: 0, dy: -40), at: 0.12) == Output(passes: false, commands: [.vertical(up: true)]))
}

@Test func aClickOfOneSideButtonReachesTheApps() {
    // Mac Mouse Fix's "back" on button 4 keeps working: the press is given back with its release.
    var gesture = MouseButtonGesture(buttons: [4, 5])
    #expect(gesture.handle(.down(4), at: 0) == swallowed)
    #expect(gesture.handle(.up(4), at: 0.08) == Output(replay: [4], passes: true))
    #expect(!gesture.holdsButtons)
    #expect(gesture.deadline == nil)
}

@Test func holdingOneSideButtonHandsItOnAfterTheWindow() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    #expect(gesture.expire(at: 0.1) == [])                                        // still waiting
    #expect(gesture.expire(at: MouseButtonGesture.chordWindow) == [4])
    #expect(!gesture.holdsButtons)
    #expect(gesture.handle(.drag(dx: 30, dy: 0), at: 0.3) == passes)              // the apps' own drag now
    #expect(gesture.handle(.down(5), at: 0.4) == passes)                          // too late to make the chord
    #expect(gesture.handle(.up(5), at: 0.5) == passes)
    #expect(gesture.handle(.up(4), at: 0.6) == passes)
    // Everything released: the next chord works.
    _ = gesture.handle(.down(5), at: 1)
    #expect(gesture.handle(.down(4), at: 1.05) == swallowed)
}

@Test func aLateTimerStillHandsThePressOnFirst() {
    // The timer that calls `expire` can run late; the window still ends on time.
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    #expect(gesture.handle(.down(5), at: 0.3) == Output(replay: [4], passes: true))
}

@Test func draggingWithOneSideButtonHandsItOn() {
    // Mac Mouse Fix's drag on button 4 keeps working.
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    #expect(gesture.handle(.drag(dx: 3, dy: 2), at: 0.02) == swallowed)           // a hand's tremble
    #expect(gesture.handle(.drag(dx: 4, dy: 3), at: 0.04) == Output(replay: [4], passes: true))
    #expect(gesture.handle(.up(4), at: 0.3) == passes)
}

@Test func turningTheWheelHandsTheWaitingPressOn() {
    // Mac Mouse Fix zooms with button 5 held and the wheel turned: the press must reach it before the wheel does.
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(5), at: 0)
    #expect(gesture.handle(.scroll, at: 0.05) == Output(replay: [5], passes: true))
    #expect(gesture.handle(.scroll, at: 0.06) == passes)
    #expect(gesture.handle(.up(5), at: 0.3) == passes)
    // During a gesture the wheel is the apps' and changes nothing.
    _ = gesture.handle(.down(4), at: 1)
    _ = gesture.handle(.down(5), at: 1.01)
    #expect(gesture.handle(.scroll, at: 1.02) == passes)
    #expect(gesture.handle(.drag(dx: 0, dy: -45), at: 1.03) == Output(passes: false, commands: [.vertical(up: true)]))
}

@Test func anotherButtonHandsTheWaitingPressOn() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    #expect(gesture.handle(.down(3), at: 0.05) == Output(replay: [4], passes: true))
    #expect(gesture.handle(.up(3), at: 0.1) == passes)
    #expect(gesture.handle(.up(4), at: 0.2) == passes)
}

@Test func releasingTheChordWithoutMovingDoesNothing() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    _ = gesture.handle(.down(5), at: 0.02)
    #expect(gesture.handle(.up(4), at: 0.2) == swallowed)                         // no stray back and forward
    #expect(gesture.handle(.up(5), at: 0.21) == swallowed)
}

@Test func pressingTheChordAgainStartsAnotherGesture() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    _ = gesture.handle(.down(5), at: 0.02)
    _ = gesture.handle(.drag(dx: 0, dy: -50), at: 0.05)                           // up
    #expect(gesture.handle(.up(5), at: 0.1) == swallowed)
    #expect(gesture.handle(.down(5), at: 0.3) == swallowed)                       // 4 is still held: the chord again
    #expect(gesture.handle(.drag(dx: 0, dy: 50), at: 0.35) == swallowed)
    #expect(gesture.handle(.up(5), at: 0.4) == Output(passes: false, commands: [.vertical(up: false)]))
}

@Test func releasingOneButtonMidSlideAndPressingItAgainSlidesAgain() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    _ = gesture.handle(.down(5), at: 0.01)
    _ = gesture.handle(.drag(dx: 20, dy: 0), at: 0.02)
    #expect(isSlideEnd(gesture.handle(.up(5), at: 0.05)))
    #expect(gesture.handle(.down(5), at: 0.2) == swallowed)
    #expect(gesture.handle(.drag(dx: -9, dy: 0), at: 0.22) == Output(passes: false, commands: [.slideBegan, .slide(-9)]))
}

@Test func anotherButtonBeforeTheChordMovesGoesOn() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    _ = gesture.handle(.down(5), at: 0.01)
    #expect(gesture.handle(.down(3), at: 0.02) == passes)
    #expect(gesture.handle(.up(3), at: 0.03) == passes)
    #expect(gesture.handle(.drag(dx: 0, dy: -50), at: 0.04) == Output(passes: false, commands: [.vertical(up: true)]))
}

@Test func anyEventAfterTheWindowHandsThePressOnFirst() {
    for (event, expected) in [(MouseButtonGesture.Input.up(4), Output(replay: [4], passes: true)),
                              (.drag(dx: 10, dy: 0), Output(replay: [4], passes: true)),
                              (.scroll, Output(replay: [4], passes: true))] {
        var gesture = MouseButtonGesture(buttons: [4, 5])
        _ = gesture.handle(.down(4), at: 0)
        #expect(gesture.handle(event, at: 0.3) == expected, "\(event)")
    }
}

@Test func aPlainMoveDuringAChordForgetsIt() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    _ = gesture.handle(.down(5), at: 0.01)
    #expect(gesture.handle(.released, at: 0.02) == passes)
    #expect(gesture.heldButtons.isEmpty)
    _ = gesture.handle(.down(4), at: 1)
    _ = gesture.handle(.down(5), at: 1.01)
    _ = gesture.handle(.drag(dx: 0, dy: 45), at: 1.02)                            // on its way down
    #expect(gesture.handle(.released, at: 1.03) == passes)
    #expect(gesture.handle(.up(4), at: 1.04) == passes)                           // the apps' now: Rambla forgot it
}

@Test func theHeldButtonsAreThoseKeptFromTheApps() {
    var gesture = MouseButtonGesture(buttons: [3, 4, 5])
    _ = gesture.handle(.down(5), at: 0)
    _ = gesture.handle(.down(4), at: 0.01)
    #expect(gesture.heldButtons == [5, 4])
    _ = gesture.expire(at: 0.2)
    #expect(gesture.heldButtons.isEmpty)
}

@Test func otherButtonsAndPlainMovesAreTheApps() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    #expect(gesture.handle(.down(3), at: 0) == passes)
    #expect(gesture.handle(.drag(dx: 40, dy: 0), at: 0.05) == passes)
    #expect(gesture.handle(.up(3), at: 0.1) == passes)
    #expect(gesture.handle(.released, at: 0.2) == passes)
    #expect(gesture.handle(.up(6), at: 0.3) == passes)                            // a release whose press Rambla never saw
}

@Test func anotherButtonDuringAGestureGoesOnAndTheGestureContinues() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    _ = gesture.handle(.down(5), at: 0.01)
    _ = gesture.handle(.drag(dx: 10, dy: 0), at: 0.02)
    #expect(gesture.handle(.down(3), at: 0.03) == passes)
    #expect(gesture.handle(.drag(dx: 10, dy: 0), at: 0.04) == Output(passes: false, commands: [.slide(10)]))
    #expect(gesture.handle(.up(3), at: 0.05) == passes)
}

@Test func partOfALargerChordGoesOnTogether() {
    var gesture = MouseButtonGesture(buttons: [3, 4, 5])
    _ = gesture.handle(.down(4), at: 0)
    #expect(gesture.handle(.down(5), at: 0.05) == swallowed)
    #expect(gesture.expire(at: MouseButtonGesture.chordWindow) == [4, 5])         // the window counts from the first press
    #expect(gesture.handle(.up(5), at: 0.3) == passes)
    #expect(gesture.handle(.up(4), at: 0.31) == passes)

    _ = gesture.handle(.down(4), at: 1)
    _ = gesture.handle(.down(5), at: 1.05)
    #expect(gesture.handle(.up(4), at: 1.1) == Output(replay: [4, 5], passes: true))
    #expect(gesture.handle(.up(5), at: 1.15) == passes)
}

@Test func aChordCannotUseAButtonTheAppsHave() {
    var gesture = MouseButtonGesture(buttons: [3, 4, 5])
    _ = gesture.handle(.down(3), at: 0)
    #expect(gesture.expire(at: 0.2) == [3])                                       // 3 is the apps' now
    #expect(gesture.handle(.down(4), at: 0.3) == passes)
    #expect(gesture.handle(.down(5), at: 0.31) == passes)
    #expect(gesture.handle(.up(4), at: 0.4) == passes)
}

// MARK: - Lost events

@Test func aPlainMoveMeansTheButtonsWereReleased() {
    // A release can go by unseen (the tap was off for a moment); a move without buttons proves it, and ends the slide.
    var gesture = MouseButtonGesture(buttons: [3])
    _ = gesture.handle(.down(3), at: 0)
    _ = gesture.handle(.drag(dx: 10, dy: 0), at: 0.01)
    _ = gesture.handle(.drag(dx: 10, dy: 0), at: 0.02)
    let output = gesture.handle(.released, at: 0.03)
    #expect(output.passes && output.replay.isEmpty)
    #expect(isSlideEnd(output))
    #expect(!gesture.holdsButtons)
    #expect(gesture.handle(.down(3), at: 1) == swallowed)                         // and the next press works
}

@Test func aPressWaitingForItsChordIsForgottenWhenReleasedUnseen() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    #expect(gesture.handle(.released, at: 0.05) == passes)                        // not replayed: no release would follow
    #expect(gesture.deadline == nil)
    #expect(gesture.expire(at: 1) == [])
}

@Test func aSecondPressOfAButtonMeansItsReleaseWasMissed() {
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    #expect(gesture.expire(at: 0.2) == [4])                                       // the apps have it
    // Its release went by unseen: the next press of 4 starts over, and can make the chord.
    #expect(gesture.handle(.down(4), at: 2) == swallowed)
    #expect(gesture.handle(.down(5), at: 2.05) == swallowed)
}

@Test func aSecondPressOfAHeldButtonEndsWhatItWasDoing() {
    var gesture = MouseButtonGesture(buttons: [3])
    _ = gesture.handle(.down(3), at: 0)
    _ = gesture.handle(.drag(dx: 20, dy: 0), at: 0.01)
    let again = gesture.handle(.down(3), at: 1)
    #expect(again.passes == false && again.replay.isEmpty)
    #expect(isSlideEnd(again))
    #expect(gesture.handle(.up(3), at: 1.1) == Output(replay: [3], passes: true))  // a fresh click
}

@Test func cancelDropsAPressWaitingForItsChord() {
    // The taps are going away: nothing can be given back any more.
    var gesture = MouseButtonGesture(buttons: [4, 5])
    _ = gesture.handle(.down(4), at: 0)
    #expect(gesture.cancel().isEmpty)
    #expect(gesture.deadline == nil)
    #expect(gesture.expire(at: 1) == [])
}

@Test func cancelEndsTheSlideAndForgetsTheButtons() {
    var gesture = MouseButtonGesture(buttons: [3])
    #expect(gesture.cancel().isEmpty)
    _ = gesture.handle(.down(3), at: 0)
    _ = gesture.handle(.drag(dx: 20, dy: 0), at: 0.01)
    #expect(gesture.cancel() == [.slideEnded(velocity: 0)])
    #expect(!gesture.holdsButtons)
    #expect(gesture.handle(.up(3), at: 0.1) == passes)                            // what is left of it is the apps'
}

@Test func withoutButtonsNothingIsRamblas() {
    var gesture = MouseButtonGesture(buttons: [])
    #expect(gesture.handle(.down(3), at: 0) == passes)
    #expect(gesture.handle(.drag(dx: 50, dy: 0), at: 0.05) == passes)
    #expect(gesture.handle(.up(3), at: 0.1) == passes)
}
