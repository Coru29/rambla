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
    private lazy var overview = OverviewController { [weak self] id, key in self?.engine.focus(window: id, in: key) }
    private let border = FocusBorderController()
    private let dimmer = DimmerController()
    private var indicatorKey: StripKey?
    private var icons: [pid_t: NSImage] = [:]
    private var tints: [pid_t: NSColor] = [:]

    init(engine: WindowManager) {
        self.engine = engine
        engine.overlayHook = { [weak self] in self?.refresh() }
        engine.indicatorHook = { [weak self] key, modifiers in self?.showIndicator(key, holding: modifiers) }
        engine.overviewHook = { [weak self] key in self?.toggleOverview(key) }
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
        guard let display = engine.display(for: key), let content = overviewContent(for: key, display: display) else { return }
        indicator.hide()
        overview.show(content, key: key, on: display.screen)
    }

    private func overviewContent(for key: StripKey, display: DisplayInfo) -> OverviewContent? {
        guard let strip = engine.strips[key], !strip.columns.isEmpty, let result = engine.results[key] else { return nil }
        let hidden = engine.hidden[key] ?? []
        var pinned: [UUID: Double] = [:]
        for column in strip.columns where column.pinned != nil {
            if let frame = result.columnFrames[column.id] { pinned[column.id] = Double(frame.width) }
        }
        let gap = engine.prefs.innerGap
        let overview = Overview(strip: strip, metrics: result.metrics, pinnedWidths: pinned, gap: gap, hidden: hidden,
                                focused: engine.focusedWindow)
        var items: [WindowID: OverviewItem] = [:]
        for column in strip.columns {
            for id in column.windows {
                let record = engine.windows[id]
                let app = record.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName } ?? ""
                items[id] = OverviewItem(app: app, title: record?.title ?? "", icon: icon(for: id), tint: tint(for: id),
                                         hidden: hidden.contains(id))
            }
        }
        // Cards keep the windows' proportions: as tall as a share of the screen, narrower when the strip is long.
        let screen = display.screen.frame
        var scale = screen.height * Self.overviewHeight / max(display.visible.height, 1)
        let room = screen.width - 160
        if CGFloat(overview.total) * scale > room {
            scale = max(room / CGFloat(max(overview.total, 1)), Self.overviewMinScale)
        }
        return OverviewContent(overview: overview, items: items, scale: scale, gap: gap,
                               cardHeight: display.visible.height * scale)
    }

    /// The app's color for its miniature in the overview.
    private func tint(for id: WindowID) -> NSColor {
        guard let pid = engine.windows[id]?.pid else { return Self.neutralTint }
        if let cached = tints[pid] { return cached }
        let color = Self.tint(of: icon(for: id))
        tints[pid] = color
        return color
    }

    private static let neutralTint = NSColor(calibratedHue: 0.6, saturation: 0.14, brightness: 0.3, alpha: 1)

    /// An icon's color, weighted by saturation so its color counts more than its white or gray parts, then made dark
    /// and calm enough for white text. A gray icon (a terminal, say) gets a neutral slate.
    static func tint(of image: NSImage?) -> NSColor {
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return neutralTint }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return neutralTint }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[index]) / 255 / alpha, g = Double(pixels[index + 1]) / 255 / alpha
            let b = Double(pixels[index + 2]) / 255 / alpha
            let w = 0.1 + max(r, g, b) - min(r, g, b)
            red += r * w
            green += g * w
            blue += b * w
            weight += w
        }
        guard weight > 0 else { return neutralTint }
        let average = NSColor(calibratedRed: red / weight, green: green / weight, blue: blue / weight, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation > 0.15 else { return neutralTint }
        return NSColor(calibratedHue: hue, saturation: min(max(saturation, 0.3), 0.62), brightness: 0.4, alpha: 1)
    }
}
