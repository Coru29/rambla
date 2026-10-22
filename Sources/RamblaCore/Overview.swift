import Foundation

/// The overview ("Vista general"): one strip laid out as a single row of cards, to see every window at once and jump
/// to one. Positions are strip points (the view scales them to fit its screen): the left-pinned column first, then the
/// strip's columns in order, then the right-pinned one, `gap` apart. It also keeps the selection the keyboard moves.
public struct Overview: Equatable, Sendable {
    public struct Card: Equatable, Sendable {
        /// Index of the column in the strip.
        public var column: Int
        public var x: Double
        public var width: Double
        public var windows: [WindowID]
        /// The window the column shows (the active tab, or the stack's active row).
        public var active: Int
        public var tabbed: Bool
        public var pinned: PinSide?
        /// Every window of the column is hidden (minimized, app hidden): a small card the arrows skip.
        public var collapsed: Bool
    }

    public struct Selection: Equatable, Sendable {
        public var card: Int
        public var row: Int

        public init(card: Int, row: Int) {
            self.card = card
            self.row = row
        }
    }

    public enum Move: Sendable { case left, right, up, down }

    /// Width of the card of a collapsed column, which takes no room on screen.
    public static let collapsedWidth = 120.0

    public private(set) var cards: [Card] = []
    /// Right edge of the last card.
    public private(set) var total = 0.0
    /// The part of the strip on screen now, in card coordinates (pinned columns are always on screen and not in it);
    /// nil when no scrolling column is.
    public private(set) var viewport: ClosedRange<Double>?
    public private(set) var selection = Selection(card: 0, row: 0)

    /// `metrics` is the strip's layout and `pinnedWidths` the on-screen width of its pinned columns (which the scroll
    /// area does not hold). The selection starts on `focused`, or on the focused column's active window.
    public init(strip: Strip, metrics: StripMetrics, pinnedWidths: [UUID: Double], gap: Double, hidden: Set<WindowID>,
                focused: WindowID?) {
        let order = strip.columns.indices.filter { strip.columns[$0].pinned == .left }
            + strip.columns.indices.filter { strip.columns[$0].pinned == nil }
            + strip.columns.indices.filter { strip.columns[$0].pinned == .right }
        var x = 0.0
        var start: Double?
        var end: Double?
        let shown = strip.scroll...(strip.scroll + metrics.area.width)
        for index in order {
            let column = strip.columns[index]
            let collapsed = strip.isCollapsed(index, hidden: hidden)
            let width: Double
            if let pinned = column.pinned.flatMap({ _ in pinnedWidths[column.id] }) {
                width = pinned
            } else if collapsed || !metrics.isLaidOut(index) {
                width = Self.collapsedWidth
            } else {
                width = metrics.widths[index]
                // Where the screen shows this column, mapped onto its card.
                let left = metrics.xs[index], right = left + width
                if right > shown.lowerBound, left < shown.upperBound {
                    let from = x + max(left, shown.lowerBound) - left
                    let to = x + min(right, shown.upperBound) - left
                    start = min(start ?? from, from)
                    end = max(end ?? to, to)
                }
            }
            cards.append(Card(column: index, x: x, width: width, windows: column.windows,
                              active: min(max(column.active, 0), max(column.windows.count - 1, 0)),
                              tabbed: column.mode == .tabbed, pinned: column.pinned, collapsed: collapsed))
            x += width + gap
        }
        total = max(0, x - gap)
        if let start, let end { viewport = start...end }
        if let focused, let card = cards.firstIndex(where: { $0.windows.contains(focused) }),
           let row = cards[card].windows.firstIndex(of: focused) {
            selection = Selection(card: card, row: row)
        } else if let column = strip.focused, let card = cards.firstIndex(where: { $0.column == column }) {
            selection = Selection(card: card, row: cards[card].active)
        } else if let card = cards.firstIndex(where: { !$0.collapsed }) {
            selection = Selection(card: card, row: cards[card].active)
        }
    }

    public func window(at selection: Selection) -> WindowID? {
        guard cards.indices.contains(selection.card) else { return nil }
        let windows = cards[selection.card].windows
        return windows.indices.contains(selection.row) ? windows[selection.row] : nil
    }

    /// The window of the `number`th card (from 1, as ⌃⌘1…9 count columns), the one the column shows.
    public func window(atCard number: Int) -> WindowID? {
        guard cards.indices.contains(number - 1) else { return nil }
        return window(at: Selection(card: number - 1, row: cards[number - 1].active))
    }

    /// Moves the selection to the next card that has a window on screen, or to the next window of the card; it stops
    /// at the ends. A new card is entered on the window its column shows.
    public mutating func move(_ move: Move) {
        switch move {
        case .left, .right:
            let step = move == .left ? -1 : 1
            var card = selection.card + step
            while cards.indices.contains(card), cards[card].collapsed { card += step }
            guard cards.indices.contains(card) else { return }
            selection = Selection(card: card, row: cards[card].active)
        case .up, .down:
            guard cards.indices.contains(selection.card) else { return }
            let row = selection.row + (move == .up ? -1 : 1)
            guard cards[selection.card].windows.indices.contains(row) else { return }
            selection.row = row
        }
    }

    public mutating func select(_ selection: Selection) {
        guard window(at: selection) != nil else { return }
        self.selection = selection
    }
}
