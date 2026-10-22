import Foundation

// Strip mutations. Conventions shared by every operation in this file:
// - An operation on "the focused column" does nothing on an empty strip, or when `focused` is nil or stale.
// - `heightWeights` stays parallel to `windows`, and `active` keeps naming a window of its column.
// - Pinned columns never take part in `stack`, `popOut` or `moveColumn(_:)`, neither as source nor as target.
// - `hidden` is the set of windows that take no space (minimized, app hidden, inactive native tab).
//   A column whose windows are all hidden is collapsed.

private extension Column {
    /// Row of `activeWindow`: `active`, or 0 when `active` is out of range (as `activeWindow` falls back).
    var activeRow: Int? {
        windows.isEmpty ? nil : (windows.indices.contains(active) ? active : 0)
    }
}

extension Strip {
    // MARK: Queries

    /// `focused` when it points at an existing column.
    private var focusedIndex: Int? {
        guard let focused, columns.indices.contains(focused) else { return nil }
        return focused
    }

    public var focusedColumn: Column? { focusedIndex.map { columns[$0] } }

    public var focusedWindow: WindowID? { focusedColumn?.activeWindow }

    /// Every window, column by column in array order (not visual order).
    public var allWindows: [WindowID] { columns.flatMap(\.windows) }

    public func location(of window: WindowID) -> (column: Int, row: Int)? {
        for (c, column) in columns.enumerated() {
            if let r = column.windows.firstIndex(of: window) { return (c, r) }
        }
        return nil
    }

    public func contains(_ window: WindowID) -> Bool { location(of: window) != nil }

    public func index(ofColumn id: UUID) -> Int? { columns.firstIndex { $0.id == id } }

    // MARK: Insert and remove

    /// Adds `window` as a new single-window column and focuses it. Without a focused column, `.afterFocused`
    /// appends. A window that is already in the strip is ignored, so no window can end up in two columns.
    public mutating func insert(window: WindowID, width: ColumnWidth, at position: InsertPosition) {
        guard !contains(window) else { return }
        let newIndex: Int
        switch position {
        case .start: newIndex = 0
        case .end: newIndex = columns.count
        case .afterFocused: newIndex = focusedIndex.map { $0 + 1 } ?? columns.count
        }
        columns.insert(Column(windows: [window], width: width), at: newIndex)
        focused = newIndex
    }

    /// Removes `window`, and its column if that leaves it empty. Focus stays on the same column object when
    /// it survives; otherwise it moves to `min(oldIndex, count - 1)`, or to nil when the strip is empty.
    public mutating func remove(window: WindowID) {
        guard let found = location(of: window) else { return }
        let focusedID = focusedColumn?.id
        detach(row: found.row, fromColumn: found.column)
        if columns[found.column].windows.isEmpty { columns.remove(at: found.column) }
        if let focusedID, let survivor = index(ofColumn: focusedID) {
            focused = survivor
        } else if let old = focused {
            focused = columns.isEmpty ? nil : min(old, columns.count - 1)
        }
    }

    /// Takes the window at `row` out of column `c`, keeping `heightWeights` parallel and `active` on the same
    /// window (or on the one that took its slot). An emptied column is left for the caller to remove.
    private mutating func detach(row: Int, fromColumn c: Int) {
        columns[c].windows.remove(at: row)
        columns[c].heightWeights.remove(at: row)
        if row < columns[c].active { columns[c].active -= 1 }
        columns[c].active = max(0, min(columns[c].active, columns[c].windows.count - 1))
    }

    // MARK: Focus

    /// Focuses the column holding `window` and makes it that column's active window.
    @discardableResult
    public mutating func focus(window: WindowID) -> Bool {
        guard let found = location(of: window) else { return false }
        focused = found.column
        columns[found.column].active = found.row
        return true
    }

    /// Steps along `visualOrder` without wrapping. A focused column that is itself collapsed keeps its slot
    /// in that order, so navigation continues from where it would be.
    public mutating func focusColumn(_ direction: HDirection, hidden: Set<WindowID>) {
        guard let current = focusedIndex else { return }
        let order = visualOrder(hidden: [])
        guard var position = order.firstIndex(of: current) else { return }
        let step = direction == .left ? -1 : 1
        position += step
        while order.indices.contains(position) {
            if !isCollapsed(order[position], hidden: hidden) {
                focused = order[position]
                return
            }
            position += step
        }
    }

    /// Moves the active window up or down inside the focused column, skipping hidden windows, without wrapping.
    public mutating func focusRow(_ direction: VDirection, hidden: Set<WindowID>) {
        guard let f = focusedIndex, var row = columns[f].activeRow else { return }
        let windows = columns[f].windows
        let step = direction == .up ? -1 : 1
        row += step
        while windows.indices.contains(row) {
            if !hidden.contains(windows[row]) {
                columns[f].active = row
                return
            }
            row += step
        }
    }

    public mutating func focusFirst(hidden: Set<WindowID>) {
        focusNth(1, hidden: hidden)
    }

    public mutating func focusLast(hidden: Set<WindowID>) {
        guard focusedIndex != nil, let last = visualOrder(hidden: hidden).last else { return }
        focused = last
    }

    /// `n` is 1-based along `visualOrder`; out of range does nothing.
    public mutating func focusNth(_ n: Int, hidden: Set<WindowID>) {
        guard focusedIndex != nil else { return }
        let order = visualOrder(hidden: hidden)
        guard order.indices.contains(n - 1) else { return }
        focused = order[n - 1]
    }

    // MARK: Move

    /// Swaps the focused column with the nearest unpinned neighbor in that direction; focus follows it.
    public mutating func moveColumn(_ direction: HDirection) {
        guard let f = focusedIndex, columns[f].pinned == nil else { return }
        let step = direction == .left ? -1 : 1
        var target = f + step
        while columns.indices.contains(target), columns[target].pinned != nil { target += step }
        guard columns.indices.contains(target) else { return }
        columns.swapAt(f, target)
        focused = target
    }

    /// `to` is the final index of the moved column, which becomes the focused one. Out-of-range indices, or
    /// `from == to`, do nothing.
    public mutating func moveColumn(from: Int, to: Int) {
        guard columns.indices.contains(from), columns.indices.contains(to), from != to else { return }
        let column = columns.remove(at: from)
        columns.insert(column, at: to)
        focused = to
    }

    /// Swaps the active window with its neighbor in the focused column; its height weight travels with it.
    public mutating func moveRow(_ direction: VDirection) {
        guard let f = focusedIndex, let row = columns[f].activeRow else { return }
        let neighbor = direction == .up ? row - 1 : row + 1
        guard columns[f].windows.indices.contains(neighbor) else { return }
        columns[f].windows.swapAt(row, neighbor)
        columns[f].heightWeights.swapAt(row, neighbor)
        columns[f].active = neighbor
    }

    // MARK: Stack and pop out

    /// Moves the active window of the focused column to the end of the nearest unpinned, non-collapsed column in
    /// that direction, with weight 1. An emptied source column is removed. Focus goes to the target column.
    public mutating func stack(_ direction: HDirection, hidden: Set<WindowID>) {
        guard let f = focusedIndex, columns[f].pinned == nil, let row = columns[f].activeRow else { return }
        let step = direction == .left ? -1 : 1
        var target = f + step
        while columns.indices.contains(target), columns[target].pinned != nil || isCollapsed(target, hidden: hidden) {
            target += step
        }
        guard columns.indices.contains(target) else { return }

        let window = columns[f].windows[row]
        let targetID = columns[target].id
        detach(row: row, fromColumn: f)
        columns[target].windows.append(window)
        columns[target].heightWeights.append(1)
        columns[target].active = columns[target].windows.count - 1
        if columns[f].windows.isEmpty { columns.remove(at: f) }
        focused = index(ofColumn: targetID)
    }

    /// Moves the active window of a multi-window column into a new column of the same width, immediately to the
    /// left or right of the source. Focus goes to the new column.
    public mutating func popOut(_ direction: HDirection) {
        guard let f = focusedIndex, columns[f].pinned == nil, columns[f].windows.count > 1,
              let row = columns[f].activeRow else { return }
        let window = columns[f].windows[row]
        let width = columns[f].width
        detach(row: row, fromColumn: f)
        let newIndex = direction == .left ? f : f + 1
        columns.insert(Column(windows: [window], width: width), at: newIndex)
        focused = newIndex
    }

    // MARK: Mode and pins

    public mutating func toggleTabbed() {
        guard let f = focusedIndex else { return }
        columns[f].mode = columns[f].mode == .tabbed ? .stacked : .tabbed
    }

    /// Unpins the focused column if it is pinned on `side`. Otherwise pins it there, releasing whichever other
    /// column held that side (a column pinned on the other side switches sides).
    public mutating func togglePin(_ side: PinSide) {
        guard let f = focusedIndex else { return }
        if columns[f].pinned == side {
            columns[f].pinned = nil
            return
        }
        for i in columns.indices where i != f && columns[i].pinned == side { columns[i].pinned = nil }
        columns[f].pinned = side
    }

    // MARK: Width

    /// Sets the focused column to the first preset greater than its current fraction plus 1 %, wrapping to the
    /// first preset when none is greater. Forgets the width saved by `toggleFullWidth`.
    public mutating func cycleWidth(presets: [Double], available: Double, gap: Double) {
        guard let f = focusedIndex, let first = presets.first else { return }
        let current = columns[f].width.asFraction(available: available, gap: gap)
        columns[f].width = .fraction(presets.first(where: { $0 > current + 0.01 }) ?? first)
        columns[f].widthBeforeFull = nil
    }

    /// Full width, remembering the previous width in `widthBeforeFull`; calling it again restores that width.
    public mutating func toggleFullWidth() {
        guard let f = focusedIndex else { return }
        if let previous = columns[f].widthBeforeFull {
            columns[f].width = previous
            columns[f].widthBeforeFull = nil
        } else {
            columns[f].widthBeforeFull = columns[f].width
            columns[f].width = .fraction(1)
        }
    }

    /// Full width on (swipe up) or back to the width it had (swipe down). Unlike `toggleFullWidth`, asking for the
    /// state the column is already in does nothing, so a second swipe up keeps the width to go back to. A column
    /// made narrower after `toggleFullWidth` goes full again and still remembers its old width.
    public mutating func setFullWidth(_ full: Bool) {
        guard let f = focusedIndex else { return }
        if full {
            guard columns[f].width != .fraction(1) else { return }
            if columns[f].widthBeforeFull == nil { columns[f].widthBeforeFull = columns[f].width }
            columns[f].width = .fraction(1)
        } else if let previous = columns[f].widthBeforeFull {
            columns[f].width = previous
            columns[f].widthBeforeFull = nil
        }
    }

    /// Changes the focused column's width by `delta` (as a fraction), keeping it within 0.1...1.0.
    public mutating func adjustWidth(by delta: Double, available: Double, gap: Double) {
        guard let f = focusedIndex else { return }
        // A column wider than the area is shown at the area's width: start from what is shown.
        let current = min(columns[f].width.asFraction(available: available, gap: gap), 1)
        columns[f].width = .fraction(min(max(current + delta, 0.1), 1.0))
    }

    /// Adopts a width in points for the column holding `window`.
    public mutating func setWidth(points: Double, window: WindowID) {
        guard let found = location(of: window) else { return }
        columns[found.column].width = .points(points)
    }

    // MARK: Height

    /// With two or more visible windows, moves the active window's share of the visible height by `delta`
    /// (share clamped to 0.1...0.9). With one visible window, adjusts `heightFraction` instead (0.2...1.0).
    public mutating func adjustHeight(by delta: Double, hidden: Set<WindowID>) {
        guard let f = focusedIndex else { return }
        let visible = visibleRows(ofColumn: f, hidden: hidden)
        switch visible.count {
        case 0:
            return
        case 1:
            columns[f].heightFraction = min(max((columns[f].heightFraction ?? 1) + delta, 0.2), 1.0)
        default:
            guard let row = columns[f].activeRow, visible.contains(row) else { return }
            let weights = columns[f].heightWeights
            let share = weights[row] / visible.reduce(0) { $0 + weights[$1] }
            rescale(row: row, ofColumn: f, toShare: share + delta, among: visible)
        }
    }

    /// Gives `window` the height share `share` (clamped to 0.1...0.9) of the visible windows of its column.
    /// Does nothing unless the window is visible and shares its column with another visible window.
    public mutating func setHeightShare(window: WindowID, share: Double, hidden: Set<WindowID>) {
        guard let found = location(of: window) else { return }
        let visible = visibleRows(ofColumn: found.column, hidden: hidden)
        guard visible.count >= 2, visible.contains(found.row) else { return }
        rescale(row: found.row, ofColumn: found.column, toShare: share, among: visible)
    }

    /// Resets the focused column to equal heights.
    public mutating func equalizeHeights() {
        guard let f = focusedIndex else { return }
        columns[f].heightWeights = Array(repeating: 1, count: columns[f].windows.count)
        columns[f].heightFraction = nil
    }

    private func visibleRows(ofColumn c: Int, hidden: Set<WindowID>) -> [Int] {
        columns[c].windows.indices.filter { !hidden.contains(columns[c].windows[$0]) }
    }

    /// Gives `row` the share `share` (clamped to 0.1...0.9) and scales the other visible weights in proportion,
    /// so the visible weights sum to 1. Weights of hidden windows are left alone.
    private mutating func rescale(row: Int, ofColumn c: Int, toShare share: Double, among visible: [Int]) {
        let share = min(max(share, 0.1), 0.9)
        let others = visible.filter { $0 != row }
        let othersTotal = others.reduce(0) { $0 + columns[c].heightWeights[$1] }
        for other in others {
            columns[c].heightWeights[other] = othersTotal > 0
                ? columns[c].heightWeights[other] / othersTotal * (1 - share)
                : (1 - share) / Double(others.count)
        }
        columns[c].heightWeights[row] = share
    }
}
