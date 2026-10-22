import AppKit
import SwiftUI

/// "Automatización": `rambla://` URLs, the `rambla` command and Raycast scripts.
struct AutomationView: View {
    let backend: SettingsBackend?
    @State private var installOutcome = Outcome.idle
    @State private var exportOutcome = Outcome.idle

    private enum Outcome: Equatable {
        case idle
        case working
        case success(String)
        case failure(String)
        case exported(URL)
    }

    var body: some View {
        Form {
            urlSection
            terminalSection
            if backend != nil { raycastSection }
        }
        .formStyle(.grouped)
    }

    // MARK: - Sections

    private var urlSection: some View {
        Section {
            ExampleRow(text: "rambla://focus-left")
            ExampleRow(text: "rambla://focus-3")
            ExampleRow(text: "rambla://toggle-pause")
        } header: {
            Text("Por URL")
        } footer: {
            Text("Sirven en la app Atajos de macOS, en Raycast, Alfred o Hammerspoon, y desde la Terminal con el comando open. Cada acción tiene su id, que aparece en `rambla list`.")
        }
    }

    private var terminalSection: some View {
        Section {
            ExampleRow(text: "rambla focus-left")
            ExampleRow(text: "rambla list")
            if backend != nil {
                Button(action: install) {
                    Text("Instalar comando `rambla`")
                }
                .disabled(installOutcome == .working)
                outcomeView(installOutcome)
            }
        } header: {
            Text("En la Terminal")
        } footer: {
            Text("`rambla list` muestra todas las acciones. Instalarlo crea `/usr/local/bin/rambla`; si hace falta, macOS pide la contraseña.")
        }
    }

    private var raycastSection: some View {
        Section {
            Button(action: export) {
                Text("Exportar scripts de Raycast…")
            }
            .disabled(exportOutcome == .working)
            outcomeView(exportOutcome)
        } header: {
            Text("Raycast")
        } footer: {
            Text("Crea un script por acción. Después, en Raycast, agregá la carpeta desde Extensions → Script Commands → Add Directories.")
        }
    }

    // MARK: - Actions

    private func install() {
        guard let backend else { return }
        installOutcome = .working
        // Installing may sit on the administrator password prompt; let "Trabajando…" show first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated {
                if let message = backend.installCLI() {
                    installOutcome = .failure(message)
                } else {
                    installOutcome = .success("Listo: ya podés usar «rambla» en la Terminal.")
                }
            }
        }
    }

    private func export() {
        guard let backend else { return }
        let panel = NSOpenPanel()
        panel.title = "Exportar scripts de Raycast"
        panel.message = "Elegí la carpeta donde guardar los scripts."
        panel.prompt = "Exportar acá"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        presentOpenPanel(panel) { folder in
            guard let folder else { return }
            if let message = backend.exportRaycastScripts(to: folder) {
                exportOutcome = .failure(message)
            } else {
                exportOutcome = .exported(folder)
            }
        }
    }

    @ViewBuilder
    private func outcomeView(_ outcome: Outcome) -> some View {
        switch outcome {
        case .idle:
            EmptyView()
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Trabajando…").foregroundStyle(.secondary)
            }
        case .success(let message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .failure(let message):
            Label {
                Text(message).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        case .exported(let folder):
            HStack {
                Label {
                    Text("Scripts guardados en \(folder.path)")
                        .lineLimit(2)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
            }
        }
    }
}

/// A line of monospaced sample text with a copy button.
private struct ExampleRow: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack {
            Text(verbatim: text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copiar")
            .accessibilityLabel("Copiar \(text)")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            MainActor.assumeIsolated { copied = false }
        }
    }
}
