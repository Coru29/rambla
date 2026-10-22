import AppKit
import RamblaCore
import SwiftUI

/// The heading of a step: a small colored tile with a symbol, then the title.
struct WelcomePageHeader: View {
    let symbol: String
    let tint: Color
    let title: Text

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            title.font(.title2.bold())
            Spacer(minLength: 0)
        }
    }
}

/// One row of "Atajos básicos": what it does, and the key caps of the user's current shortcut(s) for it.
struct WelcomeShortcutRow: View {
    let title: Text
    let combos: [KeyCombo]

    var body: some View {
        HStack(spacing: 12) {
            title.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if combos.isEmpty {
                Text("Sin atajo").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    ForEach(Array(combos.enumerated()), id: \.offset) { _, combo in WelcomeKeyCaps(combo: combo) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

/// A shortcut drawn as key caps, one per modifier and one for the key: ⌃ ⌘ ←
struct WelcomeKeyCaps: View {
    let combo: KeyCombo

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.parts(of: combo).enumerated()), id: \.offset) { _, part in WelcomeKeyCap(label: part) }
        }
    }

    /// The text `KeyNames.display` gives for the combo (modifier symbols, then the key), cut into the pieces to draw.
    static func parts(of combo: KeyCombo) -> [String] {
        split(KeyNames.display(combo))
    }

    static func split(_ display: String) -> [String] {
        let modifierSymbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        var parts: [String] = []
        var rest = Substring(display)
        while let first = rest.first, modifierSymbols.contains(first) {
            parts.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty { parts.append(String(rest)) }
        return parts
    }
}

private struct WelcomeKeyCap: View {
    let label: String

    var body: some View {
        Text(verbatim: label)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .frame(minWidth: 24, minHeight: 24)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                    }
            }
    }
}

/// A row of the Mac checks (a title and what it found), with a status icon.
struct WelcomeCheckRow: View {
    let check: CheckResult
    /// Runs after the row's fix, to read the system again.
    var onFix: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    // The wording comes from RamblaCore, which is not localized yet.
                    Text(verbatim: check.title).font(.callout.weight(.semibold))
                    Text(verbatim: check.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                if let fix = check.fix {
                    Button(fix.title) {
                        SystemChecks.apply(fix)
                        onFix()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var symbol: String {
        switch check.status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch check.status {
        case .ok: return .green
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

/// The idea of Rambla in one picture: windows are columns on a strip wider than the screen, and the screen
/// (the blue frame) shows a part of it. Decorative.
struct WelcomeStripIllustration: View {
    private static let columnWidth: CGFloat = 58
    private static let columnHeight: CGFloat = 46
    private static let gap: CGFloat = 8
    private static let hues: [Color] = [.orange, .blue, .green, .purple, .pink, .teal, .indigo]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The strip starts one column to the right and slides into place the first time it shows.
    @State private var slid = false

    var body: some View {
        let step = Self.columnWidth + Self.gap
        let visible = 3
        ZStack {
            HStack(spacing: Self.gap) {
                ForEach(Self.hues.indices, id: \.self) { index in
                    let inScreen = (2..<(2 + visible)).contains(index)
                    Column(hue: Self.hues[index])
                        .frame(width: Self.columnWidth, height: Self.columnHeight)
                        .opacity(inScreen ? 1 : 0.4)
                }
            }
            .offset(x: slid ? 0 : step)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2.5)
                .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(width: CGFloat(visible) * step + 4, height: Self.columnHeight + 16)
        }
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                   .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .onAppear {
            if reduceMotion { slid = true } else { withAnimation(.spring(duration: 0.9, bounce: 0.18).delay(0.25)) { slid = true } }
        }
        .accessibilityHidden(true)
    }

    /// A little window: a title bar in the color of "its app", and a body.
    private struct Column: View {
        let hue: Color

        var body: some View {
            VStack(spacing: 0) {
                hue.opacity(0.85).frame(height: 11)
                Color(nsColor: .controlBackgroundColor)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
            }
        }
    }
}

/// Where Rambla lives once this window is closed: its icon, highlighted, among the other menu bar icons.
/// Decorative.
struct WelcomeMenuBarIllustration: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(index == 0 ? 0.32 : 0.16))
                    .frame(width: index == 0 ? 34 : 26, height: 6)
            }
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
                Image(nsImage: Self.menuBarIcon)
                    .renderingMode(.template)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.28), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Image(systemName: "switch.2")
            }
            .font(.system(size: 13))
            .foregroundStyle(.primary.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    /// The same icon the menu bar item uses (a copy: the item's own image must stay as it is).
    private static var menuBarIcon: NSImage {
        let source = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: nil)
        let image = (source?.copy() as? NSImage) ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
