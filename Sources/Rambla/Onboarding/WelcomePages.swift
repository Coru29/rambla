import AppKit
import RamblaCore
import SwiftUI

// The five steps of the welcome guide. Every visible string is a literal that SwiftUI localizes, with the
// Spanish text as its key; the few interpolations are whole sentences.

// MARK: - 1. Bienvenida

struct WelcomeIntroPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            // The artwork is full-bleed (macOS rounds it itself in the Dock), so round it here.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22.4, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
                .accessibilityHidden(true)
            Text("Bienvenido a Rambla")
                .font(.largeTitle.bold())
                .padding(.top, 12)
            Text("Cada ventana es una columna en una tira horizontal que se desliza hasta la que enfocás, y Rambla se lleva bien con Rectangle.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
                .padding(.top, 8)
            WelcomeStripIllustration()
                .padding(.top, 26)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 2. Permiso de Accesibilidad

struct WelcomeAccessibilityPage: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WelcomePageHeader(symbol: "accessibility", tint: .blue, title: Text("Permiso de Accesibilidad"))
            Text("Rambla lo necesita para mover y acomodar las ventanas de otras apps. No graba ni envía nada de lo que hacés.")
                .fixedSize(horizontal: false, vertical: true)
            WelcomeCard {
                HStack(spacing: 12) {
                    if model.isTrusted {
                        Label {
                            Text("Permiso activado")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                        }
                    } else {
                        Label {
                            Text("Falta el permiso")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                        }
                    }
                    Spacer(minLength: 8)
                    if model.isTrusted {
                        Button("Abrir Ajustes de Accesibilidad", action: openAccessibilitySettings)
                    } else {
                        Button("Abrir Ajustes de Accesibilidad", action: openAccessibilitySettings)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .font(.body.weight(.medium))
                .padding(12)
            }
            Group {
                if model.isTrusted {
                    Text("Listo, Rambla ya puede acomodar tus ventanas.")
                } else {
                    Text("Activá Rambla en la lista de Ajustes y volvé acá: esta ventana se actualiza sola.")
                }
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .welcomePagePadding()
    }

    private func openAccessibilitySettings() {
        NSWorkspace.shared.open(MacChecks.accessibilityURL)
    }
}

// MARK: - 3. Trackpad

struct WelcomeTrackpadPage: View {
    @ObservedObject var model: WelcomeModel
    @ObservedObject private var store = PreferencesStore.shared
    @State private var rows: [CheckResult] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WelcomePageHeader(symbol: "hand.draw", tint: .indigo, title: Text("Trackpad"))
            Text("Deslizá con 3 o 4 dedos hacia los costados y la tira te sigue. macOS usa ese mismo gesto para cambiar de escritorio, así que conviene que no choquen.")
                .fixedSize(horizontal: false, vertical: true)
            WelcomeCard {
                HStack(spacing: 12) {
                    Toggle("Deslizar con el trackpad", isOn: $store.prefs.trackpad.enabled)
                        .toggleStyle(.switch)
                    Spacer(minLength: 12)
                    Picker("Cantidad de dedos", selection: $store.prefs.trackpad.fingers) {
                        Text("3 dedos").tag(3)
                        Text("4 dedos").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!store.prefs.trackpad.enabled)
                }
                .padding(12)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { WelcomeCheckRow(check: $0) }
            }
            .padding(.horizontal, 2)
            Button("Abrir Ajustes del Trackpad") {
                NSWorkspace.shared.open(MacChecks.trackpadURL)
            }
            Spacer(minLength: 0)
        }
        .welcomePagePadding()
        .onAppear(perform: reload)
        .onChange(of: store.prefs.trackpad) { reload() }
        // The user comes back from System Settings: look at the settings again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    private func reload() {
        rows = WelcomeModel.trackpadRows(from: model.readChecks(store.prefs))
    }
}

// MARK: - 4. Atajos básicos

struct WelcomeShortcutsPage: View {
    @ObservedObject private var store = PreferencesStore.shared

    var body: some View {
        let prefs = store.prefs
        func combos(_ actions: Action...) -> [KeyCombo] {
            actions.compactMap { prefs.shortcuts(for: $0).first }
        }
        let floatKeys = combos(.toggleFloat).first.map(KeyNames.display)

        return VStack(alignment: .leading, spacing: 14) {
            WelcomePageHeader(symbol: "keyboard", tint: .gray, title: Text("Atajos básicos"))
            WelcomeCard {
                WelcomeShortcutRow(title: Text("Moverte entre columnas"), combos: combos(.focusLeft, .focusRight))
                Divider().padding(.leading, 12)
                WelcomeShortcutRow(title: Text("Cambiar el ancho de la columna"), combos: combos(.cycleWidth))
                Divider().padding(.leading, 12)
                WelcomeShortcutRow(title: Text("Alternar entre pila y pestañas"), combos: combos(.toggleTabbed))
                Divider().padding(.leading, 12)
                WelcomeShortcutRow(title: Text("Sacar la ventana de la tira o devolverla"), combos: combos(.toggleFloat))
                Divider().padding(.leading, 12)
                WelcomeShortcutRow(title: Text("Fijar la columna a la izquierda"), combos: combos(.pinLeft))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Rambla usa ⌃⌘ y Rectangle usa ⌃⌥, así que no se pisan.")
                if let floatKeys {
                    Text("Una ventana que mueve Rectangle queda flotando: con \(floatKeys) la devolvés a la tira.")
                } else {
                    Text("Una ventana que mueve Rectangle queda flotando: la devolvés a la tira desde el menú de Rambla.")
                }
                Text("Podés cambiar todos los atajos en Configuración.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
            Spacer(minLength: 0)
        }
        .welcomePagePadding()
    }
}

// MARK: - 5. Listo

struct WelcomeDonePage: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var launchAtLoginFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WelcomePageHeader(symbol: "checkmark", tint: .green, title: Text("Todo listo"))
            Text("Rambla vive en la barra de menú. Desde ahí la pausás, abrís la configuración o volvés a esta guía.")
                .fixedSize(horizontal: false, vertical: true)
            WelcomeMenuBarIllustration()
            WelcomeCard {
                Toggle("Arrancar con la Mac", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    .toggleStyle(WelcomeSwitchStyle())
                    .padding(12)
            }
            if launchAtLoginFailed {
                Text("No se pudo cambiar esta opción.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Link("Abrir el manual", destination: AppDelegate.manualURL)
            Spacer(minLength: 0)
        }
        .welcomePagePadding()
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private func setLaunchAtLogin(_ wanted: Bool) {
        do {
            try LoginItem.set(wanted)
            launchAtLoginFailed = false
        } catch {
            Log.error("Launch at login could not be \(wanted ? "turned on" : "turned off"): \(error.localizedDescription)")
            launchAtLoginFailed = true
        }
        // Show what macOS really did, which is not always what was asked.
        launchAtLogin = LoginItem.isEnabled
    }
}

// MARK: - Shared pieces

/// A rounded panel that groups rows, like the groups in System Settings.
struct WelcomeCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
            }
    }
}

/// A switch with its label on the left, the way System Settings lays out its rows.
struct WelcomeSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Toggle(configuration)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private extension View {
    func welcomePagePadding() -> some View {
        padding(.horizontal, 36)
            .padding(.top, 26)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
