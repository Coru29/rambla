import AppKit
import SwiftUI

/// Owns the settings window. While it is open Rambla is a regular app (Dock icon, ⌘Tab, see `AppWindows`); closing
/// it releases the window, so a closed settings window costs no memory.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    /// What the window needs from the running app. The app sets it once at launch; changing it while the window is
    /// open refreshes the pages that use it.
    var backend: SettingsBackend? {
        didSet { hostingView?.rootView = SettingsRoot(backend: backend) }
    }

    private var window: NSWindow?
    private var hostingView: NSHostingView<SettingsRoot>?

    private override init() {
        super.init()
    }

    /// Opens the window (or brings the open one forward) and activates the app.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        AppWindows.present(window)
    }

    // MARK: - Window

    /// Builds the window without showing it or touching the activation policy.
    func makeWindow(initialSection: SettingsSection = .general) -> NSWindow {
        let size = SettingsRoot.minimumSize
        let hosting = NSHostingView(rootView: SettingsRoot(backend: backend, initialSection: initialSection))
        // Keep the title bar plain: bridged, the split view puts a sidebar toggle in a toolbar that crowds the title,
        // and the sidebar has no business being hidden here.
        hosting.sceneBridgingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configuración de Rambla"
        window.contentView = hosting
        window.contentMinSize = size
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]   // open where the user is, not on the Space it was last in
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("RamblaSettings")      // restores the size and position the user left it in
        hostingView = hosting
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        ShortcutRecording.shared.cancel()   // a recorder left listening would keep every hot key released
        closing.delegate = nil
        window = nil
        hostingView = nil
        AppWindows.willClose(closing)
        // The window is still on its way out of this call; let it go on the next turn.
        DispatchQueue.main.async { withExtendedLifetime(closing) {} }
    }
}
