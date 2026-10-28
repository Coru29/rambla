import AppKit
import RamblaCore
import UniformTypeIdentifiers

/// Feeds the overlays (strip indicator, tab bars, focus border, dimming, overview) from the engine's state. What the
/// user does on them (choosing or moving a column, a tab, a window of the overview, closing it) comes after the
/// switches between strips waiting for the veil, as anything asked of Rambla does (`runPendingSwitches`).
@MainActor
final class OverlayCoordinator {
    private let engine: WindowManager
    private lazy var indicator = IndicatorController(
        onSelect: { [weak self] id in self?.selectColumn(id) },
        onMove: { [weak self] from, to in self?.moveColumn(from: from, to: to) })
    private lazy var tabBars = TabBarController { [weak self] id in
        self?.engine.runPendingSwitches()
        self?.engine.focusTab(id)
    }
    private lazy var overview = OverviewController(
        onChoose: { [weak self] id, key in self?.focusFromOverview(id, in: key) },
        onMove: { [weak self] column, target, key, window in
            self?.moveFromOverview(column, toPlaceOf: target, in: key, selecting: window)
        },
        onSend: { [weak self] column, key, level, index, window in
            self?.sendFromOverview(column, from: key, toLevel: level, at: index, selecting: window)
        },
        onDismiss: { [weak self] in
            self?.engine.runPendingSwitches()
            self?.engine.keepKeyboardInView()
        })
    private let border = FocusBorderController()
    private let hint = HintController()
    private let dimmer = DimmerController()
    /// The veils over the switches between strips: once one covers its display the switches waiting for it run, and it
    /// goes once the apps have moved their windows, or after a quarter of a second.
    private lazy var veil = LevelTransitionController(
        covered: { [weak self] in self?.engine.runPendingSwitches() },
        settle: { [weak self] done in
            guard let self else { return done() }
            engine.afterPendingMoves(timeout: 0.25, done)
        })
    private var indicatorKey: StripKey?
    private var icons: [pid_t: NSImage] = [:]
    private var tints: [pid_t: NSColor] = [:]
    /// The sites the browser windows show, which the overview and the veil draw them with (`look`).
    private lazy var pages: PageIcons = {
        let pages = PageIcons { [weak self] id, done in
            guard let self else { return done(nil) }
            engine.readPage(of: id, done)
        }
        pages.changed = { [weak self] in self?.pagesChanged() }
        return pages
    }()
    /// Stands in for the icon of an app that has none.
    private lazy var genericIcon = NSWorkspace.shared.icon(for: .application)

    init(engine: WindowManager) {
        self.engine = engine
        engine.overlayHook = { [weak self] in self?.refresh() }
        engine.indicatorHook = { [weak self] key, modifiers in self?.showIndicator(key, holding: modifiers) }
        engine.levelHook = { [weak self] stack in self?.levelChanged(on: stack) }
        engine.titleHook = { [weak self] id in self?.titleChanged(id) }
        engine.emptyLevelHook = { [weak self] stack in self?.showEmptyStripHint(of: stack) }
        engine.levelTransition = { [weak self] stack, up in self?.coverSwitch(of: stack, up: up) ?? false }
        engine.levelTransitionReset = { [weak self] in self?.veil.reset() }
        engine.overviewHook = { [weak self] key in self?.toggleOverview(key) }
        engine.overviewAction = { [weak self] action in self?.overview.perform(action) ?? false }
        engine.overviewSwipe = { [weak self] stack, up, move in self?.overview.swipe(on: stack, up: up, move: move) ?? nil }
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
        engine.runPendingSwitches()
        guard let key = indicatorKey else { return }
        engine.focusColumn(id: id, in: key)
        showIndicator(key, holding: nil)
    }

    /// Indicator positions are in visual order; map them back to strip columns (pinned ones stay put).
    private func moveColumn(from: Int, to: Int) {
        engine.runPendingSwitches()
        guard let key = indicatorKey, let (_, order) = tiles(for: key), let strip = engine.strips[key],
              order.indices.contains(from), order.indices.contains(to) else { return }
        let source = order[from], target = order[to]
        guard strip.columns[source].pinned == nil, strip.columns[target].pinned == nil else { return }
        engine.moveColumn(in: key, from: source, to: target)
        showIndicator(key, holding: nil)
    }

    // MARK: - Strip levels

    /// The strips of a stack as the levels panel draws them, the highest first: the icons of the apps of each strip's
    /// columns in visual order, each from the first window of its column that is not hidden. A level without a strip
    /// is an empty row.
    private func levelRows(of stack: StackKey) -> [LevelRow] {
        let active = engine.activeLevel(of: stack)
        return (0...engine.topLevel(of: stack)).reversed().map { level in
            let key = stack.level(level)
            let strip = engine.strips[key] ?? Strip()
            let hidden = engine.hidden[key] ?? []
            // One icon per column, so that a strip with windows never reads as empty: an app with no icon gets the
            // generic one.
            let icons = strip.visualOrder(hidden: hidden).map { index -> NSImage in
                let window = strip.columns[index].windows.first { !hidden.contains($0) }
                return window.flatMap { icon(for: $0) } ?? genericIcon
            }
            return LevelRow(id: level, icons: icons, isActive: level == active)
        }
    }

    /// A switch between strips the user asked for waits for the veil of the stack's display to cover it, and the veil
    /// waits for the windows to be in their places before it goes. False with the animations off, as every move is
    /// instant then, or without that display: the switch runs at once.
    private func coverSwitch(of stack: StackKey, up: Bool) -> Bool {
        let prefs = engine.prefs
        guard prefs.animations, let display = engine.display(forStack: stack) else { return false }
        veil.request(on: display, up: up, speed: prefs.animationSpeed,
                     reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                     cards: { [weak self] in self?.veilCards(of: stack) ?? [] })
        return true
    }

    /// The windows shown on the display of `stack`, as the veil draws them: the strip in view's, column by column (the
    /// tab a tabbed column shows), then the floating windows in view, the focused window last, on top. Each where it is
    /// going: those of a strip that just came into view went there at once.
    private func veilCards(of stack: StackKey) -> [VeilCard] {
        guard let display = engine.display(forStack: stack), let key = engine.currentKey(of: display) else { return [] }
        var shown: [(id: WindowID, frame: CGRect)] = []
        if let strip = engine.strips[key], let placements = engine.results[key]?.placements {
            let hidden = engine.hidden[key] ?? []
            for column in strip.columns {
                let windows = column.mode == .tabbed ? column.activeWindow.map { [$0] } ?? [] : column.windows
                for id in windows where !hidden.contains(id) {
                    guard case .visible(let frame)? = placements[id] else { continue }
                    shown.append((id, engine.animator.current[id] ?? frame))
                }
            }
        }
        // The floating windows that go with the strips: those parked with a strip out of view are not shown.
        let parked = Set(engine.floatShelf.values.flatMap(\.keys)).union(engine.floatsAway.keys)
        let onScreen = WindowManager.windowIDs(onScreenOnly: true)
        for id in engine.floating.sorted() where !parked.contains(id) && onScreen.contains(id) {
            guard let record = engine.windows[id], !record.traits.isMinimized,
                  NSRunningApplication(processIdentifier: record.pid)?.isHidden != true else { continue }
            // Where it is, unless it is still parked off the display: then where it was just sent back to.
            var frame = record.frame
            if frame.intersection(display.visible).width < frame.width / 2, let going = engine.requested[id] {
                frame = going
            }
            guard Displays.best(for: frame, in: engine.displays)?.uuid == display.uuid else { continue }
            shown.append((id, frame))
        }
        if let focused = engine.focusedWindow, let index = shown.firstIndex(where: { $0.id == focused }) {
            shown.append(shown.remove(at: index))
        }
        return shown.compactMap { id, frame in
            guard frame.intersects(display.visible), let record = engine.windows[id] else { return nil }
            let look = look(of: id)
            return VeilCard(id: id, frame: frame, app: look.name, title: record.title, icon: look.icon ?? genericIcon,
                            tint: look.tint)
        }
    }

    /// Another strip of `stack` came into view. The hint of an empty strip that was left goes, unless the strip that
    /// came is empty too: Rambla holds the keyboard then (`takeKeyboardFocus`), and the engine has just shown that
    /// strip's own hint. An overview of the stack no longer shows the strip in view as it is, and goes.
    private func levelChanged(on stack: StackKey) {
        if engine.focusedWindow != nil { hint.hide() }
        if overview.shows(stack) { overview.close() }
        showLevels(of: stack)
    }

    /// Shows the stack on its display, unless the indicator is off. With one strip left (the empty one that was just
    /// left is dropped) there is nothing to tell apart: nothing is shown, and the panel of the switch before, which still
    /// lists the dropped strip, goes.
    private func showLevels(of stack: StackKey) {
        guard engine.prefs.indicatorEnabled, let display = engine.display(forStack: stack) else { return }
        let rows = levelRows(of: stack)
        guard rows.count > 1 else {
            indicator.hide()
            return
        }
        indicator.showLevels(rows, on: display.screen)
    }

    /// An empty strip came into view and Rambla holds the keyboard, with nothing on screen to show for it: the hint
    /// says how to fill it and how to go back.
    private func showEmptyStripHint(of stack: StackKey) {
        guard let display = engine.display(forStack: stack) else { return }
        hint.show(String(localized: "Tira vacía"), detail: emptyStripDetail(of: stack), on: display.screen)
    }

    /// The hint's second line (`EmptyStripHint`), from the levels as the switch left them (the empty ones that were not
    /// needed went before the hook ran) and from the shortcuts and the swipe the user has.
    private func emptyStripDetail(of stack: StackKey) -> String {
        EmptyStripHint.detail(active: engine.activeLevel(of: stack), occupied: engine.occupiedLevels(of: stack),
                              prefs: engine.prefs, shortcutName: KeyNames.display)
    }

    // MARK: - Overview

    /// Opens the overview of the stack of `key`, the strip in view, or closes it when it is on screen. A stack without a
    /// window in any of its strips has nothing to show: a hint says how to bring one.
    private func toggleOverview(_ key: StripKey) {
        if overview.isShown {
            overview.hide()
            return
        }
        guard let display = engine.display(for: key) else { return }
        guard let content = overviewContent(for: key.stack, display: display) else {
            showEmptyHint(on: display.screen)
            return
        }
        hint.hide()
        indicator.hide()
        overview.show(content, stack: key.stack, on: display.screen)
    }

    private func showEmptyHint(on screen: NSScreen) {
        let detail = engine.prefs.shortcuts(for: .sendNextDisplay).first.map {
            String(localized: "Con \(KeyNames.display($0)) mandás acá la ventana enfocada, o arrastrá una desde otra pantalla.")
        } ?? String(localized: "Arrastrá una ventana hasta acá desde otra pantalla.")
        hint.show(String(localized: "Esta pantalla no tiene ventanas"), detail: detail, on: screen)
    }

    /// The overview of a stack: a row per level from the top one down to 0, each laid out as it is in view, or would be
    /// (a strip out of view keeps its place for when it comes back). `selecting` is the window the overview starts on
    /// (the focused one, and in each other row its strip's focused column, when nil). Nil when no strip has a window.
    private func overviewContent(for stack: StackKey, display: DisplayInfo, selecting: WindowID? = nil) -> OverviewContent? {
        var rows: [OverviewStack.Row] = []
        var items: [WindowID: OverviewItem] = [:]
        for level in (0...engine.topLevel(of: stack)).reversed() {
            let key = stack.level(level)
            let strip = engine.strips[key] ?? Strip()
            let hidden = engine.hidden[key] ?? []
            let result = Layout.compute(engine.layoutInput(for: key, strip: strip, display: display))
            var pinned: [UUID: Double] = [:]
            for column in strip.columns where column.pinned != nil {
                if let frame = result.columnFrames[column.id] { pinned[column.id] = Double(frame.width) }
            }
            rows.append(OverviewStack.Row(level: level, overview: Overview(
                strip: strip, metrics: result.metrics, pinnedWidths: pinned, gap: engine.prefs.innerGap, hidden: hidden,
                focused: selecting ?? engine.focusedWindow)))
            for id in strip.allWindows {
                let look = look(of: id)
                items[id] = OverviewItem(app: look.name, title: engine.windows[id]?.title ?? "", icon: look.icon,
                                         tint: look.tint, hidden: hidden.contains(id))
            }
        }
        guard rows.contains(where: { !$0.overview.cards.isEmpty }) else { return nil }
        let active = engine.activeLevel(of: stack)
        var model = OverviewStack(rows: rows, activeLevel: active)
        if let selecting, let row = rows.firstIndex(where: { $0.overview.cards.contains { $0.windows.contains(selecting) } }) {
            model.select(row: row, rows[row].overview.selection)
        }
        return OverviewContent(stack: model, items: items, activeLevel: active, screen: display.screen.frame.size,
                               visible: display.visible.size)
    }

    /// A column moved in its row of the overview: its strip changes, and the overview shows the stack as it is now.
    /// Columns are found by id, since the strip may have changed since the overview was made.
    private func moveFromOverview(_ column: UUID, toPlaceOf target: UUID, in key: StripKey,
                                  selecting window: WindowID?) -> OverviewContent? {
        engine.runPendingSwitches()
        guard let display = engine.display(forStack: key.stack), let strip = engine.strips[key],
              let from = strip.index(ofColumn: column), let to = strip.index(ofColumn: target) else { return nil }
        engine.moveColumn(in: key, from: from, to: to)
        return overviewContent(for: key.stack, display: display, selecting: window)
    }

    /// A column sent to another strip of the stack in the overview (dragged to another row or to the new strip, or
    /// ⇧↑ ⇧↓): the overview shows the stack as it is now. The overview holds the keyboard meanwhile, so a focused window
    /// that goes out of view with its column hands it over only once the overview closes (`onDismiss`).
    private func sendFromOverview(_ column: UUID, from key: StripKey, toLevel level: Int, at index: Int?,
                                  selecting window: WindowID?) -> OverviewContent? {
        engine.runPendingSwitches()
        guard let display = engine.display(forStack: key.stack), engine.strips[key]?.index(ofColumn: column) != nil else {
            return nil
        }
        engine.moveColumn(id: column, from: key, toLevel: level, at: index, handOverKeyboard: false)
        guard engine.strips[key.stack.level(level)]?.index(ofColumn: column) != nil else { return nil }
        return overviewContent(for: key.stack, display: display, selecting: window)
    }

    /// A window chosen in the overview, unless it closed meanwhile. One of the strip in view gets the focus; one of
    /// another strip brings that strip into view, with it focused. When it is gone, the overview has closed all the
    /// same, so the keyboard comes back from it as when the user closes it (`keepKeyboardInView`).
    private func focusFromOverview(_ id: WindowID, in key: StripKey) {
        engine.runPendingSwitches()
        guard engine.windows[id] != nil, engine.strips[key]?.contains(id) == true else {
            NSSound.beep()
            engine.keepKeyboardInView()
            return
        }
        if key.level == engine.activeLevel(of: key.stack) {
            engine.focus(window: id, in: key)
        } else {
            engine.switchLevel(of: key.stack, to: key.level, focusing: id)
        }
    }

    /// How a window shows in the overview and on the veil: its app's name, icon and color, or for a browser window the
    /// site it shows, once known (`PageIcons`).
    private func look(of id: WindowID) -> (name: String, icon: NSImage?, tint: NSColor) {
        let record = engine.windows[id]
        let app = record.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName } ?? ""
        guard let record, let page = pages.look(of: id, bundleID: record.bundleID, title: record.title,
                                                 browserIcon: icon(for: id)) else {
            return (app, icon(for: id), tint(for: id))
        }
        return (page.site, page.icon ?? icon(for: id), page.tint ?? tint(for: id))
    }

    /// A window's title changed: for a browser window, the site it shows may have changed with it.
    private func titleChanged(_ id: WindowID) {
        guard let record = engine.windows[id] else { return }
        pages.titleChanged(id, bundleID: record.bundleID, title: record.title)
    }

    /// A site the browser windows show, or its icon, came: the overview on screen draws its windows again.
    private func pagesChanged() {
        overview.updateItems { items in
            for (id, item) in items {
                let look = look(of: id)
                items[id] = OverviewItem(app: look.name, title: item.title, icon: look.icon, tint: look.tint,
                                         hidden: item.hidden)
            }
        }
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
