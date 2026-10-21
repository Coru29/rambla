// TEMPORARY: signature-only stand-ins so the engine compiles and can be tested live before the
// overlay task lands. That task replaces this file with the real controllers.
import AppKit
import RamblaCore

struct IndicatorTile: Identifiable {
    let id: UUID
    let icons: [NSImage]
    let isFocused: Bool
    let isVisible: Bool
}

@MainActor
final class IndicatorController {
    init(onSelect: @escaping (UUID) -> Void, onMove: @escaping (_ from: Int, _ to: Int) -> Void) {}
    func show(_ tiles: [IndicatorTile], on screen: NSScreen, holding: NSEvent.ModifierFlags?) {}
    func hide() {}
}

struct TabItem {
    let windowID: WindowID
    let title: String
    let icon: NSImage?
}

struct TabBarModel {
    let columnID: UUID
    let frame: CGRect
    let tabs: [TabItem]
    let active: Int
}

@MainActor
final class TabBarController {
    init(onSelect: @escaping (WindowID) -> Void) {}
    func update(_ bars: [TabBarModel]) {}
}

@MainActor
final class FocusBorderController {
    func update(frame: CGRect?, windowID: WindowID?, prefs: FocusBorderPrefs) {}
}

@MainActor
final class DimmerController {
    func update(focused: WindowID?, screens: [NSScreen], prefs: DimPrefs) {}
}
