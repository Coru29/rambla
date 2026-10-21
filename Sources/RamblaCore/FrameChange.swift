import CoreGraphics

/// Classifies a window frame change that Rambla did not make.
public enum FrameChange {
    /// True when the change is a resize that kept one corner in place on each axis (x or the right edge,
    /// y or the bottom edge): what an app does when it adjusts its own size (terminals snap to their
    /// character grid keeping a corner fixed). Moves by other apps (Rectangle, zoom) shift an edge that
    /// a self-resize keeps. Tolerance: 2 pt.
    public static func isAnchoredResize(from old: CGRect, to new: CGRect) -> Bool {
        let dx = new.minX - old.minX, dy = new.minY - old.minY
        let dw = new.width - old.width, dh = new.height - old.height
        guard abs(dw) > 2 || abs(dh) > 2 else { return false }
        let xAnchored = abs(dx) <= 2 || abs(dx + dw) <= 2
        let yAnchored = abs(dy) <= 2 || abs(dy + dh) <= 2
        return xAnchored && yAnchored
    }
}
