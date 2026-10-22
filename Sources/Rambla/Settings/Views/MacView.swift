import AppKit
import SwiftUI

/// "Mac": what macOS settings mean for Rambla, with a shortcut to the right System Settings pane.
struct MacView: View {
    @ObservedObject private var store = PreferencesStore.shared
    @StateObject private var checks = ChecksModel()

    var body: some View {
        Form {
            Section {
                if checks.results.isEmpty {
                    Text("Todavía no hay nada para revisar.")
                        .foregroundStyle(.secondary)
                }
                ForEach(checks.results) { result in
                    CheckRow(result: result)
                }
            } header: {
                Text("Estado de macOS")
            } footer: {
                Text("Rambla no cambia estos ajustes: solo te avisa cuáles conviene tocar.")
            }
            Section {
                HStack {
                    Spacer()
                    Button("Volver a revisar", action: refresh)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        // Back from System Settings after changing something.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        checks.refresh(prefs: store.prefs)
    }
}
