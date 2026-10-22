import AppKit
import RamblaCore
import SwiftUI

/// "General": on/off, launch at login, animation, centering, gaps and widths.
struct GeneralView: View {
    let backend: SettingsBackend?
    @ObservedObject private var store = PreferencesStore.shared
    /// A copy of `backend.launchAtLogin`: the backend is not observable, and registering can fail.
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            generalSection
            animationSection
            windowsSection
            gapsSection
            presetsSection
            adjustSection
            externalSection
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onAppear(perform: syncLaunchAtLogin)
        // The user may change the login item in System Settings while this window is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncLaunchAtLogin()
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section {
            Toggle("Activo", isOn: $store.prefs.enabled)
            if let backend {
                Toggle("Arrancar con la Mac", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        backend.launchAtLogin = newValue
                        launchAtLogin = backend.launchAtLogin   // shows what macOS accepted
                    }
                ))
            }
        } footer: {
            Text("En pausa, Rambla trae las ventanas de vuelta a la pantalla y libera sus atajos.")
        }
    }

    private var animationSection: some View {
        Section {
            Toggle("Animaciones", isOn: $store.prefs.animations)
            SliderRow("Velocidad", value: $store.prefs.animationSpeed, in: 0.5...2.0, step: 0.1,
                      display: SettingsFormat.multiplier)
                .disabled(!store.prefs.animations)
        }
    }

    private var windowsSection: some View {
        Section("Ventanas") {
            Picker("Centrar la columna enfocada", selection: $store.prefs.centerMode) {
                Text("Nunca").tag(CenterMode.never)
                Text("Solo si no entra").tag(CenterMode.onOverflow)
                Text("Siempre").tag(CenterMode.always)
            }
            Picker("Ancho de ventanas nuevas", selection: widthChoice) {
                ForEach(widthChoices, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            Toggle("Mantener altura original", isOn: $store.prefs.keepOriginalHeight)
        }
    }

    private var gapsSection: some View {
        Section("Espaciado") {
            SliderRow("Separación entre ventanas", value: $store.prefs.innerGap, in: 0...40, step: 1,
                      display: SettingsFormat.points)
            SliderRow("Margen exterior", value: $store.prefs.outerGap, in: 0...40, step: 1,
                      display: SettingsFormat.points)
        }
    }

    private var presetsSection: some View {
        Section {
            ForEach(Array(store.prefs.presetWidths.enumerated()), id: \.offset) { index, _ in
                presetRow(index)
            }
            HStack {
                Button("Agregar preset", action: addPreset)
                Button("Restablecer", action: resetPresets)
                Spacer()
            }
        } header: {
            Text("Presets de ancho")
        } footer: {
            Text("«Rotar ancho» pasa al siguiente. Van de 5 % a 100 % y se mantienen ordenados.")
        }
    }

    private var adjustSection: some View {
        Section {
            SliderRow("Paso de ajuste", value: nudgePercent, in: 2...20, step: 1) { "\(Int($0.rounded())) %" }
        } footer: {
            Text("Cuánto cambian «Más ancha» y «Más angosta» el ancho de la columna.")
        }
    }

    private var externalSection: some View {
        Section {
            Toggle("Si otra app (como Rectangle) mueve una ventana, sacarla de la tira",
                   isOn: $store.prefs.floatOnExternalMove)
        } footer: {
            Text("La ventana queda flotando donde la dejaron. Con «Flotar / volver a la tira» regresa.")
        }
    }

    // MARK: - Launch at login

    private func syncLaunchAtLogin() {
        launchAtLogin = backend?.launchAtLogin ?? false
    }

    // MARK: - Width of new windows

    /// "Propio de la ventana" or a fixed fraction. A fraction outside the usual three (set by hand in the
    /// preferences) is listed too, so the picker always has a selection.
    private enum WidthChoice: Hashable {
        case natural
        case fraction(Double)

        var value: NewWindowWidth {
            switch self {
            case .natural: return .natural
            case .fraction(let fraction): return .fraction(fraction)
            }
        }

        var label: String {
            switch self {
            case .natural: return "Propio de la ventana"
            case .fraction(let fraction): return SettingsFormat.wholePercent(fraction)
            }
        }
    }

    private static let standardFractions: [Double] = [1.0 / 3, 0.5, 2.0 / 3]

    private var widthChoices: [WidthChoice] {
        var fractions = Self.standardFractions
        if case .fraction(let current) = store.prefs.newWindowWidth,
           !fractions.contains(where: { abs($0 - current) < 0.005 }) {
            fractions.append(current)
            fractions.sort()
        }
        return [.natural] + fractions.map { .fraction($0) }
    }

    private var widthChoice: Binding<WidthChoice> {
        Binding(
            get: {
                switch store.prefs.newWindowWidth {
                case .natural:
                    return .natural
                case .fraction(let current):
                    // Snap to the listed value so the picker's tag matches exactly.
                    return .fraction(Self.standardFractions.first { abs($0 - current) < 0.005 } ?? current)
                }
            },
            set: { store.prefs.newWindowWidth = $0.value }
        )
    }

    // MARK: - Width presets

    private func presetRow(_ index: Int) -> some View {
        LabeledContent("Preset \(index + 1)") {
            HStack(spacing: 6) {
                TextField("Ancho del preset \(index + 1)", value: presetPercent(index),
                          format: .number.precision(.fractionLength(0...1)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("%").foregroundStyle(.secondary)
                Button { removePreset(at: index) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Quitar este preset")
                .accessibilityLabel("Quitar el preset \(index + 1)")
                .disabled(store.prefs.presetWidths.count <= 1)   // "Rotar ancho" needs at least one
            }
        }
    }

    private func presetPercent(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                let widths = store.prefs.presetWidths
                return widths.indices.contains(index) ? widths[index] * 100 : 0
            },
            set: { percent in
                store.prefs.presetWidths = PresetWidths.setting(store.prefs.presetWidths, at: index, percent: percent)
            }
        )
    }

    private func removePreset(at index: Int) {
        store.prefs.presetWidths = PresetWidths.removing(store.prefs.presetWidths, at: index)
    }

    private func addPreset() {
        store.prefs.presetWidths = PresetWidths.adding(to: store.prefs.presetWidths)
    }

    private func resetPresets() {
        store.prefs.presetWidths = Preferences().presetWidths
    }

    // MARK: - Adjustment step

    private var nudgePercent: Binding<Double> {
        Binding(
            get: { store.prefs.nudgeStep * 100 },
            set: { store.prefs.nudgeStep = $0 / 100 }
        )
    }
}

/// Edits to the list of width presets (fractions of the viewport). The list stays sorted, between 5 % and 100 %,
/// without near-duplicates, and never empty ("Rotar ancho" needs at least one).
enum PresetWidths {
    static let range: ClosedRange<Double> = 0.05...1.0

    /// Sorted, with values closer than 0.05 % collapsed into one.
    static func normalized(_ widths: [Double]) -> [Double] {
        var result: [Double] = []
        for width in widths.sorted() {
            if let last = result.last, abs(last - width) < 0.0005 { continue }
            result.append(width)
        }
        return result
    }

    /// Sets the preset at `index` to `percent` (clamped to 5...100); anything that is not a number changes nothing.
    /// The field shows one decimal ("33,3"), so committing what it already shows is not an edit and must not turn an
    /// exact 1/3 into 0.333.
    static func setting(_ widths: [Double], at index: Int, percent: Double) -> [Double] {
        guard widths.indices.contains(index), percent.isFinite else { return widths }
        if abs(widths[index] * 100 - percent) < 0.05 { return widths }
        var result = widths
        result[index] = min(max(percent / 100, range.lowerBound), range.upperBound)
        return normalized(result)
    }

    static func removing(_ widths: [Double], at index: Int) -> [Double] {
        guard widths.count > 1, widths.indices.contains(index) else { return widths }
        var result = widths
        result.remove(at: index)
        return result
    }

    /// Adds the first usual width that is not in the list yet.
    static func adding(to widths: [Double]) -> [Double] {
        let candidates: [Double] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1.0, 0.4, 0.6, 0.8, 0.9, 0.2, 0.1]
        let fresh = candidates.first { candidate in !widths.contains { abs($0 - candidate) < 0.005 } } ?? 0.5
        return normalized(widths + [fresh])
    }
}
