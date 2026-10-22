import SwiftUI

/// The pages of the settings window, in sidebar order.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, shortcuts, trackpad, appearance, apps, displays, mac, automation, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Atajos"
        case .trackpad: return "Trackpad"
        case .appearance: return "Apariencia"
        case .apps: return "Apps"
        case .displays: return "Pantallas"
        case .mac: return "Mac"
        case .automation: return "Automatización"
        case .about: return "Acerca de"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .trackpad: return "hand.draw"
        case .appearance: return "paintbrush"
        case .apps: return "square.grid.2x2"
        case .displays: return "display"
        case .mac: return "checkmark.shield"
        case .automation: return "terminal"
        case .about: return "info.circle"
        }
    }
}

/// Sidebar plus the selected page.
struct SettingsRoot: View {
    static let minimumSize = CGSize(width: 720, height: 520)

    let backend: SettingsBackend?
    @State private var selection: SettingsSection?

    init(backend: SettingsBackend?, initialSection: SettingsSection = .general) {
        self.backend = backend
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        // A constant visibility keeps the sidebar from being dragged shut: nothing in the window could reopen it.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            page(for: selection ?? .general)
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }

    @ViewBuilder
    private func page(for section: SettingsSection) -> some View {
        switch section {
        case .general: GeneralView(backend: backend)
        case .shortcuts: ShortcutsView(backend: backend)
        case .trackpad: TrackpadView()
        case .appearance: AppearanceView()
        case .apps: AppsView(backend: backend)
        case .displays: DisplaysView(backend: backend)
        case .mac: MacView()
        case .automation: AutomationView(backend: backend)
        case .about: AboutView(backend: backend)
        }
    }
}
