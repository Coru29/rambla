import RamblaCore
import SwiftUI

/// "Atajos": every action grouped as in `ActionGroup`, each with up to two recorders.
struct ShortcutsView: View {
    let backend: SettingsBackend?
    @ObservedObject private var store = PreferencesStore.shared
    @State private var confirmingReset = false

    var body: some View {
        // Read once per render: the backend computes both lists on access.
        let notes = ConflictNotes(prefs: store.prefs, backend: backend)
        Form {
            introSection
            ForEach(ActionGroup.allCases, id: \.self) { group in
                Section(group.title) {
                    ForEach(Action.allCases.filter { $0.group == group }, id: \.self) { action in
                        row(for: action, notes: notes)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("¿Restaurar los atajos predeterminados?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Restaurar", role: .destructive) { store.prefs.shortcutOverrides = [:] }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se pierden todos los atajos que cambiaste.")
        }
    }

    private var introSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Hacé clic en un atajo y escribí el nuevo. ⎋ cancela y ⌫ lo borra.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Restaurar predeterminados") { confirmingReset = true }
                    .disabled(store.prefs.shortcutOverrides.isEmpty)
            }
        }
    }

    private func row(for action: Action, notes: ConflictNotes) -> some View {
        let combos = store.prefs.shortcuts(for: action)
        // An HStack rather than LabeledContent: a long title wraps instead of pushing the recorders under it.
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(action.title)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            ShortcutRecorder(combo: slot(action, 0), conflictText: notes.text(for: action, combos: combos, index: 0),
                             accessibilityTitle: "\(action.title), atajo 1")
            ShortcutRecorder(combo: slot(action, 1), conflictText: notes.text(for: action, combos: combos, index: 1),
                             placeholder: "Otro atajo", accessibilityTitle: "\(action.title), atajo 2")
                .disabled(combos.isEmpty)
        }
    }

    /// The `index`-th shortcut of an action as an optional: nil is an empty slot. Writes go to the store right away
    /// (which persists them and re-registers the hot keys); an empty first slot is filled before the second one.
    private func slot(_ action: Action, _ index: Int) -> Binding<KeyCombo?> {
        Binding(
            get: {
                let combos = store.prefs.shortcuts(for: action)
                return combos.indices.contains(index) ? combos[index] : nil
            },
            set: { newValue in
                let combos = ShortcutSlots.updated(store.prefs.shortcuts(for: action), slot: index, to: newValue)
                store.prefs.setShortcuts(combos, for: action)
            }
        )
    }
}

/// How a recorder writes into the list of shortcuts of one action (at most two are shown).
enum ShortcutSlots {
    /// Replaces the shortcut in slot `index`, fills the slot if it is empty, or removes it when `newValue` is nil.
    /// An empty first slot is filled before the second one, and the same shortcut twice on one action is dropped.
    static func updated(_ combos: [KeyCombo], slot index: Int, to newValue: KeyCombo?) -> [KeyCombo] {
        var result = combos
        if let newValue {
            if result.indices.contains(index) { result[index] = newValue } else { result.append(newValue) }
        } else if result.indices.contains(index) {
            result.remove(at: index)
        }
        var seen: Set<KeyCombo> = []
        return result.filter { seen.insert($0).inserted }
    }
}

/// Why a shortcut cannot be trusted, worked out once per render. Most specific first: another Rambla action using
/// it, then Rectangle, then macOS refusing the registration (which is what a clash with either of them looks like).
@MainActor
private struct ConflictNotes {
    private struct Key: Hashable {
        let action: Action
        let combo: KeyCombo
    }

    private var users: [KeyCombo: [Action]] = [:]
    private var rectangle: [Key: String] = [:]
    private var failures: Set<KeyCombo> = []

    init(prefs: Preferences, backend: SettingsBackend?) {
        for action in Action.allCases {
            for combo in prefs.shortcuts(for: action) { users[combo, default: []].append(action) }
        }
        guard let backend else { return }
        failures = backend.hotkeyFailures
        for conflict in backend.rectangleConflicts {
            let key = Key(action: conflict.action, combo: conflict.combo)
            if rectangle[key] == nil { rectangle[key] = Self.rectangleName(conflict.rectangleAction) }
        }
    }

    func text(for action: Action, combos: [KeyCombo], index: Int) -> String? {
        guard combos.indices.contains(index) else { return nil }
        let combo = combos[index]
        if let other = users[combo]?.first(where: { $0 != action }) { return "Ya lo usa «\(other.title)»" }
        if let name = rectangle[Key(action: action, combo: combo)] { return "Lo usa Rectangle (\(name))" }
        if failures.contains(combo) { return "macOS no lo dejó registrar" }
        return nil
    }

    /// Rectangle's own action ids in Spanish; an id this table does not know is shown as Rectangle names it.
    private static func rectangleName(_ id: String) -> String {
        let names: [String: String] = [
            "leftHalf": "Mitad izquierda", "rightHalf": "Mitad derecha",
            "topHalf": "Mitad superior", "bottomHalf": "Mitad inferior",
            "topLeft": "Esquina superior izquierda", "topRight": "Esquina superior derecha",
            "bottomLeft": "Esquina inferior izquierda", "bottomRight": "Esquina inferior derecha",
            "maximize": "Maximizar", "almostMaximize": "Casi maximizar", "maximizeHeight": "Maximizar alto",
            "previousDisplay": "Pantalla anterior", "nextDisplay": "Pantalla siguiente",
            "larger": "Agrandar", "smaller": "Achicar", "center": "Centrar", "restore": "Restaurar",
            "firstThird": "Primer tercio", "centerThird": "Tercio central", "lastThird": "Último tercio",
            "firstTwoThirds": "Primeros dos tercios", "centerTwoThirds": "Dos tercios centrales",
            "lastTwoThirds": "Últimos dos tercios",
            "moveLeft": "Mover a la izquierda", "moveRight": "Mover a la derecha",
            "moveUp": "Mover hacia arriba", "moveDown": "Mover hacia abajo",
        ]
        return names[id] ?? id
    }
}
