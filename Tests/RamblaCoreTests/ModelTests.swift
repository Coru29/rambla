import Testing
@testable import RamblaCore

@Test func fractionsFillExactly() {
    #expect(ColumnWidth.fraction(0.5).resolve(available: 1000, gap: 10) == 495)
    #expect(ColumnWidth.fraction(1).resolve(available: 1000, gap: 10) == 1000)
    #expect(abs(ColumnWidth.points(400).asFraction(available: 1000, gap: 10) - 410.0 / 1010.0) < 1e-9)
}

@Test func columnActiveWindowFallsBack() {
    var c = Column(windows: [7, 8], width: .fraction(0.5))
    c.active = 5
    #expect(c.activeWindow == 7)
}

@Test func collapsedWhenAllWindowsHidden() {
    let s = Strip(columns: [
        Column(windows: [1, 2], width: .fraction(0.5)),
        Column(windows: [3], width: .fraction(0.5)),
    ], focused: 0)
    #expect(s.isCollapsed(0, hidden: [1]) == false)
    #expect(s.isCollapsed(0, hidden: [1, 2]) == true)
    #expect(s.isCollapsed(1, hidden: []) == false)
}

@Test func visualOrderPutsPinnedAtEdges() {
    var a = Column(windows: [1], width: .fraction(0.5)); a.pinned = .right
    let b = Column(windows: [2], width: .fraction(0.5))
    var c = Column(windows: [3], width: .fraction(0.5)); c.pinned = .left
    let d = Column(windows: [4], width: .fraction(0.5))
    let s = Strip(columns: [a, b, c, d], focused: 1)
    #expect(s.visualOrder(hidden: []) == [2, 1, 3, 0])
    #expect(s.visualOrder(hidden: [4]) == [2, 1, 0])
}
