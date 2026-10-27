import CoreGraphics
import Testing
@testable import RamblaCore

// VS Code reported a window parked at the left edge, where Rambla had put it a moment before, after Rambla had already
// asked for it back in view: Rambla took that for another app's move and took the window out of its strip.

private let parked = CGRect(x: -821, y: 38, width: 822, height: 951)
private let inView = CGRect(x: 1454, y: 38, width: 822, height: 951)

@Test func aFrameAskedForAMomentAgoIsRamblasOwn() {
    var echoes = FrameEchoes()
    echoes.asked(parked, of: 7, at: 100)
    echoes.asked(inView, of: 7, at: 100.4)
    #expect(echoes.isOwn(parked, of: 7, at: 101))
    #expect(echoes.isOwn(inView, of: 7, at: 101))
    // Within a couple of points: apps round frames.
    #expect(echoes.isOwn(parked.offsetBy(dx: 1.5, dy: -1), of: 7, at: 101))
}

@Test func aFrameNeverAskedForIsAnotherAppsMove() {
    var echoes = FrameEchoes()
    echoes.asked(parked, of: 7, at: 100)
    #expect(!echoes.isOwn(CGRect(x: 200, y: 150, width: 700, height: 500), of: 7, at: 100.5))
    #expect(!echoes.isOwn(parked.offsetBy(dx: 3, dy: 0), of: 7, at: 100.5))
    // Asked of another window.
    #expect(!echoes.isOwn(parked, of: 8, at: 100.5))
}

@Test func aFrameAskedForLongAgoIsNotAnEcho() {
    var echoes = FrameEchoes()
    echoes.asked(parked, of: 7, at: 100)
    #expect(echoes.isOwn(parked, of: 7, at: 100 + FrameEchoes.window))
    #expect(!echoes.isOwn(parked, of: 7, at: 100 + FrameEchoes.window + 0.1))
    // Older frames go as new ones come; the last time anything was asked stays.
    echoes.asked(inView, of: 7, at: 200)
    #expect(!echoes.isOwn(parked, of: 7, at: 200))
    #expect(echoes.lastAsked(7) == 200)
}

@Test func aClosedWindowIsForgotten() {
    var echoes = FrameEchoes()
    echoes.asked(parked, of: 7, at: 100)
    echoes.forget(7)
    #expect(!echoes.isOwn(parked, of: 7, at: 100))
    #expect(echoes.lastAsked(7) == nil)
}
