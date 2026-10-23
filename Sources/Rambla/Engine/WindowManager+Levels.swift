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
    /// level's) or else the level's focused window. The windows that arrive jump to their places first, behind the ones
    /// that leave, which then jump to their parking spots: nothing crosses the display and nothing in between shows. On
    /// an empty level Rambla takes the keyboard, so nothing typed reaches a window out of sight. `mouseFollows` is
    /// false when the switch follows a focus from outside Rambla (`FocusRoute`): "mouse follows focus" is for the focus
    /// Rambla gives through its own shortcuts.
    func switchLevel(of stack: StackKey, to level: Int, focusing window: WindowID? = nil, mouseFollows: Bool = true) {
        guard isRunning, !isPaused, isCurrentStack(stack), level >= 0, level <= topLevel(of: stack) + 1 else { return }
        let old = activeLevel(of: stack)
        let new = stack.level(level)
        let chosen = window.flatMap { strips[new]?.contains($0) == true ? $0 : nil }
        guard level != old else {
            if let chosen { focus(window: chosen, in: new, mouseFollows: mouseFollows) }
            return
        }
        activeLevels[stack] = level
        levelSwitchedAt[stack] = CFAbsoluteTimeGetCurrent()
        if strips[new] == nil { strips[new] = Strip() }
        apply(new, animate: false)
        shelve(stack.level(old))
        dropEmptyLevels(of: stack)
        // A strip read from an older file may have no focused column: its first one then.
        if let focused = chosen ?? strips[new]?.focusedWindow ?? strips[new]?.columns.first?.activeWindow {
            focus(window: focused, in: new, mouseFollows: mouseFollows)
        } else {
            takeKeyboardFocus()
            emptyLevelHook?(stack)
        }
        levelHook?(stack)
        onStateChanged?()
        scheduleSave()
        Log.info("Strip level \(level) of display \(stack.displayUUID.prefix(8))")
    }

    /// Goes to the level above or below the one in view of `stack`; above the top, to a new empty level when the top
    /// has windows (`StripLevels.target`). False at either end of the stack.
    @discardableResult
    func stepLevel(up: Bool, on stack: StackKey) -> Bool {
        guard isRunning, !isPaused, isCurrentStack(stack),
              let level = StripLevels.target(from: activeLevel(of: stack), up: up, top: topLevel(of: stack),
                                             occupied: occupiedLevels(of: stack)) else { return false }
        switchLevel(of: stack, to: level)
        return true
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
    /// focused column and with its width, and follows it there.
    func sendFocusedWindow(up: Bool) {
        guard isRunning, !isPaused, let key = activeStripKey(), let id = strips[key]?.focusedWindow,
              let level = StripLevels.target(from: key.level, up: up, top: topLevel(of: key.stack),
                                             occupied: occupiedLevels(of: key.stack)) else { return }
        let target = key.stack.level(level)
        let width = strips[key]!.location(of: id).map { strips[key]!.columns[$0.column].width } ?? .fraction(0.5)
        strips[key]!.remove(window: id)
        var other = strips[target] ?? Strip()
        other.insert(window: id, width: width, at: .afterFocused)
        strips[target] = other
        carryHidden([id], from: key, to: target)
        Log.info("Window \(id) sent to strip level \(level)")
        switchLevel(of: key.stack, to: level, focusing: id)
    }

    /// Moves a whole column (its windows, width and mode; not its pin) to `level` of the same stack, at `index`, or
    /// after that level's focused column when nil: the overview's drags between rows, and ⇧↑ ⇧↓ there. Each of the two
    /// levels is laid out where it is, the one in view on screen and any other out of sight. The level in view does not
    /// change, nor does the keyboard focus: that is the caller's.
    func moveColumn(id columnID: UUID, from key: StripKey, toLevel level: Int, at index: Int?) {
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
        strips[targetKey] = target
        carryHidden(column.windows, from: key, to: targetKey)
        Log.info("Column of \(column.windows.count) window(s) moved from strip level \(key.level) to \(level)")
        // The windows that leave the view jump away before the rest closes the gap; those that arrive come in as the
        // ones left behind are parked.
        layOutLevel(targetKey)
        layOutLevel(key)
        dropEmptyLevels(of: stack)
        onStateChanged?()
        scheduleSave()
    }

    // MARK: - Helpers

    /// Removes the empty levels of `stack` that are no longer needed: those above every level with windows and above
    /// the one in view (`StripLevels.droppable`). Level 0 and the level in view always stay.
    func dropEmptyLevels(of stack: StackKey) {
        for level in StripLevels.droppable(top: topLevel(of: stack), occupied: occupiedLevels(of: stack),
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
