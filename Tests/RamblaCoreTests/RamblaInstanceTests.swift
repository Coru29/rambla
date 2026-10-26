import Testing
@testable import RamblaCore

@Test func aRamblaYieldsOnlyToOneThatStartedBeforeIt() {
    let running = RamblaInstance(pid: 500, start: 100)
    let second = RamblaInstance(pid: 700, start: 200)
    #expect(running.startedBefore(second))
    #expect(!second.startedBefore(running))
    // The process ids wrapped around since the first one started: it is still the one that stays.
    let wrapped = RamblaInstance(pid: 300, start: 200)
    #expect(running.startedBefore(wrapped))
    #expect(!wrapped.startedBefore(running))
}

@Test func ofTwoRamblasStartedTogetherExactlyOneStays() {
    let a = RamblaInstance(pid: 500, start: 100.000001)
    let b = RamblaInstance(pid: 501, start: 100.000002)
    #expect(a.startedBefore(b) != b.startedBefore(a))
    // In the same microsecond, the lower process id.
    let twin = RamblaInstance(pid: 499, start: a.start)
    #expect(twin.startedBefore(a))
    #expect(!a.startedBefore(twin))
    // None yields to itself.
    #expect(!a.startedBefore(a))
}
