import AppKit

/// Taps on a Force Touch trackpad. macOS plays them only while a finger is on it, so they go with the trackpad
/// gestures; with a mouse, or a trackpad without the haptic engine, nothing happens.
enum Haptics {
    /// A slide by hand passed a column (`SlideDetent`).
    static func detent() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// A swipe up or down changed the column's width.
    static func widthChanged() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
