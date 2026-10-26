import AppKit
import RamblaCore

/// Stacked strips: each display and Space holds a stack of strips, levels 0, 1, 2… from the bottom, and shows one of
/// them. The others are parked out of sight on a side edge (`shelve`), each keeping its focus, scroll and pinned
/// columns for when it is back in view. Where a move goes and which empty levels go are `StripLevels`' rules.
extension WindowManager {
    // MARK: - Stacks

    /// The level of `stack` in view: 0 until another one is chosen.
    func activeLevel(of stack: StackKey) -> Int { activeLevels[stack] ?? 0 }

    /// The highest level of `stack` with a strip; 0 when it has none.
    func topLevel(of stack: StackKey) -> Int {
        strips.keys.filter { $0.stack == stack }.map(\.level).max() ?? 0
    }

    /// The levels of `stack` with at least one window.
    func occupiedLevels(of stack: StackKey) -> Set<Int> {
        Set(strips.filter { $0.key.stack == stack && !$0.value.columns.isEmpty }.map(\.key.level))
    }

    /// The stack of the display under the pointer, or of the first managed display when the pointer is on none.
    func stackUnderPointer() -> StackKey? {
        let mouse = Displays.axPoint(NSEvent.mouseLocation)
        let display = enabledDisplays.first { $0.frame.contains(mouse) } ?? enabledDisplays.first
        return display.flatMap(currentKey)?.stack
    }

    // MARK: - Switching

    /// Brings `level` of `stack` into view, a new empty one when it has no strip yet, and focuses `window` (one of that
    /// level's, in its strip or floating and parked with it) or else the level's focused window, unless that one is
    /// hidden (minimized, its app hidden): then the one used last there that shows. The windows that arrive jump to
    /// their places first, the column that gets the focus already in view, behind the ones that leave, which then jump
    /// to their parking spots: nothing crosses the display, nothing in between shows, and nothing moves a second time.
    /// The floating windows go the same way (`floatShelf`): those parked with the level that comes into view come back
    /// to their places, and those in view on its display go with the level that leaves, all but `carried`, the focused
    /// one that `sendFocusedWindow` takes along, which keeps the focus. On a level with nothing that shows to focus
    /// Rambla takes the keyboard, so nothing typed reaches a window out of sight. `routed`: the switch follows a focus
    /// from outside Rambla (`FocusRoute`), so the pointer stays where it is: "mouse follows focus" is for the focus
    /// Rambla gives through its own shortcuts.
    func switchLevel(of stack: StackKey, to level: Int, focusing window: WindowID? = nil, routed: Bool = false,
                     carrying carried: WindowID? = nil) {
        guard isRunning, !isPaused, isCurrentStack(stack), level >= 0, level <= topLevel(of: stack) + 1 else { return }
        let old = activeLevel(of: stack)
        let new = stack.level(level)
        let chosen = window.flatMap { strips[new]?.contains($0) == true ? $0 : nil }
        guard level != old else {
            if let chosen { focus(window: chosen, in: new, routed: routed) }
            return
        }
        let chosenFloat = window.flatMap { floatShelf[new]?[$0] != nil ? $0 : nil }
        let focusedFloat = carried ?? chosenFloat
        // Found before anything moves, so that the floating windows coming back with the new level are not among them.
        let leaving = floatsInView(of: stack, except: carried)
        // The window of the level's strip that gets the focus, found before anything moves too: the one asked for, else
        // the strip's focused window, else, when that one is hidden or there is none (a strip read from an older file
        // may have no focused column), the one used last that shows.
        let focused = focusedFloat == nil ? chosen ?? shownWindow(of: new) : nil
        activeLevels[stack] = level
        levelSwitchedAt[stack] = CFAbsoluteTimeGetCurrent()
        if strips[new] == nil { strips[new] = Strip() }
        // Laid out with that window's column in view at once: revealed afterwards, the strip would move a second time.
        if let focused {
            strips[new]!.focus(window: focused)
            reveal(new, animate: false)
        } else {
            apply(new, animate: false)
        }
        let back = bringBackFloats(of: new)
        shelve(stack.level(old))
        parkFloats(leaving, with: stack.level(old))
        dropEmptyLevels(of: stack)
        if let focusedFloat {
            focusFloat(focusedFloat, routed: routed)
        } else if let focused {
            focus(window: focused, in: new, routed: routed)
        } else if let float = FocusRoute.byLastUse(back.sorted(), lastUsed: lastFocusedAt).first {
            // No window of its strip that shows, but floating windows came back with it: the one used last.
            focusFloat(float, routed: routed)
        } else {
            // Nothing there shows (no window, or only hidden ones): as on an empty strip.
            takeKeyboardFocus()
            emptyLevelHook?(stack)
        }
        levelHook?(stack)
        onStateChanged?()
        scheduleSave()
        Log.info("Strip level \(level) of display \(stack.displayUUID.prefix(8))")
    }

    /// Goes to the level above or below the one in view of `stack`, behind the veil (`levelTransition`); above the top,
    /// to a new empty level when the top has windows (`StripLevels.target`). False at either end of the stack.
    @discardableResult
    func stepLevel(up: Bool, on stack: StackKey) -> Bool {
        guard stepTarget(up: up, on: stack) != nil else { return false }
        behindVeil(of: stack, up: up) { [weak self] in
            // Found again once the veil covers: the stack may have changed meanwhile.
            guard let self, let level = stepTarget(up: up, on: stack) else { return }
            switchLevel(of: stack, to: level)
        }
        return true
    }

    /// The level `stepLevel` goes to, or nil when it goes nowhere.
    private func stepTarget(up: Bool, on stack: StackKey) -> Int? {
        guard isRunning, !isPaused, isCurrentStack(stack) else { return nil }
        return StripLevels.target(from: activeLevel(of: stack), up: up, top: topLevel(of: stack),
                                  occupied: occupiedLevels(of: stack))
    }

    /// Runs `change`, a switch between the strips of `stack` that the user asked for, behind the overlay's veil, or at
    /// once when there is none (`levelTransition`). A switch that follows a focus from outside Rambla never waits for
    /// it: the keyboard would be in a window out of sight meanwhile.
    private func behindVeil(of stack: StackKey, up: Bool, _ change: @escaping () -> Void) {
        guard let levelTransition else { return change() }
        levelTransition(stack, up, change)
    }

    /// Nothing in view to give the keyboard to (an empty level came into view, or the last window in view went away
    /// while the focus landed out of view): Rambla takes it, so nothing typed reaches a window out of sight, and shows
    /// nothing. No window has the focus until the user picks one, or opens or chooses an app.
    func takeKeyboardFocus() {
        focusedWindow = nil
        overlayHook?()
        Log.info("Nothing to focus in view: Rambla takes the keyboard")
        // The WindowServer brings Rambla to the front without raising any of its windows. NSApp.activate() could bring
        // an open Settings window forward, so it is only the fallback for when that private call is missing or fails.
        if Private.activateOwnProcess() { return }
        Log.error("Could not take the keyboard through the WindowServer: activating Rambla instead")
        NSApp.activate()
    }

    // MARK: - Sending windows

    /// Sends the focused window, alone, to the level above or below (a new one above the top), next to that level's
    /// focused column and with its width, and follows it there, behind the veil (`levelTransition`). The only window of
    /// the top level stays where it is rather than go up to a new level and leave an empty one below
    /// (`StripLevels.sendTarget`). A floating one (`floating`) goes along instead: the level of its display changes,
    /// and it stays in view with the focus.
    func sendFocusedWindow(up: Bool) {
        guard let plan = sendPlan(up: up) else { return }
        behindVeil(of: plan.stack, up: up) { [weak self] in
            // Planned again once the veil covers: the focus may have moved meanwhile.
            guard let self, let plan = sendPlan(up: up) else { return }
            send(plan)
        }
    }

    /// Where sending the focused window up or down takes it: the level of the stack it goes to, and the strip it
    /// leaves, nil for a floating window, which goes along.
    private struct SendPlan {
        let window: WindowID
        let stack: StackKey
        let level: Int
        let from: StripKey?
    }

    /// Where sending the focused window up or down takes it now, or nil when it stays.
    private func sendPlan(up: Bool) -> SendPlan? {
        guard isRunning, !isPaused else { return nil }
        if let id = focusedWindow, floating.contains(id), key(containing: id) == nil,
           floatShelfKey(holding: id) == nil {
            return floatAlongTarget(id, up: up).map { SendPlan(window: id, stack: $0.stack, level: $0.level, from: nil) }
        }
        guard let key = activeStripKey(), let id = strips[key]?.focusedWindow,
              let level = StripLevels.sendTarget(from: key.level, up: up, top: topLevel(of: key.stack),
                                                 occupied: occupiedLevels(of: key.stack),
                                                 alone: strips[key]?.allWindows == [id]) else { return nil }
        return SendPlan(window: id, stack: key.stack, level: level, from: key)
    }

    private func send(_ plan: SendPlan) {
        let id = plan.window
        guard let key = plan.from else {
            Log.info("Floating window \(id) goes along to strip level \(plan.level)")
            switchLevel(of: plan.stack, to: plan.level, carrying: id)
            return
        }
        let target = key.stack.level(plan.level)
        let width = strips[key]!.location(of: id).map { strips[key]!.columns[$0.column].width } ?? .fraction(0.5)
        strips[key]!.remove(window: id)
        var other = strips[target] ?? Strip()
        other.insert(window: id, width: width, at: .afterFocused)
        strips[target] = other
        carryHidden([id], from: key, to: target)
        Log.info("Window \(id) sent to strip level \(plan.level)")
        switchLevel(of: key.stack, to: plan.level, focusing: id)
    }

    /// Moves a whole column (its windows, width and mode; not its pin) to `level` of the same stack, at `index`, or
    /// after that level's focused column when nil: the overview's drags between rows, and ⇧↑ ⇧↓ there. Each of the two
    /// levels is laid out where it is, the one in view on screen and any other out of sight. The level in view does not
    /// change. When the column holds the focused window and goes out of view, the keyboard does not stay with it: a
    /// window in view gets it, or Rambla takes it (`keepKeyboardInView`). Unless `handOverKeyboard` is false: the
    /// overview holds the keyboard while it is on screen, and handing it over then would close it, so it does that
    /// itself once it closes. When it comes into view with the focused window (sent away and back), the level in view
    /// focuses its column, as `moveColumn(in:from:to:)` does: the keyboard, the border, the commands and the scroll go
    /// to the same window.
    func moveColumn(id columnID: UUID, from key: StripKey, toLevel level: Int, at index: Int?,
                    handOverKeyboard: Bool = true) {
        let stack = key.stack
        guard isRunning, !isPaused, isCurrentStack(stack), level >= 0, level != key.level,
              level <= topLevel(of: stack) + 1, var source = strips[key],
              let from = source.index(ofColumn: columnID) else { return }
        var column = source.columns[from]
        column.pinned = nil
        for id in column.windows { source.remove(window: id) }
        strips[key] = source
        let targetKey = stack.level(level)
        var target = strips[targetKey] ?? Strip()
        let focusedID = target.focusedColumn?.id
        let afterFocused = focusedID.flatMap(target.index(ofColumn:)).map { $0 + 1 } ?? target.columns.count
        let slot = min(max(index ?? afterFocused, 0), target.columns.count)
        target.columns.insert(column, at: slot)
        // The level keeps its focused column; one that had none focuses what arrived.
        target.focused = focusedID.flatMap(target.index(ofColumn:)) ?? slot
        // Unless what arrived in view holds the focused window: the level focuses it, so the layout brings it into view.
        if isCurrent(targetKey), let id = focusedWindow, column.windows.contains(id) { target.focus(window: id) }
        strips[targetKey] = target
        carryHidden(column.windows, from: key, to: targetKey)
        Log.info("Column of \(column.windows.count) window(s) moved from strip level \(key.level) to \(level)")
        // The windows that leave the view jump away before the rest closes the gap; those that arrive come in as the
        // ones left behind are parked.
        layOutLevel(targetKey)
        layOutLevel(key)
        dropEmptyLevels(of: stack)
        if handOverKeyboard, let id = focusedWindow, column.windows.contains(id) { keepKeyboardInView() }
        onStateChanged?()
        scheduleSave()
    }

    /// The focused window floats in view, one the user floated or one Rambla floated after another app moved it: the
    /// level of its display steps up or down (a new one above the top, as for any window sent) and the window goes
    /// along, in view with the focus, instead of being parked with the level that leaves. That stack and level, or nil
    /// when there is none that way.
    private func floatAlongTarget(_ id: WindowID, up: Bool) -> (stack: StackKey, level: Int)? {
        guard let record = windows[id] else { return nil }
        let frame = Self.windowFrames(onScreenOnly: true)[id].flatMap { $0 == .zero ? nil : $0 } ?? record.frame
        guard let best = Displays.best(for: frame, in: displays),
              let display = enabledDisplays.first(where: { $0.uuid == best.uuid }),
              let current = currentKey(of: display),
              let level = StripLevels.target(from: current.level, up: up, top: topLevel(of: current.stack),
                                             occupied: occupiedLevels(of: current.stack)) else { return nil }
        return (current.stack, level)
    }

    // MARK: - Floating windows

    /// The level a floating window is parked with (`floatShelf`), if it is.
    func floatShelfKey(holding id: WindowID) -> StripKey? {
        floatShelf.first { $0.value[id] != nil }?.key
    }

    /// Takes `id` off the shelf it is parked on (`floatShelf`), if any, and drops a shelf left empty. Returns that
    /// level and what the shelf knew of the window.
    @discardableResult
    func takeFromFloatShelf(_ id: WindowID) -> (key: StripKey, parked: FloatShelf.Parked)? {
        guard let key = floatShelfKey(holding: id), let parked = floatShelf[key]?.removeValue(forKey: id) else {
            return nil
        }
        if floatShelf[key]?.isEmpty == true { floatShelf[key] = nil }
        return (key, parked)
    }

    /// The floating windows in view on the display of `stack`, which the level in view takes along when it leaves
    /// (`FloatShelf.leaving`), each with its frame and that display's (`FloatShelf.Parked`). Only the user's floating
    /// windows and Rambla's own (`floating`): those of app rules, dialogs and panels stay in view on every level, and
    /// so does one on every desktop. `carried`, the focused one sent along to the level that comes, stays in view too.
    /// Where each one is comes from the WindowServer now: one moved since the last reconcile may be on another display.
    func floatsInView(of stack: StackKey, except carried: WindowID?) -> [WindowID: FloatShelf.Parked] {
        guard !floating.isEmpty, let display = display(forStack: stack) else { return [:] }
        let shown = Self.windowFrames(onScreenOnly: true)
        func shownFrame(_ id: WindowID) -> CGRect? {
            shown[id].flatMap { $0 == .zero ? nil : $0 } ?? windows[id]?.frame
        }
        let parked = Set(floatShelf.values.flatMap(\.keys)).union(floatsAway.keys)
        let dragging = dragTracker.isMouseDown ? draggedFloat : nil
        let spaces = Private.spaces(for: floating.filter { shown[$0] != nil && !parked.contains($0) }.sorted())
        let candidates = floating.sorted().compactMap { id -> FloatShelf.Window? in
            guard let record = windows[id], let frame = shownFrame(id) else { return nil }
            return FloatShelf.Window(
                id: id, display: Displays.best(for: frame, in: displays)?.uuid, isOnScreen: shown[id] != nil,
                isMinimized: record.traits.isMinimized,
                appIsHidden: NSRunningApplication(processIdentifier: record.pid)?.isHidden == true,
                isDragged: id == dragging, isParked: parked.contains(id),
                isOnSeveralSpaces: (spaces[id]?.count ?? 0) > 1)
        }
        var leaving: [WindowID: FloatShelf.Parked] = [:]
        for id in FloatShelf.leaving(candidates, display: display.uuid, carried: carried) {
            if let frame = shownFrame(id) { leaving[id] = FloatShelf.Parked(frame: frame, display: display.frame) }
        }
        return leaving
    }

    /// Gives the keyboard to a floating window in view and brings it to the front. With "mouse follows focus" on, the
    /// pointer goes to it too, unless the focus came from outside Rambla (`routed`).
    func focusFloat(_ id: WindowID, routed: Bool) {
        revealSuppressedFor = nil   // no reveal follows; an older suppression must not outlive this focus
        focusedWindow = id
        worker(for: id)?.focus(id)
        if !routed, prefs.mouseFollowsFocus, let frame = windows[id]?.frame {
            CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        overlayHook?()
    }

    // MARK: - Helpers

    /// Removes the empty levels of `stack` that are no longer needed: those above every level with windows and above
    /// the one in view (`StripLevels.droppable`). Level 0 and the level in view always stay. A level with floating
    /// windows parked with it (`floatShelf`) is not empty: they come back with it.
    func dropEmptyLevels(of stack: StackKey) {
        let parked = Set(floatShelf.filter { $0.key.stack == stack && !$0.value.isEmpty }.map(\.key.level))
        for level in StripLevels.droppable(top: topLevel(of: stack), occupied: occupiedLevels(of: stack).union(parked),
                                           active: activeLevel(of: stack)) {
            dropLevel(stack.level(level))
        }
    }

    /// Lays out a level that changed where it is: the level in view on screen, its focused column kept in view, and any
    /// other out of sight.
    private func layOutLevel(_ key: StripKey) {
        if !isCurrent(key) {
            shelve(key)
        } else if strips[key]?.focusedWindow != nil {
            reveal(key)
        } else {
            apply(key, animate: true)
        }
    }
}
