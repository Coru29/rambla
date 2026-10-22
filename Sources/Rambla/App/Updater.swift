import AppKit
import RamblaCore
import Security

/// Keeps Rambla up to date from its GitHub releases, as the user asked: it checks once a day (through the system's
/// energy-aware scheduler) or on demand, and when the user accepts it downloads the DMG, verifies that the new app
/// is signed with the same certificate as the running one (the designated requirement), swaps the bundle in place
/// and relaunches. Anything not signed by the project's certificate is refused and the user gets the release page.
@MainActor
final class Updater {
    static let shared = Updater()
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/Coru29/rambla/releases/latest")!
    /// Developer override (`defaults write io.github.coru29.Rambla updateFeedURL <url>`) used to test updates
    /// against a local copy of the release JSON instead of GitHub.
    static var feedURL: URL {
        UserDefaults.standard.string(forKey: "updateFeedURL").flatMap(URL.init(string:)) ?? latestReleaseAPI
    }

    struct Release {
        let version: AppVersion
        let page: URL
        let dmg: URL?
        let notes: String
    }

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): return text }
        }
    }

    /// A newer release than the running one, once a check has found it.
    private(set) var available: Release?
    private(set) var isInstalling = false
    /// Called when `available` or `isInstalling` change (the menu shows them).
    var onChange: (() -> Void)?
    private var scheduler: NSBackgroundActivityScheduler?
    /// The check 30 s after launch (or after the option is turned on): cancelled when the option is turned off.
    private var launchCheck: Task<Void, Never>?

    var currentVersion: AppVersion {
        AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") ?? AppVersion("0")!
    }

    func configure(automatic: Bool) {
        scheduler?.invalidate()
        scheduler = nil
        launchCheck?.cancel()
        launchCheck = nil
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
        launchCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await self?.check(userInitiated: false)
        }
    }

    // MARK: - Checking

    func check(userInitiated: Bool) async {
        do {
            let release = try await fetchLatest()
            available = release.version > currentVersion ? release : nil
            onChange?()
            if let available {
                Log.info("Update available: \(available.version)")
                if userInitiated { offerInstall() }
            } else if userInitiated {
                let current = currentVersion.description
                inform(String(localized: "Tenés la última versión"), String(localized: "Rambla \(current) es la versión más nueva."))
            }
        } catch {
            Log.error("Update check failed: \(error.localizedDescription)")
            if userInitiated { inform(String(localized: "No se pudo buscar actualizaciones"), error.localizedDescription) }
        }
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: Self.feedURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Rambla/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, let version = AppVersion(tag),
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw Failure.message(String(localized: "No se encontró una versión publicada."))
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))
        return Release(version: version, page: page, dmg: dmg, notes: json["body"] as? String ?? "")
    }

    // MARK: - Installing

    /// Asks before doing anything: install now (and relaunch), see the release, or later.
    func offerInstall() {
        guard let release = available, !isInstalling else { return }
        NSApp.activate()
        let alert = NSAlert()
        let version = release.version.description, current = currentVersion.description
        alert.messageText = String(localized: "Rambla \(version) está disponible")
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = String(localized: "Tenés la \(current). Rambla se descarga, se reemplaza y se vuelve a abrir; el permiso de Accesibilidad se mantiene.")
            + (notes.isEmpty ? "" : "\n\n" + String(localized: "Novedades:") + "\n\n" + String(notes.prefix(700)))
        alert.addButton(withTitle: String(localized: "Actualizar y reiniciar"))
        alert.addButton(withTitle: String(localized: "Ver en GitHub"))
        alert.addButton(withTitle: String(localized: "Más tarde"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(release)
        case .alertSecondButtonReturn: NSWorkspace.shared.open(release.page)
        default: break
        }
    }

    /// Test hook for `rambla debug-update`: only active while a local test feed is configured.
    func installForTesting() async {
        guard UserDefaults.standard.string(forKey: "updateFeedURL") != nil else {
            Log.error("debug-update ignored: no test feed configured")
            return
        }
        await check(userInitiated: false)
        if let release = available { install(release) }
    }

    private func install(_ release: Release) {
        guard let dmg = release.dmg else {
            NSWorkspace.shared.open(release.page)
            return
        }
        isInstalling = true
        onChange?()
        let appURL = Bundle.main.bundleURL
        Log.info("Installing update \(release.version) from \(dmg.absoluteString)")
        Task.detached(priority: .userInitiated) {
            let outcome: Error?
            do {
                try await Self.downloadVerifyAndReplace(dmg: dmg, appURL: appURL, expected: release.version)
                outcome = nil
            } catch {
                outcome = error
            }
            await Updater.shared.finishInstall(outcome, release: release, appURL: appURL)
        }
    }

    private func finishInstall(_ error: Error?, release: Release, appURL: URL) {
        isInstalling = false
        onChange?()
        guard let error else {
            Log.info("Updated to \(release.version); relaunching")
            Self.relaunch(appURL)
            return
        }
        Log.error("Update failed: \(error.localizedDescription)")
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "No se pudo actualizar automáticamente")
        alert.informativeText = error.localizedDescription + "\n\n" + String(localized: "Podés bajar la versión nueva desde GitHub.")
        alert.addButton(withTitle: String(localized: "Abrir GitHub"))
        alert.addButton(withTitle: String(localized: "Cerrar"))
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.page) }
    }

    /// Off the main thread: download, mount, verify signer and version, then swap the bundle atomically.
    private nonisolated static func downloadVerifyAndReplace(dmg: URL, appURL: URL, expected: AppVersion) async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("rambla-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let (downloaded, response) = try await URLSession.shared.download(from: dmg)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.message(String(localized: "La descarga falló.")) }
        let image = work.appendingPathComponent("Rambla.dmg")
        try fm.moveItem(at: downloaded, to: image)

        let mount = work.appendingPathComponent("mnt")
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, image.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }

        let newApp = mount.appendingPathComponent("Rambla.app")
        guard fm.fileExists(atPath: newApp.path) else { throw Failure.message(String(localized: "El DMG no contiene Rambla.app.")) }
        try verifySameSigner(newApp)
        let shipped = Bundle(url: newApp)?.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let version = shipped.flatMap(AppVersion.init), version == expected else {
            throw Failure.message(String(localized: "La versión descargada no coincide con la publicada."))
        }

        // Stage next to the current app (same volume) so the swap is atomic.
        let staged = appURL.deletingLastPathComponent().appendingPathComponent(".Rambla-update-\(UUID().uuidString).app")
        do {
            try run("/usr/bin/ditto", [newApp.path, staged.path])
            _ = try fm.replaceItemAt(appURL, withItemAt: staged)
        } catch {
            try? fm.removeItem(at: staged)
            let path = appURL.path, reason = error.localizedDescription
            throw Failure.message(String(localized: "No se pudo reemplazar \(path): \(reason)"))
        }
    }

    /// The new app must satisfy the running app's designated requirement: same bundle id, same certificate.
    nonisolated static func verifySameSigner(_ app: URL) throws {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate else {
            throw Failure.message(String(localized: "No se pudo leer la firma de las aplicaciones."))
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(candidate, flags, requirement)
        guard status == errSecSuccess else {
            let code = Int(status)
            throw Failure.message(String(localized: "La versión descargada no está firmada con el certificado de Rambla (\(code)); no se instaló."))
        }
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let name = URL(fileURLWithPath: tool).lastPathComponent
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.message(String(localized: "\(name) falló: \(detail)"))
        }
        return output
    }

    /// Quits normally (which brings every window back on screen) and reopens the new app once this process is gone.
    private static func relaunch(_ appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", appURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func inform(_ title: String, _ text: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
