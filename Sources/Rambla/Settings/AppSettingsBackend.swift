import AppKit
import RamblaCore

/// The running app's side of the settings window.
@MainActor
final class AppSettingsBackend: SettingsBackend {
    private static let rectangleID = "com.knollsoft.Rectangle"

    var displays: [(uuid: String, name: String)] {
        Displays.current().map { ($0.uuid, $0.name) }
    }

    var runningApps: [(bundleID: String, name: String, icon: NSImage?)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != WindowManager.ownBundleID }
            .map { ($0.bundleIdentifier!, $0.localizedName ?? $0.bundleIdentifier!, $0.icon) }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    var hotkeyFailures: Set<KeyCombo> { HotkeyCenter.shared.failures }

    /// Only meaningful when Rectangle is installed; without it, its default tables would report false conflicts.
    var rectangleConflicts: [ShortcutConflict] {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.rectangleID) != nil else { return [] }
        let raw = CFPreferencesCopyMultiple(nil, Self.rectangleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String: Any] ?? [:]
        return RectangleShortcuts.conflicts(ours: PreferencesStore.shared.prefs.allShortcuts,
                                            theirs: RectangleShortcuts.effective(preferences: raw))
    }

    var launchAtLogin: Bool {
        get { LoginItem.isEnabled }
        set {
            do { try LoginItem.set(newValue) } catch { Log.error("Launch at login: \(error.localizedDescription)") }
        }
    }

    func installCLI() -> String? { Automation.installCLI() }

    func exportRaycastScripts(to folder: URL) -> String? { Automation.exportRaycast(to: folder) }

    func openLog() { NSWorkspace.shared.open(Log.fileURL) }
}
