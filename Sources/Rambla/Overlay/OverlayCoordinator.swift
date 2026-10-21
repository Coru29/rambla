import AppKit
import RamblaCore

/// Feeds the overlays (strip indicator, tab bars, focus border, dimming) from the engine's state.
@MainActor
final class OverlayCoordinator {
    private let engine: WindowManager
    private lazy var indicator = IndicatorController(
        onSelect: { [weak self] id in self?.selectColumn(id) },
        onMove: { [weak self] from, to in self?.moveColumn(from: from, to: to) })
    private lazy var tabBars = TabBarController { [weak self] id in self?.engine.focusTab(id) }
    private let border = FocusBorderController()
    private let dimmer = DimmerController()
    private var indicatorKey: StripKey?
    private var icons: [pid_t: NSImage] = [:]

    init(engine: WindowManager) {
        self.engine = engine
        engine.overlayHook = { [weak self] in self?.refresh() }
        engine.indicatorHook = { [weak self] key, modifiers in self?.showIndicator(key, holding: modifiers) }
    }

    func refresh() {
        let prefs = engine.prefs
        let active = engine.isRunning && !engine.isPaused
        tabBars.update(active ? tabBarModels() : [])
        let focused = engine.focusedWindow
        let frame = focused.flatMap { engine.animator.current[$0] ?? engine.windows[$0]?.frame }
        border.update(frame: active ? frame : nil, windowID: focused, prefs: prefs.focusBorder)
        dimmer.update(focused: active ? focused : nil, screens: NSScreen.screens, prefs: prefs.dimInactive)
    }

    private func icon(for id: WindowID) -> NSImage? {
        guard let pid = engine.windows[id]?.pid else { return nil }
        if let cached = icons[pid] { return cached }
        let image = NSRunningApplication(processIdentifier: pid)?.icon
        icons[pid] = image
        return image
    }

    private func tabBarModels() -> [TabBarModel] {
        var bars: [TabBarModel] = []
        for key in engine.currentKeys {
            guard let strip = engine.strips[key], let result = engine.results[key] else { continue }
            let hidden = engine.hidden[key] ?? []
            for column in strip.columns where column.mode == .tabbed {
                guard var frame = result.tabBars[column.id], let active = column.activeWindow else { continue }
                // Follow the column while it animates.
                if let moving = engine.animator.current[active], let target = engine.requested[active] {
                    frame.origin.x += moving.minX - target.minX
                }
                let windows = column.windows.filter { !hidden.contains($0) }
                guard !windows.isEmpty else { continue }
                let tabs = windows.map { TabItem(windowID: $0, title: engine.windows[$0]?.title ?? "", icon: icon(for: $0)) }
                bars.append(TabBarModel(columnID: column.id, frame: frame, tabs: tabs,
                                        active: windows.firstIndex(of: active) ?? 0))
            }
        }
        return bars
    }

    private func tiles(for key: StripKey) -> (tiles: [IndicatorTile], order: [Int])? {
        guard let strip = engine.strips[key] else { return nil }
        let hidden = engine.hidden[key] ?? []
        let order = strip.visualOrder(hidden: hidden)
        let placements = engine.results[key]?.placements ?? [:]
        let tiles = order.map { index -> IndicatorTile in
            let column = strip.columns[index]
            let visible = column.windows.filter { !hidden.contains($0) }
            let isVisible = visible.contains { id in
                if case .visible = placements[id] { return true }
                return false
            }
            return IndicatorTile(id: column.id, icons: visible.prefix(3).compactMap { icon(for: $0) },
                                 isFocused: index == strip.focused, isVisible: isVisible)
        }
        return (tiles, order)
    }

    private func showIndicator(_ key: StripKey, holding modifiers: NSEvent.ModifierFlags?) {
        guard engine.prefs.indicatorEnabled, let display = engine.display(for: key),
              let (tiles, _) = tiles(for: key), !tiles.isEmpty else { return }
        indicatorKey = key
        indicator.show(tiles, on: display.screen, holding: modifiers)
    }

    private func selectColumn(_ id: UUID) {
        guard let key = indicatorKey else { return }
        engine.focusColumn(id: id, in: key)
        showIndicator(key, holding: nil)
    }

    /// Indicator positions are in visual order; map them back to strip columns (pinned ones stay put).
    private func moveColumn(from: Int, to: Int) {
        guard let key = indicatorKey, let (_, order) = tiles(for: key), let strip = engine.strips[key],
              order.indices.contains(from), order.indices.contains(to) else { return }
        let source = order[from], target = order[to]
        guard strip.columns[source].pinned == nil, strip.columns[target].pinned == nil else { return }
        engine.moveColumn(in: key, from: source, to: target)
        showIndicator(key, holding: nil)
    }
}
