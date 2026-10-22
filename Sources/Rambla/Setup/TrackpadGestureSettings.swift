import Foundation
import ObjectiveC

/// Changes macOS's horizontal trackpad swipes the way the Trackpad pane does: through the pane's own back end,
/// `MTTGestureBackEnd` in PreferencePanesSupport.framework. Setting a value there writes the preferences of both
/// trackpads and tells the system, so the change applies at once, exactly as if it was made in System Settings.
///
/// The pane offers no way to turn off only the four-finger swipe (its «3 dedos» choice keeps both on), which is why
/// Rambla does it itself. The back end is private API: everything is looked up at run time, and when anything is
/// missing the conflict row explains the manual change instead.
@MainActor
enum TrackpadGestureSettings {
    private nonisolated static let frameworkPath =
        "/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport"

    /// Whether the back end can be loaded. Checks without loading it: Rambla only loads it to make a change.
    nonisolated static var isAvailable: Bool { dlopen_preflight(frameworkPath) }

    /// Turns off macOS's horizontal swipe with `fingers` fingers (3 or 4) on this Mac and leaves the other one as it
    /// is. True when the back end took the change.
    static func turnOffSwipe(fingers: Int) -> Bool {
        guard fingers == 3 || fingers == 4, let backend = loadBackend() else { return false }
        let name = fingers == 3 ? "threeFingerHorizSwipe" : "fourFingerHorizSwipe"
        let getter = NSSelectorFromString(name)
        let setter = NSSelectorFromString("set" + name.prefix(1).uppercased() + name.dropFirst() + ":")
        guard backend.responds(to: getter), backend.responds(to: setter) else { return false }
        // This Mac only: the pane would also send the change to the user's other Macs through iCloud.
        let sync = NSSelectorFromString("setShouldSyncChangesToCloud:")
        if backend.responds(to: sync) {
            typealias SetFlag = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(backend.method(for: sync), to: SetFlag.self)(backend, sync, false)
        }
        typealias SetInt = @convention(c) (AnyObject, Selector, Int) -> Void
        typealias GetInt = @convention(c) (AnyObject, Selector) -> Int
        unsafeBitCast(backend.method(for: setter), to: SetInt.self)(backend, setter, 0)
        return unsafeBitCast(backend.method(for: getter), to: GetInt.self)(backend, getter) == 0
    }

    private static func loadBackend() -> NSObject? {
        guard dlopen(frameworkPath, RTLD_LAZY) != nil,
              let type = NSClassFromString("MTTGestureBackEnd") as? NSObject.Type else { return nil }
        let shared = NSSelectorFromString("sharedInstance")
        guard type.responds(to: shared) else { return nil }
        return type.perform(shared)?.takeUnretainedValue() as? NSObject
    }
}
