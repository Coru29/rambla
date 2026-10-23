import Foundation

/// How the Shortcuts settings page groups actions.
public enum ActionGroup: String, CaseIterable, Sendable {
    case navigate, size, stacks, other

    public var title: String {
        switch self {
        case .navigate: return String(localized: "Navegar")
        case .size: return String(localized: "Tamaño")
        case .stacks: return String(localized: "Pilas y pestañas")
        case .other: return String(localized: "Otros")
        }
    }
}

/// Every command a user can trigger. The raw value is the id used by `rambla://<id>` and by the `scroll <id>` CLI.
/// `CodingKeyRepresentable` makes `[Action: [KeyCombo]]` encode as a JSON object keyed by that id.
public enum Action: String, CaseIterable, Codable, Sendable, CodingKeyRepresentable {
    case focusLeft = "focus-left"
    case focusRight = "focus-right"
    case focusUp = "focus-up"
    case focusDown = "focus-down"
    case focusFirst = "focus-first"
    case focusLast = "focus-last"
    case focus1 = "focus-1"
    case focus2 = "focus-2"
    case focus3 = "focus-3"
    case focus4 = "focus-4"
    case focus5 = "focus-5"
    case focus6 = "focus-6"
    case focus7 = "focus-7"
    case focus8 = "focus-8"
    case focus9 = "focus-9"
    case moveLeft = "move-left"
    case moveRight = "move-right"
    case moveUp = "move-up"
    case moveDown = "move-down"
    case sendNextDisplay = "send-next-display"
    case stripUp = "strip-up"
    case stripDown = "strip-down"
    case sendStripUp = "send-strip-up"
    case sendStripDown = "send-strip-down"
    case overview
    case cycleWidth = "cycle-width"
    case fullWidth = "full-width"
    case center
    case wider
    case narrower
    case taller
    case shorter
    case equalizeHeights = "equalize-heights"
    case pinLeft = "pin-left"
    case pinRight = "pin-right"
    case stackLeft = "stack-left"
    case stackRight = "stack-right"
    case popLeft = "pop-left"
    case popRight = "pop-right"
    case toggleTabbed = "toggle-tabbed"
    case toggleFloat = "toggle-float"
    case closeWindow = "close-window"
    case togglePause = "toggle-pause"

    /// Label shown in the Shortcuts page and in exported Raycast scripts (Spanish, translated through Localizable.strings).
    public var title: String {
        switch self {
        case .focusLeft: return String(localized: "Enfocar columna izquierda")
        case .focusRight: return String(localized: "Enfocar columna derecha")
        case .focusUp: return String(localized: "Enfocar ventana de arriba")
        case .focusDown: return String(localized: "Enfocar ventana de abajo")
        case .focusFirst: return String(localized: "Ir a la primera columna")
        case .focusLast: return String(localized: "Ir a la última columna")
        case .focus1, .focus2, .focus3, .focus4, .focus5, .focus6, .focus7, .focus8, .focus9:
            let number = Int(rawValue.split(separator: "-").last ?? "") ?? 0
            return String(localized: "Ir a la columna \(number)")
        case .moveLeft: return String(localized: "Mover columna a la izquierda")
        case .moveRight: return String(localized: "Mover columna a la derecha")
        case .moveUp: return String(localized: "Mover ventana hacia arriba")
        case .moveDown: return String(localized: "Mover ventana hacia abajo")
        case .sendNextDisplay: return String(localized: "Mandar a la siguiente pantalla")
        case .stripUp: return String(localized: "Ir a la tira de arriba")
        case .stripDown: return String(localized: "Ir a la tira de abajo")
        case .sendStripUp: return String(localized: "Mandar a la tira de arriba")
        case .sendStripDown: return String(localized: "Mandar a la tira de abajo")
        case .overview: return String(localized: "Vista general")
        case .cycleWidth: return String(localized: "Rotar ancho")
        case .fullWidth: return String(localized: "Ancho completo")
        case .center: return String(localized: "Centrar columna")
        case .wider: return String(localized: "Más ancha")
        case .narrower: return String(localized: "Más angosta")
        case .taller: return String(localized: "Más alta")
        case .shorter: return String(localized: "Más baja")
        case .equalizeHeights: return String(localized: "Igualar alturas")
        case .pinLeft: return String(localized: "Fijar a la izquierda")
        case .pinRight: return String(localized: "Fijar a la derecha")
        case .stackLeft: return String(localized: "Apilar en la columna izquierda")
        case .stackRight: return String(localized: "Apilar en la columna derecha")
        case .popLeft: return String(localized: "Sacar de la pila hacia la izquierda")
        case .popRight: return String(localized: "Sacar de la pila hacia la derecha")
        case .toggleTabbed: return String(localized: "Alternar pila / pestañas")
        case .toggleFloat: return String(localized: "Flotar / volver a la tira")
        case .closeWindow: return String(localized: "Cerrar ventana")
        case .togglePause: return String(localized: "Pausar / reanudar Rambla")
        }
    }

    public var group: ActionGroup {
        switch self {
        case .focusLeft, .focusRight, .focusUp, .focusDown, .focusFirst, .focusLast,
             .focus1, .focus2, .focus3, .focus4, .focus5, .focus6, .focus7, .focus8, .focus9,
             .moveLeft, .moveRight, .moveUp, .moveDown, .sendNextDisplay,
             .stripUp, .stripDown, .sendStripUp, .sendStripDown, .overview:
            return .navigate
        case .cycleWidth, .fullWidth, .center, .wider, .narrower, .taller, .shorter,
             .equalizeHeights, .pinLeft, .pinRight:
            return .size
        case .stackLeft, .stackRight, .popLeft, .popRight, .toggleTabbed, .toggleFloat:
            return .stacks
        case .closeWindow, .togglePause:
            return .other
        }
    }

    /// Reads an action id from a URL host or a CLI word. Case and surrounding whitespace do not matter.
    public static func parse(_ text: String) -> Action? {
        Action(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
