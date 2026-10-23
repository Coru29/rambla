import Foundation

/// When each connected display appeared, so that one that comes and goes within a moment counts for nothing: while a Mac
/// with its lid closed wakes, macOS shows a virtual display for about a second as the monitor turns back on. A display
/// that has not settled neither takes windows back nor gets windows that join a strip.
public struct DisplayPresence: Sendable {
    /// How long a display must stay connected to count.
    public static let settleDelay: Double = 3

    private var since: [String: Double] = [:]

    public init() {}

    /// The displays connected `now`. Those there when Rambla starts (`atLaunch`) count at once.
    public mutating func update(connected: Set<String>, now: Double, atLaunch: Bool = false) {
        for uuid in Array(since.keys) where !connected.contains(uuid) { since[uuid] = nil }
        for uuid in connected where since[uuid] == nil { since[uuid] = atLaunch ? now - Self.settleDelay : now }
    }

    public func isSettled(_ uuid: String, now: Double) -> Bool {
        guard let appeared = since[uuid] else { return false }
        return now - appeared >= Self.settleDelay
    }

    /// When a display that has not settled by `now` will, so the caller can look again then; nil for the others.
    public func settles(_ uuid: String, now: Double) -> Double? {
        guard let appeared = since[uuid], appeared + Self.settleDelay > now else { return nil }
        return appeared + Self.settleDelay
    }
}
