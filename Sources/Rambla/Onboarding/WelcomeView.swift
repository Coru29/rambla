import SwiftUI

/// The welcome guide: one step at a time, page dots and Atrás / Siguiente underneath.
/// ⏎ goes to the next step and ⎋ closes the window; both are handled by `WelcomeWindow`.
struct WelcomeView: View {
    static let size = CGSize(width: 560, height: 440)

    @ObservedObject var model: WelcomeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch model.page {
                case .welcome: WelcomeIntroPage().transition(.opacity)
                case .accessibility: WelcomeAccessibilityPage(model: model).transition(.opacity)
                case .trackpad: WelcomeTrackpadPage(model: model).transition(.opacity)
                case .shortcuts: WelcomeShortcutsPage().transition(.opacity)
                case .done: WelcomeDonePage().transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.page)
            Divider()
            WelcomeFooter(model: model)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

private struct WelcomeFooter: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        ZStack {
            WelcomePageDots(model: model)
            HStack {
                if !model.isFirst {
                    Button("Atrás", action: model.back)
                }
                Spacer()
                forwardButton
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .frame(height: 60)
    }

    /// "Siguiente" on most steps; "Lo hago después" on the permission step while the permission is missing (it
    /// still moves on, and the step's own button is the main action there); "Empezar" on the last one.
    @ViewBuilder private var forwardButton: some View {
        if model.isLast {
            Button(action: model.advance) { Text("Empezar") }
                .buttonStyle(.borderedProminent)
        } else if model.page == .accessibility && !model.isTrusted {
            Button(action: model.advance) { Text("Lo hago después") }
        } else {
            Button(action: model.advance) { Text("Siguiente") }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct WelcomePageDots: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WelcomePage.allCases, id: \.self) { page in
                Button { model.go(to: page) } label: {
                    Circle()
                        .fill(page == model.page ? Color.primary.opacity(0.75) : Color.primary.opacity(0.2))
                        .frame(width: 7, height: 7)
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paso \(page.rawValue + 1) de \(WelcomePage.allCases.count)")
                .accessibilityAddTraits(page == model.page ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.page)
    }
}
