import CoreGraphics
import RamblaCore

struct WindowSnapshot {
    let id: WindowID
    let pid: pid_t
    var traits: WindowTraits
    var frame: CGRect
    var title: String
}

/// What an AppWorker reports to the main thread. Frame events are only sent when something differs
/// from what the worker last wrote or observed, so the main thread never sees its own moves echoed.
enum AXEvent {
    case appWindows(pid_t, [WindowSnapshot])
    case windowCreated(WindowSnapshot)
    case windowDestroyed(pid_t, WindowID)
    case frameChanged(pid_t, WindowID, CGRect, mouseDown: Bool)
    case minimized(pid_t, WindowID, Bool)
    case titleChanged(pid_t, WindowID, String)
    case focusedWindow(pid_t, WindowID?)
    /// The app did not accept the requested frame (e.g. a minimum width); carries the real frame.
    case applied(pid_t, WindowID, CGRect)
}
