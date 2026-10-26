import Foundation

/// Keyboard modifiers, independent of AppKit and Carbon (RamblaCore imports neither).
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1)
    public static let option = Modifiers(rawValue: 2)
    public static let shift = Modifiers(rawValue: 4)
    public static let command = Modifiers(rawValue: 8)

    /// The mask `RegisterEventHotKey` expects (controlKey, optionKey, shiftKey, cmdKey).
    public var carbon: UInt32 {
        var mask: UInt32 = 0
        if contains(.control) { mask |= 0x1000 }
        if contains(.option) { mask |= 0x0800 }
        if contains(.shift) { mask |= 0x0200 }
        if contains(.command) { mask |= 0x0100 }
        return mask
    }

    /// Reads `NSEvent.ModifierFlags.rawValue` (shift 1<<17, control 1<<18, option 1<<19, command 1<<20).
    /// Every other bit (caps lock, function, numeric pad, device flags) is ignored.
    public init(cocoa: UInt) {
        var result: Modifiers = []
        if cocoa & (1 << 17) != 0 { result.insert(.shift) }
        if cocoa & (1 << 18) != 0 { result.insert(.control) }
        if cocoa & (1 << 19) != 0 { result.insert(.option) }
        if cocoa & (1 << 20) != 0 { result.insert(.command) }
        self = result
    }

    /// The matching `NSEvent.ModifierFlags.rawValue`.
    public var cocoa: UInt {
        var flags: UInt = 0
        if contains(.shift) { flags |= 1 << 17 }
        if contains(.control) { flags |= 1 << 18 }
        if contains(.option) { flags |= 1 << 19 }
        if contains(.command) { flags |= 1 << 20 }
        return flags
    }

    /// Display symbols in the macOS order ⌃⌥⇧⌘.
    public var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }
}

/// A key plus modifiers, using the physical virtual key code (layout independent).
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// ANSI virtual key codes (the values of Carbon's `kVK_*`), written out so RamblaCore does not need Carbon.
public enum KeyCode {
    public static let a: UInt16 = 0x00
    public static let d: UInt16 = 0x02
    public static let f: UInt16 = 0x03
    public static let h: UInt16 = 0x04
    public static let g: UInt16 = 0x05
    public static let z: UInt16 = 0x06
    public static let c: UInt16 = 0x08
    public static let b: UInt16 = 0x0B
    public static let w: UInt16 = 0x0D
    public static let e: UInt16 = 0x0E
    public static let r: UInt16 = 0x0F
    public static let t: UInt16 = 0x11
    public static let o: UInt16 = 0x1F
    public static let u: UInt16 = 0x20
    public static let i: UInt16 = 0x22
    public static let p: UInt16 = 0x23
    public static let l: UInt16 = 0x25
    public static let j: UInt16 = 0x26
    public static let k: UInt16 = 0x28
    public static let n: UInt16 = 0x2D
    public static let m: UInt16 = 0x2E

    public static let digit1: UInt16 = 0x12
    public static let digit2: UInt16 = 0x13
    public static let digit3: UInt16 = 0x14
    public static let digit4: UInt16 = 0x15
    public static let digit5: UInt16 = 0x17
    public static let digit6: UInt16 = 0x16
    public static let digit7: UInt16 = 0x1A
    public static let digit8: UInt16 = 0x1C
    public static let digit9: UInt16 = 0x19
    public static let digit0: UInt16 = 0x1D
    /// The digit keys in keyboard order: 1, 2, ... 9, 0.
    public static let digits: [UInt16] = [digit1, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9, digit0]

    public static let equal: UInt16 = 0x18
    public static let minus: UInt16 = 0x1B
    public static let leftBracket: UInt16 = 0x21
    public static let rightBracket: UInt16 = 0x1E

    public static let returnKey: UInt16 = 0x24
    public static let space: UInt16 = 0x31
    public static let delete: UInt16 = 0x33
    public static let escape: UInt16 = 0x35
    public static let keypadEnter: UInt16 = 0x4C

    public static let left: UInt16 = 0x7B
    public static let right: UInt16 = 0x7C
    public static let down: UInt16 = 0x7D
    public static let up: UInt16 = 0x7E
}

/// The shortcuts Rambla ships with. ⌃⌘ is the base (Rectangle lives in ⌃⌥ space) and ⌃⌘⇧ marks "move" and the
/// opposite-direction variants. Arrow keys come first and the vim-style HJKL second. ⌃⌥⌘ moves between the stacked
/// strips and ⇧ takes the focused window along; Rectangle's default sets use ⌃⌥⌘ only with ← and → (its display
/// moves), so ↑ and ↓ are free.
public enum DefaultShortcuts {
    public static let table: [Action: [KeyCombo]] = {
        var table: [Action: [KeyCombo]] = [:]
        for action in Action.allCases { table[action] = combos(for: action) }
        return table
    }()

    /// An exhaustive switch on purpose: adding an `Action` forces a decision about its default here.
    private static func combos(for action: Action) -> [KeyCombo] {
        let base: Modifiers = [.control, .command]
        let shifted: Modifiers = [.control, .command, .shift]
        let stacked: Modifiers = [.control, .option, .command]
        let stackedShifted: Modifiers = [.control, .option, .command, .shift]
        func plain(_ keyCode: UInt16) -> KeyCombo { KeyCombo(keyCode: keyCode, modifiers: base) }
        func withShift(_ keyCode: UInt16) -> KeyCombo { KeyCombo(keyCode: keyCode, modifiers: shifted) }
        func strips(_ keyCode: UInt16) -> KeyCombo { KeyCombo(keyCode: keyCode, modifiers: stacked) }
        func stripsWithShift(_ keyCode: UInt16) -> KeyCombo { KeyCombo(keyCode: keyCode, modifiers: stackedShifted) }

        switch action {
        case .focusLeft: return [plain(KeyCode.left), plain(KeyCode.h)]
        case .focusRight: return [plain(KeyCode.right), plain(KeyCode.l)]
        case .focusUp: return [plain(KeyCode.up), plain(KeyCode.k)]
        case .focusDown: return [plain(KeyCode.down), plain(KeyCode.j)]
        case .focusFirst: return [plain(KeyCode.a)]
        case .focusLast: return [plain(KeyCode.e)]
        case .focus1: return [plain(KeyCode.digit1)]
        case .focus2: return [plain(KeyCode.digit2)]
        case .focus3: return [plain(KeyCode.digit3)]
        case .focus4: return [plain(KeyCode.digit4)]
        case .focus5: return [plain(KeyCode.digit5)]
        case .focus6: return [plain(KeyCode.digit6)]
        case .focus7: return [plain(KeyCode.digit7)]
        case .focus8: return [plain(KeyCode.digit8)]
        case .focus9: return [plain(KeyCode.digit9)]
        case .moveLeft: return [withShift(KeyCode.left), withShift(KeyCode.h)]
        case .moveRight: return [withShift(KeyCode.right), withShift(KeyCode.l)]
        case .moveUp: return [withShift(KeyCode.up), withShift(KeyCode.k)]
        case .moveDown: return [withShift(KeyCode.down), withShift(KeyCode.j)]
        case .sendNextDisplay: return [plain(KeyCode.n)]
        case .stripUp: return [strips(KeyCode.up)]
        case .stripDown: return [strips(KeyCode.down)]
        case .sendStripUp: return [stripsWithShift(KeyCode.up)]
        case .sendStripDown: return [stripsWithShift(KeyCode.down)]
        case .overview: return [plain(KeyCode.o)]
        case .cycleWidth: return [plain(KeyCode.r)]
        case .fullWidth: return [plain(KeyCode.m)]
        case .center: return [plain(KeyCode.c)]
        case .wider: return [plain(KeyCode.equal)]
        case .narrower: return [plain(KeyCode.minus)]
        case .taller: return [withShift(KeyCode.equal)]
        case .shorter: return [withShift(KeyCode.minus)]
        case .equalizeHeights: return [plain(KeyCode.digit0)]
        case .pinLeft: return [plain(KeyCode.p)]
        case .pinRight: return [withShift(KeyCode.p)]
        case .stackLeft: return [plain(KeyCode.leftBracket)]
        case .stackRight: return [plain(KeyCode.rightBracket)]
        case .popLeft: return [withShift(KeyCode.leftBracket)]
        case .popRight: return [withShift(KeyCode.rightBracket)]
        case .toggleTabbed: return [withShift(KeyCode.t)]
        case .toggleFloat: return [plain(KeyCode.t)]
        case .closeWindow, .togglePause: return []   // ⌃⌘Q locks the screen, so closing has no default; pause is opt-in
        }
    }
}
