import AppKit
import RamblaCore

/// Tells the user when a newer release exists on GitHub. It checks once a day through the system's energy-aware
/// scheduler (plus "Buscar actualizaciones…" on demand) and offers to open the download; it never downloads or
/// installs anything by itself.
@MainActor
final class Updater {
    static let shared = Updater()
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/Coru29/rambla/releases/latest")!

    struct Release {
        let version: AppVersion
        let page: URL
        let download: URL?
        let notes: String
    }

    /// A newer release than the running one, once a check has found it.
    private(set) var available: Release?
    /// Called when `available` changes (the menu shows it).
    var onChange: (() -> Void)?
    private var scheduler: NSBackgroundActivityScheduler?

    var currentVersion: AppVersion {
        AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") ?? AppVersion("0")!
    }

    func configure(automatic: Bool) {
        scheduler?.invalidate()
        scheduler = nil
        guard automatic else { return }
        let scheduler = NSBackgroundActivityScheduler(identifier: "io.github.coru29.Rambla.updates")
        scheduler.repeats = true
        scheduler.interval = 24 * 60 * 60
        scheduler.tolerance = 2 * 60 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.check(userInitiated: false)
                completion(.finished)
            }
        }
        self.scheduler = scheduler
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await self?.check(userInitiated: false)
        }
    }

    func check(userInitiated: Bool) async {
        do {
            let release = try await fetchLatest()
            available = release.version > currentVersion ? release : nil
            onChange?()
            if let available {
                Log.info("Update available: \(available.version)")
                if userInitiated { offerDownload() }
            } else if userInitiated {
                inform("Tenés la última versión", "Rambla \(currentVersion) es la versión más nueva.")
            }
        } catch {
            Log.error("Update check failed: \(error.localizedDescription)")
            if userInitiated { inform("No se pudo buscar actualizaciones", error.localizedDescription) }
        }
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: Self.latestReleaseAPI, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Rambla/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, let version = AppVersion(tag),
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw URLError(.cannotParseResponse)
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let download = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))
        return Release(version: version, page: page, download: download, notes: json["body"] as? String ?? "")
    }

    /// Shows what is new and opens the DMG download (or the release page) in the browser.
    func offerDownload() {
        guard let release = available else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Rambla \(release.version) está disponible"
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = "Tenés la \(currentVersion). Bajá el DMG nuevo y arrastrá Rambla a Aplicaciones para reemplazarla; el permiso de Accesibilidad se mantiene."
            + (notes.isEmpty ? "" : "\n\nNovedades:\n\n" + String(notes.prefix(700)))
        alert.addButton(withTitle: "Descargar")
        alert.addButton(withTitle: "Ver novedades")
        alert.addButton(withTitle: "Más tarde")
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.download ?? release.page)
        case .alertSecondButtonReturn: NSWorkspace.shared.open(release.page)
        default: break
        }
    }

    private func inform(_ title: String, _ text: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
