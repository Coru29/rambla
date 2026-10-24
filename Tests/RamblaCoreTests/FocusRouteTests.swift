import Testing
@testable import RamblaCore

struct FocusRouteTests {
    /// The focus lands on a window of level 1 while level 0 is in view, unless a test says otherwise.
    func decide(level: Int = 1, active: Int = 0, byActivation: Bool = false, afterLoss: Bool = false,
                chosen: Bool = false, app: [WindowID] = [], all: [WindowID] = [],
                sinceOwnSwitch: Double? = nil) -> FocusRoute {
        FocusRoute.decide(windowLevel: level, active: active, byActivation: byActivation, afterLoss: afterLoss,
                          chosen: chosen, appWindowsInView: app, windowsInView: all, sinceOwnSwitch: sinceOwnSwitch)
    }

    @Test func aWindowInViewNeedsNothing() {
        #expect(decide(level: 0) == .none)
        // Whatever brought the focus there: an activation, a loss, a report right after a switch.
        #expect(decide(level: 2, active: 2, byActivation: true, afterLoss: true, app: [5], all: [5, 3],
                       sinceOwnSwitch: 0.1) == .none)
    }

    @Test func activationWithAWindowInViewRedirectsToTheLastUsed() {
        // ⌘Tab, the Dock or a notification chose the app, not that window: like macOS's desktops, its windows in view.
        #expect(decide(byActivation: true, app: [5, 9], all: [3, 5, 9]) == .redirect(5))
    }

    @Test func activationWithoutWindowsInViewSwitches() {
        // Other apps' windows in view do not keep the app from its own.
        #expect(decide(byActivation: true, app: [], all: [3, 4]) == .switchLevel)
        #expect(decide(byActivation: true) == .switchLevel)
    }

    @Test func focusWithoutActivationSwitches() {
        // Mission Control or ⌘` chose that very window: its level comes into view even when its app has windows in the
        // one in view.
        #expect(decide(app: [5], all: [5, 3]) == .switchLevel)
        #expect(decide() == .switchLevel)
    }

    @Test func aLateReportRightAfterOwnSwitchIsLeftAloneForNow() {
        // The app that was in front reports focus on its window, now out of view, before the new one takes over.
        #expect(decide(app: [5], all: [5], sinceOwnSwitch: 0.2) == .lateReport)
        #expect(decide(app: [5], all: [5], sinceOwnSwitch: 0.8) == .switchLevel)
        #expect(decide(sinceOwnSwitch: FocusRoute.lateReportWindow) == .switchLevel)
        // An activation is the user's: right after a switch too, it follows the activation rules.
        #expect(decide(byActivation: true, app: [5], all: [5], sinceOwnSwitch: 0.2) == .redirect(5))
        #expect(decide(byActivation: true, all: [3], sinceOwnSwitch: 0.2) == .switchLevel)
    }

    @Test func aLateReportIsOnlyProvisional() {
        // In view it is no late report: nothing to wait for.
        #expect(decide(level: 0, sinceOwnSwitch: 0.1) == .none)
        // The window still has the focus once a report could no longer be late (⌘` twice across strips, the Window menu
        // right after a switch): decided again without the rule, the user chose it, and its level comes into view…
        #expect(decide(app: [5], all: [5], sinceOwnSwitch: 0.2) == .lateReport)
        #expect(decide(app: [5], all: [5], sinceOwnSwitch: nil) == .switchLevel)
        // …or, with nothing that holds it, too: the keyboard never stays in a window out of sight.
        #expect(decide(sinceOwnSwitch: nil) == .switchLevel)
    }

    @Test func aCloseKeepsTheSameAppWhenItCan() {
        #expect(decide(afterLoss: true, app: [8], all: [3, 8]) == .redirect(8))
        // Right after a switch too: a loss is never a late report.
        #expect(decide(afterLoss: true, app: [8], all: [3, 8], sinceOwnSwitch: 0.1) == .redirect(8))
    }

    @Test func aCloseThatHandsTheFocusToAnotherStripStays() {
        #expect(decide(afterLoss: true, app: [], all: [3, 4]) == .redirect(3))
        // Quitting an app activates the next one: still macOS moving the focus, not the user.
        #expect(decide(byActivation: true, afterLoss: true, app: [], all: [3, 4]) == .redirect(3))
    }

    @Test func aCloseWithNothingLeftInViewTakesTheKeyboard() {
        #expect(decide(afterLoss: true) == .takeKeyboard)
        #expect(decide(byActivation: true, afterLoss: true) == .takeKeyboard)
    }

    @Test func aWindowBroughtBackFromTheDockGoesToItsLevel() {
        // Picking that very window in the Dock is a choice, like Mission Control: its level comes into view even when
        // its app was activated with it and has windows in view…
        #expect(decide(byActivation: true, chosen: true, app: [5], all: [5, 3]) == .switchLevel)
        // …and right after a switch, since it is no late report.
        #expect(decide(chosen: true, all: [3], sinceOwnSwitch: 0.2) == .switchLevel)
        // In view it needs nothing; after a loss macOS is moving the focus by itself, which never changes the level.
        #expect(decide(level: 0, chosen: true) == .none)
        #expect(decide(afterLoss: true, chosen: true, app: [5], all: [3, 5]) == .redirect(5))
        #expect(decide(afterLoss: true, chosen: true) == .takeKeyboard)
    }

    @Test func windowsInViewGoMostRecentlyUsedFirst() {
        // Those never focused go last, in strip order; so do ties.
        #expect(FocusRoute.byLastUse([1, 2, 3, 4, 5], lastUsed: [4: 10, 2: 30, 5: 20]) == [2, 5, 4, 1, 3])
        #expect(FocusRoute.byLastUse([7, 6, 8], lastUsed: [6: 5, 7: 5, 9: 50]) == [7, 6, 8])
        #expect(FocusRoute.byLastUse([], lastUsed: [1: 1]) == [])
    }
}
