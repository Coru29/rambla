import AppKit
import RamblaCore
import SwiftUI

/// "Trackpad y mouse": the horizontal swipe, the macOS settings that would fight it, and the mouse wheel.
struct TrackpadView: View {
    @ObservedObject private var store = PreferencesStore.shared
    @StateObject private var checks = ChecksModel()

    var body: some View {
        Form {
            gestureSection
            if !related.isEmpty {
                Section {
                    ForEach(related) { CheckRow(result: $0, onFix: refresh) }
                    HStack {
                        Spacer()
                        Button("Volver a revisar", action: refresh)
                    }
                } header: {
                    Text("Conflictos con macOS")
                } footer: {
                    Text("macOS también recibe el gesto y no se puede bloquear: si usa los mismos dedos para cambiar de escritorio, pasan las dos cosas.")
                }
            }
            mouseSection
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onAppear(perform: refresh)
        .onChange(of: store.prefs.trackpad.fingers) { refresh() }
        .onChange(of: store.prefs.trackpad.enabled) { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var gestureSection: some View {
        let enabled = store.prefs.trackpad.enabled
        return Section {
            Toggle("Deslizar la tira con el trackpad", isOn: $store.prefs.trackpad.enabled)
            Picker("Dedos", selection: $store.prefs.trackpad.fingers) {
                Text("3 dedos").tag(3)
                Text("4 dedos").tag(4)
            }
            .pickerStyle(.segmented)
            .disabled(!enabled)
            SliderRow("Sensibilidad", value: $store.prefs.trackpad.sensitivity, in: 0.5...2.0, step: 0.1,
                      display: SettingsFormat.multiplier)
                .disabled(!enabled)
            Toggle("Dirección natural", isOn: $store.prefs.trackpad.natural)
                .disabled(!enabled)
        } header: {
            Text("Trackpad")
        } footer: {
            Text("Un swipe horizontal con esa cantidad de dedos desplaza la tira. Al soltar, se asienta en una columna: un swipe corto y rápido pasa a la siguiente. Con la dirección natural, la tira sigue a los dedos; sin ella, va al revés.")
        }
    }

    private var mouseSection: some View {
        Section {
            Toggle("Mover la tira con la ruedita del mouse", isOn: $store.prefs.mouse.enabled)
            Picker("Manteniendo apretado", selection: $store.prefs.mouse.modifiers) {
                ForEach(MousePrefs.modifierChoices, id: \.rawValue) { keys in
                    Text(verbatim: keys.symbols).tag(keys)
                }
            }
            .disabled(!store.prefs.mouse.enabled)
        } header: {
            Text("Mouse")
        } footer: {
            Text("Con esas teclas apretadas, cada paso de la ruedita enfoca la columna de al lado. Con un Magic Mouse, o con dos dedos en el trackpad, la tira se desliza y se asienta al soltar. Sin las teclas, la ruedita funciona como siempre.")
        }
    }

    // MARK: - Checks

    /// The Mac checks about the trackpad gesture (ids from RamblaCore's MacChecks).
    private var related: [CheckResult] {
        checks.results.filter { ["trackpad-gesture", "three-finger-drag"].contains($0.id) }
    }

    private func refresh() {
        checks.refresh(prefs: store.prefs)
    }
}
