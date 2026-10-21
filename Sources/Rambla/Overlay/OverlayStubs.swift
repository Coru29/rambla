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
