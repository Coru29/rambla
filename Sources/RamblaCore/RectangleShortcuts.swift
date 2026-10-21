import Foundation

/// A Rambla shortcut that is also bound to a Rectangle action.
public struct ShortcutConflict: Equatable, Sendable {
    public var action: Action
    public var combo: KeyCombo
    /// Rectangle's own name for the action, as used in its preferences (`leftHalf`, `topLeft`, ...).
    public var rectangleAction: String

    public init(action: Action, combo: KeyCombo, rectangleAction: String) {
        self.action = action
        self.combo = combo
        self.rectangleAction = rectangleAction
    }
}

/// Rectangle's shortcut tables, used to warn about collisions with Rambla's shortcuts.
/// Rectangle only writes shortcuts the user changed, so its real bindings are a default set plus the stored overrides.
public enum RectangleShortcuts {
    /// Rectangle's "recommended" set (preference `alternateDefaultShortcuts` on), keyed by Rectangle's action name.
    /// Transcribed from `alternateDefault` in Rectangle's `WindowAction.swift`.
    public static let alternateDefaults: [String: KeyCombo] = {
        let controlOption: Modifiers = [.control, .option]
        let controlOptionShift: Modifiers = [.control, .option, .shift]
        let controlOptionCommand: Modifiers = [.control, .option, .command]
        func combo(_ keyCode: UInt16, _ modifiers: Modifiers) -> KeyCombo { KeyCombo(keyCode: keyCode, modifiers: modifiers) }

        var table: [String: KeyCombo] = [:]
        table["leftHalf"] = combo(KeyCode.left, controlOption)
        table["rightHalf"] = combo(KeyCode.right, controlOption)
        table["bottomHalf"] = combo(KeyCode.down, controlOption)
        table["topHalf"] = combo(KeyCode.up, controlOption)
        table["bottomLeft"] = combo(KeyCode.j, controlOption)
        table["bottomRight"] = combo(KeyCode.k, controlOption)
        table["topLeft"] = combo(KeyCode.u, controlOption)
        table["topRight"] = combo(KeyCode.i, controlOption)
        table["maximize"] = combo(KeyCode.returnKey, controlOption)
        table["maximizeHeight"] = combo(KeyCode.up, controlOptionShift)
        table["previousDisplay"] = combo(KeyCode.left, controlOptionCommand)
        table["nextDisplay"] = combo(KeyCode.right, controlOptionCommand)
        table["larger"] = combo(KeyCode.equal, controlOption)
        table["smaller"] = combo(KeyCode.minus, controlOption)
        table["center"] = combo(KeyCode.c, controlOption)
        table["restore"] = combo(KeyCode.delete, controlOption)
        table["firstThird"] = combo(KeyCode.d, controlOption)
        table["firstTwoThirds"] = combo(KeyCode.e, controlOption)
        table["centerThird"] = combo(KeyCode.f, controlOption)
        table["lastTwoThirds"] = combo(KeyCode.t, controlOption)
        table["lastThird"] = combo(KeyCode.g, controlOption)
        table["centerTwoThirds"] = combo(KeyCode.r, controlOption)
        return table
    }()

    /// Rectangle's Spectacle-compatible set (the default while `alternateDefaultShortcuts` is off).
    /// Transcribed from `spectacleDefault` in Rectangle's `WindowAction.swift`.
    public static let spectacleDefaults: [String: KeyCombo] = {
        let optionCommand: Modifiers = [.option, .command]
        let controlOptionShift: Modifiers = [.control, .option, .shift]
        let controlOptionCommand: Modifiers = [.control, .option, .command]
        let controlShiftCommand: Modifiers = [.control, .shift, .command]
        let controlCommand: Modifiers = [.control, .command]
        let controlOption: Modifiers = [.control, .option]
        func combo(_ keyCode: UInt16, _ modifiers: Modifiers) -> KeyCombo { KeyCombo(keyCode: keyCode, modifiers: modifiers) }

        var table: [String: KeyCombo] = [:]
        table["leftHalf"] = combo(KeyCode.left, optionCommand)
        table["rightHalf"] = combo(KeyCode.right, optionCommand)
        table["maximize"] = combo(KeyCode.f, optionCommand)
        table["maximizeHeight"] = combo(KeyCode.up, controlOptionShift)
        table["previousDisplay"] = combo(KeyCode.left, controlOptionCommand)
        table["nextDisplay"] = combo(KeyCode.right, controlOptionCommand)
        table["larger"] = combo(KeyCode.right, controlOptionShift)
        table["smaller"] = combo(KeyCode.left, controlOptionShift)
        table["bottomHalf"] = combo(KeyCode.down, optionCommand)
        table["topHalf"] = combo(KeyCode.up, optionCommand)
        table["center"] = combo(KeyCode.c, optionCommand)
        table["bottomLeft"] = combo(KeyCode.left, controlShiftCommand)
        table["bottomRight"] = combo(KeyCode.right, controlShiftCommand)
        table["topLeft"] = combo(KeyCode.left, controlCommand)
        table["topRight"] = combo(KeyCode.right, controlCommand)
        table["restore"] = combo(KeyCode.delete, controlOption)
        return table
    }()

    /// Rectangle's bindings as they are right now, given the contents of its preferences domain
    /// (`com.knollsoft.Rectangle`): the default set picked by `alternateDefaultShortcuts`, with every stored shortcut
    /// applied on top. A stored shortcut is a dictionary with numeric `keyCode` and `modifierFlags` (Cocoa flags).
    ///
    /// Values may come straight from CFPreferences or UserDefaults, so numbers can be `Int`, `NSNumber` or `Bool`
    /// and dictionaries `[String: Any]` or `NSDictionary`. Anything else is ignored.
    public static func effective(preferences: [String: Any]) -> [String: KeyCombo] {
        var table = isOn(preferences["alternateDefaultShortcuts"]) ? alternateDefaults : spectacleDefaults
        for (name, value) in preferences {
            if let combo = storedCombo(value) { table[name] = combo }
        }
        return table
    }

    /// Every Rambla shortcut that Rectangle also uses, ordered by `Action.allCases` and then by Rectangle's action name.
    public static func conflicts(ours: [Action: [KeyCombo]], theirs: [String: KeyCombo]) -> [ShortcutConflict] {
        var found: [ShortcutConflict] = []
        for (action, combos) in ours {
            for combo in combos {
                for (name, other) in theirs where other == combo {
                    found.append(ShortcutConflict(action: action, combo: combo, rectangleAction: name))
                }
            }
        }
        var position: [Action: Int] = [:]
        for (index, action) in Action.allCases.enumerated() { position[action] = index }
        func sortKey(_ c: ShortcutConflict) -> (Int, String, UInt16, Int) {
            (position[c.action] ?? Int.max, c.rectangleAction, c.combo.keyCode, c.combo.modifiers.rawValue)
        }
        return found.sorted { sortKey($0) < sortKey($1) }
    }

    // MARK: Reading stored values

    /// True for `true` and for any non-zero number, whatever type the preferences layer used to store it.
    private static func isOn(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }

    private static func integer(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    private static func storedCombo(_ value: Any) -> KeyCombo? {
        guard let entry = value as? [String: Any],
              let code = integer(entry["keyCode"]).flatMap({ UInt16(exactly: $0) }),
              let flags = integer(entry["modifierFlags"]).flatMap({ UInt(exactly: $0) })
        else { return nil }
        return KeyCombo(keyCode: code, modifiers: Modifiers(cocoa: flags))
    }
}
