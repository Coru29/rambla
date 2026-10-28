import CoreGraphics
import Foundation

/// A window of a strip that macOS filed under the desktop of another display because Rambla had parked it past the edge
/// that display now covers: with nothing beside the display (a laptop's lid closed), windows park on that edge, and a
/// display that appears there (the lid opened) takes them, often without even drawing them. The user did not send them
/// there, so they come back to their own display.
public enum StrayParked {
    /// A display in view, other than the window's own: where it is and the desktop it shows.
    public struct Other: Sendable {
        public var frame: CGRect
        public var currentSpace: UInt64?

        public init(frame: CGRect, currentSpace: UInt64?) {
            self.frame = frame
            self.currentSpace = currentSpace
        }
    }

    /// Whether the window that Rambla last put at `frame`, which macOS files under `spaces` instead of its strip's
    /// desktop `own`, is such a window: those are the desktop another display shows, and `frame` lies more than half
    /// over that display.
    public static func isStray(frame: CGRect, spaces: [UInt64], own: UInt64, others: [Other]) -> Bool {
        guard !spaces.isEmpty, !spaces.contains(own), frame.width > 0 else { return false }
        return others.contains { other in
            guard let current = other.currentSpace, spaces.contains(current) else { return false }
            let over = frame.intersection(other.frame)
            return !over.isNull && over.width > frame.width / 2
        }
    }
}
