import AppKit
import RamblaCore
import SwiftUI

/// "Trackpad y mouse": the horizontal swipe, the macOS settings that would fight it, the mouse wheel and the mouse
/// buttons.
struct TrackpadView: View {
    let backend: SettingsBackend?
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
            buttonsSection
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onAppear(perform: refresh)
        .onChange(of: store.prefs.trackpad.fingers) { refresh() }
        .onChange(of: store.prefs.trackpad.enabled) { refresh() }
        .onChange(of: store.prefs.trackpad.verticalSwipe) { refresh() }
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
            Toggle("Hacia arriba, ancho completo; hacia abajo, el ancho de antes", isOn: $store.prefs.trackpad.verticalSwipe)
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

    private var buttonsSection: some View {
        let enabled = store.prefs.mouseButtons.enabled
        return Section {
            Toggle("Gestos con botones del mouse", isOn: $store.prefs.mouseButtons.enabled)
            LabeledContent("Botones") {
                MouseButtonsRecorder(buttons: $store.prefs.mouseButtons.buttons, backend: backend)
            }
            SliderRow("Sensibilidad", value: $store.prefs.mouseButtons.sensitivity, in: 0.5...3.0, step: 0.1,
                      display: SettingsFormat.multiplier)
                .disabled(!enabled)
            Toggle("Dirección natural", isOn: $store.prefs.mouseButtons.natural)
                .disabled(!enabled)
        } header: {
            Text("Botones del mouse")
        } footer: {
            Text("Mantené apretados esos botones y mové el mouse: hacia los costados desliza la tira, hacia arriba la columna enfocada toma el ancho completo y hacia abajo, al soltar, vuelve al ancho que tenía; bajando bastante se abre la vista general. Con un solo botón, un clic sin mover sigue funcionando como siempre. Con varios, cada uno por separado sigue haciendo lo suyo: así conviven con Mac Mouse Fix y otras apps que usan los mismos botones.")
        }
    }

    // MARK: - Checks

    /// The Mac checks about the trackpad gesture.
    private var related: [CheckResult] {
        checks.results.filter { MacChecks.trackpadCheckIDs.contains($0.id) }
    }

    private func refresh() {
        checks.refresh(prefs: store.prefs)
    }
}
