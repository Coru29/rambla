import Testing
import Foundation
@testable import RamblaCore

// MARK: - Helpers

/// A Mac with nothing to warn about: permission granted, separate Spaces, no automatic rearranging (the key exists and
/// is false, because an absent key means "on"), no Stage Manager, no macOS tiling, no gesture or drag conflict.
private func tidyMac(rectangle: RectangleStatus = .notRunning) -> MacSettings {
    MacSettings(accessibilityTrusted: true, displaysShareSpaces: false, rearrangeSpaces: false, stageManager: false,
                tilingByEdgeDrag: false, tilingToMenuBar: false, tilingWithOption: false,
                threeFingerSwipe: [0], fourFingerSwipe: [0], threeFingerDrag: [false], rectangle: rectangle)
}

private func row(_ id: String, in checks: [MacCheck]) throws -> MacCheck {
    try #require(checks.first { $0.id == id }, "no row with id \(id)")
}

private func status(of id: String, _ settings: MacSettings, _ trackpad: TrackpadPrefs = TrackpadPrefs()) throws -> MacCheck.Status {
    try row(id, in: MacChecks.evaluate(settings, trackpad: trackpad)).status
}

private func conflict(_ action: Action, _ rectangleAction: String = "leftHalf") -> ShortcutConflict {
    ShortcutConflict(action: action, combo: KeyCombo(keyCode: KeyCode.left, modifiers: [.control, .option]), rectangleAction: rectangleAction)
}

// MARK: - Rows

@Test func macChecksListTheRowsInOrderAndRectangleOnlyWhileItRuns() {
    let ids = ["accessibility", "separate-spaces", "rearrange-spaces", "stage-manager", "macos-tiling",
               "trackpad-gesture", "three-finger-drag"]
    #expect(MacChecks.evaluate(tidyMac(), trackpad: TrackpadPrefs()).map { $0.id } == ids)
    #expect(MacChecks.evaluate(tidyMac(rectangle: .running(conflicts: [])), trackpad: TrackpadPrefs()).map { $0.id } == ids + ["rectangle"])
    // Row ids are what the UI iterates over, so they must be unique.
    #expect(Set(ids + ["rectangle"]).count == 8)
}

@Test func macChecksATidyMacHasNothingToWarnAbout() {
    for fingers in [3, 4] {
        let checks = MacChecks.evaluate(tidyMac(), trackpad: TrackpadPrefs(fingers: fingers))
        #expect(checks.allSatisfy { $0.status == .ok }, "fingers \(fingers)")
    }
}

@Test func macChecksOnTheUsersMac() throws {
    // Verified on the user's Mac: spans-displays and mru-spaces absent, Stage Manager and tiling explicitly off, both
    // swipe gestures at 2 in both trackpad domains, Rectangle running with no collisions. Rambla's default is 4 fingers.
    let mac = MacSettings(accessibilityTrusted: true, stageManager: false,
                          tilingByEdgeDrag: false, tilingToMenuBar: false, tilingWithOption: false,
                          threeFingerSwipe: [2, 2], fourFingerSwipe: [2, 2], threeFingerDrag: [false, false],
                          rectangle: .running(conflicts: []))
    let checks = MacChecks.evaluate(mac, trackpad: TrackpadPrefs())
    let statuses = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0.status) })
    #expect(statuses == [
        "accessibility": .ok, "separate-spaces": .ok, "rearrange-spaces": .warning, "stage-manager": .ok,
        "macos-tiling": .ok, "trackpad-gesture": .warning, "three-finger-drag": .ok, "rectangle": .info,
    ])
    #expect(try row("rearrange-spaces", in: checks).title == "Reorganizar Spaces")
    let rectangle = try row("rectangle", in: checks)
    #expect(rectangle.detail.contains("Rectangle detectado — convivencia activa"))
    #expect(rectangle.detail.contains("Atajos en conflicto: 0"))
}

// MARK: - Accessibility, Spaces, Stage Manager, tiling

@Test func macChecksAccessibility() throws {
    var mac = tidyMac()
    #expect(try status(of: "accessibility", mac) == .ok)
    mac.accessibilityTrusted = false
    #expect(try status(of: "accessibility", mac) == .warning)
}

@Test func macChecksSeparateSpacesAbsentOrFalseIsFine() throws {
    var mac = tidyMac()
    for value in [nil, false] as [Bool?] {
        mac.displaysShareSpaces = value
        #expect(try status(of: "separate-spaces", mac) == .ok, "spans-displays \(String(describing: value))")
    }
    mac.displaysShareSpaces = true
    #expect(try status(of: "separate-spaces", mac) == .warning)
}

@Test func macChecksRearrangeSpacesIsOnWhenTheKeyIsAbsent() throws {
    var mac = tidyMac()
    mac.rearrangeSpaces = false
    #expect(try status(of: "rearrange-spaces", mac) == .ok)
    for value in [nil, true] as [Bool?] {
        mac.rearrangeSpaces = value
        let check = try row("rearrange-spaces", in: MacChecks.evaluate(mac, trackpad: TrackpadPrefs()))
        #expect(check.status == .warning, "mru-spaces \(String(describing: value))")
        #expect(check.detail.contains("Recomendado: apagado"))
    }
}

@Test func macChecksStageManager() throws {
    var mac = tidyMac()
    for value in [nil, false] as [Bool?] {
        mac.stageManager = value
        #expect(try status(of: "stage-manager", mac) == .ok, "GloballyEnabled \(String(describing: value))")
    }
    mac.stageManager = true
    #expect(try status(of: "stage-manager", mac) == .warning)
}

@Test func macChecksTilingWarnsForAnyOfTheThreeOptionsAndNamesTheOnesThatAreOn() throws {
    func tiling(_ edge: Bool?, _ menuBar: Bool?, _ option: Bool?) throws -> MacCheck {
        var mac = tidyMac()
        mac.tilingByEdgeDrag = edge
        mac.tilingToMenuBar = menuBar
        mac.tilingWithOption = option
        return try row("macos-tiling", in: MacChecks.evaluate(mac, trackpad: TrackpadPrefs()))
    }
    #expect(try tiling(nil, nil, nil).status == .ok)
    #expect(try tiling(false, false, false).status == .ok)

    let edge = try tiling(true, false, false)
    #expect(edge.status == .warning)
    #expect(edge.detail.contains("arrastrar a los bordes"))
    #expect(!edge.detail.contains("barra de menús") && !edge.detail.contains("Opción"))

    let menuBar = try tiling(false, true, nil)
    #expect(menuBar.status == .warning)
    #expect(menuBar.detail.contains("arrastrar a la barra de menús"))
    #expect(!menuBar.detail.contains("bordes") && !menuBar.detail.contains("Opción"))

    let option = try tiling(nil, false, true)
    #expect(option.status == .warning)
    #expect(option.detail.contains("arrastrar con la tecla Opción"))
    #expect(!option.detail.contains("bordes") && !option.detail.contains("barra de menús"))

    let all = try tiling(true, true, true)
    #expect(all.status == .warning)
    #expect(all.detail.contains("bordes") && all.detail.contains("barra de menús") && all.detail.contains("Opción"))
}

// MARK: - Trackpad

@Test func macChecksTrackpadGestureFollowsTheConfiguredFingerCount() throws {
    // (Rambla fingers, three-finger swipe values, four-finger swipe values, warns). Two values mean two trackpad
    // preference domains (built-in and Magic Trackpad); either one can be the trackpad in use.
    let table: [(Int, [Int], [Int], Bool)] = [
        (4, [], [], false),            // absent keys are not a conflict
        (3, [], [], false),
        (4, [], [2], true),
        (4, [0], [2], true),
        (4, [2], [0], false),          // the three-finger setting is irrelevant to a four-finger Rambla gesture
        (4, [2], [], false),
        (4, [], [1], false),           // only 2 ("swipe between full-screen apps") switches Spaces
        (4, [], [0, 2], true),         // second trackpad
        (4, [], [2, 0], true),         // first trackpad
        (3, [2], [], true),
        (3, [2], [0], true),
        (3, [], [2], false),           // the four-finger setting is irrelevant to a three-finger Rambla gesture
        (3, [0], [2], false),
        (3, [1], [2], true),           // 1 is "swipe between pages": the browser would go back while the strip slides
        (4, [1], [0], false),          // …which only ever uses three fingers
        (3, [0, 2], [], true),
        (4, [2, 2], [2, 2], true),     // the user's Mac, with the default gesture
        (3, [2, 2], [2, 2], true),     // the user's Mac, after switching Rambla to three fingers
        (2, [2], [2], false),          // macOS has no horizontal swipe with another number of fingers
        (5, [2], [2], false),
    ]
    for (fingers, three, four, warns) in table {
        var mac = tidyMac()
        mac.threeFingerSwipe = three
        mac.fourFingerSwipe = four
        let expected: MacCheck.Status = warns ? .warning : .ok
        #expect(try status(of: "trackpad-gesture", mac, TrackpadPrefs(fingers: fingers)) == expected,
                "fingers \(fingers), three \(three), four \(four)")
    }
}

private func trackpadRow(three: [Int], four: [Int], fingers: Int, canChange: Bool) throws -> MacCheck {
    var mac = tidyMac()
    mac.threeFingerSwipe = three
    mac.fourFingerSwipe = four
    mac.canChangeTrackpadGestures = canChange
    return try row("trackpad-gesture", in: MacChecks.evaluate(mac, trackpad: TrackpadPrefs(fingers: fingers)))
}

@Test func macChecksExplainThatTheThreeFingerOptionAlsoTurnsOnFour() throws {
    // The user's Mac: Trackpad → Más gestos shows «3 dedos», which System Settings stores as 2 for both counts.
    let fixable = try trackpadRow(three: [2, 2], four: [2, 2], fingers: 4, canChange: true)
    #expect(fixable.status == .warning)
    #expect(fixable.detail.contains("«3 dedos»"))
    #expect(fixable.detail.contains("activa también el de 4"))
    #expect(fixable.detail.contains("sigue cambiando de escritorio con 3"))
    #expect(fixable.fix == .turnOffSwipe(fingers: 4))
    #expect(fixable.settingsURL == MacChecks.trackpadURL)

    let manual = try trackpadRow(three: [2, 2], four: [2, 2], fingers: 4, canChange: false)
    #expect(manual.status == .warning)
    #expect(manual.fix == nil)
    #expect(manual.detail.contains("«Desactivado»"))
    #expect(!manual.detail.contains(MacCheck.Fix.turnOffSwipe(fingers: 4).title))
}

@Test func macChecksFourFingerSwitchingAloneLeavesTheKeyboardForDesktops() throws {
    let check = try trackpadRow(three: [0], four: [2], fingers: 4, canChange: true)
    #expect(check.fix == .turnOffSwipe(fingers: 4))
    #expect(check.detail.contains("⌃←"))
    #expect(!check.detail.contains("«3 dedos»"))
}

@Test func macChecksThreeFingerConflictsNameTheMacOSGesture() throws {
    let spaces = try trackpadRow(three: [2], four: [2], fingers: 3, canChange: true)
    #expect(spaces.fix == .turnOffSwipe(fingers: 3))
    #expect(spaces.detail.contains("cambia de escritorio con 3 dedos"))
    #expect(spaces.detail.contains("sigue cambiando de escritorio con 4"))

    let pages = try trackpadRow(three: [1], four: [0], fingers: 3, canChange: true)
    #expect(pages.fix == .turnOffSwipe(fingers: 3))
    #expect(pages.detail.contains("pasa de página con 3 dedos"))

    let manualPages = try trackpadRow(three: [1], four: [0], fingers: 3, canChange: false)
    #expect(manualPages.fix == nil)
    #expect(manualPages.detail.contains("Cambiar de página"))
}

@Test func macChecksOfferAFixOnlyForAConflict() throws {
    var mac = tidyMac()
    mac.canChangeTrackpadGestures = true
    for check in MacChecks.evaluate(mac, trackpad: TrackpadPrefs()) {
        #expect(check.fix == nil, "row \(check.id)")
    }
    let clear = try trackpadRow(three: [2], four: [0], fingers: 4, canChange: true)
    #expect(clear.status == .ok)
    #expect(clear.fix == nil)
}

@Test func macChecksTrackpadHasNoConflictWhileRamblaGestureIsOff() throws {
    var mac = tidyMac()
    mac.threeFingerSwipe = [2]
    mac.fourFingerSwipe = [2]
    mac.threeFingerDrag = [true]
    for fingers in [3, 4] {
        let off = TrackpadPrefs(enabled: false, fingers: fingers)
        #expect(try status(of: "trackpad-gesture", mac, off) == .ok, "fingers \(fingers)")
        #expect(try status(of: "three-finger-drag", mac, off) == .ok, "fingers \(fingers)")
    }
}

@Test func macChecksThreeFingerDragOnlyCollidesWithAThreeFingerGesture() throws {
    // (Rambla gesture on, fingers, three-finger drag values, warns)
    let table: [(Bool, Int, [Bool], Bool)] = [
        (true, 3, [true], true),
        (true, 3, [false, true], true),    // either trackpad
        (true, 3, [true, false], true),
        (true, 3, [false], false),
        (true, 3, [], false),              // absent key
        (true, 4, [true], false),          // Rambla uses four fingers
        (true, 4, [false, true], false),
        (false, 3, [true], false),         // Rambla's gesture is off
    ]
    for (enabled, fingers, drag, warns) in table {
        var mac = tidyMac()
        mac.threeFingerDrag = drag
        let expected: MacCheck.Status = warns ? .warning : .ok
        #expect(try status(of: "three-finger-drag", mac, TrackpadPrefs(enabled: enabled, fingers: fingers)) == expected,
                "enabled \(enabled), fingers \(fingers), drag \(drag)")
    }
}

// MARK: - Rectangle

@Test func macChecksRectangleIsInformationalWhileNothingCollides() throws {
    let check = try row("rectangle", in: MacChecks.evaluate(tidyMac(rectangle: .running(conflicts: [])), trackpad: TrackpadPrefs()))
    #expect(check.title == "Rectangle")
    #expect(check.status == .info)
    #expect(check.detail.contains("Rectangle detectado — convivencia activa"))
    #expect(check.detail.contains("Atajos en conflicto: 0"))
}

@Test func macChecksRectangleWarnsWithTheNumberOfCollisionsAndTheActionsInvolved() throws {
    // Two Rambla shortcuts of the same action count twice but the action is named once.
    let few = [conflict(.focusLeft), conflict(.focusLeft, "topLeft"), conflict(.center)]
    let fewCheck = try row("rectangle", in: MacChecks.evaluate(tidyMac(rectangle: .running(conflicts: few)), trackpad: TrackpadPrefs()))
    #expect(fewCheck.status == .warning)
    #expect(fewCheck.detail.contains("Rectangle detectado — convivencia activa"))
    #expect(fewCheck.detail.contains("Atajos en conflicto: 3 (Enfocar columna izquierda, Centrar columna)"))

    // More than three actions: the first three by action order, then how many are left.
    let many = [Action.focusLeft, .focusRight, .focusUp, .focusDown, .center].map { conflict($0) }
    let manyCheck = try row("rectangle", in: MacChecks.evaluate(tidyMac(rectangle: .running(conflicts: many)), trackpad: TrackpadPrefs()))
    #expect(manyCheck.status == .warning)
    #expect(manyCheck.detail.contains("Atajos en conflicto: 5"))
    #expect(manyCheck.detail.contains("Enfocar columna izquierda, Enfocar columna derecha, Enfocar ventana de arriba y 2 más"))
    #expect(!manyCheck.detail.contains("Centrar columna"))
}

@Test func macChecksRectangleWithTheRealShortcutTables() throws {
    // The user's Rectangle: "recommended" ⌃⌥ set plus custom ⌃⌥Z, ⌃⌥N and ⌃⌥B. Rambla lives in ⌃⌘ space, so no collisions.
    let theirs = RectangleShortcuts.effective(preferences: [
        "alternateDefaultShortcuts": true,
        "centerTwoThirds": ["keyCode": 6, "modifierFlags": 786432],
        "reflowTodo": ["keyCode": 45, "modifierFlags": 786432],
        "toggleTodo": ["keyCode": 11, "modifierFlags": 786432],
    ])
    let none = RectangleShortcuts.conflicts(ours: Preferences().allShortcuts, theirs: theirs)
    #expect(none.isEmpty)
    let quiet = try row("rectangle", in: MacChecks.evaluate(tidyMac(rectangle: .running(conflicts: none)), trackpad: TrackpadPrefs()))
    #expect(quiet.status == .info)

    // Moving "Enfocar columna izquierda" onto ⌃⌥← (Rectangle's left half) collides.
    var prefs = Preferences()
    prefs.setShortcuts([KeyCombo(keyCode: KeyCode.left, modifiers: [.control, .option])], for: .focusLeft)
    let found = RectangleShortcuts.conflicts(ours: prefs.allShortcuts, theirs: theirs)
    #expect(found.count == 1)
    let loud = try row("rectangle", in: MacChecks.evaluate(tidyMac(rectangle: .running(conflicts: found)), trackpad: TrackpadPrefs()))
    #expect(loud.status == .warning)
    #expect(loud.detail.contains("Atajos en conflicto: 1 (Enfocar columna izquierda)"))
}

// MARK: - System Settings links

@Test func macChecksSettingsLinks() throws {
    #expect(MacChecks.accessibilityURL.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    #expect(MacChecks.desktopAndDockURL.absoluteString == "x-apple.systempreferences:com.apple.Desktop-Settings.extension")
    #expect(MacChecks.trackpadURL.absoluteString == "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")

    // Only Accessibility, Rearrange Spaces and the trackpad gesture open a pane.
    let checks = MacChecks.evaluate(tidyMac(rectangle: .running(conflicts: [])), trackpad: TrackpadPrefs())
    let links = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0.settingsURL) })
    #expect(links == [
        "accessibility": MacChecks.accessibilityURL, "separate-spaces": nil, "rearrange-spaces": MacChecks.desktopAndDockURL,
        "stage-manager": nil, "macos-tiling": nil, "trackpad-gesture": MacChecks.trackpadURL, "three-finger-drag": nil,
        "rectangle": nil,
    ])
}
