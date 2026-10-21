import AppKit
import RamblaCore

struct CheckResult: Identifiable {
    enum Status { case ok, warning, info }
    let id: String
    let title: String
    let status: Status
    let detail: String
    let settingsURL: URL?
}

/// Reads macOS settings that affect Rambla ("Configuración → Mac").
enum SystemChecks {
    static func run(prefs: Preferences) -> [CheckResult] {
        [] // Filled in by Task 14.
    }
}
