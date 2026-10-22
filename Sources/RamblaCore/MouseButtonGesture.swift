import Foundation

/// Gestures made by moving the mouse with a chosen combination of its buttons held (a "chord": the middle button, or
/// the side buttons 4 and 5 pressed together, say). Sideways slides the strip under the pointer and lets it settle on
/// release, like the trackpad swipe; a clear move up or down is one command per press. Buttons are numbered the way
/// mouse apps number them: 3 is the middle button (pressing the wheel), 4 and 5 the side ones. The left and right
/// buttons never take part.
///
/// A chord's presses are kept from the other apps (Mac Mouse Fix included) until it is clear they are Rambla's:
/// - a press of one button of a larger chord waits `chordWindow` for the others, and goes on to the apps (replayed)
///   when they do not come, when it is released, when the pointer moves away, when another button is pressed or when
///   the wheel turns, so each button keeps doing what it did on its own;
/// - a one-button chord gives its button back as a plain click when it is released before it became a gesture, and
///   hands it on when the wheel turns while it is held.
/// A press that went to the apps stays theirs until it is released.
///
/// The app feeds it the presses and releases of every button but the left and right ones, and the pointer's moves and
/// the wheel's turns while `holdsButtons`; it posts the presses an output replays (before the event, when there is
/// one) and calls `expire` once `deadline` passes.
public struct MouseButtonGesture: Sendable {
    public enum Input: Equatable, Sendable {
        case down(Int)
        case up(Int)
        /// The pointer moved this many points with a button down (y grows downward, like screen coordinates).
        case drag(dx: Double, dy: Double)
        /// The pointer moved with no button down: whatever was held has been released unseen (the tap was off for a
        /// moment).
        case released
        /// The wheel turned. It is never Rambla's, but another app may read it together with a held button.
        case scroll
    }

    public enum Command: Equatable, Sendable {
        /// A slide starts on the strip under the pointer.
        case slideBegan
        /// The pointer moved this many points sideways during the slide (positive: right).
        case slide(Double)
        /// The slide is over: let the strip settle, carrying the pointer's speed (points per second, positive: right).
        case slideEnded(velocity: Double)
        /// A move up (true) or down: one per press of the chord.
        case vertical(up: Bool)
    }

    public struct Output: Equatable, Sendable {
        /// Held-back presses that now go to the apps, oldest first: they go before the event itself.
        public var replay: [Int]
        /// Whether the event goes on to the apps.
        public var passes: Bool
        public var commands: [Command]

        public init(replay: [Int] = [], passes: Bool, commands: [Command] = []) {
            self.replay = replay
            self.passes = passes
            self.commands = commands
        }
    }

    /// Seconds to press the rest of a chord after its first button.
    public static let chordWindow = 0.2
    /// Pointer movement (points) that still counts as holding still while waiting for the rest of a chord.
    public static let jitter = 6.0
    /// Sideways movement (points) that starts a slide.
    public static let slideStart = 8.0
    /// Upward or downward movement (points) that counts as a move up or down.
    public static let verticalStart = 40.0

    private enum Phase: Sendable {
        case idle
        /// Part of the chord is down (held back) since `since`; the pointer moved this much since then.
        case waiting(since: Double, dx: Double, dy: Double)
        /// The whole chord is down: the pointer moved this much since, and the next moves decide what it is.
        case armed(dx: Double, dy: Double)
        case sliding
        /// This press already did its part (or came apart): the rest of it is swallowed until its buttons are released.
        case spent
    }

    private let chord: Set<Int>
    /// The chord's presses held back from the apps, in the order they came.
    private var held: [Int] = []
    /// Presses that went to the apps (handed on or never Rambla's): their releases go there too.
    private var passed: Set<Int> = []
    private var phase = Phase.idle
    private var position = 0.0
    private var velocity = VelocityTracker()

    public init(buttons: [Int]) {
        chord = Set(buttons)
    }

    /// While true, the app feeds the pointer's moves (and only then: moving without the chord is none of Rambla's
    /// business).
    public var holdsButtons: Bool { !held.isEmpty }

    /// The presses kept from the apps, in the order they came.
    public var heldButtons: [Int] { held }

    /// While part of a chord waits for the rest: when `expire(at:)` must be called.
    public var deadline: Double? {
        guard case .waiting(let since, _, _) = phase else { return nil }
        return since + Self.chordWindow
    }

    public mutating func handle(_ input: Input, at time: Double) -> Output {
        // A timer that runs late must not stretch the window.
        let expired = expire(at: time)
        var output: Output
        switch input {
        case .down(let button): output = press(button, at: time)
        case .up(let button): output = release(button, at: time)
        case .drag(let dx, let dy): output = drag(dx, dy, at: time)
        case .released: output = Output(passes: true, commands: forget(at: time))
        case .scroll: output = Output(replay: scrollHandsOn ? handOn() : [], passes: true)
        }
        output.replay = expired + output.replay
        return output
    }

    /// When the rest of a chord did not come in time, returns its presses so far, which now go to the apps.
    public mutating func expire(at time: Double) -> [Int] {
        guard let deadline, time >= deadline else { return [] }
        return handOn()
    }

    /// Drops everything under way (the feature was turned off, or the taps are being made again): a slide ends
    /// without speed, and nothing is replayed, not even a press waiting for the rest of its chord.
    public mutating func cancel() -> [Command] {
        var commands: [Command] = []
        if case .sliding = phase { commands = [.slideEnded(velocity: 0)] }
        held.removeAll()
        passed.removeAll()
        velocity.reset()
        phase = .idle
        return commands
    }

    // MARK: - Inputs

    private mutating func press(_ button: Int, at time: Double) -> Output {
        var commands: [Command] = []
        if held.contains(button) {
            // Pressed again without a release in between: the release went by unseen, and with it this press.
            commands = forget(at: time)
        }
        passed.remove(button)   // same: a press the apps had was released unseen
        guard chord.contains(button), passed.isDisjoint(with: chord) else {
            // Not part of the chord, or the chord cannot come together (one of its buttons is the apps'): a part of
            // the chord still waiting goes on first, then this press.
            let replay = isWaiting ? handOn() : []
            passed.insert(button)
            return Output(replay: replay, passes: true, commands: commands)
        }
        held.append(button)
        if Set(held) == chord {
            phase = .armed(dx: 0, dy: 0)
        } else if case .idle = phase {
            phase = .waiting(since: time, dx: 0, dy: 0)
        }
        return Output(passes: false, commands: commands)
    }

    private mutating func release(_ button: Int, at time: Double) -> Output {
        if passed.remove(button) != nil { return Output(passes: true) }
        guard let index = held.firstIndex(of: button) else { return Output(passes: true) }
        switch phase {
        case .waiting:
            // A press of part of the chord on its own: it all goes to the apps, then this release.
            let replay = handOn()
            passed.remove(button)
            return Output(replay: replay, passes: true)
        case .armed:
            held.remove(at: index)
            if chord.count == 1 {
                // A one-button chord that did not become a gesture: the click the hand meant (pressing the wheel
                // moves the mouse a little), the apps' after all.
                phase = .idle
                return Output(replay: [button], passes: true)
            }
            phase = held.isEmpty ? .idle : .spent
            return Output(passes: false)
        case .sliding:
            held.remove(at: index)
            let speed = velocity.velocity(at: time)
            velocity.reset()
            phase = held.isEmpty ? .idle : .spent
            return Output(passes: false, commands: [.slideEnded(velocity: speed)])
        case .spent, .idle:
            held.remove(at: index)
            if held.isEmpty { phase = .idle }
            return Output(passes: false)
        }
    }

    private mutating func drag(_ dx: Double, _ dy: Double, at time: Double) -> Output {
        switch phase {
        case .idle:
            return Output(passes: true)
        case .waiting(let since, let x, let y):
            guard hypot(x + dx, y + dy) <= Self.jitter else {
                // A drag with that button alone (Mac Mouse Fix's, say): it goes to the apps, and this move after it.
                return Output(replay: handOn(), passes: true)
            }
            phase = .waiting(since: since, dx: x + dx, dy: y + dy)
            return Output(passes: false)
        case .armed(let x, let y):
            let (x, y) = (x + dx, y + dy)
            if abs(x) >= Self.slideStart, abs(x) > abs(y) {
                phase = .sliding
                position = x
                velocity.reset()
                velocity.add(position, at: time)
                return Output(passes: false, commands: [.slideBegan, .slide(x)])
            }
            if abs(y) >= Self.verticalStart, abs(y) > 2 * abs(x) {
                phase = .spent
                return Output(passes: false, commands: [.vertical(up: y < 0)])
            }
            phase = .armed(dx: x, dy: y)
            return Output(passes: false)
        case .sliding:
            position += dx
            velocity.add(position, at: time)
            return Output(passes: false, commands: [.slide(dx)])
        case .spent:
            return Output(passes: false)
        }
    }

    // MARK: - Helpers

    private var isWaiting: Bool {
        if case .waiting = phase { return true }
        return false
    }

    /// The wheel turning while part of a chord waits, or while a one-button chord is held still, means the button is
    /// held for the app's sake (Mac Mouse Fix zooms with a side button and the wheel).
    private var scrollHandsOn: Bool {
        switch phase {
        case .waiting: return true
        case .armed: return chord.count == 1
        default: return false
        }
    }

    /// The presses waiting for the rest of the chord go to the apps.
    private mutating func handOn() -> [Int] {
        let replay = held
        held.removeAll()
        passed.formUnion(replay)
        phase = .idle
        return replay
    }

    /// Every button was released unseen: a slide ends with the speed it had, and nothing is replayed (no release
    /// would follow it).
    private mutating func forget(at time: Double) -> [Command] {
        var commands: [Command] = []
        if case .sliding = phase { commands = [.slideEnded(velocity: velocity.velocity(at: time))] }
        held.removeAll()
        passed.removeAll()
        velocity.reset()
        phase = .idle
        return commands
    }
}
