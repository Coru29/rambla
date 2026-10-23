/// Where the focus goes when it lands on a window of a level out of view (another strip of the same stack): to that
/// level, to a window of the level in view instead, or to Rambla itself. The user never types into a window they cannot
/// see, and is never taken to another strip by something macOS did on its own.
///
/// It works like macOS's own desktops. Choosing that window (Mission Control, the Window menu, ⌘`, a click, bringing it
/// back from the Dock) goes to its level, and so does activating its app (⌘Tab, the Dock, a notification), unless that
/// app has windows in the level in view: the last one used of those gets the focus instead. When macOS moves the focus
/// by itself, because the focused window closed or was minimized or an app was hidden or quit, the level in view stays.
public enum FocusRoute: Equatable, Sendable {
    /// In view, or a late report right after Rambla switched: nothing special to do.
    case none
    /// Go to the window's level.
    case switchLevel
    /// Focus this window of the level in view instead.
    case redirect(WindowID)
    /// Nothing in view to give the focus to: Rambla takes the keyboard (as on an empty strip).
    case takeKeyboard

    /// Seconds after Rambla switches a stack's level during which a report of focus on a window of another level is
    /// late: the app that was in front reports its window, now out of view, before the next one takes over. Also how
    /// long after a loss a focus that lands out of view is macOS's doing.
    public static let lateReportWindow = 0.6

    /// `windowLevel`: where the focused window is; `active`: the level in view. `byActivation`: its app was just
    /// activated (⌘Tab, the Dock, a notification). `afterLoss`: the focused window just closed or was minimized, or an
    /// app was just hidden or quit, so macOS moved the focus by itself. `chosen`: the user picked that very window,
    /// bringing it back from the Dock, which wins over its app's activation and is never a late report.
    /// `appWindowsInView`: that app's windows in the level in view, most recently used first; `windowsInView`: every
    /// window there, most recently used first. `sinceOwnSwitch`: seconds since Rambla itself switched this stack's
    /// level (nil: long ago).
    public static func decide(windowLevel: Int, active: Int, byActivation: Bool, afterLoss: Bool, chosen: Bool = false,
                              appWindowsInView: [WindowID], windowsInView: [WindowID],
                              sinceOwnSwitch: Double?) -> FocusRoute {
        if windowLevel == active { return .none }
        // macOS moving the focus by itself never changes the level, even when it activates the next app (a quit).
        if afterLoss {
            guard let window = appWindowsInView.first ?? windowsInView.first else { return .takeKeyboard }
            return .redirect(window)
        }
        if chosen { return .switchLevel }
        if !byActivation, let since = sinceOwnSwitch, since < lateReportWindow { return .none }
        if byActivation, let window = appWindowsInView.first { return .redirect(window) }
        return .switchLevel
    }

    /// `windows`, given in strip order, the most recently used first (`lastUsed`: when each one last had the focus).
    /// Those never used go last, and ties keep the order given.
    public static func byLastUse(_ windows: [WindowID], lastUsed: [WindowID: Double]) -> [WindowID] {
        windows.enumerated().sorted { a, b in
            switch (lastUsed[a.element], lastUsed[b.element]) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }
}
