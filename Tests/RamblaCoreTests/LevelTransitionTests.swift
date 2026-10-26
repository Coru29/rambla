import Testing
@testable import RamblaCore

@Test func theVeilComesFromTheStripThatComesAndLeavesThroughTheOtherSide() {
    // The strip above comes down into view: the veil comes in from above and goes on out below.
    #expect(LevelTransition.entrySide(up: true) == 1)
    #expect(LevelTransition.exitSide(up: true) == -1)
    #expect(LevelTransition.entrySide(up: false) == -1)
    #expect(LevelTransition.exitSide(up: false) == 1)
}

@Test func coveringGoesFromWhereTheVeilIsToTheWholeDisplay() {
    #expect(LevelTransition.coverage(coveringFrom: 0, progress: 0) == 0)
    #expect(LevelTransition.coverage(coveringFrom: 0, progress: 1) == 1)
    // Sent back while it was leaving: from what it still covered.
    #expect(LevelTransition.coverage(coveringFrom: 0.4, progress: 0) == 0.4)
    #expect(LevelTransition.coverage(coveringFrom: 0.4, progress: 1) == 1)
    // It slows down as it settles over the display.
    #expect(LevelTransition.coverage(coveringFrom: 0, progress: 0.5) > 0.5)
}

@Test func revealingGoesFromTheWholeDisplayToNothing() {
    #expect(LevelTransition.coverage(revealing: 0) == 1)
    #expect(LevelTransition.coverage(revealing: 1) == 0)
    #expect(abs(LevelTransition.coverage(revealing: 0.5) - 0.5) < 1e-9)
    // It sets off gently.
    #expect(LevelTransition.coverage(revealing: 0.25) > 0.75)
}

@Test func progressPastEitherEndStaysThere() {
    #expect(LevelTransition.coverage(coveringFrom: 0, progress: -1) == 0)
    #expect(LevelTransition.coverage(coveringFrom: 0, progress: 2) == 1)
    #expect(LevelTransition.coverage(revealing: -1) == 1)
    #expect(LevelTransition.coverage(revealing: 2) == 0)
}

@Test func theVeilKeepsTheAnimationSpeed() {
    #expect(LevelTransition.seconds(0.2, speed: 1) == 0.2)
    #expect(LevelTransition.seconds(0.2, speed: 2) == 0.1)
    // Only for the part of the way left: half way in, it takes half the time to cover.
    #expect(LevelTransition.seconds(0.2, speed: 1, distance: 0.5) == 0.1)
    // Held to the range the windows' animations use.
    #expect(LevelTransition.seconds(0.2, speed: 100) == 0.2 / 3)
    #expect(LevelTransition.seconds(0.2, speed: 0) == 0.2 / 0.25)
}
