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
    /// When the strip was last in view; files from before 1.0.1 have none.
    public var lastSeen: Date?

    public init(displayUUID: String, spaceKey: String, strip: Strip, lastSeen: Date? = nil) {
        self.displayUUID = displayUUID
        self.spaceKey = spaceKey
        self.strip = strip
        self.lastSeen = lastSeen
    }

    func isFor(displayUUID: String, spaceKey: String) -> Bool {
        self.displayUUID == displayUUID && self.spaceKey == spaceKey
    }
}

/// The strips that are not in view: those saved for a Space not visited since Rambla started, and those of a display
/// that was unplugged. Each is taken back when its display and Space are in view again, and until then it is saved
/// with the live strips, so its arrangement survives restarts.
public struct StripArchive: Equatable, Sendable {
    /// How long an archived strip is kept: a month away from the office monitor still finds it as it was, while the
    /// strip of a Space deleted long ago stops being carried.
    public static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    public private(set) var strips: [SavedStrip] = []
    /// Every window the archived strips hold, by the id they have in them.
    public private(set) var refs: [WindowID: WindowRef] = [:]
    /// Strips archived during this session: their window ids are still the live ones.
    private var current: Set<String> = []

    public init() {}

    /// The archive at launch: every strip of the saved file, dated now when the file has no date.
    public init(loading state: SavedState?, at now: Date) {
        guard let state else { return }
        strips = state.strips.map { strip in
            var strip = strip
            if strip.lastSeen == nil { strip.lastSeen = now }
            return strip
        }
        for ref in state.refs { refs[ref.id] = ref }
    }

    /// Archives `strip` (the one of an unplugged display, seen until `now`), replacing any of the same display and Space.
    public mutating func store(_ strip: SavedStrip, refs: [WindowRef], at now: Date) {
        var strip = strip
        strip.lastSeen = now
        strips.removeAll { $0.isFor(displayUUID: strip.displayUUID, spaceKey: strip.spaceKey) }
        strips.append(strip)
        for ref in refs { self.refs[ref.id] = ref }
        current.insert(Self.key(strip.displayUUID, strip.spaceKey))
    }

    /// Takes the strip of that display and Space out of the archive, to restore it.
    public mutating func take(displayUUID: String, spaceKey: String) -> SavedStrip? {
        guard let index = strips.firstIndex(where: { $0.isFor(displayUUID: displayUUID, spaceKey: spaceKey) }) else {
            return nil
        }
        current.remove(Self.key(displayUUID, spaceKey))
        return strips.remove(at: index)
    }

    /// The archived strip of that display and Space, left in the archive.
    public func strip(displayUUID: String, spaceKey: String) -> SavedStrip? {
        strips.first { $0.isFor(displayUUID: displayUUID, spaceKey: spaceKey) }
    }

    /// The strip archived during this session for that display, when it is the only one: an unplugged display's
    /// desktop can come back under a new key. With several, nothing (only exact keys can tell them apart).
    public func onlyCurrentStrip(displayUUID: String) -> SavedStrip? {
        let mine = strips.filter { $0.displayUUID == displayUUID && current.contains(Self.key($0.displayUUID, $0.spaceKey)) }
        return mine.count == 1 ? mine.first : nil
    }

    /// Whether the strip of that display and Space was archived during this session, so its ids are live ids.
    public func isFromThisSession(displayUUID: String, spaceKey: String) -> Bool {
        current.contains(Self.key(displayUUID, spaceKey))
    }

    /// What to save: the live strips, seen `now`, then the archived ones that no live strip replaces and that are not
    /// older than `maxAge`, with the refs of every window they hold (once each).
    public func merged(into live: SavedState, at now: Date) -> SavedState {
        var state = live
        state.strips = live.strips.map { strip in
            var strip = strip
            strip.lastSeen = now
            return strip
        }
        var known = Set(state.refs.map(\.id))
        for strip in strips {
            guard !live.strips.contains(where: { $0.isFor(displayUUID: strip.displayUUID, spaceKey: strip.spaceKey) }),
                  let seen = strip.lastSeen, now.timeIntervalSince(seen) <= Self.maxAge else { continue }
            state.strips.append(strip)
            for id in strip.strip.allWindows where !known.contains(id) {
                guard let ref = refs[id] else { continue }
                state.refs.append(ref)
                known.insert(id)
            }
        }
        return state
    }

    private static func key(_ displayUUID: String, _ spaceKey: String) -> String { displayUUID + "/" + spaceKey }
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
    /// The saved floating windows (`pending`) to float now, taken from the one pairing the strip restore used, so a
    /// live window the strips got is never floated too. Past the first moments of a session (`byTitle` false) only
    /// pairs with the same id count: a new window sharing a saved title is a different window.
    public static func floating(in matches: [WindowID: WindowID], pending: Set<WindowID>, byTitle: Bool) -> [WindowID: WindowID] {
        matches.filter { pending.contains($0.key) && (byTitle || $0.key == $0.value) }
    }

    /// Maps saved window ids to the live windows they most likely are; saved windows with no match are absent.
    /// Pass 1 pairs windows with the same id and the same app (same login session). Pass 2 pairs what is left by app
    /// and identical non-empty title, in order (after a restart). Each live window is used at most once, and pass 1
    /// claims its windows first so a title match can never steal a window whose id is known. Without `byTitle` only
    /// pass 1 runs: past the first moments of a session, a new window sharing a saved title is a different window.
    public static func match(saved: [WindowRef], live: [WindowRef], byTitle: Bool = true) -> [WindowID: WindowID] {
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

        for ref in saved where byTitle && mapping[ref.id] == nil && !ref.title.isEmpty {
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
