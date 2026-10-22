import AppKit
import RamblaCore

struct StripKey: Hashable, Codable {
    let displayUUID: String
    let spaceID: UInt64
}

/// Owns the model (one strip per display and Space), turns events into model changes and applies layouts.
/// Everything here runs on the main thread; AX calls go through one AppWorker per app.
@MainActor
final class WindowManager {
    static let shared = WindowManager()
    static let ownBundleID = "io.github.coru29.Rambla"

    struct WindowRecord {
        let id: WindowID
        let pid: pid_t
        let bundleID: String?
        var traits: WindowTraits
        /// Last known real frame (AX coordinates).
        var frame: CGRect
        var title: String
        var kind: WindowKind
        var originalHeight: Double
        /// Learned from apps that refuse smaller frames.
        var minSize: CGSize?
        /// Created while Rambla was running: goes next to the focused column instead of in x order.
        var isFresh: Bool
    }

    private(set) var prefs = Preferences()
    private(set) var isRunning = false
    private(set) var isPaused = false
    private var onlyBundles: Set<String>?

    private var workers: [pid_t: AppWorker] = [:]
    private var appLaunchTimes: [pid_t: CFAbsoluteTime] = [:]
    private var frontmostPID: pid_t?
    private(set) var windows: [WindowID: WindowRecord] = [:]
    var floating: Set<WindowID> = []
    var strips: [StripKey: Strip] = [:]
    private(set) var displays: [DisplayInfo] = []
    /// Strip → Space UUID, so state can be matched to Spaces after a restart.
    private(set) var spaceKeys: [StripKey: String] = [:]
    private(set) var hidden: [StripKey: Set<WindowID>] = [:]
    private(set) var results: [StripKey: LayoutResult] = [:]
    var focusedWindow: WindowID?
    /// Last frame Rambla asked for, per window (the final target, not animation frames).
    private(set) var requested: [WindowID: CGRect] = [:]
    private var hiddenSince: [WindowID: CFAbsoluteTime] = [:]
    private var graceUntil: CFAbsoluteTime = 0
    private var reconcileScheduled = false
    var pendingReveal: StripKey?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private(set) lazy var animator = Animator { [weak self] frames, verify in
        self?.write(frames, verify: verify)
    }
    let dragTracker = DragTracker()

    /// Called after every layout application and animation frame (overlays).
    var overlayHook: (() -> Void)?
    /// Called after model changes (menu, settings, persistence).
    var onStateChanged: (() -> Void)?
    /// Called when a command or gesture should flash the strip indicator.
    var indicatorHook: ((StripKey, NSEvent.ModifierFlags?) -> Void)?
    /// Saved layout from the previous run; strips are rebuilt from it the first time each one is seen.
    var restoreState: SavedState?
    var restoredKeys: Set<StripKey> = []
    /// Saved ids of the floating windows not matched yet; each one floats a single live window.
    var pendingFloating: Set<WindowID> = []
    /// When Rambla started: saved windows are matched by title only for `restoreByTitleWindow` seconds after it.
    var launchTime: CFAbsoluteTime = 0
    static let restoreByTitleWindow: CFAbsoluteTime = 15
    /// Floating windows that Rambla floated by itself because another app moved them (Rectangle, a snap after a
    /// drag). Unlike the ones the user floats, they are not saved, and "Reacomodar ventanas" puts them back.
    var autoFloated: Set<WindowID> = []
    var saveWorkItem: DispatchWorkItem?
    /// Strip being moved by a trackpad swipe.
    var gestureKey: StripKey?
    /// Focus given by hover or swipe: do not scroll when macOS confirms it.
    var revealSuppressedFor: WindowID?

    // MARK: - Lifecycle

    func start(prefs: Preferences, onlyBundles: Set<String>?) {
        guard !isRunning else { return }
        self.prefs = prefs
        self.onlyBundles = onlyBundles
        isRunning = true
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        animator.onTick = { [weak self] _ in self?.overlayHook?() }
        dragTracker.onMouseUp = { [weak self] point in self?.mouseUp(at: point) }
        dragTracker.setEnabled(true)
        displays = Displays.current()
        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        restoreState = StateStore.load()
        pendingFloating = Set(restoreState?.floating ?? [])
        launchTime = CFAbsoluteTimeGetCurrent()
        observeSystem()
        NSWorkspace.shared.runningApplications.forEach(register)
        if let only = onlyBundles { Log.info("Test mode: managing only \(only.sorted().joined(separator: ", "))") }
        // Give every app's worker a moment to report its windows so the saved layout restores in one go.
        scheduleReconcile(after: 0.6)
    }

    /// Stops managing windows and puts every parked window back on screen (quit, crash signals).
    func stop() {
        guard isRunning else { return }
        animator.cancelAll()
        gatherAll(synchronously: true)
        isRunning = false
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        workers.values.forEach { $0.stop() }
        workers.removeAll()
        dragTracker.setEnabled(false)
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused, isRunning else { return }
        if paused {
            animator.cancelAll()
            gatherAll(synchronously: false)
            isPaused = true
            Log.info("Paused")
        } else {
            isPaused = false
            Log.info("Resumed")
            workers.values.forEach { $0.rescan() }
            scheduleReconcile()
        }
        onStateChanged?()
    }

    func update(prefs newPrefs: Preferences) {
        let old = prefs
        prefs = newPrefs
        guard isRunning else { return }
        if old.appRules != newPrefs.appRules {
            for (id, record) in windows { windows[id]?.kind = classify(record.traits) }
        }
        if old.disabledDisplays != newPrefs.disabledDisplays {
            gatherAll(synchronously: false)
        }
        scheduleReconcile()
    }

    // MARK: - System observation

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.didLaunchApplicationNotification) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            appLaunchTimes[app.processIdentifier] = CFAbsoluteTimeGetCurrent()
            register(app)
        }
        observe(ws, NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.unregister(app.processIdentifier)
            }
        }
        observe(ws, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            frontmostPID = app.processIdentifier
            // Some apps only become "regular" (Dock icon) after launching.
            if workers[app.processIdentifier] == nil { register(app) }
            if let worker = workers[app.processIdentifier] {
                worker.refreshFocused()
            } else {
                focusChanged(nil)
            }
        }
        observe(ws, NSWorkspace.didHideApplicationNotification) { [weak self] _ in self?.scheduleReconcile() }
        observe(ws, NSWorkspace.didUnhideApplicationNotification) { [weak self] _ in self?.scheduleReconcile() }
        observe(ws, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in
            guard let self else { return }
            // The focused window belongs to the Space we left: drop it so the border and dimming hide
            // until the new Space reports its own focus.
            focusedWindow = nil
            overlayHook?()
            frontmostPID.flatMap { self.workers[$0] }?.refreshFocused()
            grace(1.0)
            workers.values.forEach { $0.rescan() }
            scheduleReconcile(after: 0.15)
        }
        observe(ws, NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.grace(2.5)
            self?.scheduleReconcile(after: 0.8)
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.grace(2.5)
            self?.scheduleReconcile(after: 0.4)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { block(note) }
        }
        observers.append((center, token))
    }

    private func grace(_ seconds: CFAbsoluteTime) {
        graceUntil = max(graceUntil, CFAbsoluteTimeGetCurrent() + seconds)
    }

    private var inGrace: Bool { CFAbsoluteTimeGetCurrent() < graceUntil }

    // MARK: - Apps

    private func shouldManage(_ app: NSRunningApplication) -> Bool {
        guard app.processIdentifier != getpid(), app.activationPolicy == .regular,
              app.bundleIdentifier != Self.ownBundleID else { return false }
        if let only = onlyBundles { return app.bundleIdentifier.map(only.contains) ?? false }
        return true
    }

    private func register(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard workers[pid] == nil, shouldManage(app) else { return }
        let worker = AppWorker(pid: pid, bundleID: app.bundleIdentifier, isRegular: true) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        workers[pid] = worker
        worker.start()
    }

    private func unregister(_ pid: pid_t) {
        appLaunchTimes[pid] = nil
        guard let worker = workers.removeValue(forKey: pid) else { return }
        worker.stop()
        for (id, record) in windows where record.pid == pid { removeWindow(id) }
        scheduleReconcile()
    }

    func worker(for id: WindowID) -> AppWorker? {
        windows[id].flatMap { workers[$0.pid] }
    }

    // MARK: - AX events

    private func handle(_ event: AXEvent) {
        guard isRunning else { return }
        switch event {
        case .appWindows(let pid, let snapshots):
            // An app launched while Rambla runs often shows its first window before its observer exists:
            // those windows are new too, so they open next to the focused column.
            let launchedRecently = appLaunchTimes[pid].map { CFAbsoluteTimeGetCurrent() - $0 < 10 } ?? false
            snapshots.forEach { upsert($0, fresh: launchedRecently && windows[$0.id] == nil) }
            scheduleReconcile()
        case .windowCreated(let snapshot):
            upsert(snapshot, fresh: windows[snapshot.id] == nil)
            scheduleReconcile()
        case .windowDestroyed(_, let id):
            removeWindow(id)
            scheduleReconcile()
        case .frameChanged(_, let id, let frame, let mouseDown):
            externalFrameChange(id, frame, mouseDown: mouseDown)
        case .minimized(_, let id, let isMinimized):
            windows[id]?.traits.isMinimized = isMinimized
            scheduleReconcile()
        case .titleChanged(_, let id, let title):
            windows[id]?.title = title
            // Only tab bars show titles; skip the overlay refresh otherwise (terminals retitle constantly).
            if let key = key(containing: id), let location = strips[key]?.location(of: id),
               strips[key]?.columns[location.column].mode == .tabbed {
                overlayHook?()
            }
        case .focusedWindow(let pid, let id):
            if pid == frontmostPID { focusChanged(id) }
        case .applied(_, let id, let frame):
            learn(id, actual: frame)
        }
    }

    private func classify(_ traits: WindowTraits) -> WindowKind {
        Classifier.classify(traits, rules: prefs.appRules, ownBundleID: Self.ownBundleID)
    }

    private func upsert(_ snapshot: WindowSnapshot, fresh: Bool) {
        let kind = classify(snapshot.traits)
        if var record = windows[snapshot.id] {
            record.traits = snapshot.traits
            record.title = snapshot.title
            record.kind = kind
            if requested[snapshot.id] == nil { record.frame = snapshot.frame }
            windows[snapshot.id] = record
        } else {
            windows[snapshot.id] = WindowRecord(
                id: snapshot.id, pid: snapshot.pid, bundleID: snapshot.traits.bundleID, traits: snapshot.traits,
                frame: snapshot.frame, title: snapshot.title, kind: kind,
                originalHeight: snapshot.frame.height, minSize: nil, isFresh: fresh)
        }
    }

    func removeWindow(_ id: WindowID) {
        guard windows.removeValue(forKey: id) != nil || floating.contains(id) else { return }
        floating.remove(id)
        autoFloated.remove(id)
        requested[id] = nil
        hiddenSince[id] = nil
        animator.cancel(id)
        for key in strips.keys where strips[key]!.contains(id) {
            strips[key]!.remove(window: id)
        }
        if focusedWindow == id { focusedWindow = nil }
    }

    /// An app refused the requested frame: remember its minimum size and lay out again (converges in one pass).
    private func learn(_ id: WindowID, actual: CGRect) {
        guard var record = windows[id], let wanted = requested[id] else { return }
        record.frame = actual
        var minSize = record.minSize ?? .zero
        var grew = false
        if actual.width > wanted.width + 2, actual.width > minSize.width { minSize.width = actual.width; grew = true }
        if actual.height > wanted.height + 2, actual.height > minSize.height { minSize.height = actual.height; grew = true }
        record.minSize = minSize
        windows[id] = record
        if grew, let key = key(containing: id) {
            Log.info("Window \(id) (\(record.bundleID ?? "?")) needs at least \(Int(minSize.width))×\(Int(minSize.height))")
            apply(key, animate: false)
        }
    }

    // MARK: - Focus

    func focusChanged(_ id: WindowID?) {
        focusedWindow = id
        if let id, key(containing: id) == nil, floating.contains(id) || windows[id]?.kind == .float {
            // A floating window can end up under the strip (a swipe focuses the column it lands on). When its app
            // comes to the front (Dock, ⌘Tab, a click), it must be on top, not behind the strip's windows.
            worker(for: id)?.raise(id)
        }
        guard let id, let key = key(containing: id), isCurrent(key) else {
            overlayHook?()
            return
        }
        strips[key]!.focus(window: id)
        if revealSuppressedFor == id {
            revealSuppressedFor = nil
            apply(key, animate: true)
        } else if dragTracker.isMouseDown {
            pendingReveal = key
        } else {
            reveal(key)
        }
        onStateChanged?()
    }

    /// Scrolls the strip so its focused column is visible (per the centering mode) and applies the layout.
    func reveal(_ key: StripKey, animate: Bool = true, mode: CenterMode? = nil) {
        guard var strip = strips[key], let focused = strip.focused, strip.columns.indices.contains(focused),
              let display = display(for: key) else { return }
        let metrics = Layout.metrics(layoutInput(for: key, strip: strip, display: display))
        if strip.columns[focused].pinned == nil {
            strip.scroll = Layout.reveal(metrics, column: focused, current: strip.scroll, mode: mode ?? prefs.centerMode)
        } else {
            // A pinned column is always visible; just keep the rest of the strip within range.
            strip.scroll = min(max(strip.scroll, 0), max(0, metrics.total - metrics.area.width))
        }
        strips[key] = strip
        apply(key, animate: animate)
    }

    // MARK: - Reconcile

    func scheduleReconcile(after delay: TimeInterval = 0.05) {
        guard !reconcileScheduled else { return }
        reconcileScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.reconcile() }
        }
    }

    private static func windowIDs(onScreenOnly: Bool) -> Set<WindowID> {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return Set(list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
    }

    var enabledDisplays: [DisplayInfo] {
        displays.filter { !prefs.disabledDisplays.contains($0.uuid) && $0.currentSpace != nil && !$0.isFullscreenSpace }
    }

    func currentKey(of display: DisplayInfo) -> StripKey? {
        display.currentSpace.map { StripKey(displayUUID: display.uuid, spaceID: $0) }
    }

    var currentKeys: [StripKey] { enabledDisplays.compactMap(currentKey) }

    func isCurrent(_ key: StripKey) -> Bool { currentKeys.contains(key) }

    func display(for key: StripKey) -> DisplayInfo? {
        displays.first { $0.uuid == key.displayUUID && $0.currentSpace == key.spaceID }
    }

    func key(containing id: WindowID) -> StripKey? {
        strips.first { $0.value.contains(id) }?.key
    }

    private func stripKey(forSpace space: UInt64) -> StripKey? {
        for entry in Private.displaySpaces() where entry.uuids[space] != nil {
            let uuid = entry.displayUUID == "Main" ? (displays.first?.uuid ?? entry.displayUUID) : entry.displayUUID
            guard let display = displays.first(where: { $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame }),
                  !prefs.disabledDisplays.contains(display.uuid), !entry.fullscreen.contains(space) else { return nil }
            return StripKey(displayUUID: display.uuid, spaceID: space)
        }
        return nil
    }

    private func reconcile() {
        reconcileScheduled = false
        guard isRunning, !isPaused else { return }
        displays = Displays.current()
        let existing = Self.windowIDs(onScreenOnly: false)
        let visible = Self.windowIDs(onScreenOnly: true)
        let now = CFAbsoluteTimeGetCurrent()

        for id in Array(windows.keys) where !existing.contains(id) {
            worker(for: id)?.forgetWindow(id)
            removeWindow(id)
        }

        let keys = currentKeys
        for display in enabledDisplays {
            guard let key = currentKey(of: display) else { continue }
            spaceKeys[key] = display.currentSpaceKey
            if strips[key] == nil { strips[key] = Strip() }
        }

        // Windows of a visible strip that are not on screen are either hidden on this Space
        // (minimized, app hidden, inactive native tab, full screen) or were moved to another Space.
        let notVisible = keys.flatMap { strips[$0]!.allWindows.filter { !visible.contains($0) } }
        let spacesOf = Private.spaces(for: notVisible)
        var hiddenNow: [StripKey: Set<WindowID>] = [:]
        for key in keys {
            for id in strips[key]!.allWindows where !visible.contains(id) {
                let spaces = spacesOf[id] ?? []
                if !spaces.isEmpty, !spaces.contains(key.spaceID),
                   let target = spaces.lazy.compactMap({ self.stripKey(forSpace: $0) }).first, target != key {
                    let width = strips[key]!.location(of: id).map { strips[key]!.columns[$0.column].width } ?? .fraction(0.5)
                    strips[key]!.remove(window: id)
                    var other = strips[target] ?? Strip()
                    other.insert(window: id, width: width, at: .end)
                    strips[target] = other
                    Log.info("Window \(id) moved to another Space")
                } else {
                    hiddenNow[key, default: []].insert(id)
                    if hiddenSince[id] == nil { hiddenSince[id] = now }
                }
            }
        }
        for id in visible { hiddenSince[id] = nil }
        hidden = hiddenNow

        // Windows that stopped being tileable (rules changed) leave their strips.
        for key in Array(strips.keys) {
            for id in strips[key]!.allWindows where windows[id] != nil && windows[id]!.kind != .tile {
                strips[key]!.remove(window: id)
            }
        }

        // Visible tileable windows that belong to no strip yet.
        var managed = Set(strips.values.flatMap(\.allWindows))
        let candidates = windows.values
            .filter { $0.kind != .ignore && visible.contains($0.id) && !managed.contains($0.id) && !floating.contains($0.id) }
        restoreFromSavedState(keys: keys, candidates: candidates)
        managed = Set(strips.values.flatMap(\.allWindows))
        let orphans = windows.values
            .filter { $0.kind == .tile && visible.contains($0.id) && !managed.contains($0.id) && !floating.contains($0.id) }
            .sorted { $0.frame.minX < $1.frame.minX }
        var revealKeys: Set<StripKey> = []
        for record in orphans {
            // A window on a disabled display stays untouched: look it up among all displays.
            guard let display = Displays.best(for: record.frame, in: displays),
                  let key = currentKey(of: display), keys.contains(key) else { continue }
            insert(record, into: key)
            if record.isFresh { revealKeys.insert(key) }
        }

        if let focused = focusedWindow, let key = key(containing: focused), !revealKeys.contains(key) {
            strips[key]!.focus(window: focused)
        }
        for key in keys {
            if revealKeys.contains(key) { reveal(key) } else { apply(key, animate: true) }
        }
        onStateChanged?()
    }

    private func insert(_ record: WindowRecord, into key: StripKey) {
        var strip = strips[key] ?? Strip()
        let rule = prefs.rule(for: record.bundleID)
        if record.isFresh, let column = nativeTabColumn(for: record, in: strip) {
            strip.columns[column].windows.append(record.id)
            strip.columns[column].heightWeights.append(1)
            strip.columns[column].active = strip.columns[column].windows.count - 1
            strip.focused = column
        } else {
            let previousFocus = strip.focusedWindow
            strip.insert(window: record.id, width: initialWidth(record, rule: rule, key: key),
                         at: record.isFresh ? (rule?.openAt ?? .afterFocused) : .end)
            if !record.isFresh, let previousFocus { strip.focus(window: previousFocus) }
        }
        strips[key] = strip
        windows[record.id]?.isFresh = false
    }

    /// macOS native tabs are separate windows: a new window of the same app that appears where a
    /// window of that app just disappeared is its tab, so it shares that column.
    private func nativeTabColumn(for record: WindowRecord, in strip: Strip) -> Int? {
        let now = CFAbsoluteTimeGetCurrent()
        for (index, column) in strip.columns.enumerated() {
            for id in column.windows {
                guard let since = hiddenSince[id], now - since < 1.0, windows[id]?.pid == record.pid,
                      let frame = requested[id] ?? windows[id]?.frame,
                      frame.approximatelyEquals(record.frame, tolerance: 2) else { continue }
                return index
            }
        }
        return nil
    }

    private func initialWidth(_ record: WindowRecord, rule: AppRule?, key: StripKey) -> ColumnWidth {
        if let fraction = rule?.width { return .fraction(fraction) }
        switch prefs.newWindowWidth {
        case .fraction(let fraction):
            return .fraction(fraction)
        case .natural:
            guard let display = display(for: key) else { return .fraction(0.5) }
            let available = display.visible.width - 2 * prefs.outerGap
            return .points(min(max(record.frame.width, available * 0.25), available))
        }
    }

    // MARK: - Layout application

    func layoutInput(for key: StripKey, strip: Strip, display: DisplayInfo) -> LayoutInput {
        let viewport = display.visible.insetBy(dx: prefs.outerGap, dy: prefs.outerGap)
        var minSizes: [WindowID: CGSize] = [:]
        var originalHeights: [WindowID: Double] = [:]
        for id in strip.allWindows {
            if let size = windows[id]?.minSize { minSizes[id] = size }
            if let height = windows[id]?.originalHeight { originalHeights[id] = height }
        }
        return LayoutInput(
            strip: strip, viewport: viewport, display: display.frame,
            otherDisplays: displays.filter { $0.uuid != display.uuid }.map(\.frame),
            hidden: hidden[key] ?? [], minSizes: minSizes, originalHeights: originalHeights,
            config: LayoutConfig(gap: prefs.innerGap, tabBarHeight: 28, centerMode: prefs.centerMode,
                                 keepOriginalHeight: prefs.keepOriginalHeight, sliver: 1))
    }

    func apply(_ key: StripKey, animate: Bool, verify: Bool = true) {
        guard isRunning, !isPaused, let strip = strips[key], let display = display(for: key),
              !prefs.disabledDisplays.contains(key.displayUUID) else { return }
        let result = Layout.compute(layoutInput(for: key, strip: strip, display: display))
        results[key] = result
        var targets: [WindowID: CGRect] = [:]
        for (id, placement) in result.placements where !dragTracker.isFrozen(id) {
            targets[id] = placement.frame.integral(keepingSize: true)
        }
        let changed = targets.filter { id, frame in
            !(requested[id]?.approximatelyEquals(frame, tolerance: 0.5) ?? false)
                || !(windows[id]?.frame.approximatelyEquals(frame, tolerance: 2) ?? false)
        }
        for (id, frame) in targets { requested[id] = frame }
        guard !changed.isEmpty else {
            overlayHook?()
            return
        }
        if animate && prefs.animations {
            animator.speed = prefs.animationSpeed
            var from: [WindowID: CGRect] = [:]
            for id in changed.keys { from[id] = animator.current[id] ?? windows[id]?.frame }
            animator.animate(to: changed, from: from)
        } else {
            changed.keys.forEach(animator.cancel)
            write(changed, verify: verify)
        }
        overlayHook?()
        scheduleSave()
    }

    func applyAll(animate: Bool) {
        currentKeys.forEach { apply($0, animate: animate) }
    }

    /// Sends frames to each app's worker. Also records them as the windows' known frames.
    func write(_ frames: [WindowID: CGRect], verify: Bool) {
        var byPID: [pid_t: [WindowID: CGRect]] = [:]
        for (id, frame) in frames {
            guard let pid = windows[id]?.pid else { continue }
            byPID[pid, default: [:]][id] = frame
            windows[id]?.frame = frame
        }
        for (pid, group) in byPID { workers[pid]?.setFrames(group, verify: verify) }
    }

    /// "Reacomodar ventanas": reads every window again and puts back in the strip the ones Rambla floated by itself.
    func relayoutAll() {
        guard isRunning, !isPaused else { return }
        floating.subtract(autoFloated)
        autoFloated.removeAll()
        requested.removeAll()
        workers.values.forEach { $0.rescan() }
        scheduleReconcile()
    }

    /// Moves every window that is parked or sticking out of its display back into the visible area.
    func gatherAll(synchronously: Bool) {
        animator.cancelAll()
        for (key, strip) in strips {
            guard let display = displays.first(where: { $0.uuid == key.displayUUID }) else { continue }
            let area = display.visible
            for id in strip.allWindows {
                guard let frame = requested[id] ?? windows[id]?.frame, let pid = windows[id]?.pid else { continue }
                guard !area.insetBy(dx: -1, dy: -1).contains(frame) else { continue }
                var target = frame
                let visibleWidth = frame.intersection(area).isNull ? 0 : frame.intersection(area).width
                if visibleWidth < frame.width / 2 { target.origin.x = area.midX - frame.width / 2 }
                target.origin.x = min(max(target.minX, area.minX), max(area.minX, area.maxX - target.width))
                target.origin.y = min(max(target.minY, area.minY), max(area.minY, area.maxY - target.height))
                if synchronously {
                    workers[pid]?.setFrameSynchronously(id, target)
                } else {
                    write([id: target], verify: true)
                }
                requested[id] = nil
            }
        }
        results.removeAll()
        overlayHook?()
    }

    // MARK: - External changes (Rectangle, the app itself, the user's mouse)

    /// "x,y w×h", for the log.
    static func describe(_ r: CGRect) -> String {
        "\(Int(r.minX.rounded())),\(Int(r.minY.rounded())) \(Int(r.width.rounded()))×\(Int(r.height.rounded()))"
    }

    private func externalFrameChange(_ id: WindowID, _ frame: CGRect, mouseDown: Bool) {
        let previous = windows[id]?.frame
        windows[id]?.frame = frame
        guard !isPaused, let key = key(containing: id) else { return }
        if mouseDown {
            dragTracker.began(id, startFrame: requested[id] ?? previous ?? frame)
            worker(for: id)?.freeze(id, true)
            animator.cancel(id)
            return
        }
        guard !inGrace, !dragTracker.isFrozen(id) else { return }
        let reference = requested[id] ?? previous ?? frame
        if FrameChange.isAnchoredResize(from: reference, to: frame) {
            // The app resized itself (terminals snap to their character grid keeping a corner fixed).
            adoptSize(id, frame: frame, in: key)
        } else if prefs.floatOnExternalMove {
            Log.info("Window \(id) (\(windows[id]?.bundleID ?? "?")) moved by another app from \(Self.describe(reference)) "
                     + "to \(Self.describe(frame)): floating it")
            makeFloating(id, from: key, center: false, automatic: true)
        } else {
            apply(key, animate: true)
        }
    }

    func adoptSize(_ id: WindowID, frame: CGRect, in key: StripKey) {
        guard var strip = strips[key], let location = strip.location(of: id) else { return }
        let column = strip.columns[location.column]
        if let wanted = requested[id], abs(wanted.width - frame.width) > 2 {
            strip.setWidth(points: frame.width, window: id)
        }
        let visibleRows = column.windows.filter { !(hidden[key]?.contains($0) ?? false) }
        if visibleRows.count > 1, let display = display(for: key), let wanted = requested[id], abs(wanted.height - frame.height) > 2 {
            let available = display.visible.height - 2 * prefs.outerGap - prefs.innerGap * Double(visibleRows.count - 1)
            strip.setHeightShare(window: id, share: frame.height / available, hidden: hidden[key] ?? [])
        }
        strips[key] = strip
        requested[id] = nil
        apply(key, animate: true)
    }

    func markFloating(_ id: WindowID) {
        if let key = key(containing: id) { strips[key]?.remove(window: id) }
        floating.insert(id)
        requested[id] = nil
    }

    /// Takes a window out of its strip. `automatic` when Rambla decides it (another app moved the window),
    /// rather than the user.
    func makeFloating(_ id: WindowID, from key: StripKey, center: Bool, automatic: Bool = false) {
        strips[key]?.remove(window: id)
        floating.insert(id)
        if automatic { autoFloated.insert(id) } else { autoFloated.remove(id) }
        requested[id] = nil
        animator.cancel(id)
        if center, let display = display(for: key), let frame = windows[id]?.frame {
            let area = display.visible
            let size = CGSize(width: min(frame.width, area.width * 0.8), height: min(frame.height, area.height * 0.8))
            let target = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                width: size.width, height: size.height).integral(keepingSize: true)
            write([id: target], verify: true)
            worker(for: id)?.raise(id)
        }
        apply(key, animate: true)
        onStateChanged?()
    }

    // MARK: - Mouse drags

    private func mouseUp(at point: CGPoint) {
        if let key = pendingReveal {
            pendingReveal = nil
            reveal(key)
        }
        guard let drag = dragTracker.takeDrag() else { return }
        let atRelease = windows[drag.window]?.frame
        // Wait for snapping tools (Rectangle's snap areas) to act before deciding what the drag meant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let worker = self.worker(for: drag.window) else { return }
                worker.readFrame(drag.window) { frame in
                    MainActor.assumeIsolated {
                        worker.freeze(drag.window, false)
                        guard let frame else { return }
                        self.finishDrag(drag, frame: frame, frameAtRelease: atRelease ?? frame, mouse: point)
                    }
                }
            }
        }
    }

    private func finishDrag(_ drag: DragTracker.Drag, frame: CGRect, frameAtRelease: CGRect, mouse: CGPoint) {
        let id = drag.window
        windows[id]?.frame = frame
        guard let key = key(containing: id) else { return }
        if !frame.approximatelyEquals(frameAtRelease, tolerance: 2) {
            Log.info("Window \(id) (\(windows[id]?.bundleID ?? "?")) snapped by another app after a drag "
                     + "to \(Self.describe(frame)): floating it")
            makeFloating(id, from: key, center: false, automatic: true)
            return
        }
        if !frame.size.approximatelyEquals(drag.startFrame.size, tolerance: 2) {
            requested[id] = drag.startFrame
            adoptSize(id, frame: frame, in: key)
            return
        }
        drop(id, from: key, at: mouse)
    }

    /// Reorders by dropping a dragged window on another column (or another display's strip).
    private func drop(_ id: WindowID, from key: StripKey, at point: CGPoint) {
        let targetKey = displays.first { $0.frame.contains(point) }.flatMap(currentKey) ?? key
        if targetKey != key, isCurrent(targetKey), strips[targetKey] != nil {
            let width = strips[key]!.location(of: id).map { strips[key]!.columns[$0.column].width } ?? .fraction(0.5)
            strips[key]!.remove(window: id)
            strips[targetKey]!.insert(window: id, width: width, at: .afterFocused)
            requested[id] = nil
            apply(key, animate: true)
            reveal(targetKey)
            return
        }
        guard var strip = strips[key], let column = strip.location(of: id)?.column, let metrics = results[key]?.metrics,
              let to = Layout.dropIndex(metrics, stripX: point.x - metrics.area.minX + strip.scroll, dragging: column) else {
            requested[id] = nil
            apply(key, animate: true)
            return
        }
        if strip.columns[column].windows.count == 1 {
            strip.moveColumn(from: column, to: to)
        } else {
            // Only the dragged window leaves its stack; its old column stays, so shift the slot past it.
            let width = strip.columns[column].width
            strip.remove(window: id)
            let position = min(to >= column ? to + 1 : to, strip.columns.count)
            strip.columns.insert(Column(windows: [id], width: width), at: position)
        }
        strip.focus(window: id)
        strips[key] = strip
        requested[id] = nil
        reveal(key)
    }
}

extension CGRect {
    /// Whole-point origin; size rounded so apps that snap to integers agree with the request.
    func integral(keepingSize: Bool) -> CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }
}
