import Testing
import Foundation
@testable import RamblaCore

// The overview lays the strip out as one row of cards in strip points (the view scales them to fit), with the pinned
// columns at their edges, and moves a selection through them.

private let gap = 10.0

/// Columns of one window each, ids 1, 2, 3…, with the given on-screen widths.
private func strip(_ widths: [Double], pinned: [Int: PinSide] = [:], focused: Int? = 0, scroll: Double = 0) -> Strip {
    var columns: [Column] = []
    for (index, width) in widths.enumerated() {
        var column = Column(windows: [WindowID(index + 1)], width: .points(width))
        column.pinned = pinned[index]
        columns.append(column)
    }
    return Strip(columns: columns, focused: focused, scroll: scroll)
}

/// What `Layout.metrics` reports for those columns: pinned and collapsed ones take no room in the scroll area.
private func metrics(_ strip: Strip, hidden: Set<WindowID> = [], area: Double) -> StripMetrics {
    var xs: [Double] = [], widths: [Double] = []
    var x = 0.0
    for (index, column) in strip.columns.enumerated() {
        xs.append(x)
        guard column.pinned == nil, !strip.isCollapsed(index, hidden: hidden), case .points(let w) = column.width else {
            widths.append(0)
            continue
        }
        widths.append(w)
        x += w + gap
    }
    return StripMetrics(xs: xs, widths: widths, total: max(0, x - gap), area: CGRect(x: 0, y: 0, width: area, height: 800))
}

private func overview(_ strip: Strip, hidden: Set<WindowID> = [], area: Double = 1000, pinnedWidths: [Int: Double] = [:],
                      focused: WindowID? = nil) -> Overview {
    var pins: [UUID: Double] = [:]
    for (index, width) in pinnedWidths { pins[strip.columns[index].id] = width }
    return Overview(strip: strip, metrics: metrics(strip, hidden: hidden, area: area), pinnedWidths: pins, gap: gap,
                    hidden: hidden, focused: focused)
}

@Test func cardsFollowTheStripWithThePinnedColumnsAtTheirEdges() {
    let s = strip([300, 500, 400, 200], pinned: [2: .left, 3: .right])
    let o = overview(s, pinnedWidths: [2: 400, 3: 200])
    #expect(o.cards.map(\.column) == [2, 0, 1, 3])
    #expect(o.cards.map(\.x) == [0, 410, 720, 1230])
    #expect(o.cards.map(\.width) == [400, 300, 500, 200])
    #expect(o.cards.map(\.pinned) == [.left, nil, nil, .right])
    #expect(o.total == 1430)
}

@Test func aColumnWithEveryWindowHiddenGetsASmallCard() {
    let s = strip([300, 500, 400])
    let o = overview(s, hidden: [2])
    #expect(o.cards.map(\.collapsed) == [false, true, false])
    #expect(o.cards[1].width == Overview.collapsedWidth)
    #expect(o.cards[2].x == 300 + gap + Overview.collapsedWidth + gap)
}

@Test func theViewportIsThePartOfTheStripOnScreen() {
    // Columns at 0…300, 310…810, 820…1220; the screen shows 1000 points from 150.
    let o = overview(strip([300, 500, 400], scroll: 150), area: 1000)
    #expect(o.viewport == 150...1150)
    // A pinned column is always on screen, and shifts the strip's cards to its right.
    let pinned = overview(strip([300, 500, 400], pinned: [0: .left], scroll: 0), area: 600, pinnedWidths: [0: 300])
    #expect(pinned.viewport == 310...910)
}

@Test func theSelectionStartsOnTheFocusedWindow() {
    var s = strip([300, 500, 400], focused: 1)
    s.columns[1].windows = [2, 7, 8]
    s.columns[1].heightWeights = [1, 1, 1]
    s.columns[1].active = 2
    let o = overview(s, focused: 7)
    #expect(o.selection == Overview.Selection(card: 1, row: 1))
    #expect(o.window(at: o.selection) == 7)
    // Without a focused window it falls on the focused column's active window.
    #expect(overview(s, focused: nil).selection == Overview.Selection(card: 1, row: 2))
}

@Test func arrowsMoveTheSelectionThroughCardsAndRows() {
    var s = strip([300, 500, 400], focused: 0)
    s.columns[1].windows = [2, 7]
    s.columns[1].heightWeights = [1, 1]
    s.columns[1].active = 1
    var o = overview(s, focused: 1)
    o.move(.left)
    #expect(o.selection == Overview.Selection(card: 0, row: 0))                   // stops at the first card
    o.move(.right)
    #expect(o.selection == Overview.Selection(card: 1, row: 1))                   // lands on the column's active window
    o.move(.up)
    #expect(o.window(at: o.selection) == 2)
    o.move(.up)
    #expect(o.window(at: o.selection) == 2)                                       // stops at the top
    o.move(.down)
    o.move(.down)
    #expect(o.window(at: o.selection) == 7)
    o.move(.right)
    o.move(.right)
    #expect(o.window(at: o.selection) == 3)                                       // stops at the last card
}

@Test func aNumberPicksThatCard() {
    let o = overview(strip([300, 500, 400, 200], pinned: [3: .left]), pinnedWidths: [3: 200])
    #expect(o.window(atCard: 1) == 4)                                             // the pinned column comes first
    #expect(o.window(atCard: 2) == 1)
    #expect(o.window(atCard: 9) == nil)
    #expect(o.window(atCard: 0) == nil)
}

@Test func numbersCountTheColumnsOnScreenLikeTheShortcuts() {
    // ⌃⌘2 skips a column whose windows are all minimized: the overview's 2 picks the same column.
    let s = strip([300, 500, 400])
    let o = overview(s, hidden: [2])
    var focused = s
    focused.focusNth(2, hidden: [2])
    #expect(o.window(atCard: 2) == 3)
    #expect(focused.focused == 2)
    #expect(o.window(atCard: 3) == nil)
}

@Test func hiddenWindowsOfAStackAreSkipped() {
    var s = strip([300, 500, 400], focused: 0)
    s.columns[1].windows = [2, 7, 8]
    s.columns[1].heightWeights = [1, 1, 1]
    s.columns[1].active = 1                                                       // the active one is minimized
    var o = overview(s, hidden: [7], focused: 1)
    o.move(.right)
    #expect(o.window(at: o.selection) == 2)                                       // entered on a window on screen
    o.move(.down)
    #expect(o.window(at: o.selection) == 8)                                       // over the minimized one
    o.move(.up)
    #expect(o.window(at: o.selection) == 2)
    #expect(o.window(atCard: 2) == 2)
}

@Test func aCollapsedCardIsSkippedByTheArrows() {
    var o = overview(strip([300, 500, 400]), hidden: [2], focused: 1)
    o.move(.right)
    #expect(o.window(at: o.selection) == 3)
}

@Test func theSelectionJumpsToTheEnds() {
    var o = overview(strip([300, 500, 400, 200]), hidden: [4], focused: 2)
    o.move(.last)
    #expect(o.window(at: o.selection) == 3)                                       // the last card on screen
    o.move(.first)
    #expect(o.window(at: o.selection) == 1)
}

// MARK: - Drawn

@Test func theViewportMarksTheCardsItCovers() {
    // Six columns of 740 points; the screen (1490 wide) shows the fourth and fifth exactly. Drawn at 0.3 the gaps
    // are 3 points, wider than that on screen: the bar must still start and end with those two cards.
    let o = overview(strip(Array(repeating: 740, count: 6), scroll: 3 * 750), area: 1490)
    #expect(o.viewport == 2250...3740)
    let drawn = o.drawn(scale: 0.3, minimumWidth: 44, minimumGap: 10)
    #expect(drawn.cards[3] == 696...918)
    #expect(drawn.cards[4] == 928...1150)
    #expect(drawn.viewport == 696...1150)
    #expect(drawn.width == 1382)
}

@Test func smallCardsAreDrawnWiderAndTheViewportFollowsThem() {
    // A collapsed card is 120 points: at 0.16 it would be 19 points wide, so it is drawn 44 wide. The screen shows
    // the second half of the first column and half of the third.
    // Cards at 0…400, 410…530 (collapsed) and 540…940; the third shows its first 200 points.
    let o = overview(strip([400, 300, 400], scroll: 200), hidden: [2], area: 410)
    #expect(o.viewport == 200.0...740.0)
    // Drawn: 64 wide, 44 wide (not 19), 64 wide, 10 apart.
    let drawn = o.drawn(scale: 0.16, minimumWidth: 44, minimumGap: 10)
    #expect(drawn.cards.map(\.lowerBound) == [0, 74, 128])
    #expect(drawn.viewport == 32.0...160.0)
}

// MARK: - Reordering

@Test func aColumnMovesAmongTheUnpinnedOnes() throws {
    // Columns A B C, D pinned left and E pinned right: the cards are D | A B C | E.
    let s = strip([300, 500, 400, 200, 250], pinned: [3: .left, 4: .right])
    let o = overview(s, pinnedWidths: [3: 200, 4: 250])
    #expect(o.cards.map(\.column) == [3, 0, 1, 2, 4])
    #expect(o.cards.map(\.id) == [3, 0, 1, 2, 4].map { s.columns[$0].id })
    #expect(o.movable == 1...3)
    // A to where C is: the strip moves column 0 to index 2.
    let move = try #require(o.columnMove(card: 1, to: 3))
    #expect(move.from == 0 && move.to == 2)
    var moved = s
    moved.moveColumn(from: move.from, to: move.to)
    #expect(moved.visualOrder(hidden: []).map { moved.columns[$0].windows[0] } == [4, 2, 3, 1, 5])
    // Pinned columns stay put, and a card dropped where it was moves nothing.
    #expect(o.columnMove(card: 0, to: 2) == nil)
    #expect(o.columnMove(card: 1, to: 4) == nil)
    #expect(o.columnMove(card: 2, to: 2) == nil)
}

@Test func aDraggedCardLandsWhereItsCenterIs() {
    // Cards at 0…300, 310…810 and 820…1220, drawn at scale 1.
    let o = overview(strip([300, 500, 400]))
    let drawn = o.drawn(scale: 1, minimumWidth: 44, minimumGap: 10)
    #expect(o.dropSlot(forCard: 0, center: 150, in: drawn) == 0)
    #expect(o.dropSlot(forCard: 0, center: 559, in: drawn) == 0)                // short of the second card's center
    #expect(o.dropSlot(forCard: 0, center: 561, in: drawn) == 1)
    #expect(o.dropSlot(forCard: 0, center: 1500, in: drawn) == 2)
    #expect(o.dropSlot(forCard: 2, center: -50, in: drawn) == 0)
    // Never past a pinned column, which itself does not move.
    let pinned = overview(strip([300, 500, 400], pinned: [0: .left]), pinnedWidths: [0: 300])
    let pinnedDrawn = pinned.drawn(scale: 1, minimumWidth: 44, minimumGap: 10)
    #expect(pinned.dropSlot(forCard: 2, center: -50, in: pinnedDrawn) == 1)
    #expect(pinned.dropSlot(forCard: 0, center: 1500, in: pinnedDrawn) == 0)
}
