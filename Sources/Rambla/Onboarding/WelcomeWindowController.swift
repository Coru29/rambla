import AppKit
import SwiftUI

/// The welcome guide ("Bienvenida a Rambla"): shown the first time Rambla runs, and from the menu afterwards.
/// While it is open Rambla is a regular app, so the window can take focus (see `AppWindows`).
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()
    /// The UserDefaults flag that says the guide has already opened once.
    static let shownKey = "welcomeShown"

    private(set) var window: WelcomeWindow?
    private(set) var model: WelcomeModel?

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
        AppWindows.present(window ?? makeWindow(model: WelcomeModel()))
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

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        model?.stop()
        window = nil
        model = nil
        // The window is still in the middle of closing: let go of it only after this turn of the run loop.
        DispatchQueue.main.async { withExtendedLifetime(closing) {} }
        AppWindows.willClose(closing)
    }
}

/// The guide's window. Keys it answers when no control in it wants them: ⏎ goes to the next step, ⎋ and ⌘W close.
///
/// ⏎ is handled here, not as a default button: the default button is drawn in the accent color, and on the
/// permission step that color belongs to "Abrir la configuración de Accesibilidad".
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
