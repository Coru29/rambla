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

/// Everything the overview draws: the strip's cards (strip points) and how big to draw them.
struct OverviewContent {
    var overview: Overview
    var items: [WindowID: OverviewItem]
    /// Overview points per strip point.
    var scale: CGFloat
    /// Strip points between two cards.
    var gap: Double
    var cardHeight: CGFloat
}

@MainActor
final class OverviewState: ObservableObject {
    @Published var content: OverviewContent?
}

/// The overview ("Vista general"): the whole strip of one display at once, over a blurred screen, to see every window
/// and jump to one. A click on a window (or ↩ on the chosen one, or its number) focuses it and closes the overview;
/// esc, a click elsewhere, the shortcut again, another app or another desktop close it as it was.
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

    private func choose(_ id: WindowID) {
        guard let key = shownKey, let item = state.content?.items[id], !item.hidden else { return }
        hide()
        onChoose(id, key)
    }

    // MARK: - Keyboard

    /// Returns true when the overview used the key.
    private func handle(_ event: NSEvent) -> Bool {
        guard var content = state.content else { return false }
        switch event.keyCode {
        case 53: hide()                                         // esc
        case 123: content.overview.move(.left)
        case 124: content.overview.move(.right)
        case 125: content.overview.move(.down)
        case 126: content.overview.move(.up)
        case 36, 76, 49:                                        // return, enter, space
            if let id = content.overview.window(at: content.overview.selection) { choose(id) }
            return true
        default:
            guard let number = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(number) else { return false }
            if let id = content.overview.window(atCard: number) { choose(id) }
            return true
        }
        if shownKey != nil { state.content = content }
        return true
    }

    // MARK: - Panel

    private func makePanel() -> OverviewPanel {
        let panel = OverviewPanel()
        panel.onKey = { [weak self] event in self?.handle(event) ?? false }
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

/// A full-screen panel above the menu bar and the Dock that takes the keyboard without activating Rambla.
final class OverviewPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        // `.nonactivatingPanel` only takes effect when it is part of the style mask at creation.
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
        acceptsMouseMovedEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }

    /// Keys go to the overview before any view: SwiftUI's scroll view would take the arrows.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
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
    let choose: (WindowID) -> Void
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
        let scale = content.scale
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: max(CGFloat(content.gap) * scale, 10)) {
                    ForEach(Array(content.overview.cards.enumerated()), id: \.offset) { index, card in
                        OverviewCard(card: card, index: index, content: content, hovered: $hovered, choose: choose)
                            .frame(width: max(CGFloat(card.width) * scale, 44), height: content.cardHeight)
                            .id(index)
                    }
                }
                .overlay(alignment: .topLeading) { viewport(content) }
                .padding(.horizontal, 70)
                .padding(.vertical, 28)
            }
            .onAppear { proxy.scrollTo(content.overview.selection.card, anchor: .center) }
            .onChange(of: content.overview.selection) { _, selection in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(selection.card, anchor: .center) }
            }
        }
    }

    /// The part of the strip that is on screen now: a bar above the windows, like a scroll bar's thumb.
    @ViewBuilder
    private func viewport(_ content: OverviewContent) -> some View {
        if let range = content.overview.viewport {
            Capsule()
                .fill(.white.opacity(0.45))
                .frame(width: max(CGFloat(range.upperBound - range.lowerBound) * content.scale, 8), height: 3)
                .offset(x: CGFloat(range.lowerBound) * content.scale, y: -16)
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
    let choose: (WindowID) -> Void

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
