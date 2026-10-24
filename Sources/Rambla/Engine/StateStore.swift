import AppKit
import RamblaCore

/// Persists the strips to ~/Library/Application Support/Rambla/state.json.
enum StateStore {
    /// Test mode only (`--only-bundle` with `--state-file`): the file the live tests restart Rambla with, read and
    /// written instead of the user's. Without it, test mode reads and writes no layout at all.
    @MainActor static var testFile: URL?

    /// The file the strips are saved to: the user's, or in test mode the tests' own (`testFile`).
    @MainActor static var url: URL {
        if let testFile { return testFile }
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Rambla", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    @MainActor static func save(_ state: SavedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    @MainActor static func load() -> SavedState? {
        guard let data = try? Data(contentsOf: url),
              var state = try? JSONDecoder().decode(SavedState.self, from: data).upgraded() else { return nil }
        // A hand-edited or corrupt file must not break the strip invariants the operations rely on. A strip below
        // level 0 has no place in a stack: it is left out.
        state.strips.removeAll { $0.level < 0 }
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

    /// The login session Rambla runs in. macOS numbers windows again after a logout or a restart, so a saved window id
    /// names the same window only within the session it was saved in.
    static let session: String = {
        let info = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        if let uuid = info["CGSSessionUniqueSessionUUID"] as? String { return uuid }
        // Where macOS does not say, this boot and this login's audit session tell it apart.
        var boot = [CChar](repeating: 0, count: 64)
        var size = boot.count
        sysctlbyname("kern.bootsessionuuid", &boot, &size, nil, 0)
        let bootID = boot.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return bootID + "/" + String(describing: info["kCGSSessionAuditIDKey"] ?? "")
    }()
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

    /// Whether the layout is read at launch and saved: always, except in test mode, where only a file of the tests'
    /// own is (`StateStore.testFile`), never the user's.
    var keepsState: Bool { onlyBundles == nil || StateStore.testFile != nil }

    func saveNow() {
        // No window known at all (Accessibility lists none while the screen is locked) is no layout: keep the file's.
        guard keepsState, !windows.isEmpty else { return }
        var refs: [RamblaCore.WindowRef] = []
        var saved: [SavedStrip] = []
        for (key, strip) in strips where !strip.columns.isEmpty {
            guard let spaceKey = spaceKeys[key.stack] else { continue }
            // A desktop not rebuilt yet keeps its saved stack in the file, every level of it: a window that went there
            // meanwhile (moved to it from Mission Control, say) joins it when the desktop is rebuilt.
            if !restoredStacks.contains(key.stack),
               !archive.stack(displayUUID: key.displayUUID, spaceKey: spaceKey).isEmpty { continue }
            let mine = strip.allWindows.compactMap(ref)
            saved.append(SavedStrip(displayUUID: key.displayUUID, spaceKey: spaceKey, strip: strip, session: StateStore.session,
                                    refs: mine, level: key.level, activeLevel: activeLevel(of: key.stack)))
            refs += mine
        }
        // Only the windows the user floated: the ones Rambla floated by itself go back to the strip after a restart.
        let chosen = floating.subtracting(autoFloated)
        refs += chosen.compactMap(ref)
        let live = SavedState(session: StateStore.session, refs: refs, strips: saved, floating: Array(chosen))
        StateStore.save(archive.merged(into: live, at: Date()))
    }

    /// What is needed to recognise the window again after a restart.
    func ref(_ id: WindowID) -> RamblaCore.WindowRef? {
        windows[id].map { RamblaCore.WindowRef(id: id, bundleID: $0.bundleID ?? "", title: $0.title) }
    }

    /// The first time a display and Space are in view this session, rebuild their stack from the archive, every level
    /// of it at once; the windows it does not know are added afterwards in x order. Windows are matched level by level
    /// from the bottom, so none lands on two levels, the way the session each strip was saved in allows
    /// (`StateMatcher.restoredLevels`; `alive` holds every window that exists). A display that comes back takes back,
    /// for `returnWindow`, the windows of the strips archived when it was unplugged, from the strips they joined
    /// meanwhile, as long as they are on screen and the user did not float them. The stack shows the level it showed
    /// when it was saved, as far as that level is still there; the rest of the reconcile lays that level out and parks
    /// the others, once the windows the stack does not know have joined it.
    func restoreFromSavedState(stacks: [StackKey], candidates: [WindowRecord], visible: Set<WindowID>,
                               alive: Set<WindowID>) {
        let now = CFAbsoluteTimeGetCurrent()
        for stack in stacks where !restoredStacks.contains(stack) {
            // A display that has just appeared may be gone in a moment (`DisplayPresence`): wait until it stays.
            guard presence.isSettled(stack.displayUUID, now: now), let spaceKey = spaceKeys[stack],
                  let display = displays.first(where: { $0.uuid == stack.displayUUID }) else { continue }
            let returning = returningDisplays[stack.displayUUID] != nil
            var saved = archive.stack(displayUUID: stack.displayUUID, spaceKey: spaceKey)
            if saved.isEmpty, returning, !display.spaceKeys.isEmpty {
                saved = archive.strayStack(displayUUID: stack.displayUUID, spaces: display.spaceKeys)
            }
            guard !saved.isEmpty else {
                // Nothing saved for it, unless macOS has not listed a returning display's desktops yet: its strips may
                // be under another key, so look again with the next change.
                if !returning || !display.spaceKeys.isEmpty { restoredStacks.insert(stack) }
                continue
            }
            // Apps are still listing their windows, or still opening after a Mac restart: rebuilt now, the strips would
            // get only the first ones. One level that waits holds the whole stack.
            guard !waitingForWindowLists, !saved.contains(where: { waitsForApps($0, now: now) }) else { continue }
            let takesBack = returning && saved.contains(where: \.unplugged)
            // The windows no other stack holds, those that already joined this one included. Without one of this
            // display among them, wait for it instead of using up the arrangement (Accessibility lists no window while
            // the screen is locked). The levels taking their windows back find them anywhere on screen.
            let own = strips.filter { $0.key.stack == stack }.sorted { $0.key.level < $1.key.level }
                .flatMap { $0.value.allWindows }
            let placed = Set(strips.filter { $0.key.stack != stack }.values.flatMap(\.allWindows))
            let free = candidates.filter { !placed.contains($0.id) } + own.compactMap { windows[$0] }
            guard takesBack || free.contains(where: {
                $0.kind == .tile && Displays.best(for: whereShown($0), in: displays)?.uuid == stack.displayUUID
            }) else { continue }
            let onScreen = !takesBack ? [] : windows.values.filter {
                $0.kind == .tile && visible.contains($0.id) && !floating.contains($0.id)
            }
            // Taking windows back from other strips goes by id, or after a Mac restart by a title only one window has.
            let levels = StateMatcher.restoredLevels(saved, free: free.compactMap { ref($0.id) },
                                                     onScreen: onScreen.compactMap { ref($0.id) }, returning: returning,
                                                     current: StateStore.session, alive: alive)
            guard !levels.isEmpty else {
                // None of its windows is here. A display that is coming back tries again with the next change. Any
                // other Space starts as it is, with other windows: its live strips replace the archived ones when
                // saved.
                if !takesBack { restoredStacks.insert(stack) }
                continue
            }
            restoredStacks.insert(stack)
            _ = archive.takeStack(displayUUID: stack.displayUUID, spaceKey: saved[0].spaceKey)
            let restored = Set(levels.values.flatMap(\.allWindows))
            // A window that comes back to another level of this stack takes along what is known of it being hidden.
            for (level, strip) in levels {
                for id in strip.allWindows {
                    guard let from = key(containing: id), from.stack == stack, from.level != level else { continue }
                    carryHidden([id], from: from, to: stack.level(level))
                }
            }
            // The windows leave the strips they joined meanwhile; those a level does not know stay, at its end.
            let rebuilt = Set(levels.keys.map(stack.level))
            for other in Array(strips.keys) where !rebuilt.contains(other) {
                for id in strips[other]!.allWindows where restored.contains(id) { strips[other]!.remove(window: id) }
            }
            for (level, var strip) in levels {
                let key = stack.level(level)
                if let current = strips[key] {
                    for id in current.allWindows where !restored.contains(id) {
                        let width = current.location(of: id).map { current.columns[$0.column].width } ?? .fraction(0.5)
                        strip.insert(window: id, width: width, at: .end)
                    }
                }
                strips[key] = strip
            }
            // Level 0 is always there, and so is every level up to the highest one restored: the empty ones in between
            // stay, as they do while Rambla runs. The level in view is the one the strip saved last remembers.
            let top = levels.keys.max()!
            for level in 0...top where strips[stack.level(level)] == nil { strips[stack.level(level)] = Strip() }
            let latest = saved.max { ($0.lastSeen ?? .distantPast) < ($1.lastSeen ?? .distantPast) }
            activeLevels[stack] = StripLevels.restoredActive(latest?.activeLevel, top: top)
            let uuid = stack.displayUUID.prefix(8)
            for level in levels.keys.sorted() {
                let count = strips[stack.level(level)]!.allWindows.count
                let onLevel = level > 0 ? ", level \(level)" : ""
                let tookBack = returning && saved.first(where: { $0.level == level })?.unplugged == true
                Log.info(tookBack ? "Display \(uuid) is back: \(count) windows in their places\(onLevel)"
                                  : "Restored \(count) windows on display \(uuid)\(onLevel)")
            }
        }
        // Each saved floating window floats one live window, once, among those no strip took (so not while strips wait
        // for the apps). Titles only count while apps are still bringing their windows back after Rambla starts.
        guard !pendingFloating.isEmpty, !waitingForWindowLists, let file = restoreState else { return }
        let startingUp = CFAbsoluteTimeGetCurrent() - launchTime < Self.restoreByTitleWindow
        let placed = Set(strips.values.flatMap(\.allWindows))
        let live = candidates.filter { !placed.contains($0.id) }.compactMap { ref($0.id) }
        let saved = file.refs.filter { pendingFloating.contains($0.id) }
        let matches = StateMatcher.match(saved: saved, live: live, session: file.session, current: StateStore.session,
                                         alive: alive, byTitle: startingUp)
        for (savedID, liveID) in matches {
            pendingFloating.remove(savedID)
            markFloating(liveID)
        }
    }
}
