import AppKit
import QuartzCore
import RamblaCore

/// The veil over a switch between stacked strips (`LevelTransition`): a sheet of frosted glass over the windows of a
/// display, under its menu bar and Dock and under Rambla's own panels, so the levels panel shows on top of it. It
/// crosses the display the way the content goes, holds while the switch runs and the apps move their windows behind
/// it, and goes on out the other side. The mouse goes through it, and it is on screen only while it moves. One per
/// display.
@MainActor
final class LevelTransitionController {
    private var veils: [CGDirectDisplayID: Veil] = [:]

    /// Runs `change` behind the veil of `display` once it covers it. `settle` calls back once the windows that moved
    /// are in their places, or it gave up waiting, and then the veil goes. With `reduceMotion` it fades in and out
    /// where it is instead. A switch asked for while the veil is under way joins it: before it covers, it runs with the
    /// others; while it leaves, the veil comes back first.
    func run(on display: DisplayInfo, up: Bool, speed: Double, reduceMotion: Bool, change: @escaping () -> Void,
             settle: @escaping (_ done: @escaping () -> Void) -> Void) {
        let veil = veils[display.id] ?? Veil()
        veils[display.id] = veil
        veil.run(frame: Displays.cocoaRect(display.visible), up: up, speed: speed, reduceMotion: reduceMotion,
                 change: change, settle: settle)
    }
}

/// The veil of one display.
@MainActor
private final class Veil: NSObject {
    private enum Phase {
        case idle
        /// Coming over the display.
        case covering
        /// Over the whole display, that frame on its way to the screen: the switch runs on the next one.
        case covered
        /// The switch ran, and the apps move their windows behind it.
        case holding
        /// Going out the other side.
        case revealing
    }

    /// Under the Dock and the menu bar, over every app's windows, floating panels included.
    private static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)

    private let panel: OverlayPanel
    private let glass = NSVisualEffectView()
    private var link: CADisplayLink?
    private var phase = Phase.idle
    /// How much of the display the veil covers, and the side the rest of it is on (`LevelTransition.entrySide`).
    private var coverage = 0.0
    private var side = 1.0
    /// The stretch under way: what the veil covered when it set off, when, and for how long.
    private var start = 0.0
    private var startedAt: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0
    /// The way the last switch went: the veil leaves through the other side.
    private var up = true
    private var speed = 1.0
    private var reduceMotion = false
    private var pending: [() -> Void] = []
    private var settle: ((@escaping () -> Void) -> Void)?
    /// Counts the switches run while the veil holds: only the last one's settling lets it go.
    private var holds = 0

    override init() {
        panel = OverlayPanel(level: Self.level, collectionBehavior: [.canJoinAllSpaces, .transient, .ignoresCycle])
        super.init()
        panel.ignoresMouseEvents = true
        glass.material = .fullScreenUI
        glass.blendingMode = .behindWindow
        glass.state = .active
        let content = NSView()
        content.addSubview(glass)
        panel.contentView = content
    }

    func run(frame: CGRect, up: Bool, speed: Double, reduceMotion: Bool, change: @escaping () -> Void,
             settle: @escaping (@escaping () -> Void) -> Void) {
        self.up = up
        self.speed = speed
        self.settle = settle
        switch phase {
        case .idle:
            self.reduceMotion = reduceMotion
            panel.setFrame(frame, display: false)
            coverage = 0
            side = LevelTransition.entrySide(up: up)
            pending = [change]
            place()
            panel.orderFrontRegardless()
            startCovering()
        case .covering, .covered:
            pending.append(change)
        case .holding:
            change()
            waitForMoves()
        case .revealing:
            // Back over the display from where it is, on the side it was leaving through.
            pending = [change]
            startCovering()
        }
    }

    private func startCovering() {
        phase = .covering
        start = coverage
        startedAt = CACurrentMediaTime()
        duration = LevelTransition.seconds(LevelTransition.coverSeconds, speed: speed, distance: 1 - coverage)
        startLink()
    }

    private func startRevealing() {
        phase = .revealing
        side = LevelTransition.exitSide(up: up)
        startedAt = CACurrentMediaTime()
        duration = LevelTransition.seconds(LevelTransition.revealSeconds, speed: speed)
        startLink()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let progress = duration > 0 ? (CACurrentMediaTime() - startedAt) / duration : 1
        switch phase {
        case .covering:
            coverage = LevelTransition.coverage(coveringFrom: start, progress: progress)
            place()
            if progress >= 1 { phase = .covered }
        case .covered:
            // The frame that covers the display is on screen: the switch runs behind it.
            phase = .holding
            stopLink()
            let changes = pending
            pending = []
            changes.forEach { $0() }
            waitForMoves()
        case .revealing:
            coverage = LevelTransition.coverage(revealing: progress)
            place()
            if progress >= 1 { finish() }
        case .idle, .holding:
            stopLink()
        }
    }

    /// Lets the veil go once the windows that moved are in their places: those of the last switch that ran.
    private func waitForMoves() {
        holds += 1
        let hold = holds
        guard let settle else { return startRevealing() }
        settle { [weak self] in
            guard let self, phase == .holding, holds == hold else { return }
            startRevealing()
        }
    }

    private func finish() {
        stopLink()
        phase = .idle
        coverage = 0
        panel.orderOut(nil)
    }

    /// Puts the glass where `coverage` and `side` say: moved off the display by what it does not cover, or, with
    /// Reduce Motion, in place and that much see-through.
    private func place() {
        guard let content = panel.contentView else { return }
        var frame = content.bounds
        if reduceMotion {
            panel.alphaValue = coverage
        } else {
            panel.alphaValue = 1
            frame.origin.y = side * (1 - coverage) * frame.height
        }
        glass.frame = frame
    }

    private func startLink() {
        guard link == nil, let content = panel.contentView else { return }
        let link = content.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }
}
