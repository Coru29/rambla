import Testing
import Foundation
import CoreGraphics
@testable import RamblaCore

/// Layout engine tests. Geometry is in global AX coordinates (origin top-left, y grows downward).
/// Common setup: a 1000x800 viewport that is also the display, gap 10, and three 50 % columns
/// (495 pt each) holding windows 1, 2 and 3.
@Suite struct LayoutTests {
    let vp = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let cfg = LayoutConfig(gap: 10)

    // MARK: - Helpers

    func threeColumns(scroll: Double = 0) -> Strip {
        Strip(columns: [
            Column(windows: [1], width: .fraction(0.5)),
            Column(windows: [2], width: .fraction(0.5)),
            Column(windows: [3], width: .fraction(0.5)),
        ], focused: 0, scroll: scroll)
    }

    func input(_ strip: Strip, others: [CGRect] = [], hidden: Set<WindowID> = [],
               minSizes: [WindowID: CGSize] = [:], originalHeights: [WindowID: Double] = [:],
               config: LayoutConfig? = nil) -> LayoutInput {
        LayoutInput(strip: strip, viewport: vp, display: vp, otherDisplays: others, hidden: hidden,
                    minSizes: minSizes, originalHeights: originalHeights, config: config ?? cfg)
    }

    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-6 }

    func near(_ a: CGRect, _ b: CGRect) -> Bool {
        near(a.minX, b.minX) && near(a.minY, b.minY) && near(a.width, b.width) && near(a.height, b.height)
    }

    /// A window's frame, or `.null` when it has no placement (keeps failures from trapping the whole run).
    func frame(_ r: LayoutResult, _ id: WindowID) -> CGRect { r.placements[id]?.frame ?? .null }

    func isParked(_ p: Placement?) -> Bool {
        if case .parked(_)? = p { return true }
        return false
    }

    func visible(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Placement {
        .visible(CGRect(x: x, y: y, width: w, height: h))
    }

    func parked(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Placement {
        .parked(CGRect(x: x, y: y, width: w, height: h))
    }

    // MARK: - Metrics

    @Test func metricsBasic() {
        let m = Layout.metrics(input(threeColumns()))
        #expect(m.xs == [0, 505, 1010])
        #expect(m.widths == [495, 495, 495])
        #expect(m.total == 1505)
        #expect(m.area == vp)
    }

    @Test func minWidthPushesNeighbors() {
        let m = Layout.metrics(input(threeColumns(), minSizes: [1: CGSize(width: 600, height: 1)]))
        #expect(m.xs == [0, 610, 1115])
        #expect(m.widths == [600, 495, 495])
        #expect(m.total == 1610)
    }

    @Test func minWidthIgnoresHiddenWindowsAndSmallerValues() {
        let col = Column(windows: [1, 2], width: .fraction(0.5))
        let strip = Strip(columns: [col], focused: 0)
        // Window 2 is hidden, so its 800 pt minimum does not count; window 1's 300 pt is below the resolved width.
        let m = Layout.metrics(input(strip, hidden: [2], minSizes: [1: CGSize(width: 300, height: 1),
                                                                    2: CGSize(width: 800, height: 1)]))
        #expect(m.widths == [495])
        // With both visible, the widest minimum wins.
        let wide = Layout.metrics(input(strip, minSizes: [1: CGSize(width: 300, height: 1),
                                                          2: CGSize(width: 800, height: 1)]))
        #expect(wide.widths == [800])
    }

    @Test func collapsedColumnTakesNoSpace() {
        let strip = threeColumns()
        let inp = input(strip, hidden: [2])
        let m = Layout.metrics(inp)
        #expect(m.xs[2] == 505)
        #expect(m.widths[1] == 0)
        #expect(m.total == 1000)
        #expect(m.isLaidOut(0) && !m.isLaidOut(1) && m.isLaidOut(2))
        let r = Layout.compute(inp)
        #expect(r.placements[2] == nil)
        #expect(r.columnFrames[strip.columns[1].id] == nil)
        #expect(r.placements[3] == visible(505, 0, 495, 800))
    }

    @Test func emptyStripHasNoMetrics() {
        let m = Layout.metrics(input(Strip()))
        #expect(m.xs.isEmpty)
        #expect(m.widths.isEmpty)
        #expect(m.total == 0)
        #expect(m.area == vp)
        #expect(!m.isLaidOut(0))
    }

    // MARK: - Reveal

    @Test func revealNever() {
        let m = Layout.metrics(input(threeColumns()))
        #expect(Layout.reveal(m, column: 2, current: 0, mode: .never) == 505)
        #expect(Layout.reveal(m, column: 0, current: 505, mode: .never) == 0)
        #expect(Layout.reveal(m, column: 1, current: 0, mode: .never) == 0)
    }

    @Test func revealNeverClampsAndAlignsWideColumns() {
        // Widths [1000, 495], xs [0, 1010], total 1505, scroll area 1000 wide.
        let strip = Strip(columns: [Column(windows: [1], width: .fraction(1)),
                                    Column(windows: [2], width: .fraction(0.5))], focused: 0)
        let m = Layout.metrics(input(strip))
        #expect(m.widths == [1000, 495])
        #expect(Layout.reveal(m, column: 0, current: 300, mode: .never) == 0)      // column as wide as the area: align to its edge
        #expect(Layout.reveal(m, column: 1, current: 0, mode: .never) == 505)       // 1010 + 495 - 1000
        #expect(Layout.reveal(m, column: 1, current: 2000, mode: .never) == 505)    // xi = 1010 clamped to total - w
    }

    @Test func revealOnOverflow() {
        let m = Layout.metrics(input(threeColumns()))
        #expect(Layout.reveal(m, column: 1, current: 0, mode: .onOverflow) == 252.5)
        // Clamped to [0, total - w] at both ends.
        #expect(Layout.reveal(m, column: 0, current: 300, mode: .onOverflow) == 0)
        #expect(Layout.reveal(m, column: 2, current: 0, mode: .onOverflow) == 505)
        // Two columns fit in the area: no scrolling needed.
        let two = Strip(columns: Array(threeColumns().columns.prefix(2)), focused: 0)
        let m2 = Layout.metrics(input(two))
        #expect(m2.total == 1000)
        #expect(Layout.reveal(m2, column: 1, current: 300, mode: .onOverflow) == 0)
    }

    @Test func revealAlways() {
        let m = Layout.metrics(input(threeColumns()))
        #expect(Layout.reveal(m, column: 0, current: 0, mode: .always) == -252.5)
        #expect(Layout.reveal(m, column: 1, current: 0, mode: .always) == 252.5)
        #expect(Layout.reveal(m, column: 2, current: 0, mode: .always) == 757.5)   // not clamped
    }

    @Test func revealIgnoresColumnsThatAreNotLaidOut() {
        let m = Layout.metrics(input(threeColumns(), hidden: [2]))
        #expect(Layout.reveal(m, column: 1, current: 123, mode: .never) == 123)
        #expect(Layout.reveal(m, column: 1, current: 123, mode: .always) == 123)
        #expect(Layout.reveal(m, column: 9, current: 123, mode: .onOverflow) == 123)
    }

    // MARK: - Settle and drop

    @Test func settleSnaps() {
        let m = Layout.metrics(input(threeColumns()))
        let r = Layout.settle(m, scroll: 300)
        #expect(r.scroll == 505)
        #expect(r.column == 1)
    }

    @Test func settleClampsAndBreaksTiesToTheLowerColumn() {
        let m = Layout.metrics(input(threeColumns()))
        let far = Layout.settle(m, scroll: 5000)
        #expect(far.scroll == 505 && far.column == 1)             // 1010 clamped to total - w; columns 1 and 2 tie
        let neg = Layout.settle(m, scroll: -100)
        #expect(neg.scroll == 0 && neg.column == 0)
        let equidistant = Layout.settle(m, scroll: 252.5)          // equally close to 0 and 505: lower index wins
        #expect(equidistant.scroll == 0 && equidistant.column == 0)
    }

    @Test func settlePicksTheMostVisibleColumn() {
        // Widths [242.5, 747.5] fit in the area together, so the target is 0 and the wider column wins.
        let strip = Strip(columns: [Column(windows: [1], width: .fraction(0.25)),
                                    Column(windows: [2], width: .fraction(0.75))], focused: 0)
        let m = Layout.metrics(input(strip))
        #expect(m.total == 1000)
        let r = Layout.settle(m, scroll: 0)
        #expect(r.scroll == 0)
        #expect(r.column == 1)
    }

    @Test func settleWithoutColumns() {
        let none = Layout.settle(Layout.metrics(input(Strip())), scroll: 40)
        #expect(none.scroll == 0)
        #expect(none.column == nil)
        let collapsed = Layout.settle(Layout.metrics(input(threeColumns(), hidden: [1, 2, 3])), scroll: 40)
        #expect(collapsed.scroll == 0)
        #expect(collapsed.column == nil)
    }

    @Test func dropIndexCases() {
        let m = Layout.metrics(input(threeColumns()))
        #expect(Layout.dropIndex(m, stripX: 1300, dragging: 0) == 2)
        #expect(Layout.dropIndex(m, stripX: 100, dragging: 2) == 0)
        #expect(Layout.dropIndex(m, stripX: 600, dragging: 0) == 0)
        #expect(Layout.dropIndex(m, stripX: 5000, dragging: 0) == nil)
    }

    @Test func dropIndexHalvesGapsAndSelf() {
        let m = Layout.metrics(input(threeColumns()))
        // Column 1 spans [505, 1010) including its trailing gap; its midpoint is 752.5.
        #expect(Layout.dropIndex(m, stripX: 700, dragging: 2) == 1)
        #expect(Layout.dropIndex(m, stripX: 760, dragging: 2) == 2)
        #expect(Layout.dropIndex(m, stripX: 1002, dragging: 2) == 2)    // in column 1's gap
        #expect(Layout.dropIndex(m, stripX: 1002, dragging: 0) == 1)
        // The dragged column is never its own target, and nothing lies left of the strip.
        #expect(Layout.dropIndex(m, stripX: 600, dragging: 1) == nil)
        #expect(Layout.dropIndex(m, stripX: -5, dragging: 1) == nil)
    }

    @Test func dropIndexSkipsColumnsThatAreNotLaidOut() {
        let m = Layout.metrics(input(threeColumns(), hidden: [2]))   // xs [0, 505, 505], widths [495, 0, 495]
        // Column 1 is collapsed, so x = 505 belongs to column 2 (left half: position 2, minus the dragged column 0).
        #expect(Layout.dropIndex(m, stripX: 505, dragging: 0) == 1)
        #expect(Layout.dropIndex(m, stripX: 100, dragging: 2) == 0)
        #expect(Layout.dropIndex(m, stripX: 300, dragging: 2) == 1)
    }

    // MARK: - Compute: parking and visibility

    @Test func computeParksOffscreenLeft() {
        let r = Layout.compute(input(threeColumns(scroll: 505)))
        #expect(r.placements[1] == parked(-494, 0, 495, 800))
        #expect(r.placements[2] == visible(0, 0, 495, 800))
        #expect(r.placements[3] == visible(505, 0, 495, 800))
    }

    @Test func computeParksOffscreenRight() {
        let r = Layout.compute(input(threeColumns()))
        #expect(r.placements[1] == visible(0, 0, 495, 800))
        #expect(r.placements[2] == visible(505, 0, 495, 800))
        #expect(r.placements[3] == parked(999, 0, 495, 800))
    }

    @Test func parkingThresholdIsOnePoint() {
        // Parked right when x >= maxX - 1, parked left when x + w <= minX + 1.
        #expect(Layout.compute(input(threeColumns(scroll: 11))).placements[3] == parked(999, 0, 495, 800))
        #expect(Layout.compute(input(threeColumns(scroll: 11.5))).placements[3] == visible(998.5, 0, 495, 800))
        #expect(Layout.compute(input(threeColumns(scroll: 494))).placements[1] == parked(-494, 0, 495, 800))
        #expect(Layout.compute(input(threeColumns(scroll: 493.5))).placements[1] == visible(-493.5, 0, 495, 800))
    }

    @Test func parkingKeepsSliverInsideDisplay() {
        let frame = CGRect(x: 300, y: 0, width: 495, height: 800)
        let right = [CGRect(x: 1000, y: 0, width: 800, height: 600)]
        let left = [CGRect(x: -800, y: 0, width: 800, height: 600)]
        for side in [HDirection.left, .right] {
            for others in [[], right, left] {
                let p = Layout.parkingFrame(for: frame, side: side, display: vp, others: others, sliver: 1)
                let shown = p.intersection(vp)
                // An edge sliver: one point wide, the window's full height inside the display.
                #expect(shown.width == 1)
                #expect(shown.height == frame.height)
                #expect(p.size == frame.size)
            }
        }
    }

    @Test func parkingAvoidsNeighborDisplay() {
        let frame = CGRect(x: 1200, y: 0, width: 495, height: 800)
        let others = [CGRect(x: 1000, y: 0, width: 800, height: 600)]
        // The right edge would overlap the neighbor, so the window goes to the left edge instead.
        let p = Layout.parkingFrame(for: frame, side: .right, display: vp, others: others, sliver: 1)
        #expect(p == CGRect(x: -494, y: 0, width: 495, height: 800))
    }

    @Test func parkingFallsBackWhenBothSidesTaken() {
        let frame = CGRect(x: 1200, y: 0, width: 495, height: 800)
        let others = [CGRect(x: 1000, y: 0, width: 800, height: 600), CGRect(x: -800, y: 0, width: 800, height: 600)]
        let p = Layout.parkingFrame(for: frame, side: .right, display: vp, others: others, sliver: 1)
        #expect(p == CGRect(x: 999, y: 0, width: 495, height: 800))
        // Candidate 1 follows the requested side.
        let q = Layout.parkingFrame(for: frame, side: .left, display: vp, others: others, sliver: 1)
        #expect(q == CGRect(x: -494, y: 0, width: 495, height: 800))
    }

    @Test func parkingTriesTheOppositeEdgeAndKeepsItsY() {
        let frame = CGRect(x: 300, y: 50, width: 495, height: 700)
        let tallRight = CGRect(x: 1000, y: -5000, width: 800, height: 20000)
        let tallLeft = CGRect(x: -800, y: -5000, width: 800, height: 20000)
        // Requested edge free: the window keeps its own y (there are no bottom-corner candidates).
        #expect(Layout.parkingFrame(for: frame, side: .right, display: vp, others: [], sliver: 1)
                == CGRect(x: 999, y: 50, width: 495, height: 700))
        #expect(Layout.parkingFrame(for: frame, side: .left, display: vp, others: [], sliver: 1)
                == CGRect(x: -494, y: 50, width: 495, height: 700))
        // Requested edge taken: the opposite edge, same y.
        #expect(Layout.parkingFrame(for: frame, side: .right, display: vp, others: [tallRight], sliver: 1)
                == CGRect(x: -494, y: 50, width: 495, height: 700))
        #expect(Layout.parkingFrame(for: frame, side: .left, display: vp, others: [tallLeft], sliver: 1)
                == CGRect(x: 999, y: 50, width: 495, height: 700))
        // Both taken: the requested side again.
        #expect(Layout.parkingFrame(for: frame, side: .right, display: vp, others: [tallRight, tallLeft], sliver: 1)
                == CGRect(x: 999, y: 50, width: 495, height: 700))
        // A display beside the sliver but not level with the window does not block it.
        let belowNeighbor = CGRect(x: 1000, y: 800, width: 800, height: 600)
        #expect(Layout.parkingFrame(for: frame, side: .right, display: vp, others: [belowNeighbor], sliver: 1)
                == CGRect(x: 999, y: 50, width: 495, height: 700))
    }

    @Test func parkingIgnoresZeroAreaTouching() {
        let frame = CGRect(x: 300, y: 0, width: 495, height: 800)
        // Candidate 1 spans x 999...1494, y 0...800. One display only shares its right edge, the other its bottom edge.
        let touchingSide = CGRect(x: 1494, y: 0, width: 800, height: 600)
        let touchingBottom = CGRect(x: 1000, y: 800, width: 800, height: 600)
        let p = Layout.parkingFrame(for: frame, side: .right, display: vp, others: [touchingSide, touchingBottom], sliver: 1)
        #expect(p == CGRect(x: 999, y: 0, width: 495, height: 800))
    }

    @Test func parkingUsesSliverAndDisplayOrigin() {
        let frame = CGRect(x: 2000, y: 120, width: 400, height: 300)
        let display = CGRect(x: 1920, y: 100, width: 1000, height: 800)
        #expect(Layout.parkingFrame(for: frame, side: .right, display: display, others: [], sliver: 3)
                == CGRect(x: 2917, y: 120, width: 400, height: 300))
        #expect(Layout.parkingFrame(for: frame, side: .left, display: display, others: [], sliver: 3)
                == CGRect(x: 1523, y: 120, width: 400, height: 300))
        // A neighbor on the left blocks the left edge, so the right edge is used (same y, same sliver).
        let neighbor = [CGRect(x: 920, y: 100, width: 1000, height: 600)]
        #expect(Layout.parkingFrame(for: frame, side: .left, display: display, others: neighbor, sliver: 3)
                == CGRect(x: 2917, y: 120, width: 400, height: 300))
    }

    @Test func peekLimitedToHalfTowardNeighbor() {
        let neighbor = [CGRect(x: 1000, y: 0, width: 800, height: 600)]
        // Centered column 1: window 3 starts at 757.5, so 252.5 > 247.5 of it lies beyond the edge.
        // Parked: the right edge touches the neighbor, so the window goes to the opposite (left) edge.
        let centered = Layout.compute(input(threeColumns(scroll: 252.5), others: neighbor))
        #expect(centered.placements[3] == parked(-494, 0, 495, 800))
        #expect(centered.placements[2] == visible(252.5, 0, 495, 800))
        // Rambla 200: x = 810, 305 beyond.
        let farther = Layout.compute(input(threeColumns(scroll: 200), others: neighbor))
        #expect(farther.placements[3] == parked(-494, 0, 495, 800))
        // Without a neighbor the same window just peeks out.
        let free = Layout.compute(input(threeColumns(scroll: 252.5)))
        #expect(free.placements[3] == visible(757.5, 0, 495, 800))
        // Window 1 spills 252.5 to the left but there is no display on that side.
        #expect(centered.placements[1] == visible(-252.5, 0, 495, 800))
    }

    @Test func peekExactlyHalfStaysVisible() {
        let neighbor = [CGRect(x: 1000, y: 0, width: 800, height: 600)]
        // x = 752.5: exactly half (247.5) beyond the edge is allowed, only more than half parks.
        let r = Layout.compute(input(threeColumns(scroll: 257.5), others: neighbor))
        #expect(r.placements[3] == visible(752.5, 0, 495, 800))
    }

    @Test func peekLimitedToHalfAlsoOnTheLeft() {
        let neighbor = [CGRect(x: -800, y: 0, width: 800, height: 600)]
        // Rambla 300: window 1 sits at x = -300, 300 > 247.5 beyond the left edge.
        // Parked: the left edge touches the neighbor, so the window goes to the opposite (right) edge.
        let r = Layout.compute(input(threeColumns(scroll: 300), others: neighbor))
        #expect(r.placements[1] == parked(999, 0, 495, 800))
        #expect(r.placements[2] == visible(205, 0, 495, 800))
        // Rambla 200: 200 < 247.5, still a visible peek.
        #expect(Layout.compute(input(threeColumns(scroll: 200), others: neighbor)).placements[1]
                == visible(-200, 0, 495, 800))
        // Exactly half is still fine.
        #expect(Layout.compute(input(threeColumns(scroll: 247.5), others: neighbor)).placements[1]
                == visible(-247.5, 0, 495, 800))
    }

    @Test func peekNotLimitedWhenOverflowMissesTheOtherDisplays() {
        // The neighbor sits entirely below the strip's y range, so the part beyond the edge touches no display.
        let below = [CGRect(x: 1000, y: 900, width: 800, height: 600)]
        let r = Layout.compute(input(threeColumns(scroll: 200), others: below))
        #expect(r.placements[3] == visible(810, 0, 495, 800))
    }

    @Test func parkedColumnKeepsEachWindowsOwnYAndSize() {
        let stack = Column(windows: [1, 2], width: .fraction(0.5))
        let strip = Strip(columns: [stack,
                                    Column(windows: [3], width: .fraction(0.5)),
                                    Column(windows: [4], width: .fraction(0.5))], focused: 1, scroll: 505)
        let r = Layout.compute(input(strip))
        #expect(r.placements[1] == parked(-494, 0, 495, 395))
        #expect(r.placements[2] == parked(-494, 405, 495, 395))
        #expect(r.placements[3] == visible(0, 0, 495, 800))
        // The column rect stays unclamped even though its windows are parked.
        #expect(r.columnFrames[stack.id] == CGRect(x: -505, y: 0, width: 495, height: 800))
    }

    @Test func viewportInsideDisplay() {
        // Margins and the menu bar shrink the viewport, but parking is decided against the full display.
        let strip = threeColumns()
        let inp = LayoutInput(strip: strip, viewport: CGRect(x: 10, y: 25, width: 980, height: 765),
                              display: vp, config: cfg)
        let r = Layout.compute(inp)
        #expect(r.metrics.area == CGRect(x: 10, y: 25, width: 980, height: 765))
        #expect(r.metrics.widths == [485, 485, 485])
        #expect(r.placements[1] == visible(10, 25, 485, 765))
        #expect(r.placements[2] == visible(505, 25, 485, 765))
        #expect(r.placements[3] == parked(999, 25, 485, 765))
    }

    // MARK: - Compute: column content

    @Test func stackedSplit() {
        let col = Column(windows: [1, 2], width: .fraction(0.5))
        let r = Layout.compute(input(Strip(columns: [col], focused: 0)))
        #expect(r.placements[1] == visible(0, 0, 495, 395))
        #expect(r.placements[2] == visible(0, 405, 495, 395))
        #expect(r.tabBars.isEmpty)
        #expect(r.columnFrames[col.id] == CGRect(x: 0, y: 0, width: 495, height: 800))
    }

    @Test func stackedSplitFollowsWeights() {
        var col = Column(windows: [1, 2, 3], width: .fraction(0.5))
        col.heightWeights = [1, 2, 1]
        let r = Layout.compute(input(Strip(columns: [col], focused: 0)))
        // 800 - 2 * 10 = 780 split 1:2:1.
        #expect(near(frame(r, 1), CGRect(x: 0, y: 0, width: 495, height: 195)))
        #expect(near(frame(r, 2), CGRect(x: 0, y: 205, width: 495, height: 390)))
        #expect(near(frame(r, 3), CGRect(x: 0, y: 605, width: 495, height: 195)))
    }

    @Test func hiddenWindowInsideColumnIsSkipped() {
        let col = Column(windows: [1, 2, 3], width: .fraction(0.5))
        let r = Layout.compute(input(Strip(columns: [col], focused: 0), hidden: [2]))
        #expect(r.placements[2] == nil)
        #expect(r.placements[1] == visible(0, 0, 495, 395))
        #expect(r.placements[3] == visible(0, 405, 495, 395))
        // With a single visible window left it takes the full height.
        let single = Layout.compute(input(Strip(columns: [col], focused: 0), hidden: [2, 3]))
        #expect(single.placements[1] == visible(0, 0, 495, 800))
    }

    @Test func singleWindowHeightFractionTakesPrecedence() {
        var col = Column(windows: [1], width: .fraction(0.5))
        col.heightFraction = 0.5
        var c = cfg; c.keepOriginalHeight = true
        let r = Layout.compute(input(Strip(columns: [col], focused: 0), originalHeights: [1: 500], config: c))
        #expect(r.placements[1] == visible(0, 0, 495, 400))
    }

    @Test func keepOriginalHeight() {
        let strip = Strip(columns: [Column(windows: [1], width: .fraction(0.5))], focused: 0)
        var c = cfg; c.keepOriginalHeight = true
        let r = Layout.compute(input(strip, originalHeights: [1: 500], config: c))
        #expect(r.placements[1] == visible(0, 0, 495, 500))
        // Capped to the area, ignored without the flag or without a recorded height.
        #expect(Layout.compute(input(strip, originalHeights: [1: 5000], config: c)).placements[1] == visible(0, 0, 495, 800))
        #expect(Layout.compute(input(strip, originalHeights: [1: 500])).placements[1] == visible(0, 0, 495, 800))
        #expect(Layout.compute(input(strip, config: c)).placements[1] == visible(0, 0, 495, 800))
    }

    @Test func keepOriginalHeightOnlyAppliesToASingleWindow() {
        let col = Column(windows: [1, 2], width: .fraction(0.5))
        var c = cfg; c.keepOriginalHeight = true
        let r = Layout.compute(input(Strip(columns: [col], focused: 0), originalHeights: [1: 500, 2: 300], config: c))
        #expect(r.placements[1] == visible(0, 0, 495, 395))
        #expect(r.placements[2] == visible(0, 405, 495, 395))
    }

    @Test func tabbedColumn() {
        let col = Column(windows: [1, 2], width: .fraction(0.5), mode: .tabbed)
        let r = Layout.compute(input(Strip(columns: [col], focused: 0)))
        #expect(r.placements[1] == visible(0, 28, 495, 772))
        #expect(r.placements[2] == visible(0, 28, 495, 772))
        #expect(r.tabBars[col.id] == CGRect(x: 0, y: 0, width: 495, height: 28))
    }

    @Test func parkedTabbedColumnHasNoTabBar() {
        let tabs = Column(windows: [1, 2], width: .fraction(0.5), mode: .tabbed)
        let strip = Strip(columns: [tabs,
                                    Column(windows: [3], width: .fraction(0.5)),
                                    Column(windows: [4], width: .fraction(0.5))], focused: 1, scroll: 505)
        let r = Layout.compute(input(strip))
        #expect(r.tabBars[tabs.id] == nil)
        #expect(r.placements[1] == parked(-494, 28, 495, 772))
        #expect(r.placements[2] == parked(-494, 28, 495, 772))
        // Back in view, the bar returns.
        let back = Layout.compute(input(Strip(columns: strip.columns, focused: 0, scroll: 0)))
        #expect(back.tabBars[tabs.id] == CGRect(x: 0, y: 0, width: 495, height: 28))
    }

    @Test func columnFramesIncludeParkedColumnsUnclamped() {
        let strip = threeColumns(scroll: 505)
        let r = Layout.compute(input(strip))
        #expect(r.columnFrames[strip.columns[0].id] == CGRect(x: -505, y: 0, width: 495, height: 800))
        #expect(r.columnFrames[strip.columns[1].id] == CGRect(x: 0, y: 0, width: 495, height: 800))
        #expect(r.columnFrames[strip.columns[2].id] == CGRect(x: 505, y: 0, width: 495, height: 800))
        #expect(r.columnFrames.count == 3)
        #expect(r.metrics == Layout.metrics(input(strip)))
    }

    // MARK: - Compute: pinned columns

    @Test func pinnedLeftShrinksArea() {
        var s = threeColumns()
        s.columns[0].width = .fraction(0.25)
        s.columns[0].pinned = .left
        let r = Layout.compute(input(s))
        #expect(r.placements[1] == visible(0, 0, 242.5, 800))
        #expect(r.metrics.area.minX == 252.5)
        #expect(r.metrics.area.width == 747.5)
        #expect(r.placements[2] == visible(252.5, 0, 368.75, 800))
        #expect(r.placements[3] == visible(631.25, 0, 368.75, 800))
        #expect(r.columnFrames[s.columns[0].id] == CGRect(x: 0, y: 0, width: 242.5, height: 800))
        // The pinned column holds no strip space and consumes no gap.
        #expect(r.metrics.xs == [0, 0, 378.75])
        #expect(r.metrics.widths == [0, 368.75, 368.75])
        #expect(r.metrics.total == 747.5)
    }

    @Test func pinnedRightMirrorsLeft() {
        var s = threeColumns()
        s.columns[2].width = .fraction(0.25)
        s.columns[2].pinned = .right
        let r = Layout.compute(input(s))
        #expect(r.placements[3] == visible(757.5, 0, 242.5, 800))
        #expect(r.metrics.area == CGRect(x: 0, y: 0, width: 747.5, height: 800))
        #expect(r.placements[1] == visible(0, 0, 368.75, 800))
        #expect(r.placements[2] == visible(378.75, 0, 368.75, 800))
        #expect(r.columnFrames[s.columns[2].id] == CGRect(x: 757.5, y: 0, width: 242.5, height: 800))
    }

    @Test func pinnedOnBothSides() {
        var s = threeColumns()
        s.columns[0].width = .fraction(0.25); s.columns[0].pinned = .left
        s.columns[2].width = .fraction(0.25); s.columns[2].pinned = .right
        s.columns[1].width = .fraction(1)
        let r = Layout.compute(input(s))
        #expect(r.metrics.area == CGRect(x: 252.5, y: 0, width: 495, height: 800))
        #expect(r.placements[1] == visible(0, 0, 242.5, 800))
        #expect(r.placements[2] == visible(252.5, 0, 495, 800))
        #expect(r.placements[3] == visible(757.5, 0, 242.5, 800))
    }

    @Test func pinnedColumnsNeverPark() {
        var s = threeColumns(scroll: 5000)
        s.columns[0].width = .fraction(0.25)
        s.columns[0].pinned = .left
        let r = Layout.compute(input(s))
        #expect(r.placements[1] == visible(0, 0, 242.5, 800))
        // The strip columns scrolled far out of view are parked, not the pinned one.
        #expect(isParked(r.placements[2]))
        #expect(isParked(r.placements[3]))
    }

    @Test func pinnedColumnsStayVisibleEvenOutsideTheDisplay() {
        // Hostile geometry: the display is narrower than the viewport and a neighbor covers the rest, so a pinned
        // column would be parked right by the strip rules. Pinned columns are exempt from them.
        var s = threeColumns()
        s.columns[2].width = .fraction(0.25)
        s.columns[2].pinned = .right
        let narrow = CGRect(x: 0, y: 0, width: 500, height: 800)
        let neighbor = [CGRect(x: 500, y: 0, width: 500, height: 800)]
        let r = Layout.compute(LayoutInput(strip: s, viewport: vp, display: narrow, otherDisplays: neighbor, config: cfg))
        #expect(r.placements[3] == visible(757.5, 0, 242.5, 800))
    }

    @Test func pinnedTabbedColumnUsesTheFullViewportHeight() {
        let tabs = Column(windows: [1, 2], width: .fraction(0.25), mode: .tabbed)
        var pinned = tabs
        pinned.pinned = .left
        let strip = Strip(columns: [pinned, Column(windows: [3], width: .fraction(0.5))], focused: 1)
        let r = Layout.compute(input(strip))
        #expect(r.placements[1] == visible(0, 28, 242.5, 772))
        #expect(r.placements[2] == visible(0, 28, 242.5, 772))
        #expect(r.tabBars[pinned.id] == CGRect(x: 0, y: 0, width: 242.5, height: 28))
    }

    @Test func pinnedStackFollowsStackedRules() {
        var stack = Column(windows: [1, 2], width: .fraction(0.25))
        stack.pinned = .right
        let strip = Strip(columns: [Column(windows: [3], width: .fraction(0.5)), stack], focused: 0)
        let r = Layout.compute(input(strip))
        #expect(r.placements[1] == visible(757.5, 0, 242.5, 395))
        #expect(r.placements[2] == visible(757.5, 405, 242.5, 395))
    }

    @Test func collapsedPinnedColumnReservesNoSpace() {
        var s = threeColumns()
        s.columns[0].width = .fraction(0.25)
        s.columns[0].pinned = .left
        let r = Layout.compute(input(s, hidden: [1]))
        #expect(r.metrics.area == vp)
        #expect(r.placements[1] == nil)
        #expect(r.columnFrames[s.columns[0].id] == nil)
        #expect(r.placements[2] == visible(0, 0, 495, 800))
    }

    @Test func extraPinnedColumnOnTheSameSideStaysInTheStrip() {
        // The model allows one pinned column per side; if that is ever violated no window may disappear.
        var s = threeColumns()
        s.columns[0].width = .fraction(0.25); s.columns[0].pinned = .left
        s.columns[1].pinned = .left
        let r = Layout.compute(input(s))
        #expect(r.placements[1] == visible(0, 0, 242.5, 800))
        #expect(r.placements[2] == visible(252.5, 0, 368.75, 800))
        #expect(r.placements[3] == visible(631.25, 0, 368.75, 800))
    }

    // MARK: - Types

    @Test func placementFrame() {
        let r = CGRect(x: 1, y: 2, width: 3, height: 4)
        #expect(Placement.visible(r).frame == r)
        #expect(Placement.parked(r).frame == r)
        #expect(Placement.visible(r) != Placement.parked(r))
    }

    @Test func configDefaults() {
        let c = LayoutConfig()
        #expect(c.gap == 8 && c.tabBarHeight == 28 && c.centerMode == .never)
        #expect(c.keepOriginalHeight == false && c.sliver == 1)
    }
}
