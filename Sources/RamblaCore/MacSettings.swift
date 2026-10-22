import Foundation

/// Whether Rectangle is running and, if so, which Rambla shortcuts it also binds.
public enum RectangleStatus: Equatable, Sendable {
    case notRunning
    case running(conflicts: [ShortcutConflict])
}

/// The macOS settings that affect Rambla, exactly as read from preferences.
///
/// A flag is optional because an absent key means the user never changed the system default, and for some settings
/// that default is not "off" (`rearrangeSpaces`). Everything here is plain data so `MacChecks` can be tested without
/// touching the system.
public struct MacSettings: Equatable, Sendable {
    /// Rambla has the Accessibility permission (`AXIsProcessTrusted`).
    public var accessibilityTrusted: Bool
    /// `com.apple.spaces` `spans-displays`: true means every display shares one set of Spaces.
    public var displaysShareSpaces: Bool?
    /// `com.apple.dock` `mru-spaces`: Spaces reorder themselves by most recent use. macOS ships it on.
    public var rearrangeSpaces: Bool?
    /// `com.apple.WindowManager` `GloballyEnabled`: Stage Manager.
    public var stageManager: Bool?
    /// `com.apple.WindowManager` `EnableTilingByEdgeDrag`: dragging a window to a screen edge tiles it.
    public var tilingByEdgeDrag: Bool?
    /// `com.apple.WindowManager` `EnableTopTilingByEdgeDrag`: dragging a window to the menu bar fills the screen.
    public var tilingToMenuBar: Bool?
    /// `com.apple.WindowManager` `EnableTilingOptionAccelerator`: holding ⌥ while dragging tiles the window.
    public var tilingWithOption: Bool?
    /// macOS 15 and later tile by dragging out of the box: there, an absent tiling key means on.
    public var macOSTilesByDefault: Bool
    /// `TrackpadThreeFingerHorizSwipeGesture`, one entry for each trackpad preferences domain that defines it
    /// (`com.apple.AppleMultitouchTrackpad` is the built-in trackpad and
    /// `com.apple.driver.AppleBluetoothMultitouch.trackpad` a Magic Trackpad). The value 2 means
    /// "swipe between full-screen apps", which is what switches Spaces.
    public var threeFingerSwipe: [Int]
    /// `TrackpadFourFingerHorizSwipeGesture`, one entry for each domain that defines it. Same values as above.
    public var fourFingerSwipe: [Int]
    /// `TrackpadThreeFingerVertSwipeGesture`: 2 means Mission Control (up) and App Exposé (down).
    public var threeFingerVertSwipe: [Int]
    /// `TrackpadFourFingerVertSwipeGesture`, with the same values.
    public var fourFingerVertSwipe: [Int]
    /// `TrackpadThreeFingerDrag`, one entry for each domain that defines it.
    public var threeFingerDrag: [Bool]
    /// Rambla can change the swipes above itself, through the back end of the Trackpad pane (private API, so a
    /// macOS update could take it away). Without it, a conflict row explains how to change them by hand.
    public var canChangeTrackpadGestures: Bool
    public var rectangle: RectangleStatus

    /// The defaults describe a Mac where every key is absent, nothing is granted and Rectangle is closed.
    public init(accessibilityTrusted: Bool = false,
                displaysShareSpaces: Bool? = nil,
                rearrangeSpaces: Bool? = nil,
                stageManager: Bool? = nil,
                tilingByEdgeDrag: Bool? = nil,
                tilingToMenuBar: Bool? = nil,
                tilingWithOption: Bool? = nil,
                macOSTilesByDefault: Bool = false,
                threeFingerSwipe: [Int] = [],
                fourFingerSwipe: [Int] = [],
                threeFingerVertSwipe: [Int] = [],
                fourFingerVertSwipe: [Int] = [],
                threeFingerDrag: [Bool] = [],
                canChangeTrackpadGestures: Bool = false,
                rectangle: RectangleStatus = .notRunning) {
        self.accessibilityTrusted = accessibilityTrusted
        self.displaysShareSpaces = displaysShareSpaces
        self.rearrangeSpaces = rearrangeSpaces
        self.stageManager = stageManager
        self.tilingByEdgeDrag = tilingByEdgeDrag
        self.tilingToMenuBar = tilingToMenuBar
        self.tilingWithOption = tilingWithOption
        self.macOSTilesByDefault = macOSTilesByDefault
        self.threeFingerSwipe = threeFingerSwipe
        self.fourFingerSwipe = fourFingerSwipe
        self.threeFingerVertSwipe = threeFingerVertSwipe
        self.fourFingerVertSwipe = fourFingerVertSwipe
        self.threeFingerDrag = threeFingerDrag
        self.canChangeTrackpadGestures = canChangeTrackpadGestures
        self.rectangle = rectangle
    }
}

/// One row of "Configuración → Mac". The app maps it one to one onto its `CheckResult`.
public struct MacCheck: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case ok, warning, info }

    /// A change Rambla can make itself, offered as a button on the row.
    public enum Fix: Equatable, Sendable {
        /// Turn off the macOS horizontal swipe with this many fingers (switching desktops or pages).
        case turnOffSwipe(fingers: Int)
        /// Turn off the macOS vertical swipe with this many fingers (Mission Control and App Exposé).
        case turnOffVerticalSwipe(fingers: Int)

        public var title: String {
            switch self {
            case .turnOffSwipe, .turnOffVerticalSwipe: return String(localized: "Apagarlo en macOS")
            }
        }
    }

    public var id: String
    public var title: String
    public var status: Status
    public var detail: String
    /// A System Settings pane that holds the setting, if there is one worth linking.
    public var settingsURL: URL?
    public var fix: Fix?

    public init(id: String, title: String, status: Status, detail: String, settingsURL: URL? = nil, fix: Fix? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.settingsURL = settingsURL
        self.fix = fix
    }
}

/// Turns the raw macOS settings into the rows of the Mac page. The copy is Spanish, translated through
/// Localizable.strings (in tests, without the app's translations, it stays Spanish).
public enum MacChecks {
    public static let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    public static let desktopAndDockURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
    public static let trackpadURL = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!

    /// The rows about the trackpad gesture, which the trackpad pages show next to the gesture's settings.
    public static let trackpadCheckIDs = ["trackpad-gesture", "vertical-gesture", "three-finger-drag"]

    /// The macOS value of the swipe-between-full-screen-apps gesture, which is what switches Spaces.
    private static let switchSpacesGesture = 2
    /// The macOS value of the three-finger swipe between pages (back and forward in browsers and Finder).
    private static let swipePagesGesture = 1
    /// How many conflicting actions the Rectangle row names before it says "y N más".
    private static let namedConflicts = 3

    /// Rows in display order. The Rectangle row exists only while Rectangle is running.
    public static func evaluate(_ settings: MacSettings, trackpad: TrackpadPrefs) -> [MacCheck] {
        var checks = [
            accessibility(settings),
            separateSpaces(settings),
            rearrangeSpaces(settings),
            stageManager(settings),
            tiling(settings),
            trackpadGesture(settings, trackpad),
            verticalGesture(settings, trackpad),
            threeFingerDrag(settings, trackpad),
        ]
        if let rectangle = rectangle(settings) { checks.append(rectangle) }
        return checks
    }

    // MARK: Checks

    private static func accessibility(_ s: MacSettings) -> MacCheck {
        MacCheck(
            id: "accessibility", title: String(localized: "Accesibilidad"),
            status: s.accessibilityTrusted ? .ok : .warning,
            detail: s.accessibilityTrusted
                ? String(localized: "Permiso concedido.")
                : String(localized: "Falta el permiso. Sin él Rambla no puede mover ni enfocar ventanas."),
            settingsURL: accessibilityURL)
    }

    /// Absent or false is fine: macOS ships with a separate set of Spaces for each display.
    private static func separateSpaces(_ s: MacSettings) -> MacCheck {
        let shared = s.displaysShareSpaces == true
        return MacCheck(
            id: "separate-spaces", title: String(localized: "Spaces separados"),
            status: shared ? .warning : .ok,
            detail: shared
                ? String(localized: "Las pantallas comparten los mismos Spaces. Conviene activar «Las pantallas tienen Spaces independientes» (hay que cerrar sesión para que se aplique).")
                : String(localized: "Cada pantalla tiene sus propios Spaces."))
    }

    /// Absent counts as on, because that is the macOS default.
    private static func rearrangeSpaces(_ s: MacSettings) -> MacCheck {
        let rearranges = s.rearrangeSpaces != false
        return MacCheck(
            id: "rearrange-spaces", title: String(localized: "Reorganizar Spaces"),
            status: rearranges ? .warning : .ok,
            detail: rearranges
                ? String(localized: "Recomendado: apagado. macOS reordena los Spaces según el uso reciente y cuesta saber qué tira hay en cada uno (Escritorio y Dock → Mission Control).")
                : String(localized: "Los Spaces conservan su orden."),
            settingsURL: desktopAndDockURL)
    }

    private static func stageManager(_ s: MacSettings) -> MacCheck {
        let on = s.stageManager == true
        return MacCheck(
            id: "stage-manager", title: String(localized: "Organizador visual"),
            status: on ? .warning : .ok,
            detail: on
                ? String(localized: "El Organizador visual está activado y acomoda las ventanas por su cuenta, lo que choca con Rambla. Conviene apagarlo.")
                : String(localized: "Apagado."))
    }

    private static func tiling(_ s: MacSettings) -> MacCheck {
        let active = [
            (s.tilingByEdgeDrag, String(localized: "arrastrar a los bordes")),
            (s.tilingToMenuBar, String(localized: "arrastrar a la barra de menús")),
            (s.tilingWithOption, String(localized: "arrastrar con la tecla Opción")),
        ].compactMap { ($0.0 ?? s.macOSTilesByDefault) ? $0.1 : nil }
        let list = active.joined(separator: ", ")
        return MacCheck(
            id: "macos-tiling", title: String(localized: "Mosaico por arrastre de macOS"),
            status: active.isEmpty ? .ok : .warning,
            detail: active.isEmpty
                ? String(localized: "Apagado.")
                : String(localized: "macOS acomoda las ventanas al arrastrarlas (\(list)) y compite con Rambla. Conviene apagarlo en Escritorio y Dock."),
            settingsURL: desktopAndDockURL)
    }

    /// Only the swipe with Rambla's finger count matters. Three fingers collide with both "swipe between pages" (1)
    /// and "swipe between full-screen apps" (2, which switches desktops); four fingers only ever switch desktops.
    /// Either trackpad (built-in or Magic Trackpad) can be the one in use, and an absent key is not a conflict.
    ///
    /// The Trackpad pane hides one trap: its «3 dedos» option for full-screen apps stores 2 for both three and four
    /// fingers, so a four-finger Rambla swipe also switches desktops while the pane reads «3 dedos», and the pane has
    /// no way to turn off only the four-finger one. Rambla can (`Fix.turnOffSwipe`), when the back end is there.
    private static func trackpadGesture(_ s: MacSettings, _ trackpad: TrackpadPrefs) -> MacCheck {
        let id = "trackpad-gesture", title = String(localized: "Gesto del trackpad")
        guard trackpad.enabled else {
            return MacCheck(id: id, title: title, status: .ok,
                            detail: String(localized: "El gesto de Rambla está desactivado: no hay conflicto."),
                            settingsURL: trackpadURL)
        }
        let fingers = trackpad.fingers
        let threeSwitches = s.threeFingerSwipe.contains(switchSpacesGesture)
        let fourSwitches = s.fourFingerSwipe.contains(switchSpacesGesture)
        let threePages = s.threeFingerSwipe.contains(swipePagesGesture)
        let canFix = s.canChangeTrackpadGestures
        let button = MacCheck.Fix.turnOffSwipe(fingers: fingers).title
        let problem: String, remedy: String
        switch fingers {
        case 4 where fourSwitches && threeSwitches:
            problem = String(localized: "macOS también cambia de escritorio con 4 dedos: su opción «3 dedos» de «Cambiar entre apps en pantalla completa» activa también el de 4, y Configuración del Sistema no deja apagar solo ese.")
            remedy = canFix
                ? String(localized: "«\(button)» lo apaga y macOS sigue cambiando de escritorio con 3 dedos.")
                : String(localized: "Elegí «Desactivado» en Trackpad → Más gestos, o pasá Rambla a 3 dedos y macOS a «4 dedos».")
        case 4 where fourSwitches:
            problem = String(localized: "macOS cambia de escritorio con 4 dedos, el mismo gesto que usa Rambla.")
            remedy = canFix
                ? String(localized: "«\(button)» lo apaga; para cambiar de escritorio quedan ⌃← y ⌃→.")
                : String(localized: "Elegí «Desactivado» en Trackpad → Más gestos → «Cambiar entre apps en pantalla completa».")
        case 3 where threeSwitches:
            problem = String(localized: "macOS también cambia de escritorio con 3 dedos («Cambiar entre apps en pantalla completa»).")
            if !canFix {
                remedy = String(localized: "Elegí «4 dedos» o «Desactivado» en Trackpad → Más gestos.")
            } else if fourSwitches {
                remedy = String(localized: "«\(button)» apaga ese gesto y macOS sigue cambiando de escritorio con 4 dedos.")
            } else {
                remedy = String(localized: "«\(button)» apaga ese gesto; para cambiar de escritorio quedan ⌃← y ⌃→.")
            }
        case 3 where threePages:
            problem = String(localized: "macOS pasa de página con 3 dedos y lo haría a la vez que Rambla mueve la tira.")
            remedy = canFix
                ? String(localized: "«\(button)» apaga ese gesto.")
                : String(localized: "Elegí «Ir a la izquierda o la derecha con 2 dedos» en Trackpad → Más gestos → «Cambiar de página».")
        default:
            return MacCheck(id: id, title: title, status: .ok,
                            detail: String(localized: "macOS no usa el deslizamiento horizontal de \(fingers) dedos."),
                            settingsURL: trackpadURL)
        }
        return MacCheck(id: id, title: title, status: .warning, detail: problem + " " + remedy, settingsURL: trackpadURL,
                        fix: canFix ? .turnOffSwipe(fingers: fingers) : nil)
    }

    /// Rambla's swipe up (full width) and down collide with Mission Control and App Exposé when macOS uses the same
    /// fingers for them. The pane's «3 dedos» choice for Mission Control also stores 2 for four fingers, the same
    /// trap as the horizontal swipe.
    private static func verticalGesture(_ s: MacSettings, _ trackpad: TrackpadPrefs) -> MacCheck {
        let id = "vertical-gesture", title = String(localized: "Gesto hacia arriba y abajo")
        guard trackpad.enabled, trackpad.verticalSwipe else {
            return MacCheck(id: id, title: title, status: .ok,
                            detail: String(localized: "El gesto vertical de Rambla está desactivado: no hay conflicto."),
                            settingsURL: trackpadURL)
        }
        let fingers = trackpad.fingers
        let three = s.threeFingerVertSwipe.contains(switchSpacesGesture)
        let four = s.fourFingerVertSwipe.contains(switchSpacesGesture)
        let canFix = s.canChangeTrackpadGestures
        let button = MacCheck.Fix.turnOffVerticalSwipe(fingers: fingers).title
        let problem: String, remedy: String
        switch fingers {
        case 4 where four && three:
            problem = String(localized: "macOS también abre Mission Control con 4 dedos hacia arriba: su opción «3 dedos» de Mission Control activa también el de 4.")
            remedy = canFix
                ? String(localized: "«\(button)» lo apaga y Mission Control sigue con 3 dedos.")
                : String(localized: "Desactivá Mission Control y Exposé en Trackpad → Más gestos, o apagá el gesto vertical de Rambla.")
        case 4 where four:
            problem = String(localized: "macOS abre Mission Control con 4 dedos hacia arriba, el mismo gesto que usa Rambla.")
            remedy = canFix
                ? String(localized: "«\(button)» lo apaga; Mission Control queda en ⌃↑.")
                : String(localized: "Elegí «3 dedos» o «Desactivado» para Mission Control en Trackpad → Más gestos.")
        case 3 where three:
            problem = String(localized: "macOS abre Mission Control con 3 dedos hacia arriba, el mismo gesto que usa Rambla.")
            remedy = canFix
                ? String(localized: "«\(button)» lo apaga; Mission Control queda en ⌃↑.")
                : String(localized: "Elegí «4 dedos» o «Desactivado» para Mission Control en Trackpad → Más gestos.")
        default:
            return MacCheck(id: id, title: title, status: .ok,
                            detail: String(localized: "macOS no usa el deslizamiento vertical de \(fingers) dedos."),
                            settingsURL: trackpadURL)
        }
        return MacCheck(id: id, title: title, status: .warning, detail: problem + " " + remedy, settingsURL: trackpadURL,
                        fix: canFix ? .turnOffVerticalSwipe(fingers: fingers) : nil)
    }

    /// Three-finger drag takes over every three-finger movement, so it only collides with a three-finger Rambla gesture.
    private static func threeFingerDrag(_ s: MacSettings, _ trackpad: TrackpadPrefs) -> MacCheck {
        let on = s.threeFingerDrag.contains(true)
        let conflict = on && trackpad.enabled && trackpad.fingers == 3
        return MacCheck(
            id: "three-finger-drag", title: String(localized: "Arrastre con tres dedos"),
            status: conflict ? .warning : .ok,
            detail: conflict
                ? String(localized: "El arrastre con tres dedos choca con el deslizamiento de 3 dedos de Rambla. Conviene usar 4 dedos en Rambla o apagarlo en Accesibilidad → Control del puntero → Opciones del trackpad.")
                : (on ? String(localized: "Activado, pero no choca con el gesto de Rambla.") : String(localized: "Apagado.")))
    }

    /// Informational while the shortcuts do not collide; a warning as soon as one does.
    private static func rectangle(_ s: MacSettings) -> MacCheck? {
        guard case .running(let conflicts) = s.rectangle else { return nil }
        guard !conflicts.isEmpty else {
            return MacCheck(id: "rectangle", title: "Rectangle", status: .info,
                            detail: String(localized: "Rectangle detectado — convivencia activa. Atajos en conflicto: 0."))
        }
        var titles: [String] = []
        for conflict in conflicts where !titles.contains(conflict.action.title) { titles.append(conflict.action.title) }
        var named = titles.prefix(namedConflicts).joined(separator: ", ")
        if titles.count > namedConflicts { named = String(localized: "\(named) y \(titles.count - namedConflicts) más") }
        return MacCheck(
            id: "rectangle", title: "Rectangle", status: .warning,
            detail: String(localized: "Rectangle detectado — convivencia activa. Atajos en conflicto: \(conflicts.count) (\(named)). Se cambian en la sección Atajos."))
    }
}
