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
}

@Test func aCollapsedCardIsSkippedByTheArrows() {
    var o = overview(strip([300, 500, 400]), hidden: [2], focused: 1)
    o.move(.right)
    #expect(o.window(at: o.selection) == 3)
}
