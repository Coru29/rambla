import Foundation

/// The veil over a switch between stacked strips: a sheet of frosted glass that crosses the display the way the
/// content goes, covers it while the windows jump to their places behind it, and goes on out the other side. The
/// windows cannot slide up or down themselves (macOS keeps them below the menu bar and above the bottom edge), so the
/// veil makes the switch read as a move instead of a jump. Here are its path and its phases (`Veil`); the overlay draws
/// it.
///
/// Where the veil is goes by how much of the display it covers, 0 to 1. It comes in from the side of the strip that
/// comes into view (`entrySide`) and slows down as it settles over the display, then sets off gently out the other
/// side. A switch asked for while it leaves sends it back from where it is.
public enum LevelTransition {
    /// Seconds to cover the display, and to leave it, at Rambla's animation speed 1.
    public static let coverSeconds = 0.12
    public static let revealSeconds = 0.18

    /// The side the veil comes in from, as a sign on AppKit's y axis: from above (+1) when the strip above comes into
    /// view (the content goes down, as the fingers do with the natural direction), from below (−1) for the one below.
    public static func entrySide(up: Bool) -> Double { up ? 1 : -1 }

    /// The side it leaves through: the other one, so that it crosses the display.
    public static func exitSide(up: Bool) -> Double { -entrySide(up: up) }

    /// How much of the display the veil covers `progress` (0 to 1) of the way in from `start`, what it covered when it
    /// set off: it slows down as it settles.
    public static func coverage(coveringFrom start: Double, progress: Double) -> Double {
        start + (1 - start) * easeOut(clamped(progress))
    }

    /// How much it covers `progress` of the way out: it sets off gently, speeds up and slows down again as it goes.
    public static func coverage(revealing progress: Double) -> Double {
        1 - easeInOut(clamped(progress))
    }

    /// Seconds for a stretch that takes `base` at speed 1, for the part of the display left to cross (`distance`, 0 to
    /// 1), at Rambla's animation speed, held to the range the windows' animations use.
    public static func seconds(_ base: Double, speed: Double, distance: Double = 1) -> Double {
        base * min(max(distance, 0), 1) / min(max(speed, 0.25), 3)
    }

    private static func clamped(_ progress: Double) -> Double { min(max(progress, 0), 1) }
    private static func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    private static func easeInOut(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }

    /// Seconds a stretch of the veil (coming over the display, or leaving it) may take beyond its own before the veil
    /// ends it without the display link: a display asleep or unplugged, or a link that stalls, never leaves the veil
    /// on screen or a switch waiting for it.
    public static let watchdogSlack = 0.3
    /// The longest the veil holds over the display while the apps move their windows, whatever the wait for them does.
    public static let holdCap = 0.5
}

extension LevelTransition {
    /// The veil of one display, its phases and rules, for the overlay to draw (`Effect`). The overlay tells it of each
    /// switch asked for (`request`), of each frame while it moves (`tick`), of the end of a wait for the windows
    /// (`settled`) and of each deadline that comes (`deadline`), and does what each of these says, in order.
    ///
    /// A request puts the veil on screen, off the display on the side of the strip that comes, and it comes over the
    /// display. Once a frame with the whole display covered is on screen, it says so (`covered`): the switches that
    /// wait for it run, and it holds while the apps move their windows behind it (`settle`). Then it leaves through
    /// the other side of the last switch's direction. A request while it comes over joins that cover; one while it
    /// holds is covered at once, and it holds again; one while it leaves brings it back from where it is.
    ///
    /// Each stretch has a deadline (`watchdogSlack`, `holdCap`) in case the display link stops: a cover then ends as
    /// covered, a hold leaves, and a reveal takes the veil off the display.
    public struct Veil: Sendable {
        public enum Phase: Equatable, Sendable {
            case idle
            /// Coming over the display.
            case covering
            /// Over the whole display, that frame on its way to the screen: it is covered on the next one.
            case covered
            /// Covered: the switches ran, and the apps move their windows behind it.
            case holding
            /// Going out the other side.
            case revealing
        }

        /// What the overlay does, in the order given.
        public enum Effect: Equatable, Sendable {
            /// Put the panel on screen (where the glass already is).
            case show
            /// Put the glass over `coverage` (0 to 1) of the display, the rest of it off the display on `side`, a sign
            /// on AppKit's y axis (`entrySide`).
            case slide(coverage: Double, side: Double)
            /// With Reduce Motion: the glass over the whole display, `opacity` opaque.
            case fade(opacity: Double)
            /// Call `tick` on every frame from now on (the display link, unless it already runs).
            case tick
            /// No more frames.
            case stopTicking
            /// Call `deadline` with this token in so many seconds.
            case deadline(Int, after: Double)
            /// The veil covers the display: the switches that wait for it run now.
            case covered
            /// Wait for the windows that moved to be in their places, then call `settled` with this token.
            case settle(hold: Int)
            /// Take the panel off screen.
            case hide
        }

        public private(set) var phase = Phase.idle
        /// How much of the display the veil covers, and the side the rest of it is on.
        public private(set) var coverage = 0.0
        private var side = 1.0
        /// The stretch under way: what the veil covered when it set off, when, and for how long.
        private var start = 0.0
        private var startedAt = 0.0
        private var duration = 0.0
        /// The way the last switch went: the veil leaves through the other side.
        private var up = true
        private var speed = 1.0
        private var reduceMotion = false
        /// Counts the stretches (covering, holding, revealing): the settling or the deadline of one that is over does
        /// nothing.
        private var stretch = 0

        public init() {}

        /// A switch is asked for (`up`: toward the strip above), at Rambla's animation `speed`, at `now` (seconds).
        public mutating func request(up: Bool, speed: Double, reduceMotion: Bool, now: Double) -> [Effect] {
            self.up = up
            self.speed = speed
            switch phase {
            case .idle:
                self.reduceMotion = reduceMotion
                coverage = 0
                side = LevelTransition.entrySide(up: up)
                return [glass, .show] + startCovering(now: now)
            case .covering, .covered:
                return []
            case .holding:
                return [.covered] + hold()
            case .revealing:
                // Back over the display from where it is, on the side it was leaving through.
                return startCovering(now: now)
            }
        }

        /// A frame, at `now`.
        public mutating func tick(now: Double) -> [Effect] {
            let progress = duration > 0 ? (now - startedAt) / duration : 1
            switch phase {
            case .covering:
                coverage = LevelTransition.coverage(coveringFrom: start, progress: progress)
                if progress >= 1 { phase = .covered }
                return [glass]
            case .covered:
                // The frame that covers the display is on screen: the switches run behind it.
                return [.stopTicking, .covered] + hold()
            case .revealing:
                coverage = LevelTransition.coverage(revealing: progress)
                return progress >= 1 ? [glass] + finish() : [glass]
            case .idle, .holding:
                return [.stopTicking]
            }
        }

        /// The windows that moved in the hold `hold` are in their places, or the wait for them is over.
        public mutating func settled(hold: Int, now: Double) -> [Effect] {
            guard phase == .holding, hold == stretch else { return [] }
            return startRevealing(now: now)
        }

        /// The deadline of the stretch `token` came: the stretch ends now if it has not.
        public mutating func deadline(_ token: Int, now: Double) -> [Effect] {
            guard token == stretch else { return [] }
            switch phase {
            case .idle:
                return []
            case .covering, .covered:
                // The display link did not bring it over the display: it covers it now, and the switches run.
                coverage = 1
                return [glass, .stopTicking, .covered] + hold()
            case .holding:
                return startRevealing(now: now)
            case .revealing:
                return finish()
            }
        }

        /// Off the display at once, and nothing more to do: no switch waits for it any more (the desktop or the
        /// displays changed).
        public mutating func reset() -> [Effect] {
            phase == .idle ? [] : finish()
        }

        /// Where the glass goes: in place and that much opaque with Reduce Motion, else moved off the display by what
        /// it does not cover.
        private var glass: Effect {
            reduceMotion ? .fade(opacity: coverage) : .slide(coverage: coverage, side: side)
        }

        private mutating func startCovering(now: Double) -> [Effect] {
            phase = .covering
            start = coverage
            startedAt = now
            duration = LevelTransition.seconds(LevelTransition.coverSeconds, speed: speed, distance: 1 - coverage)
            return [.tick] + startStretch(lasting: duration + LevelTransition.watchdogSlack)
        }

        /// Covered: the switches ran, or are about to. The veil goes once the windows are in their places, those of the
        /// last switch that ran: a request meanwhile holds it again, and the settling of the hold before it does
        /// nothing.
        private mutating func hold() -> [Effect] {
            phase = .holding
            let deadline = startStretch(lasting: LevelTransition.holdCap)
            return [.settle(hold: stretch)] + deadline
        }

        private mutating func startRevealing(now: Double) -> [Effect] {
            phase = .revealing
            side = LevelTransition.exitSide(up: up)
            startedAt = now
            duration = LevelTransition.seconds(LevelTransition.revealSeconds, speed: speed)
            return [.tick] + startStretch(lasting: duration + LevelTransition.watchdogSlack)
        }

        /// A new stretch, which ends by `seconds` from now at the latest.
        private mutating func startStretch(lasting seconds: Double) -> [Effect] {
            stretch += 1
            return [.deadline(stretch, after: seconds)]
        }

        private mutating func finish() -> [Effect] {
            phase = .idle
            coverage = 0
            return [.stopTicking, .hide]
        }
    }
}
