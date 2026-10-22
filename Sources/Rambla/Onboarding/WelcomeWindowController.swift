import AppKit
import SwiftUI

/// The welcome guide ("Bienvenida a Rambla"): shown the first time Rambla runs, and from the menu afterwards.
///
/// Rambla normally has no Dock icon. While this window is open it becomes a regular app (Dock icon, ⌘Tab) so
/// the window can take focus, and it goes back to being a menu bar app when the window closes.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()
    /// The UserDefaults flag that says the guide has already opened once.
    static let shownKey = "welcomeShown"

    /// The calls the controller makes on the app itself. Real AppKit by default; a harness swaps them for recorders
    /// so that checking the controller never shows a window, takes focus or changes how the app appears.
    struct Hooks {
        var setActivationPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void = { _ = NSApp.setActivationPolicy($0) }
        var present: @MainActor (NSWindow) -> Void = { window in
            window.makeKeyAndOrderFront(nil)
            // If macOS declines to activate Rambla, the window must still be seen.
            window.orderFrontRegardless()
            NSApp.activate()
        }
        /// Whether a regular window other than `closing` is open: the settings window needs the Dock icon and the
        /// menu bar as much as this one does. Panels (alerts) and borderless overlays do not count.
        var hasOtherRegularWindow: @MainActor (NSWindow) -> Bool = { closing in
            NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
        }
    }

    private(set) var window: WelcomeWindow?
    private(set) var model: WelcomeModel?
    var hooks = Hooks()

    /// True the first time it is asked on this Mac, and never again: the flag is set on the spot, so closing the
    /// guide half way is final.
    static func claimFirstLaunch(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: shownKey) else { return false }
        defaults.set(true, forKey: shownKey)
        return true
    }

    /// Opens the guide on the first launch only.
    func showIfFirstLaunch(defaults: UserDefaults = .standard) {
        if Self.claimFirstLaunch(defaults: defaults) { show() }
    }

    /// Opens the guide at its first step, or brings it forward if it is already open.
    func show() {
        present(window ?? makeWindow(model: WelcomeModel()))
    }

    func close() {
        window?.close()
    }

    /// Builds the guide's window around `model` and keeps both, without showing anything yet.
    func makeWindow(model: WelcomeModel) -> WelcomeWindow {
        let window = WelcomeWindow(contentRect: NSRect(origin: .zero, size: WelcomeView.size),
                                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "Bienvenida a Rambla")
        window.isReleasedWhenClosed = false
        // Opening it from the menu on another desktop brings it along instead of jumping back to the old one.
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = NSHostingView(rootView: WelcomeView(model: model))
        window.onReturn = { [weak model] in model?.advance() }
        model.finish = { [weak self] in self?.close() }
        window.delegate = self
        window.center()
        self.window = window
        self.model = model
        return window
    }

    private func present(_ window: NSWindow) {
        hooks.setActivationPolicy(.regular)
        hooks.present(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        model?.stop()
        window = nil
        model = nil
        // The window is still in the middle of closing: let go of it only after this turn of the run loop.
        DispatchQueue.main.async { withExtendedLifetime(closing) {} }
        if !hooks.hasOtherRegularWindow(closing) { hooks.setActivationPolicy(.accessory) }
    }
}

/// The guide's window. Keys it answers when no control in it wants them: ⏎ goes to the next step, ⎋ and ⌘W close.
///
/// ⏎ is handled here, not as a default button: the default button is drawn in the accent color, and on the
/// permission step that color belongs to "Abrir Ajustes de Accesibilidad".
final class WelcomeWindow: NSWindow {
    /// What ⏎ does.
    var onReturn: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        // A held key must not race through the steps and close the window.
        guard event.type == .keyDown, !event.isARepeat else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.isEmpty {
            // Physical keys: Return, Enter on the numeric pad, Escape.
            if event.keyCode == 36 || event.keyCode == 76 {
                onReturn?()
                return true
            }
            if event.keyCode == 53 {
                performClose(nil)
                return true
            }
        } else if modifiers == .command, event.charactersIgnoringModifiers == "w" {
            // By character, so it is the key labeled W on any keyboard layout.
            performClose(nil)
            return true
        }
        return false
    }
}
