import Foundation

/// Width given to a window when it first enters the strip.
public enum NewWindowWidth: Codable, Equatable, Sendable {
    /// The window's own width, limited to 25 %...100 % of the viewport.
    case natural
    /// A fixed fraction of the viewport.
    case fraction(Double)
}

/// What a short vertical swipe does, with the trackpad's fingers or the mouse's buttons.
public enum VerticalGesture: String, Codable, CaseIterable, Sendable {
    /// Changes the strip in view. A long swipe up gives the focused column the full width (or gives it back), and a
    /// long one down opens the overview.
    case strips
    /// The gesture as it was before stacked strips: up gives the focused column the full width at once, down gives
    /// back its width (when the swipe ends), and a long one down opens the overview.
    case width
}

public struct FocusBorderPrefs: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var colorHex: String
    public var width: Double

    public init(enabled: Bool = false, colorHex: String = "#0A84FF", width: Double = 3) {
        self.enabled = enabled
        self.colorHex = colorHex
        self.width = width
    }

    /// Missing keys take their defaults, so older saved preferences keep loading when a field is added.
    public init(from decoder: Decoder) throws {
        let defaults = FocusBorderPrefs()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? defaults.colorHex
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? defaults.width
    }
}

public struct DimPrefs: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Opacity of the black overlay, 0...1.
    public var amount: Double

    public init(enabled: Bool = false, amount: Double = 0.25) {
        self.enabled = enabled
        self.amount = amount
    }

    public init(from decoder: Decoder) throws {
        let defaults = DimPrefs()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? defaults.amount
    }
}

public struct TrackpadPrefs: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Number of fingers of the horizontal swipe (3 or 4).
    public var fingers: Int
    public var sensitivity: Double
    /// Natural direction: the strip follows the fingers.
    public var natural: Bool
    /// Swiping up or down with the same fingers does what `Preferences.verticalGesture` says; without it, nothing.
    public var verticalSwipe: Bool
    /// A tap on the trackpad (Force Touch) each time a slide passes a column, and when a swipe up or down acts.
    public var haptics: Bool

    public init(enabled: Bool = true, fingers: Int = 4, sensitivity: Double = 1.0, natural: Bool = true,
                verticalSwipe: Bool = true, haptics: Bool = true) {
        self.enabled = enabled
        self.fingers = fingers
        self.sensitivity = sensitivity
        self.natural = natural
        self.verticalSwipe = verticalSwipe
        self.haptics = haptics
    }

    public init(from decoder: Decoder) throws {
        let defaults = TrackpadPrefs()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        fingers = try container.decodeIfPresent(Int.self, forKey: .fingers) ?? defaults.fingers
        sensitivity = try container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? defaults.sensitivity
        natural = try container.decodeIfPresent(Bool.self, forKey: .natural) ?? defaults.natural
        verticalSwipe = try container.decodeIfPresent(Bool.self, forKey: .verticalSwipe) ?? defaults.verticalSwipe
        haptics = try container.decodeIfPresent(Bool.self, forKey: .haptics) ?? defaults.haptics
    }
}

/// Sliding the strip with a mouse: while these keys are held, each notch of the wheel moves to the next column,
/// and a Magic Mouse swipe (or two fingers on a trackpad) slides the strip like the trackpad gesture.
public struct MousePrefs: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var modifiers: Modifiers

    /// The key combinations offered in the settings, the default first. A lone key is taken: ⇧ scrolls sideways
    /// and ⌥ or ⌘ change how many apps scroll or zoom.
    public static let modifierChoices: [Modifiers] = [[.control, .command], [.option, .command], [.control, .option],
                                                      [.control, .option, .command]]

    public init(enabled: Bool = true, modifiers: Modifiers = [.control, .command]) {
        self.enabled = enabled
        self.modifiers = modifiers
    }

    public init(from decoder: Decoder) throws {
        let defaults = MousePrefs()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        modifiers = try container.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? defaults.modifiers
    }
}

/// Moving the mouse with a combination of its buttons held (see `MouseButtonGesture`): sideways slides the strip, and
/// up and down do what `Preferences.verticalGesture` says.
public struct MouseButtonsPrefs: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// The buttons to hold together, numbered the way mouse apps number them: 3 is the middle button, 4 and 5 the
    /// side ones. Never the left or right button. Sorted, without repeats.
    public var buttons: [Int] {
        didSet { buttons = Self.normalized(buttons) }
    }
    public var sensitivity: Double
    /// The strip follows the pointer; without it, it goes the other way.
    public var natural: Bool

    /// The side buttons together: on their own they keep going back and forward, in the browser or in Mac Mouse Fix.
    public static let defaultButtons = [4, 5]

    /// The buttons a chord can use, in order: the left and right ones (1 and 2) are left out, like numbers no mouse
    /// button has (macOS counts 32).
    public static func normalized(_ buttons: [Int]) -> [Int] {
        Array(Set(buttons.filter { (3...32).contains($0) })).sorted()
    }

    public init(enabled: Bool = false, buttons: [Int] = MouseButtonsPrefs.defaultButtons, sensitivity: Double = 1.0,
                natural: Bool = true) {
        self.enabled = enabled
        self.buttons = Self.normalized(buttons)
        self.sensitivity = sensitivity
        self.natural = natural
    }

    public init(from decoder: Decoder) throws {
        let defaults = MouseButtonsPrefs()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        let stored = Self.normalized(try container.decodeIfPresent([Int].self, forKey: .buttons) ?? [])
        buttons = stored.isEmpty ? defaults.buttons : stored
        sensitivity = try container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? defaults.sensitivity
        natural = try container.decodeIfPresent(Bool.self, forKey: .natural) ?? defaults.natural
    }
}

/// A per-app override: always float it, give it an initial width, or choose where its windows open.
public struct AppRule: Codable, Equatable, Identifiable, Sendable {
    public enum Behavior: String, Codable, CaseIterable, Sendable { case tile, float }

    public var id: UUID
    public var bundleID: String
    public var name: String
    public var behavior: Behavior
    /// Initial width as a fraction of the viewport; nil follows `Preferences.newWindowWidth`.
    public var width: Double?
    public var openAt: InsertPosition

    public init(id: UUID = UUID(), bundleID: String, name: String, behavior: Behavior = .tile,
                width: Double? = nil, openAt: InsertPosition = .afterFocused) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.behavior = behavior
        self.width = width
        self.openAt = openAt
    }

    /// Only `bundleID` is required; a missing `name` falls back to it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleID = try container.decode(String.self, forKey: .bundleID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? bundleID
        behavior = try container.decodeIfPresent(Behavior.self, forKey: .behavior) ?? .tile
        width = try container.decodeIfPresent(Double.self, forKey: .width)
        openAt = try container.decodeIfPresent(InsertPosition.self, forKey: .openAt) ?? .afterFocused
    }
}

/// Everything configurable from the settings window. Stored as JSON in UserDefaults.
public struct Preferences: Codable, Equatable, Sendable {
    public var enabled = true
    public var innerGap: Double = 8
    public var outerGap: Double = 8
    public var presetWidths: [Double] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75]
    public var newWindowWidth: NewWindowWidth = .natural
    public var nudgeStep = 0.05
    public var centerMode: CenterMode = .never
    public var keepOriginalHeight = false
    public var animations = true
    public var animationSpeed = 1.0
    /// A window that another app moves (Rectangle, a title-bar double click) leaves the strip.
    public var floatOnExternalMove = true
    public var indicatorEnabled = true
    public var focusBorder = FocusBorderPrefs()
    public var dimInactive = DimPrefs()
    public var focusFollowsMouse = false
    public var mouseFollowsFocus = false
    public var trackpad = TrackpadPrefs()
    public var mouse = MousePrefs()
    public var mouseButtons = MouseButtonsPrefs()
    /// What a short swipe up or down does, on the trackpad and with the mouse's buttons.
    public var verticalGesture: VerticalGesture = .strips
    public var appRules: [AppRule] = []
    /// UUIDs of the displays Rambla does not manage.
    public var disabledDisplays: [String] = []
    /// Only the actions whose shortcuts differ from `DefaultShortcuts.table` are stored here.
    public var shortcutOverrides: [Action: [KeyCombo]] = [:]
    /// Look for a new release on GitHub once a day.
    public var checkForUpdates = true
    /// In the overview and on the veil, a browser window shows the site it is on: Rambla reads the page's address and
    /// asks the site for its icon. Off unless the user turns it on, as it is a connection to the internet.
    public var siteIcons = false

    public init() {}

    /// Every field is optional in the stored JSON: a missing key takes its default (the value set above),
    /// so adding a preference later never invalidates what users already saved.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        innerGap = try container.decodeIfPresent(Double.self, forKey: .innerGap) ?? innerGap
        outerGap = try container.decodeIfPresent(Double.self, forKey: .outerGap) ?? outerGap
        presetWidths = try container.decodeIfPresent([Double].self, forKey: .presetWidths) ?? presetWidths
        newWindowWidth = try container.decodeIfPresent(NewWindowWidth.self, forKey: .newWindowWidth) ?? newWindowWidth
        nudgeStep = try container.decodeIfPresent(Double.self, forKey: .nudgeStep) ?? nudgeStep
        centerMode = try container.decodeIfPresent(CenterMode.self, forKey: .centerMode) ?? centerMode
        keepOriginalHeight = try container.decodeIfPresent(Bool.self, forKey: .keepOriginalHeight) ?? keepOriginalHeight
        animations = try container.decodeIfPresent(Bool.self, forKey: .animations) ?? animations
        animationSpeed = try container.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? animationSpeed
        floatOnExternalMove = try container.decodeIfPresent(Bool.self, forKey: .floatOnExternalMove) ?? floatOnExternalMove
        indicatorEnabled = try container.decodeIfPresent(Bool.self, forKey: .indicatorEnabled) ?? indicatorEnabled
        focusBorder = try container.decodeIfPresent(FocusBorderPrefs.self, forKey: .focusBorder) ?? focusBorder
        dimInactive = try container.decodeIfPresent(DimPrefs.self, forKey: .dimInactive) ?? dimInactive
        focusFollowsMouse = try container.decodeIfPresent(Bool.self, forKey: .focusFollowsMouse) ?? focusFollowsMouse
        mouseFollowsFocus = try container.decodeIfPresent(Bool.self, forKey: .mouseFollowsFocus) ?? mouseFollowsFocus
        trackpad = try container.decodeIfPresent(TrackpadPrefs.self, forKey: .trackpad) ?? trackpad
        mouse = try container.decodeIfPresent(MousePrefs.self, forKey: .mouse) ?? mouse
        mouseButtons = try container.decodeIfPresent(MouseButtonsPrefs.self, forKey: .mouseButtons) ?? mouseButtons
        verticalGesture = try container.decodeIfPresent(VerticalGesture.self, forKey: .verticalGesture) ?? verticalGesture
        appRules = try container.decodeIfPresent([AppRule].self, forKey: .appRules) ?? appRules
        disabledDisplays = try container.decodeIfPresent([String].self, forKey: .disabledDisplays) ?? disabledDisplays
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? checkForUpdates
        siteIcons = try container.decodeIfPresent(Bool.self, forKey: .siteIcons) ?? siteIcons
        // Decoded through plain strings so an id this version does not know (a downgrade, a removed action) is
        // skipped instead of making the whole dictionary, and with it every preference, fail to load.
        if let stored = try container.decodeIfPresent([String: [KeyCombo]].self, forKey: .shortcutOverrides) {
            var overrides: [Action: [KeyCombo]] = [:]
            for (id, combos) in stored {
                if let action = Action(rawValue: id) { overrides[action] = combos }
            }
            shortcutOverrides = overrides
        }
    }

    /// The shortcuts in effect for an action: the user's override, or the defaults the user has not given to another
    /// action (a default that comes with a new version must not take a combination already in use).
    public func shortcuts(for action: Action) -> [KeyCombo] {
        if let combos = shortcutOverrides[action] { return combos }
        let taken = Set(shortcutOverrides.filter { $0.key != action }.values.joined())
        return (DefaultShortcuts.table[action] ?? []).filter { !taken.contains($0) }
    }

    /// Stores the user's shortcuts for an action. Setting exactly what the defaults give removes the override, so
    /// later changes to the defaults still reach users who never customized that action.
    public mutating func setShortcuts(_ combos: [KeyCombo], for action: Action) {
        shortcutOverrides[action] = nil
        if combos != shortcuts(for: action) { shortcutOverrides[action] = combos }
    }

    /// The first rule written for this app, if any.
    public func rule(for bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return appRules.first { $0.bundleID == bundleID }
    }

    /// The shortcuts in effect for every action (an action without any maps to an empty list).
    public var allShortcuts: [Action: [KeyCombo]] {
        var all: [Action: [KeyCombo]] = [:]
        for action in Action.allCases { all[action] = shortcuts(for: action) }
        return all
    }
}
