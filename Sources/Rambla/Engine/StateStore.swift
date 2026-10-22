import AppKit
import RamblaCore

/// Persists the strips to ~/Library/Application Support/Rambla/state.json.
enum StateStore {
    static var url: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Rambla", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    static func save(_ state: SavedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> SavedState? {
        guard let data = try? Data(contentsOf: url),
              var state = try? JSONDecoder().decode(SavedState.self, from: data).upgraded() else { return nil }
        // A hand-edited or corrupt file must not break the strip invariants the operations rely on.
        for index in state.strips.indices {
            state.strips[index].strip.columns = state.strips[index].strip.columns.compactMap { column in
                guard !column.windows.isEmpty else { return nil }
                var column = column
                if column.heightWeights.count != column.windows.count {
                    column.heightWeights = Array(repeating: 1, count: column.windows.count)
                }
                column.active = min(max(column.active, 0), column.windows.count - 1)
                return column
            }
            let count = state.strips[index].strip.columns.count
            if let focused = state.strips[index].strip.focused, !(0..<count).contains(focused) {
                state.strips[index].strip.focused = count > 0 ? 0 : nil
            }
        }
        return state
    }
}

extension WindowManager {
    func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    func saveNow() {
        // No window known at all (Accessibility lists none while the screen is locked) is no layout: keep the file's.
        guard !windows.isEmpty else { return }
        var refs: [RamblaCore.WindowRef] = []
        var saved: [SavedStrip] = []
        for (key, strip) in strips where !strip.columns.isEmpty {
            guard let spaceKey = spaceKeys[key] else { continue }
            saved.append(SavedStrip(displayUUID: key.displayUUID, spaceKey: spaceKey, strip: strip))
            for id in strip.allWindows {
                if let record = windows[id] { refs.append(RamblaCore.WindowRef(id: id, bundleID: record.bundleID ?? "", title: record.title)) }
            }
        }
        // Only the windows the user floated: the ones Rambla floated by itself go back to the strip after a restart.
        let chosen = floating.subtracting(autoFloated)
        for id in chosen {
            if let record = windows[id] { refs.append(RamblaCore.WindowRef(id: id, bundleID: record.bundleID ?? "", title: record.title)) }
        }
        StateStore.save(archive.merged(into: SavedState(refs: refs, strips: saved, floating: Array(chosen)), at: Date()))
    }

    /// What is needed to recognise the window again after a restart.
    func ref(_ id: WindowID) -> RamblaCore.WindowRef? {
        windows[id].map { RamblaCore.WindowRef(id: id, bundleID: $0.bundleID ?? "", title: $0.title) }
    }

    /// The first time a display and Space are in view this session, or when an unplugged display comes back, rebuild
    /// their strip from the archive: windows are matched by id, then by app + title (after a restart ids are new), and
    /// the ones the archive does not know are added afterwards in x order. A display that comes back takes back its
    /// windows from the strips they joined meanwhile, as long as they are on screen and the user did not float them.
    func restoreFromSavedState(keys: [StripKey], candidates: [WindowRecord], visible: Set<WindowID>) {
        // Without a window to place in a strip (Rambla started while the screen was locked, when Accessibility lists
        // none), wait for one instead of using up the restore of the strips seen now.
        guard windows.values.contains(where: { $0.kind == .tile }) else { return }
        let live = candidates.map { RamblaCore.WindowRef(id: $0.id, bundleID: $0.bundleID ?? "", title: $0.title) }
        let matches = StateMatcher.match(saved: Array(archive.refs.values), live: live)
        for key in keys where !restoredKeys.contains(key) {
            restoredKeys.insert(key)
            guard let spaceKey = spaceKeys[key] else { continue }
            // Archived this session (an unplugged display): its ids are live ones. `onlyCurrentStrip` only finds those.
            guard let saved = archive.strip(displayUUID: key.displayUUID, spaceKey: spaceKey)
                ?? archive.onlyCurrentStrip(displayUUID: key.displayUUID) else { continue }
            let returning = archive.isFromThisSession(displayUUID: saved.displayUUID, spaceKey: saved.spaceKey)
            let alreadyPlaced = Set(strips.values.flatMap(\.allWindows))
            var map = matches.filter { !alreadyPlaced.contains($0.value) }
            if returning {
                // The display came back: its windows are wherever macOS put them meanwhile.
                for id in saved.strip.allWindows where map[id] == nil {
                    guard let record = windows[id], record.kind == .tile, visible.contains(id), !floating.contains(id),
                          !map.values.contains(id) else { continue }
                    map[id] = id
                }
            }
            var restored = saved.strip.remapped(map)
            // None of its windows is here: it stays archived, for a later restart.
            guard !restored.columns.isEmpty else { continue }
            _ = archive.take(displayUUID: saved.displayUUID, spaceKey: saved.spaceKey)
            for id in restored.allWindows {
                for other in Array(strips.keys) where other != key && strips[other]!.contains(id) {
                    strips[other]!.remove(window: id)
                }
            }
            if let current = strips[key] {
                for id in current.allWindows where !restored.contains(id) {
                    restored.insert(window: id, width: current.location(of: id).map { current.columns[$0.column].width } ?? .fraction(0.5), at: .end)
                }
            }
            strips[key] = restored
            Log.info(returning ? "Display \(key.displayUUID.prefix(8)) is back: \(restored.allWindows.count) windows in their places"
                               : "Restored \(restored.allWindows.count) windows on display \(key.displayUUID.prefix(8))")
        }
        // Each saved floating window floats one live window, once, from the same pairing the strips used. Titles only
        // count while apps are still bringing their windows back after Rambla starts.
        guard !pendingFloating.isEmpty else { return }
        let startingUp = CFAbsoluteTimeGetCurrent() - launchTime < Self.restoreByTitleWindow
        for (savedID, liveID) in StateMatcher.floating(in: matches, pending: pendingFloating, byTitle: startingUp) {
            pendingFloating.remove(savedID)
            markFloating(liveID)
        }
    }
}
