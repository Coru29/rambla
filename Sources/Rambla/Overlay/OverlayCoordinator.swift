import AppKit
import RamblaCore

/// Feeds the overlays (strip indicator, tab bars, focus border, dimming, overview) from the engine's state.
@MainActor
final class OverlayCoordinator {
    private let engine: WindowManager
    private lazy var indicator = IndicatorController(
        onSelect: { [weak self] id in self?.selectColumn(id) },
        onMove: { [weak self] from, to in self?.moveColumn(from: from, to: to) })
    private lazy var tabBars = TabBarController { [weak self] id in self?.engine.focusTab(id) }
    private lazy var overview = OverviewController(
        onChoose: { [weak self] id, key in self?.focusFromOverview(id, in: key) },
        onMove: { [weak self] column, target, key, window in
            self?.moveFromOverview(column, toPlaceOf: target, in: key, selecting: window)
        })
    private let border = FocusBorderController()
    private let hint = HintController()
    private let dimmer = DimmerController()
    private var indicatorKey: StripKey?
    private var icons: [pid_t: NSImage] = [:]
    private var tints: [pid_t: NSColor] = [:]

    init(engine: WindowManager) {
        self.engine = engine
        engine.overlayHook = { [weak self] in self?.refresh() }
        engine.indicatorHook = { [weak self] key, modifiers in self?.showIndicator(key, holding: modifiers) }
        engine.overviewHook = { [weak self] key in self?.toggleOverview(key) }
        engine.overviewAction = { [weak self] action in self?.overview.perform(action) ?? false }
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

    // MARK: - Overview

    /// Largest card height, as a share of the screen: an overview, not another copy of the screen.
    private static let overviewHeight: CGFloat = 0.42
    /// Smallest scale before the strip scrolls sideways instead of shrinking further.
    private static let overviewMinScale: CGFloat = 0.16

    private func toggleOverview(_ key: StripKey) {
        if overview.isShown {
            overview.hide()
            return
        }
        guard let display = engine.display(for: key) else { return }
        guard let content = overviewContent(for: key, display: display) else {
            // A display without windows has nothing to show: say how to bring one.
            if engine.strips[key]?.columns.isEmpty ?? true { showEmptyHint(on: display.screen) }
            return
        }
        indicator.hide()
        overview.show(content, key: key, on: display.screen)
    }

    private func showEmptyHint(on screen: NSScreen) {
        let detail = engine.prefs.shortcuts(for: .sendNextDisplay).first.map {
            String(localized: "Con \(KeyNames.display($0)) mandás acá la ventana enfocada, o arrastrá una desde otra pantalla.")
        } ?? String(localized: "Arrastrá una ventana hasta acá desde otra pantalla.")
        hint.show(String(localized: "Esta pantalla no tiene ventanas"), detail: detail, on: screen)
    }

    /// `selecting` is the window the overview starts on (the focused one when nil).
    private func overviewContent(for key: StripKey, display: DisplayInfo, selecting: WindowID? = nil) -> OverviewContent? {
        guard let strip = engine.strips[key], !strip.columns.isEmpty, let result = engine.results[key] else { return nil }
        let hidden = engine.hidden[key] ?? []
        var pinned: [UUID: Double] = [:]
        for column in strip.columns where column.pinned != nil {
            if let frame = result.columnFrames[column.id] { pinned[column.id] = Double(frame.width) }
        }
        let overview = Overview(strip: strip, metrics: result.metrics, pinnedWidths: pinned, gap: engine.prefs.innerGap,
                                hidden: hidden, focused: selecting ?? engine.focusedWindow)
        var items: [WindowID: OverviewItem] = [:]
        for column in strip.columns {
            for id in column.windows {
                let record = engine.windows[id]
                let app = record.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName } ?? ""
                items[id] = OverviewItem(app: app, title: record?.title ?? "", icon: icon(for: id), tint: tint(for: id),
                                         hidden: hidden.contains(id))
            }
        }
        // Cards keep the windows' proportions: as tall as a share of the screen, narrower when the strip is long. Small
        // cards and gaps are drawn wider than their share, so it shrinks a few times until the row fits.
        let screen = display.screen.frame
        var content = OverviewContent(overview: overview, items: items,
                                      scale: screen.height * Self.overviewHeight / max(display.visible.height, 1),
                                      cardHeight: 0)
        let room = screen.width - 160
        for _ in 0..<3 {
            let width = CGFloat(content.drawn.width)
            guard width > room, content.scale > Self.overviewMinScale else { break }
            content.scale = max(content.scale * room / width, Self.overviewMinScale)
        }
        content.cardHeight = display.visible.height * content.scale
        return content
    }

    /// A column moved in the overview: the strip behind it changes, and the overview shows it as it is now. Columns
    /// are found by id, since the strip may have changed since the overview was made.
    private func moveFromOverview(_ column: UUID, toPlaceOf target: UUID, in key: StripKey,
                                  selecting window: WindowID?) -> OverviewContent? {
        guard let display = engine.display(for: key), let strip = engine.strips[key],
              let from = strip.index(ofColumn: column), let to = strip.index(ofColumn: target) else { return nil }
        engine.moveColumn(in: key, from: from, to: to)
        return overviewContent(for: key, display: display, selecting: window)
    }

    /// A window chosen in the overview, unless it closed meanwhile.
    private func focusFromOverview(_ id: WindowID, in key: StripKey) {
        guard engine.windows[id] != nil, engine.strips[key]?.contains(id) == true else {
            NSSound.beep()
            return
        }
        engine.focus(window: id, in: key)
    }

    /// The app's color for its miniature in the overview.
    private func tint(for id: WindowID) -> NSColor {
        guard let pid = engine.windows[id]?.pid else { return OverviewItem.neutralTint }
        if let cached = tints[pid] { return cached }
        let color = OverviewItem.tint(of: icon(for: id))
        tints[pid] = color
        return color
    }
}
