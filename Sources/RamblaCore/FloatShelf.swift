import CoreGraphics

/// The floating windows that go with their strip: those the user floated (⌃⌘T) and those Rambla floated after another
/// app moved them. Each one belongs to the strip in view on its display when that strip leaves the view: it is parked
/// with it, out of sight like its windows, and comes back to its place with it. The floating windows of app rules, and
/// the dialogs and panels Rambla never arranges, are not Rambla's to move: they stay in view on every strip, and so
/// does a window on every desktop. Kept apart from the windows, so that the rules can be tested.
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
        /// Parked already, with another strip, or let go from one and not back at its place yet.
        public var isParked: Bool
        /// On more than one desktop (assigned to all of them).
        public var isOnSeveralSpaces: Bool

        public init(id: WindowID, display: String?, isOnScreen: Bool, isMinimized: Bool, appIsHidden: Bool,
                    isDragged: Bool, isParked: Bool, isOnSeveralSpaces: Bool) {
            self.id = id
            self.display = display
            self.isOnScreen = isOnScreen
            self.isMinimized = isMinimized
            self.appIsHidden = appIsHidden
            self.isDragged = isDragged
            self.isParked = isParked
            self.isOnSeveralSpaces = isOnSeveralSpaces
        }
    }

    /// The floating windows that go with the strip leaving the view on `display`, in the order given: those in view
    /// there, which are on screen, not minimized, of an app that is not hidden, not being dragged (it stays under the
    /// pointer), not parked with another strip already, and on one desktop only. `carried` is the focused one being
    /// sent along to the strip that comes into view: it stays in view.
    public static func leaving(_ windows: [Window], display: String, carried: WindowID? = nil) -> [WindowID] {
        windows.filter { window in
            window.display == display && window.isOnScreen && !window.isMinimized && !window.appIsHidden
                && !window.isDragged && !window.isParked && !window.isOnSeveralSpaces && window.id != carried
        }.map(\.id)
    }

    /// A floating window parked with its strip: the frame it had when the strip left the view, and the frame of its
    /// display then.
    public struct Parked: Equatable, Sendable {
        public var frame: CGRect
        public var display: CGRect

        public init(frame: CGRect, display: CGRect) {
            self.frame = frame
            self.display = display
        }
    }

    /// Where a parked window waits on `display`, its display's frame now, the way the windows of its strip do
    /// (`Layout.shelvedFrame`): from its place on the display, measured from the display's top-left corner as when it
    /// was parked, so that it parks right even when the displays moved meanwhile. `others` are the other displays, and
    /// `sliver` how much of it stays on `display`.
    public static func parkingFrame(_ parked: Parked, display: CGRect, others: [CGRect], sliver: Double) -> CGRect {
        Layout.shelvedFrame(for: place(parked, on: display), display: display, others: others, sliver: sliver)
    }

    /// Where a parked window comes back on `display`, its display's frame now: the frame it had, when that display has
    /// not changed. Otherwise (a display unplugged beside it changes the coordinates of the others, or it got smaller),
    /// its place on the display, measured from the display's top-left corner as when it was parked, and brought into
    /// `visible`, the display's area for windows, if most of it would lie off every display (`inView`).
    public static func returnFrame(_ parked: Parked, display: CGRect, visible: CGRect, displays: [CGRect]) -> CGRect {
        guard display != parked.display else { return parked.frame }
        return inView(place(parked, on: display), visible: visible, displays: displays)
    }

    /// `frame`, brought into `visible` (a display's area for windows) when most of it lies off every display in
    /// `displays`, the way "Traer todas las ventanas" brings a floating window in: across when less than half of it is
    /// in the area, and within its edges. Unchanged otherwise: a window the user left across two displays stays there.
    public static func inView(_ frame: CGRect, visible: CGRect, displays: [CGRect]) -> CGRect {
        let shown = displays.reduce(0.0) { sum, display in
            let part = frame.intersection(display)
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

    /// A parked window that macOS files under `spaces` (empty when it does not say) has left `space`, the desktop of
    /// its strip: it is on another one (the user took it there in Mission Control), or on several (assigned to all of
    /// them).
    public static func isAway(spaces: [UInt64], from space: UInt64) -> Bool {
        !spaces.isEmpty && (!spaces.contains(space) || spaces.count > 1)
    }

    /// Its frame moved with its display: the same place from the display's top-left corner.
    private static func place(_ parked: Parked, on display: CGRect) -> CGRect {
        parked.frame.offsetBy(dx: display.minX - parked.display.minX, dy: display.minY - parked.display.minY)
    }
}
