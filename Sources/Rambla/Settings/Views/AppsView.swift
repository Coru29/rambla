import AppKit
import RamblaCore
import SwiftUI
import UniformTypeIdentifiers

/// "Apps": per-app rules (tile or float, initial width, where new windows open).
struct AppsView: View {
    let backend: SettingsBackend?
    @ObservedObject private var store = PreferencesStore.shared
    @State private var alertMessage: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    addMenu
                    Spacer()
                }
            } footer: {
                Text("Las apps sin regla van a la tira (Mosaico): cada ventana nueva entra como una columna a la derecha de la enfocada.")
            }
            if store.prefs.appRules.isEmpty {
                Section {
                    Text("Todavía no hay reglas.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(store.prefs.appRules) { rule in
                ruleSection(rule)
            }
        }
        .formStyle(.grouped)
        .alert("Rambla", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("Aceptar") {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Adding rules

    private struct Candidate: Identifiable {
        let bundleID: String
        let name: String
        let icon: NSImage?
        var id: String { bundleID }
    }

    /// Open apps that do not have a rule yet (and are not Rambla itself).
    private var candidates: [Candidate] {
        guard let backend else { return [] }
        var seen = Set(store.prefs.appRules.map(\.bundleID))
        if let own = Bundle.main.bundleIdentifier { seen.insert(own) }
        return backend.runningApps
            .filter { seen.insert($0.bundleID).inserted }   // one entry per app, even with several instances running
            .map { Candidate(bundleID: $0.bundleID, name: $0.name, icon: $0.icon) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var addMenu: some View {
        Menu {
            let open = candidates
            if !open.isEmpty {
                Section("Apps abiertas") {
                    ForEach(open) { app in
                        Button {
                            add(bundleID: app.bundleID, name: app.name)
                        } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                Image(nsImage: Self.menuIcon(app.icon))
                            }
                        }
                    }
                }
                Divider()
            }
            Button("Elegir una app…", action: chooseApp)
        } label: {
            Label("Agregar app", systemImage: "plus")
        }
        .fixedSize()
    }

    private static func menuIcon(_ image: NSImage?) -> NSImage {
        guard let copy = image?.copy() as? NSImage else { return NSImage() }
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Elegir una app"
        panel.message = "Elegí la app a la que querés agregarle una regla."
        panel.prompt = "Elegir"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        presentOpenPanel(panel) { url in
            guard let url else { return }
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
                alertMessage = "No pude leer el identificador de esa app."
                return
            }
            add(bundleID: bundleID, name: Self.displayName(of: bundle, at: url))
        }
    }

    private static func displayName(of bundle: Bundle, at url: URL) -> String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let value = bundle.object(forInfoDictionaryKey: key) as? String, !value.isEmpty { return value }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func add(bundleID: String, name: String) {
        if let existing = store.prefs.rule(for: bundleID) {
            alertMessage = "«\(existing.name)» ya tiene una regla."
            return
        }
        store.prefs.appRules.append(AppRule(bundleID: bundleID, name: name))
    }

    // MARK: - One rule

    private func ruleSection(_ rule: AppRule) -> some View {
        Section {
            HStack(spacing: 10) {
                Image(nsImage: AppIcons.icon(for: rule.bundleID))
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.name).font(.headline)
                    Text(rule.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button { remove(rule.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Quitar la regla de \(rule.name)")
                .accessibilityLabel("Quitar la regla de \(rule.name)")
            }
            Picker("Comportamiento", selection: field(rule.id, \.behavior, default: rule.behavior)) {
                Text("Mosaico").tag(AppRule.Behavior.tile)
                Text("Flotante").tag(AppRule.Behavior.float)
            }
            .pickerStyle(.segmented)
            Picker("Ancho inicial", selection: widthBinding(rule)) {
                Text("Predeterminado").tag(Double?.none)
                ForEach(widthOptions(including: rule.width), id: \.self) { value in
                    Text(SettingsFormat.percent(value)).tag(Double?.some(value))
                }
            }
            .disabled(rule.behavior == .float)
            Picker("Posición al abrir", selection: field(rule.id, \.openAt, default: rule.openAt)) {
                Text("Junto a la enfocada").tag(InsertPosition.afterFocused)
                Text("Al principio").tag(InsertPosition.start)
                Text("Al final").tag(InsertPosition.end)
            }
            .disabled(rule.behavior == .float)
        }
    }

    /// A binding to one field of a rule, found by id at the moment it is read or written, so a rule removed in the
    /// meantime can never be indexed out of range.
    private func field<Value>(_ id: UUID, _ keyPath: WritableKeyPath<AppRule, Value>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { store.prefs.appRules.first { $0.id == id }?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard let index = store.prefs.appRules.firstIndex(where: { $0.id == id }) else { return }
                store.prefs.appRules[index][keyPath: keyPath] = value
            }
        )
    }

    private func remove(_ id: UUID) {
        store.prefs.appRules.removeAll { $0.id == id }
    }

    // MARK: - Initial width

    /// The usual fractions, the user's presets and the rule's own value, ascending and without near-duplicates.
    private func widthOptions(including current: Double?) -> [Double] {
        var values: [Double] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1.0] + store.prefs.presetWidths
        if let current { values.append(current) }
        var options: [Double] = []
        for value in values.sorted() where options.last.map({ value - $0 >= 0.005 }) ?? true {
            options.append(value)
        }
        return options
    }

    private func widthBinding(_ rule: AppRule) -> Binding<Double?> {
        Binding(
            get: {
                guard let current = store.prefs.appRules.first(where: { $0.id == rule.id })?.width else { return nil }
                // Snap to a listed option so the picker always has a matching tag.
                return widthOptions(including: current).first { abs($0 - current) < 0.005 } ?? current
            },
            set: { value in
                guard let index = store.prefs.appRules.firstIndex(where: { $0.id == rule.id }) else { return }
                store.prefs.appRules[index].width = value
            }
        )
    }
}

/// App icons by bundle id, looked up once.
@MainActor
private enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        cache[bundleID] = image
        return image
    }
}
