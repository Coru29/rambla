import AppKit
import SwiftUI

/// "Pantallas": which connected displays Rambla manages.
struct DisplaysView: View {
    let backend: SettingsBackend?
    @ObservedObject private var store = PreferencesStore.shared
    /// Bumped when macOS reports a display change, so the list is read from the backend again.
    @State private var displaysVersion = 0

    var body: some View {
        let _ = displaysVersion
        Form {
            Section {
                if rows.isEmpty {
                    Text("No encontré pantallas.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.uuid) { row in
                    Toggle(row.title, isOn: managed(row.uuid))
                }
            } header: {
                Text("Pantallas conectadas")
            } footer: {
                Text("Rambla no mueve las ventanas de las pantallas que desactives: quedan como las dejes.")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displaysVersion += 1
        }
    }

    /// Two identical monitors share a name; the second one gets a number so the switches can be told apart.
    private var rows: [(uuid: String, title: String)] {
        var seen: [String: Int] = [:]
        return (backend?.displays ?? []).map { display in
            let count = (seen[display.name] ?? 0) + 1
            seen[display.name] = count
            return (display.uuid, count == 1 ? display.name : "\(display.name) (\(count))")
        }
    }

    private func managed(_ uuid: String) -> Binding<Bool> {
        Binding(
            get: { !store.prefs.disabledDisplays.contains(uuid) },
            set: { isManaged in
                if isManaged {
                    store.prefs.disabledDisplays.removeAll { $0 == uuid }
                } else if !store.prefs.disabledDisplays.contains(uuid) {
                    store.prefs.disabledDisplays.append(uuid)
                }
            }
        )
    }
}
