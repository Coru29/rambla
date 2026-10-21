import Testing
import Foundation
@testable import RamblaCore

private func decodePreferences(_ json: String) throws -> Preferences {
    try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
}

@Test func preferencesDefaultsFromEmptyJSON() throws {
    #expect(try decodePreferences("{}") == Preferences())
}

@Test func preferencesDefaultValues() {
    let p = Preferences()
    #expect(p.enabled == true)
    #expect(p.innerGap == 8)
    #expect(p.outerGap == 8)
    let presets: [Double] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75]
    #expect(p.presetWidths == presets)
    #expect(p.newWindowWidth == .natural)
    #expect(p.nudgeStep == 0.05)
    #expect(p.centerMode == .never)
    #expect(p.keepOriginalHeight == false)
    #expect(p.animations == true)
    #expect(p.animationSpeed == 1.0)
    #expect(p.floatOnExternalMove == true)
    #expect(p.indicatorEnabled == true)
    #expect(p.focusBorder == FocusBorderPrefs())
    #expect(p.focusBorder.enabled == false)
    #expect(p.focusBorder.colorHex == "#0A84FF")
    #expect(p.focusBorder.width == 3)
    #expect(p.dimInactive == DimPrefs())
    #expect(p.dimInactive.enabled == false)
    #expect(p.dimInactive.amount == 0.25)
    #expect(p.focusFollowsMouse == false)
    #expect(p.mouseFollowsFocus == false)
    #expect(p.trackpad == TrackpadPrefs())
    #expect(p.trackpad.enabled == true)
    #expect(p.trackpad.fingers == 4)
    #expect(p.trackpad.sensitivity == 1.0)
    #expect(p.trackpad.natural == true)
    #expect(p.appRules.isEmpty)
    #expect(p.disabledDisplays.isEmpty)
    #expect(p.shortcutOverrides.isEmpty)
}

@Test func preferencesPartialJSONKeepsOtherDefaults() throws {
    let p = try decodePreferences("""
    {"innerGap": 12, "centerMode": "always", "focusBorder": {"enabled": true},
     "trackpad": {"fingers": 3}, "dimInactive": {"amount": 0.5}}
    """)
    var expected = Preferences()
    expected.innerGap = 12
    expected.centerMode = .always
    expected.focusBorder.enabled = true
    expected.trackpad.fingers = 3
    expected.dimInactive.amount = 0.5
    #expect(p == expected)
    // Nested defaults survive a partial object.
    #expect(p.focusBorder.colorHex == "#0A84FF")
    #expect(p.focusBorder.width == 3)
    #expect(p.trackpad.sensitivity == 1.0)
    #expect(p.dimInactive.enabled == false)
}

private func customizedPreferences() -> Preferences {
    var p = Preferences()
    p.enabled = false
    p.innerGap = 4
    p.outerGap = 0
    p.presetWidths = [0.3, 0.6]
    p.newWindowWidth = .fraction(0.4)
    p.nudgeStep = 0.1
    p.centerMode = .onOverflow
    p.keepOriginalHeight = true
    p.animations = false
    p.animationSpeed = 1.75
    p.floatOnExternalMove = false
    p.indicatorEnabled = false
    p.focusBorder = FocusBorderPrefs(enabled: true, colorHex: "#FF3B30", width: 5)
    p.dimInactive = DimPrefs(enabled: true, amount: 0.4)
    p.focusFollowsMouse = true
    p.mouseFollowsFocus = true
    p.trackpad = TrackpadPrefs(enabled: false, fingers: 3, sensitivity: 1.5, natural: false)
    p.appRules = [
        AppRule(bundleID: "com.apple.finder", name: "Finder", behavior: .float),
        AppRule(bundleID: "com.apple.TextEdit", name: "TextEdit", behavior: .tile, width: 0.5, openAt: .end),
    ]
    p.disabledDisplays = ["37D8832A-2D66-02CA-B9F7-8F30A301B230"]
    p.setShortcuts([KeyCombo(keyCode: KeyCode.left, modifiers: [.control, .option, .command])], for: .focusLeft)
    p.setShortcuts([], for: .focusRight)   // a deliberately disabled default
    return p
}

@Test func preferencesRoundTrip() throws {
    // Defaults.
    let defaults = Preferences()
    #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(defaults)) == defaults)
    // Everything customized, including rules (their ids are random, so compare against the original instance).
    let original = customizedPreferences()
    let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
    #expect(decoded.appRules.map { $0.id } == original.appRules.map { $0.id })
    #expect(decoded.newWindowWidth == .fraction(0.4))
}

@Test func preferencesEncodeShortcutOverridesAsObjectKeyedById() throws {
    var p = Preferences()
    p.setShortcuts([KeyCombo(keyCode: 0x00, modifiers: [.control, .option])], for: .focusFirst)
    let data = try JSONEncoder().encode(p)
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let overrides = try #require(root["shortcutOverrides"] as? [String: Any])
    #expect(Set(overrides.keys) == ["focus-first"])
}

@Test func preferencesDecodeSkipsUnknownShortcutOverrideIds() throws {
    let p = try decodePreferences("""
    {"innerGap": 3, "shortcutOverrides": {
        "focus-left": [{"keyCode": 0, "modifiers": 3}],
        "action-from-the-future": [{"keyCode": 1, "modifiers": 1}]}}
    """)
    #expect(p.innerGap == 3)
    #expect(p.shortcutOverrides == [.focusLeft: [KeyCombo(keyCode: 0, modifiers: [.control, .option])]])
}

@Test func overrideRemovedWhenDefault() {
    var p = Preferences()
    let custom = [KeyCombo(keyCode: KeyCode.f, modifiers: [.control, .option, .command])]
    p.setShortcuts(custom, for: .focusLeft)
    #expect(p.shortcutOverrides[.focusLeft] == custom)
    #expect(p.shortcuts(for: .focusLeft) == custom)
    // Setting the defaults again drops the override instead of storing a copy of the defaults.
    p.setShortcuts(DefaultShortcuts.table[.focusLeft] ?? [], for: .focusLeft)
    #expect(p.shortcutOverrides[.focusLeft] == nil)
    #expect(p.shortcutOverrides.isEmpty)
    #expect(p.shortcuts(for: .focusLeft) == DefaultShortcuts.table[.focusLeft])
}

@Test func shortcutsFallBackToDefaultsAndHonorOverrides() {
    var p = Preferences()
    for action in Action.allCases { #expect(p.shortcuts(for: action) == (DefaultShortcuts.table[action] ?? [])) }
    let custom = [KeyCombo(keyCode: KeyCode.k, modifiers: [.control, .option, .command])]
    p.setShortcuts(custom, for: .closeWindow)
    #expect(p.shortcuts(for: .closeWindow) == custom)
    #expect(p.shortcuts(for: .togglePause) == [])
}

@Test func emptyOverrideDisablesAShortcutThatHasADefault() {
    var p = Preferences()
    p.setShortcuts([], for: .focusLeft)
    #expect(p.shortcuts(for: .focusLeft) == [])
    #expect(p.shortcutOverrides[.focusLeft] == [])
    // For an action whose default is already empty, an empty list is the default and leaves no override.
    p.setShortcuts([], for: .closeWindow)
    #expect(p.shortcutOverrides[.closeWindow] == nil)
}

@Test func allShortcutsMergesOverridesIntoDefaults() {
    var p = Preferences()
    #expect(p.allShortcuts == DefaultShortcuts.table)
    let custom = [KeyCombo(keyCode: KeyCode.z, modifiers: [.control, .option, .command])]
    p.setShortcuts(custom, for: .center)
    p.setShortcuts([], for: .focus1)
    let all = p.allShortcuts
    #expect(all.count == Action.allCases.count)
    #expect(all[.center] == custom)
    #expect(all[.focus1] == [])
    #expect(all[.focusRight] == DefaultShortcuts.table[.focusRight])
    #expect(all[.togglePause] == [])
}

@Test func ruleLookupByBundleID() {
    var p = Preferences()
    let finder = AppRule(bundleID: "com.apple.finder", name: "Finder", behavior: .float)
    let again = AppRule(bundleID: "com.apple.finder", name: "Finder (duplicate)", behavior: .tile)
    let textEdit = AppRule(bundleID: "com.apple.TextEdit", name: "TextEdit", width: 0.6)
    p.appRules = [finder, again, textEdit]
    #expect(p.rule(for: "com.apple.finder") == finder)          // first match wins
    #expect(p.rule(for: "com.apple.TextEdit") == textEdit)
    #expect(p.rule(for: "com.apple.Safari") == nil)
    #expect(p.rule(for: nil) == nil)
    #expect(Preferences().rule(for: "com.apple.finder") == nil)
}

@Test func appRuleDefaultsAndDecoding() throws {
    let rule = AppRule(bundleID: "com.apple.Terminal", name: "Terminal")
    #expect(rule.behavior == .tile)
    #expect(rule.width == nil)
    #expect(rule.openAt == .afterFocused)
    #expect(AppRule(bundleID: "a", name: "A").id != AppRule(bundleID: "a", name: "A").id)

    let minimal = try JSONDecoder().decode(AppRule.self, from: Data(#"{"bundleID": "com.apple.Terminal", "name": "Terminal"}"#.utf8))
    #expect(minimal.bundleID == "com.apple.Terminal")
    #expect(minimal.name == "Terminal")
    #expect(minimal.behavior == .tile)
    #expect(minimal.width == nil)
    #expect(minimal.openAt == .afterFocused)

    let full = AppRule(bundleID: "com.apple.Notes", name: "Notes", behavior: .float, width: 0.33, openAt: .start)
    #expect(try JSONDecoder().decode(AppRule.self, from: JSONEncoder().encode(full)) == full)
}

@Test func newWindowWidthRoundTrip() throws {
    for value in [NewWindowWidth.natural, .fraction(0.5), .fraction(1.0 / 3)] {
        let decoded = try JSONDecoder().decode(NewWindowWidth.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
    }
    #expect(NewWindowWidth.natural != NewWindowWidth.fraction(0.5))
}
