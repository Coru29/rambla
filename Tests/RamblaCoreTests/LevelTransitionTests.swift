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

// MARK: - The veil's phases

private typealias Veil = LevelTransition.Veil

private let cover = LevelTransition.seconds(LevelTransition.coverSeconds, speed: 1)
private let reveal = LevelTransition.seconds(LevelTransition.revealSeconds, speed: 1)
/// One frame of the display link. A stretch ends on the first frame at or past its end.
private let frame = 1.0 / 60

/// The token of the deadline among `effects`, and in how many seconds it comes.
private func deadline(in effects: [Veil.Effect]) -> (token: Int, after: Double)? {
    for case .deadline(let token, let after) in effects { return (token, after) }
    return nil
}

/// The token of the hold among `effects`.
private func hold(in effects: [Veil.Effect]) -> Int? {
    for case .settle(let hold) in effects { return hold }
    return nil
}

/// Where the glass is put among `effects`, when it slides.
private func slide(in effects: [Veil.Effect]) -> (coverage: Double, side: Double)? {
    for case .slide(let coverage, let side) in effects { return (coverage, side) }
    return nil
}

/// A veil asked for at 0 (`up`) that came over the whole display and covers it: it holds, with the token of that hold.
private func held(up: Bool = true) -> (veil: Veil, hold: Int) {
    var veil = Veil()
    _ = veil.request(up: up, speed: 1, reduceMotion: false, now: 0)
    _ = veil.tick(now: cover)
    let hold = hold(in: veil.tick(now: cover + frame))!
    return (veil, hold)
}

@Test func aSwitchPutsTheVeilOnScreenOffTheDisplayAndBringsItOver() {
    var veil = Veil()
    let effects = veil.request(up: true, speed: 1, reduceMotion: false, now: 0)
    // Off the display above (the strip above comes), then on screen, and it comes over the display frame by frame.
    #expect(Array(effects.prefix(3)) == [.slide(coverage: 0, side: 1), .show, .tick])
    #expect(veil.phase == .covering)
    let halfWay = slide(in: veil.tick(now: cover / 2))
    #expect(halfWay.map { $0.coverage > 0.5 && $0.coverage < 1 && $0.side == 1 } == true)
    #expect(veil.tick(now: cover) == [.slide(coverage: 1, side: 1)])
    // The strip below comes up from below.
    var below = Veil()
    #expect(below.request(up: false, speed: 1, reduceMotion: false, now: 0).first == .slide(coverage: 0, side: -1))
}

@Test func theSwitchesRunOnTheFrameAfterTheOneThatCoversTheDisplay() {
    var veil = Veil()
    _ = veil.request(up: true, speed: 1, reduceMotion: false, now: 0)
    // That frame is on its way to the screen: not covered yet.
    #expect(!veil.tick(now: cover).contains(.covered))
    #expect(veil.phase == .covered)
    let effects = veil.tick(now: cover + frame)
    guard let hold = hold(in: effects) else {
        Issue.record("no hold")
        return
    }
    // The frames stop, the switches run, and only then does the wait for the windows start, with its deadline.
    #expect(effects == [.stopTicking, .covered, .settle(hold: hold), .deadline(hold, after: LevelTransition.holdCap)])
    #expect(veil.phase == .holding)
}

@Test func requestsWhileTheVeilComesOverJoinThatCover() {
    var veil = Veil()
    _ = veil.request(up: true, speed: 1, reduceMotion: false, now: 0)
    #expect(veil.request(up: true, speed: 1, reduceMotion: false, now: 0.03).isEmpty)
    _ = veil.tick(now: cover)
    #expect(veil.request(up: false, speed: 1, reduceMotion: false, now: cover + 0.005).isEmpty)
    // One cover for the three of them.
    let covered = veil.tick(now: cover + frame) + veil.tick(now: cover + 2 * frame)
    #expect(covered.filter { $0 == .covered }.count == 1)
}

@Test func aSwitchWhileTheVeilHoldsRunsAtOnceAndOnlyTheNewestHoldLetsItGo() {
    var (veil, first) = held()
    let effects = veil.request(up: true, speed: 1, reduceMotion: false, now: 0.2)
    guard let second = hold(in: effects) else {
        Issue.record("no new hold")
        return
    }
    #expect(second != first)
    #expect(effects == [.covered, .settle(hold: second), .deadline(second, after: LevelTransition.holdCap)])
    // The windows of the first switch are in their places: the second one's may not be yet.
    #expect(veil.settled(hold: first, now: 0.25).isEmpty)
    #expect(veil.phase == .holding)
    let leaving = veil.settled(hold: second, now: 0.3)
    #expect(Array(leaving.prefix(1)) == [.tick])
    #expect(deadline(in: leaving)?.after == reveal + LevelTransition.watchdogSlack)
    #expect(veil.phase == .revealing)
}

@Test func theVeilLeavesThroughTheOtherSideOfTheLastSwitch() {
    // Up: it came down from above, and goes on out below.
    var (up, upHold) = held(up: true)
    _ = up.settled(hold: upHold, now: 1)
    let goingDown = slide(in: up.tick(now: 1 + reveal / 2))
    #expect(goingDown.map { $0.coverage > 0 && $0.coverage < 1 && $0.side == -1 } == true)
    // Up, then down while it came over: it covers from above, and goes back out the way it came.
    var veil = Veil()
    _ = veil.request(up: true, speed: 1, reduceMotion: false, now: 0)
    _ = veil.request(up: false, speed: 1, reduceMotion: false, now: 0.02)
    _ = veil.tick(now: cover)
    let hold = hold(in: veil.tick(now: cover + frame))!
    _ = veil.settled(hold: hold, now: 1)
    let goingUp = slide(in: veil.tick(now: 1 + reveal / 2))
    #expect(goingUp.map { $0.coverage > 0 && $0.coverage < 1 && $0.side == 1 } == true)
    // Done: off the display, and off screen.
    #expect(veil.tick(now: 1 + reveal + frame) == [.slide(coverage: 0, side: 1), .stopTicking, .hide])
    #expect(veil.phase == .idle)
}

@Test func aSwitchWhileTheVeilLeavesBringsItBackFromWhereItIs() {
    var (veil, hold) = held(up: true)
    _ = veil.settled(hold: hold, now: 1)
    let now = 1 + reveal / 2
    _ = veil.tick(now: now)
    let left = veil.coverage
    #expect(left > 0 && left < 1)
    let effects = veil.request(up: true, speed: 1, reduceMotion: false, now: now)
    #expect(Array(effects.prefix(1)) == [.tick])
    #expect(veil.phase == .covering)
    // Only what is left to cover, from where it is, on the side it was leaving through (below).
    let rest = LevelTransition.seconds(LevelTransition.coverSeconds, speed: 1, distance: 1 - left)
    #expect(deadline(in: effects)?.after == rest + LevelTransition.watchdogSlack)
    #expect(veil.tick(now: now) == [.slide(coverage: left, side: -1)])
    #expect(veil.tick(now: now + rest + frame) == [.slide(coverage: 1, side: -1)])
    #expect(veil.tick(now: now + rest + 2 * frame).contains(.covered))
}

@Test func withReduceMotionTheVeilFadesInPlace() {
    var veil = Veil()
    #expect(Array(veil.request(up: true, speed: 1, reduceMotion: true, now: 0).prefix(2)) == [.fade(opacity: 0), .show])
    guard case .fade(let opacity)? = veil.tick(now: cover / 2).first else {
        Issue.record("no fade half way in")
        return
    }
    #expect(opacity > 0.5 && opacity < 1)
    #expect(veil.tick(now: cover) == [.fade(opacity: 1)])
    let hold = hold(in: veil.tick(now: cover + frame))!
    _ = veil.settled(hold: hold, now: 1)
    #expect(veil.tick(now: 1 + reveal + frame) == [.fade(opacity: 0), .stopTicking, .hide])
}

@Test func theVeilKeepsTheAnimationSpeedAndEachStretchHasADeadline() {
    var veil = Veil()
    let fast = LevelTransition.seconds(LevelTransition.coverSeconds, speed: 2)
    let effects = veil.request(up: true, speed: 2, reduceMotion: false, now: 0)
    #expect(deadline(in: effects)?.after == fast + LevelTransition.watchdogSlack)
    #expect(veil.tick(now: fast) == [.slide(coverage: 1, side: 1)])
    let hold = hold(in: veil.tick(now: fast + frame))!
    let leaving = veil.settled(hold: hold, now: 1)
    let fastReveal = LevelTransition.seconds(LevelTransition.revealSeconds, speed: 2)
    #expect(deadline(in: leaving)?.after == fastReveal + LevelTransition.watchdogSlack)
}

@Test func aCoverTheDisplayLinkDoesNotFinishEndsAsCoveredAtItsDeadline() {
    // No frame at all (a display asleep or unplugged): the veil covers at once, and the switches run.
    var veil = Veil()
    let token = deadline(in: veil.request(up: true, speed: 1, reduceMotion: false, now: 0))!.token
    let effects = veil.deadline(token, now: cover + LevelTransition.watchdogSlack)
    guard let hold = hold(in: effects) else {
        Issue.record("no hold")
        return
    }
    #expect(effects == [.slide(coverage: 1, side: 1), .stopTicking, .covered, .settle(hold: hold),
                        .deadline(hold, after: LevelTransition.holdCap)])
    #expect(veil.phase == .holding)
    // The link stalls on the frame that covers the display: the same.
    var stalled = Veil()
    let stalledToken = deadline(in: stalled.request(up: false, speed: 1, reduceMotion: false, now: 0))!.token
    _ = stalled.tick(now: cover)
    #expect(stalled.phase == .covered)
    #expect(stalled.deadline(stalledToken, now: cover + LevelTransition.watchdogSlack).contains(.covered))
    #expect(stalled.phase == .holding)
}

@Test func aHoldEndsAtItsDeadlineWhateverTheWaitForTheWindows() {
    var (veil, hold) = held()
    let leaving = veil.deadline(hold, now: cover + LevelTransition.holdCap)
    #expect(Array(leaving.prefix(1)) == [.tick])
    #expect(veil.phase == .revealing)
    // The wait gives up after it: nothing more.
    #expect(veil.settled(hold: hold, now: 1).isEmpty)
}

@Test func aRevealTheDisplayLinkDoesNotFinishTakesTheVeilOffAtItsDeadline() {
    var (veil, hold) = held()
    let token = deadline(in: veil.settled(hold: hold, now: 1))!.token
    _ = veil.tick(now: 1 + reveal / 3)
    #expect(veil.deadline(token, now: 1 + reveal + LevelTransition.watchdogSlack) == [.stopTicking, .hide])
    #expect(veil.phase == .idle)
    #expect(veil.coverage == 0)
}

@Test func aLateSettleDoesNothing() {
    // The hold before a newer one, a hold its deadline already ended, and one after the veil went.
    var (veil, first) = held()
    let second = hold(in: veil.request(up: true, speed: 1, reduceMotion: false, now: 0.2))!
    #expect(veil.settled(hold: first, now: 0.21).isEmpty)
    _ = veil.deadline(second, now: 0.7)
    #expect(veil.phase == .revealing)
    #expect(veil.settled(hold: second, now: 0.71).isEmpty)
    _ = veil.tick(now: 0.7 + reveal + frame)
    #expect(veil.phase == .idle)
    #expect(veil.settled(hold: second, now: 2).isEmpty)
    #expect(veil.phase == .idle)
}

@Test func aLateDeadlineDoesNothing() {
    // The cover's, once it covered in time.
    var veil = Veil()
    let coverToken = deadline(in: veil.request(up: true, speed: 1, reduceMotion: false, now: 0))!.token
    _ = veil.tick(now: cover)
    let hold = hold(in: veil.tick(now: cover + frame))!
    #expect(veil.deadline(coverToken, now: cover + LevelTransition.watchdogSlack).isEmpty)
    #expect(veil.phase == .holding)
    // The reveal's, once a switch brought the veil back over the display.
    let revealToken = deadline(in: veil.settled(hold: hold, now: 0.3))!.token
    _ = veil.tick(now: 0.3 + reveal / 2)
    _ = veil.request(up: true, speed: 1, reduceMotion: false, now: 0.3 + reveal / 2)
    #expect(veil.deadline(revealToken, now: 0.3 + reveal + LevelTransition.watchdogSlack).isEmpty)
    #expect(veil.phase == .covering)
    // Any of them once the veil went.
    var gone = Veil()
    let token = deadline(in: gone.request(up: true, speed: 1, reduceMotion: false, now: 0))!.token
    _ = gone.reset()
    #expect(gone.deadline(token, now: 1).isEmpty)
    #expect(gone.phase == .idle)
}

@Test func aResetTakesTheVeilOffAtOnceAndCallsNothingBack() {
    var covering = Veil()
    _ = covering.request(up: true, speed: 1, reduceMotion: false, now: 0)
    _ = covering.tick(now: cover / 2)
    #expect(covering.reset() == [.stopTicking, .hide])
    #expect(covering.phase == .idle)
    #expect(covering.coverage == 0)
    var (holding, hold) = held()
    #expect(holding.reset() == [.stopTicking, .hide])
    #expect(holding.settled(hold: hold, now: 1).isEmpty)
    #expect(holding.reset().isEmpty)
    // The next switch starts afresh, off the display.
    #expect(holding.request(up: false, speed: 1, reduceMotion: false, now: 2).first == .slide(coverage: 0, side: -1))
}

@Test func aFrameWhileTheVeilHoldsOrIsGoneStopsTheFrames() {
    var (veil, _) = held()
    #expect(veil.tick(now: 0.3) == [.stopTicking])
    var idle = Veil()
    #expect(idle.tick(now: 0) == [.stopTicking])
}

@Test func onlyTheSwitchesBetweenStripsWaitForTheVeil() {
    #expect(Action.allCases.filter(\.switchesStrips) == [.stripUp, .stripDown, .sendStripUp, .sendStripDown])
}
