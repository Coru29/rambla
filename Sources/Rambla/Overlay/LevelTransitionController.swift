import AppKit
import QuartzCore
import RamblaCore

/// A window as the veil shows it while the strips change: a card at its place (`VeilCardArt`).
struct VeilCard {
    let id: WindowID
    /// Where the window is, or goes, in AX coordinates.
    let frame: CGRect
    let app: String
    let title: String
    let icon: NSImage?
    /// The app's color, from its icon (`OverviewItem.tint`).
    let tint: NSColor
}

/// The veil over a switch between stacked strips (`LevelTransition`): frosted glass over the windows of a display, under
/// its menu bar and Dock and under Rambla's own panels, so the levels panel shows on top of it, with a card over each
/// window shown. It fades in with the cards where the windows are, and once it covers the display the switch runs: the
/// cards of the strip that left slide off the way the content goes, those of the strip that came slide in to their
/// windows' places, and the veil fades out once they are there and the apps have moved the windows behind it. The mouse
/// goes through it, and it is on screen only during a switch. One per display. Its phases and rules are
/// `LevelTransition.Veil`'s: here are only the panel, the glass, the cards, the display link that fades it and the
/// timers of its deadlines.
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
    /// does. The veil then holds until the windows are in their places (`settle`) and their cards too, and goes.
    /// `cards` gives the windows shown on the display as they are then: asked as the veil comes, and once the switches
    /// ran. With `reduceMotion` there are no cards: the glass fades in and out. A switch asked for while the veil is
    /// under way joins it: before it covers, it is covered with the others; while it holds, at once; while it leaves,
    /// the veil comes back first.
    func request(on display: DisplayInfo, up: Bool, speed: Double, reduceMotion: Bool,
                 cards: @escaping () -> [VeilCard]) {
        let veil = veils[display.id] ?? DisplayVeil(covered: covered, settle: settle)
        veils[display.id] = veil
        veil.request(frame: Displays.cocoaRect(display.visible), up: up, speed: speed, reduceMotion: reduceMotion,
                     cards: cards)
    }

    /// Takes every veil off its display at once, calling nothing back: the switches waiting for them were dropped.
    func reset() {
        veils.values.forEach { $0.reset() }
    }
}

/// A card on the veil: its layer, its window's place (in the veil's coordinates), and whether it is on its way out.
private final class Card {
    let layer: CALayer
    var home: CGPoint
    var leaving = false

    init(layer: CALayer, home: CGPoint) {
        self.layer = layer
        self.home = home
    }
}

/// The veil of one display, doing what its state machine says.
@MainActor
private final class DisplayVeil: NSObject {
    /// Under the Dock and the menu bar, over every app's windows, floating panels included.
    private static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
    /// The cards set off gently, cross quickly and slow down into their places.
    private static let slideCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)

    private let panel: OverlayPanel
    private let glass = NSVisualEffectView()
    /// Holds the cards, over the glass.
    private let stage = NSView()
    private var link: CADisplayLink?
    private var machine = LevelTransition.Veil()
    private let covered: () -> Void
    private let settle: (@escaping () -> Void) -> Void
    /// The way, the speed and the windows of the last switch asked for.
    private var up = true
    private var speed = 1.0
    private var reduceMotion = false
    private var scene: (() -> [VeilCard])?
    /// The cards on the veil by window, those on their way out included, and those that gave their window to a card of
    /// another size, on their way out too.
    private var cards: [WindowID: Card] = [:]
    private var replaced: [Card] = []
    /// Counts the slides: the end of one that another took over does nothing.
    private var slide = 0
    /// What waits for the cards to be in their places; nil while they are.
    private var afterSlide: [() -> Void]?
    /// The hold waiting for the windows and for the cards, and for how many of the two still.
    private var waiting: (hold: Int, left: Int)?

    init(covered: @escaping () -> Void, settle: @escaping (@escaping () -> Void) -> Void) {
        self.covered = covered
        self.settle = settle
        panel = OverlayPanel(level: Self.level, collectionBehavior: [.canJoinAllSpaces, .transient, .ignoresCycle])
        super.init()
        panel.ignoresMouseEvents = true
        glass.material = .fullScreenUI
        glass.blendingMode = .behindWindow
        glass.state = .active
        // Hosts its own layers: AppKit leaves the cards alone.
        stage.layer = CALayer()
        stage.wantsLayer = true
        let content = NSView()
        content.addSubview(glass)
        content.addSubview(stage)
        panel.contentView = content
    }

    func request(frame: CGRect, up: Bool, speed: Double, reduceMotion: Bool, cards: @escaping () -> [VeilCard]) {
        self.up = up
        self.speed = speed
        scene = cards
        if machine.phase == .idle {
            // Off screen, it takes the display's frame before it comes on: the display may have changed since.
            panel.setFrame(frame, display: false)
            let bounds = panel.contentView?.bounds ?? .zero
            glass.frame = bounds
            stage.frame = bounds
            self.reduceMotion = reduceMotion
        }
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
            case .slide(let coverage, _):
                // The glass fades in and out where it is: the cards carry the move.
                panel.alphaValue = coverage
            case .fade(let opacity):
                panel.alphaValue = opacity
            case .show:
                showCards()
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
                slideCards()
            case .settle(let hold):
                waiting = (hold, 2)
                settle { [weak self] in
                    MainActor.assumeIsolated { self?.settled(hold) }
                }
                afterCards { [weak self] in self?.settled(hold) }
            case .hide:
                panel.orderOut(nil)
                clearCards()
            }
        }
    }

    /// One of the two that the hold `hold` waits for is done (the windows, the cards): once both are, the veil goes.
    private func settled(_ hold: Int) {
        guard var waiting, waiting.hold == hold else { return }
        waiting.left -= 1
        self.waiting = waiting.left > 0 ? waiting : nil
        if waiting.left == 0 { apply(machine.settled(hold: hold, now: CACurrentMediaTime())) }
    }

    // MARK: - Cards

    /// The veil comes: a card over each window shown, where it is, the focused window's on top.
    private func showCards() {
        clearCards()
        guard !reduceMotion, let scene, let stageLayer = stage.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, item) in scene().enumerated() {
            let card = makeCard(item)
            card.layer.zPosition = CGFloat(index)
            cards[item.id] = card
            stageLayer.addSublayer(card.layer)
        }
        CATransaction.commit()
    }

    /// The switches ran: the cards of the windows shown now slide to their places, those on the veil already from where
    /// they are and the others from off the display on the side the content comes from, and the other cards slide off
    /// it the other way, under them. The focused window's card goes on top: one taken along to the strip that comes
    /// stays in sight as it crosses.
    private func slideCards() {
        guard !reduceMotion, let scene, let stageLayer = stage.layer else { return }
        let distance = LevelTransition.slideDistance(height: Double(stage.bounds.height))
        let enter = CGFloat(LevelTransition.entrySide(up: up) * distance)
        let leave = CGFloat(LevelTransition.exitSide(up: up) * distance)
        let duration = LevelTransition.slideDuration(speed: speed)
        var moved = false
        var shown = Set<WindowID>()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, item) in scene().enumerated() {
            shown.insert(item.id)
            let rect = localRect(item.frame)
            let home = CGPoint(x: rect.midX, y: rect.midY)
            if let card = cards[item.id] {
                let size = card.layer.bounds.size
                if abs(size.width - rect.width) < 1, abs(size.height - rect.height) < 1 {
                    // On the veil already (its window comes along, or comes back): from where it is.
                    card.leaving = false
                    card.home = home
                    card.layer.zPosition = CGFloat(index)
                    moved = move(card.layer, to: home, duration: duration) || moved
                    continue
                }
                // Another size: that card goes with the strip that leaves, and another one comes.
                replaced.append(card)
                card.layer.zPosition = -1
                moved = move(card.layer, to: CGPoint(x: card.home.x, y: card.home.y + leave), duration: duration) || moved
            }
            let card = makeCard(item)
            card.layer.position = CGPoint(x: home.x, y: home.y + enter)
            card.layer.zPosition = CGFloat(index)
            cards[item.id] = card
            stageLayer.addSublayer(card.layer)
            moved = move(card.layer, to: home, duration: duration) || moved
        }
        for (id, card) in cards where !shown.contains(id) && !card.leaving {
            // Its window went with the strip that left.
            card.leaving = true
            card.layer.zPosition = -1
            moved = move(card.layer, to: CGPoint(x: card.home.x, y: card.home.y + leave), duration: duration) || moved
        }
        CATransaction.commit()
        slide += 1
        let token = slide
        guard moved else { return slid(token) }
        if afterSlide == nil { afterSlide = [] }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            MainActor.assumeIsolated { self?.slid(token) }
        }
    }

    /// Slides `layer` from where it shows now to `point`, and says whether it moves at all.
    private func move(_ layer: CALayer, to point: CGPoint, duration: Double) -> Bool {
        let from = layer.presentation()?.position ?? layer.position
        layer.position = point
        guard hypot(point.x - from.x, point.y - from.y) > 0.5 else {
            layer.removeAnimation(forKey: "slide")
            return false
        }
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: from)
        animation.toValue = NSValue(point: point)
        animation.duration = duration
        animation.timingFunction = Self.slideCurve
        layer.add(animation, forKey: "slide")
        return true
    }

    /// The slide `token` is over: the cards that went come off the veil, and what waited for the cards goes on.
    private func slid(_ token: Int) {
        guard token == slide else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, card) in cards where card.leaving {
            card.layer.removeFromSuperlayer()
            cards[id] = nil
        }
        replaced.forEach { $0.layer.removeFromSuperlayer() }
        CATransaction.commit()
        replaced.removeAll()
        let waiting = afterSlide ?? []
        afterSlide = nil
        waiting.forEach { $0() }
    }

    /// Calls `done` once the cards are in their places: now when they are.
    private func afterCards(_ done: @escaping () -> Void) {
        if afterSlide != nil { afterSlide?.append(done) } else { done() }
    }

    /// Takes every card off the veil, and nothing waits for them or for the windows any more.
    private func clearCards() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cards.values.forEach { $0.layer.removeFromSuperlayer() }
        replaced.forEach { $0.layer.removeFromSuperlayer() }
        CATransaction.commit()
        cards.removeAll()
        replaced.removeAll()
        slide += 1
        afterSlide = nil
        waiting = nil
    }

    private func makeCard(_ item: VeilCard) -> Card {
        let rect = localRect(item.frame)
        let layer = VeilCardArt.layer(size: rect.size, app: item.app, title: item.title, icon: item.icon,
                                      tint: item.tint, scale: panel.backingScaleFactor)
        let home = CGPoint(x: rect.midX, y: rect.midY)
        layer.position = home
        return Card(layer: layer, home: home)
    }

    /// A window's frame (AX coordinates) in the veil's.
    private func localRect(_ frame: CGRect) -> CGRect {
        Displays.cocoaRect(frame).offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
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
