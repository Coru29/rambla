import AppKit

/// Taps on a Force Touch trackpad. macOS plays them only while a finger is on it, so they go with the trackpad
/// gestures; with a mouse, or a trackpad without the haptic engine, nothing happens.
enum Haptics {
    /// A slide by hand passed a column (`SlideDetent`).
    static func detent() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// A swipe up or down did what it does (a width, the overview), or went far enough that lifting the fingers changes
    /// strip.
    static func gesture() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
