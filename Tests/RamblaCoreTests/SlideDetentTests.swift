import Testing
import Foundation
@testable import RamblaCore

// Sliding the strip by hand ticks on the trackpad like detents: once each time the column it would settle on changes.

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

@Test func aSlideTicksOncePerColumnItPasses() {
    // Columns at 0, 510, 1020 and 1530 on a screen 1000 wide: it settles at 0, 510, 1020 or the end, 1030.
    // 0 starts the slide; 200 is still closest to 0; 300 to 510; 600 too; 800 to 1020; 1035 is the end, only 10
    // points further, so the same detent; back to 0 in one move is one tick.
    let m = metrics([500, 500, 500, 500], area: 1000)
    var detent = SlideDetent()
    let ticks = [0.0, 200, 300, 600, 800, 1035, 200].map { detent.crossed(m, scroll: $0) }
    #expect(ticks == [false, false, true, false, true, false, true])
}

@Test func aStripThatFitsNeverTicks() {
    let m = metrics([300, 300], area: 1000)
    var detent = SlideDetent()
    let ticks = stride(from: -200.0, through: 400, by: 50).map { detent.crossed(m, scroll: $0) }
    #expect(!ticks.contains(true))
}
