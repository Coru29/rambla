import Testing
@testable import RamblaCore

// A logout, a restart or a shutdown quits the apps, and each app that quits takes its windows out of the strips: the
// layout saved for the next login is the one from before.

private func layout(_ windows: [WindowID]) -> SavedState {
    SavedState(session: "today", refs: windows.map { WindowRef(id: $0, bundleID: "app", title: "window \($0)") })
}

private let hold = LogoutLayout.hold
private let run = LogoutLayout.closingRun

@Test func aNoticeSavesTheLayoutAsItIsAndHoldsSaving() {
    var logout = LogoutLayout()
    #expect(!logout.isHeld(at: 100))
    #expect(logout.heldFor(at: 100) == nil)
    #expect(logout.logoutBegan(.notice, at: 100, layout: layout([1, 2, 3])) == layout([1, 2, 3]))
    #expect(logout.isHeld(at: 101))
    #expect(logout.heldFor(at: 101) == hold - 1)
    // A logout cancelled with no notice: saving goes on once the hold is over.
    #expect(!logout.isHeld(at: 100 + hold))
}

@Test func appsQuittingAfterTheNoticeChangeNothingSaved() {
    // Rambla's own quit comes after the apps that quit before it: the notice saved the layout, and nothing replaces it.
    var logout = LogoutLayout()
    _ = logout.logoutBegan(.notice, at: 100, layout: layout([1, 2, 3]))
    logout.windowGoes(at: 101) { layout([1, 2, 3]) }
    logout.windowGoes(at: 102) { layout([1, 3]) }
    #expect(logout.logoutBegan(.quit, at: 103, layout: layout([3])) == nil)
    // Even when the apps took longer than a run of closings.
    #expect(logout.logoutBegan(.quit, at: 102 + run + 5, layout: layout([3])) == nil)
    #expect(logout.isHeld(at: 104))
}

@Test func anotherNoticeAfterAppsQuitKeepsWhatTheFirstSaved() {
    // loginwindow may say a logout began and then that a restart did: by the second notice apps may be gone.
    var logout = LogoutLayout()
    _ = logout.logoutBegan(.notice, at: 100, layout: layout([1, 2, 3]))
    logout.windowGoes(at: 101) { layout([1, 2, 3]) }
    #expect(logout.logoutBegan(.notice, at: 101 + run + 5, layout: layout([3])) == nil)
}

@Test func aQuitAfterAppsQuitSavesTheLayoutFromBeforeThem() {
    // No notice came, and macOS quit apps before Rambla: the layout from before the first of them is the one saved.
    var logout = LogoutLayout()
    var asked = 0
    logout.windowGoes(at: 100) { asked += 1; return layout([1, 2, 3, 4]) }
    logout.windowGoes(at: 101) { asked += 1; return layout([2, 3, 4]) }
    logout.windowGoes(at: 103) { asked += 1; return layout([3, 4]) }
    #expect(asked == 1)
    #expect(logout.logoutBegan(.quit, at: 104, layout: layout([4])) == layout([1, 2, 3, 4]))
    #expect(logout.isHeld(at: 105))
}

@Test func aNoticeRightAfterAppsQuitAlsoSavesTheLayoutFromBeforeThem() {
    var logout = LogoutLayout()
    logout.windowGoes(at: 100) { layout([1, 2]) }
    #expect(logout.logoutBegan(.notice, at: 101, layout: layout([2])) == layout([1, 2]))
}

@Test func aWindowTheUserClosedBeforeTheNoticeStaysClosed() {
    // `exit` in one terminal, then Restart: the notice comes before macOS quits anything, so a closing seconds before
    // it is the user's. Saved, the closed window would also keep the other terminal from being recognised later.
    var logout = LogoutLayout()
    logout.windowGoes(at: 100) { layout([1, 2]) }
    #expect(logout.logoutBegan(.notice, at: 105, layout: layout([2])) == layout([2]))
}

@Test func aRunOfClosingsGoesOnWhileTheyComeMomentsApart() {
    var logout = LogoutLayout()
    logout.windowGoes(at: 100) { layout([1, 2, 3, 4]) }
    logout.windowGoes(at: 105) { layout([2, 3, 4]) }
    logout.windowGoes(at: 110) { layout([3, 4]) }
    #expect(logout.logoutBegan(.quit, at: 115, layout: layout([4])) == layout([1, 2, 3, 4]))
}

@Test func aRunBegunLongBeforeTheLogoutIsTheUsers() {
    // A minute closing windows and tabs by hand, a few seconds apart, and then a restart: what they did meanwhile stays.
    var logout = LogoutLayout()
    for at in stride(from: 100.0, through: 140, by: 8) {
        logout.windowGoes(at: at) { layout([1, 2, 3, 4, 5, 6]) }
    }
    #expect(logout.logoutBegan(.quit, at: 141, layout: layout([6, 7])) == layout([6, 7]))
}

@Test func closingsLongBeforeTheLogoutDoNotCount() {
    // The user closed a window a while ago: the layout as it is now is the one saved.
    var logout = LogoutLayout()
    logout.windowGoes(at: 100) { layout([1, 2]) }
    #expect(logout.logoutBegan(.quit, at: 101 + run, layout: layout([2, 5])) == layout([2, 5]))

    // A new run after a pause starts from the layout as it was then.
    var later = LogoutLayout()
    later.windowGoes(at: 100) { layout([1, 2, 3]) }
    later.windowGoes(at: 101 + run) { layout([2, 3]) }
    #expect(later.logoutBegan(.quit, at: 102 + run, layout: layout([3])) == layout([2, 3]))
}

@Test func aCancelledLogoutLetsSavingGoOn() {
    var logout = LogoutLayout()
    logout.windowGoes(at: 100) { layout([1, 2]) }
    _ = logout.logoutBegan(.notice, at: 101, layout: layout([2]))
    logout.logoutCancelled()
    #expect(!logout.isHeld(at: 102))
    // The apps that quit before it was cancelled are gone: another logout saves the layout as it is.
    #expect(logout.logoutBegan(.quit, at: 103, layout: layout([2])) == layout([2]))
}

@Test func aSecondNoticeSavesAgainWhenNothingWentAway() {
    // A logout cancelled with no notice, then another: the second notice saves the layout as it is by then.
    var logout = LogoutLayout()
    _ = logout.logoutBegan(.notice, at: 100, layout: layout([1, 2]))
    #expect(logout.logoutBegan(.notice, at: 200, layout: layout([1, 2, 5])) == layout([1, 2, 5]))
    #expect(logout.isHeld(at: 200 + hold - 1))
}

@Test func theHoldEndsHoweverManyWindowsGoMeanwhile() {
    // A logout cancelled with no notice, and the user keeps working: saving goes on once the hold is over.
    var logout = LogoutLayout()
    _ = logout.logoutBegan(.notice, at: 100, layout: layout([1, 2]))
    logout.windowGoes(at: 100 + hold - 10) { layout([1, 2]) }
    #expect(logout.isHeld(at: 100 + hold - 1))
    #expect(!logout.isHeld(at: 100 + hold))
}

@Test func aNoticeLongAfterTheHoldBeganIsAnotherLogout() {
    // A restart that an app refused, with no notice that it was cancelled, the user working on, then a real restart:
    // its notice saves the layout as it is by then.
    var logout = LogoutLayout()
    _ = logout.logoutBegan(.notice, at: 100, layout: layout([1, 2, 3]))
    logout.windowGoes(at: 110) { layout([1, 2, 3]) }
    let later = 100 + LogoutLayout.newLogoutAfter + 60
    #expect(logout.logoutBegan(.notice, at: later, layout: layout([1, 2, 7])) == layout([1, 2, 7]))
    // Its own quit, later on, keeps it.
    #expect(logout.logoutBegan(.quit, at: later + 5, layout: layout([7])) == nil)
}

@Test func aQuitWithNoNoticeHoldsSavingToo() {
    // Rambla's own last save, as it quits, must not replace it.
    var logout = LogoutLayout()
    #expect(logout.logoutBegan(.quit, at: 100, layout: layout([1, 2])) == layout([1, 2]))
    #expect(logout.isHeld(at: 101))
}

@Test func noLayoutToSaveStillHoldsSaving() {
    // Test mode without a layout file of its own, or no window known yet: nothing to save, and nothing saved later.
    var logout = LogoutLayout()
    #expect(logout.logoutBegan(.notice, at: 100, layout: nil) == nil)
    #expect(logout.isHeld(at: 101))
}
