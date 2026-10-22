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

private func saved(_ display: String, _ space: String, _ windows: [WindowID], seen: Date? = nil) -> SavedStrip {
    SavedStrip(displayUUID: display, spaceKey: space, strip: strip(windows), lastSeen: seen)
}

private func ref(_ id: WindowID, _ app: String = "app") -> WindowRef {
    WindowRef(id: id, bundleID: app, title: "window \(id)")
}

@Test func theArchiveStartsWithEverySavedStrip() {
    let file = SavedState(refs: [ref(1), ref(2), ref(3)], strips: [saved("A", "s1", [1, 2]), saved("B", "s2", [3])])
    let archive = StripArchive(loading: file, at: now)
    #expect(archive.strips.count == 2)
    #expect(archive.strips.allSatisfy { $0.lastSeen == now })                      // older files have no date
    #expect(archive.refs[3] == ref(3))
}

@Test func takingAStripRemovesItFromTheArchive() {
    var archive = StripArchive(loading: SavedState(refs: [ref(1)], strips: [saved("A", "s1", [1])]), at: now)
    #expect(archive.take(displayUUID: "A", spaceKey: "s2") == nil)
    #expect(archive.take(displayUUID: "A", spaceKey: "s1")?.strip.allWindows == [1])
    #expect(archive.take(displayUUID: "A", spaceKey: "s1") == nil)
    #expect(archive.strips.isEmpty)
}

@Test func storingAStripReplacesTheOneOfTheSameSpace() {
    var archive = StripArchive()
    archive.store(saved("A", "s1", [1]), refs: [ref(1)], at: now)
    archive.store(saved("A", "s1", [2, 3]), refs: [ref(2), ref(3)], at: now)
    #expect(archive.strips.map(\.strip.allWindows) == [[2, 3]])
    #expect(archive.strips.first?.lastSeen == now)
    #expect(archive.isFromThisSession(displayUUID: "A", spaceKey: "s1"))
    #expect(!StripArchive(loading: SavedState(strips: [saved("A", "s1", [1])]), at: now)
        .isFromThisSession(displayUUID: "A", spaceKey: "s1"))
}

@Test func savingKeepsTheArchivedStripsOfSpacesNotInView() {
    // Two restarts without visiting a Space used to lose its strip: the second save no longer knew it.
    let archive = StripArchive(loading: SavedState(refs: [ref(7)], strips: [saved("A", "unvisited", [7], seen: now - day)]),
                               at: now)
    let live = SavedState(refs: [ref(1)], strips: [saved("A", "current", [1])], floating: [])
    let state = archive.merged(into: live, at: now)
    #expect(state.strips.map(\.spaceKey) == ["current", "unvisited"])
    #expect(state.strips.first?.lastSeen == now)                                   // the live one was seen now
    #expect(state.strips.last?.lastSeen == now - day)                              // the archived one keeps its date
    #expect(Set(state.refs.map(\.id)) == [1, 7])
}

@Test func aLiveStripReplacesTheArchivedOneOfTheSameSpace() {
    let archive = StripArchive(loading: SavedState(refs: [ref(9)], strips: [saved("A", "s1", [9])]), at: now)
    let state = archive.merged(into: SavedState(refs: [ref(1)], strips: [saved("A", "s1", [1])]), at: now)
    #expect(state.strips.map(\.strip.allWindows) == [[1]])
    #expect(state.refs.map(\.id) == [1])                                          // no ref for what is not saved
}

@Test func aWindowInALiveAndAnArchivedStripIsSavedOnce() {
    // An unplugged display's windows join the strips of the display they are on, and its archived strip keeps
    // them too, to take them back when it returns.
    var archive = StripArchive()
    archive.store(saved("external", "s1", [4, 5]), refs: [ref(4), ref(5)], at: now)
    let state = archive.merged(into: SavedState(refs: [ref(4), ref(1)], strips: [saved("laptop", "s9", [1, 4])]), at: now)
    #expect(state.strips.count == 2)
    #expect(state.refs.map(\.id).sorted() == [1, 4, 5])
}

@Test func archivedStripsTooOldToComeBackAreDropped() {
    var archive = StripArchive()
    archive.store(saved("A", "old", [1]), refs: [ref(1)], at: now - StripArchive.maxAge - day)
    archive.store(saved("A", "recent", [2]), refs: [ref(2)], at: now - day)
    let state = archive.merged(into: SavedState(), at: now)
    #expect(state.strips.map(\.spaceKey) == ["recent"])
    #expect(state.refs.map(\.id) == [2])
}

@Test func theSavedDateSurvivesTheFile() throws {
    let strip = saved("A", "s1", [1], seen: now)
    let decoded = try JSONDecoder().decode(SavedStrip.self, from: JSONEncoder().encode(strip))
    #expect(decoded == strip)
    // Files written before 1.0.1 have no date.
    let old = try JSONDecoder().decode(SavedStrip.self, from: JSONEncoder().encode(saved("A", "s1", [1])))
    #expect(old.lastSeen == nil)
}

@Test func aDisplayThatComesBackUnderANewSpaceKeyGetsItsOnlyStrip() {
    // macOS can give an unplugged display's desktop a new key when it comes back.
    var archive = StripArchive(loading: SavedState(strips: [saved("external", "from-the-file", [9])]), at: now)
    archive.store(saved("external", "old-key", [4, 5]), refs: [ref(4), ref(5)], at: now)
    let only = archive.onlyCurrentStrip(displayUUID: "external")
    #expect(only?.strip.allWindows == [4, 5])
    #expect(archive.take(displayUUID: "external", spaceKey: only?.spaceKey ?? "") != nil)
    #expect(archive.onlyCurrentStrip(displayUUID: "external") == nil)            // only this session's strips count
    #expect(archive.strip(displayUUID: "external", spaceKey: "from-the-file") != nil)

    // With several desktops it cannot tell which one this is: only exact keys are restored.
    var several = StripArchive()
    several.store(saved("external", "s1", [1]), refs: [], at: now)
    several.store(saved("external", "s2", [2]), refs: [], at: now)
    #expect(several.onlyCurrentStrip(displayUUID: "external") == nil)
}
