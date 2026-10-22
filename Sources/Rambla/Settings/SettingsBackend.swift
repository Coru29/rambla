import AppKit
import RamblaCore

/// What the settings window needs from the running app (implemented by the app, faked in previews).
@MainActor
protocol SettingsBackend: AnyObject {
    var displays: [(uuid: String, name: String)] { get }
    var runningApps: [(bundleID: String, name: String, icon: NSImage?)] { get }
    var hotkeyFailures: Set<KeyCombo> { get }
    var rectangleConflicts: [ShortcutConflict] { get }
    var launchAtLogin: Bool { get set }
    /// macOS registered the login item but waits for the user to allow it.
    var launchAtLoginNeedsApproval: Bool { get }
    func openLoginItemsSettings()
    /// Returns an error message, or nil on success.
    func installCLI() -> String?
    func exportRaycastScripts(to folder: URL) -> String?
    func openLog()
    /// Listens to the mouse's buttons (all but the left and right ones) for the "Botones" recorder: `onChange` gets the
    /// buttons down so far, `onDone` the most that were down at once, after all of them are released. Meanwhile those
    /// presses reach no app.
    func recordMouseButtons(onChange: @escaping ([Int]) -> Void, onDone: @escaping ([Int]) -> Void)
    func stopRecordingMouseButtons()
}
