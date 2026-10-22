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
                   session: String? = "today", unplugged: Bool = false) -> SavedStrip {
    SavedStrip(displayUUID: display, spaceKey: space, strip: strip(windows), lastSeen: seen, session: session,
               refs: windows.map { ref($0) }, unplugged: unplugged)
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
    #expect(archive.take(displayUUID: "A", spaceKey: "s2") == nil)
    #expect(archive.take(displayUUID: "A", spaceKey: "s1")?.strip.allWindows == [1])
    #expect(archive.take(displayUUID: "A", spaceKey: "s1") == nil)
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

    let reloaded = try #require(StripArchive(loading: state, at: now).strip(displayUUID: "D", spaceKey: "s5"))
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
    #expect(StripArchive(loading: file, at: now).strip(displayUUID: "D", spaceKey: "s5")?.refs == [docs])
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
    #expect(archive.strayStrip(displayUUID: "external", spaces: ["old-key", "unvisited"]) == nil)
    #expect(archive.strayStrip(displayUUID: "external", spaces: ["new-key", "unvisited"])?.strip.allWindows == [4, 5])
    // Once the display had its chance, only exact keys find its strips, matched like any other.
    archive.settle(displayUUID: "external")
    #expect(archive.strayStrip(displayUUID: "external", spaces: ["new-key"]) == nil)
    #expect(archive.strip(displayUUID: "external", spaceKey: "old-key")?.unplugged == false)

    // With several desktops it cannot tell which one this is: only exact keys are restored.
    var several = StripArchive()
    several.store(saved("external", "s1", [1], unplugged: true), at: now)
    several.store(saved("external", "s2", [2], unplugged: true), at: now)
    #expect(several.strayStrip(displayUUID: "external", spaces: ["new"]) == nil)
}
