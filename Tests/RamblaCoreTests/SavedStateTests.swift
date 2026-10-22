import Testing
import Foundation
@testable import RamblaCore

private func savedColumn(_ windows: [WindowID], _ width: ColumnWidth = .fraction(0.5)) -> Column {
    Column(windows: windows, width: width)
}

// MARK: - StateMatcher

@Test func matcherByIdThenTitle() {
    let terminal = "com.apple.Terminal", safari = "com.apple.Safari", notes = "com.apple.Notes"
    let saved = [
        WindowRef(id: 10, bundleID: terminal, title: "zsh"),      // same id and bundle are alive: pass 1
        WindowRef(id: 11, bundleID: terminal, title: "build"),    // id is gone, same title is alive: pass 2
        WindowRef(id: 12, bundleID: safari, title: "Apple"),      // the id now belongs to another app: pass 2 by title
        WindowRef(id: 13, bundleID: notes, title: ""),            // empty titles never match
        WindowRef(id: 14, bundleID: notes, title: "Shopping"),    // nothing alive matches
    ]
    let live = [
        WindowRef(id: 10, bundleID: terminal, title: "vim"),
        WindowRef(id: 90, bundleID: terminal, title: "build"),
        WindowRef(id: 12, bundleID: notes, title: "Other"),
        WindowRef(id: 91, bundleID: safari, title: "Apple"),
        WindowRef(id: 92, bundleID: notes, title: ""),
    ]
    #expect(StateMatcher.match(saved: saved, live: live) == [10: 10, 11: 90, 12: 91])
}

@Test func matcherReservesIdMatchesBeforeTitleMatches() {
    let app = "com.example.App"
    // A single pass in saved order would give saved 1 the live window 2 (same title) and cross the mapping.
    let saved = [WindowRef(id: 1, bundleID: app, title: "doc"), WindowRef(id: 2, bundleID: app, title: "doc")]
    let live = [WindowRef(id: 2, bundleID: app, title: "doc"), WindowRef(id: 3, bundleID: app, title: "doc")]
    #expect(StateMatcher.match(saved: saved, live: live) == [2: 2, 1: 3])
}

@Test func matcherUsesEachLiveWindowOnce() {
    let app = "com.example.App"
    // One live window can serve only one saved window; the earlier saved window wins.
    let two = [WindowRef(id: 1, bundleID: app, title: "x"), WindowRef(id: 2, bundleID: app, title: "x")]
    #expect(StateMatcher.match(saved: two, live: [WindowRef(id: 9, bundleID: app, title: "x")]) == [1: 9])
    // Equal titles are consumed in order.
    let saved = [1, 2, 3].map { WindowRef(id: WindowID($0), bundleID: app, title: "x") }
    let live = [7, 8, 9].map { WindowRef(id: WindowID($0), bundleID: app, title: "x") }
    let mapping = StateMatcher.match(saved: saved, live: live)
    #expect(mapping == [1: 7, 2: 8, 3: 9])
    #expect(Set(mapping.values).count == mapping.count)
}

@Test func matcherRequiresSameBundle() {
    let saved = [WindowRef(id: 5, bundleID: "com.example.A", title: "t")]
    #expect(StateMatcher.match(saved: saved, live: [WindowRef(id: 5, bundleID: "com.example.B", title: "t")]).isEmpty)
    #expect(StateMatcher.match(saved: saved, live: [WindowRef(id: 6, bundleID: "com.example.B", title: "t")]).isEmpty)
    #expect(StateMatcher.match(saved: saved, live: []).isEmpty)
    #expect(StateMatcher.match(saved: [], live: saved).isEmpty)
}

@Test func windowRefIsHashable() {
    let a = WindowRef(id: 1, bundleID: "com.example.A", title: "t")
    let b = WindowRef(id: 1, bundleID: "com.example.A", title: "t")
    let c = WindowRef(id: 1, bundleID: "com.example.A", title: "other")
    #expect(Set([a, b, c]).count == 2)
}

// MARK: - Strip.remapped

@Test func remappedDropsEmptyColumns() {
    var c0 = savedColumn([1, 2]); c0.heightWeights = [1, 3]; c0.active = 1
    let c1 = savedColumn([3])
    var c2 = savedColumn([4, 5], .points(400)); c2.active = 1
    let strip = Strip(columns: [c0, c1, c2], focused: 2, scroll: 321)

    let r = strip.remapped([2: 20, 4: 40, 5: 50])
    #expect(r.columns.map { $0.windows } == [[20], [40, 50]])
    #expect(r.columns.map { $0.heightWeights } == [[3], [1, 1]])   // weights of dropped windows are dropped too
    #expect(r.columns.map { $0.id } == [c0.id, c2.id])             // column 1 lost every window and is gone
    #expect(r.columns.map { $0.active } == [0, 1])                 // the active window is still the same window
    #expect(r.focused == 1)                                        // the focused column is still the same column
    #expect(r.scroll == 321)
}

@Test func remappedKeepsColumnProperties() {
    var c = savedColumn([1, 2], .points(400))
    c.mode = .tabbed
    c.pinned = .right
    c.widthBeforeFull = .fraction(0.25)
    c.heightFraction = 0.6
    let r = Strip(columns: [c], focused: 0, scroll: 7).remapped([1: 11, 2: 22])
    var expected = c
    expected.windows = [11, 22]
    #expect(r.columns == [expected])
    #expect(r.columns[0].mode == .tabbed)
    #expect(r.columns[0].pinned == .right)
    #expect(r.columns[0].width == .points(400))
    #expect(r.columns[0].widthBeforeFull == .fraction(0.25))
    #expect(r.columns[0].heightFraction == 0.6)
}

@Test func remappedFocusFollowsItsColumnOrClamps() {
    let strip = Strip(columns: [savedColumn([1]), savedColumn([2]), savedColumn([3])], focused: 1)
    // An earlier column disappears: focus stays on the same column object.
    #expect(strip.remapped([2: 2, 3: 3]).focused == 0)
    // The focused column disappears: the index clamps into the new range, so the next column slides under it.
    #expect(strip.remapped([1: 1, 3: 3]).focused == 1)
    // The focused column was the last one and disappears: clamp to the new last column.
    let lastFocused = Strip(columns: [savedColumn([1]), savedColumn([2]), savedColumn([3])], focused: 2)
    #expect(lastFocused.remapped([1: 1]).focused == 0)
    // No focus stays no focus.
    let unfocused = Strip(columns: [savedColumn([1])], focused: nil)
    #expect(unfocused.remapped([1: 1]).focused == nil)
    // Nothing left.
    let empty = strip.remapped([:])
    #expect(empty.columns.isEmpty)
    #expect(empty.focused == nil)
}

@Test func remappedClampsFocusedThatWasOutOfRange() {
    let strip = Strip(columns: [savedColumn([1]), savedColumn([2])], focused: 5)
    #expect(strip.remapped([1: 1, 2: 2]).focused == 1)
}

@Test func remappedKeepsActiveWindowOrClamps() {
    var c = savedColumn([1, 2, 3]); c.heightWeights = [1, 2, 3]; c.active = 2
    let strip = Strip(columns: [c], focused: 0)

    // The active window is dropped: active clamps into the remaining windows.
    let dropActive = strip.remapped([1: 1, 2: 2])
    #expect(dropActive.columns[0].windows == [1, 2])
    #expect(dropActive.columns[0].heightWeights == [1, 2])
    #expect(dropActive.columns[0].active == 1)

    // An earlier window is dropped: active follows its window.
    let dropEarlier = strip.remapped([2: 2, 3: 3])
    #expect(dropEarlier.columns[0].windows == [2, 3])
    #expect(dropEarlier.columns[0].heightWeights == [2, 3])
    #expect(dropEarlier.columns[0].active == 1)

    // The active window in the middle is dropped: the window that slid into its slot becomes active.
    var middle = c; middle.active = 1
    let dropMiddle = Strip(columns: [middle], focused: 0).remapped([1: 1, 3: 3])
    #expect(dropMiddle.columns[0].windows == [1, 3])
    #expect(dropMiddle.columns[0].active == 1)

    // Same result as removing the windows one by one (the strip operations' `remove`): dropping window 1 shifts the
    // active slot to index 0, dropping window 2 (the active one) leaves window 3 in that slot. Clamping the old
    // index (1) would wrongly pick window 4.
    var five = savedColumn([1, 2, 3, 4, 5]); five.active = 1
    let dropFirstTwo = Strip(columns: [five], focused: 0).remapped([3: 3, 4: 4, 5: 5])
    #expect(dropFirstTwo.columns[0].windows == [3, 4, 5])
    #expect(dropFirstTwo.columns[0].active == 0)
    // An active window past the end (stale state) lands on the last window.
    var stale = savedColumn([1, 2, 3]); stale.active = 7
    #expect(Strip(columns: [stale], focused: 0).remapped([1: 1, 2: 2, 3: 3]).columns[0].active == 2)
}

@Test func remappedRenamesWindowsAndKeepsOrder() {
    let strip = Strip(columns: [savedColumn([1, 2]), savedColumn([3]), savedColumn([4])], focused: 0, scroll: -12.5)
    let r = strip.remapped([4: 400, 3: 300, 2: 200, 1: 100])
    #expect(r.columns.map { $0.windows } == [[100, 200], [300], [400]])
    #expect(r.focused == 0)
    #expect(r.scroll == -12.5)
}

@Test func remappedNeverPlacesAWindowTwice() {
    let strip = Strip(columns: [savedColumn([1]), savedColumn([2, 3])], focused: 1)
    let r = strip.remapped([1: 9, 2: 9, 3: 8])
    #expect(r.columns.map { $0.windows } == [[9], [8]])
    #expect(r.columns[1].heightWeights.count == 1)
}

@Test func remappedEmptyStripStaysEmpty() {
    #expect(Strip().remapped([1: 2]) == Strip())
    #expect(Strip(scroll: 50).remapped([:]).scroll == 50)
}

// MARK: - SavedState

@Test func savedStateRoundTripsThroughJSON() throws {
    var column = savedColumn([1, 2], .points(480)); column.mode = .tabbed; column.pinned = .left
    let state = SavedState(
        refs: [WindowRef(id: 1, bundleID: "com.apple.Terminal", title: "zsh"),
               WindowRef(id: 2, bundleID: "com.apple.Safari", title: "Apple")],
        strips: [SavedStrip(displayUUID: "37D8832A-2D66-02CA-B9F7-8F30A301B230", spaceKey: "1",
                            strip: Strip(columns: [column, savedColumn([3])], focused: 1, scroll: 12.5))],
        floating: [7, 8])
    #expect(state.version == 2)
    let decoded = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
    #expect(decoded == state)
    #expect(SavedState().version == SavedState.currentVersion)
    #expect(SavedState().strips.isEmpty)
}

@Test func savedStateFromVersionOneForgetsItsFloatingWindows() throws {
    // Version 1 also saved the windows Rambla floated by itself (moved by another app), which kept them out of the
    // strip after every restart. Its floating list cannot tell them apart, so it is dropped.
    let json = """
    {"version": 1, "refs": [{"id": 7, "bundleID": "net.kovidgoyal.kitty", "title": "zsh"}], "strips": [], "floating": [7]}
    """
    let old = try JSONDecoder().decode(SavedState.self, from: Data(json.utf8))
    let upgraded = old.upgraded()
    #expect(upgraded.version == SavedState.currentVersion)
    #expect(upgraded.floating.isEmpty)
    #expect(upgraded.refs == old.refs)
}

@Test func savedStateFromThisVersionKeepsItsFloatingWindows() {
    let state = SavedState(floating: [7, 8])
    #expect(state.upgraded() == state)
}

@Test func matcherCanLeaveTitlesOut() {
    // After the first moments of a session, a new window that happens to share a saved title must not inherit its
    // place (a floating "zsh" would make every new Terminal window float).
    let saved = [WindowRef(id: 1, bundleID: "com.apple.Terminal", title: "zsh"),
                 WindowRef(id: 2, bundleID: "com.apple.Safari", title: "Apple")]
    let live = [WindowRef(id: 9, bundleID: "com.apple.Terminal", title: "zsh"),
                WindowRef(id: 2, bundleID: "com.apple.Safari", title: "Apple")]
    #expect(StateMatcher.match(saved: saved, live: live) == [1: 9, 2: 2])
    #expect(StateMatcher.match(saved: saved, live: live, byTitle: false) == [2: 2])
}

@Test func matcherFollowsTheSessionTheWindowsWereSavedIn() {
    let terminal = "com.apple.Terminal"
    let saved = [WindowRef(id: 7, bundleID: terminal, title: "zsh")]
    let sameID = WindowRef(id: 7, bundleID: terminal, title: "vim")
    let sameTitle = WindowRef(id: 30, bundleID: terminal, title: "zsh")
    // In the login session they were saved in, a live id is that window: while window 7 exists, a new "zsh" window
    // is another window.
    #expect(StateMatcher.match(saved: saved, live: [sameTitle], session: "today", current: "today", alive: [7]).isEmpty)
    #expect(StateMatcher.match(saved: saved, live: [sameTitle, sameID], session: "today", current: "today",
                               alive: [7, 30]) == [7: 7])
    // Once window 7 is gone (closed, or its app restarted), its title may find it again.
    #expect(StateMatcher.match(saved: saved, live: [sameTitle], session: "today", current: "today", alive: [30]) == [7: 30])
    #expect(StateMatcher.match(saved: saved, live: [sameTitle], session: "today", current: "today", alive: [30],
                               byTitle: false).isEmpty)
    // After a logout or a restart ids are handed out again: only the title tells.
    #expect(StateMatcher.match(saved: saved, live: [sameID, sameTitle], session: "earlier", current: "today",
                               alive: [7, 30]) == [7: 30])
    #expect(StateMatcher.match(saved: saved, live: [sameID], session: "earlier", current: "today", alive: [7]).isEmpty)
    #expect(StateMatcher.match(saved: saved, live: [sameTitle], session: "earlier", current: "today", alive: [30],
                               byTitle: false).isEmpty)
    // Files from before 1.1.0 do not say: ids first, then titles.
    #expect(StateMatcher.match(saved: saved, live: [sameTitle, sameID], session: nil, current: "today",
                               alive: [7, 30]) == [7: 7])
    #expect(StateMatcher.match(saved: saved, live: [sameTitle], session: nil, current: "today", alive: [30]) == [7: 30])
    #expect(StateMatcher.match(saved: saved, live: [sameTitle], session: nil, current: "today", alive: [30],
                               byTitle: false).isEmpty)
}

@Test func anAmbiguousTitleCanBeLeftUnmatched() {
    // Two Terminal windows with the default title: which one was saved cannot be told.
    let saved = [WindowRef(id: 7, bundleID: "com.apple.Terminal", title: "user — -zsh — 80×24")]
    let twins = [WindowRef(id: 30, bundleID: "com.apple.Terminal", title: "user — -zsh — 80×24"),
                 WindowRef(id: 31, bundleID: "com.apple.Terminal", title: "user — -zsh — 80×24")]
    #expect(StateMatcher.match(saved: saved, live: twins, session: "earlier", current: "today", alive: [30, 31]) == [7: 30])
    #expect(StateMatcher.match(saved: saved, live: twins, session: "earlier", current: "today", alive: [30, 31],
                               uniqueTitles: true).isEmpty)
    #expect(StateMatcher.match(saved: saved, live: [twins[0]], session: "earlier", current: "today", alive: [30],
                               uniqueTitles: true) == [7: 30])
}
