import AppKit
import RamblaCore
import SwiftUI

/// One window as the overview shows it.
struct OverviewItem {
    let app: String
    let title: String
    let icon: NSImage?
    /// The app's color, from its icon: the miniature window's body.
    let tint: NSColor
    /// Minimized, its app hidden: shown faded, not chosen.
    let hidden: Bool
}

extension OverviewItem {
    static let neutralTint = NSColor(calibratedHue: 0.6, saturation: 0.14, brightness: 0.3, alpha: 1)

    /// An icon's color, weighted by saturation so its color counts more than its white or gray parts, then made dark
    /// and calm enough for white text. A gray icon (a terminal, say) gets a neutral slate.
    static func tint(of image: NSImage?) -> NSColor {
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return neutralTint }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return neutralTint }
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[index]) / 255 / alpha, g = Double(pixels[index + 1]) / 255 / alpha
            let b = Double(pixels[index + 2]) / 255 / alpha
            let w = 0.1 + max(r, g, b) - min(r, g, b)
            red += r * w
            green += g * w
            blue += b * w
            weight += w
        }
        guard weight > 0 else { return neutralTint }
        let average = NSColor(calibratedRed: red / weight, green: green / weight, blue: blue / weight, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation > 0.15 else { return neutralTint }
        return NSColor(calibratedHue: hue, saturation: min(max(saturation, 0.3), 0.62), brightness: 0.4, alpha: 1)
    }
}

/// Everything the overview draws: the strip's cards (strip points) and how big to draw them.
struct OverviewContent {
    var overview: Overview
    var items: [WindowID: OverviewItem]
    /// Overview points per strip point.
    var scale: CGFloat
    var cardHeight: CGFloat

    /// The narrowest card and the smallest gap between two: a long strip still shows each window's icon.
    static let minimumCardWidth = 44.0
    static let minimumGap = 10.0

    var drawn: Overview.Drawn {
        overview.drawn(scale: Double(scale), minimumWidth: Self.minimumCardWidth, minimumGap: Self.minimumGap)
    }
}

@MainActor
final class OverviewState: ObservableObject {
    @Published var content: OverviewContent?
}

/// The overview ("Vista general"): the whole strip of one display at once, over a blurred screen, to see every window
/// and jump to one. A click on a window (or ↩ on the chosen one, or its number) focuses it and closes the overview;
/// esc, ⌘W, a click elsewhere, the shortcut again, another app or another desktop close it as it was.
///
/// The panel takes the keyboard without activating Rambla, so whatever app was in front stays in front until a
/// window is chosen. It exists only while shown.
@MainActor
final class OverviewController {
    private let onChoose: (WindowID, StripKey) -> Void
    private let state = OverviewState()
    private var panel: OverviewPanel?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var shownKey: StripKey?

    init(onChoose: @escaping (WindowID, StripKey) -> Void) {
        self.onChoose = onChoose
    }

    var isShown: Bool { shownKey != nil }

    func show(_ content: OverviewContent, key: StripKey, on screen: NSScreen) {
        state.content = content
        let panel = makePanel()
        panel.setFrame(screen.frame, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        shownKey = key
        observe(panel)
    }

    func hide() {
        guard let panel, shownKey != nil else { return }
        shownKey = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.close()
            }
        })
    }

    /// A window that is not on screen (minimized, its app hidden) cannot be chosen.
    private func choose(_ id: WindowID?) {
        guard let id, let key = shownKey, let item = state.content?.items[id], !item.hidden else {
            NSSound.beep()
            return
        }
        hide()
        onChoose(id, key)
    }

    private func move(_ move: Overview.Move) {
        guard shownKey != nil, var content = state.content else { return }
        content.overview.move(move)
        state.content = content
    }

    // MARK: - Keyboard

    /// Returns true when the overview used the key.
    private func handle(_ event: NSEvent) -> Bool {
        guard let overview = state.content?.overview else { return false }
        switch event.keyCode {
        case KeyCode.escape: hide()
        case KeyCode.left: move(.left)
        case KeyCode.right: move(.right)
        case KeyCode.down: move(.down)
        case KeyCode.up: move(.up)
        case KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.space: choose(overview.window(at: overview.selection))
        default:
            guard let number = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(number) else { return false }
            choose(overview.window(atCard: number))
        }
        return true
    }

    /// A Rambla shortcut while the overview is on screen. Its hot keys reach Rambla before the panel sees them, so the
    /// ones that move the focus move the selection instead, ⌃⌘1…9 choose, and the overview's own closes it. Any other
    /// closes it and then acts on the strip as usual. Returns true when the overview used the shortcut.
    func perform(_ action: Action) -> Bool {
        guard let overview = state.content?.overview, isShown else { return false }
        switch action {
        case .focusLeft: move(.left)
        case .focusRight: move(.right)
        case .focusUp: move(.up)
        case .focusDown: move(.down)
        case .focusFirst: move(.first)
        case .focusLast: move(.last)
        case .focus1, .focus2, .focus3, .focus4, .focus5, .focus6, .focus7, .focus8, .focus9:
            choose(Int(action.rawValue.split(separator: "-").last!).flatMap(overview.window(atCard:)))
        case .overview: hide()
        default:
            hide()
            return false
        }
        return true
    }

    // MARK: - Panel

    private func makePanel() -> OverviewPanel {
        let panel = OverviewPanel()
        panel.onKey = { [weak self] event in self?.handle(event) ?? false }
        panel.onClose = { [weak self] in self?.hide() }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        let hosting = OverviewHostingView(rootView: OverviewView(
            state: state,
            choose: { [weak self] id in self?.choose(id) },
            dismiss: { [weak self] in self?.hide() }))
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        panel.contentView = blur
        return panel
    }

    /// Another app in front, another desktop, a display change or a click on another screen: the strip behind is not
    /// the one shown any more.
    private func observe(_ panel: OverviewPanel) {
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default
        let close: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        observers = [
            (workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                              queue: .main, using: close)),
            (workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                              queue: .main, using: close)),
            (local, local.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                      queue: .main, using: close)),
            (local, local.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main,
                                      using: close)),
        ]
    }
}

/// A full-screen overlay panel above the menu bar and the Dock that, unlike the others, takes the keyboard (still
/// without activating Rambla).
final class OverviewPanel: OverlayPanel {
    var onKey: ((NSEvent) -> Bool)?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    init() {
        super.init(level: .popUpMenu, collectionBehavior: [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle])
        appearance = NSAppearance(named: .darkAqua)
        acceptsMouseMovedEvents = true
    }

    /// Keys go to the overview before any view: SwiftUI's scroll view would take the arrows.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }

    /// ⌘-keys would otherwise reach Rambla's own menu, where ⌘Q quits it and ⌘H hides its overlays. ⌘W closes the
    /// overview; the rest do nothing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == KeyCode.w { onClose?() }
        return true
    }
}

/// The first click counts even if the panel was not key yet.
final class OverviewHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Views

/// Like Mission Control: the desktop blurred and darkened, the strip as a row of miniature windows.
struct OverviewView: View {
    @ObservedObject var state: OverviewState
    let choose: (WindowID?) -> Void
    let dismiss: () -> Void
    @State private var hovered: WindowID?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            if let content = state.content {
                VStack(spacing: 34) {
                    strip(content)
                    Text("← → elegí una ventana · ↩ la enfoca · esc cierra")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private func strip(_ content: OverviewContent) -> some View {
        let drawn = content.drawn
        let gap = drawn.cards.count > 1 ? drawn.cards[1].lowerBound - drawn.cards[0].upperBound : 0
        return GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: CGFloat(gap)) {
                        ForEach(Array(content.overview.cards.enumerated()), id: \.offset) { index, card in
                            OverviewCard(card: card, index: index, content: content, hovered: $hovered, choose: choose)
                                .frame(width: CGFloat(drawn.cards[index].upperBound - drawn.cards[index].lowerBound),
                                       height: content.cardHeight)
                                .id(index)
                        }
                    }
                    .overlay(alignment: .topLeading) { viewport(drawn) }
                    .padding(.horizontal, 70)
                    .padding(.vertical, 28)
                    // Centered when the strip is shorter than the screen, and a click beside the cards closes too.
                    .frame(minWidth: geometry.size.width)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)
                }
                .onAppear { proxy.scrollTo(content.overview.selection.card, anchor: .center) }
                .onChange(of: content.overview.selection) { _, selection in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(selection.card, anchor: .center) }
                }
            }
        }
        .frame(height: content.cardHeight + 56)
    }

    /// The part of the strip that is on screen now: a bar above the windows, like a scroll bar's thumb.
    @ViewBuilder
    private func viewport(_ drawn: Overview.Drawn) -> some View {
        if let range = drawn.viewport {
            Capsule()
                .fill(.white.opacity(0.45))
                .frame(width: max(CGFloat(range.upperBound - range.lowerBound), 8), height: 3)
                .offset(x: CGFloat(range.lowerBound), y: -16)
                .allowsHitTesting(false)
        }
    }
}

/// One column: its window, its stack (one miniature per window) or its tabs (one miniature, the tabs in its title bar).
private struct OverviewCard: View {
    let card: Overview.Card
    let index: Int
    let content: OverviewContent
    @Binding var hovered: WindowID?
    let choose: (WindowID?) -> Void

    private var selectedRow: Int? {
        content.overview.selection.card == index ? content.overview.selection.row : nil
    }

    var body: some View {
        if card.collapsed {
            collapsed
        } else if card.tabbed, card.windows.count > 1 {
            let shown = selectedRow ?? card.active
            miniature(card.windows[shown], selected: selectedRow != nil, tabs: card.windows, shownTab: shown)
        } else {
            VStack(spacing: 10) {
                ForEach(Array(card.windows.enumerated()), id: \.offset) { row, id in
                    miniature(id, selected: selectedRow == row, tabs: [], shownTab: 0)
                }
            }
        }
    }

    /// Every window of the column is minimized or hidden: just its icons, faded.
    private var collapsed: some View {
        VStack(spacing: 6) {
            ForEach(Array(card.windows.prefix(3).enumerated()), id: \.offset) { _, id in
                AppIcon(image: content.items[id]?.icon, size: 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
        .opacity(0.6)
        .contentShape(Rectangle())
        .onTapGesture { choose(card.windows.first) }
    }

    private func miniature(_ id: WindowID, selected: Bool, tabs: [WindowID], shownTab: Int) -> some View {
        let item = content.items[id]
        let tint = Color(nsColor: item?.tint ?? .darkGray)
        let isHovered = hovered == id
        return GeometryReader { geometry in
            let size = geometry.size
            let compact = size.height < 120
            VStack(spacing: 0) {
                titleBar(item, tabs: tabs, shownTab: shownTab, pinned: card.pinned != nil)
                ZStack {
                    LinearGradient(colors: [tint, tint.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: compact ? 4 : 10) {
                        AppIcon(image: item?.icon, size: compact ? 30 : min(72, size.width * 0.32, size.height * 0.34))
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                        if !compact || size.height > 80 {
                            Text(item?.app ?? "")
                                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(isHovered && !selected ? 0.55 : 0.14), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 13).inset(by: -3).strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0))
            .shadow(color: .black.opacity(selected ? 0.55 : 0.4), radius: selected ? 24 : 14, y: selected ? 14 : 8)
            .scaleEffect(selected ? 1.03 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selected)
        }
        .opacity(item?.hidden == true ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? id : (hovered == id ? nil : hovered) }
        .onTapGesture { choose(id) }
    }

    /// The miniature's title bar: the three window buttons and the title, or the tabs.
    private func titleBar(_ item: OverviewItem?, tabs: [WindowID], shownTab: Int, pinned: Bool) -> some View {
        HStack(spacing: 7) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
            }
            .frame(width: 34, height: 8)
            if tabs.isEmpty {
                Text(item?.title.isEmpty == false ? item!.title : item?.app ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            } else {
                HStack(spacing: 3) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                        AppIcon(image: content.items[tab]?.icon, size: 14)
                            .frame(maxWidth: .infinity)
                            .frame(height: 18)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(index == shownTab ? 0.28 : 0.08)))
                            .onTapGesture { choose(tab) }
                    }
                }
            }
            Spacer(minLength: 0)
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color.black.opacity(0.32))
    }
}

private struct AppIcon: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "macwindow").resizable().scaledToFit().foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
    }
}
