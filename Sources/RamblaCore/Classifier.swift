import Foundation

/// What the Accessibility layer knows about a window, reduced to the facts that decide how Rambla treats it.
public struct WindowTraits: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var isResizable: Bool
    public var isMinimized: Bool
    public var isFullscreen: Bool
    public var hasCloseButton: Bool
    public var bundleID: String?
    /// The owning app has a Dock icon (`NSApplication.ActivationPolicy.regular`).
    public var appIsRegular: Bool

    public init(role: String?, subrole: String?, isResizable: Bool, isMinimized: Bool, isFullscreen: Bool,
                hasCloseButton: Bool, bundleID: String?, appIsRegular: Bool) {
        self.role = role
        self.subrole = subrole
        self.isResizable = isResizable
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.hasCloseButton = hasCloseButton
        self.bundleID = bundleID
        self.appIsRegular = appIsRegular
    }
}

public enum WindowKind: Equatable, Sendable {
    /// Lives in a strip.
    case tile
    /// Left alone where it is, above the strip.
    case float
    /// Not Rambla's business at all (no window of its own, full screen, Rambla's own windows).
    case ignore
}

public enum Classifier {
    /// Decides how a window is treated. The checks run in this order and the first that applies wins:
    /// not an `AXWindow`, app not regular, Rambla's own window, native full screen -> ignore;
    /// app rule says float, not a standard window, not resizable, no close button -> float; otherwise tile.
    public static func classify(_ traits: WindowTraits, rules: [AppRule], ownBundleID: String) -> WindowKind {
        if traits.role != "AXWindow" { return .ignore }
        if !traits.appIsRegular { return .ignore }
        if traits.bundleID == ownBundleID { return .ignore }
        if traits.isFullscreen { return .ignore }
        if let bundleID = traits.bundleID,
           rules.first(where: { $0.bundleID == bundleID })?.behavior == .float { return .float }
        if traits.subrole != "AXStandardWindow" { return .float }
        if !traits.isResizable { return .float }
        if !traits.hasCloseButton { return .float }
        return .tile
    }
}
