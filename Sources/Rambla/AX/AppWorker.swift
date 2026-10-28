import AppKit
import ApplicationServices
import RamblaCore

private let windowNotifications: [String] = [
    kAXUIElementDestroyedNotification,
    kAXWindowMovedNotification,
    kAXWindowResizedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
    kAXTitleChangedNotification,
]

private let observerCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    Unmanaged<AppWorker>.fromOpaque(refcon).takeUnretainedValue().handle(element, notification as String)
}

/// Owns every Accessibility call for one app, on a dedicated thread with its own run loop, so a hung
/// app only blocks itself. All `private` state below is touched only on that thread, except the
/// lock-guarded pending writes.
final class AppWorker: @unchecked Sendable {
    let pid: pid_t
    let bundleID: String?
    private let isRegular: Bool
    private let emitOnMain: (AXEvent) -> Void
    private let app: AXUIElement

    private var runLoop: CFRunLoop?
    private var observer: AXObserver?
    private var windows: [WindowID: AXUIElement] = [:]
    private var ids: [AXElementKey: WindowID] = [:]
    private var lastFrames: [WindowID: CGRect] = [:]
    private var lastWrite: [WindowID: CFAbsoluteTime] = [:]
    /// Windows whose position is not known for sure: the frame read back after a write was not the one written (an app
    /// that applies moves late), or the app did not answer. Their size read back stays known.
    private var originUnknown: Set<WindowID> = []
    /// The last frame written to each window, and every one written in the last moments: a notice of an earlier one,
    /// within the echo window of the last, is an earlier write applied late.
    private var lastTarget: [WindowID: CGRect] = [:]
    private var written = FrameEchoes()
    /// Windows to read again once the echo window of their last write is over (`recheck`).
    private var recheckPending: Set<WindowID> = []
    /// Test mode only (`debugUnseenMove`): windows whose notices go unheard until then.
    private var muted: [WindowID: CFAbsoluteTime] = [:]
    private var frozen: Set<WindowID> = []
    private var titlePending: Set<WindowID> = []
    private var stopped = false

    private let lock = NSLock()
    private var pending: [WindowID: (frame: CGRect, verify: Bool, force: Bool)] = [:]
    private var drainScheduled = false

    /// Notifications that arrive this soon after our own write are echoes of it.
    private static let echoWindow: CFAbsoluteTime = 0.25

    init(pid: pid_t, bundleID: String?, isRegular: Bool, emit: @escaping (AXEvent) -> Void) {
        self.pid = pid
        self.bundleID = bundleID
        self.isRegular = isRegular
        self.emitOnMain = emit
        self.app = AXUIElementCreateApplication(pid)
    }

    // MARK: - Lifecycle

    func start() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            var context = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)
            CFRunLoopAddSource(runLoop, keepAlive, .defaultMode)
            ready.signal()
            setUp(attempt: 0)
            while !stopped {
                CFRunLoopRunInMode(.defaultMode, 3600, false)
            }
        }
        thread.name = "ax.\(pid).\(bundleID ?? "?")"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func stop() {
        perform { [self] in
            if let observer {
                CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
            }
            observer = nil
            windows.removeAll()
            ids.removeAll()
            stopped = true
            CFRunLoopStop(runLoop)
        }
    }

    private func perform(_ block: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    private func perform(after delay: TimeInterval, _ block: @escaping () -> Void) {
        guard let runLoop else { return }
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { _ in block() }
        CFRunLoopAddTimer(runLoop, timer, .defaultMode)
    }

    private func emit(_ event: AXEvent) {
        DispatchQueue.main.async { [emitOnMain] in emitOnMain(event) }
    }

    /// Apps that are still launching refuse observers and report no windows; retry with backoff.
    private func setUp(attempt: Int) {
        guard !stopped else { return }
        let delays: [TimeInterval] = [0.1, 0.3, 1, 3]
        if observer == nil {
            var created: AXObserver?
            if AXObserverCreate(pid, observerCallback, &created) == .success, let created {
                let refcon = Unmanaged.passUnretained(self).toOpaque()
                let a = AXObserverAddNotification(created, app, kAXWindowCreatedNotification as CFString, refcon)
                let b = AXObserverAddNotification(created, app, kAXFocusedWindowChangedNotification as CFString, refcon)
                if a == .success || b == .success {
                    CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(created), .defaultMode)
                    observer = created
                }
            }
        }
        if observer == nil || AX.windows(of: app) == nil {
            if attempt < delays.count {
                perform(after: delays[attempt]) { [self] in setUp(attempt: attempt + 1) }
            } else {
                Log.info("App \(bundleID ?? "\(pid)") is not accessible; ignoring it")
            }
            if observer == nil { return }
        }
        rescanNow()
        refreshFocusedNow()
    }

    // MARK: - Commands from the main thread

    /// Coalesced: the latest frame per window wins and one drain runs per run-loop turn.
    /// `verify` reads the frame back (used for final positions, skipped for animation frames). `force` writes it even
    /// where the worker last saw the window there: the window moved without a word from its app.
    func setFrames(_ frames: [WindowID: CGRect], verify: Bool = true, force: Bool = false) {
        lock.lock()
        for (id, frame) in frames { pending[id] = (frame, verify, force || pending[id]?.force == true) }
        let schedule = !drainScheduled
        drainScheduled = true
        lock.unlock()
        if schedule { perform { [self] in drain() } }
    }

    func freeze(_ id: WindowID, _ isFrozen: Bool) {
        perform { [self] in
            if isFrozen { frozen.insert(id) } else { frozen.remove(id) }
        }
    }

    func focus(_ id: WindowID) {
        perform { [self] in
            guard let element = windows[id] else { return }
            let focused = Private.focus(pid: pid, window: id)
            AX.makeMain(element)
            AX.raise(element)
            if !focused {
                DispatchQueue.main.async { [pid] in
                    NSRunningApplication(processIdentifier: pid)?.activate()
                }
            }
        }
    }

    func raise(_ id: WindowID) {
        perform { [self] in
            if let element = windows[id] { AX.raise(element) }
        }
    }

    func close(_ id: WindowID) {
        perform { [self] in
            if let element = windows[id] { AX.close(element) }
        }
    }

    func refreshFocused() {
        perform { [self] in refreshFocusedNow() }
    }

    func rescan() {
        perform { [self] in rescanNow() }
    }

    /// The main thread found that the WindowServer no longer has this window.
    func forgetWindow(_ id: WindowID) {
        perform { [self] in
            if let element = windows[id] { forget(id, element, notify: false) }
        }
    }

    func readFrame(_ id: WindowID, _ completion: @escaping (CGRect?) -> Void) {
        perform { [self] in
            let frame = windows[id].flatMap(AX.frame)
            if let frame {
                lastFrames[id] = frame
                originUnknown.remove(id)
            }
            DispatchQueue.main.async { completion(frame) }
        }
    }

    /// Reads the address of the page a browser window shows (`AX.pageURL`), and calls `completion` with it on the main
    /// thread: nil when it shows none, or is gone.
    func readPage(_ id: WindowID, _ completion: @escaping (URL?) -> Void) {
        perform { [self] in
            let url = windows[id].flatMap { AX.pageURL($0) }
            DispatchQueue.main.async { completion(url) }
        }
    }

    /// Calls `done` on the main thread once this worker has done everything asked of it before, the frame writes
    /// included: it takes them in order.
    func afterPendingWork(_ done: @escaping @Sendable () -> Void) {
        perform { DispatchQueue.main.async(execute: done) }
    }

    /// Test hook: moves a window the way another app (e.g. Rectangle) would, bypassing Rambla's own
    /// bookkeeping, so the move reaches the engine as an external change.
    func debugExternalMove(_ id: WindowID, _ frame: CGRect) {
        perform { [self] in
            guard let element = windows[id] else { return }
            AX.setSize(element, frame.size)
            AX.setPosition(element, frame.origin)
        }
    }

    /// Test mode only: moves window `id` with no word of it reaching the main thread, nor this worker's record of where
    /// the window is, as macOS can when a display appears.
    func debugUnseenMove(_ id: WindowID, _ frame: CGRect) {
        perform { [self] in
            guard let element = windows[id] else { return }
            muted[id] = CFAbsoluteTimeGetCurrent() + 0.5
            AX.setSize(element, frame.size)
            AX.setPosition(element, frame.origin)
        }
    }

    /// Synchronous write used while quitting, when the main thread must not return before windows are visible.
    func setFrameSynchronously(_ id: WindowID, _ frame: CGRect) {
        let done = DispatchSemaphore(value: 0)
        perform { [self] in
            if let element = windows[id] {
                AX.setPosition(element, frame.origin)
                AX.setSize(element, frame.size)
                AX.setPosition(element, frame.origin)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    // MARK: - Worker-thread internals

    private func drain() {
        lock.lock()
        let batch = pending
        pending.removeAll()
        drainScheduled = false
        lock.unlock()
        guard !batch.isEmpty else { return }

        let enhanced = AX.enhancedUserInterface(app)
        if enhanced { AX.setEnhancedUserInterface(app, false) }
        defer { if enhanced { AX.setEnhancedUserInterface(app, true) } }

        for (id, request) in batch {
            guard let element = windows[id], !frozen.contains(id) else { continue }
            let target = request.frame
            let current = lastFrames[id]
            // A forced write goes where the worker's record is stale by definition: size and position, read back.
            let sizeChanged = request.force
                || (current.map { abs($0.width - target.width) > 0.5 || abs($0.height - target.height) > 0.5 } ?? true)
            let originChanged = originUnknown.contains(id)
                || (current.map { abs($0.minX - target.minX) > 0.5 || abs($0.minY - target.minY) > 0.5 } ?? true)
            guard request.force || sizeChanged || originChanged else { continue }
            let now = CFAbsoluteTimeGetCurrent()
            lastWrite[id] = now
            lastTarget[id] = target
            written.asked(target, of: id, at: now)
            if sizeChanged {
                // Size, position, size: a large window may not fit at its old position (Rectangle's approach).
                AX.setSize(element, target.size)
                AX.setPosition(element, target.origin)
            } else {
                AX.setPosition(element, target.origin)
            }
            var actual = target
            var answered = true
            if request.verify || sizeChanged {
                if let read = AX.frame(element) {
                    actual = read
                    if sizeChanged, !actual.size.approximatelyEquals(target.size, tolerance: 1) {
                        AX.setSize(element, target.size)
                        actual = AX.frame(element) ?? actual
                    }
                } else {
                    answered = false
                }
            }
            // A frame read back that is not the one written may only be the app not done yet (Electron apps apply
            // moves late), and an app that does not answer may not have moved at all: the size read back stays known,
            // the position does not, so the next write is not skipped as one already made.
            let applied = answered && actual.approximatelyEquals(target, tolerance: 2)
            lastFrames[id] = actual
            if applied { originUnknown.remove(id) } else { originUnknown.insert(id) }
            if answered, !applied {
                emit(.applied(pid, id, actual))
            }
        }
    }

    /// Once the echo window of the last write to window `id` is over: if the window is still at a frame written before
    /// that one, the main thread hears of it. A newer write gets its own echo window first.
    private func recheck(_ id: WindowID) {
        recheckPending.remove(id)
        guard let element = windows[id], !frozen.contains(id), let frame = AX.frame(element) else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if let at = lastWrite[id], now - at < Self.echoWindow {
            recheckPending.insert(id)
            perform(after: at + Self.echoWindow + 0.05 - now) { [self] in recheck(id) }
            return
        }
        guard let target = lastTarget[id], !frame.approximatelyEquals(target, tolerance: 2),
              written.isOwn(frame, of: id, at: now) else { return }
        lastFrames[id] = frame
        originUnknown.remove(id)
        // A frame Rambla wrote, whatever the mouse is doing: never the start of a drag.
        emit(.frameChanged(pid, id, frame, mouseDown: false))
    }

    /// AX only lists windows of the active Spaces, so a missing window is not a closed one: windows are
    /// forgotten only on a destroy notification (the main thread also drops ids gone from the WindowServer).
    private func rescanNow() {
        guard let list = AX.windows(of: app) else { return }
        emit(.appWindows(pid, list.compactMap { register($0) }))
    }

    private func refreshFocusedNow() {
        let id = AX.focusedWindow(of: app).flatMap { ids[AXElementKey($0)] ?? Private.windowID(of: $0) }
        emit(.focusedWindow(pid, id))
    }

    @discardableResult
    private func register(_ element: AXUIElement) -> WindowSnapshot? {
        guard let id = Private.windowID(of: element) else { return nil }
        if windows[id] == nil {
            windows[id] = element
            ids[AXElementKey(element)] = id
            if let observer {
                let refcon = Unmanaged.passUnretained(self).toOpaque()
                for name in windowNotifications {
                    AXObserverAddNotification(observer, element, name as CFString, refcon)
                }
            }
        }
        let read = AX.frame(element)
        let frame = read ?? .zero
        lastFrames[id] = frame
        if read == nil { originUnknown.insert(id) } else { originUnknown.remove(id) }
        return WindowSnapshot(id: id, pid: pid,
                              traits: AX.traits(of: element, bundleID: bundleID, appIsRegular: isRegular),
                              frame: frame, title: AX.title(element))
    }

    private func forget(_ id: WindowID, _ element: AXUIElement, notify: Bool = true) {
        if let observer {
            for name in windowNotifications {
                AXObserverRemoveNotification(observer, element, name as CFString)
            }
        }
        windows[id] = nil
        ids[AXElementKey(element)] = nil
        lastFrames[id] = nil
        lastWrite[id] = nil
        originUnknown.remove(id)
        lastTarget[id] = nil
        written.forget(id)
        recheckPending.remove(id)
        muted[id] = nil
        frozen.remove(id)
        if notify { emit(.windowDestroyed(pid, id)) }
    }

    /// New windows sometimes have no id or role yet; retry briefly before giving up.
    private func discoverCreated(_ element: AXUIElement, attempt: Int) {
        guard !stopped else { return }
        let delays: [TimeInterval] = [0.05, 0.2, 0.5]
        if AX.string(element, kAXRoleAttribute) == kAXWindowRole, let snapshot = register(element) {
            emit(.windowCreated(snapshot))
            return
        }
        if attempt < delays.count {
            perform(after: delays[attempt]) { [self] in discoverCreated(element, attempt: attempt + 1) }
        }
    }

    fileprivate func handle(_ element: AXUIElement, _ notification: String) {
        switch notification {
        case kAXWindowCreatedNotification:
            discoverCreated(element, attempt: 0)
        case kAXFocusedWindowChangedNotification:
            refreshFocusedNow()
        case kAXUIElementDestroyedNotification:
            if let id = ids[AXElementKey(element)] { forget(id, element) }
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let id = ids[AXElementKey(element)], let frame = AX.frame(element) else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if let until = muted[id] {
                if now < until { return }
                muted[id] = nil
            }
            if !originUnknown.contains(id), let last = lastFrames[id], frame.approximatelyEquals(last, tolerance: 2) {
                return
            }
            lastFrames[id] = frame
            originUnknown.remove(id)
            if let at = lastWrite[id], now - at < Self.echoWindow, !frozen.contains(id) {
                // Most likely Rambla's own write settling. A frame written before the last one, though, is an earlier
                // write applied late (Electron apps): if the window is still there once this write had its time, the
                // main thread hears of it, so that the window goes where Rambla wants it.
                if let target = lastTarget[id], !frame.approximatelyEquals(target, tolerance: 2),
                   written.isOwn(frame, of: id, at: now), recheckPending.insert(id).inserted {
                    perform(after: at + Self.echoWindow + 0.05 - now) { [self] in recheck(id) }
                }
                return
            }
            let mouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
            emit(.frameChanged(pid, id, frame, mouseDown: mouseDown))
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            if let id = ids[AXElementKey(element)] {
                emit(.minimized(pid, id, notification == kAXWindowMiniaturizedNotification))
            }
        case kAXTitleChangedNotification:
            // Coalesced: some apps (terminals with spinners) change their title several times a second.
            guard let id = ids[AXElementKey(element)], !titlePending.contains(id) else { return }
            titlePending.insert(id)
            perform(after: 0.5) { [self] in
                titlePending.remove(id)
                if let element = windows[id] { emit(.titleChanged(pid, id, AX.title(element))) }
            }
        default:
            break
        }
    }
}

extension CGRect {
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

extension CGSize {
    func approximatelyEquals(_ other: CGSize, tolerance: CGFloat) -> Bool {
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
