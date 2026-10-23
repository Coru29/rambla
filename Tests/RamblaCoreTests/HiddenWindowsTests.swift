import Testing
@testable import RamblaCore

struct HiddenWindowsTests {
    let desktop = "desktop", other = "other"
    let window: WindowID = 7

    @Test func keepsTheStripsThePassDidNotLookAt() {
        // On a full-screen Space no strip is current: the pass looks at none and must not forget the desktop's windows.
        let record = HiddenWindows.update([desktop: [window]], found: [:], looked: [], exists: { _ in true })
        #expect(record == [desktop: [window]])
    }

    @Test func replacesWhatThePassLookedAt() {
        let record = HiddenWindows.update([desktop: [window], other: [9]], found: [desktop: [8]], looked: [desktop],
                                          exists: { _ in true })
        #expect(record == [desktop: [8], other: [9]])
    }

    @Test func aStripWithNothingHiddenLosesItsEntry() {
        let record = HiddenWindows.update([desktop: [window]], found: [:], looked: [desktop], exists: { _ in true })
        #expect(record.isEmpty)
    }

    @Test func dropsStripsThatNoLongerExist() {
        let record = HiddenWindows.update([desktop: [window], other: [9]], found: [:], looked: [],
                                          exists: { $0 == "desktop" })
        #expect(record == [desktop: [window]])
    }

    @Test func aWindowThatLeavesFullScreenAfterAVisitToItsDesktopHasReturned() {
        // On the desktop while the window is in full screen: hidden there.
        let onDesktop = HiddenWindows.update([String: Set<WindowID>](), found: [desktop: [window]], looked: [desktop],
                                             exists: { _ in true })
        // Back on its full-screen Space.
        let onFullScreen = HiddenWindows.update(onDesktop, found: [:], looked: [], exists: { _ in true })
        // It leaves full screen: shown on the desktop again.
        let back = HiddenWindows.update(onFullScreen, found: [:], looked: [desktop], exists: { _ in true })
        #expect(HiddenWindows.returned(window, on: desktop, before: onFullScreen, now: back))
    }

    @Test func aWindowStillHiddenHasNotReturned() {
        let record = [desktop: Set([window])]
        #expect(!HiddenWindows.returned(window, on: desktop, before: record, now: record))
    }

    @Test func aWindowNeverHiddenHasNotReturned() {
        #expect(!HiddenWindows.returned(window, on: desktop, before: [other: [window]], now: [:]))
    }
}

@Test func theWindowsThatCameBackAreTheOnesNoLongerHidden() {
    // On strip "a" window 2 was minimized and is back, 3 still is; on "b" window 7 came back from a hidden app.
    let before: [String: Set<WindowID>] = ["a": [2, 3], "b": [7]]
    let now: [String: Set<WindowID>] = ["a": [3]]
    #expect(HiddenWindows.returned(before: before, now: now) == [2, 7])
    #expect(HiddenWindows.returned(before: now, now: now).isEmpty)
}
