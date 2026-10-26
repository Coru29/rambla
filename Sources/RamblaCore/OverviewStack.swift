import Foundation

/// The overview of a stack of strips (those of one display and Space): one row per level, the highest first, each the
/// `Overview` of its strip, and the selection the keyboard moves among them. Every row keeps a selection of its own;
/// the one of `selectedRow` is the overview's.
///
/// Rows are compared by where their cards are drawn on the screen: the view centers each row, so a card's place
/// across the screen is its drawn center measured from the middle of its row.
public struct OverviewStack: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var level: Int
        public var overview: Overview

        public init(level: Int, overview: Overview) {
            self.level = level
            self.overview = overview
        }
    }

    /// Highest level first.
    public private(set) var rows: [Row]
    public private(set) var selectedRow: Int

    /// The selection starts in the row of `activeLevel`, on that overview's own selection; when that row has no cards,
    /// in the nearest row that has. A row has cards to choose when one of them has a window on screen; with one as near
    /// on each side, the row below, the way back from an empty strip (`StripLevels.nearestOccupied`). That row's own
    /// selection may be a card with no window on screen (its strip focuses a column of a hidden app): then its first
    /// card that can be chosen.
    public init(rows: [Row], activeLevel: Int) {
        self.rows = rows
        let active = rows.firstIndex { $0.level == activeLevel } ?? 0
        guard rows.indices.contains(active), !Self.hasCards(rows[active]) else {
            selectedRow = active
            return
        }
        let candidates = rows.indices.filter { Self.hasCards(rows[$0]) }
        // Rows go from the highest level down, so on a tie the larger index is the row below.
        selectedRow = candidates.min { (abs($0 - active), -$0) < (abs($1 - active), -$1) } ?? active
        guard selectedRow != active else { return }
        let overview = self.rows[selectedRow].overview
        if !overview.cards.indices.contains(overview.selection.card) || overview.cards[overview.selection.card].collapsed {
            self.rows[selectedRow].overview.move(.first)
        }
    }

    public var selectedWindow: WindowID? {
        guard rows.indices.contains(selectedRow) else { return nil }
        let overview = rows[selectedRow].overview
        return overview.window(at: overview.selection)
    }

    /// Left, right, first and last stay in the row. Up and down move inside the chosen card's stack and, past its top
    /// or bottom window, to the row above or below (skipping rows without cards), on the card whose drawn center is
    /// nearest; `drawn` holds each row's drawn cards, parallel to `rows`.
    public mutating func move(_ move: Overview.Move, drawn: [Overview.Drawn]) {
        guard rows.indices.contains(selectedRow) else { return }
        switch move {
        case .left, .right, .first, .last:
            rows[selectedRow].overview.move(move)
        case .up, .down:
            let before = rows[selectedRow].overview.selection
            rows[selectedRow].overview.move(move)
            guard rows[selectedRow].overview.selection == before else { return }
            moveRow(up: move == .up, drawn: drawn)
        }
    }

    /// The nearest row above (`up`) or below the selected one that has cards to choose; nil at the top or the bottom.
    public func row(toward up: Bool) -> Int? {
        let others = up ? Array((0..<max(selectedRow, 0)).reversed()) : Array((selectedRow + 1)..<max(rows.count, selectedRow + 1))
        return others.first { Self.hasCards(rows[$0]) }
    }

    /// Moves the selection straight to the row above (`up`) or below (`row(toward:)`), whatever window of its card's
    /// stack is chosen, onto the card whose drawn center is nearest the chosen one's. A stack is entered on its window
    /// nearest the row the selection comes from. False, and nothing moves, at the top or the bottom.
    @discardableResult
    public mutating func moveRow(up: Bool, drawn: [Overview.Drawn]) -> Bool {
        guard let target = row(toward: up) else { return false }
        let overview = rows[target].overview
        let open = overview.cards.indices.filter { !overview.cards[$0].collapsed }
        let current = rows.indices.contains(selectedRow)
            ? Self.place(of: rows[selectedRow].overview.selection.card, in: drawn, row: selectedRow) : nil
        var card = open.contains(overview.selection.card) ? overview.selection.card : open[0]
        if let current {
            card = open.min {
                abs((Self.place(of: $0, in: drawn, row: target) ?? 0) - current)
                    < abs((Self.place(of: $1, in: drawn, row: target) ?? 0) - current)
            } ?? card
        }
        selectedRow = target
        rows[target].overview.select(Overview.Selection(card: card, row: overview.entryRow(card, fromBelow: up)))
        return true
    }

    /// Whether a column of `row` can go to a new strip above the top one: the top row has windows (an empty top strip is
    /// already there to take it), and the column is not the only one of the top row, which would only leave an empty
    /// strip below the new one.
    public func offersNewStrip(movingFrom row: Int) -> Bool {
        guard let top = rows.first, !top.overview.cards.isEmpty else { return false }
        return row != 0 || top.overview.cards.count > 1
    }

    /// Chooses a window of any row; nothing changes when there is none at `selection`.
    public mutating func select(row: Int, _ selection: Overview.Selection) {
        guard rows.indices.contains(row), rows[row].overview.window(at: selection) != nil else { return }
        selectedRow = row
        rows[row].overview.select(selection)
    }

    // MARK: - Helpers

    /// A row has something to choose: a card with a window on screen.
    private static func hasCards(_ row: Row) -> Bool {
        row.overview.cards.contains { !$0.collapsed }
    }

    /// Where `card` of `row` is drawn across the screen: its drawn center from the middle of its row. Nil when `drawn`
    /// does not hold that card.
    private static func place(of card: Int, in drawn: [Overview.Drawn], row: Int) -> Double? {
        guard drawn.indices.contains(row), drawn[row].cards.indices.contains(card) else { return nil }
        let span = drawn[row].cards[card]
        return (span.lowerBound + span.upperBound) / 2 - drawn[row].width / 2
    }
}
