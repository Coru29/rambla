import Testing
import Foundation
@testable import RamblaCore

// The overview of a stack of strips shows one row per strip, the highest first, and the keyboard's selection moves
// across them: up and down go through a card's stack first, then to the nearest card of the row above or below.

private let gap = 10.0

/// One-window columns with the given widths, their windows numbered from `first`.
private func strip(_ widths: [Double], first: WindowID, focused: Int? = 0) -> Strip {
    let columns = widths.indices.map { Column(windows: [first + WindowID($0)], width: .points(widths[$0])) }
    return Strip(columns: columns, focused: columns.isEmpty ? nil : focused)
}

/// The overview of `strip` laid out the way `Layout.metrics` does on a screen wide enough for all of it: the columns
/// side by side, `gap` apart, the pinned and collapsed ones taking no room (`pinnedWidths`: the pinned ones' widths).
private func overview(_ strip: Strip, hidden: Set<WindowID> = [], pinnedWidths: [Int: Double] = [:],
                      focused: WindowID? = nil) -> Overview {
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
    let metrics = StripMetrics(xs: xs, widths: widths, total: max(0, x - gap),
                               area: CGRect(x: 0, y: 0, width: 5000, height: 800))
    var pins: [UUID: Double] = [:]
    for (index, width) in pinnedWidths { pins[strip.columns[index].id] = width }
    return Overview(strip: strip, metrics: metrics, pinnedWidths: pins, gap: gap, hidden: hidden, focused: focused)
}

private func row(_ level: Int, _ overview: Overview) -> OverviewStack.Row {
    OverviewStack.Row(level: level, overview: overview)
}

/// Every row drawn at scale 1: a card as wide as its column, `gap` from the next.
private func drawn(_ stack: OverviewStack) -> [Overview.Drawn] {
    stack.rows.map { $0.overview.drawn(scale: 1, minimumWidth: 1, minimumGap: gap) }
}

/// A stack of `windows` in one column of `strip`.
private func stacking(_ windows: [WindowID], in column: Int, of strip: Strip, tabbed: Bool = false, active: Int = 0) -> Strip {
    var strip = strip
    strip.columns[column].windows = windows
    strip.columns[column].heightWeights = windows.map { _ in 1 }
    strip.columns[column].mode = tabbed ? .tabbed : .stacked
    strip.columns[column].active = active
    return strip
}

// MARK: - Where the selection starts

@Test func selectionStartsOnTheActiveRow() {
    // Level 1 above, with windows 11 and 12 (its strip focuses the second); level 0 below, with 1, 2 and 3.
    let above = row(1, overview(strip([300, 300], first: 11, focused: 1)))
    let below = row(0, overview(strip([200, 400, 300], first: 1, focused: 2)))
    let stack = OverviewStack(rows: [above, below], activeLevel: 0)
    #expect(stack.selectedRow == 1)
    #expect(stack.selectedWindow == 3)
    // With the level above in view, its row's own selection: the column its strip focuses.
    let fromAbove = OverviewStack(rows: [above, below], activeLevel: 1)
    #expect(fromAbove.selectedRow == 0)
    #expect(fromAbove.selectedWindow == 12)
}

@Test func selectionOfAnEmptyActiveRowGoesToTheNearestRowWithCards() {
    let empty = overview(Strip())
    let bottom = overview(strip([300, 300], first: 1, focused: 1))
    // A new empty strip in view above the one with windows.
    let up = OverviewStack(rows: [row(1, empty), row(0, bottom)], activeLevel: 1)
    #expect(up.selectedRow == 1)
    #expect(up.selectedWindow == 2)
    // One level up is nearer than two down.
    let near = OverviewStack(rows: [row(3, overview(strip([300], first: 31))), row(2, empty), row(1, empty), row(0, bottom)],
                             activeLevel: 2)
    #expect(near.selectedRow == 0)
    #expect(near.selectedWindow == 31)
    // As near either way: the one below, the way back from an empty strip.
    let between = OverviewStack(rows: [row(2, overview(strip([300], first: 21))), row(1, empty), row(0, bottom)],
                                activeLevel: 1)
    #expect(between.selectedRow == 2)
    #expect(between.selectedWindow == 2)
}

@Test func aFallbackRowStartsOnACardThatCanBeChosen() {
    // The strip in view is empty, and the one above focuses a column whose only window's app is hidden: the selection
    // starts on that row's first card that can be chosen, not on the hidden one.
    let above = overview(strip([300, 300, 300], first: 11, focused: 0), hidden: [11])
    #expect(above.cards[above.selection.card].collapsed)
    let stack = OverviewStack(rows: [row(1, above), row(0, overview(Strip()))], activeLevel: 0)
    #expect(stack.selectedRow == 0)
    #expect(stack.selectedWindow == 12)
}

@Test func aRowWhoseWindowsAreAllHiddenHasNothingToChoose() {
    // Level 0 in view has only a minimized window: the selection goes to the level above, which has one on screen.
    let stack = OverviewStack(rows: [row(1, overview(strip([300], first: 11))), row(0, overview(strip([300], first: 1), hidden: [1]))],
                              activeLevel: 0)
    #expect(stack.selectedRow == 0)
    #expect(stack.selectedWindow == 11)
    // With no window on screen anywhere it stays where it is, as the overview of one strip does.
    let nothing = OverviewStack(rows: [row(1, overview(Strip())), row(0, overview(strip([300], first: 1), hidden: [1]))],
                                activeLevel: 0)
    #expect(nothing.selectedRow == 1)
}

// MARK: - Arrows

@Test func upFromTheTopWindowGoesToTheNearestCardAbove() {
    // Each row is centered on the screen. Above, cards at 0…300 and 310…610: their centers 155 left and 155 right of
    // the middle. Below, 0…200, 210…610 and 620…920: 360 left, 50 left and 310 right.
    let above = row(1, overview(strip([300, 300], first: 11)))
    let below = row(0, overview(strip([200, 400, 300], first: 1, focused: 2)))
    var fromRight = OverviewStack(rows: [above, below], activeLevel: 0)
    fromRight.move(.up, drawn: drawn(fromRight))
    #expect(fromRight.selectedRow == 0)
    #expect(fromRight.selectedWindow == 12)
    // From 50 left of the middle, 155 left is nearer than 155 right (though not in the rows' own coordinates).
    var fromMiddle = OverviewStack(rows: [above, below], activeLevel: 0)
    fromMiddle.select(row: 1, Overview.Selection(card: 1, row: 0))
    fromMiddle.move(.up, drawn: drawn(fromMiddle))
    #expect(fromMiddle.selectedRow == 0)
    #expect(fromMiddle.selectedWindow == 11)
}

@Test func downFromTheBottomWindowGoesToTheRowBelow() {
    // Above, one column holding a stack of windows 11 and 15.
    let above = row(1, overview(stacking([11, 15], in: 0, of: strip([300], first: 11))))
    let below = row(0, overview(strip([200, 400, 300], first: 1)))
    var stack = OverviewStack(rows: [above, below], activeLevel: 1)
    #expect(stack.selectedWindow == 11)
    stack.move(.down, drawn: drawn(stack))
    #expect(stack.selectedRow == 0)
    #expect(stack.selectedWindow == 15)                                           // through the stack first
    stack.move(.down, drawn: drawn(stack))
    #expect(stack.selectedRow == 1)
    #expect(stack.selectedWindow == 2)                                            // the card below its middle
    stack.move(.down, drawn: drawn(stack))
    #expect(stack.selectedRow == 1)
    #expect(stack.selectedWindow == 2)                                            // nothing below the bottom row
}

@Test func upInsideAStackStaysInTheCard() {
    // Below, the second column holds windows 2 and 7, and 7 has the focus.
    let bottom = stacking([2, 7], in: 1, of: strip([200, 400], first: 1, focused: 1), active: 1)
    var stack = OverviewStack(rows: [row(1, overview(strip([300], first: 11))), row(0, overview(bottom, focused: 7))],
                              activeLevel: 0)
    #expect(stack.selectedWindow == 7)
    stack.move(.up, drawn: drawn(stack))
    #expect(stack.selectedRow == 1)
    #expect(stack.selectedWindow == 2)
    stack.move(.up, drawn: drawn(stack))
    #expect(stack.selectedRow == 0)
    #expect(stack.selectedWindow == 11)
}

@Test func upAtTheTopRowStays() {
    var stack = OverviewStack(rows: [row(1, overview(strip([300, 300], first: 11))), row(0, overview(strip([300], first: 1)))],
                              activeLevel: 1)
    let before = stack
    stack.move(.up, drawn: drawn(stack))
    #expect(stack == before)
}

@Test func leftAndRightStayInTheRow() {
    // The row above is longer: the arrows still stop at the ends of the selected row.
    let above = row(1, overview(strip([300, 300, 300], first: 11)))
    let below = row(0, overview(strip([300, 300], first: 1, focused: 1)))
    var stack = OverviewStack(rows: [above, below], activeLevel: 0)
    stack.move(.right, drawn: drawn(stack))
    #expect(stack.selectedRow == 1)
    #expect(stack.selectedWindow == 2)
    stack.move(.left, drawn: drawn(stack))
    stack.move(.left, drawn: drawn(stack))
    #expect(stack.selectedRow == 1)
    #expect(stack.selectedWindow == 1)
    stack.move(.last, drawn: drawn(stack))
    #expect(stack.selectedRow == 1)
    #expect(stack.selectedWindow == 2)
    stack.move(.first, drawn: drawn(stack))
    #expect(stack.selectedRow == 1)
    #expect(stack.selectedWindow == 1)
}

@Test func rowsWithoutCardsAreSkipped() {
    // Level 1 is empty and the only window of level 2 is minimized: up from level 0 reaches level 3, and back.
    let rows = [row(3, overview(strip([300], first: 31))), row(2, overview(strip([300], first: 21), hidden: [21])),
                row(1, overview(Strip())), row(0, overview(strip([300], first: 1)))]
    var stack = OverviewStack(rows: rows, activeLevel: 0)
    stack.move(.up, drawn: drawn(stack))
    #expect(stack.selectedRow == 0)
    #expect(stack.selectedWindow == 31)
    stack.move(.down, drawn: drawn(stack))
    #expect(stack.selectedRow == 3)
    #expect(stack.selectedWindow == 1)
}

@Test func aStackIsEnteredOnTheWindowNearestTheRowItIsReachedFrom() {
    // The middle level holds a stack of 21, 22 and 23 (23 minimized) and tabs 24 and 25 that show 25.
    var middle = stacking([21, 22, 23], in: 0, of: strip([300, 300], first: 21))
    middle = stacking([24, 25], in: 1, of: middle, tabbed: true, active: 1)
    let rows = [row(2, overview(strip([300, 300], first: 31))), row(1, overview(middle, hidden: [23])),
                row(0, overview(strip([300, 300], first: 1)))]
    var fromBelow = OverviewStack(rows: rows, activeLevel: 0)
    fromBelow.move(.up, drawn: drawn(fromBelow))
    #expect(fromBelow.selectedWindow == 22)                                       // the lowest window on screen
    var fromAbove = OverviewStack(rows: rows, activeLevel: 2)
    fromAbove.move(.down, drawn: drawn(fromAbove))
    #expect(fromAbove.selectedWindow == 21)                                       // the highest
    // Tabs share one miniature: they are entered on the tab they show.
    var tabs = OverviewStack(rows: rows, activeLevel: 0)
    tabs.move(.right, drawn: drawn(tabs))
    tabs.move(.up, drawn: drawn(tabs))
    #expect(tabs.selectedWindow == 25)
}

// MARK: - A row at a time, and choosing

@Test func aRowStepGoesStraightToTheNextRow() {
    // A short swipe over the overview: from the bottom window of a stack to the row above, past the stack's top window.
    let bottom = stacking([1, 2], in: 0, of: strip([300], first: 1), active: 1)
    var stack = OverviewStack(rows: [row(1, overview(strip([300], first: 11))), row(0, overview(bottom, focused: 2))],
                              activeLevel: 0)
    #expect(stack.row(toward: true) == 0)
    #expect(stack.row(toward: false) == nil)
    let up = stack.moveRow(up: true, drawn: drawn(stack))
    #expect(up)
    #expect(stack.selectedRow == 0)
    #expect(stack.selectedWindow == 11)
    // Nothing above the top row.
    #expect(stack.row(toward: true) == nil)
    let top = stack
    let past = stack.moveRow(up: true, drawn: drawn(stack))
    #expect(!past)
    #expect(stack == top)
    // Back down, the stack is entered from above.
    let down = stack.moveRow(up: false, drawn: drawn(stack))
    #expect(down)
    #expect(stack.selectedRow == 1)
    #expect(stack.selectedWindow == 1)
}

@Test func aWindowOfAnotherRowCanBeChosen() {
    var stack = OverviewStack(rows: [row(1, overview(strip([300, 300], first: 11))), row(0, overview(strip([300], first: 1)))],
                              activeLevel: 0)
    stack.select(row: 0, Overview.Selection(card: 1, row: 0))
    #expect(stack.selectedRow == 0)
    #expect(stack.selectedWindow == 12)
    // Where there is no window, nothing changes.
    stack.select(row: 1, Overview.Selection(card: 3, row: 0))
    stack.select(row: 5, Overview.Selection(card: 0, row: 0))
    #expect(stack.selectedRow == 0)
    #expect(stack.selectedWindow == 12)
}

// MARK: - A new strip

@Test func theOnlyColumnOfTheTopStripMakesNoNewStrip() {
    // Moving it up would only leave an empty strip below.
    let bottom = row(0, overview(strip([300, 300], first: 1)))
    let stack = OverviewStack(rows: [row(1, overview(strip([300], first: 11))), bottom], activeLevel: 0)
    #expect(!stack.offersNewStrip(movingFrom: 0))
    #expect(stack.offersNewStrip(movingFrom: 1))
    // With two columns on top, either one can go up.
    let two = OverviewStack(rows: [row(1, overview(strip([300, 300], first: 11))), bottom], activeLevel: 0)
    #expect(two.offersNewStrip(movingFrom: 0))
    // A strip alone with one window has nothing to make a new strip from.
    let alone = OverviewStack(rows: [row(0, overview(strip([300], first: 1)))], activeLevel: 0)
    #expect(!alone.offersNewStrip(movingFrom: 0))
}

@Test func anEmptyTopStripTakesTheCardInsteadOfANewOne() {
    let stack = OverviewStack(rows: [row(1, overview(Strip())), row(0, overview(strip([300, 300], first: 1)))],
                              activeLevel: 1)
    #expect(!stack.offersNewStrip(movingFrom: 1))
}

// MARK: - A card dropped on another row

@Test func aCardFromAnotherRowLandsAmongTheUnpinnedColumns() {
    // Columns B, A (pinned left), C and D (pinned right): the cards read A | B C | D, and the strip's array keeps A
    // between B and C. Cards at 0…200 (A), 210…510 (B), 520…820 (C) and 830…1080 (D).
    var s = strip([300, 200, 300, 250], first: 1)
    s.columns[1].pinned = .left
    s.columns[3].pinned = .right
    let o = overview(s, pinnedWidths: [1: 200, 3: 250])
    #expect(o.cards.map(\.column) == [1, 0, 2, 3])
    let d = o.drawn(scale: 1, minimumWidth: 1, minimumGap: gap)
    #expect(o.insertionSlot(center: 100, in: d) == 1)                              // never before the left pin
    #expect(o.insertionSlot(center: 359, in: d) == 1)                              // short of B's center
    #expect(o.insertionSlot(center: 361, in: d) == 2)
    #expect(o.insertionSlot(center: 2000, in: d) == 3)                             // never after the right pin
    // In the strip's array: before B, before C, after C. The column is then drawn at that place.
    let places: [(slot: Int, order: [WindowID])] = [(1, [2, 9, 1, 3, 4]), (2, [2, 1, 9, 3, 4]), (3, [2, 1, 3, 9, 4])]
    for (slot, order) in places {
        var moved = s
        moved.columns.insert(Column(windows: [9], width: .points(100)), at: o.columnIndex(insertingAt: slot))
        #expect(moved.visualOrder(hidden: []).map { moved.columns[$0].windows[0] } == order)
    }
}

@Test func aRowWithoutUnpinnedColumnsTakesTheCardBetweenItsPins() {
    let empty = overview(Strip())
    #expect(empty.insertionSlot(center: 500, in: empty.drawn(scale: 1, minimumWidth: 1, minimumGap: gap)) == 0)
    #expect(empty.columnIndex(insertingAt: 0) == 0)
    // Window 1 pinned right comes first in the array, window 2 pinned left second: the cards read 2 | 1.
    var s = strip([200, 250], first: 1)
    s.columns[0].pinned = .right
    s.columns[1].pinned = .left
    let o = overview(s, pinnedWidths: [0: 200, 1: 250])
    let d = o.drawn(scale: 1, minimumWidth: 1, minimumGap: gap)
    #expect(o.insertionSlot(center: 0, in: d) == 1)
    #expect(o.insertionSlot(center: 5000, in: d) == 1)
    var moved = s
    moved.columns.insert(Column(windows: [9], width: .points(100)), at: o.columnIndex(insertingAt: 1))
    #expect(moved.visualOrder(hidden: []).map { moved.columns[$0].windows[0] } == [2, 9, 1])
}
