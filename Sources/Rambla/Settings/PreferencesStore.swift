import Combine
import Foundation
import RamblaCore

/// Single source of truth for user preferences, persisted as JSON in UserDefaults under "preferences".
@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()
    private static let key = "preferences"

    @Published var prefs: Preferences {
        didSet {
            guard prefs != oldValue else { return }
            save()
            onChange?(prefs)
        }
    }

    /// The engine's hook; SwiftUI views observe `prefs` directly.
    var onChange: ((Preferences) -> Void)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            prefs = decoded
        } else {
            prefs = Preferences()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
