import AppKit

/// Rambla is a menu bar app with no Dock icon. While one of its own windows is open (settings, the welcome guide)
/// it becomes a regular app, so the window can take focus and the Dock icon, ⌘Tab and the menu bar work; once the
/// last one closes it goes back to the menu bar. Every window opens and closes through here, so closing one never
/// takes the Dock icon away from another that is still open.
@MainActor
enum AppWindows {
    /// Brings `window` to the front and activates Rambla.
    static func present(_ window: NSWindow) {
        installMainMenuIfNeeded()
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        // If macOS declines to activate Rambla, the window must still be seen.
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        // The policy change is not instant: ask once more on the next turn if the first request did not stick.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            }
        }
    }

    /// Call from `windowWillClose`: back to a menu bar app, unless another of Rambla's windows stays open.
    static func willClose(_ window: NSWindow) {
        if !hasOpenWindow(besides: window) { NSApp.setActivationPolicy(.accessory) }
    }

    /// A titled window other than `closing` is open, or minimized in the Dock. Alerts (panels) and the borderless
    /// overlays (indicator, focus border, dimming) do not count.
    static func hasOpenWindow(besides closing: NSWindow) -> Bool {
        NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized) && $0.styleMask.contains(.titled) && !($0 is NSPanel)
        }
    }

    // MARK: - Main menu

    /// A regular app needs a menu bar: ⌘W closes the window, ⌘Q quits and ⌘C / ⌘V work in the text fields.
    /// The menu bar agent has none of that until one of its windows opens.
    private static func installMainMenuIfNeeded() {
        guard NSApp.mainMenu == nil else { return }
        let mainMenu = NSMenu()

        let appMenu = submenu(titled: "Rambla", in: mainMenu)
        appMenu.addItem(withTitle: String(localized: "Ocultar Rambla"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Salir de Rambla"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = submenu(titled: String(localized: "Archivo"), in: mainMenu)
        fileMenu.addItem(withTitle: String(localized: "Cerrar"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenu = submenu(titled: String(localized: "Edición"), in: mainMenu)
        editMenu.addItem(withTitle: String(localized: "Deshacer"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: String(localized: "Rehacer"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cortar"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copiar"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Pegar"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Seleccionar todo"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = submenu(titled: String(localized: "Ventana"), in: mainMenu)
        windowMenu.addItem(withTitle: String(localized: "Minimizar"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private static func submenu(titled title: String, in menu: NSMenu) -> NSMenu {
        let item = NSMenuItem()
        let submenu = NSMenu(title: title)
        item.submenu = submenu
        menu.addItem(item)
        return submenu
    }
}
