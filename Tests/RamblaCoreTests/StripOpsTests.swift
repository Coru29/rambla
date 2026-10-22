import Testing
import Foundation
@testable import RamblaCore

@Suite struct StripOpsTests {
    // MARK: helpers

    /// One column per inner array, each `.fraction(0.5)` wide. `pinned` maps a column index to its pin side.
    func strip(_ cols: [[WindowID]], focused: Int?, pinned: [Int: PinSide] = [:]) -> Strip {
        var columns = cols.map { Column(windows: $0, width: .fraction(0.5)) }
        for (index, side) in pinned { columns[index].pinned = side }
        return Strip(columns: columns, focused: focused)
    }

    /// `columns.map(\.windows)`, the shape the assertions are written in.
    func shape(_ s: Strip) -> [[WindowID]] { s.columns.map(\.windows) }

    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    static let presets: [Double] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75]

    // MARK: accessors

    @Test func focusedColumnAndWindow() {
        var s = strip([[1, 2], [3]], focused: 0)
        s.columns[0].active = 1
        #expect(s.focusedColumn?.windows == [1, 2])
        #expect(s.focusedWindow == 2)
        s.focused = 1
        #expect(s.focusedColumn?.windows == [3])
        #expect(s.focusedWindow == 3)
        s.focused = nil
        #expect(s.focusedColumn == nil)
        #expect(s.focusedWindow == nil)
        s.focused = 7   // stale index
        #expect(s.focusedColumn == nil)
        #expect(s.focusedWindow == nil)
    }

    @Test func allWindowsFollowsColumnOrder() {
        #expect(strip([[1, 2], [3], [4, 5]], focused: 0).allWindows == [1, 2, 3, 4, 5])
        #expect(Strip().allWindows.isEmpty)
    }

    @Test func locateWindows() {
        let s = strip([[1, 2], [3]], focused: 0)
        #expect(s.location(of: 2)?.column == 0)
        #expect(s.location(of: 2)?.row == 1)
        #expect(s.location(of: 3)?.column == 1)
        #expect(s.location(of: 3)?.row == 0)
        #expect(s.location(of: 9) == nil)
        #expect(s.contains(3))
        #expect(!s.contains(9))
        #expect(s.index(ofColumn: s.columns[1].id) == 1)
        #expect(s.index(ofColumn: UUID()) == nil)
    }

    @Test func visualOrderWithPins() {
        let s = strip([[1], [2], [3]], focused: 1, pinned: [0: .right, 2: .left])
        #expect(s.visualOrder(hidden: []) == [2, 1, 0])
    }

    // MARK: insert

    @Test func insertAfterFocused() {
        var s = strip([[1], [2]], focused: 0)
        s.insert(window: 3, width: .fraction(0.5), at: .afterFocused)
        #expect(shape(s) == [[1], [3], [2]])
        #expect(s.focused == 1)

        s = strip([[1], [2]], focused: 0)
        s.insert(window: 3, width: .fraction(0.5), at: .start)
        #expect(shape(s) == [[3], [1], [2]])
        #expect(s.focused == 0)

        s = strip([[1], [2]], focused: 0)
        s.insert(window: 3, width: .fraction(0.5), at: .end)
        #expect(shape(s) == [[1], [2], [3]])
        #expect(s.focused == 2)

        s = Strip()
        s.insert(window: 3, width: .fraction(0.5), at: .afterFocused)
        #expect(shape(s) == [[3]])
        #expect(s.focused == 0)
    }

    @Test func insertIntoEmptyStripLandsAtZero() {
        for position in InsertPosition.allCases {
            var s = Strip()
            s.insert(window: 5, width: .fraction(0.5), at: position)
            #expect(shape(s) == [[5]])
            #expect(s.focused == 0)
        }
    }

    @Test func insertBuildsAFreshSingleWindowColumn() {
        var s = strip([[1]], focused: 0)
        s.insert(window: 2, width: .points(300), at: .end)
        let column = s.columns[1]
        #expect(column.windows == [2])
        #expect(column.heightWeights == [1])
        #expect(column.active == 0)
        #expect(column.width == .points(300))
        #expect(column.mode == .stacked)
        #expect(column.pinned == nil)
        #expect(column.widthBeforeFull == nil)
        #expect(column.heightFraction == nil)
    }

    @Test func insertAfterTheFocusedColumnKeepsTheOthersUntouched() {
        var s = strip([[1, 2], [3]], focused: 0)
        s.columns[0].active = 1
        let first = s.columns[0]
        let last = s.columns[1]
        s.insert(window: 4, width: .fraction(0.5), at: .afterFocused)
        #expect(s.columns[0] == first)
        #expect(s.columns[2] == last)
    }

    @Test func insertWithoutAFocusedColumnAppends() {
        var s = strip([[1], [2]], focused: nil)
        s.insert(window: 3, width: .fraction(0.5), at: .afterFocused)
        #expect(shape(s) == [[1], [2], [3]])
        #expect(s.focused == 2)
    }

    @Test func insertIgnoresAWindowAlreadyInTheStrip() {
        var s = strip([[1], [2]], focused: 0)
        let before = s
        s.insert(window: 2, width: .fraction(0.5), at: .afterFocused)
        #expect(s == before)
    }

    // MARK: remove

    @Test func removeKeepsFocusedColumn() {
        var s = strip([[1], [2], [3]], focused: 2)
        s.remove(window: 1)
        #expect(shape(s) == [[2], [3]])
        #expect(s.focused == 1)
    }

    @Test func removeFocused() {
        var s = strip([[1], [2], [3]], focused: 1)
        s.remove(window: 2)
        #expect(shape(s) == [[1], [3]])
        #expect(s.focused == 1)
    }

    @Test func removeTheLastColumnClampsFocus() {
        var s = strip([[1], [2], [3]], focused: 2)
        s.remove(window: 3)
        #expect(shape(s) == [[1], [2]])
        #expect(s.focused == 1)
    }

    @Test func removeTheLastWindowEmptiesTheStrip() {
        var s = strip([[1]], focused: 0)
        s.remove(window: 1)
        #expect(s.columns.isEmpty)
        #expect(s.focused == nil)
    }

    @Test func removeFromStack() {
        var s = strip([[1, 2]], focused: 0)
        s.columns[0].active = 1
        s.remove(window: 2)
        #expect(shape(s) == [[1]])
        #expect(s.columns[0].active == 0)
        #expect(s.columns[0].heightWeights == [1])
    }

    @Test func removeKeepsWeightsParallelToWindows() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.columns[0].heightWeights = [0.5, 0.2, 0.3]
        s.remove(window: 2)
        #expect(shape(s) == [[1, 3]])
        #expect(s.columns[0].heightWeights == [0.5, 0.3])
    }

    @Test func removeAboveTheActiveWindowKeepsItActive() {
        var s = strip([[1, 2, 3, 4]], focused: 0)
        s.columns[0].active = 2   // window 3, with a window below it so the end of the stack cannot hide a mistake
        s.remove(window: 1)
        #expect(shape(s) == [[2, 3, 4]])
        #expect(s.columns[0].active == 1)
        #expect(s.columns[0].activeWindow == 3)
    }

    @Test func removeTheActiveWindowPassesActiveToItsSuccessor() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.columns[0].active = 1
        s.remove(window: 2)
        #expect(s.columns[0].active == 1)
        #expect(s.columns[0].activeWindow == 3)
    }

    @Test func removeBelowTheActiveWindowLeavesActiveAlone() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.remove(window: 3)
        #expect(s.columns[0].active == 0)
        #expect(s.columns[0].activeWindow == 1)
    }

    @Test func removeColumnsBeforeTheFocusedOneTracksItsIndex() {
        // The focused column is not the last one, so clamping the old index could not give the right answer.
        var s = strip([[1], [2], [3], [4], [5]], focused: 3)
        let focusedID = s.columns[3].id
        s.remove(window: 1)
        #expect(shape(s) == [[2], [3], [4], [5]])
        #expect(s.focused == 2)
        #expect(s.focusedColumn?.id == focusedID)
        s.remove(window: 3)
        #expect(shape(s) == [[2], [4], [5]])
        #expect(s.focused == 1)
        #expect(s.focusedColumn?.id == focusedID)
    }

    @Test func removeColumnsAfterTheFocusedOneLeavesItsIndex() {
        var s = strip([[1], [2], [3], [4]], focused: 1)
        let focusedID = s.columns[1].id
        s.remove(window: 4)
        s.remove(window: 3)
        #expect(shape(s) == [[1], [2]])
        #expect(s.focused == 1)
        #expect(s.focusedColumn?.id == focusedID)
    }

    @Test func removeFromAColumnThatSurvivesLeavesFocusAlone() {
        var s = strip([[1, 2], [3], [4]], focused: 2)
        s.remove(window: 1)
        #expect(shape(s) == [[2], [3], [4]])
        #expect(s.focused == 2)
    }

    @Test func removeUnknownWindowChangesNothing() {
        var s = strip([[1, 2], [3]], focused: 1)
        let before = s
        s.remove(window: 9)
        #expect(s == before)
    }

    // MARK: focus

    @Test func focusWindowSetsColumnAndActive() {
        var s = strip([[1, 2], [3]], focused: 1)
        let foundSecond = s.focus(window: 2)
        #expect(foundSecond)
        #expect(s.focused == 0)
        #expect(s.columns[0].active == 1)
        let foundThird = s.focus(window: 3)
        #expect(foundThird)
        #expect(s.focused == 1)
        #expect(s.columns[1].active == 0)
    }

    @Test func focusWindowThatIsNotInTheStripFails() {
        var s = strip([[1, 2], [3]], focused: 1)
        let before = s
        let found = s.focus(window: 9)
        #expect(!found)
        #expect(s == before)
    }

    @Test func focusColumnNoWrap() {
        var s = strip([[1], [2], [3]], focused: 1)
        s.focusColumn(.right, hidden: [])
        #expect(s.focused == 2)
        s.focusColumn(.right, hidden: [])
        #expect(s.focused == 2)
        s.focusColumn(.left, hidden: [])
        #expect(s.focused == 1)
        s.focusColumn(.left, hidden: [])
        #expect(s.focused == 0)
        s.focusColumn(.left, hidden: [])
        #expect(s.focused == 0)
    }

    @Test func focusSkipsCollapsed() {
        var s = strip([[1], [2], [3]], focused: 0)
        s.focusColumn(.right, hidden: [2])
        #expect(s.focused == 2)
        s.focusColumn(.left, hidden: [2])
        #expect(s.focused == 0)
    }

    @Test func focusColumnStaysPutWhenNothingIsReachable() {
        var s = strip([[1], [2], [3]], focused: 0)
        s.focusColumn(.right, hidden: [2, 3])
        #expect(s.focused == 0)
    }

    @Test func focusColumnWalksTheVisualOrder() {
        // Visual order is column 2 (left pin), 1, 0 (right pin).
        var s = strip([[1], [2], [3]], focused: 1, pinned: [0: .right, 2: .left])
        s.focusColumn(.right, hidden: [])
        #expect(s.focused == 0)
        s.focusColumn(.right, hidden: [])
        #expect(s.focused == 0)
        s.focusColumn(.left, hidden: [])
        #expect(s.focused == 1)
        s.focusColumn(.left, hidden: [])
        #expect(s.focused == 2)
        s.focusColumn(.left, hidden: [])
        #expect(s.focused == 2)
    }

    @Test func focusColumnLeavesACollapsedFocusedColumn() {
        // The focused column is itself hidden: navigation continues from its slot.
        var s = strip([[1], [2], [3]], focused: 1)
        s.focusColumn(.right, hidden: [2])
        #expect(s.focused == 2)
        s = strip([[1], [2], [3]], focused: 1)
        s.focusColumn(.left, hidden: [2])
        #expect(s.focused == 0)
    }

    @Test func focusRow() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.focusRow(.down, hidden: [2])
        #expect(s.columns[0].active == 2)
        s.focusRow(.down, hidden: [2])
        #expect(s.columns[0].active == 2)
        s.focusRow(.up, hidden: [2])
        #expect(s.columns[0].active == 0)
        s.focusRow(.up, hidden: [2])
        #expect(s.columns[0].active == 0)
    }

    @Test func focusRowStaysPutWhenOnlyHiddenWindowsLieThatWay() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.focusRow(.down, hidden: [2, 3])
        #expect(s.columns[0].active == 0)
    }

    @Test func focusRowOnlyTouchesTheFocusedColumn() {
        var s = strip([[1, 2], [3, 4]], focused: 1)
        s.focusRow(.down, hidden: [])
        #expect(s.columns[1].active == 1)
        #expect(s.columns[0].active == 0)
        #expect(s.focused == 1)
    }

    @Test func focusFirstAndLast() {
        var s = strip([[1], [2], [3]], focused: 1)
        s.focusLast(hidden: [])
        #expect(s.focused == 2)
        s.focusFirst(hidden: [])
        #expect(s.focused == 0)
    }

    @Test func focusFirstAndLastFollowVisualOrderAndSkipCollapsed() {
        // Visual order is column 2 (left pin), 1, 0 (right pin).
        var s = strip([[1], [2], [3]], focused: 1, pinned: [0: .right, 2: .left])
        s.focusFirst(hidden: [])
        #expect(s.focused == 2)
        s.focusLast(hidden: [])
        #expect(s.focused == 0)
        s.focusFirst(hidden: [3])   // the left pin is collapsed
        #expect(s.focused == 1)
        s.focused = 2
        s.focusLast(hidden: [1])    // the right pin is collapsed
        #expect(s.focused == 1)
    }

    @Test func focusNth() {
        var s = strip([[1], [2], [3]], focused: 0)
        s.focusNth(3, hidden: [])
        #expect(s.focused == 2)

        s = strip([[1], [2], [3]], focused: 0)
        s.focusNth(4, hidden: [])
        #expect(s.focused == 0)
        s.focusNth(0, hidden: [])
        #expect(s.focused == 0)
        s.focusNth(-1, hidden: [])
        #expect(s.focused == 0)
    }

    @Test func focusNthCountsAlongTheVisualOrderWithoutCollapsed() {
        // Visual order is column 2 (left pin), 1, 0 (right pin).
        var s = strip([[1], [2], [3]], focused: 1, pinned: [0: .right, 2: .left])
        s.focusNth(1, hidden: [])
        #expect(s.focused == 2)
        s.focusNth(3, hidden: [])
        #expect(s.focused == 0)
        s = strip([[1], [2], [3]], focused: 2, pinned: [0: .right, 2: .left])
        s.focusNth(2, hidden: [2])   // column 1 collapsed: the order is 2, 0
        #expect(s.focused == 0)
        s.focusNth(3, hidden: [2])   // only two columns are open
        #expect(s.focused == 0)
    }

    // MARK: move

    @Test func moveColumnSwaps() {
        var s = strip([[1], [2], [3]], focused: 0)
        s.moveColumn(.right)
        #expect(shape(s) == [[2], [1], [3]])
        #expect(s.focused == 1)
        s.moveColumn(.right)
        #expect(shape(s) == [[2], [3], [1]])
        #expect(s.focused == 2)
        s.moveColumn(.left)
        #expect(shape(s) == [[2], [1], [3]])
        #expect(s.focused == 1)
    }

    @Test func moveColumnAtTheEdgesDoesNothing() {
        var s = strip([[1], [2]], focused: 0)
        s.moveColumn(.left)
        #expect(shape(s) == [[1], [2]])
        #expect(s.focused == 0)
        s.focused = 1
        s.moveColumn(.right)
        #expect(shape(s) == [[1], [2]])
        #expect(s.focused == 1)
    }

    @Test func moveColumnSwapsWithTheNearestUnpinnedNeighbor() {
        var s = strip([[1], [2], [3]], focused: 0, pinned: [1: .left])
        s.moveColumn(.right)
        #expect(shape(s) == [[3], [2], [1]])
        #expect(s.focused == 2)
        #expect(s.columns[1].pinned == .left)
    }

    @Test func moveColumnDoesNothingWhenOnlyPinnedColumnsLieThatWay() {
        var s = strip([[1], [2], [3]], focused: 0, pinned: [1: .left, 2: .right])
        let before = s
        s.moveColumn(.right)
        #expect(s == before)
    }

    @Test func moveColumnDoesNothingOnAPinnedColumn() {
        var s = strip([[1], [2], [3]], focused: 1, pinned: [1: .left])
        let before = s
        s.moveColumn(.left)
        #expect(s == before)
        s.moveColumn(.right)
        #expect(s == before)
    }

    @Test func moveColumnFromTo() {
        var s = strip([[1], [2], [3]], focused: 0)
        s.moveColumn(from: 0, to: 2)
        #expect(shape(s) == [[2], [3], [1]])
        #expect(s.focused == 2)
    }

    @Test func moveColumnFromToMovesLeftwardToo() {
        var s = strip([[1], [2], [3]], focused: 0)
        s.moveColumn(from: 2, to: 0)
        #expect(shape(s) == [[3], [1], [2]])
        #expect(s.focused == 0)
        s.moveColumn(from: 2, to: 1)
        #expect(shape(s) == [[3], [2], [1]])
        #expect(s.focused == 1)
    }

    @Test func moveColumnFromToMovesFocusToTheMovedColumn() {
        var s = strip([[1], [2], [3]], focused: 2)
        s.moveColumn(from: 0, to: 1)
        #expect(shape(s) == [[2], [1], [3]])
        #expect(s.focused == 1)
        #expect(s.focusedWindow == 1)
    }

    @Test func moveColumnFromToIgnoresBadIndices() {
        var s = strip([[1], [2], [3]], focused: 0)
        let before = s
        s.moveColumn(from: 3, to: 0)
        s.moveColumn(from: 0, to: 3)
        s.moveColumn(from: -1, to: 1)
        s.moveColumn(from: 1, to: -1)
        #expect(s == before)
    }

    @Test func moveColumnFromToTheSameIndexMovesNothing() {
        var s = strip([[1], [2], [3]], focused: 0)
        let before = s
        s.moveColumn(from: 1, to: 1)
        #expect(s == before)
    }

    @Test func moveRowSwapsWithTheNeighbor() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.columns[0].heightWeights = [0.5, 0.2, 0.3]
        s.moveRow(.down)
        #expect(shape(s) == [[2, 1, 3]])
        #expect(s.columns[0].heightWeights == [0.2, 0.5, 0.3])
        #expect(s.columns[0].active == 1)
        #expect(s.columns[0].activeWindow == 1)
        s.moveRow(.down)
        #expect(shape(s) == [[2, 3, 1]])
        #expect(s.columns[0].heightWeights == [0.2, 0.3, 0.5])
        #expect(s.columns[0].active == 2)
        s.moveRow(.up)
        #expect(shape(s) == [[2, 1, 3]])
        #expect(s.columns[0].heightWeights == [0.2, 0.5, 0.3])
        #expect(s.columns[0].active == 1)
    }

    @Test func moveRowAtTheEdgesDoesNothing() {
        var s = strip([[1, 2]], focused: 0)
        let before = s
        s.moveRow(.up)
        #expect(s == before)
        s.columns[0].active = 1
        let atBottom = s
        s.moveRow(.down)
        #expect(s == atBottom)
    }

    @Test func moveRowOnlyTouchesTheFocusedColumn() {
        var s = strip([[1, 2], [3, 4]], focused: 1)
        s.moveRow(.down)
        #expect(shape(s) == [[1, 2], [4, 3]])
    }

    // MARK: stack and pop out

    @Test func stackLeft() {
        var s = strip([[1], [2]], focused: 1)
        s.stack(.left, hidden: [])
        #expect(shape(s) == [[1, 2]])
        #expect(s.focused == 0)
        #expect(s.columns[0].active == 1)
    }

    @Test func stackRight() {
        var s = strip([[1, 2], [3]], focused: 0)
        s.columns[0].active = 1
        s.stack(.right, hidden: [])
        #expect(shape(s) == [[1], [3, 2]])
        #expect(s.focused == 1)
        #expect(s.columns[1].active == 1)
    }

    @Test func stackWithNoNeighborDoesNothing() {
        var s = strip([[1], [2]], focused: 1)
        let before = s
        s.stack(.right, hidden: [])
        #expect(s == before)
        s = strip([[1], [2]], focused: 0)
        let atLeftEdge = s
        s.stack(.left, hidden: [])
        #expect(s == atLeftEdge)
    }

    @Test func stackRemovingTheSourceColumnShiftsTheTargetIndex() {
        var s = strip([[1], [2]], focused: 0)
        s.stack(.right, hidden: [])
        #expect(shape(s) == [[2, 1]])
        #expect(s.focused == 0)
        #expect(s.columns[0].active == 1)
        #expect(s.focusedWindow == 1)
    }

    @Test func stackedWindowGetsWeightOne() {
        var s = strip([[1], [2, 3]], focused: 0)
        s.columns[1].heightWeights = [0.7, 0.3]
        s.stack(.right, hidden: [])
        #expect(shape(s) == [[2, 3, 1]])
        #expect(s.columns[0].heightWeights == [0.7, 0.3, 1])
    }

    @Test func stackLeavesTheSourceConsistent() {
        var s = strip([[1, 2, 3], [4]], focused: 0)
        s.columns[0].heightWeights = [0.5, 0.2, 0.3]
        s.columns[0].active = 1
        s.stack(.right, hidden: [])
        #expect(shape(s) == [[1, 3], [4, 2]])
        #expect(s.columns[0].heightWeights == [0.5, 0.3])
        #expect(s.columns[0].active == 1)
        #expect(s.columns[1].heightWeights == [1, 1])
    }

    @Test func stackSkipsPinnedColumns() {
        var s = strip([[1], [2], [3]], focused: 0, pinned: [1: .left])
        s.stack(.right, hidden: [])
        #expect(shape(s) == [[2], [3, 1]])
        #expect(s.focused == 1)
        #expect(s.columns[0].pinned == .left)
        #expect(s.columns[1].pinned == nil)
    }

    @Test func stackSkipsCollapsedColumns() {
        var s = strip([[1], [2], [3]], focused: 0)
        s.stack(.right, hidden: [2])
        #expect(shape(s) == [[2], [3, 1]])
        #expect(s.focused == 1)
    }

    @Test func stackDoesNothingWhenEveryCandidateIsPinnedOrCollapsed() {
        var s = strip([[1], [2], [3]], focused: 0, pinned: [1: .left])
        let before = s
        s.stack(.right, hidden: [3])
        #expect(s == before)
    }

    @Test func stackDoesNothingOnAPinnedColumn() {
        var s = strip([[1], [2]], focused: 0, pinned: [0: .left])
        let before = s
        s.stack(.right, hidden: [])
        #expect(s == before)
    }

    @Test func popOutRight() {
        var s = strip([[1, 2]], focused: 0)
        s.columns[0].active = 1
        s.popOut(.right)
        #expect(shape(s) == [[1], [2]])
        #expect(s.focused == 1)
    }

    @Test func popOutLeft() {
        var s = strip([[1, 2]], focused: 0)
        s.popOut(.left)
        #expect(shape(s) == [[1], [2]])
        #expect(s.focused == 0)
    }

    @Test func popOutOfASingleWindowDoesNothing() {
        var s = strip([[1], [2]], focused: 0)
        let before = s
        s.popOut(.right)
        s.popOut(.left)
        #expect(s == before)
    }

    @Test func popOutCreatesAFreshColumnWithTheSourceWidth() {
        var s = strip([[1, 2]], focused: 0)
        s.columns[0].width = .fraction(1)
        s.columns[0].widthBeforeFull = .fraction(1.0 / 3)
        s.columns[0].active = 1
        s.popOut(.right)
        let popped = s.columns[1]
        #expect(popped.windows == [2])
        #expect(popped.heightWeights == [1])
        #expect(popped.active == 0)
        #expect(popped.width == .fraction(1))
        #expect(popped.widthBeforeFull == nil)
        #expect(popped.mode == .stacked)
        #expect(popped.pinned == nil)
        #expect(s.columns[0].widthBeforeFull == .fraction(1.0 / 3))
    }

    @Test func popOutLeavesTheSourceConsistent() {
        var s = strip([[1, 2, 3], [4]], focused: 0)
        s.columns[0].heightWeights = [0.5, 0.2, 0.3]
        s.columns[0].active = 1
        s.popOut(.right)
        #expect(shape(s) == [[1, 3], [2], [4]])
        #expect(s.columns[0].heightWeights == [0.5, 0.3])
        #expect(s.columns[0].active == 1)
        #expect(s.focused == 1)
        #expect(s.focusedWindow == 2)
    }

    @Test func popOutDoesNothingOnAPinnedColumn() {
        var s = strip([[1, 2]], focused: 0, pinned: [0: .right])
        let before = s
        s.popOut(.left)
        #expect(s == before)
    }

    // MARK: mode and pins

    @Test func toggleTabbed() {
        var s = strip([[1, 2], [3]], focused: 0)
        s.toggleTabbed()
        #expect(s.columns[0].mode == .tabbed)
        #expect(s.columns[1].mode == .stacked)
        s.toggleTabbed()
        #expect(s.columns[0].mode == .stacked)
    }

    @Test func togglePin() {
        var s = strip([[1], [2]], focused: 0)
        s.togglePin(.left)
        #expect(s.columns[0].pinned == .left)
        s.togglePin(.left)
        #expect(s.columns[0].pinned == nil)

        s.togglePin(.left)
        s.focused = 1
        s.togglePin(.left)
        #expect(s.columns[1].pinned == .left)
        #expect(s.columns[0].pinned == nil)
    }

    @Test func togglePinSwitchesSide() {
        var s = strip([[1], [2]], focused: 0)
        s.togglePin(.left)
        s.togglePin(.right)
        #expect(s.columns[0].pinned == .right)
        s.togglePin(.right)
        #expect(s.columns[0].pinned == nil)
    }

    @Test func togglePinLeavesTheOtherSideAlone() {
        var s = strip([[1], [2]], focused: 0)
        s.togglePin(.left)
        s.focused = 1
        s.togglePin(.right)
        #expect(s.columns[0].pinned == .left)
        #expect(s.columns[1].pinned == .right)
        #expect(s.focused == 1)
    }

    // MARK: width

    @Test func cycleWidth() {
        var s = strip([[1]], focused: 0)
        s.cycleWidth(presets: Self.presets, available: 1000, gap: 10)
        #expect(s.columns[0].width == .fraction(2.0 / 3))

        s.columns[0].width = .fraction(0.75)
        s.cycleWidth(presets: Self.presets, available: 1000, gap: 10)
        #expect(s.columns[0].width == .fraction(0.25))

        s.columns[0].width = .points(400)
        s.cycleWidth(presets: Self.presets, available: 1000, gap: 10)
        #expect(s.columns[0].width == .fraction(0.5))
    }

    @Test func cycleWidthToleratesAOnePercentDifference() {
        var s = strip([[1]], focused: 0)
        s.columns[0].width = .fraction(0.495)   // within 0.01 of the 0.5 preset
        s.cycleWidth(presets: Self.presets, available: 1000, gap: 10)
        #expect(s.columns[0].width == .fraction(2.0 / 3))
        s.columns[0].width = .fraction(0.1)
        s.cycleWidth(presets: Self.presets, available: 1000, gap: 10)
        #expect(s.columns[0].width == .fraction(0.25))
    }

    @Test func cycleWidthClearsTheWidthBeforeFull() {
        var s = strip([[1]], focused: 0)
        s.toggleFullWidth()
        #expect(s.columns[0].widthBeforeFull != nil)
        s.cycleWidth(presets: Self.presets, available: 1000, gap: 10)
        #expect(s.columns[0].widthBeforeFull == nil)
        #expect(s.columns[0].width == .fraction(0.25))
    }

    @Test func cycleWidthWithoutPresetsDoesNothing() {
        var s = strip([[1]], focused: 0)
        let before = s
        s.cycleWidth(presets: [], available: 1000, gap: 10)
        #expect(s == before)
    }

    @Test func cycleWidthOnlyTouchesTheFocusedColumn() {
        var s = strip([[1], [2]], focused: 1)
        s.cycleWidth(presets: Self.presets, available: 1000, gap: 10)
        #expect(s.columns[0].width == .fraction(0.5))
        #expect(s.columns[1].width == .fraction(2.0 / 3))
    }

    @Test func toggleFullWidth() {
        var s = strip([[1]], focused: 0)
        s.columns[0].width = .fraction(1.0 / 3)
        s.toggleFullWidth()
        #expect(s.columns[0].width == .fraction(1))
        #expect(s.columns[0].widthBeforeFull == .fraction(1.0 / 3))
        s.toggleFullWidth()
        #expect(s.columns[0].width == .fraction(1.0 / 3))
        #expect(s.columns[0].widthBeforeFull == nil)
    }

    @Test func setFullWidthOnlyChangesWhatIsNotAlreadySo() {
        var s = strip([[1], [2]], focused: 1)
        s.columns[1].width = .points(420)
        s.setFullWidth(true)
        #expect(s.columns[1].width == .fraction(1) && s.columns[1].widthBeforeFull == .points(420))
        s.setFullWidth(true)                                   // a second swipe up keeps the width to go back to
        #expect(s.columns[1].widthBeforeFull == .points(420))
        s.setFullWidth(false)
        #expect(s.columns[1].width == .points(420) && s.columns[1].widthBeforeFull == nil)
        s.setFullWidth(false)                                  // nothing to go back to
        #expect(s.columns[1].width == .points(420))
        var none = strip([[1]], focused: nil)
        none.setFullWidth(true)
        #expect(none.columns[0].widthBeforeFull == nil)
    }

    @Test func swipingUpAfterNarrowingAFullColumnGoesFullAgain() {
        // ⌃⌘M then ⌃⌘- leaves the column a bit narrower but still remembering its old width (ruling 8): swiping up
        // makes it full again, and swiping down still returns to that old width.
        var s = strip([[1]], focused: 0)
        s.columns[0].width = .fraction(1.0 / 3)
        s.toggleFullWidth()
        s.adjustWidth(by: -0.05, available: 1000, gap: 10)
        #expect(s.columns[0].width == .fraction(0.95))
        s.setFullWidth(true)
        #expect(s.columns[0].width == .fraction(1) && s.columns[0].widthBeforeFull == .fraction(1.0 / 3))
        s.setFullWidth(false)
        #expect(s.columns[0].width == .fraction(1.0 / 3))
        // A column that is already full width without anything to go back to stays as it is.
        s.columns[0].width = .fraction(1)
        s.setFullWidth(true)
        #expect(s.columns[0].widthBeforeFull == nil)
    }

    @Test func toggleFullWidthRestoresPointWidthsToo() {
        var s = strip([[1]], focused: 0)
        s.columns[0].width = .points(420)
        s.toggleFullWidth()
        #expect(s.columns[0].width == .fraction(1))
        s.toggleFullWidth()
        #expect(s.columns[0].width == .points(420))
    }

    @Test func adjustWidthClamps() {
        var s = strip([[1]], focused: 0)
        s.columns[0].width = .fraction(0.95)
        s.adjustWidth(by: 0.1, available: 1000, gap: 10)
        #expect(s.columns[0].width == .fraction(1.0))

        s.columns[0].width = .fraction(0.12)
        s.adjustWidth(by: -0.05, available: 1000, gap: 10)
        #expect(s.columns[0].width == .fraction(0.1))
    }

    @Test func adjustWidthStepsFromTheCurrentFraction() {
        var s = strip([[1], [2]], focused: 0)
        s.adjustWidth(by: 0.05, available: 1000, gap: 10)
        guard case .fraction(let grown) = s.columns[0].width else {
            Issue.record("expected a fraction width")
            return
        }
        #expect(near(grown, 0.55))
        #expect(s.columns[1].width == .fraction(0.5))
    }

    @Test func adjustWidthConvertsPointWidthsToFractions() {
        var s = strip([[1]], focused: 0)
        s.columns[0].width = .points(400)   // (400 + 10) / (1000 + 10)
        s.adjustWidth(by: 0.05, available: 1000, gap: 10)
        guard case .fraction(let grown) = s.columns[0].width else {
            Issue.record("expected a fraction width")
            return
        }
        #expect(near(grown, 410.0 / 1010.0 + 0.05))
    }

    @Test func setWidthInPointsTargetsTheWindowsColumn() {
        var s = strip([[1], [2, 3]], focused: 0)
        s.setWidth(points: 320, window: 3)
        #expect(s.columns[1].width == .points(320))
        #expect(s.columns[0].width == .fraction(0.5))
        #expect(s.focused == 0)
    }

    @Test func setWidthForAnUnknownWindowDoesNothing() {
        var s = strip([[1], [2]], focused: 0)
        let before = s
        s.setWidth(points: 320, window: 9)
        #expect(s == before)
    }

    // MARK: height

    @Test func adjustHeightStack() {
        var s = strip([[1, 2]], focused: 0)
        s.adjustHeight(by: 0.1, hidden: [])
        let weights = s.columns[0].heightWeights
        let sum = weights.reduce(0, +)
        #expect(near(weights[0] / sum, 0.6))
        #expect(near(sum, 1))
    }

    @Test func adjustHeightActsOnTheActiveWindow() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.columns[0].active = 1
        s.adjustHeight(by: 0.1, hidden: [])
        let weights = s.columns[0].heightWeights
        #expect(near(weights[1], 1.0 / 3 + 0.1))
        #expect(near(weights[0], weights[2]))
        #expect(near(weights.reduce(0, +), 1))
    }

    @Test func adjustHeightRescalesTheOthersProportionally() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.columns[0].heightWeights = [2, 1, 1]   // shares 0.5, 0.25, 0.25
        s.columns[0].active = 1
        s.adjustHeight(by: 0.25, hidden: [])      // share 0.25 -> 0.5, the others scale by 2/3
        let weights = s.columns[0].heightWeights
        #expect(near(weights[0], 1.0 / 3))
        #expect(near(weights[1], 0.5))
        #expect(near(weights[2], 1.0 / 6))
    }

    @Test func adjustHeightClampsTheShare() {
        var s = strip([[1, 2]], focused: 0)
        s.adjustHeight(by: 0.9, hidden: [])
        #expect(near(s.columns[0].heightWeights[0], 0.9))
        #expect(near(s.columns[0].heightWeights[1], 0.1))
        s.adjustHeight(by: -2, hidden: [])
        #expect(near(s.columns[0].heightWeights[0], 0.1))
        #expect(near(s.columns[0].heightWeights[1], 0.9))
    }

    @Test func adjustHeightOnlyCountsVisibleWindows() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.adjustHeight(by: 0.1, hidden: [3])
        let weights = s.columns[0].heightWeights
        #expect(near(weights[0], 0.6))
        #expect(near(weights[1], 0.4))
        #expect(weights[2] == 1)
    }

    @Test func adjustHeightSingle() {
        var s = strip([[1]], focused: 0)
        s.adjustHeight(by: -0.3, hidden: [])
        s.adjustHeight(by: -0.3, hidden: [])
        guard let fraction = s.columns[0].heightFraction else {
            Issue.record("expected a height fraction")
            return
        }
        #expect(near(fraction, 0.4))
        #expect(s.columns[0].heightWeights == [1])
    }

    @Test func adjustHeightSingleClamps() {
        var s = strip([[1]], focused: 0)
        for _ in 0..<5 { s.adjustHeight(by: -0.3, hidden: []) }
        #expect(s.columns[0].heightFraction == 0.2)
        for _ in 0..<5 { s.adjustHeight(by: 0.3, hidden: []) }
        #expect(s.columns[0].heightFraction == 1.0)
    }

    @Test func adjustHeightWithOneVisibleWindowUsesTheHeightFraction() {
        var s = strip([[1, 2]], focused: 0)
        s.adjustHeight(by: -0.3, hidden: [2])
        guard let fraction = s.columns[0].heightFraction else {
            Issue.record("expected a height fraction")
            return
        }
        #expect(near(fraction, 0.7))
        #expect(s.columns[0].heightWeights == [1, 1])
    }

    @Test func adjustHeightWithNoVisibleWindowDoesNothing() {
        var s = strip([[1, 2]], focused: 0)
        let before = s
        s.adjustHeight(by: 0.1, hidden: [1, 2])
        #expect(s == before)
    }

    @Test func adjustHeightDoesNothingWhenTheActiveWindowIsHidden() {
        var s = strip([[1, 2, 3]], focused: 0)   // window 1 is active, and hidden
        let before = s
        s.adjustHeight(by: 0.1, hidden: [1])
        #expect(s == before)
    }

    @Test func setHeightShare() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.setHeightShare(window: 2, share: 0.7, hidden: [])
        let weights = s.columns[0].heightWeights
        #expect(near(weights[1], 0.7))
        #expect(near(weights[0], 0.15))
        #expect(near(weights[2], 0.15))
        #expect(near(weights.reduce(0, +), 1))
    }

    @Test func setHeightShareKeepsTheOthersProportions() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.columns[0].heightWeights = [3, 1, 1]
        s.setHeightShare(window: 2, share: 0.5, hidden: [])
        let weights = s.columns[0].heightWeights
        #expect(near(weights[1], 0.5))
        #expect(near(weights[0], 0.375))   // 3/4 of the remaining half
        #expect(near(weights[2], 0.125))   // 1/4 of the remaining half
    }

    @Test func setHeightShareClamps() {
        var s = strip([[1, 2]], focused: 0)
        s.setHeightShare(window: 1, share: 0.95, hidden: [])
        #expect(near(s.columns[0].heightWeights[0], 0.9))
        #expect(near(s.columns[0].heightWeights[1], 0.1))
        s.setHeightShare(window: 1, share: 0.02, hidden: [])
        #expect(near(s.columns[0].heightWeights[0], 0.1))
        #expect(near(s.columns[0].heightWeights[1], 0.9))
    }

    @Test func setHeightShareLeavesHiddenWindowsAlone() {
        var s = strip([[1, 2, 3]], focused: 0)
        s.columns[0].heightWeights = [1, 1, 5]
        s.setHeightShare(window: 1, share: 0.75, hidden: [3])
        let weights = s.columns[0].heightWeights
        #expect(near(weights[0], 0.75))
        #expect(near(weights[1], 0.25))
        #expect(weights[2] == 5)
    }

    @Test func setHeightShareIgnoresWindowsThatCannotTakeAShare() {
        var s = strip([[1, 2, 3], [4]], focused: 0)
        let before = s
        s.setHeightShare(window: 9, share: 0.7, hidden: [])          // not in the strip
        s.setHeightShare(window: 1, share: 0.7, hidden: [1])         // hidden itself, though others are visible
        s.setHeightShare(window: 1, share: 0.7, hidden: [2, 3])      // the only visible window of its column
        s.setHeightShare(window: 4, share: 0.7, hidden: [])          // alone in its column
        #expect(s == before)
    }

    @Test func equalize() {
        var s = strip([[1, 2]], focused: 0)
        s.adjustHeight(by: 0.1, hidden: [])
        s.columns[0].heightFraction = 0.5
        s.equalizeHeights()
        #expect(s.columns[0].heightWeights == [1, 1])
        #expect(s.columns[0].heightFraction == nil)
    }

    @Test func equalizeOnlyTouchesTheFocusedColumn() {
        var s = strip([[1, 2], [3, 4]], focused: 0)
        s.columns[0].heightWeights = [0.7, 0.3]
        s.columns[1].heightWeights = [0.7, 0.3]
        s.equalizeHeights()
        #expect(s.columns[0].heightWeights == [1, 1])
        #expect(s.columns[1].heightWeights == [0.7, 0.3])
    }

    // MARK: degenerate strips

    @Test func operationsOnAnEmptyStripDoNothing() {
        var s = Strip()
        s.focusColumn(.left, hidden: [])
        s.focusColumn(.right, hidden: [])
        s.focusRow(.up, hidden: [])
        s.focusRow(.down, hidden: [])
        s.focusFirst(hidden: [])
        s.focusLast(hidden: [])
        s.focusNth(1, hidden: [])
        s.moveColumn(.left)
        s.moveColumn(.right)
        s.moveColumn(from: 0, to: 1)
        s.moveRow(.up)
        s.moveRow(.down)
        s.stack(.left, hidden: [])
        s.stack(.right, hidden: [])
        s.popOut(.left)
        s.popOut(.right)
        s.toggleTabbed()
        s.togglePin(.left)
        s.togglePin(.right)
        s.cycleWidth(presets: Self.presets, available: 1000, gap: 10)
        s.toggleFullWidth()
        s.adjustWidth(by: 0.1, available: 1000, gap: 10)
        s.adjustHeight(by: 0.1, hidden: [])
        s.setHeightShare(window: 1, share: 0.5, hidden: [])
        s.equalizeHeights()
        s.setWidth(points: 300, window: 1)
        s.remove(window: 1)
        let found = s.focus(window: 1)
        #expect(!found)
        #expect(s == Strip())
    }

    @Test func operationsWithoutAFocusedColumnDoNothing() {
        // `focused` may be nil, past the end or negative; none of those names a column.
        for focused in [nil, 7, -1] as [Int?] {
            let original = strip([[1, 2], [3]], focused: focused)
            var s = original
            s.focusColumn(.left, hidden: [])
            s.focusColumn(.right, hidden: [])
            s.focusRow(.up, hidden: [])
            s.focusRow(.down, hidden: [])
            s.focusFirst(hidden: [])
            s.focusLast(hidden: [])
            s.focusNth(1, hidden: [])
            s.moveColumn(.left)
            s.moveColumn(.right)
            s.moveRow(.up)
            s.moveRow(.down)
            s.stack(.left, hidden: [])
            s.stack(.right, hidden: [])
            s.popOut(.left)
            s.popOut(.right)
            s.toggleTabbed()
            s.togglePin(.left)
            s.togglePin(.right)
            s.cycleWidth(presets: Self.presets, available: 1000, gap: 10)
            s.toggleFullWidth()
            s.adjustWidth(by: 0.1, available: 1000, gap: 10)
            s.adjustHeight(by: 0.1, hidden: [])
            s.equalizeHeights()
            #expect(s == original, "focused = \(String(describing: focused))")
        }
    }

    @Test func anOutOfRangeActiveIndexActsLikeTheFirstWindow() {
        // `Column.activeWindow` falls back to the first window; the operations must agree with it.
        var s = strip([[1, 2], [3]], focused: 0)
        s.columns[0].active = 9
        #expect(s.focusedWindow == 1)
        s.stack(.right, hidden: [])
        #expect(shape(s) == [[2], [3, 1]])
        #expect(s.focusedWindow == 1)

        s = strip([[1, 2]], focused: 0)
        s.columns[0].active = 9
        s.popOut(.right)
        #expect(shape(s) == [[2], [1]])
        #expect(s.focusedWindow == 1)

        s = strip([[1, 2, 3]], focused: 0)
        s.columns[0].active = 9
        s.focusRow(.down, hidden: [])
        #expect(s.columns[0].active == 1)
    }
}
