import AppKit

/// The menu bar icon and its menu. Later components contribute items through `setItems`.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var customItems: [NSMenuItem] = []

    init(statusTitle: String) {
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Rambla")
            image?.isTemplate = true
            button.image = image
        }
        statusLine.isEnabled = false
        statusItem.menu = menu
        setStatus(statusTitle, active: true)
        rebuild()
    }

    func setStatus(_ title: String, active: Bool) {
        statusLine.title = title
        statusItem.button?.appearsDisabled = !active
    }

    func setItems(_ items: [NSMenuItem]) {
        customItems = items
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        customItems.forEach { menu.addItem($0) }
        if !customItems.isEmpty { menu.addItem(.separator()) }
        let quit = NSMenuItem(title: "Salir de Rambla", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }
}
