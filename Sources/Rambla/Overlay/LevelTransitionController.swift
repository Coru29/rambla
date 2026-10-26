import AppKit
import QuartzCore
import RamblaCore

/// The veil over a switch between stacked strips (`LevelTransition`): a sheet of frosted glass over the windows of a
/// display, under its menu bar and Dock and under Rambla's own panels, so the levels panel shows on top of it. It
/// crosses the display the way the content goes, holds while the switch runs and the apps move their windows behind
/// it, and goes on out the other side. The mouse goes through it, and it is on screen only during a switch. One per
/// display. Its phases and rules are `LevelTransition.Veil`'s: here are only the panel, the glass, the display link
/// that moves it and the timers of its deadlines.
@MainActor
final class LevelTransitionController {
    private var veils: [CGDirectDisplayID: DisplayVeil] = [:]
    /// Called once a veil covers its display, or its deadline says it does: the switches waiting for it run.
    private let covered: () -> Void
    /// Starts waiting for the windows that moved to be in their places, and calls `done` once they are, or it gave up.
    private let settle: (_ done: @escaping () -> Void) -> Void

    init(covered: @escaping () -> Void, settle: @escaping (_ done: @escaping () -> Void) -> Void) {
        self.covered = covered
        self.settle = settle
    }

    /// Covers `display` for a switch between its strips (`up`: toward the strip above) and calls `covered` once it
    /// does. The veil then holds until the windows are in their places (`settle`), and goes. With `reduceMotion` it
    /// fades in and out where it is instead. A switch asked for while the veil is under way joins it: before it
    /// covers, it is covered with the others; while it holds, at once; while it leaves, the veil comes back first.
    func request(on display: DisplayInfo, up: Bool, speed: Double, reduceMotion: Bool) {
        let veil = veils[display.id] ?? DisplayVeil(covered: covered, settle: settle)
        veils[display.id] = veil
        veil.request(frame: Displays.cocoaRect(display.visible), up: up, speed: speed, reduceMotion: reduceMotion)
    }

    /// Takes every veil off its display at once, calling nothing back: the switches waiting for them were dropped.
    func reset() {
        veils.values.forEach { $0.reset() }
    }
}

/// The veil of one display, doing what its state machine says.
@MainActor
private final class DisplayVeil: NSObject {
    /// Under the Dock and the menu bar, over every app's windows, floating panels included.
    private static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)

    private let panel: OverlayPanel
    private let glass = NSVisualEffectView()
    private var link: CADisplayLink?
    private var machine = LevelTransition.Veil()
    private let covered: () -> Void
    private let settle: (@escaping () -> Void) -> Void

    init(covered: @escaping () -> Void, settle: @escaping (@escaping () -> Void) -> Void) {
        self.covered = covered
        self.settle = settle
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

    func request(frame: CGRect, up: Bool, speed: Double, reduceMotion: Bool) {
        // Off screen, it takes the display's frame before it comes on: the display may have changed since.
        if machine.phase == .idle { panel.setFrame(frame, display: false) }
        apply(machine.request(up: up, speed: speed, reduceMotion: reduceMotion, now: CACurrentMediaTime()))
    }

    func reset() {
        apply(machine.reset())
    }

    @objc private func tick(_ link: CADisplayLink) {
        apply(machine.tick(now: CACurrentMediaTime()))
    }

    private func apply(_ effects: [LevelTransition.Veil.Effect]) {
        for effect in effects {
            switch effect {
            case .slide(let coverage, let side):
                place(offset: side * (1 - coverage), opacity: 1)
            case .fade(let opacity):
                place(offset: 0, opacity: opacity)
            case .show:
                panel.orderFrontRegardless()
            case .tick:
                startLink()
            case .stopTicking:
                stopLink()
            case .deadline(let token, let seconds):
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.apply(self.machine.deadline(token, now: CACurrentMediaTime()))
                    }
                }
            case .covered:
                covered()
            case .settle(let hold):
                settle { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.apply(self.machine.settled(hold: hold, now: CACurrentMediaTime()))
                    }
                }
            case .hide:
                panel.orderOut(nil)
            }
        }
    }

    /// Puts the glass `offset` of the display's height off it (up when positive, on AppKit's y axis), at `opacity`.
    private func place(offset: Double, opacity: Double) {
        guard let content = panel.contentView else { return }
        var frame = content.bounds
        frame.origin.y = offset * frame.height
        panel.alphaValue = opacity
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
