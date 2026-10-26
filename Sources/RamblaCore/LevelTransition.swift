import Foundation

/// The veil over a switch between stacked strips: a sheet of frosted glass that crosses the display the way the
/// content goes, covers it while the windows jump to their places behind it, and goes on out the other side. The
/// windows cannot slide up or down themselves (macOS keeps them below the menu bar and above the bottom edge), so the
/// veil makes the switch read as a move instead of a jump. Here is its path; the overlay draws it.
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
}
