import Foundation

/// The overview ("Vista general"): one strip laid out as a single row of cards, to see every window at once and jump
/// to one. Positions are strip points (the view scales them to fit its screen): the left-pinned column first, then the
/// strip's columns in order, then the right-pinned one, `gap` apart. It also keeps the selection the keyboard moves.
/// The overview of a display shows one per strip of its stack (`OverviewStack`).
public struct Overview: Equatable, Sendable {
    public struct Card: Equatable, Identifiable, Sendable {
        /// The column's id: the card stays the same card when the columns move.
        public var id: UUID
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

    public enum Move: Sendable { case left, right, up, down, first, last }

    /// Where the cards and the viewport are drawn.
    public struct Drawn: Equatable, Sendable {
        /// Each card's left and right edges.
        public var cards: [ClosedRange<Double>]
        public var viewport: ClosedRange<Double>?
        /// Right edge of the last card.
        public var width: Double
    }

    /// Width of the card of a collapsed column, which takes no room on screen.
    public static let collapsedWidth = 120.0

    public private(set) var cards: [Card] = []
    /// Right edge of the last card.
    public private(set) var total = 0.0
    /// The part of the strip on screen now, in card coordinates (pinned columns are always on screen and not in it);
    /// nil when no scrolling column is.
    public private(set) var viewport: ClosedRange<Double>?
    public private(set) var selection = Selection(card: 0, row: 0)
    /// Strip points between two cards.
    public let gap: Double
    /// Windows that are minimized or whose app is hidden: never chosen.
    private let hidden: Set<WindowID>

    /// `metrics` is the strip's layout and `pinnedWidths` the on-screen width of its pinned columns (which the scroll
    /// area does not hold). The selection starts on `focused`, or on the focused column's active window.
    public init(strip: Strip, metrics: StripMetrics, pinnedWidths: [UUID: Double], gap: Double, hidden: Set<WindowID>,
                focused: WindowID?) {
        self.gap = gap
        self.hidden = hidden
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
            cards.append(Card(id: column.id, column: index, x: x, width: width, windows: column.windows,
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
            selection = Selection(card: card, row: entryRow(card))
        } else if let card = cards.firstIndex(where: { !$0.collapsed }) {
            selection = Selection(card: card, row: entryRow(card))
        }
    }

    /// The cards and the viewport at `scale` (drawn points per strip point), with every card at least `minimumWidth`
    /// wide and at least `minimumGap` from the next. Small cards take more room than their share, so the viewport is
    /// mapped card by card: the bar starts and ends on the cards it covers.
    public func drawn(scale: Double, minimumWidth: Double, minimumGap: Double) -> Drawn {
        let drawnGap = max(gap * scale, minimumGap)
        var spans: [ClosedRange<Double>] = []
        var x = 0.0
        for card in cards {
            let width = max(card.width * scale, minimumWidth)
            spans.append(x...(x + width))
            x += width + drawnGap
        }
        func place(_ point: Double) -> Double {
            for (index, card) in cards.enumerated() {
                let span = spans[index], right = card.x + card.width
                if point <= right {
                    let share = card.width > 0 ? (max(point, card.x) - card.x) / card.width : 0
                    return span.lowerBound + share * (span.upperBound - span.lowerBound)
                }
                let next = cards.indices.contains(index + 1) ? cards[index + 1].x : right
                if point < next { return span.upperBound + (point - right) / (next - right) * drawnGap }
            }
            return spans.last?.upperBound ?? 0
        }
        return Drawn(cards: spans, viewport: viewport.map { place($0.lowerBound)...place($0.upperBound) },
                     width: max(0, x - drawnGap))
    }

    public func window(at selection: Selection) -> WindowID? {
        guard cards.indices.contains(selection.card) else { return nil }
        let windows = cards[selection.card].windows
        return windows.indices.contains(selection.row) ? windows[selection.row] : nil
    }

    /// The cards whose columns can move: those between the pinned ones (nil when every column is pinned).
    public var movable: ClosedRange<Int>? {
        let open = cards.indices.filter { cards[$0].pinned == nil }
        guard let first = open.first, let last = open.last else { return nil }
        return first...last
    }

    /// Where a card dragged with its center at `center` (drawn points) lands: after every other movable card whose
    /// center is left of it. A pinned card stays where it is.
    public func dropSlot(forCard card: Int, center: Double, in drawn: Drawn) -> Int {
        guard let movable, movable.contains(card) else { return card }
        let before = movable.filter { $0 != card && (drawn.cards[$0].lowerBound + drawn.cards[$0].upperBound) / 2 < center }
        return movable.lowerBound + before.count
    }

    /// Moving the column of `card` to the place of the card at `slot`: the column that moves and the one whose place
    /// it takes, by id, since the strip may have changed since the overview was made. Nil for a pinned column, a place
    /// outside the unpinned ones, or the card's own place.
    public func columnMove(card: Int, to slot: Int) -> (column: UUID, toPlaceOf: UUID)? {
        guard let movable, movable.contains(card), movable.contains(slot), slot != card else { return nil }
        return (cards[card].id, cards[slot].id)
    }

    /// Where a card of another row (another strip), dragged with its center at `center` (drawn points), lands in this
    /// one: like `dropSlot`, after every movable card whose center is left of it, so always between the pinned ones.
    /// The place is a card index: the cards from there on make room.
    public func insertionSlot(center: Double, in drawn: Drawn) -> Int {
        guard let movable else { return cards.filter { $0.pinned == .left }.count }
        return movable.lowerBound + movable.filter { (drawn.cards[$0].lowerBound + drawn.cards[$0].upperBound) / 2 < center }.count
    }

    /// The index in the strip's columns at which a column that comes from another strip, unpinned, is drawn at card
    /// place `slot` (`insertionSlot`): before the column of the movable card there, or after the last movable one.
    /// Pinned columns can sit anywhere in the strip's array, so the card index alone would not do.
    public func columnIndex(insertingAt slot: Int) -> Int {
        // Without unpinned columns, any index draws it between the pinned ones.
        guard let movable else { return 0 }
        return slot <= movable.upperBound ? cards[max(slot, movable.lowerBound)].column : cards[movable.upperBound].column + 1
    }

    /// The window of the `number`th card from 1, the one its column shows. Like ⌃⌘1…9, it counts only the columns
    /// with a window on screen.
    public func window(atCard number: Int) -> WindowID? {
        let open = cards.indices.filter { !cards[$0].collapsed }
        guard open.indices.contains(number - 1) else { return nil }
        let card = open[number - 1]
        return window(at: Selection(card: card, row: entryRow(card)))
    }

    /// Moves the selection to the next card that has a window on screen, or to the next window of the card that is on
    /// screen; it stops at the ends. A new card is entered on the window its column shows.
    public mutating func move(_ move: Move) {
        switch move {
        case .left, .right:
            let step = move == .left ? -1 : 1
            var card = selection.card + step
            while cards.indices.contains(card), cards[card].collapsed { card += step }
            guard cards.indices.contains(card) else { return }
            selection = Selection(card: card, row: entryRow(card))
        case .first, .last:
            let open = cards.indices.filter { !cards[$0].collapsed }
            guard let card = move == .first ? open.first : open.last else { return }
            selection = Selection(card: card, row: entryRow(card))
        case .up, .down:
            guard cards.indices.contains(selection.card) else { return }
            let windows = cards[selection.card].windows
            let step = move == .up ? -1 : 1
            var row = selection.row + step
            while windows.indices.contains(row), hidden.contains(windows[row]) { row += step }
            guard windows.indices.contains(row) else { return }
            selection.row = row
        }
    }

    /// The row a card is entered on: the window its column shows, or its first window on screen when that one is not.
    private func entryRow(_ card: Int) -> Int {
        let windows = cards[card].windows
        guard windows.indices.contains(cards[card].active), hidden.contains(windows[cards[card].active]) else {
            return cards[card].active
        }
        return windows.firstIndex { !hidden.contains($0) } ?? cards[card].active
    }

    /// The row a card is entered on from the row of cards below it (`fromBelow`) or above it (`OverviewStack`): of a
    /// stack, its window on screen nearest that side; of tabs, which share one miniature, the one it shows (`entryRow`).
    func entryRow(_ card: Int, fromBelow: Bool) -> Int {
        let windows = cards[card].windows
        guard !cards[card].tabbed else { return entryRow(card) }
        let open = windows.indices.filter { !hidden.contains(windows[$0]) }
        return (fromBelow ? open.last : open.first) ?? entryRow(card)
    }

    public mutating func select(_ selection: Selection) {
        guard window(at: selection) != nil else { return }
        self.selection = selection
    }
}
