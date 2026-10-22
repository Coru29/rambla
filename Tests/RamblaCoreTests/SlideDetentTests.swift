import Testing
import Foundation
@testable import RamblaCore

// Sliding the strip by hand taps the trackpad like detents: each time the column it would land on, if let go now,
// changes. With speed, a flick lands on the next column, so the tap comes while the fingers are still on the trackpad.

/// Columns of `widths` side by side, 10 points apart, on a scroll area `area` wide.
private func metrics(_ widths: [Double], area: Double) -> StripMetrics {
    var xs: [Double] = []
    var x = 0.0
    for width in widths {
        xs.append(x)
        x += width + 10
    }
    return StripMetrics(xs: xs, widths: widths, total: x - 10, area: CGRect(x: 0, y: 0, width: area, height: 800))
}

/// Feeds `moves` (points, at seconds) to a detent from scroll 0 and returns which of them tap.
private func taps(_ m: StripMetrics, _ moves: [(points: Double, time: Double)]) -> [Bool] {
    var detent = SlideDetent()
    var scroll = 0.0
    return moves.map { move in
        scroll += move.points
        return detent.moved(by: move.points, to: scroll, in: m, at: move.time)
    }
}

@Test func aSlowSlideTapsAtEachColumnItPasses() {
    // Columns at 0, 510, 1020 and 1530 on a screen 1000 wide: let go without speed it lands at 0, 510, 1020 or the
    // end, 1030. Moves a second apart carry no speed.
    let m = metrics([500, 500, 500, 500], area: 1000)
    let slow = taps(m, [(0, 0), (200, 1), (100, 2), (300, 3), (200, 4), (235, 5), (-835, 6)])
    // 0 starts; 200 is still closest to 0; 300 to 510; 600 too; 800 to 1020; 1035 is the end, only 10 points
    // further, so the same detent; back to 200 in one move is one tap.
    #expect(slow == [false, false, true, false, true, false, true])
}

@Test func aQuickFlickTapsWhileTheFingersAreStillDown() {
    // 8 points every 10 ms is 800 points a second, a flick: let go, it would reach the next column, at 510.
    let m = metrics([500, 500, 500, 500], area: 1000)
    let flick = taps(m, [(0, 0), (8, 0.01), (8, 0.02), (8, 0.03)])
    #expect(flick == [false, true, false, false])
}

@Test func aLandingThatFlipsBackAndForthDoesNotBuzz() {
    // Fingers jerking back and forth across the first column every 10 ms flip where the strip would land each time:
    // taps stay at least `minimumInterval` apart.
    let m = metrics([500, 500, 500, 500], area: 1000)
    var moves: [(points: Double, time: Double)] = [(0, 0)]
    for step in 1...20 { moves.append((step % 2 == 1 ? 300 : -300, Double(step) * 0.01)) }
    let count = taps(m, moves).filter { $0 }.count
    #expect(count >= 2)
    #expect(count <= Int(0.2 / SlideDetent.minimumInterval) + 1)
}

@Test func aStripThatFitsNeverTaps() {
    let m = metrics([300, 300], area: 1000)
    let moves = (0...12).map { (points: $0 == 0 ? -200.0 : 50, time: Double($0)) }
    #expect(!taps(m, moves).contains(true))
}
