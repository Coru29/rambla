import AppKit
import RamblaCore

/// Spring animation of window positions. Sizes jump at the start (resizing every frame is slow for
/// most apps); positions follow per-window critically damped springs on a 60 Hz timer that only
/// runs while something moves. Retargeting keeps each window's current position and velocity.
@MainActor
final class Animator {
    private struct State {
        var x: Double
        var y: Double
        var vx: Double = 0
        var vy: Double = 0
        var target: CGRect
    }

    private let write: ([WindowID: CGRect], _ verify: Bool) -> Void
    var onTick: (([WindowID: CGRect]) -> Void)?
    var speed: Double = 1
    private var states: [WindowID: State] = [:]
    private var timer: Timer?
    private var lastTick: CFAbsoluteTime = 0

    init(write: @escaping ([WindowID: CGRect], _ verify: Bool) -> Void) {
        self.write = write
    }

    var isAnimating: Bool { timer != nil }

    /// Where each animating window is right now.
    var current: [WindowID: CGRect] {
        states.mapValues { CGRect(x: $0.x, y: $0.y, width: $0.target.width, height: $0.target.height) }
    }

    func animate(to targets: [WindowID: CGRect], from start: [WindowID: CGRect]) {
        var sizeWrites: [WindowID: CGRect] = [:]
        for (id, target) in targets {
            if var state = states[id] {
                if state.target.size != target.size {
                    sizeWrites[id] = CGRect(x: state.x, y: state.y, width: target.width, height: target.height)
                }
                state.target = target
                states[id] = state
                continue
            }
            guard let from = start[id], !from.approximatelyEquals(target, tolerance: 0.5) else {
                write([id: target], true)
                continue
            }
            states[id] = State(x: from.minX, y: from.minY, target: target)
            if !from.size.approximatelyEquals(target.size, tolerance: 0.5) {
                sizeWrites[id] = CGRect(origin: from.origin, size: target.size)
            }
        }
        if !sizeWrites.isEmpty { write(sizeWrites, false) }
        guard !states.isEmpty, timer == nil else { return }
        lastTick = CFAbsoluteTimeGetCurrent()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel(_ id: WindowID) {
        states[id] = nil
        stopIfIdle()
    }

    func cancelAll() {
        states.removeAll()
        stopIfIdle()
    }

    private func stopIfIdle() {
        guard states.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = min(max(now - lastTick, 1.0 / 240.0), 1.0 / 20.0)
        lastTick = now
        let spring = Spring(response: 0.24 / max(speed, 0.2))
        var moving: [WindowID: CGRect] = [:]
        var finished: [WindowID: CGRect] = [:]
        for (id, var state) in states {
            spring.step(&state.x, &state.vx, target: state.target.minX, dt: dt)
            spring.step(&state.y, &state.vy, target: state.target.minY, dt: dt)
            if Spring.settled(state.x, state.vx, target: state.target.minX),
               Spring.settled(state.y, state.vy, target: state.target.minY) {
                finished[id] = state.target
                states[id] = nil
            } else {
                states[id] = state
                moving[id] = CGRect(x: state.x.rounded(), y: state.y.rounded(),
                                    width: state.target.width, height: state.target.height)
            }
        }
        if !moving.isEmpty { write(moving, false) }
        if !finished.isEmpty { write(finished, true) }
        onTick?(moving.merging(finished) { current, _ in current })
        stopIfIdle()
    }
}
