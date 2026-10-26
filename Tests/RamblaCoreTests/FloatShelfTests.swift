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
                appHidden: Bool = false, dragged: Bool = false, parked: Bool = false,
                severalSpaces: Bool = false) -> FloatShelf.Window {
        FloatShelf.Window(id: id, display: display, isOnScreen: onScreen, isMinimized: minimized,
                          appIsHidden: appHidden, isDragged: dragged, isParked: parked,
                          isOnSeveralSpaces: severalSpaces)
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

    @Test func aFloatOnEveryDesktopStaysInView() {
        // Assigned to all desktops: it is in view on every strip, as on every desktop.
        #expect(FloatShelf.leaving([window(1, severalSpaces: true), window(2)], display: "A") == [2])
    }

    // MARK: - Where they go and where they come back

    @Test func aFloatParksLikeTheWindowsOfItsStrip() {
        // Left of the display's center: on the left edge with 1 pt showing; right of it, on the right edge. Its size
        // and y stay.
        let left = FloatShelf.Parked(frame: CGRect(x: 100, y: 200, width: 300, height: 400), display: display)
        #expect(FloatShelf.parkingFrame(left, display: display, others: [], sliver: 1)
                == CGRect(x: -299, y: 200, width: 300, height: 400))
        let right = FloatShelf.Parked(frame: CGRect(x: 500, y: 200, width: 300, height: 400), display: display)
        #expect(FloatShelf.parkingFrame(right, display: display, others: [], sliver: 1)
                == CGRect(x: 999, y: 200, width: 300, height: 400))
        // A display touching the right edge takes it: the window parks on the left one.
        let neighbor = CGRect(x: 1000, y: 0, width: 800, height: 600)
        #expect(FloatShelf.parkingFrame(right, display: display, others: [neighbor], sliver: 1)
                == CGRect(x: -299, y: 200, width: 300, height: 400))
    }

    @Test func aFloatComesBackToTheFrameItHad() {
        let frame = CGRect(x: 120, y: 80, width: 500, height: 300)
        let parked = FloatShelf.Parked(frame: frame, display: display)
        #expect(FloatShelf.returnFrame(parked, display: display, visible: visible, displays: [display]) == frame)
        // One the user left mostly off screen too: its display has not changed, so it comes back exactly there.
        let peeking = FloatShelf.Parked(frame: CGRect(x: 900, y: 80, width: 500, height: 300), display: display)
        #expect(FloatShelf.returnFrame(peeking, display: display, visible: visible, displays: [display])
                == peeking.frame)
    }

    @Test func aFloatKeepsItsPlaceOnItsDisplayWhenTheDisplaysMove() {
        // A monitor on the left of this display was unplugged: this display is the main one now, at the origin.
        let before = CGRect(x: 1920, y: -200, width: 1000, height: 800)
        let parked = FloatShelf.Parked(frame: CGRect(x: 2020, y: -100, width: 400, height: 300), display: before)
        #expect(FloatShelf.returnFrame(parked, display: display, visible: visible, displays: [display])
                == CGRect(x: 100, y: 100, width: 400, height: 300))
        #expect(FloatShelf.parkingFrame(parked, display: display, others: [], sliver: 1)
                == CGRect(x: -399, y: 100, width: 400, height: 300))
    }

    @Test func aFloatThatWouldComeBackOffScreenComesBackInView() {
        // The display got narrower while the window was parked: its place is off every display now. Less than half of
        // it in the area: centered across, and kept within the area.
        let wide = CGRect(x: 0, y: 0, width: 2000, height: 800)
        let gone = FloatShelf.Parked(frame: CGRect(x: 1500, y: 100, width: 400, height: 300), display: wide)
        #expect(FloatShelf.returnFrame(gone, display: display, visible: visible, displays: [display])
                == CGRect(x: 300, y: 100, width: 400, height: 300))
    }

    @Test func aFloatOnAnotherDisplayComesBackToTheSamePlaceThere() {
        // Taken to a desktop of another display: its place there is the same, from that display's corner.
        let other = CGRect(x: 1000, y: 0, width: 1200, height: 900)
        let parked = FloatShelf.Parked(frame: CGRect(x: 100, y: 100, width: 400, height: 300), display: display)
        #expect(FloatShelf.returnFrame(parked, display: other, visible: other, displays: [display, other])
                == CGRect(x: 1100, y: 100, width: 400, height: 300))
    }

    // MARK: - Into view

    @Test func aWindowMostlyOffEveryDisplayComesIntoView() {
        // Parked on an edge with 1 pt showing, and Rambla stopped before bringing it back: centered across.
        #expect(FloatShelf.inView(CGRect(x: 999, y: 100, width: 400, height: 300), visible: visible,
                                  displays: [display]) == CGRect(x: 300, y: 100, width: 400, height: 300))
        // A third of it on the display: pulled in through the nearest edges instead.
        #expect(FloatShelf.inView(CGRect(x: 800, y: 600, width: 400, height: 300), visible: visible,
                                  displays: [display]) == CGRect(x: 600, y: 500, width: 400, height: 300))
    }

    @Test func aWindowMostlyOnDisplaysStaysWhereItIs() {
        // Across two displays, though not on its own: the user left it there.
        let other = CGRect(x: 1000, y: 0, width: 800, height: 800)
        let across = CGRect(x: 800, y: 100, width: 400, height: 300)
        #expect(FloatShelf.inView(across, visible: visible, displays: [display, other]) == across)
        let inside = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(FloatShelf.inView(inside, visible: visible, displays: [display]) == inside)
    }

    // MARK: - Leaving the desktop of its strip

    @Test func aParkedFloatOnAnotherDesktopHasLeftItsStrip() {
        #expect(FloatShelf.isAway(spaces: [7], from: 3))
        // On several desktops (assigned to all of them), its own among them.
        #expect(FloatShelf.isAway(spaces: [3, 7], from: 3))
        // Still on its own, or macOS does not say.
        #expect(!FloatShelf.isAway(spaces: [3], from: 3))
        #expect(!FloatShelf.isAway(spaces: [], from: 3))
    }
}
