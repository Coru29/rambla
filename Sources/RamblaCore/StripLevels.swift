/// The rules of a stack of strips (those of one display and Space): levels 0, 1, 2… from the bottom, one in view at a
/// time, where 0 is the strip there has always been. They say where a move between levels goes and which empty levels
/// go. Kept apart from the windows, so that they can be tested without any.
///
/// A level with no windows is kept only while it is useful. Above everything that has windows it is a place for the
/// next one, so a new level can always be opened there, but it goes as soon as it is left. Below a level with windows
/// it stays, so that "work below, home above" does not flip over when one of the two is empty for a while.
public enum StripLevels {
    /// Where a move from `active` goes. Levels 0...`top` exist; `occupied` are the ones with at least one window.
    /// Up: the next level, or a new one above `top` when `active` is the top and has windows. Down: the previous one.
    /// Nil at either end.
    public static func target(from active: Int, up: Bool, top: Int, occupied: Set<Int>) -> Int? {
        if !up { return active > 0 ? active - 1 : nil }
        if active < top { return active + 1 }
        // The top is the end of the stack unless it has windows: another level above an empty one would only pile up
        // empty levels.
        return occupied.contains(active) ? active + 1 : nil
    }

    /// The levels to remove, ascending: those above both the highest occupied level and `active`. Never 0.
    public static func droppable(top: Int, occupied: Set<Int>, active: Int) -> [Int] {
        // Level 0 always stays, empty or not, so with no windows anywhere only the levels above it can go.
        let highestKept = max(occupied.max() ?? 0, active)
        return highestKept < top ? Array((highestKept + 1)...top) : []
    }

    /// Whether a short swipe up or down goes to the strip above: the fingers (or the pointer) went up when `fingersUp`.
    /// With the device's natural direction the content follows them, so going down brings the strip above into view;
    /// without it, going up does.
    public static func stripAbove(fingersUp: Bool, natural: Bool) -> Bool {
        natural ? !fingersUp : fingersUp
    }

    /// The level a restored stack shows: `saved` (nil means 0), kept within 0...`top`.
    public static func restoredActive(_ saved: Int?, top: Int) -> Int {
        // Nil: a file from before stacked strips. A saved level above `top` has nothing left to restore, and one below
        // 0 comes only from a hand-edited file.
        max(0, min(saved ?? 0, top))
    }
}
