import AppKit
import SwiftUI

/// One column of the strip, as the indicator draws it.
struct IndicatorTile: Identifiable {
    let id: UUID
    let icons: [NSImage]
    let isFocused: Bool
    let isVisible: Bool
}

/// The strip overview: a frosted panel above the Dock with one tile per column. It appears after navigating or
/// moving columns and fades out on its own. A click on a tile focuses that column; dragging a tile reorders.
///
/// The panel never takes focus. The only timer exists while it is on screen: it polls the modifier keys at
/// 10 Hz so the panel stays while the keys of the last shortcut are held.
@MainActor
final class IndicatorController {
    private static let visibleDuration: CFTimeInterval = 0.8
    private static let fadeDuration: TimeInterval = 0.2
    private static let modifierPollInterval: TimeInterval = 0.1
    private static let cornerRadius: CGFloat = 14
    /// Distance between the panel and the bottom of the screen's visible area (so it sits above the Dock).
    private static let bottomOffset: CGFloat = 12
    private static let screenMargin: CGFloat = 12
    /// Horizontal travel that turns a click into a drag.
    private static let dragThreshold: CGFloat = 4
    /// How long a press may outlast the physical button before it counts as lost (a quick tap is never lost).
    private static let stuckPressGrace: CFTimeInterval = 0.5
    private static let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    private let onSelect: (UUID) -> Void
    private let onMove: (_ from: Int, _ to: Int) -> Void
    private let model = IndicatorModel()
    private var panel: OverlayPanel?
    private var timer: Timer?
    private var hideDeadline: CFAbsoluteTime = 0
    private var heldModifiers: NSEvent.ModifierFlags = []
    /// Our own bookkeeping of "on screen": the timer must not depend on `NSWindow.isVisible` to know when to stop.
    private var isShown = false
    private var isFading = false
    /// Invalidates the completion of a fade that was cancelled by a newer `show`.
    private var fadeToken = 0
    /// The tile under the mouse button while it is down, where the press began, and when.
    private var press: (index: Int, x: CGFloat, at: CFAbsoluteTime)?

    init(onSelect: @escaping (UUID) -> Void, onMove: @escaping (_ from: Int, _ to: Int) -> Void) {
        self.onSelect = onSelect
        self.onMove = onMove
    }

    // MARK: - Showing and hiding

    /// Shows (or refreshes) the indicator on `screen`. It fades out 0.8 s after the last call, but not while every
    /// modifier in `holding` is still down.
    func show(_ tiles: [IndicatorTile], on screen: NSScreen, holding: NSEvent.ModifierFlags?) {
        guard !tiles.isEmpty else {
            hide()
            return
        }
        // While a tile is pressed the mouse owns the content; whatever happens next refreshes it.
        guard press == nil else { return }
        let panel = panel ?? makePanel()
        let visible = screen.visibleFrame
        let metrics = IndicatorMetrics(count: tiles.count, maxWidth: visible.width - 2 * Self.screenMargin)
        model.set(tiles: tiles, metrics: metrics)

        let size = metrics.size
        let x = (visible.midX - size.width / 2).rounded()
        let y = (visible.minY + Self.bottomOffset).rounded()
        let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
        cancelFade()
        if !panel.isVisible { panel.orderFrontRegardless() }
        isShown = true

        heldModifiers = (holding ?? []).intersection(Self.modifierMask)
        hideDeadline = CFAbsoluteTimeGetCurrent() + Self.visibleDuration
        startTimer()
    }

    /// Takes the indicator off screen at once.
    func hide() {
        stopTimer()
        cancelFade()
        press = nil
        model.endDrag()
        isShown = false
        panel?.orderOut(nil)
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.modifierPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isShown, let panel else {
            stopTimer()
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        // The system can take the event stream mid-drag (screen lock, a dialog) and the mouse-up never comes:
        // without this, `show` would ignore every update from then on.
        if let press, now - press.at > Self.stuckPressGrace, NSEvent.pressedMouseButtons & 1 == 0 {
            self.press = nil
            model.endDrag()
            hideDeadline = now + Self.visibleDuration
        }
        guard press == nil, now >= hideDeadline else { return }
        if !heldModifiers.isEmpty, NSEvent.modifierFlags.contains(heldModifiers) { return }
        fadeOut(panel)
    }

    private func fadeOut(_ panel: OverlayPanel) {
        stopTimer()
        isFading = true
        fadeToken += 1
        let token = fadeToken
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.fadeToken == token else { return }
                self.isFading = false
                self.isShown = false
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        })
    }

    /// Brings a fading panel back to full opacity (a newer `show` or a click arrived while it faded).
    private func cancelFade() {
        guard isFading, let panel else { return }
        isFading = false
        fadeToken += 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
    }

    // MARK: - Panel

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(level: .statusBar, collectionBehavior: [.canJoinAllSpaces, .transient])
        panel.hasShadow = true

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        // The panel is never key, and the default state would draw the flat "inactive window" look.
        background.state = .active
        background.appearance = NSAppearance(named: .vibrantDark)
        // The mask clips the blur and the window shadow; the layer radius clips the SwiftUI content.
        background.maskImage = OverlayStyle.roundedMask(radius: Self.cornerRadius)
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.masksToBounds = true

        let hosting = OverlayHostingView(rootView: IndicatorContent(model: model))
        hosting.sizingOptions = []
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.onMouseDown = { [weak self] point in self?.mouseDown(at: point) }
        hosting.onMouseDragged = { [weak self] point in self?.mouseDragged(to: point) }
        hosting.onMouseUp = { [weak self] point in self?.mouseUp(at: point) }
        background.addSubview(hosting)

        panel.contentView = background
        self.panel = panel
        return panel
    }

    // MARK: - Mouse

    private func mouseDown(at point: CGPoint) {
        guard let index = model.metrics.index(atX: point.x), model.tiles.indices.contains(index) else { return }
        cancelFade()
        press = (index, point.x, CFAbsoluteTimeGetCurrent())
        startTimer()
    }

    private func mouseDragged(to point: CGPoint) {
        guard let press else { return }
        let travel = point.x - press.x
        if model.dragIndex == nil {
            guard abs(travel) >= Self.dragThreshold else { return }
            model.beginDrag(at: press.index)
        }
        model.drag(by: travel)
    }

    private func mouseUp(at point: CGPoint) {
        guard let press else { return }
        self.press = nil
        hideDeadline = CFAbsoluteTimeGetCurrent() + Self.visibleDuration
        let tileID = model.tiles.indices.contains(press.index) ? model.tiles[press.index].id : nil
        let drop = model.dragIndex.map { (from: $0, to: model.dropIndex ?? $0) }
        // The callbacks refresh the indicator (re-entering `show`), so the mouse state is settled before them.
        withAnimation(.easeOut(duration: 0.15)) {
            model.endDrag()
            if let drop, drop.from != drop.to { onMove(drop.from, drop.to) }
        }
        if drop == nil, let tileID { onSelect(tileID) }
    }
}

// MARK: - Layout

/// Sizes shared by the SwiftUI drawing and the mouse handling, so what is drawn is exactly what is hit.
private struct IndicatorMetrics: Equatable {
    static let baseTile: CGFloat = 44
    static let minimumTile: CGFloat = 20
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 10

    let count: Int
    /// 44 pt, shrunk only when that many tiles would not fit the screen.
    let tile: CGFloat

    init(count: Int, maxWidth: CGFloat) {
        self.count = count
        let columns = CGFloat(max(count, 1))
        let fitting = ((maxWidth - 2 * Self.padding - (columns - 1) * Self.spacing) / columns).rounded(.down)
        tile = min(Self.baseTile, max(Self.minimumTile, fitting))
    }

    var pitch: CGFloat { tile + Self.spacing }

    var size: CGSize {
        let columns = CGFloat(max(count, 1))
        return CGSize(width: 2 * Self.padding + columns * tile + (columns - 1) * Self.spacing,
                      height: tile + 2 * Self.padding)
    }

    func centerX(of index: Int) -> CGFloat {
        Self.padding + CGFloat(index) * pitch + tile / 2
    }

    /// The tile at `x`, or nil over the padding and the gaps between tiles.
    func index(atX x: CGFloat) -> Int? {
        let relative = x - Self.padding
        guard count > 0, relative >= 0 else { return nil }
        let index = Int(relative / pitch)
        return index < count && relative - CGFloat(index) * pitch <= tile ? index : nil
    }

    /// The slot (0..<count) whose cell, tile plus half the gap on each side, contains `x`.
    func slot(atX x: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let slot = Int(((x - Self.padding + Self.spacing / 2) / pitch).rounded(.down))
        return min(max(slot, 0), count - 1)
    }
}

// MARK: - Model

@MainActor
private final class IndicatorModel: ObservableObject {
    @Published private(set) var tiles: [IndicatorTile] = []
    @Published private(set) var metrics = IndicatorMetrics(count: 0, maxWidth: .infinity)
    /// While a tile is dragged: its index, how far it has moved, and the slot it would drop into.
    @Published private(set) var dragIndex: Int?
    @Published private(set) var dragOffset: CGFloat = 0
    @Published private(set) var dropIndex: Int?

    /// Key repeat calls `show` many times a second: only publish what actually changed.
    func set(tiles newTiles: [IndicatorTile], metrics newMetrics: IndicatorMetrics) {
        if !Self.same(tiles, newTiles) { tiles = newTiles }
        if metrics != newMetrics { metrics = newMetrics }
    }

    func beginDrag(at index: Int) {
        dragIndex = index
        dragOffset = 0
        dropIndex = index
    }

    /// Moves the dragged tile with the pointer, kept inside the row.
    func drag(by travel: CGFloat) {
        guard let from = dragIndex else { return }
        let offset = min(max(travel, -CGFloat(from) * metrics.pitch), CGFloat(metrics.count - 1 - from) * metrics.pitch)
        dragOffset = offset
        dropIndex = metrics.slot(atX: metrics.centerX(of: from) + offset)
    }

    func endDrag() {
        guard dragIndex != nil else { return }
        dragIndex = nil
        dragOffset = 0
        dropIndex = nil
    }

    private static func same(_ a: [IndicatorTile], _ b: [IndicatorTile]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { x, y in
            x.id == y.id && x.isFocused == y.isFocused && x.isVisible == y.isVisible
                && x.icons.count == y.icons.count && zip(x.icons, y.icons).allSatisfy { $0 === $1 }
        }
    }
}

// MARK: - Views

private struct IndicatorContent: View {
    @ObservedObject var model: IndicatorModel

    var body: some View {
        HStack(spacing: IndicatorMetrics.spacing) {
            ForEach(Array(model.tiles.enumerated()), id: \.element.id) { index, tile in
                let isDragged = model.dragIndex == index
                TileView(tile: tile, size: model.metrics.tile, isLifted: isDragged)
                    .offset(x: shift(of: index))
                    .zIndex(isDragged ? 1 : 0)
                    // The dragged tile follows the pointer directly; the others slide out of its way.
                    .transaction { transaction in
                        if isDragged { transaction.animation = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.dropIndex)
        .padding(IndicatorMetrics.padding)
        .frame(width: model.metrics.size.width, height: model.metrics.size.height, alignment: .topLeading)
    }

    /// Horizontal displacement of a tile: the dragged one follows the pointer, those between it and the drop
    /// slot move one place toward the gap it left.
    private func shift(of index: Int) -> CGFloat {
        guard let from = model.dragIndex else { return 0 }
        if index == from { return model.dragOffset }
        guard let to = model.dropIndex else { return 0 }
        let pitch = model.metrics.pitch
        if from < to, index > from, index <= to { return -pitch }
        if from > to, index >= to, index < from { return pitch }
        return 0
    }
}

private struct TileView: View {
    let tile: IndicatorTile
    let size: CGFloat
    let isLifted: Bool

    private var unit: CGFloat { size / IndicatorMetrics.baseTile }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10 * unit, style: .continuous)
        ZStack {
            shape.fill(Color.white.opacity(tile.isFocused ? 0.2 : 0.09))
            IconStack(icons: tile.icons, unit: unit)
        }
        // Columns on screen at full strength, the ones scrolled out dimmed.
        .opacity(tile.isVisible ? 1 : 0.45)
        .overlay {
            if tile.isFocused { shape.strokeBorder(Color.accentColor, lineWidth: 2) }
        }
        .frame(width: size, height: size)
        .scaleEffect(isLifted ? 1.08 : 1)
        .shadow(color: .black.opacity(isLifted ? 0.4 : 0), radius: 6, y: 2)
    }
}

/// The icons of a column: one large icon, or up to three small ones cascading like a stack of cards.
private struct IconStack: View {
    let icons: [NSImage]
    let unit: CGFloat

    var body: some View {
        let shown = Array(icons.prefix(3))
        if shown.isEmpty {
            Image(systemName: "macwindow")
                .font(.system(size: 22 * unit))
                .foregroundStyle(Color.white.opacity(0.7))
        } else if shown.count == 1 {
            icon(shown[0], size: 32 * unit)
        } else {
            // The first window's icon sits in front at the top left; the others peek out behind it.
            let box = 34 * unit
            let size = (shown.count == 2 ? 24 : 20) * unit
            let step = (box - size) / CGFloat(shown.count - 1)
            ZStack(alignment: .topLeading) {
                ForEach(shown.indices.reversed(), id: \.self) { index in
                    icon(shown[index], size: size)
                        .offset(x: CGFloat(index) * step, y: CGFloat(index) * step)
                }
            }
            .frame(width: box, height: box, alignment: .topLeading)
        }
    }

    private func icon(_ image: NSImage, size: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
