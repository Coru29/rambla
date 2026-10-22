import AppKit
import RamblaCore
import SwiftUI

/// A labelled slider with its current value on the right: every slider in the settings window looks the same.
/// The slider itself is continuous and the value is snapped to `step` as it changes, because a `step:` makes
/// macOS draw one tick mark per step (forty of them for a gap).
struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: (Double) -> String

    init(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
         display: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.display = display
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: snapped, in: range)
                    .frame(width: 200)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(display(value))
                Text(display(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }

    private var snapped: Binding<Double> {
        Binding(
            get: { value },
            set: { value = Self.snap($0, to: step, in: range) }
        )
    }

    /// The multiple of `step` (counted from the start of the range) closest to `raw`, kept inside the range.
    static func snap(_ raw: Double, to step: Double, in range: ClosedRange<Double>) -> Double {
        var value = raw.isFinite ? raw : range.lowerBound
        if step > 0 { value = range.lowerBound + ((value - range.lowerBound) / step).rounded() * step }
        value = min(max(value, range.lowerBound), range.upperBound)
        return (value * 1e6).rounded() / 1e6   // 0.5 + 3 * 0.1 must be 0.8, not 0.8000000000000002
    }
}

/// Number formats shared by the settings pages. They follow the user's region, not the app's language:
/// "33,3 %" in Uruguay, "33.3%" in the United States.
enum SettingsFormat {
    /// 0.5 -> "50 %", 1/3 -> "33,3 %": every percentage in the settings looks like this.
    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0...1)))
    }

    /// 8 -> "8 pt".
    static func points(_ value: Double) -> String { "\(Int(value.rounded())) pt" }

    /// 1.5 -> "1,5×".
    static func multiplier(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))×"
    }
}

/// The results of `SystemChecks.run`, refreshed on demand (never on a timer).
@MainActor
final class ChecksModel: ObservableObject {
    @Published private(set) var results: [CheckResult] = []

    func refresh(prefs: Preferences) {
        results = SystemChecks.run(prefs: prefs)
    }
}

/// One line of a checks list: status icon, title and detail, and buttons to fix it (when Rambla can) or to open
/// the matching System Settings pane. `onFix` runs after a fix, to read the system again.
struct CheckRow: View {
    let result: CheckResult
    var onFix: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityLabel(statusName)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                if !result.detail.isEmpty {
                    Text(result.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let fix = result.fix {
                    Button(fix.title) {
                        SystemChecks.apply(fix)
                        onFix()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let url = result.settingsURL {
                    Button("Abrir Ajustes") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    private var symbol: String {
        switch result.status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch result.status {
        case .ok: return .green
        case .warning: return .orange
        case .info: return .accentColor
        }
    }

    private var statusName: String {
        switch result.status {
        case .ok: return String(localized: "Correcto")
        case .warning: return String(localized: "Atención")
        case .info: return String(localized: "Información")
        }
    }
}

/// Shows an open panel as a sheet on the settings window (or free-standing if there is none) and reports the chosen URL.
@MainActor
func presentOpenPanel(_ panel: NSOpenPanel, completion: @escaping (URL?) -> Void) {
    let finish: (NSApplication.ModalResponse) -> Void = { response in
        completion(response == .OK ? panel.url : nil)
    }
    if let window = NSApp.keyWindow {
        panel.beginSheetModal(for: window, completionHandler: finish)
    } else {
        panel.begin(completionHandler: finish)
    }
}
