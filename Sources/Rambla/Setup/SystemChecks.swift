import AppKit
import ApplicationServices
import RamblaCore

struct CheckResult: Identifiable {
    enum Status { case ok, warning, info }
    let id: String
    let title: String
    let status: Status
    let detail: String
    let settingsURL: URL?
}

/// Reads macOS settings that affect Rambla ("Configuración → Mac").
///
/// This file only reads the system. What each value means (and the Spanish text of each row) is decided by
/// `MacChecks` in RamblaCore, which is where the tests are.
enum SystemChecks {
    static let rectangleBundleID = "com.knollsoft.Rectangle"
    /// The built-in trackpad and a Magic Trackpad keep their gesture settings in separate domains.
    private static let trackpadDomains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]

    /// Reads the system right now. Cheap enough to call again whenever the Mac page appears or the app becomes active.
    static func run(prefs: Preferences) -> [CheckResult] {
        MacChecks.evaluate(currentSettings(prefs: prefs), trackpad: prefs.trackpad).map(result(from:))
    }

    /// Everything `MacChecks` needs, as it is on this Mac at this moment.
    static func currentSettings(prefs: Preferences) -> MacSettings {
        MacSettings(
            accessibilityTrusted: AXIsProcessTrusted(),
            displaysShareSpaces: flag("spans-displays", in: "com.apple.spaces"),
            rearrangeSpaces: flag("mru-spaces", in: "com.apple.dock"),
            stageManager: flag("GloballyEnabled", in: "com.apple.WindowManager"),
            tilingByEdgeDrag: flag("EnableTilingByEdgeDrag", in: "com.apple.WindowManager"),
            tilingToMenuBar: flag("EnableTopTilingByEdgeDrag", in: "com.apple.WindowManager"),
            tilingWithOption: flag("EnableTilingOptionAccelerator", in: "com.apple.WindowManager"),
            threeFingerSwipe: trackpadDomains.compactMap { integer("TrackpadThreeFingerHorizSwipeGesture", in: $0) },
            fourFingerSwipe: trackpadDomains.compactMap { integer("TrackpadFourFingerHorizSwipeGesture", in: $0) },
            threeFingerDrag: trackpadDomains.compactMap { flag("TrackpadThreeFingerDrag", in: $0) },
            rectangle: isRectangleRunning ? .running(conflicts: rectangleConflicts(prefs: prefs)) : .notRunning)
    }

    static var isRectangleRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: rectangleBundleID).contains { !$0.isTerminated }
    }

    /// The Rambla shortcuts that Rectangle also binds: Rectangle's stored preferences applied on top of its default
    /// shortcut set. Does not check whether Rectangle is running.
    static func rectangleConflicts(prefs: Preferences) -> [ShortcutConflict] {
        let stored = CFPreferencesCopyMultiple(nil, rectangleBundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String: Any] ?? [:]
        return RectangleShortcuts.conflicts(ours: prefs.allShortcuts, theirs: RectangleShortcuts.effective(preferences: stored))
    }

    // MARK: Preferences

    /// The stored number (or boolean) for a key, or nil when the key is absent or holds something else.
    /// `CFPreferencesCopyAppValue` asks the preferences daemon, so it sees changes made in System Settings at once.
    private static func number(_ key: String, in domain: String) -> NSNumber? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber
    }

    private static func flag(_ key: String, in domain: String) -> Bool? {
        number(key, in: domain)?.boolValue
    }

    private static func integer(_ key: String, in domain: String) -> Int? {
        number(key, in: domain)?.intValue
    }

    private static func result(from check: MacCheck) -> CheckResult {
        let status: CheckResult.Status
        switch check.status {
        case .ok: status = .ok
        case .warning: status = .warning
        case .info: status = .info
        }
        return CheckResult(id: check.id, title: check.title, status: status, detail: check.detail, settingsURL: check.settingsURL)
    }
}
