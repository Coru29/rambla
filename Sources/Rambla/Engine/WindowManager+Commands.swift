import AppKit
import RamblaCore

extension WindowManager {
    /// Text commands from `rambla://` links and from the `rambla` command. What each source may run is decided by
    /// `CommandPolicy`. Returns false if the command is unknown or not allowed.
    @discardableResult
    func perform(command: String, from source: CommandPolicy.Source) -> Bool {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        guard let word = parts.first else { return false }
        guard CommandPolicy.allows(word, from: source) else {
            Log.error("Refused command from \(source == .url ? "a link" : "the command line"): \(word)")
            return false
        }
        let argument = parts.count > 1 ? parts[1] : nil
        switch word {
        case "dump":
            reply(dumpJSON(), to: argument)
        case "debug-windows":
            reply(debugWindowsJSON(), to: argument)
        case "settings":
            SettingsOpener.open()
        case "gather":
            gatherAll(synchronously: false)
        case "relayout":
            relayoutAll()
        case "debug-update":
            Task { await Updater.shared.installForTesting() }
        case "debug-external-move":
            let values = (argument ?? "").split(separator: " ").compactMap { Double($0) }
            guard values.count == 5, let id = WindowID(exactly: values[0]) else { return false }
            worker(for: id)?.debugExternalMove(id, CGRect(x: values[1], y: values[2], width: values[3], height: values[4]))
        case "debug-neighbor":
            // "x y w h" plugs a display there; no arguments unplug it.
            let values = (argument ?? "").split(separator: " ").compactMap { Double($0) }
            guard values.isEmpty || values.count == 4 else { return false }
            let frame = values.isEmpty ? nil : CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            guard setTestNeighbor(frame) else {
                Log.error("debug-neighbor works only in test mode")
                return false
            }
        default:
            guard let action = Action.parse(word) else {
                Log.error("Unknown command: \(command)")
                return false
            }
            perform(action)
        }
        return true
    }

    func perform(_ action: Action, holding modifiers: NSEvent.ModifierFlags? = nil) {
        guard isRunning, overviewAction?(action) != true else { return }
        if action == .togglePause {
            setPaused(!isPaused)
            return
        }
        guard !isPaused else { return }
        if action == .overview {
            if let key = activeStripKey() { overviewHook?(key) }
            return
        }
        if action == .toggleFloat {
            toggleFloatFocused()
            return
        }
        switch action {
        case .stripUp, .stripDown:
            // The stack of the focused window, else the one under the pointer, even before it has a strip.
            if let stack = activeStripKey()?.stack ?? stackUnderPointer() { stepLevel(up: action == .stripUp, on: stack) }
            return
        case .sendStripUp, .sendStripDown:
            sendFocusedWindow(up: action == .sendStripUp)
            return
        default:
            break
        }
        guard let key = activeStripKey(), var strip = strips[key], let display = display(for: key) else { return }
        let hiddenSet = hidden[key] ?? []
        let metrics = Layout.metrics(layoutInput(for: key, strip: strip, display: display))
        let available = metrics.area.width
        let gap = prefs.innerGap
        let before = strip.focusedWindow

        switch action {
        case .focusLeft: strip.focusColumn(.left, hidden: hiddenSet)
        case .focusRight: strip.focusColumn(.right, hidden: hiddenSet)
        case .focusUp: strip.focusRow(.up, hidden: hiddenSet)
        case .focusDown: strip.focusRow(.down, hidden: hiddenSet)
        case .focusFirst: strip.focusFirst(hidden: hiddenSet)
        case .focusLast: strip.focusLast(hidden: hiddenSet)
        case .focus1, .focus2, .focus3, .focus4, .focus5, .focus6, .focus7, .focus8, .focus9:
            strip.focusNth(Int(action.rawValue.split(separator: "-").last!)!, hidden: hiddenSet)
        case .moveLeft: strip.moveColumn(.left)
        case .moveRight: strip.moveColumn(.right)
        case .moveUp: strip.moveRow(.up)
        case .moveDown: strip.moveRow(.down)
        case .sendNextDisplay:
            sendFocusedToNextDisplay(from: key)
            return
        case .cycleWidth: strip.cycleWidth(presets: prefs.presetWidths, available: available, gap: gap)
        case .fullWidth: strip.toggleFullWidth()
        case .center:
            strips[key] = strip
            reveal(key, mode: .always)
            indicatorHook?(key, modifiers)
            return
        case .wider: strip.adjustWidth(by: prefs.nudgeStep, available: available, gap: gap)
        case .narrower: strip.adjustWidth(by: -prefs.nudgeStep, available: available, gap: gap)
        case .taller: strip.adjustHeight(by: prefs.nudgeStep, hidden: hiddenSet)
        case .shorter: strip.adjustHeight(by: -prefs.nudgeStep, hidden: hiddenSet)
        case .equalizeHeights: strip.equalizeHeights()
        case .pinLeft: strip.togglePin(.left)
        case .pinRight: strip.togglePin(.right)
        case .stackLeft: strip.stack(.left, hidden: hiddenSet)
        case .stackRight: strip.stack(.right, hidden: hiddenSet)
        case .popLeft: strip.popOut(.left)
        case .popRight: strip.popOut(.right)
        case .toggleTabbed: strip.toggleTabbed()
        case .closeWindow:
            if let id = strip.focusedWindow ?? focusedWindow { worker(for: id)?.close(id) }
            return
        case .overview, .toggleFloat, .togglePause, .stripUp, .stripDown, .sendStripUp, .sendStripDown:
            return   // handled before the strip guard
        }

        strips[key] = strip
        if let target = strip.focusedWindow, target != before || target != focusedWindow {
            focus(window: target, in: key)
        } else {
            reveal(key)
        }
        indicatorHook?(key, modifiers)
        onStateChanged?()
    }

    /// The strip commands act on: the focused window's strip, else the strip of the display under the mouse.
    func activeStripKey() -> StripKey? {
        if let id = focusedWindow, let key = key(containing: id), isCurrent(key) { return key }
        let mouse = Displays.axPoint(NSEvent.mouseLocation)
        let display = enabledDisplays.first { $0.frame.contains(mouse) } ?? enabledDisplays.first
        guard let key = display.flatMap(currentKey), strips[key] != nil else { return nil }
        return key
    }

    /// Focuses a strip window: real keyboard focus through its app, then scrolls it into view. With "mouse follows
    /// focus" on, the pointer goes to it too. `routed`: Rambla only passes on a focus that macOS or another app moved
    /// (`FocusRoute`), which behaves like any focus from outside: the pointer stays where it is, and while the mouse
    /// button is down the strip scrolls only once it is released.
    func focus(window id: WindowID, in key: StripKey, routed: Bool = false) {
        revealSuppressedFor = nil   // this focus reveals by itself; an older suppression must not outlive it
        focusedWindow = id
        strips[key]?.focus(window: id)
        worker(for: id)?.focus(id)
        if routed, dragTracker.isMouseDown {
            pendingReveal = key
        } else {
            reveal(key)
        }
        if !routed, prefs.mouseFollowsFocus, let frame = results[key]?.placements[id]?.frame {
            CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    func focusColumn(id columnID: UUID, in key: StripKey) {
        guard let index = strips[key]?.index(ofColumn: columnID),
              let window = strips[key]?.columns[index].activeWindow else { return }
        focus(window: window, in: key)
    }

    /// Moves a column (the strip indicator's or the overview's drag): the focused window keeps the focus and stays in
    /// view, where the keyboard still is.
    func moveColumn(in key: StripKey, from: Int, to: Int) {
        guard var strip = strips[key], strip.columns.indices.contains(from), strip.columns.indices.contains(to) else { return }
        strip.moveColumn(from: from, to: to)
        if let id = focusedWindow, strip.contains(id) { strip.focus(window: id) }
        strips[key] = strip
        reveal(key)
        onStateChanged?()
    }

    func focusTab(_ id: WindowID) {
        guard let key = key(containing: id) else { return }
        focus(window: id, in: key)
    }

    private func sendFocusedToNextDisplay(from key: StripKey) {
        let ordered = enabledDisplays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        guard ordered.count > 1, let id = strips[key]?.focusedWindow,
              let index = ordered.firstIndex(where: { $0.uuid == key.displayUUID }),
              let target = currentKey(of: ordered[(index + 1) % ordered.count]) else { return }
        let width = strips[key]!.location(of: id).map { strips[key]!.columns[$0.column].width } ?? .fraction(0.5)
        strips[key]!.remove(window: id)
        var other = strips[target] ?? Strip()
        other.insert(window: id, width: width, at: .afterFocused)
        strips[target] = other
        apply(key, animate: true)
        focus(window: id, in: target)
        onStateChanged?()
    }

    func toggleFloatFocused() {
        guard let id = focusedWindow else { return }
        toggleFloat(id)
    }

    func toggleFloat(_ id: WindowID) {
        if let key = key(containing: id) {
            makeFloating(id, from: key, center: true)
            return
        }
        guard floating.contains(id) || windows[id]?.kind == .float, let frame = windows[id]?.frame,
              let display = Displays.best(for: frame, in: enabledDisplays), let key = currentKey(of: display) else { return }
        floating.remove(id)
        autoFloated.remove(id)
        // One parked with a level out of view (it has the focus there for a moment) joins the level in view instead.
        takeFromFloatShelf(id)
        floatsAway[id] = nil
        var strip = strips[key] ?? Strip()
        let available = display.visible.width - 2 * prefs.outerGap
        strip.insert(window: id, width: .points(min(max(frame.width, available * 0.25), available)), at: .afterFocused)
        strips[key] = strip
        focus(window: id, in: key)
        onStateChanged?()
    }

    // MARK: - Debug replies

    /// Writes a diagnostics reply, only to the reply file the `rambla` command reads (see `CommandPolicy`).
    private func reply(_ data: Data, to requested: String?) {
        guard let requested, let path = CommandPolicy.replyPath(requested, temporaryDirectory: NSTemporaryDirectory()) else {
            Log.error("Refused to write a reply outside Rambla's reply file")
            return
        }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func rectJSON(_ r: CGRect) -> [String: Double] {
        ["x": r.minX, "y": r.minY, "w": r.width, "h": r.height]
    }

    func dumpJSON() -> Data {
        var stripList: [[String: Any]] = []
        for (key, strip) in strips {
            var placements: [String: Any] = [:]
            for (id, placement) in results[key]?.placements ?? [:] {
                switch placement {
                case .visible(let f): placements["\(id)"] = ["kind": "visible", "frame": rectJSON(f)]
                case .parked(let f): placements["\(id)"] = ["kind": "parked", "frame": rectJSON(f)]
                }
            }
            stripList.append([
                "display": key.displayUUID, "space": key.spaceID, "level": key.level,
                "current": isCurrent(key), "active": isCurrent(key),
                "scroll": strip.scroll, "focused": strip.focused as Any,
                "columns": strip.columns.map { column -> [String: Any] in
                    var width: [String: Double] = [:]
                    switch column.width {
                    case .fraction(let f): width["fraction"] = f
                    case .points(let p): width["points"] = p
                    }
                    return ["windows": column.windows, "active": column.active, "mode": column.mode.rawValue,
                            "pinned": column.pinned?.rawValue as Any, "width": width]
                },
                "hidden": Array(hidden[key] ?? []),
                "placements": placements,
            ])
        }
        // Every stack with a strip: the level in view and the highest one.
        let stacks = Set(strips.keys.map(\.stack))
            .sorted { ($0.displayUUID, $0.spaceID) < ($1.displayUUID, $1.spaceID) }
            .map { stack -> [String: Any] in
                ["display": stack.displayUUID, "space": stack.spaceID, "active": activeLevel(of: stack),
                 "top": topLevel(of: stack)]
            }
        // The floating windows parked with each level out of view.
        let floatShelfList = floatShelf.keys
            .sorted { ($0.displayUUID, $0.spaceID, $0.level) < ($1.displayUUID, $1.spaceID, $1.level) }
            .map { key -> [String: Any] in
                ["display": key.displayUUID, "space": key.spaceID, "level": key.level,
                 "windows": (floatShelf[key] ?? [:]).keys.sorted()]
            }
        let object: [String: Any] = [
            "paused": isPaused, "focused": focusedWindow as Any, "floating": Array(floating),
            "floatShelf": floatShelfList, "floatsAway": floatsAway.keys.sorted(),
            "displays": displays.map { ["uuid": $0.uuid, "frame": rectJSON($0.frame), "visible": rectJSON($0.visible),
                                        "space": $0.currentSpace as Any] },
            "stacks": stacks,
            "strips": stripList,
            "windows": windows.values.map { ["id": $0.id, "pid": $0.pid, "bundle": $0.bundleID as Any,
                                             "title": $0.title, "kind": "\($0.kind)", "frame": rectJSON($0.frame)] },
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private func debugWindowsJSON() -> Data {
        let list = windows.values.map { record -> [String: Any] in
            ["id": record.id, "pid": record.pid, "bundle": record.bundleID as Any, "title": record.title,
             "role": record.traits.role as Any, "subrole": record.traits.subrole as Any,
             "resizable": record.traits.isResizable, "closeButton": record.traits.hasCloseButton,
             "fullscreenButton": record.traits.hasFullscreenButton, "kind": "\(record.kind)",
             "autoFloated": autoFloated.contains(record.id), "frame": rectJSON(record.frame)]
        }
        return (try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}
