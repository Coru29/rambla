import AppKit
import IOKit
import RamblaCore

/// A display and Space: the stack of strips it holds, levels 0, 1, 2… from the bottom, one of them in view
/// (`WindowManager.activeLevels`).
struct StackKey: Hashable {
    let displayUUID: String
    let spaceID: UInt64

    /// The strip at `level` of this stack.
    func level(_ level: Int) -> StripKey { StripKey(displayUUID: displayUUID, spaceID: spaceID, level: level) }
}

/// One strip: its display and Space, and its level in their stack (0 is the strip there has always been).
struct StripKey: Hashable, Codable {
    let displayUUID: String
    let spaceID: UInt64
    var level: Int = 0

    var stack: StackKey { StackKey(displayUUID: displayUUID, spaceID: spaceID) }
}

/// macOS is about to change the displays, or just did (one plugged or unplugged, a lid opened or closed).
private let displaysReconfigured: CGDisplayReconfigurationCallBack = { _, _, userInfo in
    guard let userInfo else { return }
    let manager = Unmanaged<WindowManager>.fromOpaque(userInfo).takeUnretainedValue()
    if Thread.isMainThread {
        MainActor.assumeIsolated { manager.displaysReconfiguring() }
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated { manager.displaysReconfiguring() } }
    }
}

/// Owns the model (a stack of strips per display and Space, one in view), turns events into model changes and applies
/// layouts.
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
    /// Test mode (`--only-bundle`): only these apps' windows are managed, and the user's saved layout is neither read
    /// nor written; a file of the tests' own is, when they name one (`--state-file`, `StateStore.testFile`).
    private(set) var onlyBundles: Set<String>?
    /// Test mode only (`rambla debug-neighbor`): a display that is not there, beside which the strips lay out and park.
    private var testNeighbor: CGRect?

    private var workers: [pid_t: AppWorker] = [:]
    private var appLaunchTimes: [pid_t: CFAbsoluteTime] = [:]
    private var frontmostPID: pid_t?
    private(set) var windows: [WindowID: WindowRecord] = [:]
    var floating: Set<WindowID> = []
    /// Every strip, of every level: the levels out of view are parked out of sight (`shelve`).
    var strips: [StripKey: Strip] = [:]
    /// The level in view of each stack; a stack missing here shows level 0.
    var activeLevels: [StackKey: Int] = [:]
    private(set) var displays: [DisplayInfo] = []
    /// Stack → Space UUID, so state can be matched to Spaces after a restart.
    private(set) var spaceKeys: [StackKey: String] = [:]
    private(set) var hidden: [StripKey: Set<WindowID>] = [:]
    private(set) var results: [StripKey: LayoutResult] = [:]
    var focusedWindow: WindowID?
    /// Last frame Rambla asked for, per window (the final target, not animation frames).
    private(set) var requested: [WindowID: CGRect] = [:]
    /// Where the WindowServer showed each on-screen window at the last reconcile (`whereShown`).
    private var onScreenFrames: [WindowID: CGRect] = [:]
    private var hiddenSince: [WindowID: CFAbsoluteTime] = [:]
    /// Windows macOS is putting back (back from the Dock, their app unhidden), and until when: macOS moves them by
    /// itself then (a parked one back on screen, a minimized one to where it was), which is not another app's move.
    private var reappearing: [WindowID: CFAbsoluteTime] = [:]
    private static let reappearDelay: CFAbsoluteTime = 1.5
    /// Displays that have strips but are not connected, and since when (a resolution change, a dock or a wake can drop
    /// a display for a while). In uptime, which does not count time asleep, and waking starts the count again.
    private var displayGoneSince: [String: TimeInterval] = [:]
    /// Some monitors leave the list of displays while the screens sleep: they are asleep, not gone.
    private var screensAsleep = false
    /// How long a display must stay disconnected before its windows join the strips where they are now: long enough
    /// for a dock or a monitor that is slow to come back after a wake.
    private static let goneDisplayDelay: TimeInterval = 15
    /// The Mac's own screen with the lid closed is gone until the lid opens: its windows, which macOS has moved to the
    /// monitor, join the strips there at once instead of sitting on top of them.
    private static let closedLidDelay: TimeInterval = 2
    /// Displays seen as the Mac's own screen.
    private var builtinDisplays: Set<String> = []
    /// The reconcile that checks again once a display's time is up (gone long enough, or done coming back), and when.
    /// Separate from `scheduleReconcile`, which would otherwise hold every other reconcile until then.
    private var displayCheck: DispatchWorkItem?
    private var displayCheckAt: CFAbsoluteTime = 0
    /// How long a display that appears (plugged in again, or there when Rambla starts) may take back the windows of its
    /// strips archived when it was unplugged.
    static let returnWindow: CFAbsoluteTime = 10
    /// Displays that appeared, and until when they may take their windows back.
    private(set) var returningDisplays: [String: CFAbsoluteTime] = [:]
    /// When each display appeared: one that has not stayed a moment takes and gets no windows.
    private(set) var presence = DisplayPresence()
    /// Windows that macOS put back on a display that has just returned, which takes them back once it settles: left
    /// there meanwhile, instead of pulled into the strips they joined while it was away and then flown back.
    private var heldForReturn: Set<WindowID> = []
    /// Windows that, as orphans, joined the level they had on a display that was unplugged, and that display. A window
    /// goes back to its level that way only the first time it is an orphan after its display left: it may be moved
    /// after that, and an orphan again later (put back by "Reacomodar ventanas", its desktop removed, a rule changed)
    /// it joins the level in view instead of jumping back. Forgotten once that display's strips are taken back or
    /// settled, so its windows find their levels again the next time it leaves.
    private var placedAtUnpluggedLevel: [WindowID: String] = [:]
    private var graceUntil: CFAbsoluteTime = 0
    private var reconcileScheduled = false
    var pendingReveal: StripKey?
    /// A window of a level out of view that got the focus while the mouse button was down (a click on its sliver): its
    /// level comes into view once the button is released, so nothing moves under a click or a drag.
    private var pendingLevelSwitch: WindowID?
    /// Rambla resumed, or manages a display again: while it did not, no level was parked there and the user may have
    /// focused any window. The next reconcile brings the focused window's level into view if it is out of view, before
    /// it parks anything.
    private var focusMayBeOutOfView = false
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
    /// Called to show (or hide, when it is on screen) the overview of a strip.
    var overviewHook: ((StripKey) -> Void)?
    /// Offered every shortcut first while the overview is on screen; true when the overview used it.
    var overviewAction: ((Action) -> Bool)?
    /// Offered a short vertical swipe on a stack first while the overview is on screen (`up`: toward the strip above).
    /// Nil when the overview does not show that stack, and the swipe changes strips. Otherwise whether its selection
    /// can go to the row that way, and, with `move`, it goes there.
    var overviewSwipe: ((_ stack: StackKey, _ up: Bool, _ move: Bool) -> Bool?)?
    /// Called when another level of that stack comes into view (the levels indicator).
    var levelHook: ((StackKey) -> Void)?
    /// Called when the level that came into view of that stack is empty (its hint).
    var emptyLevelHook: ((StackKey) -> Void)?
    /// Covers the display of a stack with the overlay's veil, for a switch between its strips that the user asked for
    /// (a swipe, a strip shortcut, sending a window; `up`: toward the strip above), and calls `runPendingSwitches` once
    /// the veil covers it. False when no veil comes (the animations are off, or the display is not there), and nil
    /// without an overlay: the switch runs at once.
    var levelTransition: ((_ stack: StackKey, _ up: Bool) -> Bool)?
    /// The switches between strips the user asked for that wait for the veil to cover their display (`behindVeil`),
    /// oldest first: `runPendingSwitches` runs them.
    var pendingSwitches: [() -> Void] = []
    /// Saved layout from the previous run (its floating windows; the strips go to `archive`).
    var restoreState: SavedState?
    /// Strips not in view: those of the previous run not seen yet, and those of unplugged displays. Each is rebuilt
    /// the first time its display and Space are in view again, and saved meanwhile.
    var archive = StripArchive()
    /// The stacks already rebuilt from the archive this session, every level at once, or found with nothing to rebuild:
    /// each is rebuilt once, until it goes to the archive again (its display unplugged, its desktop gone).
    var restoredStacks: Set<StackKey> = []
    /// Apps asked to list their windows (at launch, after an unlock, on a desktop change) that have not answered yet,
    /// and until when to wait for them: a strip rebuilt before they answer gets only the windows of the apps that
    /// answered first.
    private var awaitingWindowLists: Set<pid_t> = []
    private var awaitingUntil: CFAbsoluteTime = 0
    private static let windowListWait: CFAbsoluteTime = 2
    /// Apps that have listed their windows at least once: one Accessibility cannot reach never answers.
    private var listedOnce: Set<pid_t> = []
    /// When Rambla last learnt of a window it did not know.
    private var lastWindowAppeared: CFAbsoluteTime = 0
    /// Saved ids of the floating windows not matched yet; each one floats a single live window.
    var pendingFloating: Set<WindowID> = []
    /// When Rambla started: saved windows are matched by title only for `restoreByTitleWindow` seconds after it.
    var launchTime: CFAbsoluteTime = 0
    static let restoreByTitleWindow: CFAbsoluteTime = 15
    /// Floating windows that Rambla floated by itself because another app moved them (Rectangle, a snap after a
    /// drag). Unlike the ones the user floats, they are not saved, and "Reacomodar ventanas" puts them back.
    var autoFloated: Set<WindowID> = []
    /// Floating windows (the user's ⌃⌘T ones and the ones Rambla floated after another app moved them) parked with a
    /// level that went out of view, with the frame each had then and the frame of its display then
    /// (`FloatShelf.Parked`): each comes back to that frame, or to the same place on its display if the displays
    /// changed meanwhile. In memory only: quitting and pausing bring every one back (`gatherAll`).
    var floatShelf: [StripKey: [WindowID: FloatShelf.Parked]] = [:]
    /// Floating windows let go from their shelf because they left the desktop of their level (the user took them to
    /// another one in Mission Control, or they are on all of them now), with what the shelf knew of them: each one goes
    /// to its place where it is as soon as it shows (`placeFloatsAway`), as a window out of sight may not take a move.
    var floatsAway: [WindowID: FloatShelf.Parked] = [:]
    /// A floating window the user is dragging, while the left button is down: a level switch leaves it in view, and a
    /// parked one stays where the drag takes it until the button is released.
    private(set) var draggedFloat: WindowID?
    var saveWorkItem: DispatchWorkItem?
    /// Strip being moved by a trackpad swipe.
    var gestureKey: StripKey?
    /// The detents of a slide done on the trackpad, felt as taps (nil when it is not, or haptics are off).
    var slideDetent: SlideDetent?
    /// Focus given by hover or swipe: do not scroll when macOS confirms it.
    var revealSuppressedFor: WindowID?
    /// The last app activated (⌘Tab, the Dock, a notification, a click on one of its windows), and when.
    private var lastActivation: (pid: pid_t, at: CFAbsoluteTime)?
    /// A report of focus on one of its windows this soon after its app was activated came with that activation.
    private static let activationWindow: CFAbsoluteTime = 0.5
    /// When the focused window (in a level in view, or floating on a display in view) last closed or was minimized,
    /// or the app that had the focus was last hidden or quit (`hadTheFocus`): macOS then moves the focus by itself,
    /// which never changes the level in view (`FocusRoute`).
    private var lastLossAt: CFAbsoluteTime?
    /// When each window last had the focus in a level in view, or floating in view: a window that gets the focus
    /// instead of one out of view is the most recently used, and so is a floating window that comes back with its
    /// level to one without windows of its own.
    private(set) var lastFocusedAt: [WindowID: CFAbsoluteTime] = [:]
    /// Windows coming back from the Dock (unminimized), and until when: one that takes the focus then was picked by the
    /// user, like a window chosen in Mission Control.
    private var backFromDock: [WindowID: CFAbsoluteTime] = [:]
    /// When Rambla last switched the level in view of each stack: a report of focus right after can be a late one.
    var levelSwitchedAt: [StackKey: CFAbsoluteTime] = [:]
    /// The check that routes again, once a report could no longer be late, a focus left alone as a possible late one
    /// (`recheckLateReport`). One at a time: only the focused window can still need it.
    private var lateReportCheck: DispatchWorkItem?
    /// A focus that came before `displays` showed its window's Space (⌘Tab to an app on another desktop: only the next
    /// reconcile reads the Space change), and how it came. That reconcile routes it.
    private var focusAwaitingSpace: FocusArrival?
    /// How long such a focus may wait for a reconcile that sees its Space.
    private static let spaceChangeWait: CFAbsoluteTime = 2

    // MARK: - Lifecycle

    /// `stateFile`: in test mode, the tests' own file for the layout (`--state-file`); ignored otherwise.
    func start(prefs: Preferences, onlyBundles: Set<String>?, stateFile: URL? = nil) {
        guard !isRunning else { return }
        self.prefs = prefs
        self.onlyBundles = onlyBundles
        StateStore.testFile = onlyBundles == nil ? nil : stateFile
        isRunning = true
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        animator.onTick = { [weak self] _ in self?.overlayHook?() }
        dragTracker.onMouseUp = { [weak self] point in self?.mouseUp(at: point) }
        dragTracker.setEnabled(true)
        displays = Displays.current()
        presence.update(connected: Set(displays.map(\.uuid)), now: CFAbsoluteTimeGetCurrent(), atLaunch: true)
        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        restoreState = keepsState ? StateStore.load() : nil
        archive = StripArchive(loading: restoreState, at: Date())
        pendingFloating = Set(restoreState?.floating ?? [])
        launchTime = CFAbsoluteTimeGetCurrent()
        lastWindowAppeared = launchTime
        // A display may have been plugged back while Rambla was not running. After a Mac restart its windows can take
        // a while to come back, as their apps open again (`waitsForApps`).
        for display in displays {
            returningDisplays[display.uuid] = launchTime + Self.restoreByTitleWindow + Self.returnWindow
        }
        observeSystem()
        NSWorkspace.shared.runningApplications.forEach(register)
        awaitWindowLists(from: Set(workers.keys))
        if let only = onlyBundles { Log.info("Test mode: managing only \(only.sorted().joined(separator: ", "))") }
        if let file = StateStore.testFile { Log.info("Test mode: the layout is kept in \(file.path)") }
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
        CGDisplayRemoveReconfigurationCallback(displaysReconfigured, Unmanaged.passUnretained(self).toOpaque())
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
            focusMayBeOutOfView = true
            rescanAll()
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
        let wasOff = Set(old.disabledDisplays), isOff = Set(newPrefs.disabledDisplays)
        if wasOff != isOff {
            // Only the displays Rambla stops or starts managing: the strips out of view on the others stay out of
            // sight, and so do the floating windows parked with them.
            gatherAll(synchronously: false, only: wasOff.symmetricDifference(isOff))
            if !wasOff.isSubset(of: isOff) { focusMayBeOutOfView = true }
        }
        scheduleReconcile()
    }

    // MARK: - System observation

    private func observeSystem() {
        CGDisplayRegisterReconfigurationCallback(displaysReconfigured, Unmanaged.passUnretained(self).toOpaque())
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.didLaunchApplicationNotification) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            appLaunchTimes[app.processIdentifier] = CFAbsoluteTimeGetCurrent()
            register(app)
        }
        observe(ws, NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            // Quitting the app that has the focus moves it by itself, often to a window of the next app. Asked before
            // its windows go.
            if hadTheFocus(app.processIdentifier) { lastLossAt = CFAbsoluteTimeGetCurrent() }
            unregister(app.processIdentifier)
        }
        observe(ws, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            frontmostPID = app.processIdentifier
            lastActivation = (app.processIdentifier, CFAbsoluteTimeGetCurrent())
            // Some apps only become "regular" (Dock icon) after launching.
            if workers[app.processIdentifier] == nil { register(app) }
            if let worker = workers[app.processIdentifier] {
                worker.refreshFocused()
            } else {
                focusChanged(nil)
            }
        }
        observe(ws, NSWorkspace.didHideApplicationNotification) { [weak self] note in
            guard let self else { return }
            // Hiding the app that has the focus moves it by itself, to a window of the next app; hiding the others
            // (⌥⌘H) does not.
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               hadTheFocus(app.processIdentifier) {
                lastLossAt = CFAbsoluteTimeGetCurrent()
            }
            scheduleReconcile()
        }
        observe(ws, NSWorkspace.didUnhideApplicationNotification) { [weak self] note in
            guard let self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                markReappearing(windows.values.filter { $0.pid == app.processIdentifier }.map(\.id))
            }
            scheduleReconcile()
        }
        observe(ws, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in
            guard let self else { return }
            // The focused window belongs to the Space we left: drop it so the border and dimming hide
            // until the new Space reports its own focus.
            focusedWindow = nil
            overlayHook?()
            frontmostPID.flatMap { self.workers[$0] }?.refreshFocused()
            grace(1.0)
            rescanAll()
            scheduleReconcile(after: 0.15)
        }
        observe(ws, NSWorkspace.didWakeNotification) { [weak self] _ in self?.screensWoke() }
        observe(ws, NSWorkspace.screensDidSleepNotification) { [weak self] _ in self?.screensAsleep = true }
        observe(ws, NSWorkspace.screensDidWakeNotification) { [weak self] _ in self?.screensWoke() }
        observe(DistributedNotificationCenter.default(), Self.screenUnlocked) { [weak self] _ in
            // Accessibility lists no window while the screen is locked: if Rambla started then, it knows none yet.
            Log.info("Screen unlocked: reading the windows again")
            self?.readWindowsAgain()
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.grace(2.5)
            self?.scheduleReconcile(after: 0.4)
        }
    }

    /// After a wake, of the Mac or only of its screens, a monitor can take a while to come back.
    private func screensWoke() {
        screensAsleep = false
        displayGoneSince.removeAll()
        grace(2.5)
        scheduleReconcile(after: 0.8)
    }

    private static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    /// Every app lists its windows again, and one reconcile takes all the answers after the same wait as at launch.
    /// Right after an unlock Accessibility may still list nothing: while no window is known, it tries twice more.
    private func readWindowsAgain(retries: Int = 2) {
        rescanAll(waitingForAll: true)
        scheduleReconcile(after: 0.6)
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, self.windows.isEmpty else { return }
                self.readWindowsAgain(retries: retries - 1)
            }
        }
    }

    /// The sleep and wake notifications keep `screensAsleep`; a display that is awake also ends it, in case a wake
    /// notification was missed. A monitor can leave the list while it sleeps, so with no display awake to ask, the
    /// notifications decide.
    private func screensAreAsleep() -> Bool {
        if screensAsleep, Self.anyDisplayAwake() { screensAsleep = false }
        return screensAsleep
    }

    /// The lid of a laptop is closed (`AppleClamshellState`); false on a desktop Mac.
    private static func lidIsClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return state?.takeRetainedValue() as? Bool ?? false
    }

    private static func anyDisplayAwake() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsAsleep($0) == 0 }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { block(note) }
        }
        observers.append((center, token))
    }

    /// macOS moves windows while it changes the displays, sometimes before the screen-parameters notification: those
    /// moves are not another app's, so they must not float the windows.
    fileprivate func displaysReconfiguring() {
        guard isRunning else { return }
        grace(2.5)
        scheduleReconcile(after: 0.4)
    }

    /// Lets the live tests plug and unplug a display beside the real ones (nil unplugs it). Test mode only.
    func setTestNeighbor(_ frame: CGRect?) -> Bool {
        guard onlyBundles != nil else { return false }
        testNeighbor = frame
        displaysReconfiguring()
        return true
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
        awaitingWindowLists.remove(pid)
        listedOnce.remove(pid)
        guard let worker = workers.removeValue(forKey: pid) else { return }
        worker.stop()
        for (id, record) in windows where record.pid == pid { removeWindow(id) }
        scheduleReconcile()
    }

    /// The app `pid` has the focus: the focused window is one of its own, or it is the app in front. Hiding or quitting
    /// it moves the focus by itself, which is a loss (`lastLossAt`); hiding or quitting another app is none.
    private func hadTheFocus(_ pid: pid_t) -> Bool {
        focusedWindow.flatMap { windows[$0]?.pid } == pid || frontmostPID == pid
    }

    /// Every app lists its windows again; saved strips wait for the answers of those that answered before, or of all
    /// of them after an unlock (while the screen is locked Accessibility may not answer at all).
    private func rescanAll(waitingForAll: Bool = false) {
        workers.values.forEach { $0.rescan() }
        awaitWindowLists(from: waitingForAll ? Set(workers.keys) : listedOnce.intersection(workers.keys))
    }

    private func awaitWindowLists(from apps: Set<pid_t>) {
        awaitingWindowLists = apps
        awaitingUntil = CFAbsoluteTimeGetCurrent() + Self.windowListWait
        checkDisplaysAgain(after: Self.windowListWait + 0.05)
    }

    private func markReappearing<S: Sequence>(_ ids: S) where S.Element == WindowID {
        let until = CFAbsoluteTimeGetCurrent() + Self.reappearDelay
        for id in ids { reappearing[id] = until }
    }

    /// Some app has not listed its windows yet (`awaitingWindowLists`).
    var waitingForWindowLists: Bool { !awaitingWindowLists.isEmpty && CFAbsoluteTimeGetCurrent() < awaitingUntil }

    /// After a Mac restart Rambla can start before macOS opens the apps again. For `restoreByTitleWindow` after launch,
    /// a strip saved in an earlier login session waits until each of its apps shows a window and no new window has
    /// appeared for a second (three while one of its apps has none: it may not come back).
    func waitsForApps(_ saved: SavedStrip, now: CFAbsoluteTime) -> Bool {
        let deadline = launchTime + Self.restoreByTitleWindow
        guard let session = saved.session, session != StateStore.session, now < deadline else { return false }
        let shown = Set(windows.values.compactMap(\.bundleID))
        let quiet: CFAbsoluteTime = Set(saved.refs.map(\.bundleID)).subtracting([""]).isSubset(of: shown) ? 1 : 3
        let ready = lastWindowAppeared + quiet
        guard now < ready else { return false }
        checkDisplaysAgain(after: min(ready, deadline) - now + 0.05)
        return true
    }

    func worker(for id: WindowID) -> AppWorker? {
        windows[id].flatMap { workers[$0.pid] }
    }

    /// Calls `done` once every app has made the moves asked of it so far (each app's worker makes them in order), or
    /// after `timeout` when one takes longer: the veil over a switch between strips waits for the windows to be in
    /// their places before it shows them.
    func afterPendingMoves(timeout: TimeInterval, _ done: @escaping () -> Void) {
        let waiting = PendingMoves(apps: workers.count, done: done)
        for worker in workers.values {
            worker.afterPendingWork { MainActor.assumeIsolated { waiting.appDone() } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { MainActor.assumeIsolated { waiting.finish() } }
    }

    // MARK: - AX events

    private func handle(_ event: AXEvent) {
        guard isRunning else { return }
        switch event {
        case .appWindows(let pid, let snapshots):
            awaitingWindowLists.remove(pid)
            listedOnce.insert(pid)
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
            // Minimizing the focused window moves the focus by itself; a window back from the Dock that takes the focus
            // was picked by the user (`FocusRoute`).
            if isMinimized, id == focusedWindow, spaceInView(of: id, record: windows[id]) != nil {
                lastLossAt = CFAbsoluteTimeGetCurrent()
            }
            windows[id]?.traits.isMinimized = isMinimized
            if !isMinimized {
                markReappearing([id])
                backFromDock[id] = CFAbsoluteTimeGetCurrent() + Self.reappearDelay
            }
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
            lastWindowAppeared = CFAbsoluteTimeGetCurrent()
        }
    }

    func removeWindow(_ id: WindowID) {
        let record = windows.removeValue(forKey: id)
        guard record != nil || floating.contains(id) else { return }
        // The focused window going away (closed, or gone with its app) moves the focus by itself (`FocusRoute`).
        if id == focusedWindow, spaceInView(of: id, record: record) != nil { lastLossAt = CFAbsoluteTimeGetCurrent() }
        floating.remove(id)
        autoFloated.remove(id)
        requested[id] = nil
        hiddenSince[id] = nil
        lastFocusedAt[id] = nil
        backFromDock[id] = nil
        placedAtUnpluggedLevel[id] = nil
        // A floating window parked with a level out of view leaves its shelf.
        takeFromFloatShelf(id)
        floatsAway[id] = nil
        if draggedFloat == id { draggedFloat = nil }
        for key in Array(hidden.keys) { hidden[key]?.remove(id) }
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
            // Out of view too: parked at its old width, a wider window would show more than its sliver.
            if isCurrent(key) { apply(key, animate: false) } else { shelve(key) }
        }
    }

    // MARK: - Focus

    /// How a focus came to a window, for `FocusRoute`: when, whether its app had just been activated, whether macOS was
    /// moving the focus by itself after a loss, and whether the user picked that very window, back from the Dock.
    private struct FocusArrival {
        let window: WindowID
        let at: CFAbsoluteTime
        var byActivation: Bool
        var afterLoss: Bool
        var chosen: Bool
    }

    func focusChanged(_ id: WindowID?) {
        let now = CFAbsoluteTimeGetCurrent()
        let previous = focusedWindow
        focusedWindow = id
        // A floating window parked with a level out of view (`floatShelf`) is out of view with it: it is routed like
        // the windows of that level. One parked with the level in view (it was hidden when that level came back)
        // floats in view, and the next pass brings it back to its place. So does one on another desktop (taken there
        // in Mission Control while parked, or now on all of them): it is no longer that level's.
        var parkedWith = id.flatMap(floatShelfKey(holding:))
        if let id, let shelf = parkedWith {
            if isCurrent(shelf) {
                parkedWith = nil
                scheduleReconcile()
            } else if !inGrace, !isTuckedAway(id), let spaces = Private.spaces(for: [id])[id],
                      FloatShelf.isAway(spaces: spaces, from: shelf.spaceID) {
                letGo(id, from: shelf)
                parkedWith = nil
                scheduleReconcile()
                // On a desktop no display shows (⌘Tab to its app with macOS's "switch to a Space with open windows"
                // off): the keyboard does not stay in it, out of sight, as when the focused window goes out of view.
                if !isShown(id, on: spaces) {
                    focusAwaitingSpace = nil
                    let inView = displays.first { $0.uuid == shelf.displayUUID }.flatMap(currentKey)
                    handKeyboardOn(from: id, to: inView.flatMap { isCurrent($0) ? $0 : nil },
                                   report: "Floating window \(id), which has the focus, is on a desktop not shown")
                    return
                }
            }
        }
        if let id, key(containing: id) == nil, parkedWith == nil, floating.contains(id) || windows[id]?.kind == .float {
            // A floating window can end up under the strip (a swipe focuses the column it lands on). When its app
            // comes to the front (Dock, ⌘Tab, a click), it must be on top, not behind the strip's windows.
            worker(for: id)?.raise(id)
            lastFocusedAt[id] = now
        }
        let awaiting = focusAwaitingSpace
        focusAwaitingSpace = nil
        guard let id, let key = key(containing: id) ?? parkedWith else {
            overlayHook?()
            return
        }
        if isCurrent(key) {
            focusSettled(id, in: key)
            return
        }
        guard !isPaused else {
            overlayHook?()
            return
        }
        // A window of a level out of view got the focus, or one of a Space not read yet. When the same window was
        // waiting for its Space, how its focus first came still counts.
        var arrival = arrival(of: id, at: now)
        if let awaiting, awaiting.window == id, now - awaiting.at < Self.spaceChangeWait {
            arrival = FocusArrival(window: id, at: awaiting.at, byActivation: arrival.byActivation || awaiting.byActivation,
                                   afterLoss: arrival.afterLoss || awaiting.afterLoss,
                                   chosen: arrival.chosen || awaiting.chosen)
        }
        if isCurrentStack(key.stack) {
            route(arrival, in: key, leaving: previous)
        } else {
            // Its display may have just changed Space (⌘Tab to an app on another desktop), which `displays` shows only
            // from the next reconcile: that one routes this focus.
            focusAwaitingSpace = arrival
            overlayHook?()
        }
    }

    /// The focus settled on a window of a level in view: it becomes its strip's focused window, its column comes into
    /// view, and it is the most recently used there.
    private func focusSettled(_ id: WindowID, in key: StripKey) {
        lastFocusedAt[id] = CFAbsoluteTimeGetCurrent()
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

    /// How the focus came to `id` at `now`: right after its app was activated, while macOS moves the focus after a
    /// loss, and as the window comes back from the Dock. Its report of being unminimized may come after the focus: a
    /// window still minimized as far as Rambla knows is coming back too.
    private func arrival(of id: WindowID, at now: CFAbsoluteTime) -> FocusArrival {
        let pid = windows[id]?.pid
        return FocusArrival(window: id, at: now,
                            byActivation: lastActivation.map { $0.pid == pid && now - $0.at < Self.activationWindow } ?? false,
                            afterLoss: lastLossAt.map { now - $0 < FocusRoute.lateReportWindow } ?? false,
                            chosen: windows[id]?.traits.isMinimized == true || (backFromDock[id] ?? 0) > now)
    }

    /// A window of `key`, a level of a stack in view (in its strip, or floating and parked with it), got the focus from
    /// outside Rambla (Mission Control, ⌘Tab, a click on its sliver, or macOS after a window closed): `FocusRoute` says
    /// whether its level comes into view, a window of the level in view gets the focus instead, or Rambla takes the
    /// keyboard, so the keyboard never types into a window that cannot be seen. `previous`: the window that had the
    /// focus before, if known. `lateReports`: false once a focus left alone as a possible late report has outlasted
    /// the time one could be late (`recheckLateReport`).
    private func route(_ arrival: FocusArrival, in key: StripKey, leaving previous: WindowID?,
                       lateReports: Bool = true) {
        let id = arrival.window
        let now = CFAbsoluteTimeGetCurrent()
        let active = key.stack.level(activeLevel(of: key.stack))
        var afterLoss = arrival.afterLoss
        // The window that had the focus in view (in a level in view, or floating) went away (closed, minimized, its app
        // hidden or quit), and its app reported the new focus before saying so: the loss counts from now.
        if !afterLoss, key != active, let previous, previous != id,
           let space = spaceInView(of: previous, record: windows[previous]), wentAway(previous, from: space) {
            lastLossAt = now
            afterLoss = true
        }
        let inView = windowsInView(of: active)
        let pid = windows[id]?.pid
        let switchedAt = levelSwitchedAt[key.stack]
        let decision = FocusRoute.decide(
            windowLevel: key.level, active: active.level, byActivation: arrival.byActivation, afterLoss: afterLoss,
            chosen: arrival.chosen, appWindowsInView: inView.filter { windows[$0]?.pid == pid }, windowsInView: inView,
            sinceOwnSwitch: lateReports ? switchedAt.map { now - $0 } : nil)
        let cause = afterLoss ? " as something in view went away"
            : arrival.chosen ? " as it came back from the Dock"
            : arrival.byActivation ? " as its app came to the front" : ""
        let report = "Window \(id) of strip level \(key.level) got the focus\(cause)"
        switch decision {
        case .none:
            focusSettled(id, in: key)
        case .lateReport:
            Log.info("\(report) right after a level switch: maybe a late report, left alone for now")
            recheckLateReport(arrival, leaving: previous, at: (switchedAt ?? now) + FocusRoute.lateReportWindow)
            overlayHook?()
        case .switchLevel where dragTracker.isMouseDown:
            Log.info("\(report): its level comes into view once the mouse button is released")
            pendingLevelSwitch = id
            overlayHook?()
        case .switchLevel:
            Log.info("\(report): its level comes into view")
            followFocus(to: id, in: key)
        case .redirect(let window):
            Log.info("\(report): window \(window), in view, gets it instead")
            focus(window: window, in: active, routed: true)
        case .takeKeyboard:
            Log.info("\(report): nothing in view can take it")
            takeKeyboardFocus()
        }
    }

    /// `arrival` came right after Rambla switched its stack's level, and was left alone as a possible late report
    /// (`FocusRoute.lateReport`). At `deadline`, when a report could no longer be late, its window is routed again
    /// without that rule if it still has the focus on a level out of view, its app still in front: then it was no late
    /// report, but the user's choice (⌘` twice across strips, or the Window menu, right after a switch), and the
    /// keyboard must not stay out of sight. A late report is over by then: the window Rambla focused, or Rambla itself
    /// on an empty strip, has taken the focus. `previous`, the window that had the focus before the report, goes on to
    /// `route` as it was: if it went away since (minimized, or its app hidden), macOS moved the focus by itself, which
    /// is no choice of the user's either.
    private func recheckLateReport(_ arrival: FocusArrival, leaving previous: WindowID?, at deadline: CFAbsoluteTime) {
        lateReportCheck?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lateReportCheck = nil
                let id = arrival.window
                guard self.isRunning, !self.isPaused, self.focusedWindow == id, self.pendingLevelSwitch != id,
                      let pid = self.windows[id]?.pid,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                      let key = self.key(containing: id)
                        ?? self.floatShelfKey(holding: id).flatMap({ self.isCurrent($0) ? nil : $0 }),
                      !self.isCurrent(key), self.isCurrentStack(key.stack) else { return }
                Log.info("Window \(id) of strip level \(key.level) still has the focus after the level switch: "
                         + "no late report")
                self.route(arrival, in: key, leaving: previous, lateReports: false)
            }
        }
        lateReportCheck = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - CFAbsoluteTimeGetCurrent()) + 0.05,
                                      execute: item)
    }

    /// What can take the focus in view: the windows of `active`, a level in view, that are on screen, the last used
    /// first. For a level out of view of a stack in view, those that show once it comes into view: its parked windows
    /// are on screen too, on their sliver, and the minimized ones and those of hidden apps are not.
    private func windowsInView(of active: StripKey) -> [WindowID] {
        let shown = Self.windowIDs(onScreenOnly: true)
        return FocusRoute.byLastUse((strips[active]?.allWindows ?? []).filter {
            shown.contains($0) && windows[$0]?.traits.isMinimized != true
        }, lastUsed: lastFocusedAt)
    }

    /// The window of `key`, a level of a stack in view, that gets the focus when the level comes into view or takes
    /// the keyboard back: its focused window when that one shows (`windowsInView`), else the one used last there that
    /// does. Nil when none shows (all minimized, or of hidden apps) or the level has none.
    func shownWindow(of key: StripKey) -> WindowID? {
        let shown = windowsInView(of: key)
        return strips[key]?.focusedWindow.flatMap { shown.contains($0) ? $0 : nil } ?? shown.first
    }

    /// `id`, the focused window, is on `key`, a level out of view, by Rambla's own doing: rebuilt there from the saved
    /// stack, taken back there by its display, or back on the level it had on a display that was unplugged; or its
    /// level left the view under it, as a rebuilt stack shows again the level it showed when it was saved. Nothing
    /// typed may reach it there, and the level in view does not change for it: as after a loss (`FocusRoute`), the
    /// last used window in view gets the focus, one of the same app first, or Rambla takes the keyboard. In view means
    /// on the level the window was on, `from`, when that is still in view, else on the one in view of its stack now.
    private func focusWentOutOfView(_ id: WindowID, to key: StripKey, from: StripKey?) {
        let stack = from.flatMap { isCurrent($0) ? $0.stack : nil } ?? key.stack
        handKeyboardOn(from: id, to: stack.level(activeLevel(of: stack)),
                       report: "Window \(id), which has the focus, is now out of view on strip level \(key.level)")
    }

    /// `id` has the focus where it cannot be seen. As after a loss (`FocusRoute`), the last used window in view of
    /// `active`, a level in view, gets it, one of the same app first; Rambla takes the keyboard when there is none, or
    /// no such level.
    private func handKeyboardOn(from id: WindowID, to active: StripKey?, report: String) {
        let inView = active.map { windowsInView(of: $0) } ?? []
        let pid = windows[id]?.pid
        if let active, let window = inView.first(where: { windows[$0]?.pid == pid }) ?? inView.first {
            Log.info("\(report): window \(window), in view, gets it instead")
            focus(window: window, in: active, routed: true)
        } else {
            Log.info("\(report): nothing in view can take it")
            takeKeyboardFocus()
        }
    }

    /// The focused window is on a level out of view of a stack in view, because its column was moved there
    /// (`moveColumn(id:from:toLevel:at:handOverKeyboard:)`): nothing typed may reach it there, and the level in view
    /// does not change for it. That level's focused window gets the keyboard (when it is not on screen, the window of
    /// that level used last that is), or Rambla takes it when that level has none. The pointer stays where it is.
    func keepKeyboardInView() {
        guard isRunning, !isPaused, let id = focusedWindow, let home = key(containing: id), !isCurrent(home),
              isCurrentStack(home.stack) else { return }
        let active = home.stack.level(activeLevel(of: home.stack))
        let report = "Window \(id), which has the focus, went to strip level \(home.level), out of view"
        if let window = shownWindow(of: active) {
            Log.info("\(report): window \(window), in view, gets it instead")
            focus(window: window, in: active, routed: true)
        } else {
            Log.info("\(report): nothing in view can take it")
            takeKeyboardFocus()
        }
    }

    /// The Space on which `id` is in view: its strip's when that is a level in view (or the level it is parked with,
    /// for a floating window that went with its level, `floatShelf`), or the current one of the display it floats on
    /// (a dialog, a settings window, one the user floated). Nil when it is not in view.
    private func spaceInView(of id: WindowID, record: WindowRecord?) -> UInt64? {
        if let key = key(containing: id) ?? floatShelfKey(holding: id) { return isCurrent(key) ? key.spaceID : nil }
        guard let record, floating.contains(id) || record.kind == .float else { return nil }
        return Displays.best(for: whereShown(record), in: enabledDisplays)?.currentSpace
    }

    /// `id`, a window in view on `space`, is no longer on screen: it closed or was minimized, or its app was hidden or
    /// quit. A window the user took to another Space in Mission Control did not go away: it is on that Space.
    private func wentAway(_ id: WindowID, from space: UInt64) -> Bool {
        guard !Self.isOnScreen(id) else { return false }
        let spaces = Private.spaces(for: [id])[id] ?? []
        return spaces.isEmpty || spaces.contains(space)
    }

    /// `id`, a window macOS files under `spaces`, can be seen: it is on screen, or on a desktop a display shows now,
    /// as the WindowServer has it (macOS may be switching to that desktop for it, after ⌘Tab to its app).
    private func isShown(_ id: WindowID, on spaces: [UInt64]) -> Bool {
        Self.isOnScreen(id) || Private.displaySpaces().contains { spaces.contains($0.current) }
    }

    /// The level of `id`, a window of `key` (in its strip, or floating and parked with it) that got the focus from
    /// outside Rambla, comes into view with that window focused, leaving the pointer where it is. The window already
    /// has the focus, so its app may not report it again: it counts as the most recently used here.
    private func followFocus(to id: WindowID, in key: StripKey) {
        switchLevel(of: key.stack, to: key.level, focusing: id, routed: true)
        if isCurrent(key) { lastFocusedAt[id] = CFAbsoluteTimeGetCurrent() }
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

    static func windowIDs(onScreenOnly: Bool) -> Set<WindowID> {
        Set(windowFrames(onScreenOnly: onScreenOnly).keys)
    }

    /// The normal windows the WindowServer has (`onScreenOnly`: the ones on screen now), with where they are.
    static func windowFrames(onScreenOnly: Bool) -> [WindowID: CGRect] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var frames: [WindowID: CGRect] = [:]
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
            frames[id] = bounds ?? .zero
        }
        return frames
    }

    /// The WindowServer shows the window now, whatever its layer (a dialog or a panel can float above the others).
    private static func isOnScreen(_ id: WindowID) -> Bool {
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(id)) as? [[String: Any]]
        return list?.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    /// Where a window is: where the WindowServer shows it when it is on screen, else where Rambla last knew it. Rambla's
    /// own record keeps the frame it asked for, which is out of date once macOS moved the window by itself (a display
    /// that went away).
    func whereShown(_ record: WindowRecord) -> CGRect {
        onScreenFrames[record.id].flatMap { $0 == .zero ? nil : $0 } ?? record.frame
    }

    var enabledDisplays: [DisplayInfo] {
        displays.filter { !prefs.disabledDisplays.contains($0.uuid) && $0.currentSpace != nil && !$0.isFullscreenSpace }
    }

    /// The strip in view on `display`: the level in view of the stack of its current Space.
    func currentKey(of display: DisplayInfo) -> StripKey? {
        display.currentSpace.map { space in
            let stack = StackKey(displayUUID: display.uuid, spaceID: space)
            return stack.level(activeLevel(of: stack))
        }
    }

    /// The strips in view, one per managed display: only these are laid out with `apply`, have overlays and take
    /// gestures. The other levels of their stacks are parked out of sight (`shelve`).
    var currentKeys: [StripKey] { enabledDisplays.compactMap(currentKey) }

    func isCurrent(_ key: StripKey) -> Bool { currentKeys.contains(key) }

    /// Its display shows its Space and is managed: one of its levels is in view.
    func isCurrentStack(_ stack: StackKey) -> Bool {
        enabledDisplays.contains { $0.uuid == stack.displayUUID && $0.currentSpace == stack.spaceID }
    }

    /// The display a strip is shown on: nil unless its Space is the display's current one and its level is the one in
    /// view, so nothing lays out or draws a strip that is not there to see.
    func display(for key: StripKey) -> DisplayInfo? {
        guard key.level == activeLevel(of: key.stack) else { return nil }
        return display(forStack: key.stack)
    }

    /// The display showing a stack's Space, whichever of its levels is in view.
    func display(forStack stack: StackKey) -> DisplayInfo? {
        displays.first { $0.uuid == stack.displayUUID && $0.currentSpace == stack.spaceID }
    }

    /// The strip holding a window, at any level.
    func key(containing id: WindowID) -> StripKey? {
        strips.first { $0.value.contains(id) }?.key
    }

    /// The strip in view of a Space (a window moved to it in Mission Control joins it).
    private func stripKey(forSpace space: UInt64) -> StripKey? {
        for entry in Private.displaySpaces() where entry.uuids[space] != nil {
            let uuid = entry.displayUUID == "Main" ? (displays.first?.uuid ?? entry.displayUUID) : entry.displayUUID
            guard let display = displays.first(where: { $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame }),
                  !prefs.disabledDisplays.contains(display.uuid), !entry.fullscreen.contains(space) else { return nil }
            let stack = StackKey(displayUUID: display.uuid, spaceID: space)
            return stack.level(activeLevel(of: stack))
        }
        return nil
    }

    private func reconcile() {
        reconcileScheduled = false
        guard isRunning, !isPaused else { return }
        let connectedBefore = Set(displays.map(\.uuid))
        displays = Displays.current()
        let existing = Self.windowIDs(onScreenOnly: false)
        onScreenFrames = Self.windowFrames(onScreenOnly: true)
        let visible = Set(onScreenFrames.keys)
        let now = CFAbsoluteTimeGetCurrent()
        presence.update(connected: Set(displays.map(\.uuid)), now: now)
        builtinDisplays.formUnion(displays.filter { CGDisplayIsBuiltin($0.id) != 0 }.map(\.uuid))
        let settled = displays.filter { presence.isSettled($0.uuid, now: now) }
        for display in displays {
            if let at = presence.settles(display.uuid, now: now) { checkDisplaysAgain(after: at - now + 0.1) }
        }

        for id in Array(windows.keys) where !existing.contains(id) {
            worker(for: id)?.forgetWindow(id)
            removeWindow(id)
        }
        followReturningDisplays(connectedBefore: connectedBefore, now: now)
        heldForReturn = windowsHeldForReturn(now: now)
        dropStripsOfDisconnectedDisplays(now: ProcessInfo.processInfo.systemUptime)
        archiveStripsOfGoneSpaces()

        var keys = currentKeys
        for display in enabledDisplays {
            guard let key = currentKey(of: display) else { continue }
            spaceKeys[key.stack] = display.currentSpaceKey
            if strips[key] == nil { strips[key] = Strip() }
        }

        // Windows of a visible strip that are not on screen are either hidden on this Space
        // (minimized, app hidden, inactive native tab, full screen) or were moved to another Space.
        // A minimized window or one of a hidden app cannot be moved to another Space by the user: macOS files it under
        // another one when a display appears beside it (a parked window lies almost all past the edge), and it keeps
        // its place.
        let hiddenBefore = hidden
        // The other levels of the stacks in view are on these Spaces too. A window of theirs that is not on screen takes
        // no room and is not parked, and one that is back on screen (its app shown again) is parked with the rest.
        let outOfView = strips.keys.filter { key in !keys.contains(key) && keys.contains { $0.stack == key.stack } }
        let notVisible = (keys + outOfView).flatMap { strips[$0]!.allWindows.filter { !visible.contains($0) } }
        let spacesOf = Private.spaces(for: notVisible)
        var hiddenNow: [StripKey: Set<WindowID>] = [:]
        for key in keys {
            for id in strips[key]!.allWindows where !visible.contains(id) {
                if !followToItsSpace(id, from: key, spaces: spacesOf[id] ?? [], now: now) {
                    hiddenNow[key, default: []].insert(id)
                    if hiddenSince[id] == nil { hiddenSince[id] = now }
                }
            }
        }
        // A parked window of a level out of view lies almost all past an edge too, so macOS may file it under another
        // Space while the displays change: during the grace it keeps its place. Outside it, a window the user took to
        // another Space in Mission Control goes there, as one in view does.
        for key in outOfView {
            for id in strips[key]!.allWindows where !visible.contains(id) {
                if inGrace || !followToItsSpace(id, from: key, spaces: spacesOf[id] ?? [], now: now) {
                    hiddenNow[key, default: []].insert(id)
                    if hiddenSince[id] == nil { hiddenSince[id] = now }
                }
            }
        }
        for id in visible { hiddenSince[id] = nil }
        hidden = HiddenWindows.update(hidden, found: hiddenNow, looked: Set(keys + outOfView),
                                      exists: { strips[$0] != nil })
        reappearing = reappearing.filter { $0.value > now }
        backFromDock = backFromDock.filter { $0.value > now }
        markReappearing(HiddenWindows.returned(before: hiddenBefore, now: hidden))

        // Windows that stopped being tileable (rules changed) leave their strips. A window in native full screen keeps
        // its column, hidden like a minimized one, so it comes back to its place when it leaves full screen. One that
        // leaves while parked (on a level out of view, or in a column off screen) comes into view: no strip lays it out
        // any more, and "Traer todas las ventanas" would not find it on its sliver.
        for key in Array(strips.keys) {
            for id in strips[key]!.allWindows {
                guard let record = windows[id], record.kind != .tile, !record.traits.isFullscreen else { continue }
                var parked = !isCurrent(key)
                if case .parked? = results[key]?.placements[id] { parked = true }
                strips[key]!.remove(window: id)
                if parked { bringInIfOffScreen(id) }
            }
        }

        // Visible tileable windows that belong to no strip yet.
        var managed = Set(strips.values.flatMap(\.allWindows))
        let candidates = windows.values
            .filter { $0.kind != .ignore && visible.contains($0.id) && !managed.contains($0.id) && !floating.contains($0.id) }
        // Where the focused window was, and which levels were in view, before stacks are rebuilt and new windows join
        // them.
        let focusedKeyBefore = focusedWindow.flatMap { key(containing: $0) }
        let keysBefore = keys
        restoreFromSavedState(stacks: keys.map(\.stack), candidates: candidates, visible: visible, alive: existing)
        // A rebuilt stack shows again the level it showed when it was saved: from here on, that level is the one in
        // view, laid out below with the windows that join it, while the others are parked.
        keys = currentKeys
        // After a pause, or once a display is managed again, the focused window can be on a level out of view: that
        // level comes into view in this pass, before anything is parked, so the keyboard never ends up out of sight.
        let broughtIn = focusMayBeOutOfView ? bringFocusedLevelIntoView() : nil
        focusMayBeOutOfView = false
        if broughtIn != nil { keys = currentKeys }
        managed = Set(strips.values.flatMap(\.allWindows))
        let orphans = windows.values
            .filter { $0.kind == .tile && visible.contains($0.id) && !managed.contains($0.id) && !floating.contains($0.id) }
            .sorted { $0.frame.minX < $1.frame.minX }
        var revealKeys: Set<StripKey> = []
        if let broughtIn { revealKeys.insert(broughtIn) }
        // The focused window was hidden (full screen, minimized, its app hidden) and is back: the strip may have scrolled
        // meanwhile, so bring it into view instead of laying it out wherever its column is now.
        if let focused = focusedWindow, let key = key(containing: focused), keys.contains(key),
           HiddenWindows.returned(focused, on: key, before: hiddenBefore, now: hidden) {
            strips[key]!.focus(window: focused)
            revealKeys.insert(key)
        }
        for record in orphans {
            // A window on a disabled display stays untouched: look it up among all displays.
            // A stack waiting to be rebuilt takes its windows then, in their places.
            guard let display = Displays.best(for: whereShown(record), in: settled),
                  let inView = currentKey(of: display), keys.contains(inView),
                  restoredStacks.contains(inView.stack) || !waitingForWindowLists else { continue }
            // A window of a display that was unplugged joins the level it was on there, the first time it is an orphan
            // since that display left (`placedAtUnpluggedLevel`), created with the levels below it if they are missing,
            // and parked at the end of this pass if that level is not in view. Any other window joins the level in
            // view.
            var level = inView.level
            if let holder = archive.unpluggedStrip(holding: record.id, session: StateStore.session),
               placedAtUnpluggedLevel[record.id] != holder.displayUUID {
                level = max(0, holder.level)
                placedAtUnpluggedLevel[record.id] = holder.displayUUID
            }
            let key = inView.stack.level(level)
            for below in 0..<level where strips[inView.stack.level(below)] == nil {
                strips[inView.stack.level(below)] = Strip()
            }
            insert(record, into: key)
            // A window that joins at the end can have the focus (it came back from somewhere): show it.
            if record.id == focusedWindow { strips[key]!.focus(window: record.id) }
            if key == inView, record.isFresh || record.id == focusedWindow { revealKeys.insert(key) }
        }

        if let focused = focusedWindow, let key = key(containing: focused), !revealKeys.contains(key) {
            strips[key]!.focus(window: focused)
        }
        for key in keys {
            if revealKeys.contains(key) { reveal(key) } else { apply(key, animate: true) }
        }
        // The other levels of the stacks in view stay out of sight: what drifted (moved by its app, or by macOS while
        // the displays changed) goes back to its parking spot, and nothing is written when nothing did. An empty level
        // left above the others (its last window closed) goes.
        for key in keys {
            dropEmptyLevels(of: key.stack)
            for other in Array(strips.keys) where other.stack == key.stack && other != key { shelve(other) }
        }
        // The same for the floating windows parked with those levels (`floatShelf`).
        settleFloatShelves(inView: keys, visible: visible)
        if let broughtIn { levelHook?(broughtIn.stack) }
        // A focus that came before this pass read its window's Space (⌘Tab to an app on another desktop) is routed now
        // that its stack is in view, if the window still has it. It is dropped once the focus moved on, or too late.
        // A floating window parked with a level out of view is routed as a window of that level.
        if let held = focusAwaitingSpace {
            let home = key(containing: held.window)
                ?? floatShelfKey(holding: held.window).flatMap { isCurrent($0) ? nil : $0 }
            if focusedWindow == held.window, let home, isCurrentStack(home.stack) {
                focusAwaitingSpace = nil
                route(held, in: home, leaving: nil)
            } else if (focusedWindow != nil && focusedWindow != held.window) || now - held.at >= Self.spaceChangeWait {
                focusAwaitingSpace = nil
            }
        }
        // The focused window that this pass put out of view does not keep the keyboard out of sight, unless its level
        // is to come into view once the mouse button is released. It went to a level out of view (rebuilt there, taken
        // back there by its display, or back on the level it had on a display that was unplugged), or its level left
        // the view under it (a rebuilt stack shows again the level it showed when it was saved).
        if let id = focusedWindow, let home = key(containing: id), !isCurrent(home), isCurrentStack(home.stack),
           pendingLevelSwitch != id, home != focusedKeyBefore || keysBefore.contains(home) {
            focusWentOutOfView(id, to: home, from: focusedKeyBefore)
        }
        // Strips that wait for the apps' window lists need a reconcile once the wait is over, whichever came first.
        if waitingForWindowLists { checkDisplaysAgain(after: awaitingUntil - CFAbsoluteTimeGetCurrent() + 0.05) }
        onStateChanged?()
    }

    /// Rambla resumed, or manages a display again (`focusMayBeOutOfView`), and the focused window is on a level out of
    /// view of a stack in view (in its strip, or floating and parked with it): the user focused it while nothing was
    /// parked there, so its level, rather than another window, comes into view. That level becomes the one in view, its
    /// strip focused on the window, for the reconcile to lay it out with its column revealed and park the others; the
    /// floating windows in view stay, as after a pause they belong to the strip in view. Returns that level.
    private func bringFocusedLevelIntoView() -> StripKey? {
        guard let id = focusedWindow, pendingLevelSwitch != id,
              let home = key(containing: id) ?? floatShelfKey(holding: id), !isCurrent(home),
              isCurrentStack(home.stack) else { return nil }
        Log.info("Window \(id), which has the focus, is on strip level \(home.level), out of view: "
                 + "that level comes into view")
        activeLevels[home.stack] = home.level
        if strips[home]?.contains(id) == true { strips[home]!.focus(window: id) }
        lastFocusedAt[id] = CFAbsoluteTimeGetCurrent()
        return home
    }

    /// The windows of a display that has returned and not settled yet that macOS already put back on it: those of every
    /// level archived when it was unplugged, in this session, wherever their strips are now (a level in view or not).
    private func windowsHeldForReturn(now: CFAbsoluteTime) -> Set<WindowID> {
        var held: Set<WindowID> = []
        for display in displays where returningDisplays[display.uuid] != nil && !presence.isSettled(display.uuid, now: now) {
            for saved in archive.strips where saved.displayUUID == display.uuid && saved.unplugged && saved.session == StateStore.session {
                for ref in saved.refs {
                    guard let record = windows[ref.id],
                          Displays.best(for: whereShown(record), in: displays)?.uuid == display.uuid else { continue }
                    held.insert(ref.id)
                }
            }
        }
        return held
    }

    /// Minimized, or its app hidden: the user cannot take it to another Space.
    private func isTuckedAway(_ id: WindowID) -> Bool {
        guard let record = windows[id] else { return false }
        return record.traits.isMinimized || NSRunningApplication(processIdentifier: record.pid)?.isHidden == true
    }

    /// `id`, a window of `key` that is not on screen, is on another Space (`spaces`, the ones macOS files it under):
    /// the user took it there in Mission Control, and it joins the strip in view of that Space. False when it stays:
    /// on no other Space Rambla manages, tucked away (`isTuckedAway`), or that Space's display not settled yet.
    private func followToItsSpace(_ id: WindowID, from key: StripKey, spaces: [UInt64], now: CFAbsoluteTime) -> Bool {
        guard !spaces.isEmpty, !spaces.contains(key.spaceID), !isTuckedAway(id),
              let target = spaces.lazy.compactMap({ self.stripKey(forSpace: $0) }).first, target != key,
              presence.isSettled(target.displayUUID, now: now) else { return false }
        let width = strips[key]!.location(of: id).map { strips[key]!.columns[$0.column].width } ?? .fraction(0.5)
        strips[key]!.remove(window: id)
        var other = strips[target] ?? Strip()
        other.insert(window: id, width: width, at: .end)
        strips[target] = other
        Log.info("Window \(id) moved to another Space")
        return true
    }

    /// A display that appears may take back, for `returnWindow`, the windows of its strips archived when it was
    /// unplugged. Once that time is up its strips are matched like any other saved strip, so a desktop visited later
    /// never pulls windows the user is working with somewhere else.
    private func followReturningDisplays(connectedBefore: Set<String>, now: CFAbsoluteTime) {
        let connected = Set(displays.map(\.uuid))
        for display in displays where !connectedBefore.contains(display.uuid) {
            returningDisplays[display.uuid] = now + DisplayPresence.settleDelay + Self.returnWindow
            Log.info("Display \(display.uuid.prefix(8)) appeared: \(display.name), \(Int(display.frame.width))×\(Int(display.frame.height)) "
                     + "at \(Int(display.frame.minX)),\(Int(display.frame.minY)), vendor \(CGDisplayVendorNumber(display.id)) "
                     + "model \(CGDisplayModelNumber(display.id))")
        }
        for (uuid, until) in returningDisplays {
            if !connected.contains(uuid) {
                returningDisplays[uuid] = nil
            } else if until <= now {
                returningDisplays[uuid] = nil
                archive.settle(displayUUID: uuid)
                placedAtUnpluggedLevel = placedAtUnpluggedLevel.filter { $0.value != uuid }
            } else {
                checkDisplaysAgain(after: until - now + 0.1)
            }
        }
    }

    /// macOS moves the windows of an unplugged display to the remaining ones, but they stayed in that display's strips,
    /// which no longer lay anything out: untiled and out of reach of the shortcuts. Once the display has been gone for
    /// `goneDisplayDelay`, its strips go to the archive, every level, and the windows join the same level of the
    /// displays they are on now (`reconcile`); when the display comes back, `restoreFromSavedState` takes them back to
    /// their places.
    private func dropStripsOfDisconnectedDisplays(now: TimeInterval) {
        let connected = Set(displays.map(\.uuid))
        for uuid in connected { displayGoneSince[uuid] = nil }
        guard !screensAreAsleep() else { return }
        for uuid in Set(strips.keys.map(\.displayUUID)) where !connected.contains(uuid) {
            let since = displayGoneSince[uuid] ?? now
            displayGoneSince[uuid] = since
            let delay = builtinDisplays.contains(uuid) && Self.lidIsClosed() ? Self.closedLidDelay : Self.goneDisplayDelay
            guard now - since >= delay else {
                checkDisplaysAgain(after: delay - (now - since) + 0.1)
                continue
            }
            for key in Array(strips.keys) where key.displayUUID == uuid { archiveStrip(key, unplugged: true) }
            rescanAll()
            displayGoneSince[uuid] = nil
            Log.info("Display \(uuid.prefix(8)) disconnected: its windows join the strips of the displays they are on until it comes back")
        }
    }

    /// A display that comes back before `goneDisplayDelay` can come back with new ids for its desktops, and a desktop
    /// can be removed: a strip whose desktop is no longer on its display would keep its windows out of reach. It goes
    /// to the archive (a display coming back takes it back under the desktop's new key) and its windows join the strips
    /// of the desktops they are on now.
    private func archiveStripsOfGoneSpaces() {
        var archived = false
        for display in displays {
            guard let current = display.currentSpace, display.spaceIDs.contains(current) else { continue }
            for key in Array(strips.keys) where key.displayUUID == display.uuid && !display.spaceIDs.contains(key.spaceID) {
                archiveStrip(key, unplugged: returningDisplays[display.uuid] != nil)
                archived = true
                let onLevel = key.level > 0 ? ", level \(key.level)" : ""
                Log.info("Desktop \(key.spaceID) is no longer on display \(display.uuid.prefix(8)): "
                         + "its strip goes to the archive\(onLevel)")
            }
        }
        if archived { rescanAll() }
    }

    /// Takes a strip out of the live state, into the archive when it holds windows of a known desktop. Rambla no longer
    /// places its windows, so the frames it asked for them are forgotten: the next listing reads where macOS put them.
    private func archiveStrip(_ key: StripKey, unplugged: Bool) {
        if let spaceKey = spaceKeys[key.stack], let strip = strips[key], !strip.columns.isEmpty {
            archive.store(SavedStrip(displayUUID: key.displayUUID, spaceKey: spaceKey, strip: strip, session: StateStore.session,
                                     refs: strip.allWindows.compactMap(ref), unplugged: unplugged,
                                     level: key.level, activeLevel: activeLevel(of: key.stack)), at: Date())
        }
        for id in strips[key]?.allWindows ?? [] { requested[id] = nil }
        strips[key] = nil
        results[key] = nil
        hidden[key] = nil
        releaseFloatShelf(of: key)
        // The stack goes with its last level: the other levels, archived after this one, still need its Space key and
        // the level in view. Once it is in view again, it is rebuilt from the archive.
        if !strips.keys.contains(where: { $0.stack == key.stack }) {
            spaceKeys[key.stack] = nil
            activeLevels[key.stack] = nil
            levelSwitchedAt[key.stack] = nil
            restoredStacks.remove(key.stack)
        }
    }

    /// The floating windows parked with `key`, a level that goes to the archive, float again as plain floating windows
    /// (the archive keeps strips only): back in their places when its display is still there (its desktop went away, or
    /// came back under another key), else where macOS put them (its display was unplugged).
    private func releaseFloatShelf(of key: StripKey) {
        guard let shelf = floatShelf.removeValue(forKey: key) else { return }
        let display = displays.first { $0.uuid == key.displayUUID }
        var frames: [WindowID: CGRect] = [:]
        for (id, parked) in shelf {
            requested[id] = nil
            if let display, windows[id] != nil { frames[id] = floatReturnFrame(parked, on: display) }
        }
        write(frames, verify: true)
        let place = display == nil ? "where macOS put them" : "in their places"
        Log.info("Strip level \(key.level) of display \(key.displayUUID.prefix(8)) went to the archive: "
                 + "its \(shelf.count) parked floating windows float again \(place)")
    }

    /// Removes an empty level that is no longer needed (`StripLevels.droppable`): its strip, its layout and its record
    /// of hidden windows. Level 0, the level in view and a level that still has windows always stay, whoever asks:
    /// floating windows parked with it (`floatShelf`) count, as they come back with it.
    func dropLevel(_ key: StripKey) {
        guard key.level != 0, key.level != activeLevel(of: key.stack), strips[key]?.columns.isEmpty ?? true,
              floatShelf[key]?.isEmpty ?? true else { return }
        strips[key] = nil
        results[key] = nil
        hidden[key] = nil
    }

    /// Strips of a display taken back from the archive (`restoreFromSavedState`): the windows that went back to their
    /// levels from them, as orphans, may do so again the next time that display leaves (`placedAtUnpluggedLevel`).
    func forgetUnpluggedPlacements(in taken: [SavedStrip]) {
        for strip in taken {
            for ref in strip.refs where placedAtUnpluggedLevel[ref.id] == strip.displayUUID {
                placedAtUnpluggedLevel[ref.id] = nil
            }
        }
    }

    /// Windows that move to another strip take along what is known of them being hidden (minimized, their app hidden):
    /// a level out of view is not looked at, and would lay them out as shown.
    func carryHidden(_ ids: [WindowID], from source: StripKey, to target: StripKey) {
        guard let moving = hidden[source]?.intersection(ids), !moving.isEmpty else { return }
        hidden[source]?.subtract(moving)
        if hidden[source]?.isEmpty == true { hidden[source] = nil }
        hidden[target, default: []].formUnion(moving)
    }

    /// A reconcile `delay` seconds from now, unless one is already due sooner: each reconcile asks again for what is
    /// still pending.
    private func checkDisplaysAgain(after delay: TimeInterval) {
        let at = CFAbsoluteTimeGetCurrent() + delay
        if displayCheck != nil, displayCheckAt <= at { return }
        displayCheck?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.displayCheck = nil
                self?.scheduleReconcile()
            }
        }
        displayCheck = item
        displayCheckAt = at
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
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
            guard let display = display(forStack: key.stack) else { return .fraction(0.5) }
            let available = display.visible.width - 2 * prefs.outerGap
            return .points(min(max(record.frame.width, available * 0.25), available))
        }
    }

    // MARK: - Layout application

    /// How much of a parked window stays on its display, in points.
    static let sliver: Double = 1

    func layoutInput(for key: StripKey, strip: Strip, display: DisplayInfo) -> LayoutInput {
        let viewport = display.visible.insetBy(dx: prefs.outerGap, dy: prefs.outerGap)
        var minSizes: [WindowID: CGSize] = [:]
        var originalHeights: [WindowID: Double] = [:]
        for id in strip.allWindows {
            if let size = windows[id]?.minSize { minSizes[id] = size }
            if let height = windows[id]?.originalHeight { originalHeights[id] = height }
        }
        return LayoutInput(
            strip: strip, viewport: viewport, display: display.frame, otherDisplays: otherDisplays(than: display),
            hidden: hidden[key] ?? [], minSizes: minSizes, originalHeights: originalHeights,
            config: LayoutConfig(gap: prefs.innerGap, tabBarHeight: 28, centerMode: prefs.centerMode,
                                 keepOriginalHeight: prefs.keepOriginalHeight, sliver: Self.sliver))
    }

    /// The frames of the displays besides `display`, which its windows park away from (with the tests' display that
    /// is not there, `debug-neighbor`).
    func otherDisplays(than display: DisplayInfo) -> [CGRect] {
        displays.filter { $0.uuid != display.uuid }.map(\.frame) + (testNeighbor.map { [$0] } ?? [])
    }

    func apply(_ key: StripKey, animate: Bool, verify: Bool = true) {
        guard isRunning, !isPaused, let strip = strips[key], let display = display(for: key),
              !prefs.disabledDisplays.contains(key.displayUUID) else { return }
        let input = layoutInput(for: key, strip: strip, display: display)
        let previous = results[key]
        let result = Layout.compute(input)
        results[key] = result
        var targets: [WindowID: CGRect] = [:]
        for (id, placement) in result.placements where !dragTracker.isFrozen(id) && !heldForReturn.contains(id) {
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
            var to: [WindowID: CGRect] = [:], from: [WindowID: CGRect] = [:], then: [WindowID: CGRect] = [:]
            var jumps: [WindowID: CGRect] = [:]
            for (id, frame) in changed {
                let now = animator.current[id] ?? windows[id]?.frame
                switch Layout.transition(of: id, at: now, to: result, from: previous, display: input.display,
                                         others: input.otherDisplays, sliver: input.config.sliver) {
                case .jump:
                    jumps[id] = frame
                case .animate(let start):
                    to[id] = frame
                    from[id] = start?.integral(keepingSize: true) ?? now
                case .exit(let through):
                    to[id] = through.integral(keepingSize: true)
                    from[id] = now
                    then[id] = frame
                }
            }
            if !jumps.isEmpty {
                jumps.keys.forEach(animator.cancel)
                write(jumps, verify: verify)
            }
            animator.animate(to: to, from: from, then: then)
        } else {
            changed.keys.forEach(animator.cancel)
            write(changed, verify: verify)
        }
        overlayHook?()
        scheduleSave()
    }

    /// Lays out a level that is not the one in view, of a stack whose display shows its Space: every window parked out
    /// of sight on a side edge (`Layout.shelved`). Only the frames that changed are written, and straight there, never
    /// animated across the display: the windows of a level that leaves the view jump to their parking spot, and a
    /// reconcile puts back what drifted. Windows being dragged, and those a display coming back will take, stay put.
    func shelve(_ key: StripKey) {
        guard isRunning, !isPaused, key.level != activeLevel(of: key.stack), let strip = strips[key],
              let display = display(forStack: key.stack), !prefs.disabledDisplays.contains(key.displayUUID) else { return }
        let result = Layout.shelved(layoutInput(for: key, strip: strip, display: display))
        results[key] = result
        var changed: [WindowID: CGRect] = [:]
        for (id, placement) in result.placements where !dragTracker.isFrozen(id) && !heldForReturn.contains(id) {
            let frame = placement.frame.integral(keepingSize: true)
            if !(requested[id]?.approximatelyEquals(frame, tolerance: 0.5) ?? false)
                || !(windows[id]?.frame.approximatelyEquals(frame, tolerance: 2) ?? false) {
                changed[id] = frame
            }
            requested[id] = frame
        }
        guard !changed.isEmpty else { return }
        changed.keys.forEach(animator.cancel)
        write(changed, verify: true)
    }

    /// Parks floating windows with `key`, the level that just left the view (`floatShelf`): each one goes straight to a
    /// side edge of its display, as the windows of that level do (`floatParkingFrame`), and its shelf keeps the frame
    /// it had for when the level comes back. `leaving` comes from `floatsInView`.
    func parkFloats(_ leaving: [WindowID: FloatShelf.Parked], with key: StripKey) {
        guard !leaving.isEmpty, let display = display(forStack: key.stack) else { return }
        var frames: [WindowID: CGRect] = [:]
        for (id, parked) in leaving {
            floatShelf[key, default: [:]][id] = parked
            let park = floatParkingFrame(parked, on: display)
            frames[id] = park
            requested[id] = park
        }
        write(frames, verify: true)
        Log.info("Parked \(leaving.count) floating windows with strip level \(key.level) of display "
                 + "\(key.displayUUID.prefix(8))")
    }

    /// The floating windows parked with `key`, a level in view now, go straight back to their places, and their order
    /// on screen stays as it is. Those not on screen (`shown`; the WindowServer's list of now when nil) wait on the
    /// shelf: a minimized one, or one of a hidden app, comes back once it shows again (`settleFloatShelves`). One that
    /// closed or no longer floats leaves the shelf. Returns those that came back.
    @discardableResult
    func bringBackFloats(of key: StripKey, shown: Set<WindowID>? = nil) -> [WindowID] {
        guard let shelf = floatShelf[key], let display = display(forStack: key.stack) else { return [] }
        let onScreen = shown ?? Self.windowIDs(onScreenOnly: true)
        var frames: [WindowID: CGRect] = [:]
        for (id, parked) in shelf {
            guard windows[id] != nil, floating.contains(id) else {
                floatShelf[key]?[id] = nil
                continue
            }
            guard onScreen.contains(id) else { continue }
            floatShelf[key]?[id] = nil
            requested[id] = nil
            frames[id] = floatReturnFrame(parked, on: display)
        }
        if floatShelf[key]?.isEmpty == true { floatShelf[key] = nil }
        guard !frames.isEmpty else { return [] }
        write(frames, verify: true)
        Log.info("Brought back \(frames.count) floating windows with strip level \(key.level) of display "
                 + "\(key.displayUUID.prefix(8))")
        return Array(frames.keys)
    }

    /// Where a parked floating window waits on `display` (`FloatShelf.parkingFrame`), with the other displays and the
    /// sliver of the strips' windows.
    func floatParkingFrame(_ parked: FloatShelf.Parked, on display: DisplayInfo) -> CGRect {
        FloatShelf.parkingFrame(parked, display: display.frame, others: otherDisplays(than: display),
                                sliver: Self.sliver).integral(keepingSize: true)
    }

    /// Where a parked floating window comes back on `display` (`FloatShelf.returnFrame`): the frame it had, unless the
    /// display changed meanwhile.
    func floatReturnFrame(_ parked: FloatShelf.Parked, on display: DisplayInfo) -> CGRect {
        let frame = FloatShelf.returnFrame(parked, display: display.frame, visible: display.visible,
                                           displays: displays.map(\.frame))
        return frame == parked.frame ? frame : frame.integral(keepingSize: true)
    }

    /// Brings a window that no strip lays out into view when most of it lies off every display (`FloatShelf.inView`),
    /// onto the display it is mostly on, else the first one, as "Traer todas las ventanas" would a floating one. A
    /// saved floating one restored after Rambla stopped without bringing it back (a crash, Force Quit) may still be
    /// parked on an edge, and so may one that left its strip while parked, as it is no longer tiled (an app rule).
    func bringInIfOffScreen(_ id: WindowID) {
        guard let record = windows[id] else { return }
        let frame = whereShown(record)
        guard let display = Displays.best(for: frame, in: displays) ?? displays.first else { return }
        let target = FloatShelf.inView(frame, visible: display.visible, displays: displays.map(\.frame))
        guard target != frame else { return }
        let rounded = target.integral(keepingSize: true)
        Log.info("Window \(id), in no strip, lies off every display at \(Self.describe(frame)): "
                 + "it comes into view at \(Self.describe(rounded))")
        requested[id] = nil
        write([id: rounded], verify: true)
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
    /// One parked with a level out of view (`floatShelf`) goes back into the strip of that level, out of view with it:
    /// as an orphan it would join the level in view instead.
    func relayoutAll() {
        guard isRunning, !isPaused else { return }
        var levels: Set<StripKey> = []
        for id in autoFloated {
            guard let parked = takeFromFloatShelf(id), let record = windows[id] else { continue }
            insert(record, into: parked.key)
            levels.insert(parked.key)
            Log.info("Window \(id), floating with strip level \(parked.key.level), goes back into that strip")
        }
        floating.subtract(autoFloated)
        autoFloated.removeAll()
        requested.removeAll()
        for key in levels {
            if isCurrent(key) { apply(key, animate: true) } else { shelve(key) }
        }
        rescanAll()
        scheduleReconcile()
    }

    /// Moves every window that is parked or sticking out of its display back into the visible area. With `only`, just
    /// those of these displays (the ones Rambla stops or starts managing): the strips of the others, and the floating
    /// windows parked with them, stay as they are, out of sight where they are out of view.
    func gatherAll(synchronously: Bool, only: Set<String>? = nil) {
        /// The windows of display `uuid` are gathered: those of every display, or of the ones in `only`.
        func gathers(_ uuid: String?) -> Bool {
            guard let only else { return true }
            return uuid.map(only.contains) ?? false
        }
        if let only {
            for (key, strip) in strips where only.contains(key.displayUUID) {
                strip.allWindows.forEach(animator.cancel)
            }
        } else {
            animator.cancelAll()
        }
        // Every window Rambla knows a place for: the strips' (an unplugged display's too, whose display is gone) and the
        // floating ones (a strip window Rambla parked and another app then moved stays half off screen).
        var gathered = Set<WindowID>()
        func gather(_ id: WindowID, onto display: DisplayInfo?) {
            guard gathered.insert(id).inserted, let frame = requested[id] ?? windows[id]?.frame, let pid = windows[id]?.pid,
                  let display = display ?? Displays.best(for: frame, in: displays) ?? displays.first else { return }
            let area = display.visible
            guard !area.insetBy(dx: -1, dy: -1).contains(frame) else { return }
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
        // The floating windows parked with a level out of view come back to their places first, as plain floating
        // windows from now on, and so do those let go on another desktop that have not shown there yet. Those of a
        // display that is gone stay where macOS put them; like every floating window, one that lies mostly off every
        // display is brought in below.
        func bringBack(_ id: WindowID, _ parked: FloatShelf.Parked, on display: DisplayInfo?) -> Bool {
            requested[id] = nil
            guard let display, let pid = windows[id]?.pid else { return false }
            let frame = floatReturnFrame(parked, on: display)
            if synchronously {
                windows[id]?.frame = frame
                workers[pid]?.setFrameSynchronously(id, frame)
            } else {
                write([id: frame], verify: true)
            }
            return true
        }
        for (key, shelf) in floatShelf where gathers(key.displayUUID) {
            let display = displays.first { $0.uuid == key.displayUUID }
            var back = 0
            for (id, parked) in shelf where bringBack(id, parked, on: display) { back += 1 }
            floatShelf[key] = nil
            guard back > 0 else { continue }
            Log.info("Brought back \(back) floating windows with strip level \(key.level) of display "
                     + "\(key.displayUUID.prefix(8))")
        }
        for (id, parked) in floatsAway {
            // On the display it is on, where it still waits at its parking spot.
            let display = windows[id].flatMap { Displays.best(for: whereShown($0), in: displays) } ?? displays.first
            guard gathers(display?.uuid) else { continue }
            _ = bringBack(id, parked, on: display)
            floatsAway[id] = nil
        }
        for (key, strip) in strips where gathers(key.displayUUID) {
            let display = displays.first(where: { $0.uuid == key.displayUUID })
            for id in strip.allWindows { gather(id, onto: display) }
        }
        // A floating window only when most of it is off every display: one the user left across two stays there. One
        // still parked with a level of a display left as it is stays parked.
        let stillParked = Set(floatShelf.values.flatMap(\.keys)).union(floatsAway.keys)
        for id in floating where !stillParked.contains(id) {
            guard let frame = requested[id] ?? windows[id]?.frame,
                  gathers((Displays.best(for: frame, in: displays) ?? displays.first)?.uuid) else { continue }
            let shown = displays.reduce(0.0) { sum, display in
                let part = frame.intersection(display.frame)
                return sum + (part.isNull ? 0 : part.width * part.height)
            }
            if shown < frame.width * frame.height / 2 { gather(id, onto: nil) }
        }
        if let only {
            results = results.filter { !only.contains($0.key.displayUUID) }
        } else {
            results.removeAll()
        }
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
        guard !isPaused else { return }
        guard let key = key(containing: id) else {
            // A floating window: one the user drags stays in view through a level switch, and where one let go on
            // another desktop goes is the user's from then on. One parked with a level out of view goes back to its
            // parking spot.
            if mouseDown, floating.contains(id) {
                draggedFloat = id
                floatsAway[id] = nil
            }
            if let shelf = floatShelfKey(holding: id) {
                parkedFloatMoved(id, frame, from: previous, mouseDown: mouseDown, with: shelf)
            }
            return
        }
        // macOS is moving the windows of a display that went away; they join another strip once it is gone for good.
        guard displays.contains(where: { $0.uuid == key.displayUUID }) else { return }
        if key.level != activeLevel(of: key.stack) {
            shelvedWindowMoved(id, frame, from: previous, mouseDown: mouseDown, in: key)
            return
        }
        if mouseDown {
            dragTracker.began(id, startFrame: requested[id] ?? previous ?? frame)
            worker(for: id)?.freeze(id, true)
            animator.cancel(id)
            return
        }
        guard !dragTracker.isFrozen(id) else { return }
        // Exactly where Rambla put it: the app reported Rambla's own move late (it applies AX writes asynchronously).
        if let wanted = requested[id], frame.approximatelyEquals(wanted, tolerance: 2) { return }
        if inGrace {
            // macOS moving windows while it changes the displays or the Space (one that spanned two displays, one
            // parked past an edge) is not another app's move: once it is done, the strips put them back in place.
            Log.info("Window \(id) moved by macOS from \(Self.describe(requested[id] ?? previous ?? frame)) "
                     + "to \(Self.describe(frame)) while the displays changed: it goes back to its place")
            checkDisplaysAgain(after: graceUntil - CFAbsoluteTimeGetCurrent() + 0.1)
            return
        }
        // macOS putting a hidden window back by itself (back from the Dock, its app unhidden): it goes back to its place
        // in the strip instead of floating.
        if hidden[key]?.contains(id) == true || (reappearing[id] ?? 0) > CFAbsoluteTimeGetCurrent() {
            apply(key, animate: true)
            return
        }
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

    /// A window of a level out of view moved: its app restoring or rearranging its frame, macOS putting it back from
    /// the Dock or with its app shown again, or moving it while the displays change. None of that floats it or changes
    /// its size in the strip: it goes back to its parking spot. Only the user focusing it brings its level into view.
    private func shelvedWindowMoved(_ id: WindowID, _ frame: CGRect, from previous: CGRect?, mouseDown: Bool,
                                    in key: StripKey) {
        // The mouse is down (its sliver dragged, or the button held for something else), or the window is being
        // dragged: it stays until a later pass parks it again. A stack out of view is parked again once it is in view.
        guard !mouseDown, !dragTracker.isFrozen(id), isCurrentStack(key.stack) else { return }
        // Exactly where Rambla parked it: its own move, reported late.
        if let wanted = requested[id], frame.approximatelyEquals(wanted, tolerance: 2) { return }
        let reference = requested[id] ?? previous ?? frame
        if inGrace {
            // As for the windows in view: once the displays are done changing, the reconcile parks it again.
            Log.info("Window \(id) moved by macOS from \(Self.describe(reference)) "
                     + "to \(Self.describe(frame)) while the displays changed: it goes back to its place")
            checkDisplaysAgain(after: graceUntil - CFAbsoluteTimeGetCurrent() + 0.1)
            return
        }
        let byMacOS = hidden[key]?.contains(id) == true || (reappearing[id] ?? 0) > CFAbsoluteTimeGetCurrent()
        Log.info("Window \(id) of strip level \(key.level) moved by \(byMacOS ? "macOS" : "another app") "
                 + "from \(Self.describe(reference)) to \(Self.describe(frame)): back to its place")
        shelve(key)
    }

    /// A floating window parked with a level out of view (`floatShelf`) moved: its app rearranging it, macOS putting it
    /// back from the Dock or with its app shown again, or moving it while the displays change. As for the windows of
    /// that level (`shelvedWindowMoved`), that is no new place for it: it goes back to its parking spot, and only its
    /// level coming into view brings it back to the place it had.
    private func parkedFloatMoved(_ id: WindowID, _ frame: CGRect, from previous: CGRect?, mouseDown: Bool,
                                  with key: StripKey) {
        // The mouse is down (its sliver dragged), or its stack is out of view (another desktop, or its display gone for
        // now): a later pass parks it again. Parked with the level in view (it was hidden when that level came back),
        // it comes back to its place with the next pass.
        guard !mouseDown, isCurrentStack(key.stack), let display = display(forStack: key.stack),
              let parked = floatShelf[key]?[id] else { return }
        guard !isCurrent(key) else {
            scheduleReconcile()
            return
        }
        let park = floatParkingFrame(parked, on: display)
        // Exactly where Rambla parked it: its own move, reported late.
        if frame.approximatelyEquals(park, tolerance: 2) { return }
        let reference = requested[id] ?? previous ?? frame
        if inGrace {
            // As for the windows of its level: once the displays are done changing, the reconcile parks it again.
            Log.info("Floating window \(id) moved by macOS from \(Self.describe(reference)) "
                     + "to \(Self.describe(frame)) while the displays changed: it goes back to its place")
            checkDisplaysAgain(after: graceUntil - CFAbsoluteTimeGetCurrent() + 0.1)
            return
        }
        let byMacOS = (reappearing[id] ?? 0) > CFAbsoluteTimeGetCurrent()
        Log.info("Floating window \(id) parked with strip level \(key.level) moved by "
                 + "\(byMacOS ? "macOS" : "another app") from \(Self.describe(reference)) to \(Self.describe(frame)): "
                 + "back to its place")
        requested[id] = park
        write([id: park], verify: true)
    }

    /// The floating windows parked with the levels out of view of the stacks in view (`floatShelf`) stay out of sight,
    /// as the windows of those levels do (`shelve`): what drifted (moved by its app, or by macOS while the displays
    /// changed) goes back to its parking spot, and nothing is written when nothing did. Those parked with a level in
    /// view (hidden when it came back, or a stack rebuilt with another level in view) come back to their places. Either
    /// way, only once they show (`visible`): a window that is minimized, or of a hidden app, waits on its shelf. One
    /// being dragged stays under the pointer.
    ///
    /// One that left the desktop of its level is let go (`letGoFloatsAway`): out of sight on a desktop in view while
    /// macOS files it under another one, or on screen while its display shows another desktop.
    private func settleFloatShelves(inView keys: [StripKey], visible: Set<WindowID>) {
        let dragging = dragTracker.isMouseDown ? draggedFloat : nil
        var maybeAway: [WindowID] = []
        for key in Array(floatShelf.keys) {
            guard isCurrentStack(key.stack), let display = display(forStack: key.stack) else {
                // Its display shows another desktop: one of them on screen there may be on that desktop.
                if enabledDisplays.contains(where: { $0.uuid == key.displayUUID }) {
                    maybeAway += (floatShelf[key] ?? [:]).keys.filter { visible.contains($0) && $0 != dragging }
                }
                continue
            }
            let inView = keys.contains(key)
            if inView { bringBackFloats(of: key, shown: visible) }
            var drifted: [WindowID: CGRect] = [:]
            for (id, parked) in floatShelf[key] ?? [:] where id != dragging {
                guard visible.contains(id) else {
                    // Out of sight, and not because it is minimized, its app hidden or in full screen: it may be on
                    // another desktop.
                    if !isTuckedAway(id), windows[id]?.traits.isFullscreen != true { maybeAway.append(id) }
                    continue
                }
                guard !inView else { continue }
                let park = floatParkingFrame(parked, on: display)
                if !(requested[id]?.approximatelyEquals(park, tolerance: 0.5) ?? false)
                    || !(windows[id]?.frame.approximatelyEquals(park, tolerance: 2) ?? false) {
                    drifted[id] = park
                }
                requested[id] = park
            }
            write(drifted, verify: true)
        }
        letGoFloatsAway(maybeAway)
        placeFloatsAway(visible: visible)
    }

    /// Of `ids`, parked floating windows that may have left the desktop of their level, those macOS files under another
    /// desktop, or under several (assigned to all of them), are let go: the user took them there in Mission Control,
    /// as strip windows follow (`followToItsSpace`). Only outside the grace of a display or desktop change, when macOS
    /// files windows under other desktops by itself: the reconcile after it looks again. The one with the focus, when
    /// it is not shown (`isShown`), does not keep the keyboard out of sight: it goes on to a window in view, as in
    /// `focusChanged`.
    private func letGoFloatsAway(_ ids: [WindowID]) {
        guard !ids.isEmpty else { return }
        guard !inGrace else {
            checkDisplaysAgain(after: graceUntil - CFAbsoluteTimeGetCurrent() + 0.1)
            return
        }
        let spaces = Private.spaces(for: ids)
        for id in ids {
            guard let key = floatShelfKey(holding: id),
                  FloatShelf.isAway(spaces: spaces[id] ?? [], from: key.spaceID) else { continue }
            letGo(id, from: key)
            if id == focusedWindow, !isShown(id, on: spaces[id] ?? []) {
                let inView = displays.first { $0.uuid == key.displayUUID }.flatMap(currentKey)
                handKeyboardOn(from: id, to: inView.flatMap { isCurrent($0) ? $0 : nil },
                               report: "Floating window \(id), which has the focus, is on a desktop not shown")
            }
        }
    }

    /// `id`, parked with `key`, left the desktop of that level: it leaves its shelf and floats where it is now, at its
    /// place as soon as it shows (`placeFloatsAway`).
    private func letGo(_ id: WindowID, from key: StripKey) {
        guard let taken = takeFromFloatShelf(id) else { return }
        floatsAway[id] = taken.parked
        requested[id] = nil
        Log.info("Floating window \(id), parked with strip level \(key.level), is on another desktop now: "
                 + "it floats there")
    }

    /// The floating windows let go on another desktop (`floatsAway`) that show now go to their places there, on the
    /// display they show on (`floatReturnFrame`). Outside the grace of a display or desktop change, as macOS may still
    /// be moving them, and not while one is dragged.
    private func placeFloatsAway(visible: Set<WindowID>) {
        guard !floatsAway.isEmpty else { return }
        let dragging = dragTracker.isMouseDown ? draggedFloat : nil
        var frames: [WindowID: CGRect] = [:]
        var waiting = false
        for (id, parked) in floatsAway {
            guard let record = windows[id], floating.contains(id) else {
                floatsAway[id] = nil
                continue
            }
            guard visible.contains(id), id != dragging,
                  let display = Displays.best(for: whereShown(record), in: displays) ?? displays.first else { continue }
            guard !inGrace else {
                waiting = true
                continue
            }
            frames[id] = floatReturnFrame(parked, on: display)
            floatsAway[id] = nil
        }
        if waiting { checkDisplaysAgain(after: graceUntil - CFAbsoluteTimeGetCurrent() + 0.1) }
        guard !frames.isEmpty else { return }
        write(frames, verify: true)
        Log.info("Put \(frames.count) floating windows let go on another desktop at their places there")
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
        // A window of a level out of view floats on the display of its stack too, instead of where it was parked.
        if center, let display = display(forStack: key.stack), let frame = windows[id]?.frame {
            let area = display.visible
            let size = CGSize(width: min(frame.width, area.width * 0.8), height: min(frame.height, area.height * 0.8))
            let target = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                width: size.width, height: size.height).integral(keepingSize: true)
            write([id: target], verify: true)
            worker(for: id)?.raise(id)
        }
        if isCurrent(key) { apply(key, animate: true) } else { shelve(key) }
        onStateChanged?()
    }

    // MARK: - Mouse drags

    private func mouseUp(at point: CGPoint) {
        draggedFloat = nil
        // The level of a window that got the focus while the button was down comes into view now, if that window still
        // has the focus and its level is still out of view (for a floating window, the level it is parked with).
        if let id = pendingLevelSwitch {
            pendingLevelSwitch = nil
            if focusedWindow == id, let key = key(containing: id) ?? floatShelfKey(holding: id), !isCurrent(key),
               isCurrentStack(key.stack) {
                followFocus(to: id, in: key)
            }
        }
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

/// What `afterPendingMoves` waits for: the apps that have not made their moves yet, and what to call, once, when none
/// is left or the wait is over.
@MainActor
private final class PendingMoves {
    private var apps: Int
    private var done: (() -> Void)?

    init(apps: Int, done: @escaping () -> Void) {
        self.apps = apps
        self.done = done
        if apps == 0 { finish() }
    }

    func appDone() {
        apps -= 1
        if apps == 0 { finish() }
    }

    func finish() {
        let done = self.done
        self.done = nil
        done?()
    }
}

extension CGRect {
    /// Whole-point origin; size rounded so apps that snap to integers agree with the request.
    func integral(keepingSize: Bool) -> CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }
}
