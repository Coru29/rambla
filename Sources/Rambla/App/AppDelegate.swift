import AppKit
import ApplicationServices
import RamblaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var menuBar: MenuBarController!
    private var trustTimer: Timer?
    private var trustObserver: NSObjectProtocol?
    private var commandObserver: NSObjectProtocol?
    private var signalSources: [DispatchSourceSignal] = []
    private let engine = WindowManager.shared
    private let store = PreferencesStore.shared
    private lazy var gestures = GestureTracker(
        onBegin: { [weak self] in self?.engine.gestureBegan() },
        onChange: { [weak self] dx in self?.engine.gestureChanged(dx) },
        onEnd: { [weak self] velocity in self?.engine.gestureEnded(velocity: velocity) },
        onVertical: { [weak self] up in self?.engine.verticalSwipe(up: up) })
    private lazy var wheel = ScrollWheelTracker(handlers: .init(
        step: { [weak self] columns in self?.engine.wheelStep(columns) },
        slideBegan: { [weak self] in self?.engine.gestureBegan() },
        slide: { [weak self] points in self?.engine.slide(by: points) },
        slideEnded: { [weak self] velocity in self?.engine.slideEnded(velocity: velocity) }))
    private lazy var mouseFocus = MouseFocus { [weak self] point in self?.engine.hover(at: point) }
    private var overlays: OverlayCoordinator?
    private let settingsBackend = AppSettingsBackend()

    /// `--only-bundle <id>` (repeatable) limits management to those apps: used by the live tests.
    private lazy var onlyBundles: Set<String>? = {
        var result: Set<String> = []
        var args = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = args.next() {
            if arg == "--only-bundle", let value = args.next() { result.insert(value) }
        }
        return result.isEmpty ? nil : result
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("Rambla \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") started")
        menuBar = MenuBarController(statusTitle: String(localized: "Iniciando…"))
        installSignalHandlers()
        listenForCommands()
        if AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
            becameTrusted()
        } else {
            waitForTrust()
        }
        // Even before the permission is granted: that is when the guide helps most. Not while testing.
        if onlyBundles == nil { WelcomeWindowController.shared.showIfFirstLaunch() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        engine.saveNow()
        Log.info("Rambla quit")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "rambla" {
            let command = [url.host, url.path.isEmpty ? nil : String(url.path.dropFirst())]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "-")
            engine.perform(command: command, from: .url)
        }
    }

    // MARK: - Accessibility permission

    private func waitForTrust() {
        menuBar.setStatus(String(localized: "Falta el permiso de Accesibilidad"), active: false)
        let open = NSMenuItem(title: String(localized: "Abrir Ajustes de Accesibilidad…"), action: #selector(openAccessibilitySettings), keyEquivalent: "")
        open.target = self
        menuBar.setItems([open, item(String(localized: "Bienvenida…"), #selector(openWelcome))])
        // macOS posts this when any app's Accessibility permission changes; the timer is a fallback
        // that only runs while the permission is missing.
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.recheckTrust() }
            }
        }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckTrust() }
        }
    }

    private func recheckTrust() {
        guard trustTimer != nil, AXIsProcessTrusted() else { return }
        trustTimer?.invalidate()
        trustTimer = nil
        if let observer = trustObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            trustObserver = nil
        }
        becameTrusted()
    }

    private func becameTrusted() {
        Log.info("Accessibility permission granted")
        store.onChange = { [weak self] prefs in self?.preferencesChanged(prefs) }
        engine.onStateChanged = { [weak self] in self?.refreshMenu() }
        HotkeyCenter.shared.onAction = { [weak self] action, combo in
            self?.engine.perform(action, holding: combo.modifiers.eventFlags)
        }
        overlays = OverlayCoordinator(engine: engine)
        SettingsWindowController.shared.backend = settingsBackend
        SettingsOpener.handler = { SettingsWindowController.shared.show() }
        Updater.shared.onChange = { [weak self] in self?.refreshMenu(force: true) }
        Updater.shared.configure(automatic: store.prefs.checkForUpdates)
        lastPrefs = store.prefs
        engine.start(prefs: store.prefs, onlyBundles: onlyBundles)
        if !store.prefs.enabled { engine.setPaused(true) }
        refreshMenu(force: true)
    }

    private var lastPrefs: Preferences?

    /// Settings sliders change preferences many times a second: only redo the parts that depend on what changed.
    private func preferencesChanged(_ prefs: Preferences) {
        let old = lastPrefs
        lastPrefs = prefs
        if old?.checkForUpdates != prefs.checkForUpdates {
            Updater.shared.configure(automatic: prefs.checkForUpdates)
        }
        engine.update(prefs: prefs)
        if prefs.enabled == engine.isPaused { engine.setPaused(!prefs.enabled) }
        if old?.allShortcuts != prefs.allShortcuts { applyHotkeys() }
        if old?.trackpad != prefs.trackpad || old?.mouse != prefs.mouse || old?.focusFollowsMouse != prefs.focusFollowsMouse {
            applyInputs()
        }
        refreshMenu()
    }

    /// Input sources that cost something while active exist only when their feature is on.
    private func applyInputs() {
        let prefs = store.prefs
        let active = !engine.isPaused && prefs.enabled
        gestures.configure(enabled: active && prefs.trackpad.enabled, fingers: prefs.trackpad.fingers,
                           vertical: prefs.trackpad.verticalSwipe)
        wheel.configure(enabled: active && prefs.mouse.enabled, modifiers: prefs.mouse.modifiers)
        mouseFocus.setEnabled(active && prefs.focusFollowsMouse)
    }

    private func applyHotkeys() {
        let prefs = store.prefs
        let paused = engine.isPaused || !prefs.enabled
        HotkeyCenter.shared.apply(prefs.allShortcuts, only: paused ? [.togglePause] : nil)
    }

    // MARK: - Menu

    private var menuPausedState: Bool?

    /// Rebuilds the menu and re-registers shortcuts only when the paused state changes
    /// (onStateChanged also fires on every focus change).
    private func refreshMenu(force: Bool = false) {
        let paused = engine.isPaused
        guard force || paused != menuPausedState else { return }
        menuPausedState = paused
        // "Activo" in General and the pause command are the same switch; keep them in sync.
        if store.prefs.enabled == paused { store.prefs.enabled = !paused }
        menuBar.setStatus(paused ? String(localized: "En pausa") : String(localized: "Activo"), active: !paused)
        let toggle = item(paused ? String(localized: "Reanudar Rambla") : String(localized: "Pausar Rambla"), #selector(togglePause))
        var items: [NSMenuItem] = []
        if let update = Updater.shared.available {
            let version = update.version.description
            let title = Updater.shared.isInstalling ? String(localized: "Actualizando a Rambla \(version)…")
                                                    : String(localized: "Actualizar a Rambla \(version)…")
            let updateItem = item(title, #selector(offerUpdate))
            updateItem.isEnabled = !Updater.shared.isInstalling
            items += [updateItem, .separator()]
        }
        items += [
            toggle,
            item(String(localized: "Reacomodar ventanas"), #selector(relayout)),
            item(String(localized: "Traer todas las ventanas a la pantalla"), #selector(gather)),
            item(String(localized: "Flotar / volver la ventana actual"), #selector(toggleFloat)),
            .separator(),
            item(String(localized: "Configuración…"), #selector(openSettings), key: ","),
            item(String(localized: "Bienvenida…"), #selector(openWelcome)),
            item(String(localized: "Manual de uso"), #selector(openManual)),
            item(String(localized: "Buscar actualizaciones…"), #selector(checkForUpdates)),
            item(String(localized: "Mostrar registro"), #selector(showLog)),
        ]
        menuBar.setItems(items)
        applyHotkeys()
        applyInputs()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePause() { engine.setPaused(!engine.isPaused) }
    @objc private func relayout() { engine.relayoutAll() }
    @objc private func gather() { engine.gatherAll(synchronously: false) }
    @objc private func toggleFloat() { engine.toggleFloatFocused() }
    @objc private func showLog() { NSWorkspace.shared.open(Log.fileURL) }
    @objc private func openManual() { NSWorkspace.shared.open(Self.manualURL) }
    @objc private func openWelcome() { WelcomeWindowController.shared.show() }
    @objc private func offerUpdate() { Updater.shared.offerInstall() }
    @objc private func checkForUpdates() { Task { await Updater.shared.check(userInitiated: true) } }

    /// The manual in the language Rambla is showing (Spanish or English).
    static var manualURL: URL {
        let spanish = Bundle.main.preferredLocalizations.first == "es"
        let file = spanish ? "MANUAL.md" : "MANUAL.en.md"
        return URL(string: "https://github.com/Coru29/rambla/blob/main/docs/\(file)")!
    }
    @objc private func openSettings() { SettingsOpener.open() }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - CLI, signals

    private func listenForCommands() {
        commandObserver = DistributedNotificationCenter.default().addObserver(
            forName: CLI.commandNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let command = note.object as? String else { return }
            MainActor.assumeIsolated { _ = self?.engine.perform(command: command, from: .commandLine) }
        }
    }

    /// `kill`/logout must not leave windows parked off screen.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    WindowManager.shared.stop()
                    WindowManager.shared.saveNow()
                }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

/// Settings window entry point; replaced by the real window in the settings task.
@MainActor
enum SettingsOpener {
    static var handler: (() -> Void)?
    static func open() { handler?() }
}

extension Modifiers {
    var eventFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: cocoa) }
}
