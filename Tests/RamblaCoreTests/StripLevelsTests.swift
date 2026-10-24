import Testing
@testable import RamblaCore

@Test func upFromAnOccupiedTopOpensANewLevel() {
    #expect(StripLevels.target(from: 0, up: true, top: 0, occupied: [0]) == 1)
}

@Test func upFromAnEmptyTopGoesNowhere() {
    #expect(StripLevels.target(from: 1, up: true, top: 1, occupied: [0]) == nil)
    #expect(StripLevels.target(from: 0, up: true, top: 0, occupied: []) == nil)
}

@Test func upInsideTheStackReachesEmptyMiddleLevels() {
    #expect(StripLevels.target(from: 0, up: true, top: 2, occupied: [0, 2]) == 1)
}

@Test func downStopsAtZero() {
    #expect(StripLevels.target(from: 0, up: false, top: 1, occupied: [0, 1]) == nil)
    #expect(StripLevels.target(from: 2, up: false, top: 2, occupied: []) == 1)
}

@Test func emptyLevelsAboveEverythingAreDropped() {
    #expect(StripLevels.droppable(top: 2, occupied: [0], active: 0) == [1, 2])
    #expect(StripLevels.droppable(top: 2, occupied: [0], active: 2) == [])
    #expect(StripLevels.droppable(top: 2, occupied: [0], active: 1) == [2])
    #expect(StripLevels.droppable(top: 3, occupied: [0, 2], active: 0) == [3])
    #expect(StripLevels.droppable(top: 1, occupied: [], active: 0) == [1])
}

@Test func emptyLevelsBelowAnOccupiedOneStay() {
    #expect(StripLevels.droppable(top: 2, occupied: [2], active: 2) == [])
    #expect(StripLevels.droppable(top: 2, occupied: [2], active: 0) == [])
}

@Test func aStackOfOneLevelHasNothingToDrop() {
    // The state of everyone who never goes up: level 0 is the top, with or without windows, and is never dropped.
    #expect(StripLevels.droppable(top: 0, occupied: [0], active: 0) == [])
    #expect(StripLevels.droppable(top: 0, occupied: [], active: 0) == [])
}

@Test func restoredActiveClampsToTop() {
    #expect(StripLevels.restoredActive(nil, top: 2) == 0)
    #expect(StripLevels.restoredActive(1, top: 2) == 1)
    #expect(StripLevels.restoredActive(3, top: 1) == 1)
}

@Test func restoredActiveNeverGoesBelowZero() {
    // Only a hand-edited file can say so: the bottom level is the nearest one there is.
    #expect(StripLevels.restoredActive(-1, top: 2) == 0)
    #expect(StripLevels.restoredActive(-4, top: 0) == 0)
}

@Test func withTheNaturalDirectionGoingDownShowsTheStripAbove() {
    // The content follows the fingers (or the pointer): what is above comes down into view.
    #expect(StripLevels.stripAbove(fingersUp: false, natural: true))
    #expect(!StripLevels.stripAbove(fingersUp: true, natural: true))
}

@Test func withoutTheNaturalDirectionGoingUpShowsTheStripAbove() {
    #expect(StripLevels.stripAbove(fingersUp: true, natural: false))
    #expect(!StripLevels.stripAbove(fingersUp: false, natural: false))
}
