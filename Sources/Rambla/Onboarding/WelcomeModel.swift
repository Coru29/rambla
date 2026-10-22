import ApplicationServices
import Combine
import Foundation
import RamblaCore

/// The steps of the welcome guide, in the order the user sees them.
enum WelcomePage: Int, CaseIterable {
    case welcome, accessibility, trackpad, shortcuts, done
}

/// What the welcome guide is showing: the current step and, while the permission step is on screen, whether the
/// Accessibility permission has been granted yet.
///
/// The window controller owns it and calls `stop()` when the window closes. The permission is looked up once a
/// second, and only while that step is the current one: every other step, and a closed window, cost nothing.
@MainActor
final class WelcomeModel: ObservableObject {
    static let trustPollInterval: TimeInterval = 1

    @Published private(set) var page: WelcomePage
    @Published private(set) var isTrusted: Bool

    /// The macOS settings behind "Configuración → Mac". A seam for the render harness.
    var readChecks: (Preferences) -> [CheckResult] = { SystemChecks.run(prefs: $0) }
    /// What "Empezar" does once the last step is reached: the window controller points it at closing the window.
    var finish: () -> Void = {}

    private let readTrust: () -> Bool
    private var timer: Timer?
    private var stopped = false

    init(page: WelcomePage = .welcome, readTrust: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.page = page
        self.readTrust = readTrust
        self.isTrusted = readTrust()
        updatePolling()
    }

    var isFirst: Bool { page == .welcome }
    var isLast: Bool { page == .done }
    var isPolling: Bool { timer != nil }

    /// What ⏎ and the forward button do: the next step, or finish on the last one.
    func advance() {
        if isLast { finish() } else { next() }
    }

    func next() {
        if let page = WelcomePage(rawValue: page.rawValue + 1) { go(to: page) }
    }

    func back() {
        if let page = WelcomePage(rawValue: page.rawValue - 1) { go(to: page) }
    }

    func go(to page: WelcomePage) {
        guard !stopped else { return }
        self.page = page
        updatePolling()
    }

    /// The window is closing: nothing may keep running after this.
    func stop() {
        stopped = true
        updatePolling()
    }

    // MARK: - Permission polling

    private func updatePolling() {
        if page == .accessibility, !stopped {
            refreshTrust()
            guard timer == nil else { return }
            let timer = Timer(timeInterval: Self.trustPollInterval, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self else {
                        timer.invalidate()
                        return
                    }
                    self.refreshTrust()
                }
            }
            timer.tolerance = 0.2
            // Common modes: the status keeps up while the window is being dragged.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func refreshTrust() {
        let trusted = readTrust()
        if trusted != isTrusted { isTrusted = trusted }
    }

    // MARK: - Trackpad rows

    /// The rows of the Mac checks that are about the trackpad gesture (`trackpad-gesture`, `three-finger-drag`).
    static func trackpadRows(from checks: [CheckResult]) -> [CheckResult] {
        checks.filter { $0.id.contains("trackpad") || $0.id.contains("three-finger") }
    }
}
