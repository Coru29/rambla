import Testing
import Foundation
@testable import RamblaCore

// Strips that are not in view this session (a Space not visited since Rambla started, a display that was unplugged)
// keep their arrangement in the archive, and the archive is saved together with the live strips.

private let day: TimeInterval = 24 * 60 * 60
private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func strip(_ windows: [WindowID]) -> Strip {
    var strip = Strip()
    for window in windows { strip.insert(window: window, width: .fraction(0.5), at: .end) }
    return strip
}

private func saved(_ display: String, _ space: String, _ windows: [WindowID], seen: Date? = nil,
                   session: String? = "today", unplugged: Bool = false, level: Int = 0,
                   activeLevel: Int? = nil) -> SavedStrip {
    SavedStrip(displayUUID: display, spaceKey: space, strip: strip(windows), lastSeen: seen, session: session,
               refs: windows.map { ref($0) }, unplugged: unplugged, level: level, activeLevel: activeLevel)
}

private func ref(_ id: WindowID, _ app: String = "app") -> WindowRef {
    WindowRef(id: id, bundleID: app, title: "window \(id)")
}

@Test func theArchiveStartsWithEverySavedStrip() {
    // Files from before 1.1.0 say nothing about the session and keep every window's ref in one shared list.
    let file = SavedState(refs: [ref(1), ref(2), ref(3)],
                          strips: [saved("A", "s1", [1, 2], session: nil), saved("B", "s2", [3], session: nil)])
    let archive = StripArchive(loading: file, at: now)
    #expect(archive.strips.count == 2)
    #expect(archive.strips.allSatisfy { $0.lastSeen == now })                      // older files have no date
    #expect(archive.strips.map(\.refs) == [[ref(1), ref(2)], [ref(3)]])
}

@Test func takingAStripRemovesItFromTheArchive() {
    var archive = StripArchive(loading: SavedState(strips: [saved("A", "s1", [1])]), at: now)
    #expect(archive.takeStack(displayUUID: "A", spaceKey: "s2").isEmpty)
    #expect(archive.takeStack(displayUUID: "A", spaceKey: "s1").map(\.strip.allWindows) == [[1]])
    #expect(archive.takeStack(displayUUID: "A", spaceKey: "s1").isEmpty)
    #expect(archive.strips.isEmpty)
}

@Test func storingAStripReplacesTheOneOfTheSameSpace() {
    var archive = StripArchive()
    archive.store(saved("A", "s1", [1]), at: now - day)
    archive.store(saved("A", "s1", [2, 3], unplugged: true), at: now)
    #expect(archive.strips.map(\.strip.allWindows) == [[2, 3]])
    #expect(archive.strips.first?.lastSeen == now)
    #expect(archive.strips.first?.unplugged == true)
}

@Test func savingKeepsTheArchivedStripsOfSpacesNotInView() {
    // Two restarts without visiting a Space used to lose its strip: the second save no longer knew it.
    let archive = StripArchive(loading: SavedState(strips: [saved("A", "unvisited", [7], seen: now - day)]), at: now)
    let live = SavedState(session: "today", refs: [ref(1)], strips: [saved("A", "current", [1])], floating: [])
    let state = archive.merged(into: live, at: now)
    #expect(state.strips.map(\.spaceKey) == ["current", "unvisited"])
    #expect(state.strips.first?.lastSeen == now)                                   // the live one was seen now
    #expect(state.strips.last?.lastSeen == now - day)                              // the archived one keeps its date
    #expect(Set(state.refs.map(\.id)) == [1, 7])
}

@Test func aLiveStripReplacesTheArchivedOneOfTheSameSpace() {
    let archive = StripArchive(loading: SavedState(strips: [saved("A", "s1", [9])]), at: now)
    let state = archive.merged(into: SavedState(refs: [ref(1)], strips: [saved("A", "s1", [1])]), at: now)
    #expect(state.strips.map(\.strip.allWindows) == [[1]])
    #expect(state.refs.map(\.id) == [1])                                          // no ref for what is not saved
}

@Test func aWindowInALiveAndAnArchivedStripIsListedOnce() {
    // An unplugged display's windows join the strips of the display they are on, and its archived strip keeps
    // them too, to take them back when it returns.
    var archive = StripArchive()
    archive.store(saved("external", "s1", [4, 5], unplugged: true), at: now)
    let state = archive.merged(into: SavedState(refs: [ref(4), ref(1)], strips: [saved("laptop", "s9", [1, 4])]), at: now)
    #expect(state.strips.count == 2)
    #expect(state.refs.map(\.id).sorted() == [1, 4, 5])
    #expect(state.strips.last?.unplugged == true)
}

@Test func archivedStripsKeepTheirOwnWindows() throws {
    // Window ids are only unique within a login session: today a Mail window can have the id a Safari window had in
    // an archived strip from last week. The archived strip keeps its own refs, so it never takes the Mail window.
    let docs = WindowRef(id: 812, bundleID: "com.apple.Safari", title: "Docs")
    let inbox = WindowRef(id: 812, bundleID: "com.apple.mail", title: "Inbox")
    let old = SavedStrip(displayUUID: "D", spaceKey: "s5", strip: strip([812]), lastSeen: now - day, session: "last week",
                         refs: [docs])
    let archive = StripArchive(loading: SavedState(session: "last week", refs: [docs], strips: [old]), at: now)
    let live = SavedStrip(displayUUID: "L", spaceKey: "s1", strip: strip([812]), session: "today", refs: [inbox])
    let state = archive.merged(into: SavedState(session: "today", refs: [inbox], strips: [live]), at: now)
    #expect(state.strips.map(\.refs) == [[inbox], [docs]])

    let reloaded = try #require(StripArchive(loading: state, at: now).stack(displayUUID: "D", spaceKey: "s5").first)
    #expect(reloaded.refs == [docs])
    #expect(StateMatcher.match(saved: reloaded.refs, live: [inbox], session: reloaded.session, current: "today",
                               alive: [812]).isEmpty)
}

@Test func aStripFromBefore1_1_0KeepsTheWindowsItWasSavedWith() {
    // Saved again by 1.1.0 it still has no session, but it has its own refs by then: the shared list, where a newer
    // window may have one of its ids, must not replace them.
    let docs = WindowRef(id: 812, bundleID: "com.apple.Safari", title: "Docs")
    let inbox = WindowRef(id: 812, bundleID: "com.apple.mail", title: "Inbox")
    let old = SavedStrip(displayUUID: "D", spaceKey: "s5", strip: strip([812]), lastSeen: now, session: nil, refs: [docs])
    let file = SavedState(session: "today", refs: [inbox, docs], strips: [old])
    #expect(StripArchive(loading: file, at: now).stack(displayUUID: "D", spaceKey: "s5").first?.refs == [docs])
}

@Test func archivedStripsTooOldToComeBackAreDropped() {
    var archive = StripArchive()
    archive.store(saved("A", "old", [1]), at: now - StripArchive.maxAge - day)
    archive.store(saved("A", "recent", [2]), at: now - day)
    let state = archive.merged(into: SavedState(), at: now)
    #expect(state.strips.map(\.spaceKey) == ["recent"])
    #expect(state.refs.map(\.id) == [2])
}

@Test func aSavedStripSurvivesTheFile() throws {
    let strip = saved("A", "s1", [1], seen: now, session: "today", unplugged: true)
    let decoded = try JSONDecoder().decode(SavedStrip.self, from: JSONEncoder().encode(strip))
    #expect(decoded == strip)
    // Files written before 1.1.0 have no date, no session, no refs of their own and nothing unplugged.
    let body = try #require(String(data: JSONEncoder().encode(saved("A", "s1", [1]).strip), encoding: .utf8))
    let old = try JSONDecoder().decode(SavedStrip.self,
                                       from: Data(#"{"displayUUID":"A","spaceKey":"s1","strip":\#(body)}"#.utf8))
    #expect(old.lastSeen == nil && old.session == nil && old.refs.isEmpty && !old.unplugged)
    #expect(old.strip.allWindows == [1])
}

@Test func aDisplayThatComesBackUnderANewSpaceKeyGetsItsStrip() {
    // macOS can give an unplugged display's desktop a new key when it comes back.
    var archive = StripArchive(loading: SavedState(strips: [saved("external", "unvisited", [9])]), at: now)
    archive.store(saved("external", "old-key", [4, 5], unplugged: true), at: now)
    // While that desktop is still on the display, its own key will find it.
    #expect(archive.strayStack(displayUUID: "external", spaces: ["old-key", "unvisited"]).isEmpty)
    let stray = archive.strayStack(displayUUID: "external", spaces: ["new-key", "unvisited"])
    #expect(stray.map(\.strip.allWindows) == [[4, 5]])
    // Once the display had its chance, only exact keys find its strips, matched like any other.
    archive.settle(displayUUID: "external")
    #expect(archive.strayStack(displayUUID: "external", spaces: ["new-key"]).isEmpty)
    #expect(archive.stack(displayUUID: "external", spaceKey: "old-key").first?.unplugged == false)

    // With several desktops it cannot tell which one this is: only exact keys are restored.
    var several = StripArchive()
    several.store(saved("external", "s1", [1], unplugged: true), at: now)
    several.store(saved("external", "s2", [2], unplugged: true), at: now)
    #expect(several.strayStack(displayUUID: "external", spaces: ["new"]).isEmpty)
}

// MARK: - Stacked strips

// A display and Space can hold several strips, one per level, counted from the bottom (0). They are archived and saved
// side by side, and a stack comes back as a whole.

@Test func storeReplacesOnlyTheSameLevel() {
    var archive = StripArchive()
    archive.store(saved("A", "s1", [1]), at: now)                                  // level 0
    archive.store(saved("A", "s1", [2], level: 1), at: now)
    archive.store(saved("B", "s1", [5], level: 1), at: now)                        // another display
    archive.store(saved("A", "s2", [6], level: 1), at: now)                        // another Space
    #expect(archive.stack(displayUUID: "A", spaceKey: "s1").map(\.strip.allWindows) == [[1], [2]])

    // Storing a level again replaces that level alone.
    archive.store(saved("A", "s1", [3, 4], unplugged: true, level: 1), at: now)
    let stack = archive.stack(displayUUID: "A", spaceKey: "s1")
    #expect(stack.map(\.strip.allWindows) == [[1], [3, 4]])
    #expect(stack.map(\.unplugged) == [false, true])
    #expect(archive.stack(displayUUID: "B", spaceKey: "s1").map(\.strip.allWindows) == [[5]])
    #expect(archive.stack(displayUUID: "A", spaceKey: "s2").map(\.strip.allWindows) == [[6]])
    #expect(archive.strips.count == 4)
}

@Test func aStackListsOnlyItsOwnLevelsAndLeavesThemInTheArchive() {
    var archive = StripArchive()
    archive.store(saved("A", "s1", [3], level: 2), at: now)
    archive.store(saved("A", "s2", [9]), at: now)
    archive.store(saved("B", "s1", [8]), at: now)
    archive.store(saved("A", "s1", [1]), at: now)
    archive.store(saved("A", "s1", [2], level: 1), at: now)
    #expect(archive.stack(displayUUID: "A", spaceKey: "s1").map(\.level) == [0, 1, 2])   // by level, not as stored
    #expect(archive.stack(displayUUID: "A", spaceKey: "s3").isEmpty)
    #expect(archive.strips.count == 5)                                                   // looking takes nothing
}

@Test func takeStackReturnsEveryLevelInOrder() {
    var archive = StripArchive()
    archive.store(saved("A", "s1", [3], level: 2), at: now)
    archive.store(saved("A", "s2", [9]), at: now)                                  // another Space of the display
    archive.store(saved("B", "s1", [8]), at: now)                                  // the same Space key elsewhere
    archive.store(saved("A", "s1", [1]), at: now)
    archive.store(saved("A", "s1", [2], level: 1), at: now)

    let taken = archive.takeStack(displayUUID: "A", spaceKey: "s1")
    #expect(taken.map(\.level) == [0, 1, 2])
    #expect(taken.map(\.strip.allWindows) == [[1], [2], [3]])
    // Nothing of that stack stays, and nothing of any other.
    #expect(archive.stack(displayUUID: "A", spaceKey: "s1").isEmpty)
    #expect(archive.strips.map(\.strip.allWindows) == [[9], [8]])
    #expect(archive.takeStack(displayUUID: "A", spaceKey: "s1").isEmpty)
}

@Test func strayStackNeedsASingleArchivedSpace() {
    var archive = StripArchive(loading: SavedState(strips: [saved("external", "unvisited", [9])]), at: now)
    archive.store(saved("external", "old-key", [4], unplugged: true), at: now)
    archive.store(saved("external", "old-key", [5], unplugged: true, level: 1), at: now)
    archive.store(saved("laptop", "other-key", [7], unplugged: true), at: now)     // another display's

    // Both levels of the one unplugged Space; a Space archived for another reason does not count as a second one.
    let stray = archive.strayStack(displayUUID: "external", spaces: ["new-key", "unvisited"])
    #expect(stray.map(\.level) == [0, 1])
    #expect(stray.map(\.strip.allWindows) == [[4], [5]])
    #expect(archive.strips.count == 4)                                             // looking takes nothing

    // While that Space is still on the display, its own key will find it.
    #expect(archive.strayStack(displayUUID: "external", spaces: ["old-key", "new-key"]).isEmpty)

    // A second unplugged Space for the same display: only exact keys can tell them apart.
    archive.store(saved("external", "second-key", [6], unplugged: true), at: now)
    #expect(archive.strayStack(displayUUID: "external", spaces: ["new-key"]).isEmpty)
}

@Test func unpluggedLevelFindsTheWindow() {
    var archive = StripArchive()
    archive.store(saved("external", "s1", [6], session: "S", unplugged: true), at: now)
    archive.store(saved("external", "s1", [7], session: "S", unplugged: true, level: 1), at: now)
    #expect(archive.unpluggedLevel(of: 7, session: "S") == 1)
    #expect(archive.unpluggedLevel(of: 6, session: "S") == 0)
    #expect(archive.unpluggedLevel(of: 8, session: "S") == nil)                    // in no strip
    // Window ids name the same window only within the session they were saved in.
    #expect(archive.unpluggedLevel(of: 7, session: "T") == nil)

    // A strip that is not unplugged has no say: its display is not away.
    var settled = StripArchive()
    settled.store(saved("external", "s1", [7], session: "S", unplugged: false, level: 1), at: now)
    #expect(settled.unpluggedLevel(of: 7, session: "S") == nil)
}

@Test func unpluggedLevelFollowsTheStripSeenLast() {
    // A window joined the second display's strips when the first was unplugged, and the second was unplugged later:
    // both archived strips hold it, and the later one knows where it was last.
    let older = saved("first", "s1", [7], session: "S", unplugged: true, level: 1)
    let newer = saved("second", "s1", [7], session: "S", unplugged: true, level: 0)
    var archive = StripArchive()
    archive.store(older, at: now - day)
    archive.store(newer, at: now)
    #expect(archive.unpluggedLevel(of: 7, session: "S") == 0)
    // Whichever order they were stored in.
    var reversed = StripArchive()
    reversed.store(newer, at: now)
    reversed.store(older, at: now - day)
    #expect(reversed.unpluggedLevel(of: 7, session: "S") == 0)
}

@Test func theUnpluggedStripHoldingAWindowSaysWhereItWas() {
    // Its level and its display, from the strip seen last: the engine lets a window go back to that level once per
    // display that left.
    var archive = StripArchive()
    archive.store(saved("first", "s1", [7], session: "S", unplugged: true, level: 1), at: now - day)
    archive.store(saved("second", "s2", [7], session: "S", unplugged: true, level: 2), at: now)
    let holder = archive.unpluggedStrip(holding: 7, session: "S")
    #expect(holder?.displayUUID == "second")
    #expect(holder?.level == 2)
    #expect(archive.unpluggedLevel(of: 7, session: "S") == 2)
    #expect(archive.unpluggedStrip(holding: 7, session: "T") == nil)                // another session's ids
    #expect(archive.unpluggedStrip(holding: 8, session: "S") == nil)                // in no strip
}

@Test func mergedKeepsLevelsApart() {
    var archive = StripArchive()
    archive.store(saved("A", "s1", [9]), at: now)               // level 0: a live strip replaces it
    archive.store(saved("A", "s1", [8], level: 1), at: now)     // level 1: no live strip does
    let live = SavedState(session: "today", refs: [ref(1)], strips: [saved("A", "s1", [1])])
    let state = archive.merged(into: live, at: now)
    #expect(state.strips.map(\.level) == [0, 1])
    #expect(state.strips.map(\.strip.allWindows) == [[1], [8]])
    #expect(Set(state.refs.map(\.id)) == [1, 8])                                   // no ref for the replaced one
}

@Test func aSavedStackSurvivesTheFileLevelByLevel() throws {
    var archive = StripArchive()
    archive.store(saved("A", "s1", [1], activeLevel: 1), at: now)
    archive.store(saved("A", "s1", [2], level: 1, activeLevel: 1), at: now)
    let file = try JSONDecoder().decode(SavedState.self,
                                        from: JSONEncoder().encode(archive.merged(into: SavedState(), at: now)))
    let stack = StripArchive(loading: file, at: now).stack(displayUUID: "A", spaceKey: "s1")
    #expect(stack.map(\.level) == [0, 1])
    #expect(stack.map(\.activeLevel) == [1, 1])
    #expect(stack.map(\.strip.allWindows) == [[1], [2]])
}

// MARK: - Rebuilding a saved stack

// A stack comes back level by level from the bottom, each level with the windows that no level below took.

private func refs(_ titles: [WindowID: String]) -> [WindowRef] {
    titles.keys.sorted().map { WindowRef(id: $0, bundleID: "app", title: titles[$0]!) }
}

@Test func aSavedStackComesBackLevelByLevel() {
    let stack = [saved("A", "s1", [1, 2]), saved("A", "s1", [3], level: 1)]
    let levels = StateMatcher.restoredLevels(stack, free: [ref(3), ref(1), ref(2)], onScreen: [], returning: false,
                                             current: "today", alive: [1, 2, 3])
    #expect(levels.mapValues(\.allWindows) == [0: [1, 2], 1: [3]])
}

@Test func aWindowComesBackOnOneLevelOnly() {
    // Two levels name the same window, given in any order: the lower one takes it.
    let stack = [saved("A", "s1", [5, 6], level: 1), saved("A", "s1", [5])]
    let levels = StateMatcher.restoredLevels(stack, free: [ref(5), ref(6)], onScreen: [], returning: false,
                                             current: "today", alive: [5, 6])
    #expect(levels.mapValues(\.allWindows) == [0: [5], 1: [6]])

    // After a Mac restart only titles count: the one live window with a title of both levels goes to the lower one.
    let lower = SavedStrip(displayUUID: "A", spaceKey: "s1", strip: strip([1]), session: "yesterday",
                           refs: refs([1: "Notes"]))
    let upper = SavedStrip(displayUUID: "A", spaceKey: "s1", strip: strip([2]), session: "yesterday",
                           refs: refs([2: "Notes"]), level: 1)
    let restarted = StateMatcher.restoredLevels([upper, lower], free: refs([40: "Notes"]), onScreen: [],
                                                returning: false, current: "today", alive: [40])
    #expect(restarted.mapValues(\.allWindows) == [0: [40]])
}

@Test func aLevelWithNoneOfItsWindowsHereIsLeftOut() {
    let stack = [saved("A", "s1", [1]), saved("A", "s1", [2], level: 1), saved("A", "s1", [3], level: 2)]
    let levels = StateMatcher.restoredLevels(stack, free: [ref(1), ref(3)], onScreen: [], returning: false,
                                             current: "today", alive: [1, 3])
    #expect(levels.mapValues(\.allWindows) == [0: [1], 2: [3]])
}

@Test func aHandEditedStackStillComesBackAsLevels() {
    // A level below 0 is skipped, and so is a second strip of the same level.
    let stack = [saved("A", "s1", [1], level: -1), saved("A", "s1", [2]), saved("A", "s1", [3])]
    let levels = StateMatcher.restoredLevels(stack, free: [ref(1), ref(2), ref(3)], onScreen: [], returning: false,
                                             current: "today", alive: [1, 2, 3])
    #expect(levels.mapValues(\.allWindows) == [0: [2]])
}

@Test func unpluggedLevelsTakeTheirWindowsBackWhileTheirDisplayReturns() {
    // The windows joined the strips of the display they were moved to: only the levels archived when the display was
    // unplugged take them from there, and only while it is coming back.
    let stack = [saved("external", "s1", [1], unplugged: true), saved("external", "s1", [2], unplugged: true, level: 1),
                 saved("external", "s1", [3], level: 2)]
    let onScreen = [ref(1), ref(2), ref(3)]
    let back = StateMatcher.restoredLevels(stack, free: [], onScreen: onScreen, returning: true, current: "today",
                                           alive: [1, 2, 3])
    #expect(back.mapValues(\.allWindows) == [0: [1], 1: [2]])
    // Later, every level finds only the windows no other strip holds.
    let later = StateMatcher.restoredLevels(stack, free: [ref(2)], onScreen: onScreen, returning: false,
                                            current: "today", alive: [1, 2, 3])
    #expect(later.mapValues(\.allWindows) == [1: [2]])
}

@Test func takingBackByTitleNeedsATitleNoOtherWindowHas() {
    // After a Mac restart a level that takes its windows back recognises one only by a title that is the app's alone.
    let level = SavedStrip(displayUUID: "external", spaceKey: "s1", strip: strip([1]), session: "yesterday",
                           refs: refs([1: "Notes"]), unplugged: true, level: 1)
    let one = StateMatcher.restoredLevels([level], free: [], onScreen: refs([40: "Notes"]), returning: true,
                                          current: "today", alive: [40])
    #expect(one.mapValues(\.allWindows) == [1: [40]])
    let two = StateMatcher.restoredLevels([level], free: [], onScreen: refs([40: "Notes", 41: "Notes"]),
                                          returning: true, current: "today", alive: [40, 41])
    #expect(two.isEmpty)
}
