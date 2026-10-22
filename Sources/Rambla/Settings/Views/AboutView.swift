import AppKit
import SwiftUI

/// "Acerca de": icon, version, project link and the log.
struct AboutView: View {
    let backend: SettingsBackend?

    private static let repository = URL(string: "https://github.com/Coru29/rambla")!

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(verbatim: "Rambla")
                .font(.system(size: 28, weight: .semibold))
            Text(versionText)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Gestor de ventanas con scroll horizontal. Gratis y open source.")
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Link(destination: Self.repository) { Text(verbatim: "github.com/Coru29/rambla") }
            Button("Mostrar registro", action: showLog)
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "Versión 1.0.0 (3)"; a build run outside the app bundle has no Info.plist.
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String, !version.isEmpty else {
            return String(localized: "Versión de desarrollo")
        }
        if let build = info?["CFBundleVersion"] as? String, !build.isEmpty, build != version {
            return String(localized: "Versión \(version) (\(build))")
        }
        return String(localized: "Versión \(version)")
    }

    private func showLog() {
        if let backend {
            backend.openLog()
        } else {
            NSWorkspace.shared.open(Log.fileURL)
        }
    }
}
