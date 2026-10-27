import CoreGraphics
import Foundation

/// The frames Rambla asked of each window in the last moments. An app that applies moves late (VS Code and other
/// Electron apps) can report one of them after Rambla asked for the next: that is Rambla's own move, not another app's,
/// and the window still goes where Rambla wants it now.
public struct FrameEchoes: Sendable {
    /// How long a frame asked for counts as Rambla's own when the app reports it.
    public static let window: TimeInterval = 3
    /// Points a reported frame may be off on each side.
    public static let tolerance: CGFloat = 2

    private var asked: [WindowID: [(frame: CGRect, at: TimeInterval)]] = [:]
    private var lastAskedAt: [WindowID: TimeInterval] = [:]

    public init() {}

    /// Rambla asked window `id` for `frame` at `now`.
    public mutating func asked(_ frame: CGRect, of id: WindowID, at now: TimeInterval) {
        // Oldest first: an animation asks for a frame per display refresh, so only the stale front is dropped.
        let stale = asked[id]?.prefix { now - $0.at > Self.window }.count ?? 0
        if stale > 0 { asked[id]!.removeFirst(stale) }
        asked[id, default: []].append((frame, now))
        lastAskedAt[id] = now
    }

    /// Whether `frame`, reported for window `id` at `now`, is one Rambla asked of it in the last moments.
    public func isOwn(_ frame: CGRect, of id: WindowID, at now: TimeInterval) -> Bool {
        (asked[id] ?? []).contains { now - $0.at <= Self.window && Self.close($0.frame, frame) }
    }

    /// When Rambla last asked anything of window `id`.
    public func lastAsked(_ id: WindowID) -> TimeInterval? {
        lastAskedAt[id]
    }

    public mutating func forget(_ id: WindowID) {
        asked[id] = nil
        lastAskedAt[id] = nil
    }

    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
