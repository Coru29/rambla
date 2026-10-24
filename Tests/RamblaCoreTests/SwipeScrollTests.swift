import Testing
@testable import RamblaCore

// With macOS's own swipes off for the gesture's fingers, macOS sends their movement to the app under the pointer as
// scrolling. The trackpad reports the fingers touching it about every 10 ms, and the scroll begins some 60 ms after
// the last of the swipe's fingers lands. Times in seconds.

private typealias Phase = WheelGesture.Event.Phase

/// The trackpad as the filter hears of it. A class, because `#expect` cannot call a mutating method.
private final class Trackpad {
    private var filter: SwipeScroll

    init(fingers: Int = 4) {
        filter = SwipeScroll(fingers: fingers)
    }

    /// A touch report: this many fingers touch the trackpad.
    func touch(_ fingers: Int, at time: Double) {
        filter.touched(fingers, at: time)
    }

    /// Whether a scroll event (a phase, no momentum) is kept from the app. Not `fromHardware`: another app posted it.
    func scroll(_ phase: Phase, at time: Double, fromHardware: Bool = true) -> Bool {
        filter.swallows(phase: phase, momentum: .none, fromHardware: fromHardware, at: time)
    }

    /// Whether an event of the glide macOS adds after the fingers lift is kept from the app.
    func glide(_ momentum: WheelGesture.Event.Momentum, at time: Double, fromHardware: Bool = true) -> Bool {
        filter.swallows(phase: .none, momentum: momentum, fromHardware: fromHardware, at: time)
    }

    func isBusy(at time: Double) -> Bool {
        filter.isBusy(at: time)
    }
}

@Test func scrollWhileTheSwipeFingersAreDownIsSwallowed() {
    let trackpad = Trackpad()
    trackpad.touch(1, at: 0)                                            // the fingers land one by one
    trackpad.touch(3, at: 0.01)
    trackpad.touch(4, at: 0.02)
    #expect(trackpad.scroll(.mayBegin, at: 0.03))
    #expect(trackpad.scroll(.began, at: 0.08))
    trackpad.touch(4, at: 0.09)
    #expect(trackpad.scroll(.changed, at: 0.1))
    #expect(trackpad.scroll(.changed, at: 0.35))                        // a report late by less than `staleAfter`
    trackpad.touch(4, at: 0.36)
    #expect(trackpad.scroll(.changed, at: 0.37))
    trackpad.touch(0, at: 0.4)
    // The next swipe while this one still glides: its fingers land before its scroll begins.
    trackpad.touch(2, at: 0.6)
    trackpad.touch(4, at: 0.62)
    #expect(trackpad.scroll(.began, at: 0.68))
    #expect(trackpad.scroll(.changed, at: 0.7))
}

@Test func twoFingerScrollingPasses() {
    let trackpad = Trackpad()
    trackpad.touch(1, at: 0)
    trackpad.touch(2, at: 0.01)
    #expect(!trackpad.scroll(.mayBegin, at: 0.02))
    #expect(!trackpad.scroll(.began, at: 0.06))
    trackpad.touch(2, at: 0.07)
    #expect(!trackpad.scroll(.changed, at: 0.08))
    trackpad.touch(0, at: 0.2)
    #expect(!trackpad.scroll(.ended, at: 0.2))
    #expect(!trackpad.glide(.began, at: 0.22))
    #expect(!trackpad.glide(.changed, at: 0.3))
    #expect(!trackpad.glide(.ended, at: 0.6))
    // Nor does a scroll without fingers on the trackpad (a Magic Mouse) belong to a swipe.
    #expect(!trackpad.scroll(.began, at: 2))
    #expect(!trackpad.scroll(.changed, at: 2.01))
}

@Test func liftingFingerByFingerKeepsSwallowing() {
    let trackpad = Trackpad()
    trackpad.touch(4, at: 0)
    #expect(trackpad.scroll(.began, at: 0.06))
    #expect(trackpad.scroll(.changed, at: 0.07))
    trackpad.touch(3, at: 0.1)
    #expect(trackpad.scroll(.changed, at: 0.1))
    trackpad.touch(2, at: 0.11)
    // macOS ends the swipe's scroll and begins another with the fingers still down: that one is the swipe's too.
    #expect(trackpad.scroll(.ended, at: 0.11))
    #expect(trackpad.scroll(.began, at: 0.12))
    trackpad.touch(1, at: 0.13)                                         // one finger left: the swipe glides
    #expect(trackpad.scroll(.changed, at: 0.14))
    trackpad.touch(0, at: 0.15)
    #expect(trackpad.scroll(.ended, at: 0.15))
    #expect(trackpad.glide(.began, at: 0.17))
}

@Test func aSingleFingerLeftStartsTheGlide() {
    // With one finger left there is no scroll to keep from the app. A thumb resting on the trackpad, if it counts as
    // touching, must not hold the filter once the swipe's fingers lift.
    let trackpad = Trackpad()
    trackpad.touch(4, at: 0)
    #expect(trackpad.scroll(.began, at: 0.06))
    trackpad.touch(1, at: 0.1)
    #expect(trackpad.scroll(.ended, at: 0.1))
    #expect(trackpad.glide(.began, at: 0.12))
    trackpad.touch(1, at: 0.2)
    #expect(trackpad.glide(.ended, at: 0.25))
    trackpad.touch(1, at: 0.3)
    // Two fingers land beside the thumb and scroll: the user's own.
    trackpad.touch(3, at: 0.4)
    #expect(!trackpad.scroll(.began, at: 0.42))
    trackpad.touch(3, at: 0.45)
    #expect(!trackpad.scroll(.changed, at: 0.46))
}

@Test func aChangedScrollDuringTheGlideIsSwallowed() {
    // The scroll macOS began while the fingers were lifting goes on after the filter hears of the lift: it is the
    // swipe's. A new scroll by the user would first report its fingers landing.
    let trackpad = Trackpad()
    trackpad.touch(4, at: 0)
    #expect(trackpad.scroll(.began, at: 0.06))
    trackpad.touch(2, at: 0.1)
    #expect(trackpad.scroll(.began, at: 0.11))
    trackpad.touch(0, at: 0.12)
    #expect(trackpad.scroll(.changed, at: 0.125))
    #expect(trackpad.scroll(.changed, at: 0.13))
    #expect(trackpad.scroll(.ended, at: 0.14))
    #expect(trackpad.glide(.began, at: 0.16))
    // The same once reports stop coming while the fingers still move (a busy moment): the swipe ends as if they had
    // lifted, and its scroll is still kept from the app.
    let late = Trackpad()
    late.touch(4, at: 0)
    #expect(late.scroll(.began, at: 0.06))
    late.touch(4, at: 0.1)
    #expect(late.scroll(.changed, at: 0.45))
    #expect(late.scroll(.changed, at: 0.46))
}

@Test func theGlideAfterASwipeIsSwallowedUntilItEnds() {
    let trackpad = Trackpad()
    trackpad.touch(4, at: 0)
    #expect(trackpad.scroll(.began, at: 0.06))
    #expect(trackpad.scroll(.changed, at: 0.1))
    trackpad.touch(0, at: 0.2)
    #expect(trackpad.scroll(.ended, at: 0.2))
    #expect(trackpad.glide(.began, at: 0.22))
    #expect(trackpad.glide(.changed, at: 0.5))
    #expect(trackpad.glide(.changed, at: 1))
    #expect(trackpad.glide(.ended, at: 1.2))
    // Over: a phaseless scroll right after reaches the app (while the glide lasted, it would not).
    #expect(!trackpad.scroll(.none, at: 1.3))
}

@Test func aMayBeginDuringTheGlideIsSwallowed() {
    // Recorded: right after the lift, with one finger left, macOS sends `mayBegin`, and the glide comes right after it.
    // No phase ends the glide, not even one that begins a scroll.
    for phase: Phase in [.mayBegin, .began] {
        let trackpad = Trackpad()
        trackpad.touch(4, at: 723.1)
        #expect(trackpad.scroll(.began, at: 723.16))
        #expect(trackpad.scroll(.changed, at: 723.3))
        trackpad.touch(1, at: 723.338)
        #expect(trackpad.glide(.began, at: 723.357))
        #expect(trackpad.scroll(phase, at: 723.359))
        trackpad.touch(0, at: 723.359)
        for step in 1...12 { #expect(trackpad.glide(.changed, at: 723.359 + 0.03 * Double(step))) }
        #expect(trackpad.glide(.ended, at: 723.75))
        #expect(!trackpad.scroll(.none, at: 723.8))                     // the glide is over
    }
}

@Test func twoFingersLandingEndTheGlide() {
    // The user starts a scroll of their own while the swipe still glides: their fingers' report comes about 60 ms
    // before macOS's scroll, and ends the glide. One finger landing does not.
    let trackpad = Trackpad()
    trackpad.touch(4, at: 0)
    #expect(trackpad.scroll(.began, at: 0.06))
    trackpad.touch(0, at: 0.2)
    #expect(trackpad.scroll(.ended, at: 0.2))
    #expect(trackpad.glide(.began, at: 0.22))
    trackpad.touch(1, at: 0.3)
    #expect(trackpad.glide(.changed, at: 0.31))
    trackpad.touch(2, at: 0.32)
    #expect(!trackpad.glide(.ended, at: 0.33))                          // the glide is over: the rest reaches the app
    #expect(!trackpad.scroll(.mayBegin, at: 0.36))
    #expect(!trackpad.scroll(.began, at: 0.38))
    #expect(!trackpad.scroll(.changed, at: 0.4))
    trackpad.touch(0, at: 0.6)
    #expect(!trackpad.scroll(.ended, at: 0.6))
    #expect(!trackpad.glide(.began, at: 0.62))                          // the user's own glide
    #expect(!trackpad.glide(.ended, at: 1))
}

@Test func anotherAppsScrollIsHeldOnlyWhileTheFingersAreDown() {
    // Mac Mouse Fix, say, posts the smooth scrolling of the user's wheel mouse itself. While the swipe's fingers are
    // down, every continuous event is the swipe's. While it glides, another app's scrolling passes, and leaves the
    // glide alone.
    let trackpad = Trackpad()
    trackpad.touch(4, at: 0)
    #expect(trackpad.scroll(.began, at: 0.06, fromHardware: false))
    #expect(trackpad.scroll(.changed, at: 0.07, fromHardware: false))
    trackpad.touch(0, at: 0.2)
    #expect(trackpad.glide(.began, at: 0.22))
    #expect(!trackpad.scroll(.began, at: 0.25, fromHardware: false))
    #expect(!trackpad.scroll(.changed, at: 0.26, fromHardware: false))
    #expect(!trackpad.glide(.ended, at: 0.3, fromHardware: false))
    #expect(trackpad.glide(.changed, at: 0.31))
    #expect(trackpad.glide(.ended, at: 0.5))
}

@Test func anEndTheAppWaitsForStillReachesIt() {
    // The fourth finger's report came late, and the app got the start of the scroll. Its end still reaches the app
    // (an end carries no movement), or the app would keep the scroll open: Safari, an overscroll stretched.
    let trackpad = Trackpad()
    trackpad.touch(2, at: 0)
    #expect(!trackpad.scroll(.began, at: 0.06))
    #expect(!trackpad.scroll(.changed, at: 0.07))
    trackpad.touch(4, at: 0.08)
    #expect(trackpad.scroll(.changed, at: 0.09))
    #expect(!trackpad.scroll(.ended, at: 0.12))
    #expect(trackpad.scroll(.began, at: 0.13))                         // the swipe's own scroll
    #expect(trackpad.scroll(.ended, at: 0.3))                          // nobody waits for its end
    // Two fingers resting (the app got `mayBegin`) when two more land: macOS cancels that touch.
    let resting = Trackpad()
    resting.touch(2, at: 0)
    #expect(!resting.scroll(.mayBegin, at: 0.02))
    resting.touch(4, at: 0.1)
    #expect(!resting.scroll(.cancelled, at: 0.11))
    #expect(resting.scroll(.began, at: 0.16))
    #expect(resting.scroll(.cancelled, at: 0.3))
}

@Test func aMomentumEndTheAppWaitsForStillReachesIt() {
    // Four fingers land while the app glides from the user's own scroll: the rest of that glide is the swipe's, but
    // its end still reaches the app.
    let trackpad = Trackpad()
    trackpad.touch(2, at: 0)
    #expect(!trackpad.scroll(.began, at: 0.06))
    trackpad.touch(0, at: 0.2)
    #expect(!trackpad.scroll(.ended, at: 0.2))
    #expect(!trackpad.glide(.began, at: 0.22))
    #expect(!trackpad.glide(.changed, at: 0.25))
    trackpad.touch(4, at: 0.3)
    #expect(trackpad.glide(.changed, at: 0.31))
    #expect(!trackpad.glide(.ended, at: 0.32))
    #expect(trackpad.scroll(.began, at: 0.36))                         // the swipe's own scroll
    trackpad.touch(0, at: 0.5)
    #expect(trackpad.glide(.began, at: 0.52))
    #expect(trackpad.glide(.ended, at: 0.8))                           // nobody waits for this one
    // When the app's glide got no end then, the end of the swipe's glide goes to the app in its place, and still
    // ends that glide.
    let unended = Trackpad()
    unended.touch(2, at: 0)
    #expect(!unended.scroll(.began, at: 0.06))
    unended.touch(0, at: 0.2)
    #expect(!unended.scroll(.ended, at: 0.2))
    #expect(!unended.glide(.began, at: 0.22))
    unended.touch(4, at: 0.3)
    #expect(unended.scroll(.began, at: 0.36))
    unended.touch(0, at: 0.5)
    #expect(unended.glide(.began, at: 0.52))
    #expect(unended.glide(.changed, at: 0.6))
    #expect(!unended.glide(.ended, at: 0.8))
    #expect(!unended.scroll(.none, at: 0.9))                           // the glide is over
}

@Test func aLostLiftEndsTheSwipe() {
    // The fingers lifted without a report. Half a second later two fingers land and scroll: that is the user's own.
    let trackpad = Trackpad()
    trackpad.touch(4, at: 0)
    #expect(trackpad.scroll(.began, at: 0.06))
    trackpad.touch(4, at: 0.1)
    trackpad.touch(2, at: 0.6)
    #expect(!trackpad.scroll(.mayBegin, at: 0.6))
    #expect(!trackpad.scroll(.began, at: 0.65))
    trackpad.touch(2, at: 0.66)
    #expect(!trackpad.scroll(.changed, at: 0.67))
    // A scroll event can be the first to notice. The swipe ended as if the fingers had lifted at their last report:
    // its glide is still kept from the app, and its limit counts from that report.
    let quiet = Trackpad()
    quiet.touch(4, at: 0)
    quiet.touch(4, at: 0.1)
    #expect(quiet.glide(.changed, at: 0.5))
    #expect(quiet.glide(.changed, at: 1.55))
    #expect(!quiet.glide(.changed, at: 1.65))
    // Sooner than `staleAfter`, new fingers tell: none of the swipe's is among them, so the gesture tracker reports
    // the lift first, at the swipe's last report (`TrackpadSwipe.liftWentUnreported`).
    let quick = Trackpad()
    quick.touch(4, at: 0)
    #expect(quick.scroll(.began, at: 0.06))
    quick.touch(4, at: 0.1)
    quick.touch(0, at: 0.1)
    quick.touch(2, at: 0.2)
    #expect(!quick.scroll(.mayBegin, at: 0.2))
    #expect(!quick.scroll(.began, at: 0.26))
}

@Test func theGlideStopsAtItsLimit() {
    // The glide's end never came: `glideLimit` after the lift, scrolling is the apps' again.
    let trackpad = Trackpad()
    trackpad.touch(4, at: 0)
    #expect(trackpad.scroll(.began, at: 0.06))
    trackpad.touch(0, at: 0.2)
    #expect(trackpad.glide(.began, at: 0.22))
    #expect(trackpad.scroll(.none, at: 1))                              // a phaseless scroll is held back too
    #expect(trackpad.glide(.changed, at: 1.6))
    #expect(!trackpad.glide(.changed, at: 1.8))
    #expect(!trackpad.scroll(.none, at: 1.9))
}

@Test func threeFingerSwipes() {
    let trackpad = Trackpad(fingers: 3)
    trackpad.touch(3, at: 0)
    #expect(trackpad.scroll(.began, at: 0.06))
    #expect(trackpad.scroll(.changed, at: 0.07))
    trackpad.touch(2, at: 0.08)                                         // two fingers left keep the swipe going
    #expect(trackpad.scroll(.began, at: 0.085))
    trackpad.touch(1, at: 0.09)
    trackpad.touch(0, at: 0.1)
    #expect(trackpad.scroll(.cancelled, at: 0.1))
    // Two fingers still scroll the app.
    trackpad.touch(2, at: 0.5)
    #expect(!trackpad.scroll(.mayBegin, at: 0.52))
    #expect(!trackpad.scroll(.began, at: 0.55))
    #expect(!trackpad.scroll(.changed, at: 0.56))
}

@Test func aSwipeAndItsGlideKeepTheTapBusy() {
    // A new tap in the middle of a swipe would let some of it through: the tap waits until the swipe and its glide
    // are over, even when no event came to end them.
    let trackpad = Trackpad()
    #expect(!trackpad.isBusy(at: 0))
    trackpad.touch(4, at: 0)
    #expect(trackpad.isBusy(at: 0.05))
    trackpad.touch(0, at: 0.2)
    #expect(trackpad.glide(.began, at: 0.25))
    #expect(trackpad.isBusy(at: 0.3))
    #expect(trackpad.glide(.ended, at: 0.6))
    #expect(!trackpad.isBusy(at: 0.61))
    // Without an event to end it, a glide is over `glideLimit` after the lift, and a lost lift as long after the last
    // report.
    trackpad.touch(4, at: 1)
    trackpad.touch(0, at: 1.2)
    #expect(trackpad.isBusy(at: 2.6))
    #expect(!trackpad.isBusy(at: 2.8))
    trackpad.touch(4, at: 3)
    #expect(trackpad.isBusy(at: 4.4))
    #expect(!trackpad.isBusy(at: 4.6))
    // Two fingers landing end the glide at once.
    trackpad.touch(4, at: 5)
    trackpad.touch(0, at: 5.2)
    trackpad.touch(2, at: 5.4)
    #expect(!trackpad.isBusy(at: 5.41))
}
