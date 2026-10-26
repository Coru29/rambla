import AppKit
import RamblaCore
import SwiftUI

/// "Trackpad y mouse": the trackpad's swipes (sideways, and up and down as chosen), the macOS settings that would
/// fight them, the mouse wheel and the mouse buttons.
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
            Toggle("Gestos hacia arriba y abajo", isOn: $store.prefs.trackpad.verticalSwipe)
                .disabled(!enabled)
            // The trackpad's swipes up and down and the mouse buttons both go by it: open while either of them is on.
            Picker("Deslizar hacia arriba o abajo", selection: $store.prefs.verticalGesture) {
                Text("Cambia de tira").tag(VerticalGesture.strips)
                Text("Cambia el ancho").tag(VerticalGesture.width)
            }
            .pickerStyle(.segmented)
            .disabled(!((store.prefs.trackpad.enabled && store.prefs.trackpad.verticalSwipe)
                        || store.prefs.mouseButtons.enabled))
            Toggle("Respuesta háptica", isOn: $store.prefs.trackpad.haptics)
        } header: {
            Text("Trackpad")
        } footer: {
            trackpadFooter
        }
    }

    /// What the swipes do, up and down as chosen.
    private var trackpadFooter: Text {
        switch store.prefs.verticalGesture {
        case .strips:
            Text("Un swipe horizontal con esa cantidad de dedos desplaza la tira. Al soltar, se asienta en una columna: un swipe corto y rápido pasa a la siguiente. Con la dirección natural, la tira sigue a los dedos; sin ella, va al revés. Un swipe corto hacia arriba o abajo cambia de tira al soltar: con la dirección natural, hacia abajo aparece la tira de arriba; sin ella, la de abajo. Subiendo un buen trecho, la columna enfocada toma el ancho completo o, si ya lo tenía, vuelve al de antes; bajando un buen trecho se abre la vista general. Con la respuesta háptica, el trackpad da un toque suave cada vez que la tira va a pasar a otra columna, cuando ya podés soltar para cambiar de tira y al subir o bajar un buen trecho.")
        case .width:
            Text("Un swipe horizontal con esa cantidad de dedos desplaza la tira. Al soltar, se asienta en una columna: un swipe corto y rápido pasa a la siguiente. Con la dirección natural, la tira sigue a los dedos; sin ella, va al revés. Hacia arriba, la columna enfocada toma el ancho completo; hacia abajo, al soltar, vuelve al ancho que tenía, y bajando un buen trecho se abre la vista general. Con la respuesta háptica, el trackpad da un toque suave cada vez que la tira va a pasar a otra columna y con los gestos hacia arriba o abajo.")
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
            buttonsFooter
        }
    }

    /// What moving with the buttons held does, up and down as chosen in the trackpad's section.
    private var buttonsFooter: Text {
        switch store.prefs.verticalGesture {
        case .strips:
            Text("Mantené apretados esos botones y mové el mouse: hacia los costados desliza la tira, y un poco hacia arriba o abajo cambia de tira al soltar. Con la dirección natural, hacia abajo aparece la tira de arriba; sin ella, la de abajo. Subiendo bastante, la columna enfocada toma el ancho completo o, si ya lo tenía, vuelve al de antes; bajando bastante se abre la vista general. Lo que hacen hacia arriba y abajo se elige en «Deslizar hacia arriba o abajo», en la sección Trackpad. Con un solo botón, un clic sin mover sigue funcionando como siempre. Con varios, cada uno por separado sigue haciendo lo suyo: así conviven con Mac Mouse Fix y otras apps que usan los mismos botones.")
        case .width:
            Text("Mantené apretados esos botones y mové el mouse: hacia los costados desliza la tira, hacia arriba la columna enfocada toma el ancho completo y hacia abajo, al soltar, vuelve al ancho que tenía; bajando bastante se abre la vista general. Lo que hacen hacia arriba y abajo se elige en «Deslizar hacia arriba o abajo», en la sección Trackpad. Con un solo botón, un clic sin mover sigue funcionando como siempre. Con varios, cada uno por separado sigue haciendo lo suyo: así conviven con Mac Mouse Fix y otras apps que usan los mismos botones.")
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
