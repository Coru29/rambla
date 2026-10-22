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

    /// A 25 % column pinned on the left (window 1) followed by three 50 % strip columns (windows 2, 3, 4).
    /// The scroll area is 747.5 wide, so the strip columns are 368.75 wide at xs 0, 378.75 and 757.5 (total 1126.25).
    func leftPinStrip() -> Strip {
        var s = Strip(columns: [
            Column(windows: [1], width: .fraction(0.25)),
            Column(windows: [2], width: .fraction(0.5)),
            Column(windows: [3], width: .fraction(0.5)),
            Column(windows: [4], width: .fraction(0.5)),
        ], focused: 3)
        s.columns[0].pinned = .left
        return s
    }

    /// Mirror image: three 50 % strip columns (windows 1, 2, 3) followed by a 25 % column pinned on the right (window 4).
    func rightPinStrip() -> Strip {
        var s = Strip(columns: [
            Column(windows: [1], width: .fraction(0.5)),
            Column(windows: [2], width: .fraction(0.5)),
            Column(windows: [3], width: .fraction(0.5)),
            Column(windows: [4], width: .fraction(0.25)),
        ], focused: 0)
        s.columns[3].pinned = .right
        return s
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

    @Test func revealAndSettleUseTheScrollAreaWidthWithAPin() {
        // The 25 % pin shrinks the scroll area to 747.5. The array indices are pin 0 and strip columns 1, 2, 3
        // (xs 0, 378.75, 757.5, total 1126.25), so the farthest useful scroll is total - 747.5 = 378.75.
        // Against the 1000 wide viewport it would wrongly be 126.25.
        let m = Layout.metrics(input(leftPinStrip()))
        #expect(m.area.width == 747.5)
        #expect(m.xs == [0, 0, 378.75, 757.5])
        #expect(m.total == 1126.25)
        #expect(Layout.reveal(m, column: 3, current: 0, mode: .never) == m.total - 747.5)
        #expect(Layout.reveal(m, column: 3, current: 0, mode: .never) == 378.75)
        let settled = Layout.settle(m, scroll: 400)
        #expect(settled.scroll == 378.75)
        #expect(settled.column == 2)       // columns 2 and 3 tie in [378.75, 1126.25]: the lower index wins
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

    @Test func settleKeepsTheFocusedColumnAmongTheOnesSharingAStop() {
        // Widths [242.5, 747.5] fit in the area together: both columns' stops are 0, so a swipe changes nothing
        // and the focus stays where it was.
        let strip = Strip(columns: [Column(windows: [1], width: .fraction(0.25)),
                                    Column(windows: [2], width: .fraction(0.75))], focused: 0)
        let m = Layout.metrics(input(strip))
        #expect(m.total == 1000)
        #expect(Layout.settle(m, scroll: 0, velocity: 0, focused: 1) == (0, 1))
        #expect(Layout.settle(m, scroll: 0, velocity: 0, focused: 0) == (0, 0))
        #expect(Layout.settle(m, scroll: 0).column == 0)                 // nothing focused: the first one
    }

    @Test func aSwipeToTheEndFocusesTheLastColumnEvenWhenAWiderOneShowsMore() {
        // A 900 pt column before a 300 pt last one: xs 0, 610, 1520, total 1820, so the strip ends at 820. There
        // the wide column still shows 690 pt and the last one 300 pt, but the swipe went to the end: focusing the
        // wide column would scroll the strip back and the last column could never be reached.
        let strip = Strip(columns: [Column(windows: [1], width: .points(600)),
                                    Column(windows: [2], width: .points(900)),
                                    Column(windows: [3], width: .points(300))], focused: 1)
        let m = Layout.metrics(input(strip))
        #expect(m.xs == [0, 610, 1520] && m.total == 1820)
        let end = Layout.settle(m, scroll: 700, velocity: 2000, focused: 1)
        #expect(end.scroll == 820)
        #expect(end.column == 2)
        let back = Layout.settle(m, scroll: 700, velocity: -2000, focused: 2)
        #expect(back.scroll == 610 && back.column == 1)
    }

    @Test func settleFocusesTheColumnItLandsOn() {
        // Three 50 % columns at 0, 505, 1010 (the strip ends at 505). From the middle column, a swipe back to 0
        // lands on the first column even though the middle one is still fully on screen there.
        let m = Layout.metrics(input(threeColumns()))
        #expect(Layout.settle(m, scroll: 100, velocity: -1000, focused: 1) == (0, 0))
        #expect(Layout.settle(m, scroll: 400, velocity: 1000, focused: 0) == (505, 1))
    }

    @Test func settleWithoutColumns() {
        let none = Layout.settle(Layout.metrics(input(Strip())), scroll: 40)
        #expect(none.scroll == 0)
        #expect(none.column == nil)
        let collapsed = Layout.settle(Layout.metrics(input(threeColumns(), hidden: [1, 2, 3])), scroll: 40)
        #expect(collapsed.scroll == 0)
        #expect(collapsed.column == nil)
    }

    // MARK: - Settle after a flick

    /// Five 50 % columns at xs 0, 505, 1010, 1515 and 2020 (total 2515): the strip can scroll to 1515.
    func fiveColumns() -> Strip {
        Strip(columns: (1...5).map { Column(windows: [WindowID($0)], width: .fraction(0.5)) }, focused: 0)
    }

    @Test func settleWithoutVelocityIsThePlainSettle() {
        let m = Layout.metrics(input(fiveColumns()))
        for scroll in [-100.0, 0, 200, 252.5, 300, 760, 1300, 5000] {
            let plain = Layout.settle(m, scroll: scroll)
            let still = Layout.settle(m, scroll: scroll, velocity: 0)
            #expect(still.scroll == plain.scroll && still.column == plain.column, "scroll \(scroll)")
        }
    }

    @Test func aFlickReachesTheNextColumnAfterAShortMove() {
        // 400 pt/s is past the flick threshold of 0.3 area widths per second (300 pt/s here).
        let m = Layout.metrics(input(fiveColumns()))
        let forward = Layout.settle(m, scroll: 600, velocity: 400)     // the nearest column is still 505
        #expect(forward.scroll == 1010 && forward.column == 2)
        let back = Layout.settle(m, scroll: 450, velocity: -400)       // the nearest column is still 505
        #expect(back.scroll == 0 && back.column == 0)
    }

    @Test func aSlowReleaseSettlesOnTheNearestColumn() {
        let m = Layout.metrics(input(fiveColumns()))
        let slow = Layout.settle(m, scroll: 600, velocity: 200)        // glides 20 pt, to 620
        #expect(slow.scroll == 505 && slow.column == 1)
    }

    @Test func theFlickDirectionBeatsTheNearestColumn() {
        let m = Layout.metrics(input(fiveColumns()))
        let r = Layout.settle(m, scroll: 900, velocity: -400)          // 1010 is nearer, but the flick goes left
        #expect(r.scroll == 505 && r.column == 1)
    }

    @Test func aFastFlickGlidesPastSeveralColumns() {
        let m = Layout.metrics(input(fiveColumns()))
        let r = Layout.settle(m, scroll: 600, velocity: 9000)          // glides 900 pt, to 1500
        #expect(r.scroll == 1515)
        #expect(r.column == 3)                                         // columns 3 and 4 tie: the lower index wins
    }

    @Test func aFlickGlidesAtMostOneAndAHalfScreens() {
        // A stalled main thread delivers queued events at once and the measured speed spikes: the glide is capped
        // so the strip lands a few columns away instead of at the far end.
        let strip = Strip(columns: (1...10).map { Column(windows: [WindowID($0)], width: .fraction(0.5)) }, focused: 0)
        let m = Layout.metrics(input(strip))
        #expect(Layout.settle(m, scroll: 0, velocity: 1_000_000).scroll == 1515)
        #expect(Layout.settle(m, scroll: 4040, velocity: -1_000_000).scroll == 2525)
    }

    @Test func aFlickStopsAtTheEndsOfTheStrip() {
        let m = Layout.metrics(input(fiveColumns()))
        let end = Layout.settle(m, scroll: 1515, velocity: 4000)
        #expect(end.scroll == 1515)
        let start = Layout.settle(m, scroll: 0, velocity: -4000)
        #expect(start.scroll == 0 && start.column == 0)
        let none = Layout.settle(Layout.metrics(input(Strip())), scroll: 40, velocity: 4000)
        #expect(none.scroll == 0 && none.column == nil)
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
        // At scroll 200: x = 810, 305 beyond.
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
        // At scroll 300: window 1 sits at x = -300, 300 > 247.5 beyond the left edge.
        // Parked: the left edge touches the neighbor, so the window goes to the opposite (right) edge.
        let r = Layout.compute(input(threeColumns(scroll: 300), others: neighbor))
        #expect(r.placements[1] == parked(999, 0, 495, 800))
        #expect(r.placements[2] == visible(205, 0, 495, 800))
        // At scroll 200: 200 < 247.5, still a visible peek.
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

    @Test func stackedWeightsSkipHiddenWindows() {
        var col = Column(windows: [1, 2, 3], width: .fraction(0.5))
        col.heightWeights = [1, 2, 3]
        let strip = Strip(columns: [col], focused: 0)
        // Window 1 hidden: windows 2 and 3 share 800 - 10 = 790 as 2:3, so 316 and 474.
        let first = Layout.compute(input(strip, hidden: [1]))
        #expect(first.placements[1] == nil)
        #expect(near(frame(first, 2), CGRect(x: 0, y: 0, width: 495, height: 316)))
        #expect(near(frame(first, 3), CGRect(x: 0, y: 326, width: 495, height: 474)))
        // Window 2 hidden instead: windows 1 and 3 keep their own weights (1:3), so 197.5 and 592.5.
        let middle = Layout.compute(input(strip, hidden: [2]))
        #expect(middle.placements[2] == nil)
        #expect(near(frame(middle, 1), CGRect(x: 0, y: 0, width: 495, height: 197.5)))
        #expect(near(frame(middle, 3), CGRect(x: 0, y: 207.5, width: 495, height: 592.5)))
    }

    @Test func heightsNeverDropBelowOnePoint() {
        var keep = cfg
        keep.keepOriginalHeight = true
        // A single window whose fraction or recorded original height is zero or negative.
        var zeroFraction = Column(windows: [1], width: .fraction(0.5)); zeroFraction.heightFraction = 0
        var negativeFraction = Column(windows: [2], width: .fraction(0.5)); negativeFraction.heightFraction = -0.5
        let singles = Strip(columns: [zeroFraction, negativeFraction,
                                      Column(windows: [3], width: .fraction(0.5)),
                                      Column(windows: [4], width: .fraction(0.5))], focused: 0)
        let single = Layout.compute(input(singles, originalHeights: [3: 0, 4: -20], config: keep))
        for id: WindowID in 1...4 { #expect(frame(single, id).height == 1, "window \(id)") }

        // A zero (or negative) weight among positive ones leaves that window one point tall, not empty.
        for weights in [[1.0, 0.0, 1.0], [1.0, -2.0, 1.0]] {
            var stack = Column(windows: [5, 6, 7], width: .fraction(0.5))
            stack.heightWeights = weights
            let r = Layout.compute(input(Strip(columns: [stack], focused: 0)))
            #expect(frame(r, 5).height == 390, "weights \(weights)")
            #expect(frame(r, 6).height == 1, "weights \(weights)")
            #expect(frame(r, 7).height == 390, "weights \(weights)")
            #expect(frame(r, 6).minY >= frame(r, 5).maxY && frame(r, 7).minY >= frame(r, 6).maxY, "weights \(weights)")
        }

        // A tabbed column in an area shorter than its tab bar.
        let tabs = Column(windows: [8], width: .fraction(0.5), mode: .tabbed)
        let tall = LayoutConfig(gap: 10, tabBarHeight: 900)
        #expect(frame(Layout.compute(input(Strip(columns: [tabs], focused: 0), config: tall)), 8).height == 1)
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

    // MARK: - Compute: strip columns next to pinned columns

    @Test func columnUnderLeftPinIsParked() {
        var s = leftPinStrip()
        // Focusing the last column scrolls the strip to the end: 757.5 + 368.75 - 747.5.
        s.scroll = Layout.reveal(Layout.metrics(input(s)), column: 3, current: 0, mode: .never)
        #expect(s.scroll == 378.75)
        let r = Layout.compute(input(s))
        // Window 2 would land at (-126.25, 0, 368.75, 800), right on top of the pinned window, so it parks instead.
        #expect(r.columnFrames[s.columns[1].id] == CGRect(x: -126.25, y: 0, width: 368.75, height: 800))
        #expect(r.placements[2] == parked(-367.75, 0, 368.75, 800))
        // The pin and the columns that fit in the scroll area are untouched.
        #expect(r.placements[1] == visible(0, 0, 242.5, 800))
        #expect(r.placements[3] == visible(252.5, 0, 368.75, 800))
        #expect(r.placements[4] == visible(631.25, 0, 368.75, 800))
    }

    @Test func columnUnderRightPinIsParked() {
        var s = rightPinStrip()
        // Coming back from the end of the strip, focusing the first column scrolls to the start.
        s.scroll = Layout.reveal(Layout.metrics(input(s)), column: 0, current: 378.75, mode: .never)
        #expect(s.scroll == 0)
        let r = Layout.compute(input(s))
        // Window 3 would land at (757.5, 0, 368.75, 800), right on top of the pinned window, so it parks instead.
        #expect(r.columnFrames[s.columns[2].id] == CGRect(x: 757.5, y: 0, width: 368.75, height: 800))
        #expect(r.placements[3] == parked(999, 0, 368.75, 800))
        #expect(r.placements[4] == visible(757.5, 0, 242.5, 800))
        #expect(r.placements[1] == visible(0, 0, 368.75, 800))
        #expect(r.placements[2] == visible(378.75, 0, 368.75, 800))
    }

    @Test func columnFlushAgainstAPinStaysVisible() {
        // Left: window 2 starts exactly where the scroll area starts, 10 pt right of the pinned window.
        let left = Layout.compute(input(leftPinStrip()))
        #expect(left.placements[2] == visible(252.5, 0, 368.75, 800))
        #expect(left.placements[3] == visible(631.25, 0, 368.75, 800))
        // Right: window 2 ends exactly where the scroll area ends, 10 pt left of the pinned window.
        let right = Layout.compute(input(rightPinStrip()))
        #expect(right.placements[2] == visible(378.75, 0, 368.75, 800))
    }

    @Test func revealedColumnNeverParksNextToAPin() {
        // Gaps, fractions and pin widths that are not exact in binary: a column revealed flush against a pin then only
        // sits on the scroll area's edge up to rounding noise (some of these combinations land a hair past it), and
        // must not be mistaken for one that pokes under the pin.
        for gap in [3.3, 7.3] {
            let config = LayoutConfig(gap: gap)
            for fraction in [0.3, 0.35] {
                for (leftPin, rightPin) in [(0.17, 0.0), (0.0, 0.13), (0.17, 0.13), (0.19, 0.11), (0.23, 0.0)] {
                    var columns = (1...5).map { Column(windows: [WindowID($0)], width: .fraction(fraction)) }
                    if leftPin > 0 {
                        var pin = Column(windows: [10], width: .fraction(leftPin)); pin.pinned = .left
                        columns.insert(pin, at: 0)
                    }
                    if rightPin > 0 {
                        var pin = Column(windows: [11], width: .fraction(rightPin)); pin.pinned = .right
                        columns.append(pin)
                    }
                    let strip = Strip(columns: columns, focused: 0)
                    let m = Layout.metrics(input(strip, config: config))
                    for index in columns.indices where columns[index].pinned == nil {
                        for current in [-1000.0, 1000.0] {      // arrive flush right, then flush left
                            var s = strip
                            s.scroll = Layout.reveal(m, column: index, current: current, mode: .never)
                            let id = columns[index].windows[0]
                            let placement = Layout.compute(input(s, config: config)).placements[id]
                            #expect(!isParked(placement),
                                    "gap \(gap), fraction \(fraction), pins \(leftPin)/\(rightPin), column \(index), from \(current)")
                        }
                    }
                }
            }
        }
    }

    @Test func anyOverlapWithAPinParksTheColumn() {
        // The strip columns start at the scroll area's edge, which is the pinned window plus its gap (252.5).
        var left = leftPinStrip()
        for scroll in [0.5, 5, 100] {        // just into the gap, into the gap, over the pinned window
            left.scroll = scroll
            #expect(isParked(Layout.compute(input(left)).placements[2]), "left pin, scroll \(scroll)")
        }
        // Next to the pin there is no peeking: the half rule toward a neighbor display does not apply on a pinned side.
        left.scroll = 100                    // window 2 is 100 pt past the area's edge, well under half its width
        let leftNeighbor = [CGRect(x: -800, y: 0, width: 800, height: 600)]
        #expect(isParked(Layout.compute(input(left, others: leftNeighbor)).placements[2]))

        var right = rightPinStrip()
        for scroll in [-0.5, -5, -100] {     // window 2 ends 0.5, 5, 100 pt past the area's right edge
            right.scroll = scroll
            #expect(isParked(Layout.compute(input(right)).placements[2]), "right pin, scroll \(scroll)")
        }
    }

    @Test func columnsParkAtBothPins() {
        var s = threeColumns()
        s.columns[0].width = .fraction(0.25); s.columns[0].pinned = .left
        s.columns[2].width = .fraction(0.25); s.columns[2].pinned = .right
        s.columns[1].width = .fraction(1)          // 495: exactly the scroll area, 252.5...747.5
        // Flush against both pins it is fully visible.
        #expect(Layout.compute(input(s)).placements[2] == visible(252.5, 0, 495, 800))
        s.scroll = 10                              // 10 pt under the left pin
        #expect(Layout.compute(input(s)).placements[2] == parked(-494, 0, 495, 800))
        s.scroll = -10                             // 10 pt under the right pin
        #expect(Layout.compute(input(s)).placements[2] == parked(999, 0, 495, 800))
    }

    @Test func sidesWithoutAPinKeepTheDisplayRules() {
        // Left pin only. At scroll 100 window 4 sits at 252.5 + 757.5 - 100 = 910, 278.75 past the display's right edge.
        var left = leftPinStrip()
        left.scroll = 100
        #expect(Layout.compute(input(left)).placements[4] == visible(910, 0, 368.75, 800))
        // Toward a neighbor display that is more than half its width, so it parks (opposite edge: the right one is taken).
        let neighbor = [CGRect(x: 1000, y: 0, width: 800, height: 600)]
        #expect(Layout.compute(input(left, others: neighbor)).placements[4] == parked(-367.75, 0, 368.75, 800))
        left.scroll = 200                          // x = 810, 178.75 past the edge: less than half (184.375)
        #expect(Layout.compute(input(left, others: neighbor)).placements[4] == visible(810, 0, 368.75, 800))
        // Right pin only: the unpinned left side still lets window 1 peek past the display's left edge.
        var right = rightPinStrip()
        right.scroll = 100
        #expect(Layout.compute(input(right)).placements[1] == visible(-100, 0, 368.75, 800))
    }

    @Test func collapsedPinDoesNotParkColumnsUnderIt() {
        // With the pinned window hidden the side has no pin, so the plain display rules apply again.
        var s = leftPinStrip()
        s.scroll = 100
        let r = Layout.compute(input(s, hidden: [1]))
        #expect(r.metrics.area == vp)
        #expect(r.placements[2] == visible(-100, 0, 495, 800))
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
