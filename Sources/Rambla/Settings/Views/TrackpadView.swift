import AppKit
import RamblaCore
import SwiftUI

/// "Trackpad": the horizontal swipe, plus the macOS settings that would fight it.
struct TrackpadView: View {
    @ObservedObject private var store = PreferencesStore.shared
    @StateObject private var checks = ChecksModel()

    var body: some View {
        Form {
            gestureSection
            if !related.isEmpty {
                Section {
                    ForEach(related) { CheckRow(result: $0) }
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
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onAppear(perform: refresh)
        .onChange(of: store.prefs.trackpad.fingers) { refresh() }
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
        } footer: {
            Text("Un swipe horizontal con esa cantidad de dedos desplaza la tira. Al soltar, se asienta en la columna más cercana. Con la dirección natural, la tira sigue a los dedos; sin ella, va al revés.")
        }
    }

    // MARK: - Checks

    /// The checks about the trackpad gesture. `SystemChecks` names them freely, so match on what they say.
    private var related: [CheckResult] {
        checks.results.filter { result in
            let text = (result.id + " " + result.title).lowercased()
            return ["trackpad", "gesture", "gesto", "swipe", "finger", "dedos"].contains { text.contains($0) }
        }
    }

    private func refresh() {
        checks.refresh(prefs: store.prefs)
    }
}
