import AppKit
import RamblaCore
import SwiftUI

/// What a recorder learns from a key press, or from being interrupted.
enum RecordingEvent: Equatable {
    case recorded(KeyCombo)
    case cleared
    case cancelled
    /// A key without ⌃, ⌥ or ⌘: a shortcut needs at least one of them, so keep listening.
    case needsModifier

    static let escapeKey: UInt16 = 0x35
    static let forwardDeleteKey: UInt16 = 0x75

    /// ⎋ cancels and ⌫ clears (both only on their own); any other key counts when ⌃, ⌥ or ⌘ is held.
    /// Pure, so it can be checked without a window or a keyboard.
    static func interpret(keyCode: UInt16, modifiers: Modifiers) -> RecordingEvent {
        if modifiers.isEmpty {
            if keyCode == escapeKey { return .cancelled }
            if keyCode == KeyCode.delete || keyCode == forwardDeleteKey { return .cleared }
        }
        let usable: Modifiers = [.control, .option, .command]
        guard !modifiers.isDisjoint(with: usable) else { return .needsModifier }
        return .recorded(KeyCombo(keyCode: keyCode, modifiers: modifiers))
    }
}

/// Owns the single local key monitor shared by every recorder: only one can listen at a time, and Rambla's own hot keys
/// stay released for exactly as long as it does (otherwise pressing ⌃⌘C to record it would trigger "Centrar columna").
@MainActor
final class ShortcutRecording {
    static let shared = ShortcutRecording()

    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var owner: UUID?
    private var handler: ((RecordingEvent) -> Void)?

    private init() {}

    var isRecording: Bool { handler != nil }

    /// Starts listening for `owner`. A recorder that was already listening gets `.cancelled`.
    func begin(owner: UUID, onEvent: @escaping (RecordingEvent) -> Void) {
        if let previous = handler {
            removeListeners()
            previous(.cancelled)   // hot keys stay released: the next recording starts right away
        }
        self.owner = owner
        handler = onEvent
        HotkeyCenter.shared.suspend(true)
        // Swallow every key while listening, so ⌘W, ⌘Q or a beep never get a say.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.rawValue
            let isRepeat = event.isARepeat
            let swallowed = MainActor.assumeIsolated {
                self?.handle(keyCode: keyCode, flags: flags, isRepeat: isRepeat) ?? false
            }
            return swallowed ? nil : event
        }
        // Leaving the window or the app must not leave Rambla's shortcuts released.
        let center = NotificationCenter.default
        let interruptions: [Notification.Name] = [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification]
        observers = interruptions.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }
        }
    }

    /// Stops listening. With `owner`, only if that recorder is the one listening.
    func cancel(owner: UUID? = nil) {
        guard handler != nil, owner == nil || owner == self.owner else { return }
        finish(with: .cancelled)
    }

    /// Returns true when the key was consumed (every key is, while a recorder listens).
    private func handle(keyCode: UInt16, flags: UInt, isRepeat: Bool) -> Bool {
        guard handler != nil else { return false }
        guard !isRepeat else { return true }
        let outcome = RecordingEvent.interpret(keyCode: keyCode, modifiers: Modifiers(cocoa: flags))
        if outcome == .needsModifier {
            handler?(outcome)
        } else {
            finish(with: outcome)
        }
        return true
    }

    private func finish(with event: RecordingEvent) {
        guard let current = handler else { return }
        removeListeners()
        current(event)                          // the view stores the shortcut while the hot keys are still released...
        HotkeyCenter.shared.suspend(false)      // ...so they come back once, already with the new bindings
    }

    private func removeListeners() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        owner = nil
        handler = nil
    }
}

/// A button that records a keyboard shortcut. Click, then type; ⎋ cancels and ⌫ clears.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    let conflictText: String?
    let placeholder: String
    /// What VoiceOver calls this recorder, e.g. "Rotar ancho, atajo 1".
    let accessibilityTitle: String

    @State private var token = UUID()
    @State private var isRecording = false
    @State private var hint: String?

    init(combo: Binding<KeyCombo?>, conflictText: String?, placeholder: String = String(localized: "Sin atajo"),
         accessibilityTitle: String = String(localized: "Atajo")) {
        _combo = combo
        self.conflictText = conflictText
        self.placeholder = placeholder
        self.accessibilityTitle = accessibilityTitle
    }

    static let width: CGFloat = 112

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ZStack(alignment: .trailing) {
                Button(action: toggle) {
                    Text(label)
                        .font(.callout)
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(RecorderPillStyle(isRecording: isRecording, isFlagged: conflictText != nil))
                .help(isRecording ? "⎋ cancela · ⌫ borra el atajo" : "Hacé clic y escribí el atajo nuevo")
                .accessibilityLabel(accessibilityTitle)
                .accessibilityValue(accessibilityValue)

                // Inside the pill, like the clear button of a search field. Always laid out, hidden when there is
                // nothing to clear, so the pill never changes size.
                Button { combo = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Borrar este atajo")
                .accessibilityLabel("Borrar \(accessibilityTitle)")
                .padding(.trailing, 5)
                .opacity(showsClear ? 1 : 0)
                .disabled(!showsClear)
                .accessibilityHidden(!showsClear)
            }
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: Self.width)
        .onDisappear { ShortcutRecording.shared.cancel(owner: token) }
    }

    private var showsClear: Bool { combo != nil && !isRecording }

    /// While recording, the old shortcut's conflict no longer applies; only the "need a modifier" hint does.
    private var note: String? { isRecording ? hint : conflictText }

    private var label: String {
        if isRecording { return String(localized: "Escribí el atajo…") }
        if let combo { return KeyNames.display(combo) }
        return placeholder
    }

    private var labelColor: Color {
        if isRecording { return .accentColor }
        return combo == nil ? .secondary : .primary
    }

    private var accessibilityValue: String {
        if isRecording { return String(localized: "Grabando") }
        if let combo { return KeyNames.display(combo) }
        return placeholder
    }

    private func toggle() {
        if isRecording {
            ShortcutRecording.shared.cancel(owner: token)
            return
        }
        hint = nil
        isRecording = true
        ShortcutRecording.shared.begin(owner: token) { event in
            switch event {
            case .recorded(let newCombo):
                combo = newCombo
                stopped()
            case .cleared:
                combo = nil
                stopped()
            case .cancelled:
                stopped()
            case .needsModifier:
                hint = String(localized: "Incluí ⌃, ⌥ o ⌘")
            }
        }
    }

    private func stopped() {
        isRecording = false
        hint = nil
    }
}

/// A rounded "field" look for the recorder, using only system colors.
private struct RecorderPillStyle: ButtonStyle {
    let isRecording: Bool
    let isFlagged: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(width: ShortcutRecorder.width)
            .background(shape.fill(isRecording ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor)))
            .overlay(shape.strokeBorder(border, lineWidth: isRecording ? 1.5 : 1))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }

    private var border: Color {
        if isRecording { return .accentColor }
        return isFlagged ? .red : Color(nsColor: .separatorColor)
    }
}
