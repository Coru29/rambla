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
    /// `TrackpadThreeFingerHorizSwipeGesture`, one entry for each trackpad preferences domain that defines it
    /// (`com.apple.AppleMultitouchTrackpad` is the built-in trackpad and
    /// `com.apple.driver.AppleBluetoothMultitouch.trackpad` a Magic Trackpad). The value 2 means
    /// "swipe between full-screen apps", which is what switches Spaces.
    public var threeFingerSwipe: [Int]
    /// `TrackpadFourFingerHorizSwipeGesture`, one entry for each domain that defines it. Same values as above.
    public var fourFingerSwipe: [Int]
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
                threeFingerSwipe: [Int] = [],
                fourFingerSwipe: [Int] = [],
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
        self.threeFingerSwipe = threeFingerSwipe
        self.fourFingerSwipe = fourFingerSwipe
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

        public var title: String {
            switch self {
            case .turnOffSwipe: return "Apagarlo en macOS"
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

/// Turns the raw macOS settings into the rows of the Mac page. UI copy is Spanish.
public enum MacChecks {
    public static let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    public static let desktopAndDockURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
    public static let trackpadURL = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!

    /// The rows about the trackpad gesture, which the trackpad pages show next to the gesture's settings.
    public static let trackpadCheckIDs = ["trackpad-gesture", "three-finger-drag"]

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
            threeFingerDrag(settings, trackpad),
        ]
        if let rectangle = rectangle(settings) { checks.append(rectangle) }
        return checks
    }

    // MARK: Checks

    private static func accessibility(_ s: MacSettings) -> MacCheck {
        MacCheck(
            id: "accessibility", title: "Accesibilidad",
            status: s.accessibilityTrusted ? .ok : .warning,
            detail: s.accessibilityTrusted
                ? "Permiso concedido."
                : "Falta el permiso. Sin él Rambla no puede mover ni enfocar ventanas.",
            settingsURL: accessibilityURL)
    }

    /// Absent or false is fine: macOS ships with a separate set of Spaces for each display.
    private static func separateSpaces(_ s: MacSettings) -> MacCheck {
        let shared = s.displaysShareSpaces == true
        return MacCheck(
            id: "separate-spaces", title: "Spaces separados",
            status: shared ? .warning : .ok,
            detail: shared
                ? "Las pantallas comparten los mismos Spaces. Conviene activar «Las pantallas tienen Spaces independientes» (hay que cerrar sesión para que se aplique)."
                : "Cada pantalla tiene sus propios Spaces.")
    }

    /// Absent counts as on, because that is the macOS default.
    private static func rearrangeSpaces(_ s: MacSettings) -> MacCheck {
        let rearranges = s.rearrangeSpaces != false
        return MacCheck(
            id: "rearrange-spaces", title: "Reorganizar Spaces",
            status: rearranges ? .warning : .ok,
            detail: rearranges
                ? "Recomendado: apagado. macOS reordena los Spaces según el uso reciente y cuesta saber qué tira hay en cada uno (Escritorio y Dock → Mission Control)."
                : "Los Spaces conservan su orden.",
            settingsURL: desktopAndDockURL)
    }

    private static func stageManager(_ s: MacSettings) -> MacCheck {
        let on = s.stageManager == true
        return MacCheck(
            id: "stage-manager", title: "Stage Manager",
            status: on ? .warning : .ok,
            detail: on
                ? "Stage Manager (Organizador visual) está activado y acomoda las ventanas por su cuenta, lo que choca con Rambla. Conviene apagarlo."
                : "Apagado.")
    }

    private static func tiling(_ s: MacSettings) -> MacCheck {
        let active = [
            (s.tilingByEdgeDrag, "arrastrar a los bordes"),
            (s.tilingToMenuBar, "arrastrar a la barra de menús"),
            (s.tilingWithOption, "arrastrar con la tecla Opción"),
        ].compactMap { $0.0 == true ? $0.1 : nil }
        return MacCheck(
            id: "macos-tiling", title: "Mosaico por arrastre de macOS",
            status: active.isEmpty ? .ok : .warning,
            detail: active.isEmpty
                ? "Apagado."
                : "macOS acomoda las ventanas al arrastrarlas (\(active.joined(separator: ", "))) y compite con Rambla. Conviene apagarlo en Escritorio y Dock.")
    }

    /// Only the swipe with Rambla's finger count matters. Three fingers collide with both "swipe between pages" (1)
    /// and "swipe between full-screen apps" (2, which switches desktops); four fingers only ever switch desktops.
    /// Either trackpad (built-in or Magic Trackpad) can be the one in use, and an absent key is not a conflict.
    ///
    /// The Trackpad pane hides one trap: its «3 dedos» option for full-screen apps stores 2 for both three and four
    /// fingers, so a four-finger Rambla swipe also switches desktops while the pane reads «3 dedos», and the pane has
    /// no way to turn off only the four-finger one. Rambla can (`Fix.turnOffSwipe`), when the back end is there.
    private static func trackpadGesture(_ s: MacSettings, _ trackpad: TrackpadPrefs) -> MacCheck {
        let id = "trackpad-gesture", title = "Gesto del trackpad"
        guard trackpad.enabled else {
            return MacCheck(id: id, title: title, status: .ok,
                            detail: "El gesto de Rambla está desactivado: no hay conflicto.", settingsURL: trackpadURL)
        }
        let fingers = trackpad.fingers
        let threeSwitches = s.threeFingerSwipe.contains(switchSpacesGesture)
        let fourSwitches = s.fourFingerSwipe.contains(switchSpacesGesture)
        let threePages = s.threeFingerSwipe.contains(swipePagesGesture)
        let detail: String
        switch fingers {
        case 4 where fourSwitches && threeSwitches:
            detail = "macOS también cambia de escritorio con 4 dedos: su opción «3 dedos» de «Cambiar entre apps en pantalla completa» activa también el de 4, y Ajustes no deja apagar solo ese. "
                + (s.canChangeTrackpadGestures
                    ? "«\(MacCheck.Fix.turnOffSwipe(fingers: 4).title)» lo apaga y macOS sigue cambiando de escritorio con 3 dedos."
                    : "Elegí «Desactivado» en Trackpad → Más gestos, o pasá Rambla a 3 dedos y macOS a «4 dedos».")
        case 4 where fourSwitches:
            detail = "macOS cambia de escritorio con 4 dedos, el mismo gesto que usa Rambla. "
                + (s.canChangeTrackpadGestures
                    ? "«\(MacCheck.Fix.turnOffSwipe(fingers: 4).title)» lo apaga; para cambiar de escritorio quedan ⌃← y ⌃→."
                    : "Elegí «Desactivado» en Trackpad → Más gestos → «Cambiar entre apps en pantalla completa».")
        case 3 where threeSwitches:
            detail = "macOS también cambia de escritorio con 3 dedos («Cambiar entre apps en pantalla completa»). "
                + (s.canChangeTrackpadGestures
                    ? "«\(MacCheck.Fix.turnOffSwipe(fingers: 3).title)» apaga ese gesto"
                        + (fourSwitches ? " y macOS sigue cambiando de escritorio con 4 dedos." : "; para cambiar de escritorio quedan ⌃← y ⌃→.")
                    : "Elegí «4 dedos» o «Desactivado» en Trackpad → Más gestos.")
        case 3 where threePages:
            detail = "macOS pasa de página con 3 dedos y lo haría a la vez que Rambla mueve la tira. "
                + (s.canChangeTrackpadGestures
                    ? "«\(MacCheck.Fix.turnOffSwipe(fingers: 3).title)» apaga ese gesto."
                    : "Elegí «Ir a la izquierda o la derecha con 2 dedos» en Trackpad → Más gestos → «Cambiar de página».")
        default:
            return MacCheck(id: id, title: title, status: .ok,
                            detail: "macOS no usa el deslizamiento horizontal de \(fingers) dedos.", settingsURL: trackpadURL)
        }
        return MacCheck(id: id, title: title, status: .warning, detail: detail, settingsURL: trackpadURL,
                        fix: s.canChangeTrackpadGestures ? .turnOffSwipe(fingers: fingers) : nil)
    }

    /// Three-finger drag takes over every three-finger movement, so it only collides with a three-finger Rambla gesture.
    private static func threeFingerDrag(_ s: MacSettings, _ trackpad: TrackpadPrefs) -> MacCheck {
        let on = s.threeFingerDrag.contains(true)
        let conflict = on && trackpad.enabled && trackpad.fingers == 3
        return MacCheck(
            id: "three-finger-drag", title: "Arrastre con tres dedos",
            status: conflict ? .warning : .ok,
            detail: conflict
                ? "El arrastre con tres dedos choca con el deslizamiento de 3 dedos de Rambla. Conviene usar 4 dedos en Rambla o apagarlo en Accesibilidad → Control del puntero → Opciones del trackpad."
                : (on ? "Activado, pero no choca con el gesto de Rambla." : "Apagado."))
    }

    /// Informational while the shortcuts do not collide; a warning as soon as one does.
    private static func rectangle(_ s: MacSettings) -> MacCheck? {
        guard case .running(let conflicts) = s.rectangle else { return nil }
        let intro = "Rectangle detectado — convivencia activa."
        guard !conflicts.isEmpty else {
            return MacCheck(id: "rectangle", title: "Rectangle", status: .info, detail: "\(intro) Atajos en conflicto: 0.")
        }
        var titles: [String] = []
        for conflict in conflicts where !titles.contains(conflict.action.title) { titles.append(conflict.action.title) }
        var named = titles.prefix(namedConflicts).joined(separator: ", ")
        if titles.count > namedConflicts { named += " y \(titles.count - namedConflicts) más" }
        return MacCheck(
            id: "rectangle", title: "Rectangle", status: .warning,
            detail: "\(intro) Atajos en conflicto: \(conflicts.count) (\(named)). Se cambian en la sección Atajos.")
    }
}
