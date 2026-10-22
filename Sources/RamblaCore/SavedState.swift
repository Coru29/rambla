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
    /// When the strip was last in view; files from before 1.1.0 have none.
    public var lastSeen: Date?
    /// The login session it was last in view in: within it, its window ids are still the live ones. Files from before
    /// 1.1.0 do not say.
    public var session: String?
    /// Its windows, to recognise them again. Files from before 1.1.0 keep them only in `SavedState.refs`.
    public var refs: [WindowRef]
    /// Archived because its display was unplugged: when the display comes back, the strip takes its windows back from
    /// the strips they joined meanwhile.
    public var unplugged: Bool

    public init(displayUUID: String, spaceKey: String, strip: Strip, lastSeen: Date? = nil, session: String? = nil,
                refs: [WindowRef] = [], unplugged: Bool = false) {
        self.displayUUID = displayUUID
        self.spaceKey = spaceKey
        self.strip = strip
        self.lastSeen = lastSeen
        self.session = session
        self.refs = refs
        self.unplugged = unplugged
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayUUID = try container.decode(String.self, forKey: .displayUUID)
        spaceKey = try container.decode(String.self, forKey: .spaceKey)
        strip = try container.decode(Strip.self, forKey: .strip)
        lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen)
        session = try container.decodeIfPresent(String.self, forKey: .session)
        refs = try container.decodeIfPresent([WindowRef].self, forKey: .refs) ?? []
        unplugged = try container.decodeIfPresent(Bool.self, forKey: .unplugged) ?? false
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

    public init() {}

    /// The archive at launch: every strip of the saved file, dated now when the file has no date. Strips from before
    /// 1.1.0 (no session) take their windows' refs from the file's shared list.
    public init(loading state: SavedState?, at now: Date) {
        guard let state else { return }
        var shared: [WindowID: WindowRef] = [:]
        for ref in state.refs where shared[ref.id] == nil { shared[ref.id] = ref }
        strips = state.strips.map { strip in
            var strip = strip
            if strip.lastSeen == nil { strip.lastSeen = now }
            if strip.session == nil { strip.refs = strip.strip.allWindows.compactMap { shared[$0] } }
            return strip
        }
    }

    /// Archives `strip` (the one of an unplugged display, seen until `now`), replacing any of the same display and Space.
    public mutating func store(_ strip: SavedStrip, at now: Date) {
        var strip = strip
        strip.lastSeen = now
        strips.removeAll { $0.isFor(displayUUID: strip.displayUUID, spaceKey: strip.spaceKey) }
        strips.append(strip)
    }

    /// Takes the strip of that display and Space out of the archive, to restore it.
    public mutating func take(displayUUID: String, spaceKey: String) -> SavedStrip? {
        guard let index = strips.firstIndex(where: { $0.isFor(displayUUID: displayUUID, spaceKey: spaceKey) }) else {
            return nil
        }
        return strips.remove(at: index)
    }

    /// The archived strip of that display and Space, left in the archive.
    public func strip(displayUUID: String, spaceKey: String) -> SavedStrip? {
        strips.first { $0.isFor(displayUUID: displayUUID, spaceKey: spaceKey) }
    }

    /// For a display that is back with its desktop under a new key: the one strip archived when it was unplugged, as
    /// long as that strip's desktop is gone from the display (`spaces`, the keys the display has now); while it is
    /// still there, its own key will find it. With several, nothing: only exact keys can tell them apart.
    public func strayStrip(displayUUID: String, spaces: Set<String>) -> SavedStrip? {
        let mine = strips.filter { $0.displayUUID == displayUUID && $0.unplugged }
        guard mine.count == 1, let only = mine.first, !spaces.contains(only.spaceKey) else { return nil }
        return only
    }

    /// The display is back and had its chance to take its windows back: from now on its strips are matched like any
    /// other saved strip, so a desktop visited later never pulls windows the user is working with somewhere else.
    public mutating func settle(displayUUID: String) {
        for index in strips.indices where strips[index].displayUUID == displayUUID { strips[index].unplugged = false }
    }

    /// What to save: the live strips, seen `now`, then the archived ones that no live strip replaces and that are not
    /// older than `maxAge`. Each strip keeps its own refs; `refs` also lists every window once, the live ones first,
    /// for the floating windows and for older versions of Rambla.
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
            for ref in strip.refs where known.insert(ref.id).inserted { state.refs.append(ref) }
        }
        return state
    }
}

/// The contents of `state.json`.
public struct SavedState: Codable, Equatable, Sendable {
    /// 2: `floating` holds only the windows the user floated. Version 1 also held the ones Rambla floated by itself
    /// (moved by another app), which kept them out of the strip after every restart.
    public static let currentVersion = 2

    public var version: Int
    /// The login session the file was written in, which the ids of `refs` and `floating` belong to. Files from before
    /// 1.1.0 do not say.
    public var session: String?
    /// Every window that appears in `strips` or `floating`, once, for matching after a restart.
    public var refs: [WindowRef]
    public var strips: [SavedStrip]
    /// Windows the user took out of the strip.
    public var floating: [WindowID]

    public init(version: Int = SavedState.currentVersion, session: String? = nil, refs: [WindowRef] = [],
                strips: [SavedStrip] = [], floating: [WindowID] = []) {
        self.version = version
        self.session = session
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
    /// Maps saved window ids to the live windows they most likely are, the way the login session they were saved in
    /// allows (`session`; files from before 1.1.0 do not say):
    /// - in this one (`current`) ids are the live ones, so only the same id counts: a window that shares a saved title
    ///   is another window;
    /// - in an earlier one ids were handed out again, so only the app and the title count;
    /// - when unknown, ids first and then titles.
    /// Titles count only with `byTitle`: past the first moments of a session, a new window sharing a saved title is
    /// another window too.
    public static func match(saved: [WindowRef], live: [WindowRef], session: String?, current: String,
                             byTitle: Bool = true) -> [WindowID: WindowID] {
        let sameSession = session == current
        return match(saved: saved, live: live, byID: session == nil || sameSession, byTitle: byTitle && !sameSession)
    }

    /// Maps saved window ids to the live windows they most likely are; saved windows with no match are absent.
    /// Pass 1 (`byID`) pairs windows with the same id and the same app (same login session). Pass 2 (`byTitle`) pairs
    /// what is left by app and identical non-empty title, in order (after a restart). Each live window is used at most
    /// once, and pass 1 claims its windows first so a title match can never steal a window whose id is known.
    public static func match(saved: [WindowRef], live: [WindowRef], byID: Bool = true,
                             byTitle: Bool = true) -> [WindowID: WindowID] {
        var mapping: [WindowID: WindowID] = [:]
        var claimed = Set<Int>()   // indices into `live`

        var liveIndexByID: [WindowID: Int] = [:]
        for (index, ref) in live.enumerated() where liveIndexByID[ref.id] == nil { liveIndexByID[ref.id] = index }

        for ref in saved where byID && mapping[ref.id] == nil {
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
