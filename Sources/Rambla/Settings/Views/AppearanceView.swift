import AppKit
import RamblaCore
import SwiftUI

/// "Apariencia": the indicator bar, the focus border, dimming, and how the mouse and the focus follow each other.
struct AppearanceView: View {
    @ObservedObject private var store = PreferencesStore.shared

    var body: some View {
        Form {
            indicatorSection
            borderSection
            dimSection
            mouseSection
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    private var indicatorSection: some View {
        Section {
            Toggle("Barra indicadora", isOn: $store.prefs.indicatorEnabled)
        } footer: {
            Text("Un panel con un ícono por columna, abajo en la pantalla. Aparece al navegar o deslizar y se desvanece solo.")
        }
    }

    private var borderSection: some View {
        Section {
            Toggle("Borde de foco", isOn: $store.prefs.focusBorder.enabled)
            ColorPicker("Color del borde", selection: borderColor, supportsOpacity: false)
                .disabled(!store.prefs.focusBorder.enabled)
            SliderRow("Grosor del borde", value: $store.prefs.focusBorder.width, in: 1...8, step: 1,
                      display: SettingsFormat.points)
                .disabled(!store.prefs.focusBorder.enabled)
        } footer: {
            Text("Dibuja un borde redondeado alrededor de la ventana enfocada.")
        }
    }

    private var dimSection: some View {
        Section {
            Toggle("Atenuar ventanas inactivas", isOn: $store.prefs.dimInactive.enabled)
            SliderRow("Intensidad", value: $store.prefs.dimInactive.amount, in: 0.05...0.6, step: 0.05,
                      display: SettingsFormat.percent)
            .disabled(!store.prefs.dimInactive.enabled)
        } footer: {
            Text("Oscurece todo menos la ventana enfocada.")
        }
    }

    private var mouseSection: some View {
        Section {
            Toggle("El mouse sigue al foco", isOn: $store.prefs.mouseFollowsFocus)
            Toggle("El foco sigue al mouse", isOn: $store.prefs.focusFollowsMouse)
        } footer: {
            Text("Con el primero, el puntero va al centro de la ventana que enfocás con un atajo. Con el segundo, enfocás una ventana dejando el puntero quieto sobre ella (sin desplazar la tira).")
        }
    }

    /// `colorHex` is "#RRGGBB"; an unreadable value shows the default blue until the user picks a color.
    private var borderColor: Binding<Color> {
        Binding(
            get: {
                let fallback = FocusBorderPrefs().colorHex
                let color = HexColor.nsColor(store.prefs.focusBorder.colorHex) ?? HexColor.nsColor(fallback) ?? .systemBlue
                return Color(nsColor: color)
            },
            set: { color in
                if let hex = HexColor.string(from: NSColor(color)) {
                    store.prefs.focusBorder.colorHex = hex
                }
            }
        )
    }
}

/// "#RRGGBB" (or "#RRGGBBAA", alpha ignored) to and from `NSColor`, in sRGB.
enum HexColor {
    static func nsColor(_ hex: String) -> NSColor? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let shift: UInt64 = text.count == 8 ? 8 : 0
        let rgb = value >> shift
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                       green: CGFloat((rgb >> 8) & 0xFF) / 255,
                       blue: CGFloat(rgb & 0xFF) / 255,
                       alpha: 1)
    }

    static func string(from color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }
}
