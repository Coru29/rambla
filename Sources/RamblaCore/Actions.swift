import Foundation

/// How the Shortcuts settings page groups actions.
public enum ActionGroup: String, CaseIterable, Sendable {
    case navigate, size, stacks, other

    public var title: String {
        switch self {
        case .navigate: return "Navegar"
        case .size: return "Tamaño"
        case .stacks: return "Pilas y pestañas"
        case .other: return "Otros"
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

    /// Spanish label shown in the Shortcuts page and in exported Raycast scripts.
    public var title: String {
        switch self {
        case .focusLeft: return "Enfocar columna izquierda"
        case .focusRight: return "Enfocar columna derecha"
        case .focusUp: return "Enfocar ventana de arriba"
        case .focusDown: return "Enfocar ventana de abajo"
        case .focusFirst: return "Ir a la primera columna"
        case .focusLast: return "Ir a la última columna"
        case .focus1: return "Ir a la columna 1"
        case .focus2: return "Ir a la columna 2"
        case .focus3: return "Ir a la columna 3"
        case .focus4: return "Ir a la columna 4"
        case .focus5: return "Ir a la columna 5"
        case .focus6: return "Ir a la columna 6"
        case .focus7: return "Ir a la columna 7"
        case .focus8: return "Ir a la columna 8"
        case .focus9: return "Ir a la columna 9"
        case .moveLeft: return "Mover columna a la izquierda"
        case .moveRight: return "Mover columna a la derecha"
        case .moveUp: return "Mover ventana hacia arriba"
        case .moveDown: return "Mover ventana hacia abajo"
        case .sendNextDisplay: return "Mandar a la siguiente pantalla"
        case .cycleWidth: return "Rotar ancho"
        case .fullWidth: return "Ancho completo"
        case .center: return "Centrar columna"
        case .wider: return "Más ancha"
        case .narrower: return "Más angosta"
        case .taller: return "Más alta"
        case .shorter: return "Más baja"
        case .equalizeHeights: return "Igualar alturas"
        case .pinLeft: return "Fijar a la izquierda"
        case .pinRight: return "Fijar a la derecha"
        case .stackLeft: return "Apilar en la columna izquierda"
        case .stackRight: return "Apilar en la columna derecha"
        case .popLeft: return "Sacar de la pila hacia la izquierda"
        case .popRight: return "Sacar de la pila hacia la derecha"
        case .toggleTabbed: return "Alternar pila / pestañas"
        case .toggleFloat: return "Flotar / volver a la tira"
        case .closeWindow: return "Cerrar ventana"
        case .togglePause: return "Pausar / reanudar Rambla"
        }
    }

    public var group: ActionGroup {
        switch self {
        case .focusLeft, .focusRight, .focusUp, .focusDown, .focusFirst, .focusLast,
             .focus1, .focus2, .focus3, .focus4, .focus5, .focus6, .focus7, .focus8, .focus9,
             .moveLeft, .moveRight, .moveUp, .moveDown, .sendNextDisplay:
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
