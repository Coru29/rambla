import Testing
import CoreGraphics
@testable import RamblaCore

/// Floating windows that go with their strip. Display "A" is 1000×800 at the origin, with the area for windows under
/// a 25 pt menu bar, unless a test says otherwise.
struct FloatShelfTests {
    let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let visible = CGRect(x: 0, y: 25, width: 1000, height: 775)

    /// A floating window in view on display A, unless a test says otherwise.
    func window(_ id: WindowID, on display: String? = "A", onScreen: Bool = true, minimized: Bool = false,
                appHidden: Bool = false, dragged: Bool = false, parked: Bool = false) -> FloatShelf.Window {
        FloatShelf.Window(id: id, display: display, isOnScreen: onScreen, isMinimized: minimized,
                          appIsHidden: appHidden, isDragged: dragged, isParked: parked)
    }

    // MARK: - Which ones go

    @Test func theFloatsInViewOnTheDisplayGoWithItsStrip() {
        #expect(FloatShelf.leaving([window(1), window(2)], display: "A") == [1, 2])
    }

    @Test func floatsOfOtherDisplaysStay() {
        // Mostly on another display, or on none: the strip leaving display A does not take them.
        #expect(FloatShelf.leaving([window(1, on: "B"), window(2, on: nil), window(3)], display: "A") == [3])
    }

    @Test func floatsOutOfSightStay() {
        // Off screen, minimized, or of a hidden app: not in view, so they keep floating where they are.
        let windows = [window(1, onScreen: false), window(2, minimized: true), window(3, appHidden: true), window(4)]
        #expect(FloatShelf.leaving(windows, display: "A") == [4])
    }

    @Test func aDraggedFloatStaysUnderThePointer() {
        #expect(FloatShelf.leaving([window(1, dragged: true), window(2)], display: "A") == [2])
    }

    @Test func aFloatParkedWithAnotherStripStaysWithIt() {
        // Its sliver is on the display, but it belongs to the strip it was parked with.
        #expect(FloatShelf.leaving([window(1, parked: true), window(2)], display: "A") == [2])
    }

    @Test func theFloatSentAlongStaysInView() {
        #expect(FloatShelf.leaving([window(1), window(2)], display: "A", carried: 1) == [2])
        // Nothing else changes when the window sent along is none of them.
        #expect(FloatShelf.leaving([window(1), window(2)], display: "A", carried: 9) == [1, 2])
    }

    // MARK: - Where they go and where they come back

    @Test func aFloatParksLikeTheWindowsOfItsStrip() {
        // Left of the display's center: on the left edge with 1 pt showing; right of it, on the right edge. Its size
        // and y stay.
        let left = FloatShelf.offset(of: CGRect(x: 100, y: 200, width: 300, height: 400), on: display)
        #expect(FloatShelf.parkingFrame(offset: left, display: display, others: [], sliver: 1)
                == CGRect(x: -299, y: 200, width: 300, height: 400))
        let right = FloatShelf.offset(of: CGRect(x: 500, y: 200, width: 300, height: 400), on: display)
        #expect(FloatShelf.parkingFrame(offset: right, display: display, others: [], sliver: 1)
                == CGRect(x: 999, y: 200, width: 300, height: 400))
        // A display touching the right edge takes it: the window parks on the left one.
        let neighbor = CGRect(x: 1000, y: 0, width: 800, height: 600)
        #expect(FloatShelf.parkingFrame(offset: right, display: display, others: [neighbor], sliver: 1)
                == CGRect(x: -299, y: 200, width: 300, height: 400))
    }

    @Test func aFloatComesBackToItsPlace() {
        let frame = CGRect(x: 120, y: 80, width: 500, height: 300)
        let offset = FloatShelf.offset(of: frame, on: display)
        #expect(FloatShelf.returnFrame(offset: offset, display: display, visible: visible, displays: [display])
                == frame)
    }

    @Test func aFloatKeepsItsPlaceOnItsDisplayWhenTheDisplaysMove() {
        // A monitor on the left of this display was unplugged: this display is the main one now, at the origin.
        let before = CGRect(x: 1920, y: -200, width: 1000, height: 800)
        let offset = FloatShelf.offset(of: CGRect(x: 2020, y: -100, width: 400, height: 300), on: before)
        #expect(FloatShelf.returnFrame(offset: offset, display: display, visible: visible, displays: [display])
                == CGRect(x: 100, y: 100, width: 400, height: 300))
        #expect(FloatShelf.parkingFrame(offset: offset, display: display, others: [], sliver: 1)
                == CGRect(x: -399, y: 100, width: 400, height: 300))
    }

    @Test func aFloatThatWouldComeBackOffScreenComesBackInView() {
        // The display got narrower while the window was parked: its place is off every display now. Less than half of
        // it in the area: centered across, and kept within the area.
        let wide = CGRect(x: 0, y: 0, width: 2000, height: 800)
        let gone = FloatShelf.offset(of: CGRect(x: 1500, y: 100, width: 400, height: 300), on: wide)
        #expect(FloatShelf.returnFrame(offset: gone, display: display, visible: visible, displays: [display])
                == CGRect(x: 300, y: 100, width: 400, height: 300))
        // A third of it still on the display: pulled in through the nearest edges instead.
        let corner = FloatShelf.offset(of: CGRect(x: 800, y: 600, width: 400, height: 300), on: display)
        #expect(FloatShelf.returnFrame(offset: corner, display: display, visible: visible, displays: [display])
                == CGRect(x: 600, y: 500, width: 400, height: 300))
    }

    @Test func aFloatAcrossTwoDisplaysComesBackAcrossThem() {
        // Most of it is on displays, though not on its own: the user left it there.
        let other = CGRect(x: 1000, y: 0, width: 800, height: 800)
        let frame = CGRect(x: 800, y: 100, width: 400, height: 300)
        let offset = FloatShelf.offset(of: frame, on: display)
        #expect(FloatShelf.returnFrame(offset: offset, display: display, visible: visible, displays: [display, other])
                == frame)
    }
}
