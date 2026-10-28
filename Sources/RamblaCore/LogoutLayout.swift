import Foundation

/// The layout a logout, a restart or a shutdown leaves for the next login. macOS quits the apps then, and Rambla takes
/// the windows of an app that quits out of their strips, as when the user quits it: saved then, the layout would come
/// back without them. So once a logout begins, the layout is saved as it was before the apps started to quit, and
/// saving is held while the logout goes on: until it is cancelled, or for `hold`.
///
/// Two signals say a logout began: loginwindow's notice, before it quits the apps, and Rambla being asked to quit for
/// it, which can come after macOS quit other apps. Windows of the layout that went away just before (a run of closings
/// at most `closingRun` apart, begun moments before) went with the logout, and the layout from before the first of them
/// is the one saved; a run the user began earlier, closing windows by hand, is theirs, and so is what it took away.
///
/// Times are seconds of a clock that never goes back (`ProcessInfo.systemUptime`).
public struct LogoutLayout: Sendable {
    public enum Signal: Sendable {
        /// loginwindow's notice that a logout, a restart or a shutdown began.
        case notice
        /// Rambla is asked to quit for a logout, a restart or a shutdown.
        case quit
    }

    /// Closings at most this far apart are one run.
    public static let closingRun: TimeInterval = 10
    /// A logout quits every app within moments: a run begun longer ago than this is the user's.
    public static let runAge: TimeInterval = 20
    /// How long saving stays held after a logout began: one cancelled with no notice leaves Rambla running, and one
    /// waiting on a "Save changes?" sheet goes on later.
    public static let hold: TimeInterval = 30 * 60
    /// A notice this long after saving was held is another logout (the one before was cancelled with no notice): the
    /// notices of one logout come moments apart.
    public static let newLogoutAfter: TimeInterval = 2 * 60

    /// How recent the last closing must be for `signal` to take the layout from before its run. A notice comes before
    /// macOS quits the apps, so only closings of the last moments may be its own; Rambla's quit may come after them.
    static func recent(_ signal: Signal) -> TimeInterval {
        signal == .notice ? 3 : closingRun
    }

    /// The layout from before the first closing of the latest run, when that run began, and its last closing.
    private var beforeClosings: SavedState?
    private var runStart: TimeInterval?
    private var lastClosing: TimeInterval?
    /// Saving is held from then until then.
    private var heldSince: TimeInterval?
    private var heldUntil: TimeInterval?
    /// Windows went away since saving was held: what was saved then stays.
    private var closedWhileHeld = false

    public init() {}

    public func isHeld(at now: TimeInterval) -> Bool { heldUntil.map { now < $0 } ?? false }

    /// How long saving stays held from `now`, nil when it is not.
    public func heldFor(at now: TimeInterval) -> TimeInterval? {
        heldUntil.flatMap { $0 > now ? $0 - now : nil }
    }

    /// A window of the layout (in a strip, or floating by the user's choice) goes away at `now`: closed, or gone with its
    /// app. `layout` gives the layout with it still in: asked only at the first closing of a run.
    public mutating func windowGoes(at now: TimeInterval, layout: () -> SavedState?) {
        if lastClosing.map({ now - $0 > Self.closingRun }) ?? true {
            beforeClosings = layout()
            runStart = now
        }
        lastClosing = now
        if isHeld(at: now) { closedWhileHeld = true }
    }

    /// A logout began at `now`, as `signal` says; `layout` is the layout as it is. Returns the layout to save, nil for
    /// none: there is none, or saving is held already for this logout and Rambla is now asked to quit, or windows went
    /// away since (the layout saved at its start stays). From then on saving is held.
    public mutating func logoutBegan(_ signal: Signal, at now: TimeInterval, layout: SavedState?) -> SavedState? {
        if let heldSince, isHeld(at: now) {
            if signal == .quit { return nil }
            if closedWhileHeld, now - heldSince < Self.newLogoutAfter { return nil }
        }
        heldSince = now
        heldUntil = now + Self.hold
        closedWhileHeld = false
        if let beforeClosings, let runStart, let lastClosing, now - lastClosing <= Self.recent(signal),
           now - runStart <= Self.runAge {
            return beforeClosings
        }
        return layout
    }

    /// The logout was cancelled, or Rambla quits for some other reason: saving goes on, and the windows that went
    /// meanwhile are gone for good.
    public mutating func logoutCancelled() {
        heldSince = nil
        heldUntil = nil
        closedWhileHeld = false
        beforeClosings = nil
        runStart = nil
        lastClosing = nil
    }
}
