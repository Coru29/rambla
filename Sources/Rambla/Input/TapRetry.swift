import Foundation

/// When macOS refuses to create an event tap (it does while the Accessibility permission is being changed), the
/// feature tries again later, waiting twice as long each time up to a minute, for as long as it stays on.
@MainActor
final class TapRetry {
    private let name: String
    private var delay: TimeInterval = 1
    private var pending: DispatchWorkItem?

    nonisolated init(name: String) {
        self.name = name
    }

    /// An attempt is scheduled: until it runs, the feature leaves trying to it (a settings change trying at once would
    /// only fail again sooner, and log it).
    var isWaiting: Bool { pending != nil }

    /// Schedules `attempt` after the current wait, and doubles the wait for the next failure.
    func failed(then attempt: @escaping @MainActor () -> Void) {
        pending?.cancel()
        Log.error("\(name) could not be created; trying again in \(Int(delay)) s")
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pending = nil
                attempt()
            }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        delay = min(delay * 2, 60)
    }

    /// The tap exists (or the feature was turned off): the next failure waits a second again.
    func reset() {
        pending?.cancel()
        pending = nil
        delay = 1
    }
}
