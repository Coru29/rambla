import AppKit
import Carbon
import RamblaCore

/// Global shortcuts through Carbon hot keys: no extra permission, no event tap, zero cost while idle.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    var onAction: ((Action, KeyCombo) -> Void)?
    /// Shortcuts macOS refused (usually taken by another app or the system).
    private(set) var failures: Set<KeyCombo> = []

    private var refs: [EventHotKeyRef] = []
    private var registered: [UInt32: (Action, KeyCombo)] = [:]
    private var handler: EventHandlerRef?
    private var lastBindings: [Action: [KeyCombo]] = [:]
    private var lastOnly: Set<Action>?
    private var suspended = false

    func apply(_ bindings: [Action: [KeyCombo]], only: Set<Action>? = nil) {
        lastBindings = bindings
        lastOnly = only
        unregisterAll()
        guard !suspended else { return }
        installHandlerIfNeeded()
        failures = []
        defer { Log.info("Registered \(registered.count) shortcuts (\(failures.count) failed)") }
        var nextID: UInt32 = 1
        for action in Action.allCases {
            if let only, !only.contains(action) { continue }
            for combo in bindings[action] ?? [] {
                var ref: EventHotKeyRef?
                let hotKeyID = EventHotKeyID(signature: OSType(0x524D_424C), id: nextID) // 'RMBL'
                let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.modifiers.carbon, hotKeyID,
                                                 GetEventDispatcherTarget(), 0, &ref)
                if status == noErr, let ref {
                    refs.append(ref)
                    registered[nextID] = (action, combo)
                } else {
                    failures.insert(combo)
                    Log.error("Shortcut \(KeyNames.display(combo)) for \(action.rawValue) could not be registered (\(status))")
                }
                nextID += 1
            }
        }
    }

    /// While the shortcut recorder listens, every hot key is released so the keys reach it.
    func suspend(_ isSuspended: Bool) {
        suspended = isSuspended
        if isSuspended {
            unregisterAll()
        } else {
            apply(lastBindings, only: lastOnly)
        }
    }

    private func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        registered.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func fire(_ id: UInt32) {
        guard let (action, combo) = registered[id] else { return }
        Log.info("Shortcut \(KeyNames.display(combo)) → \(action.rawValue)")
        onAction?(action, combo)
    }
}
