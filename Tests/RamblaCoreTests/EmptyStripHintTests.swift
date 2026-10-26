import Testing
@testable import RamblaCore

// MARK: - Helpers

/// The four shortcuts the hint can name, under made-up key codes, so that a test sees which one it got.
private let shortcutNames: [UInt16: String] = [1: "send-up", 2: "send-down", 3: "go-up", 4: "go-down"]

private func name(_ combo: KeyCombo) -> String { shortcutNames[combo.keyCode] ?? "?" }

/// Preferences as a user has them by default: the trackpad swipes up and down change strips, with the natural direction,
/// and the four strip shortcuts are bound.
private func tidyPrefs() -> Preferences {
    var prefs = Preferences()
    prefs.setShortcuts([KeyCombo(keyCode: 1, modifiers: .command)], for: .sendStripUp)
    prefs.setShortcuts([KeyCombo(keyCode: 2, modifiers: .command)], for: .sendStripDown)
    prefs.setShortcuts([KeyCombo(keyCode: 3, modifiers: .command)], for: .stripUp)
    prefs.setShortcuts([KeyCombo(keyCode: 4, modifiers: .command)], for: .stripDown)
    return prefs
}

private func detail(active: Int, occupied: Set<Int>, _ prefs: Preferences) -> String {
    EmptyStripHint.detail(active: active, occupied: occupied, prefs: prefs, shortcutName: name)
}

private let open = "Abrí acá lo que quieras."

// MARK: - Where the windows are

@Test func withNoWindowsAnywhereItOnlySaysToOpenSomething() {
    #expect(detail(active: 0, occupied: [], tidyPrefs()) == open)
}

@Test func withWindowsBelowItBringsOneFromThereAndGoesBackDown() {
    // From the strip below, "send up" brings its focused window here. With the natural direction the fingers go up to
    // see the strip below.
    #expect(detail(active: 1, occupied: [0], tidyPrefs())
        == "\(open) O mandá una ventana desde la tira de abajo con send-up. Para volver, deslizá hacia arriba o usá go-down.")
}

@Test func withWindowsAboveItBringsOneFromThereAndGoesBackUp() {
    #expect(detail(active: 0, occupied: [1], tidyPrefs())
        == "\(open) O mandá una ventana desde la tira de arriba con send-down. Para volver, deslizá hacia abajo o usá go-up.")
}

@Test func theNearestStripWithWindowsIsTheOneItPointsAt() {
    let prefs = tidyPrefs()
    // One level above, another two below: the one above is nearer.
    #expect(detail(active: 2, occupied: [0, 3], prefs).contains("de arriba con send-down"))
    // Levels in between with no windows do not count.
    #expect(detail(active: 3, occupied: [0, 1], prefs).contains("de abajo con send-up"))
    #expect(detail(active: 0, occupied: [2, 5], prefs).contains("de arriba con send-down"))
}

@Test func withOneAsNearOnEachSideItPointsBelow() {
    #expect(detail(active: 1, occupied: [0, 2], tidyPrefs()).contains("de abajo con send-up"))
}

@Test func theEmptyStripItselfIsNoWayBack() {
    #expect(detail(active: 1, occupied: [1], tidyPrefs()) == open)
}

// MARK: - The swipe

@Test func withoutTheNaturalDirectionTheSwipeWordsSwap() {
    var prefs = tidyPrefs()
    prefs.trackpad.natural = false
    #expect(detail(active: 1, occupied: [0], prefs).hasSuffix("Para volver, deslizá hacia abajo o usá go-down."))
    #expect(detail(active: 0, occupied: [1], prefs).hasSuffix("Para volver, deslizá hacia arriba o usá go-up."))
}

@Test func theSwipeIsNotMentionedWhenTheTrackpadDoesNotChangeStrips() {
    var trackpadOff = tidyPrefs()
    trackpadOff.trackpad.enabled = false
    var swipesOff = tidyPrefs()
    swipesOff.trackpad.verticalSwipe = false
    var widthMode = tidyPrefs()
    widthMode.verticalGesture = .width
    for prefs in [trackpadOff, swipesOff, widthMode] {
        #expect(detail(active: 1, occupied: [0], prefs).hasSuffix(" Para volver, usá go-down."))
        #expect(detail(active: 0, occupied: [1], prefs).hasSuffix(" Para volver, usá go-up."))
    }
}

// MARK: - Shortcuts that are not bound

@Test func aSendShortcutThatIsNotBoundLeavesItsSentenceOut() {
    var prefs = tidyPrefs()
    prefs.setShortcuts([], for: .sendStripUp)
    #expect(detail(active: 1, occupied: [0], prefs) == "\(open) Para volver, deslizá hacia arriba o usá go-down.")
    // The other direction still has its own.
    #expect(detail(active: 0, occupied: [1], prefs).contains("O mandá una ventana desde la tira de arriba con send-down."))
}

@Test func aBackShortcutThatIsNotBoundKeepsTheSwipe() {
    var prefs = tidyPrefs()
    prefs.setShortcuts([], for: .stripDown)
    #expect(detail(active: 1, occupied: [0], prefs)
        == "\(open) O mandá una ventana desde la tira de abajo con send-up. Para volver, deslizá hacia arriba.")
    prefs.setShortcuts([], for: .stripUp)
    #expect(detail(active: 0, occupied: [1], prefs)
        == "\(open) O mandá una ventana desde la tira de arriba con send-down. Para volver, deslizá hacia abajo.")
}

@Test func withNeitherTheSwipeNorTheShortcutThereIsNoWayBackToSay() {
    var prefs = tidyPrefs()
    prefs.trackpad.verticalSwipe = false
    prefs.setShortcuts([], for: .stripDown)
    #expect(detail(active: 1, occupied: [0], prefs) == "\(open) O mandá una ventana desde la tira de abajo con send-up.")
    prefs.setShortcuts([], for: .sendStripUp)
    #expect(detail(active: 1, occupied: [0], prefs) == open)
}

@Test func theFirstShortcutOfAnActionIsTheOneNamed() {
    var prefs = tidyPrefs()
    prefs.setShortcuts([KeyCombo(keyCode: 2, modifiers: .command), KeyCombo(keyCode: 1, modifiers: .command)], for: .sendStripUp)
    #expect(detail(active: 1, occupied: [0], prefs).contains("con send-down."))
}
