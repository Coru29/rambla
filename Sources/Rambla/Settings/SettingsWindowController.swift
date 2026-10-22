import AppKit
import SwiftUI

/// Owns the settings window. While it is open Rambla is a regular app (Dock icon, ⌘Tab); closing it goes back to a
/// menu bar agent and releases the window, so a closed settings window costs no memory.
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
        installMainMenuIfNeeded()
        NSApp.setActivationPolicy(.regular)
        let window = self.window ?? makeWindow()
        self.window = window
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The policy change is not instant: ask once more on the next turn if the first request did not stick.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            }
        }
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
        NSApp.setActivationPolicy(.accessory)
        // The window is still on its way out of this call; let it go on the next turn.
        DispatchQueue.main.async { withExtendedLifetime(closing) {} }
    }

    // MARK: - Main menu

    /// A regular app needs a menu bar: ⌘W closes the window, ⌘Q quits and ⌘C / ⌘V work in the text fields.
    /// The menu bar agent has none of that until the settings window opens.
    private func installMainMenuIfNeeded() {
        guard NSApp.mainMenu == nil else { return }
        let mainMenu = NSMenu()

        let appMenu = submenu(titled: "Rambla", in: mainMenu)
        appMenu.addItem(withTitle: "Ocultar Rambla", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Salir de Rambla", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = submenu(titled: "Archivo", in: mainMenu)
        fileMenu.addItem(withTitle: "Cerrar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenu = submenu(titled: "Edición", in: mainMenu)
        editMenu.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = submenu(titled: "Ventana", in: mainMenu)
        windowMenu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func submenu(titled title: String, in menu: NSMenu) -> NSMenu {
        let item = NSMenuItem()
        let submenu = NSMenu(title: title)
        item.submenu = submenu
        menu.addItem(item)
        return submenu
    }
}
