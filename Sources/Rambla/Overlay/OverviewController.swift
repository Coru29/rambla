import AppKit
import RamblaCore
import SwiftUI

/// One window as the overview shows it.
struct OverviewItem {
    let app: String
    let title: String
    let icon: NSImage?
    /// The app's color, from its icon: the miniature window's body.
    let tint: NSColor
    /// Minimized, its app hidden: shown faded, not chosen.
    let hidden: Bool
}

extension OverviewItem {
    static let neutralTint = NSColor(calibratedHue: 0.6, saturation: 0.14, brightness: 0.3, alpha: 1)

    /// An icon's color, weighted by saturation so its color counts more than its white or gray parts, then made dark
    /// and calm enough for white text. A gray icon (a terminal, say) gets a neutral slate.
    static func tint(of image: NSImage?) -> NSColor {
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return neutralTint }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return neutralTint }
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

/// Everything the overview draws: a row of cards per strip of the stack, the highest first (strip points), and how big
/// to draw them. Every row has the same scale, so a window is as big in each.
struct OverviewContent {
    var stack: OverviewStack
    var items: [WindowID: OverviewItem]
    /// The level in view: only its row shows the part of its strip that is on screen.
    var activeLevel: Int
    /// Overview points per strip point.
    var scale: CGFloat
    var cardHeight: CGFloat
    /// Width of the card of a strip without windows: a window half as wide as the display.
    var emptyWidth: CGFloat

    /// The narrowest card and the smallest gap between two: a long strip still shows each window's icon.
    static let minimumCardWidth = 44.0
    static let minimumGap = 10.0
    /// Room above and below the cards of a row: the bar of what is on screen goes there, and the chosen card grows into it.
    static let rowPadding: CGFloat = 28
    /// Between two rows.
    static let rowSpacing: CGFloat = 24
    /// Largest card height, as a share of the screen: an overview, not another copy of the screen.
    static let maximumHeight: CGFloat = 0.42
    /// The share of the screen's height all the rows fit in.
    static let rowsHeight: CGFloat = 0.85
    /// The smallest card height, for a stack of so many strips that its rows would not fit otherwise.
    static let minimumCardHeight: CGFloat = 48
    /// Smallest scale before a row scrolls sideways instead of shrinking further.
    static let minimumScale: CGFloat = 0.16
    /// How far up a card has to be dragged before the new strip above the rows takes it: more than a reorder of the top
    /// row drifts, even when the card was picked up by its title bar, right under the new strip.
    static let newStripTravel: CGFloat = 2 * rowPadding

    /// The overview of `stack` on a screen of `screen` points, whose windows have `visible` (without the menu bar and
    /// the Dock). Cards keep the windows' proportions, at one scale for every row: as tall as a share of the screen,
    /// less when the rows would not fit in theirs, and narrower when the widest row is long. Small cards and gaps are
    /// drawn wider than their share, so it shrinks a few times until that row fits.
    init(stack: OverviewStack, items: [WindowID: OverviewItem], activeLevel: Int, screen: CGSize, visible: CGSize) {
        self.stack = stack
        self.items = items
        self.activeLevel = activeLevel
        let rows = CGFloat(stack.rows.count)
        let room = (screen.height * Self.rowsHeight - rows * 2 * Self.rowPadding - (rows - 1) * Self.rowSpacing) / rows
        let height = min(screen.height * Self.maximumHeight, max(room, Self.minimumCardHeight))
        let windows = max(visible.height, 1)
        scale = height / windows
        cardHeight = 0
        emptyWidth = 0
        let width = screen.width - 160
        for _ in 0..<3 {
            let widest = drawn.map { CGFloat($0.width) }.max() ?? 0
            guard widest > width, scale > Self.minimumScale else { break }
            scale = max(scale * width / widest, Self.minimumScale)
        }
        cardHeight = windows * scale
        emptyWidth = max(CGFloat(Self.minimumCardWidth), visible.width / 2 * scale)
    }

    /// Each row's cards and viewport as they are drawn, parallel to the rows.
    var drawn: [Overview.Drawn] { stack.rows.indices.map(drawn) }

    func drawn(_ row: Int) -> Overview.Drawn {
        stack.rows[row].overview.drawn(scale: Double(scale), minimumWidth: Self.minimumCardWidth, minimumGap: Self.minimumGap)
    }

    /// The drawn gap between two cards of a row.
    func gap(_ row: Int) -> CGFloat {
        CGFloat(max(stack.rows[row].overview.gap * Double(scale), Self.minimumGap))
    }

    /// A row as tall as it is drawn: its cards and the room around them.
    var rowHeight: CGFloat { cardHeight + 2 * Self.rowPadding }
}

/// Where a card dragged out of its row is let go: at a place among the cards of another row (`Overview.insertionSlot`),
/// or on the new strip above the top row.
enum OverviewDrop: Equatable {
    case row(Int, slot: Int)
    case newStrip
}

@MainActor
final class OverviewState: ObservableObject {
    @Published var content: OverviewContent?
}

/// The overview ("Vista general"): every strip of one display at once, over a blurred screen, to see every window and
/// jump to one. Each strip of the display's stack is a row, the highest on top. A click on a window (or ↩ on the chosen
/// one, or its number) focuses it, bringing its strip into view, and closes the overview; esc, ⌘W, a click elsewhere,
/// the shortcut again, another app or another desktop close it as it was. Dragging a window to another place, or ⇧← →
/// on the chosen one, moves its column in its strip; dragging it to another row (or to a new strip above the top one),
/// or ⇧↑ ⇧↓, moves the column to that strip.
///
/// The panel takes the keyboard without activating Rambla, so whatever app was in front stays in front until a
/// window is chosen. It exists only while shown.
@MainActor
final class OverviewController {
    private let onChoose: (WindowID, StripKey) -> Void
    /// Moves a column of a strip to the place of another, both by id, and gives the overview of the stack as it is
    /// then, with that window chosen; nil when either column is gone.
    private let onMove: (_ column: UUID, _ toPlaceOf: UUID, _ key: StripKey, _ selecting: WindowID?) -> OverviewContent?
    /// Moves a column (by id) to the strip at `level` of the same stack, at `index` of its columns (after its focused
    /// one when nil), and gives the overview of the stack as it is then, with that window chosen; nil when it could not.
    private let onSend: (_ column: UUID, _ from: StripKey, _ level: Int, _ index: Int?, _ selecting: WindowID?)
        -> OverviewContent?
    /// The overview closed without a window chosen and with nothing else taking the keyboard (the user closed it, or
    /// the displays changed): the app in front has it again, which must not leave it in a window the overview sent out
    /// of view.
    private let onDismiss: () -> Void
    private let state = OverviewState()
    private var panel: OverviewPanel?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// The stack of strips shown.
    private(set) var shownStack: StackKey?

    init(onChoose: @escaping (WindowID, StripKey) -> Void,
         onMove: @escaping (_ column: UUID, _ toPlaceOf: UUID, _ key: StripKey, _ selecting: WindowID?) -> OverviewContent?,
         onSend: @escaping (_ column: UUID, _ from: StripKey, _ level: Int, _ index: Int?, _ selecting: WindowID?)
             -> OverviewContent?,
         onDismiss: @escaping () -> Void) {
        self.onChoose = onChoose
        self.onMove = onMove
        self.onSend = onSend
        self.onDismiss = onDismiss
    }

    var isShown: Bool { shownStack != nil }

    /// The overview is on screen, showing `stack`.
    func shows(_ stack: StackKey) -> Bool { shownStack == stack }

    func show(_ content: OverviewContent, stack: StackKey, on screen: NSScreen) {
        state.content = content
        let panel = makePanel()
        panel.setFrame(screen.frame, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        shownStack = stack
        observe(panel)
    }

    /// The user closes the overview without choosing (esc, ⌘W, a click beside the windows, the shortcut again, another
    /// of Rambla's shortcuts), or the displays change: it goes, and the keyboard comes back from it (`onDismiss`).
    func hide() {
        guard isShown else { return }
        close()
        onDismiss()
    }

    /// Takes the overview off screen: a window was chosen, or something else took the keyboard (another app, another
    /// desktop, another window, another strip in view).
    func close() {
        guard let panel, shownStack != nil else { return }
        shownStack = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.close()
            }
        })
    }

    /// The windows look otherwise now (the icon of a site a browser window shows came): the overview on screen draws them
    /// again.
    func updateItems(_ update: (inout [WindowID: OverviewItem]) -> Void) {
        guard isShown, var content = state.content else { return }
        update(&content.items)
        state.content = content
    }

    /// A window that is not on screen (minimized, its app hidden) cannot be chosen, nor can a strip without windows.
    private func choose(_ id: WindowID?) {
        guard let id, let stack = shownStack, let content = state.content, let item = content.items[id], !item.hidden,
              let row = content.stack.rows.first(where: { $0.overview.cards.contains { $0.windows.contains(id) } }) else {
            NSSound.beep()
            return
        }
        close()
        onChoose(id, stack.level(row.level))
    }

    private func move(_ move: Overview.Move) {
        guard isShown, var content = state.content else { return }
        content.stack.move(move, drawn: content.drawn)
        state.content = content
    }

    /// The selection goes straight to the row above (`up`) or below, whichever window of a stack is chosen. False at
    /// the top or the bottom row, where nothing happens.
    @discardableResult
    private func moveRow(up: Bool) -> Bool {
        guard isShown, var content = state.content else { return false }
        let moved = content.stack.moveRow(up: up, drawn: content.drawn)
        state.content = content
        return moved
    }

    /// A short vertical swipe on `stack` (`up`: toward the strip above): over its overview the selection goes to the
    /// row that way instead of the strip changing. Nil when the overview does not show that stack; otherwise whether
    /// there is a row that way, where the selection goes when `move`.
    func swipe(on stack: StackKey, up: Bool, move: Bool) -> Bool? {
        guard shows(stack), let content = state.content else { return nil }
        return move ? moveRow(up: up) : content.stack.row(toward: up) != nil
    }

    /// The window to keep chosen once the column of `card` in `row` moves: the chosen one when it is that card's, else
    /// the one its column shows.
    private func window(movingWith card: Int, in row: Int, of content: OverviewContent) -> WindowID? {
        let overview = content.stack.rows[row].overview
        if content.stack.selectedRow == row, overview.selection.card == card { return overview.window(at: overview.selection) }
        let moved = overview.cards[card]
        return moved.windows.indices.contains(moved.active) ? moved.windows[moved.active] : moved.windows.first
    }

    /// Moves the column of `card` in `row` to the place of the card at `slot` of the same row (a drop, or one place
    /// over with ⇧← →). The overview then shows the stack as it is, with that column's window chosen. False when it
    /// cannot go there.
    @discardableResult
    private func moveColumn(row: Int, card: Int, to slot: Int) -> Bool {
        guard let stack = shownStack, let content = state.content, content.stack.rows.indices.contains(row) else { return false }
        let overview = content.stack.rows[row].overview
        guard let move = overview.columnMove(card: card, to: slot),
              let moved = onMove(move.column, move.toPlaceOf, stack.level(content.stack.rows[row].level),
                                 window(movingWith: card, in: row, of: content)) else { return false }
        state.content = moved
        return true
    }

    private func moveChosenColumn(by step: Int) {
        guard let content = state.content, content.stack.rows.indices.contains(content.stack.selectedRow) else {
            NSSound.beep()
            return
        }
        let row = content.stack.selectedRow
        let card = content.stack.rows[row].overview.selection.card
        guard moveColumn(row: row, card: card, to: card + step) else {
            NSSound.beep()
            return
        }
    }

    /// Moves the column of `card` in `row` to the strip at `level`, at `index` of its columns (after its focused one
    /// when nil). The overview then shows the stack as it is, with that column's window still chosen. False when it
    /// could not.
    @discardableResult
    private func send(row: Int, card: Int, toLevel level: Int, at index: Int?) -> Bool {
        guard let stack = shownStack, let content = state.content, content.stack.rows.indices.contains(row),
              content.stack.rows[row].overview.cards.indices.contains(card) else { return false }
        let from = content.stack.rows[row]
        guard let sent = onSend(from.overview.cards[card].id, stack.level(from.level), level, index,
                                window(movingWith: card, in: row, of: content)) else { return false }
        state.content = sent
        return true
    }

    /// ⇧↑ ⇧↓: the chosen card's column goes to the strip above or below its own (above the top one, to a new strip),
    /// after the focused column there (`StripLevels.target`). A beep when there is no strip that way, or when the column
    /// is the only one of the top strip, which a new strip would only leave empty (`OverviewStack.offersNewStrip`).
    private func sendChosenColumn(up: Bool) {
        guard let content = state.content, content.stack.rows.indices.contains(content.stack.selectedRow) else {
            NSSound.beep()
            return
        }
        let rows = content.stack.rows
        let row = content.stack.selectedRow
        let top = rows.map(\.level).max() ?? 0
        let occupied = Set(rows.filter { !$0.overview.cards.isEmpty }.map(\.level))
        guard let level = StripLevels.target(from: rows[row].level, up: up, top: top, occupied: occupied),
              level <= top || content.stack.offersNewStrip(movingFrom: row),
              send(row: row, card: rows[row].overview.selection.card, toLevel: level, at: nil) else {
            NSSound.beep()
            return
        }
    }

    /// A card of `row` let go on another row, where it was dropped among its cards, or on the new strip above the top
    /// row.
    private func drop(row: Int, card: Int, on target: OverviewDrop) {
        guard let content = state.content else { return }
        let sent: Bool
        switch target {
        case .row(let other, let slot):
            guard content.stack.rows.indices.contains(other) else { return }
            let into = content.stack.rows[other]
            sent = send(row: row, card: card, toLevel: into.level, at: into.overview.columnIndex(insertingAt: slot))
        case .newStrip:
            sent = send(row: row, card: card, toLevel: (content.stack.rows.map(\.level).max() ?? 0) + 1, at: nil)
        }
        if !sent { NSSound.beep() }
    }

    /// The overview of the row the selection is in: numbers count its cards.
    private var selectedOverview: Overview? {
        guard let stack = state.content?.stack, stack.rows.indices.contains(stack.selectedRow) else { return nil }
        return stack.rows[stack.selectedRow].overview
    }

    // MARK: - Keyboard

    /// Returns true when the overview used the key.
    private func handle(_ event: NSEvent) -> Bool {
        guard let content = state.content else { return false }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case KeyCode.escape: hide()
        case KeyCode.left where shift: moveChosenColumn(by: -1)
        case KeyCode.right where shift: moveChosenColumn(by: 1)
        case KeyCode.up where shift: sendChosenColumn(up: true)
        case KeyCode.down where shift: sendChosenColumn(up: false)
        case KeyCode.left: move(.left)
        case KeyCode.right: move(.right)
        case KeyCode.down: move(.down)
        case KeyCode.up: move(.up)
        case KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.space: choose(content.stack.selectedWindow)
        default:
            guard let number = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(number) else { return false }
            choose(selectedOverview?.window(atCard: number))
        }
        return true
    }

    /// A Rambla shortcut while the overview is on screen. Its hot keys reach Rambla before the panel sees them, so the
    /// ones that move the focus move the selection instead (those that change strips, to the row above or below),
    /// ⌃⌘1…9 choose, ⌃⌘⇧← → move the chosen window's column, the ones that send a window to another strip send its
    /// column, and the overview's own closes it. Any other closes it and then acts on the strip as usual. Returns true
    /// when the overview used the shortcut.
    func perform(_ action: Action) -> Bool {
        guard isShown, state.content != nil else { return false }
        switch action {
        case .focusLeft: move(.left)
        case .focusRight: move(.right)
        case .focusUp: move(.up)
        case .focusDown: move(.down)
        case .focusFirst: move(.first)
        case .focusLast: move(.last)
        case .moveLeft: moveChosenColumn(by: -1)
        case .moveRight: moveChosenColumn(by: 1)
        case .stripUp, .stripDown: moveRow(up: action == .stripUp)
        case .sendStripUp, .sendStripDown: sendChosenColumn(up: action == .sendStripUp)
        case .focus1, .focus2, .focus3, .focus4, .focus5, .focus6, .focus7, .focus8, .focus9:
            choose(Int(action.rawValue.split(separator: "-").last!).flatMap { selectedOverview?.window(atCard: $0) })
        case .overview: hide()
        default:
            hide()
            return false
        }
        return true
    }

    // MARK: - Panel

    private func makePanel() -> OverviewPanel {
        let panel = OverviewPanel()
        panel.onKey = { [weak self] event in self?.handle(event) ?? false }
        panel.onClose = { [weak self] in self?.hide() }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        let hosting = OverviewHostingView(rootView: OverviewView(
            state: state,
            choose: { [weak self] id in self?.choose(id) },
            move: { [weak self] row, card, slot in self?.moveColumn(row: row, card: card, to: slot) },
            drop: { [weak self] row, card, target in self?.drop(row: row, card: card, on: target) },
            dismiss: { [weak self] in self?.hide() }))
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        panel.contentView = blur
        return panel
    }

    /// Another app in front, another desktop, a display change or a click on another screen: the strips behind are not
    /// the ones shown any more. The keyboard is where the first three put it; a display change puts it nowhere else, so
    /// the overview gives it back as when the user closes it.
    private func observe(_ panel: OverviewPanel) {
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default
        let close: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        let hide: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        observers = [
            (workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                              queue: .main, using: close)),
            (workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                              queue: .main, using: close)),
            (local, local.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                      queue: .main, using: hide)),
            (local, local.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main,
                                      using: close)),
        ]
    }
}

/// A full-screen overlay panel above the menu bar and the Dock that, unlike the others, takes the keyboard (still
/// without activating Rambla).
final class OverviewPanel: OverlayPanel {
    var onKey: ((NSEvent) -> Bool)?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    init() {
        super.init(level: .popUpMenu, collectionBehavior: [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle])
        appearance = NSAppearance(named: .darkAqua)
        acceptsMouseMovedEvents = true
    }

    /// Keys go to the overview before any view: SwiftUI's scroll view would take the arrows.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }

    /// ⌘-keys would otherwise reach Rambla's own menu, where ⌘Q quits it and ⌘H hides its overlays. ⌘W closes the
    /// overview; the rest do nothing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == KeyCode.w { onClose?() }
        return true
    }
}

/// The first click counts even if the panel was not key yet.
final class OverviewHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Views

/// Like Mission Control: the desktop blurred and darkened, each strip of the stack as a row of miniature windows, the
/// highest on top. A window dragged to another place lifts off its row, the others make room where it would land, and
/// once let go it glides there before its column moves. Dragged more than half a row up or down, it goes to the row
/// under the pointer, whose cards make room in turn; while a window is dragged, a "Tira nueva" row above the top one
/// takes it to a new strip (unless it is the only window of the top strip).
struct OverviewView: View {
    @ObservedObject var state: OverviewState
    let choose: (WindowID?) -> Void
    /// Moves the column of a card to the place of the card at a slot of its row.
    let move: (_ row: Int, _ card: Int, _ slot: Int) -> Void
    /// Moves the column of a card to another strip.
    let drop: (_ row: Int, _ card: Int, _ target: OverviewDrop) -> Void
    let dismiss: () -> Void
    @State private var hovered: WindowID?
    @State private var drag: CardDrag?
    /// Where the cards of each level's row begin across the rows (`Self.rows` space): a row is centered, and a long one
    /// scrolls.
    @State private var origins: [Int: CGFloat] = [:]
    /// Where the rows are on the screen: the room above them holds the new strip.
    @State private var rowsFrame = CGRect.zero

    /// A card being dragged.
    private struct CardDrag {
        var row: Int
        var card: Int
        /// How far the pointer moved since the drag began.
        var offset: CGSize
        /// Where the pointer began (`Self.rows` space).
        var start: CGPoint
        /// Let go on this place: the card glides there before the strips change.
        var landing: Place?
    }

    /// Where a dragged card would land: at a slot of a row (its own, or another one), or on the new strip.
    private enum Place: Equatable {
        case row(Int, slot: Int)
        case newStrip
    }

    private static let screen = "overview.screen"
    private static let rows = "overview.rows"
    /// What a row shows besides its cards (by index): the place a card dragged in from another row lands on, and the
    /// card of a strip without windows.
    private static let incoming = -1
    private static let empty = -2

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            if let content = state.content {
                VStack(spacing: 34) {
                    rows(content)
                    Group {
                        if content.stack.rows.count > 1 {
                            Text("← → ↑ ↓ elegí una ventana · arrastrala o ⇧ + flecha para moverla · ↩ la enfoca · esc cierra")
                        } else {
                            Text("← → elegí una ventana · arrastrala o ⇧← → para moverla · ↩ la enfoca · esc cierra")
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .coordinateSpace(.named(Self.screen))
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    /// The rows, the highest strip on top, each as wide as the screen. While a card is dragged, it is drawn over them,
    /// and so is the new strip, whose label goes over the card.
    private func rows(_ content: OverviewContent) -> some View {
        let place = drag.flatMap { landingPlace(of: $0, content) }
        let newStrip = drag.map { content.stack.offersNewStrip(movingFrom: $0.row) } ?? false
        let ids = content.stack.rows.map { $0.overview.cards.map(\.id) }
        return VStack(spacing: OverviewContent.rowSpacing) {
            ForEach(Array(content.stack.rows.enumerated()), id: \.element.level) { index, _ in
                row(index, content, place: place)
            }
        }
        .coordinateSpace(.named(Self.rows))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.screen)) } action: { rowsFrame = $0 }
        .overlay(alignment: .topLeading) {
            if newStrip { newStripBand(content, targeted: place == .newStrip) }
        }
        .overlay(alignment: .topLeading) {
            if let drag { lifted(drag, content, place: place) }
        }
        .overlay(alignment: .topLeading) {
            if newStrip { newStripLabel(content, targeted: place == .newStrip) }
        }
        // The stack changed under a drag (a shortcut moved a column meanwhile): the drag's card is not that one.
        .onChange(of: ids) { _, _ in drag = nil }
    }

    /// One strip: a row of cards, centered when it is shorter than the screen and scrolled sideways when it is longer.
    /// Only the strip in view shows the bar of what is on screen; one without windows shows a card that says so.
    private func row(_ index: Int, _ content: OverviewContent, place: Place?) -> some View {
        let overview = content.stack.rows[index].overview
        let level = content.stack.rows[index].level
        let drawn = content.drawn(index)
        let cells = cells(of: index, content, place: place)
        let selection = content.stack.selectedRow == index ? overview.selection : nil
        return GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: content.gap(index)) {
                        ForEach(cells, id: \.self) { cell in
                            self.cell(cell, of: index, content, drawn, place: place)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.86), value: cells)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.rows)).minX } action: {
                        origins[level] = $0
                    }
                    .overlay(alignment: .topLeading) {
                        if drag == nil, level == content.activeLevel { viewport(drawn) }
                    }
                    // Centered from its width as it is: a card that comes in or goes out while dragged makes the row
                    // longer or shorter on the right, and the cards under the pointer stay where they are.
                    .padding(.leading, max(70, (geometry.size.width - baseWidth(of: index, content)) / 2))
                    .padding(.trailing, 70)
                    .padding(.vertical, OverviewContent.rowPadding)
                    // A click beside the cards closes too.
                    .frame(minWidth: geometry.size.width, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)
                }
                .onAppear { scroll(proxy, to: overview.selection.card, of: overview) }
                .onChange(of: selection) { _, selection in
                    guard let selection else { return }
                    withAnimation(.easeOut(duration: 0.2)) { scroll(proxy, to: selection.card, of: overview) }
                }
            }
        }
        .frame(height: content.rowHeight)
    }

    private func scroll(_ proxy: ScrollViewProxy, to card: Int, of overview: Overview) {
        guard overview.cards.indices.contains(card) else { return }
        proxy.scrollTo(overview.cards[card].id, anchor: .center)
    }

    /// How wide a row is drawn when nothing is dragged: its cards, or the card of an empty strip.
    private func baseWidth(of row: Int, _ content: OverviewContent) -> CGFloat {
        content.stack.rows[row].overview.cards.isEmpty ? content.emptyWidth : CGFloat(content.drawn(row).width)
    }

    /// What a row shows, in order: its cards by index, the dragged one, while it is over its own row, where it would
    /// land (the others make room); `incoming` where a card from another row would land; `empty` for a strip without
    /// windows. Out of its own row a dragged card keeps its place there, empty until it is let go: its view holds the
    /// drag.
    private func cells(of row: Int, _ content: OverviewContent, place: Place?) -> [Int] {
        let cards = content.stack.rows[row].overview.cards
        let comesIn: Int? = {
            guard let drag, drag.row != row, case .row(row, let slot)? = place else { return nil }
            return slot
        }()
        if cards.isEmpty { return comesIn != nil ? [Self.incoming] : [Self.empty] }
        var order = Array(cards.indices)
        if let drag, drag.row == row, cards.indices.contains(drag.card) {
            if case .row(row, let slot)? = place {
                order.remove(at: drag.card)
                order.insert(drag.card, at: min(slot, order.count))
            }
        } else if let comesIn {
            order.insert(Self.incoming, at: min(comesIn, order.count))
        }
        return order
    }

    /// Drawn width of a cell of `row`.
    private func width(of cell: Int, in row: Int, _ content: OverviewContent) -> CGFloat {
        switch cell {
        case Self.empty: return content.emptyWidth
        case Self.incoming: return draggedWidth(content)
        default:
            let span = content.drawn(row).cards[cell]
            return CGFloat(span.upperBound - span.lowerBound)
        }
    }

    @ViewBuilder
    private func cell(_ cell: Int, of row: Int, _ content: OverviewContent, _ drawn: Overview.Drawn, place: Place?) -> some View {
        switch cell {
        case Self.empty: emptyCard(content)
        case Self.incoming: outline.frame(width: draggedWidth(content), height: content.cardHeight)
        default: card(cell, of: row, content, drawn, place: place)
        }
    }

    /// One card in its row. The one being dragged leaves a dashed outline where it will land, while that is in its row.
    private func card(_ index: Int, of row: Int, _ content: OverviewContent, _ drawn: Overview.Drawn,
                      place: Place?) -> some View {
        let card = content.stack.rows[row].overview.cards[index]
        let dragged = drag?.row == row && drag?.card == index
        let landsHere: Bool = {
            guard dragged, case .row(row, _)? = place else { return false }
            return true
        }()
        return OverviewCard(card: card, row: row, index: index, content: content, hovered: $hovered, choose: choose)
            .frame(width: CGFloat(drawn.cards[index].upperBound - drawn.cards[index].lowerBound), height: content.cardHeight)
            .opacity(dragged ? 0 : 1)
            .overlay {
                if landsHere { outline }
            }
            // A click still chooses: the drag only starts once the pointer has moved. A pinned column stays put in its
            // row, but can go to another strip.
            .highPriorityGesture(dragGesture(row, index, content))
            .id(card.id)
    }

    /// Where the dragged card lands: its outline, dashed.
    private var outline: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
    }

    /// The card of a strip without windows: there is nothing in it to choose.
    private func emptyCard(_ content: OverviewContent) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        return Text("Vacía")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: content.emptyWidth, height: content.cardHeight)
            .background(shape.fill(.white.opacity(0.05)))
            .overlay(shape.strokeBorder(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .contentShape(Rectangle())
            .onTapGesture { choose(nil) }
    }

    private func dragGesture(_ row: Int, _ index: Int, _ content: OverviewContent) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.rows))
            .onChanged { value in
                guard drag?.landing == nil else { return }
                drag = CardDrag(row: row, card: index, offset: value.translation, start: value.startLocation)
            }
            .onEnded { _ in land(content) }
    }

    // MARK: - Dragging

    /// Top of a row's cards (`Self.rows` space).
    private func cardsTop(of row: Int, _ content: OverviewContent) -> CGFloat {
        CGFloat(row) * (content.rowHeight + OverviewContent.rowSpacing) + OverviewContent.rowPadding
    }

    /// Where a row's cards begin (`Self.rows` space), as the row was last laid out.
    private func origin(of row: Int, _ content: OverviewContent) -> CGFloat {
        origins[content.stack.rows[row].level] ?? 70
    }

    private func draggedWidth(_ content: OverviewContent) -> CGFloat {
        guard let drag, content.stack.rows.indices.contains(drag.row),
              content.stack.rows[drag.row].overview.cards.indices.contains(drag.card) else { return 0 }
        let span = content.drawn(drag.row).cards[drag.card]
        return CGFloat(span.upperBound - span.lowerBound)
    }

    /// Where the new strip is drawn (`Self.rows` space): in the room above the rows, at most as tall as a card, and as
    /// wide as the widest row.
    private func newStripFrame(_ content: OverviewContent) -> CGRect {
        let height = max(36, min(content.cardHeight, rowsFrame.minY - 8))
        let widest = content.drawn.map { CGFloat($0.width) }.max() ?? 0
        let width = min(max(widest, content.emptyWidth, 320), max(rowsFrame.width - 140, 320))
        return CGRect(x: (rowsFrame.width - width) / 2, y: -height, width: width, height: height)
    }

    /// Where `drag` would land now. In its own row it lands where the others make room for it, as it always did;
    /// dragged more than half a row's height up or down, in the row under the pointer, where its center falls; with the
    /// pointer in the band of the new strip (or above it, at the edge of the screen), on the new strip, when there is
    /// one and the card went up far enough (`OverviewContent.newStripTravel`). Nil when its card is gone.
    private func landingPlace(of drag: CardDrag, _ content: OverviewContent) -> Place? {
        if let landing = drag.landing { return landing }
        let rows = content.stack.rows
        guard rows.indices.contains(drag.row), rows[drag.row].overview.cards.indices.contains(drag.card) else { return nil }
        let pointer = drag.start.y + drag.offset.height
        if content.stack.offersNewStrip(movingFrom: drag.row), -drag.offset.height >= OverviewContent.newStripTravel {
            let band = newStripFrame(content)
            let x = drag.start.x + drag.offset.width
            if pointer < band.maxY, x >= band.minX, x <= band.maxX { return .newStrip }
        }
        var row = drag.row
        if abs(drag.offset.height) > content.rowHeight / 2 {
            // Rows meet halfway through the space between them.
            let pitch = content.rowHeight + OverviewContent.rowSpacing
            row = min(max(Int(((pointer + OverviewContent.rowSpacing / 2) / pitch).rounded(.down)), 0), rows.count - 1)
        }
        let own = content.drawn(drag.row)
        let span = own.cards[drag.card]
        let center = (span.lowerBound + span.upperBound) / 2 + Double(drag.offset.width)
        if row == drag.row {
            return .row(row, slot: rows[row].overview.dropSlot(forCard: drag.card, center: center, in: own))
        }
        // From its own row's coordinates to the other's.
        let there = center + Double(origin(of: drag.row, content) - origin(of: row, content))
        return .row(row, slot: rows[row].overview.insertionSlot(center: there, in: content.drawn(row)))
    }

    /// Let go: the card glides to the place it lands on, and only then its column moves, so the rows it comes back to
    /// are already in that order.
    private func land(_ content: OverviewContent) {
        guard var landing = drag, landing.landing == nil else { return }
        guard let place = landingPlace(of: landing, content) else {
            drag = nil
            return
        }
        switch place {
        case .row(let row, let slot):
            let start = CGPoint(x: origin(of: landing.row, content)
                                    + CGFloat(content.drawn(landing.row).cards[landing.card].lowerBound),
                                y: cardsTop(of: landing.row, content))
            let before = cells(of: row, content, place: place).prefix(slot)
            let x = before.reduce(CGFloat(0)) { $0 + width(of: $1, in: row, content) + content.gap(row) }
            let end = CGPoint(x: origin(of: row, content) + x, y: cardsTop(of: row, content))
            landing.offset = CGSize(width: end.x - start.x, height: end.y - start.y)
        case .newStrip:
            // To the middle of the band, where the card stays while it is over it (`liftedCard`).
            landing.offset.width = newStripFrame(content).midX - landing.start.x
        }
        landing.landing = place
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9), completionCriteria: .logicallyComplete) {
            drag = landing
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                drag = nil
                switch place {
                case .row(let row, let slot) where row == landing.row:
                    if slot != landing.card { move(row, landing.card, slot) }
                case .row(let row, let slot):
                    drop(landing.row, landing.card, .row(row, slot: slot))
                case .newStrip:
                    drop(landing.row, landing.card, .newStrip)
                }
            }
        }
    }

    /// The dragged card, lifted, under the pointer. In its own row it never passes the pinned columns; out of it, it
    /// goes where the pointer goes, and shrinks over the new strip.
    @ViewBuilder
    private func lifted(_ drag: CardDrag, _ content: OverviewContent, place: Place?) -> some View {
        if content.stack.rows.indices.contains(drag.row), content.stack.rows[drag.row].overview.cards.indices.contains(drag.card) {
            liftedCard(drag, content, place: place)
        }
    }

    private func liftedCard(_ drag: CardDrag, _ content: OverviewContent, place: Place?) -> some View {
        let overview = content.stack.rows[drag.row].overview
        let drawn = content.drawn(drag.row)
        let span = drawn.cards[drag.card]
        let width = span.upperBound - span.lowerBound
        var x = span.lowerBound + Double(drag.offset.width)
        let inOwnRow: Bool = {
            guard case .row(drag.row, _)? = place else { return false }
            return true
        }()
        if inOwnRow, overview.cards[drag.card].pinned == nil, let movable = overview.movable {
            x = min(max(x, drawn.cards[movable.lowerBound].lowerBound), drawn.cards[movable.upperBound].upperBound - width)
        }
        let up = drag.landing == nil
        // Over the new strip it shrinks to fit the band, which may be thin, and sits in it under the pointer.
        let band = newStripFrame(content)
        let overNewStrip = place == .newStrip
        let small = min(0.5, max(band.height - 8, 4) / max(content.cardHeight, 1))
        let left = overNewStrip ? drag.start.x + drag.offset.width - CGFloat(width) / 2
                                : origin(of: drag.row, content) + CGFloat(x)
        let top = overNewStrip ? band.midY - content.cardHeight / 2
                               : cardsTop(of: drag.row, content) + drag.offset.height
        return OverviewCard(card: overview.cards[drag.card], row: drag.row, index: drag.card, content: content,
                            hovered: .constant(nil), choose: { _ in }, opaque: true)
            .frame(width: CGFloat(width), height: content.cardHeight)
            .scaleEffect(overNewStrip ? small : (up ? 1.04 : 1))
            .shadow(color: .black.opacity(up ? 0.6 : 0.4), radius: overNewStrip ? 6 : (up ? 28 : 14),
                    y: overNewStrip ? 3 : (up ? 18 : 8))
            .offset(x: left, y: top)
            // Into the band and out of it, it glides; elsewhere it stays under the pointer.
            .animation(.spring(response: 0.25, dampingFraction: 0.86), value: overNewStrip)
            .allowsHitTesting(false)
    }

    /// While a card is dragged, a row above the top one that takes it to a new strip, as tall as the room there allows
    /// (`newStripFrame`). It lights up while the card is over it. Its label is drawn apart, over the card.
    private func newStripBand(_ content: OverviewContent, targeted: Bool) -> some View {
        let band = newStripFrame(content)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return shape.fill(.white.opacity(targeted ? 0.14 : 0.05))
            .overlay(shape.strokeBorder(targeted ? Color.accentColor : .white.opacity(0.3),
                                        style: StrokeStyle(lineWidth: targeted ? 2.5 : 1.5, dash: targeted ? [] : [6, 5])))
            .frame(width: band.width, height: band.height)
            .animation(.easeOut(duration: 0.15), value: targeted)
            .offset(x: band.minX, y: band.minY)
            .allowsHitTesting(false)
    }

    /// The new strip's name, over the dragged card, which never hides it.
    private func newStripLabel(_ content: OverviewContent, targeted: Bool) -> some View {
        let band = newStripFrame(content)
        return HStack(spacing: 7) {
            Image(systemName: "plus")
            Text("Tira nueva")
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white.opacity(targeted ? 0.95 : 0.6))
        .shadow(color: .black.opacity(0.5), radius: 2)
        .frame(width: band.width, height: band.height)
        .animation(.easeOut(duration: 0.15), value: targeted)
        .offset(x: band.minX, y: band.minY)
        .allowsHitTesting(false)
    }

    /// The part of the strip that is on screen now: a bar above the windows, like a scroll bar's thumb.
    @ViewBuilder
    private func viewport(_ drawn: Overview.Drawn) -> some View {
        if let range = drawn.viewport {
            Capsule()
                .fill(.white.opacity(0.45))
                .frame(width: max(CGFloat(range.upperBound - range.lowerBound), 8), height: 3)
                .offset(x: CGFloat(range.lowerBound), y: -16)
                .allowsHitTesting(false)
        }
    }
}

/// One column: its window, its stack (one miniature per window) or its tabs (one miniature, the tabs in its title bar).
private struct OverviewCard: View {
    let card: Overview.Card
    /// The row of its strip, and its place in it.
    let row: Int
    let index: Int
    let content: OverviewContent
    @Binding var hovered: WindowID?
    let choose: (WindowID?) -> Void
    /// Nothing shows through it: the dragged card goes over the others, which its translucent parts would let through.
    var opaque = false

    /// The chosen window's place in the column, when it is this card's.
    private var chosenRow: Int? {
        let stack = content.stack
        guard stack.selectedRow == row, stack.rows.indices.contains(row) else { return nil }
        let selection = stack.rows[row].overview.selection
        return selection.card == index ? selection.row : nil
    }

    var body: some View {
        if card.collapsed {
            collapsed
        } else if card.tabbed, card.windows.count > 1 {
            let shown = chosenRow ?? card.active
            miniature(card.windows[shown], selected: chosenRow != nil, tabs: card.windows, shownTab: shown)
        } else {
            VStack(spacing: 10) {
                ForEach(Array(card.windows.enumerated()), id: \.offset) { row, id in
                    miniature(id, selected: chosenRow == row, tabs: [], shownTab: 0)
                }
            }
        }
    }

    /// Every window of the column is minimized or hidden: just its icons, faded.
    private var collapsed: some View {
        VStack(spacing: 6) {
            ForEach(Array(card.windows.prefix(3).enumerated()), id: \.offset) { _, id in
                AppIcon(image: content.items[id]?.icon, size: 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
        .opacity(0.6)
        .contentShape(Rectangle())
        .onTapGesture { choose(card.windows.first) }
    }

    private func miniature(_ id: WindowID, selected: Bool, tabs: [WindowID], shownTab: Int) -> some View {
        let item = content.items[id]
        let tint = Color(nsColor: item?.tint ?? .darkGray)
        let isHovered = hovered == id
        return GeometryReader { geometry in
            let size = geometry.size
            let compact = size.height < 120
            VStack(spacing: 0) {
                titleBar(item, tabs: tabs, shownTab: shownTab, pinned: card.pinned != nil)
                ZStack {
                    LinearGradient(colors: [tint, tint.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: compact ? 4 : 10) {
                        AppIcon(image: item?.icon, size: compact ? 30 : min(72, size.width * 0.32, size.height * 0.34))
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                        if !compact || size.height > 80 {
                            Text(item?.app ?? "")
                                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .background {
                if opaque { Color(white: 0.14) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(isHovered && !selected ? 0.55 : 0.14), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 13).inset(by: -3).strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0))
            .shadow(color: .black.opacity(selected ? 0.55 : 0.4), radius: selected ? 24 : 14, y: selected ? 14 : 8)
            .scaleEffect(selected ? 1.03 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selected)
        }
        .opacity(item?.hidden == true ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? id : (hovered == id ? nil : hovered) }
        .onTapGesture { choose(id) }
    }

    /// The miniature's title bar: the three window buttons and the title, or the tabs.
    private func titleBar(_ item: OverviewItem?, tabs: [WindowID], shownTab: Int, pinned: Bool) -> some View {
        HStack(spacing: 7) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
            }
            .frame(width: 34, height: 8)
            if tabs.isEmpty {
                Text(item?.title.isEmpty == false ? item!.title : item?.app ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            } else {
                HStack(spacing: 3) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                        AppIcon(image: content.items[tab]?.icon, size: 14)
                            .frame(maxWidth: .infinity)
                            .frame(height: 18)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(index == shownTab ? 0.28 : 0.08)))
                            .onTapGesture { choose(tab) }
                    }
                }
            }
            Spacer(minLength: 0)
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color.black.opacity(0.32))
    }
}

private struct AppIcon: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "macwindow").resizable().scaledToFit().foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
    }
}
