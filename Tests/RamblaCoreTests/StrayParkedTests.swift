import CoreGraphics
import Testing
@testable import RamblaCore

// The lid of the laptop beside the monitor closed: the windows of the monitor's strip parked on its right edge, past
// which nothing was. The lid opened: the laptop's display lay there again, and macOS filed one of them under its desktop.

private let laptop = StrayParked.Other(frame: CGRect(x: 1920, y: 49, width: 1512, height: 982), currentSpace: 6723)
private let parkedRight = CGRect(x: 1919, y: 38, width: 822, height: 951)

@Test func aWindowParkedWhereADisplayAppearedComesBack() {
    #expect(StrayParked.isStray(frame: parkedRight, spaces: [6723], own: 6, others: [laptop]))
}

@Test func aWindowTheUserTookToTheOtherDisplayStaysThere() {
    // Rambla had it on its own display: Mission Control took it to the laptop's desktop.
    let parkedLeft = CGRect(x: -821, y: 38, width: 822, height: 951)
    #expect(!StrayParked.isStray(frame: parkedLeft, spaces: [6723], own: 6, others: [laptop]))
    // Half over the other display is not more than half.
    let half = CGRect(x: 1509, y: 38, width: 822, height: 951)
    #expect(!StrayParked.isStray(frame: half, spaces: [6723], own: 6, others: [laptop]))
}

@Test func onlyTheDesktopTheOtherDisplayShowsCounts() {
    // Still on its own desktop, on another desktop of the laptop (not the one it shows), or on none known.
    #expect(!StrayParked.isStray(frame: parkedRight, spaces: [6, 6723], own: 6, others: [laptop]))
    #expect(!StrayParked.isStray(frame: parkedRight, spaces: [6800], own: 6, others: [laptop]))
    #expect(!StrayParked.isStray(frame: parkedRight, spaces: [], own: 6, others: [laptop]))
    let unknown = StrayParked.Other(frame: laptop.frame, currentSpace: nil)
    #expect(!StrayParked.isStray(frame: parkedRight, spaces: [6723], own: 6, others: [unknown]))
}
