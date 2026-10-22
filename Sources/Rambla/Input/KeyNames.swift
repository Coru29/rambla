import Carbon
import RamblaCore

/// Human-readable shortcut labels in the current keyboard layout (AZERTY, QWERTZ, Dvorak…):
/// shortcuts are stored as physical key codes, the label is whatever that key types now.
enum KeyNames {
    private static let special: [UInt16: String] = [
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x24: "↩", 0x4C: "⌤", 0x33: "⌫", 0x75: "⌦",
        0x35: "⎋", 0x30: "⇥", 0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]

    static func label(for keyCode: UInt16) -> String {
        if keyCode == 0x31 { return String(localized: "Espacio") }
        if let name = special[keyCode] { return name }
        return translate(keyCode) ?? "#\(keyCode)"
    }

    static func display(_ combo: KeyCombo) -> String {
        combo.modifiers.symbols + label(for: combo.keyCode)
    }

    /// "Botón del medio", "Botón 4 + Botón 5": mouse buttons, numbered the way mouse apps number them.
    static func mouseButtons(_ buttons: [Int]) -> String {
        buttons.map { $0 == 3 ? String(localized: "Botón del medio") : String(localized: "Botón \($0)") }
            .joined(separator: " + ")
    }

    private static func translate(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let fallback = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        for candidate in [source, fallback].compactMap({ $0 }) {
            guard let pointer = TISGetInputSourceProperty(candidate, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            let text: String? = data.withUnsafeBytes { raw in
                guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
                var deadKeys: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        return nil
    }
}
