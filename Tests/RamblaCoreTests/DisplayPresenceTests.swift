import Testing
@testable import RamblaCore

@Test func aDisplayCountsOnlyOnceItStays() {
    var presence = DisplayPresence()
    presence.update(connected: ["A"], now: 100, atLaunch: true)
    presence.update(connected: ["A", "V"], now: 200)
    // There when Rambla started: settled at once.
    #expect(presence.isSettled("A", now: 200))
    #expect(presence.settles("A", now: 200) == nil)
    // Just appeared (macOS shows a virtual display for about a second while a closed-lid Mac wakes).
    #expect(!presence.isSettled("V", now: 201))
    #expect(presence.settles("V", now: 201) == 200 + DisplayPresence.settleDelay)
    #expect(presence.isSettled("V", now: 200 + DisplayPresence.settleDelay))
    #expect(!presence.isSettled("unknown", now: 500))
}

@Test func aDisplayThatLeavesStartsOverWhenItComesBack() {
    var presence = DisplayPresence()
    presence.update(connected: ["A"], now: 0, atLaunch: true)
    presence.update(connected: [], now: 10)
    presence.update(connected: ["A"], now: 20)
    #expect(!presence.isSettled("A", now: 21))
    #expect(presence.isSettled("A", now: 20 + DisplayPresence.settleDelay))
    // Seen again while it stays: the time it appeared does not move.
    presence.update(connected: ["A"], now: 22)
    #expect(presence.settles("A", now: 22) == 20 + DisplayPresence.settleDelay)
}
