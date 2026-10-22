import Foundation

/// What is needed to recognise a window again later: its id while the system session lasts, its app and title across
/// a restart (ids are not stable across reboots).
public struct WindowRef: Codable, Hashable, Sendable {
    public var id: WindowID
    public var bundleID: String
    public var title: String

    public init(id: WindowID, bundleID: String, title: String) {
        self.id = id
        self.bundleID = bundleID
        self.title = title
    }
}

/// One strip, keyed by the display (UUID) and the Space (key) it belongs to.
public struct SavedStrip: Codable, Equatable, Sendable {
    public var displayUUID: String
    public var spaceKey: String
    public var strip: Strip

    public init(displayUUID: String, spaceKey: String, strip: Strip) {
        self.displayUUID = displayUUID
        self.spaceKey = spaceKey
        self.strip = strip
    }
}

/// The contents of `state.json`.
public struct SavedState: Codable, Equatable, Sendable {
    /// 2: `floating` holds only the windows the user floated. Version 1 also held the ones Rambla floated by itself
    /// (moved by another app), which kept them out of the strip after every restart.
    public static let currentVersion = 2

    public var version: Int
    /// Every window that appears in `strips` or `floating`, for matching after a restart.
    public var refs: [WindowRef]
    public var strips: [SavedStrip]
    /// Windows the user took out of the strip.
    public var floating: [WindowID]

    public init(version: Int = SavedState.currentVersion, refs: [WindowRef] = [], strips: [SavedStrip] = [],
                floating: [WindowID] = []) {
        self.version = version
        self.refs = refs
        self.strips = strips
        self.floating = floating
    }

    /// The same state with today's meaning. Version 1's floating list cannot tell the user's floating windows from
    /// the ones Rambla floated by itself, so it is dropped: those windows go back to their strips.
    public func upgraded() -> SavedState {
        var state = self
        if version < 2 { state.floating = [] }
        state.version = Self.currentVersion
        return state
    }
}

public enum StateMatcher {
    /// Maps saved window ids to the live windows they most likely are; saved windows with no match are absent.
    /// Pass 1 pairs windows with the same id and the same app (same login session). Pass 2 pairs what is left by app
    /// and identical non-empty title, in order (after a restart). Each live window is used at most once, and pass 1
    /// claims its windows first so a title match can never steal a window whose id is known.
    public static func match(saved: [WindowRef], live: [WindowRef]) -> [WindowID: WindowID] {
        var mapping: [WindowID: WindowID] = [:]
        var claimed = Set<Int>()   // indices into `live`

        var liveIndexByID: [WindowID: Int] = [:]
        for (index, ref) in live.enumerated() where liveIndexByID[ref.id] == nil { liveIndexByID[ref.id] = index }

        for ref in saved where mapping[ref.id] == nil {
            guard let index = liveIndexByID[ref.id], !claimed.contains(index), live[index].bundleID == ref.bundleID
            else { continue }
            mapping[ref.id] = live[index].id
            claimed.insert(index)
        }

        for ref in saved where mapping[ref.id] == nil && !ref.title.isEmpty {
            guard let index = live.indices.first(where: {
                !claimed.contains($0) && live[$0].bundleID == ref.bundleID && live[$0].title == ref.title
            }) else { continue }
            mapping[ref.id] = live[index].id
            claimed.insert(index)
        }
        return mapping
    }
}

extension Strip {
    /// Rewrites window ids through `map` (saved id -> live id) after a restore.
    /// Windows without a mapping are dropped together with their height weights, and columns left empty are removed.
    /// Cleanup follows `remove(window:)`: `focused` stays on the same column when it survives, otherwise it becomes
    /// `min(oldIndex, count - 1)` (nil when nothing is left); `active` stays on the same window when it survives,
    /// otherwise on the window that took its slot (the last one if none follows). `scroll` is kept.
    /// A mapped id that would appear twice is kept only the first time, so no window lands in two places.
    public func remapped(_ map: [WindowID: WindowID]) -> Strip {
        var placed = Set<WindowID>()
        var kept: [Column] = []
        var newIndexOfColumn: [Int?] = []   // parallel to `columns`; nil when the column was dropped

        for old in columns {
            var windows: [WindowID] = []
            var weights: [Double] = []
            var survivorsBeforeActive = 0
            for (index, window) in old.windows.enumerated() {
                guard let mapped = map[window], placed.insert(mapped).inserted else { continue }
                if index < old.active { survivorsBeforeActive += 1 }
                windows.append(mapped)
                weights.append(old.heightWeights.indices.contains(index) ? old.heightWeights[index] : 1)
            }
            guard !windows.isEmpty else {
                newIndexOfColumn.append(nil)
                continue
            }
            var column = old
            column.windows = windows
            column.heightWeights = weights
            column.active = min(survivorsBeforeActive, windows.count - 1)   // the active slot, or the last window
            newIndexOfColumn.append(kept.count)
            kept.append(column)
        }

        var newFocused: Int?
        if let oldFocused = focused, !kept.isEmpty {
            if newIndexOfColumn.indices.contains(oldFocused), let survivor = newIndexOfColumn[oldFocused] {
                newFocused = survivor
            } else {
                newFocused = min(max(oldFocused, 0), kept.count - 1)
            }
        }
        return Strip(columns: kept, focused: newFocused, scroll: scroll)
    }
}
