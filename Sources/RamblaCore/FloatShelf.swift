import CoreGraphics

/// The floating windows that go with their strip: those the user floated (⌃⌘T) and those Rambla floated after another
/// app moved them. Each one belongs to the strip in view on its display when that strip leaves the view: it is parked
/// with it, out of sight like its windows, and comes back to its place with it. The floating windows of app rules, and
/// the dialogs and panels Rambla never arranges, are not Rambla's to move: they stay in view on every strip. Kept apart
/// from the windows, so that the rules can be tested.
public enum FloatShelf {
    /// What is known of a floating window as the strip in view on a display leaves it.
    public struct Window: Equatable, Sendable {
        public var id: WindowID
        /// The display it lies mostly on, by uuid; nil when it is on none.
        public var display: String?
        /// The WindowServer shows it.
        public var isOnScreen: Bool
        public var isMinimized: Bool
        public var appIsHidden: Bool
        /// The user is dragging it.
        public var isDragged: Bool
        /// Parked already, with another strip.
        public var isParked: Bool

        public init(id: WindowID, display: String?, isOnScreen: Bool, isMinimized: Bool, appIsHidden: Bool,
                    isDragged: Bool, isParked: Bool) {
            self.id = id
            self.display = display
            self.isOnScreen = isOnScreen
            self.isMinimized = isMinimized
            self.appIsHidden = appIsHidden
            self.isDragged = isDragged
            self.isParked = isParked
        }
    }

    /// The floating windows that go with the strip leaving the view on `display`, in the order given: those in view
    /// there, which are on screen, not minimized, of an app that is not hidden, not being dragged (it stays under the
    /// pointer) and not parked with another strip already. `carried` is the focused one being sent along to the strip
    /// that comes into view: it stays in view.
    public static func leaving(_ windows: [Window], display: String, carried: WindowID? = nil) -> [WindowID] {
        windows.filter { window in
            window.display == display && window.isOnScreen && !window.isMinimized && !window.appIsHidden
                && !window.isDragged && !window.isParked && window.id != carried
        }.map(\.id)
    }

    /// What the shelf keeps of a window's frame: its place on `display`, from the display's top-left corner. The
    /// displays can move while the strip is out of view (a display unplugged beside it changes the coordinates of the
    /// others), and the window comes back to the same place on its display.
    public static func offset(of frame: CGRect, on display: CGRect) -> CGRect {
        frame.offsetBy(dx: -display.minX, dy: -display.minY)
    }

    /// Where a window kept at `offset` parks on `display`, the way the windows of its strip do (`Layout.shelvedFrame`):
    /// `others` are the other displays, and `sliver` how much of it stays on `display`.
    public static func parkingFrame(offset: CGRect, display: CGRect, others: [CGRect], sliver: Double) -> CGRect {
        Layout.shelvedFrame(for: place(offset, on: display), display: display, others: others, sliver: sliver)
    }

    /// Where a window kept at `offset` comes back on `display`: its place there, unless most of it would lie off
    /// every display (`displays`), as when the display got smaller meanwhile. Then it comes into `visible`, the
    /// display's area for windows, the way "Traer todas las ventanas" brings a window in: across when less than half
    /// of it would be in the area, and within its edges. No floating window is lost off screen.
    public static func returnFrame(offset: CGRect, display: CGRect, visible: CGRect, displays: [CGRect]) -> CGRect {
        let frame = place(offset, on: display)
        let shown = displays.reduce(0.0) { sum, other in
            let part = frame.intersection(other)
            return sum + (part.isNull ? 0 : Double(part.width * part.height))
        }
        guard shown < Double(frame.width * frame.height) / 2 else { return frame }
        var target = frame
        let inArea = frame.intersection(visible)
        if (inArea.isNull ? 0 : inArea.width) < frame.width / 2 { target.origin.x = visible.midX - frame.width / 2 }
        target.origin.x = min(max(target.minX, visible.minX), max(visible.minX, visible.maxX - target.width))
        target.origin.y = min(max(target.minY, visible.minY), max(visible.minY, visible.maxY - target.height))
        return target
    }

    private static func place(_ offset: CGRect, on display: CGRect) -> CGRect {
        offset.offsetBy(dx: display.minX, dy: display.minY)
    }
}
