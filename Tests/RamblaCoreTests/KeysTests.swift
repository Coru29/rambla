import Testing
import Foundation
@testable import RamblaCore

// MARK: - Actions

/// Every action id with its Spanish title, in spec order (independent transcription of the spec table).
private let specActions: [(id: String, title: String)] = [
    ("focus-left", "Enfocar columna izquierda"),
    ("focus-right", "Enfocar columna derecha"),
    ("focus-up", "Enfocar ventana de arriba"),
    ("focus-down", "Enfocar ventana de abajo"),
    ("focus-first", "Ir a la primera columna"),
    ("focus-last", "Ir a la última columna"),
    ("focus-1", "Ir a la columna 1"),
    ("focus-2", "Ir a la columna 2"),
    ("focus-3", "Ir a la columna 3"),
    ("focus-4", "Ir a la columna 4"),
    ("focus-5", "Ir a la columna 5"),
    ("focus-6", "Ir a la columna 6"),
    ("focus-7", "Ir a la columna 7"),
    ("focus-8", "Ir a la columna 8"),
    ("focus-9", "Ir a la columna 9"),
    ("move-left", "Mover columna a la izquierda"),
    ("move-right", "Mover columna a la derecha"),
    ("move-up", "Mover ventana hacia arriba"),
    ("move-down", "Mover ventana hacia abajo"),
    ("send-next-display", "Mandar a la siguiente pantalla"),
    ("strip-up", "Ir a la tira de arriba"),
    ("strip-down", "Ir a la tira de abajo"),
    ("send-strip-up", "Mandar a la tira de arriba"),
    ("send-strip-down", "Mandar a la tira de abajo"),
    ("overview", "Vista general"),
    ("cycle-width", "Rotar ancho"),
    ("full-width", "Ancho completo"),
    ("center", "Centrar columna"),
    ("wider", "Más ancha"),
    ("narrower", "Más angosta"),
    ("taller", "Más alta"),
    ("shorter", "Más baja"),
    ("equalize-heights", "Igualar alturas"),
    ("pin-left", "Fijar a la izquierda"),
    ("pin-right", "Fijar a la derecha"),
    ("stack-left", "Apilar en la columna izquierda"),
    ("stack-right", "Apilar en la columna derecha"),
    ("pop-left", "Sacar de la pila hacia la izquierda"),
    ("pop-right", "Sacar de la pila hacia la derecha"),
    ("toggle-tabbed", "Alternar pila / pestañas"),
    ("toggle-float", "Flotar / volver a la tira"),
    ("close-window", "Cerrar ventana"),
    ("toggle-pause", "Pausar / reanudar Rambla"),
]

@Test func actionIdsMatchSpecInOrder() {
    #expect(Action.allCases.map { $0.rawValue } == specActions.map { $0.id })
    #expect(Action.allCases.count == 43)
    #expect(Action.focus1.rawValue == "focus-1")
    #expect(Action.focus9.rawValue == "focus-9")
}

@Test func actionTitlesMatchSpec() throws {
    for (id, title) in specActions {
        let action = try #require(Action(rawValue: id), "unknown action id \(id)")
        #expect(action.title == title, "title of \(id)")
    }
}

@Test func actionGroupsMatchSpec() {
    let expected: [ActionGroup: [String]] = [
        .navigate: ["focus-left", "focus-right", "focus-up", "focus-down", "focus-first", "focus-last",
                    "focus-1", "focus-2", "focus-3", "focus-4", "focus-5", "focus-6", "focus-7", "focus-8", "focus-9",
                    "move-left", "move-right", "move-up", "move-down", "send-next-display",
                    "strip-up", "strip-down", "send-strip-up", "send-strip-down", "overview"],
        .size: ["cycle-width", "full-width", "center", "wider", "narrower", "taller", "shorter",
                "equalize-heights", "pin-left", "pin-right"],
        .stacks: ["stack-left", "stack-right", "pop-left", "pop-right", "toggle-tabbed", "toggle-float"],
        .other: ["close-window", "toggle-pause"],
    ]
    for group in ActionGroup.allCases {
        let members = Action.allCases.filter { $0.group == group }
        let ids: [String] = members.map { $0.rawValue }
        #expect(ids == (expected[group] ?? []), "group \(group)")
    }
    #expect(ActionGroup.allCases == [.navigate, .size, .stacks, .other])
    #expect(ActionGroup.allCases.map { $0.title } == ["Navegar", "Tamaño", "Pilas y pestañas", "Otros"])
}

@Test func actionParseAcceptsIds() {
    for action in Action.allCases { #expect(Action.parse(action.rawValue) == action) }
    #expect(Action.parse("focus-left") == .focusLeft)
    #expect(Action.parse("focus-3") == .focus3)
    #expect(Action.parse("toggle-pause") == .togglePause)
    // Forgiving about case and surrounding whitespace (URL hosts, shell input).
    #expect(Action.parse("Focus-Left") == .focusLeft)
    #expect(Action.parse(" focus-right\n") == .focusRight)
    // Anything else is not an action.
    for word in ["", "focus", "focus-0", "focus-10", "focusLeft", "focus_left", "dump", "list"] {
        #expect(Action.parse(word) == nil, "\(word) must not parse")
    }
}

@Test func newActionsParseTheirIDs() {
    #expect(Action.parse("strip-up") == .stripUp)
    #expect(Action.parse("strip-down") == .stripDown)
    #expect(Action.parse("send-strip-up") == .sendStripUp)
    #expect(Action.parse("send-strip-down") == .sendStripDown)
}

@Test func actionDictionaryEncodesAsObjectKeyedById() throws {
    let table: [Action: [KeyCombo]] = [
        .focusLeft: [KeyCombo(keyCode: 0x7B, modifiers: [.control, .command])],
        .togglePause: [],
    ]
    let data = try JSONEncoder().encode(table)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["focus-left", "toggle-pause"])
    #expect(try JSONDecoder().decode([Action: [KeyCombo]].self, from: data) == table)
}

// MARK: - Default shortcuts

/// The spec's default table, transcribed with raw virtual key codes and modifier symbols so that it also checks `KeyCode`.
private let specShortcuts: [(id: String, combos: [(code: UInt16, mods: String)])] = [
    ("focus-left", [(0x7B, "⌃⌘"), (0x04, "⌃⌘")]),
    ("focus-right", [(0x7C, "⌃⌘"), (0x25, "⌃⌘")]),
    ("focus-up", [(0x7E, "⌃⌘"), (0x28, "⌃⌘")]),
    ("focus-down", [(0x7D, "⌃⌘"), (0x26, "⌃⌘")]),
    ("focus-first", [(0x00, "⌃⌘")]),
    ("focus-last", [(0x0E, "⌃⌘")]),
    ("focus-1", [(0x12, "⌃⌘")]),
    ("focus-2", [(0x13, "⌃⌘")]),
    ("focus-3", [(0x14, "⌃⌘")]),
    ("focus-4", [(0x15, "⌃⌘")]),
    ("focus-5", [(0x17, "⌃⌘")]),
    ("focus-6", [(0x16, "⌃⌘")]),
    ("focus-7", [(0x1A, "⌃⌘")]),
    ("focus-8", [(0x1C, "⌃⌘")]),
    ("focus-9", [(0x19, "⌃⌘")]),
    ("move-left", [(0x7B, "⌃⇧⌘"), (0x04, "⌃⇧⌘")]),
    ("move-right", [(0x7C, "⌃⇧⌘"), (0x25, "⌃⇧⌘")]),
    ("move-up", [(0x7E, "⌃⇧⌘"), (0x28, "⌃⇧⌘")]),
    ("move-down", [(0x7D, "⌃⇧⌘"), (0x26, "⌃⇧⌘")]),
    ("send-next-display", [(0x2D, "⌃⌘")]),
    ("strip-up", [(0x7E, "⌃⌥⌘")]),
    ("strip-down", [(0x7D, "⌃⌥⌘")]),
    ("send-strip-up", [(0x7E, "⌃⌥⇧⌘")]),
    ("send-strip-down", [(0x7D, "⌃⌥⇧⌘")]),
    ("overview", [(0x1F, "⌃⌘")]),
    ("cycle-width", [(0x0F, "⌃⌘")]),
    ("full-width", [(0x2E, "⌃⌘")]),
    ("center", [(0x08, "⌃⌘")]),
    ("wider", [(0x18, "⌃⌘")]),
    ("narrower", [(0x1B, "⌃⌘")]),
    ("taller", [(0x18, "⌃⇧⌘")]),
    ("shorter", [(0x1B, "⌃⇧⌘")]),
    ("equalize-heights", [(0x1D, "⌃⌘")]),
    ("pin-left", [(0x23, "⌃⌘")]),
    ("pin-right", [(0x23, "⌃⇧⌘")]),
    ("stack-left", [(0x21, "⌃⌘")]),
    ("stack-right", [(0x1E, "⌃⌘")]),
    ("pop-left", [(0x21, "⌃⇧⌘")]),
    ("pop-right", [(0x1E, "⌃⇧⌘")]),
    ("toggle-tabbed", [(0x11, "⌃⇧⌘")]),
    ("toggle-float", [(0x11, "⌃⌘")]),
    ("close-window", []),
    ("toggle-pause", []),
]

private func describeCombos(_ combos: [KeyCombo]) -> [String] {
    combos.map { String(format: "%02X", $0.keyCode) + " " + $0.modifiers.symbols }
}

@Test func defaultsComplete() {
    for action in Action.allCases {
        let combos = DefaultShortcuts.table[action]
        #expect(combos != nil, "missing table entry for \(action.rawValue)")
        if action == .closeWindow || action == .togglePause {
            #expect(combos == [], "\(action.rawValue) has no default shortcut")
        } else {
            #expect(!(combos ?? []).isEmpty, "\(action.rawValue) needs at least one default shortcut")
            for combo in combos ?? [] {
                #expect(combo.modifiers.contains(.control) && combo.modifiers.contains(.command),
                        "\(action.rawValue) default must include ⌃ and ⌘")
            }
        }
    }
}

@Test func defaultsUnique() {
    let all = DefaultShortcuts.table.values.flatMap { $0 }
    #expect(Set(all).count == all.count)
}

@Test func focusLeftDefaults() {
    #expect(DefaultShortcuts.table[.focusLeft] == [
        KeyCombo(keyCode: 0x7B, modifiers: [.control, .command]),
        KeyCombo(keyCode: 0x04, modifiers: [.control, .command]),
    ])
}

@Test func stripShortcutDefaults() {
    // ⌃⌥⌘ moves between the stacked strips and ⇧ takes the focused window along.
    let go: Modifiers = [.control, .option, .command]
    let send: Modifiers = [.control, .option, .shift, .command]
    #expect(DefaultShortcuts.table[.stripUp] == [KeyCombo(keyCode: KeyCode.up, modifiers: go)])
    #expect(DefaultShortcuts.table[.stripDown] == [KeyCombo(keyCode: KeyCode.down, modifiers: go)])
    #expect(DefaultShortcuts.table[.sendStripUp] == [KeyCombo(keyCode: KeyCode.up, modifiers: send)])
    #expect(DefaultShortcuts.table[.sendStripDown] == [KeyCombo(keyCode: KeyCode.down, modifiers: send)])
}

@Test func defaultsMatchSpecTable() throws {
    #expect(specShortcuts.count == Action.allCases.count)
    #expect(DefaultShortcuts.table.count == Action.allCases.count)
    for (id, combos) in specShortcuts {
        let action = try #require(Action(rawValue: id), "unknown action id \(id)")
        let expected = combos.map { String(format: "%02X", $0.code) + " " + $0.mods }
        #expect(describeCombos(DefaultShortcuts.table[action] ?? []) == expected, "defaults of \(id)")
        #expect((DefaultShortcuts.table[action] ?? []).count <= 2, "an action admits at most 2 shortcuts")
    }
}

@Test func defaultsAvoidSystemShortcuts() {
    // Spec: ⌃⌘F (full screen), ⌃⌘Q (lock), ⌃⌘D (dictionary) and ⌃⌘Space (emoji) stay free.
    let taken = Set(DefaultShortcuts.table.values.flatMap { $0 })
    for code: UInt16 in [0x03, 0x0C, 0x02, 0x31] {
        let isTaken = taken.contains(KeyCombo(keyCode: code, modifiers: [.control, .command]))
        #expect(!isTaken, "key code \(code) with ⌃⌘ is a system shortcut")
    }
}

// MARK: - Rectangle shortcut tables

/// Rectangle's two default sets, transcribed independently from the brief (name, key code, modifier symbols).
private let specAlternate: [(name: String, code: UInt16, mods: String)] = [
    ("leftHalf", 0x7B, "⌃⌥"), ("rightHalf", 0x7C, "⌃⌥"), ("bottomHalf", 0x7D, "⌃⌥"), ("topHalf", 0x7E, "⌃⌥"),
    ("bottomLeft", 0x26, "⌃⌥"), ("bottomRight", 0x28, "⌃⌥"), ("topLeft", 0x20, "⌃⌥"), ("topRight", 0x22, "⌃⌥"),
    ("maximize", 0x24, "⌃⌥"), ("maximizeHeight", 0x7E, "⌃⌥⇧"),
    ("previousDisplay", 0x7B, "⌃⌥⌘"), ("nextDisplay", 0x7C, "⌃⌥⌘"),
    ("larger", 0x18, "⌃⌥"), ("smaller", 0x1B, "⌃⌥"), ("center", 0x08, "⌃⌥"), ("restore", 0x33, "⌃⌥"),
    ("firstThird", 0x02, "⌃⌥"), ("firstTwoThirds", 0x0E, "⌃⌥"), ("centerThird", 0x03, "⌃⌥"),
    ("lastTwoThirds", 0x11, "⌃⌥"), ("lastThird", 0x05, "⌃⌥"), ("centerTwoThirds", 0x0F, "⌃⌥"),
]

private let specSpectacle: [(name: String, code: UInt16, mods: String)] = [
    ("leftHalf", 0x7B, "⌥⌘"), ("rightHalf", 0x7C, "⌥⌘"), ("maximize", 0x03, "⌥⌘"), ("maximizeHeight", 0x7E, "⌃⌥⇧"),
    ("previousDisplay", 0x7B, "⌃⌥⌘"), ("nextDisplay", 0x7C, "⌃⌥⌘"),
    ("larger", 0x7C, "⌃⌥⇧"), ("smaller", 0x7B, "⌃⌥⇧"),
    ("bottomHalf", 0x7D, "⌥⌘"), ("topHalf", 0x7E, "⌥⌘"), ("center", 0x08, "⌥⌘"),
    ("bottomLeft", 0x7B, "⌃⇧⌘"), ("bottomRight", 0x7C, "⌃⇧⌘"),
    ("topLeft", 0x7B, "⌃⌘"), ("topRight", 0x7C, "⌃⌘"), ("restore", 0x33, "⌃⌥"),
]

private func describeTable(_ table: [String: KeyCombo]) -> [String: String] {
    table.mapValues { String(format: "%02X", $0.keyCode) + " " + $0.modifiers.symbols }
}

private func describeSpec(_ rows: [(name: String, code: UInt16, mods: String)]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: rows.map { ($0.name, String(format: "%02X", $0.code) + " " + $0.mods) })
}

@Test func rectangleTablesAreTranscribedFromRectangle() {
    #expect(specAlternate.count == 22)
    #expect(specSpectacle.count == 16)
    #expect(describeTable(RectangleShortcuts.alternateDefaults) == describeSpec(specAlternate))
    #expect(describeTable(RectangleShortcuts.spectacleDefaults) == describeSpec(specSpectacle))
}

@Test func defaultsDoNotCollideWithRectangleAlternate() {
    let theirs = RectangleShortcuts.effective(preferences: [
        "alternateDefaultShortcuts": true,
        "centerTwoThirds": ["keyCode": 6, "modifierFlags": 786432],
        "toggleTodo": ["keyCode": 11, "modifierFlags": 786432],
        "reflowTodo": ["keyCode": 45, "modifierFlags": 786432],
    ])
    #expect(RectangleShortcuts.conflicts(ours: DefaultShortcuts.table, theirs: theirs).isEmpty)
    // The user's three custom shortcuts really did land in the effective table.
    #expect(theirs["centerTwoThirds"] == KeyCombo(keyCode: 0x06, modifiers: [.control, .option]))
    #expect(theirs["toggleTodo"] == KeyCombo(keyCode: 0x0B, modifiers: [.control, .option]))
    #expect(theirs["reflowTodo"] == KeyCombo(keyCode: 0x2D, modifiers: [.control, .option]))
}

@Test func spectacleCollides() {
    let theirs = RectangleShortcuts.effective(preferences: ["alternateDefaultShortcuts": false])
    let found = RectangleShortcuts.conflicts(ours: DefaultShortcuts.table, theirs: theirs)
    let focusLeft = KeyCombo(keyCode: 0x7B, modifiers: [.control, .command])
    #expect(found.contains(ShortcutConflict(action: .focusLeft, combo: focusLeft, rectangleAction: "topLeft")))
    #expect(found.contains { $0.action == .focusRight && $0.rectangleAction == "topRight" })
    #expect(found.contains { $0.action == .moveLeft && $0.rectangleAction == "bottomLeft" })
    #expect(found.contains { $0.action == .moveRight && $0.rectangleAction == "bottomRight" })
    #expect(found.count == 4)
}

@Test func conflictsAreSortedByActionThenRectangleName() {
    let left = KeyCombo(keyCode: 0x7B, modifiers: [.control, .command])
    let right = KeyCombo(keyCode: 0x7C, modifiers: [.control, .command])
    let ours: [Action: [KeyCombo]] = [.focusRight: [right], .focusLeft: [left], .togglePause: []]
    let theirs: [String: KeyCombo] = ["zeta": left, "alpha": left, "beta": right]
    let expected = ["focus-left:alpha", "focus-left:zeta", "focus-right:beta"]
    for _ in 0..<20 {
        let found = RectangleShortcuts.conflicts(ours: ours, theirs: theirs)
        #expect(found.map { "\($0.action.rawValue):\($0.rectangleAction)" } == expected)
    }
    #expect(RectangleShortcuts.conflicts(ours: ours, theirs: [:]).isEmpty)
    #expect(RectangleShortcuts.conflicts(ours: [:], theirs: theirs).isEmpty)
}

@Test func effectiveBaseDependsOnAlternateFlag() {
    let alternate = RectangleShortcuts.alternateDefaults
    let spectacle = RectangleShortcuts.spectacleDefaults
    #expect(RectangleShortcuts.effective(preferences: [:]) == spectacle)
    #expect(RectangleShortcuts.effective(preferences: ["alternateDefaultShortcuts": false]) == spectacle)
    #expect(RectangleShortcuts.effective(preferences: ["alternateDefaultShortcuts": 0]) == spectacle)
    #expect(RectangleShortcuts.effective(preferences: ["alternateDefaultShortcuts": NSNumber(value: false)]) == spectacle)
    #expect(RectangleShortcuts.effective(preferences: ["alternateDefaultShortcuts": true]) == alternate)
    #expect(RectangleShortcuts.effective(preferences: ["alternateDefaultShortcuts": 1]) == alternate)
    #expect(RectangleShortcuts.effective(preferences: ["alternateDefaultShortcuts": 2]) == alternate)
    #expect(RectangleShortcuts.effective(preferences: ["alternateDefaultShortcuts": NSNumber(value: 1)]) == alternate)
    #expect(RectangleShortcuts.effective(preferences: ["alternateDefaultShortcuts": NSNumber(value: true)]) == alternate)
}

@Test func effectiveOverridesAndAddsFromStoredDictionaries() {
    let prefs: [String: Any] = [
        "alternateDefaultShortcuts": true,
        // Plain Swift dictionary with Int values replaces an existing action: ⌃⌘A.
        "leftHalf": ["keyCode": 0, "modifierFlags": 262_144 + 1_048_576],
        // What CFPreferences hands back: NSDictionary of NSNumber, plus the arrow/numeric-pad noise bits.
        "toggleTodo": NSDictionary(dictionary: ["keyCode": NSNumber(value: 11),
                                                "modifierFlags": NSNumber(value: 786_432 | 2_097_152 | 8_388_608 | 65_536)]),
        // Other numeric representations are fine too.
        "reflowTodo": ["keyCode": Int64(45), "modifierFlags": UInt(786_432)] as [String: Any],
        "someUnrelatedSetting": "text",
    ]
    let effective = RectangleShortcuts.effective(preferences: prefs)
    #expect(effective["leftHalf"] == KeyCombo(keyCode: 0x00, modifiers: [.control, .command]))
    #expect(effective["toggleTodo"] == KeyCombo(keyCode: 0x0B, modifiers: [.control, .option]))
    #expect(effective["reflowTodo"] == KeyCombo(keyCode: 0x2D, modifiers: [.control, .option]))
    #expect(effective["rightHalf"] == RectangleShortcuts.alternateDefaults["rightHalf"])
    #expect(effective.count == RectangleShortcuts.alternateDefaults.count + 2)
}

@Test func effectiveIgnoresMalformedEntries() {
    let prefs: [String: Any] = [
        "missingFlags": ["keyCode": 5],
        "missingKeyCode": ["modifierFlags": 786_432],
        "stringKeyCode": ["keyCode": "5", "modifierFlags": 786_432] as [String: Any],
        "negativeKeyCode": ["keyCode": -1, "modifierFlags": 786_432],
        "hugeKeyCode": ["keyCode": 70_000, "modifierFlags": 786_432],
        "negativeFlags": ["keyCode": 5, "modifierFlags": -4],
        "notADictionary": 42,
        "nullish": NSNull(),
        "list": [1, 2, 3],
    ]
    #expect(RectangleShortcuts.effective(preferences: prefs) == RectangleShortcuts.spectacleDefaults)
}

// MARK: - Modifiers and key combos

@Test func modifiersRoundTrip() {
    #expect(Modifiers(cocoa: 786432) == [.control, .option])
    #expect(([.control, .command] as Modifiers).carbon == 0x1100)
    #expect(([.control, .command] as Modifiers).symbols == "⌃⌘")
    #expect(([.control, .option, .shift, .command] as Modifiers).symbols == "⌃⌥⇧⌘")
    #expect(([.control, .option, .shift, .command] as Modifiers).cocoa == 0x1E0000)
    for raw in 0..<16 {
        let m = Modifiers(rawValue: raw)
        #expect(Modifiers(cocoa: m.cocoa) == m)
    }
}

@Test func modifiersMapSingleFlagsToCocoaAndCarbon() {
    #expect(Modifiers.control.rawValue == 1)
    #expect(Modifiers.option.rawValue == 2)
    #expect(Modifiers.shift.rawValue == 4)
    #expect(Modifiers.command.rawValue == 8)
    #expect(Modifiers.control.carbon == 0x1000)
    #expect(Modifiers.option.carbon == 0x0800)
    #expect(Modifiers.shift.carbon == 0x0200)
    #expect(Modifiers.command.carbon == 0x0100)
    #expect(Modifiers.shift.cocoa == 1 << 17)
    #expect(Modifiers.control.cocoa == 1 << 18)
    #expect(Modifiers.option.cocoa == 1 << 19)
    #expect(Modifiers.command.cocoa == 1 << 20)
    #expect(Modifiers([]).carbon == 0)
    #expect(Modifiers([]).symbols == "")
}

@Test func modifiersCocoaIgnoresUnrelatedBits() {
    let caps: UInt = 1 << 16
    let numericPad: UInt = 1 << 21
    let function: UInt = 1 << 23
    let deviceBits: UInt = 0x2A
    let noise: UInt = caps | numericPad | function | deviceBits
    let commandBit: UInt = 1 << 20
    #expect(Modifiers(cocoa: noise) == Modifiers([]))
    #expect(Modifiers(cocoa: commandBit | noise) == Modifiers.command)
}

@Test func keyComboJSONRoundTrip() throws {
    let combo = KeyCombo(keyCode: 0x7B, modifiers: [.control, .shift, .command])
    let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
    #expect(decoded == combo)
    #expect(combo.modifiers.rawValue == 13)
}
