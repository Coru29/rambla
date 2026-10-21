import CoreGraphics
import Testing
@testable import RamblaCore

struct FrameChangeTests {
    let old = CGRect(x: 100, y: 50, width: 600, height: 800)

    @Test func terminalSnappingHeightKeepingBottomIsSelfResize() {
        // Cocoa keeps the bottom-left corner: in AX coordinates the top moves down by the height lost.
        #expect(FrameChange.isAnchoredResize(from: old, to: CGRect(x: 100, y: 62, width: 600, height: 788)))
    }

    @Test func widthChangeKeepingLeftEdgeIsSelfResize() {
        #expect(FrameChange.isAnchoredResize(from: old, to: CGRect(x: 100, y: 50, width: 640, height: 800)))
    }

    @Test func resizeKeepingRightAndBottomEdgesIsSelfResize() {
        #expect(FrameChange.isAnchoredResize(from: old, to: CGRect(x: 80, y: 40, width: 620, height: 810)))
    }

    @Test func pureMoveIsNotSelfResize() {
        #expect(!FrameChange.isAnchoredResize(from: old, to: CGRect(x: 300, y: 50, width: 600, height: 800)))
    }

    @Test func rectangleLeftHalfIsNotSelfResize() {
        #expect(!FrameChange.isAnchoredResize(from: old, to: CGRect(x: 0, y: 33, width: 756, height: 869)))
    }

    @Test func centeredShrinkIsNotSelfResize() {
        // Rectangle's "make smaller" moves both edges.
        #expect(!FrameChange.isAnchoredResize(from: old, to: CGRect(x: 115, y: 65, width: 570, height: 770)))
    }

    @Test func noChangeIsNotSelfResize() {
        #expect(!FrameChange.isAnchoredResize(from: old, to: old.offsetBy(dx: 1, dy: 1)))
    }
}
