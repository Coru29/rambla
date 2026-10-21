import AppKit
import SwiftUI
import RamblaCore

struct TabItem {
    let windowID: WindowID
    let title: String
    let icon: NSImage?
}

struct TabBarModel {
    let columnID: UUID
    /// The strip the layout reserves above the windows of a tabbed column, in AX coordinates.
    let frame: CGRect
    let tabs: [TabItem]
    let active: Int
}

/// The tab bars of tabbed columns: one small floating panel per column, segmented-control style, with an icon
/// and a truncated title for each window. A click on a segment focuses that window.
///
/// `update` runs on every animation frame, so a panel that did not change only moves.
@MainActor
final class TabBarController {
    private static let maxSpares = 4

    private let onSelect: (WindowID) -> Void
    private var bars: [UUID: TabBar] = [:]
    /// Panels of columns that went away, kept (not destroyed) for the next column that needs a bar.
    private var spares: [TabBar] = []

    init(onSelect: @escaping (WindowID) -> Void) {
        self.onSelect = onSelect
    }

    /// Shows exactly the given bars: panels are created on demand, reused, and hidden when their column is gone.
    func update(_ models: [TabBarModel]) {
        var live: Set<UUID> = []
        for model in models where !model.tabs.isEmpty {
            live.insert(model.columnID)
            bar(for: model.columnID).apply(model)
        }
        for id in Array(bars.keys) where !live.contains(id) { retire(id) }
    }

    private func bar(for columnID: UUID) -> TabBar {
        if let bar = bars[columnID] { return bar }
        let bar = spares.popLast() ?? TabBar { [weak self] id in self?.onSelect(id) }
        bars[columnID] = bar
        return bar
    }

    private func retire(_ columnID: UUID) {
        guard let bar = bars.removeValue(forKey: columnID) else { return }
        bar.hide()
        if spares.count < Self.maxSpares { spares.append(bar) } else { bar.close() }
    }
}

// MARK: - One bar

@MainActor
private final class TabBar {
    private static let cornerRadius: CGFloat = 8
    /// The layout reserves 28 pt above the windows; the panel is this much shorter, so a gap separates it from
    /// the window below (room for the focus border) while its top edge lines up with the other columns.
    private static let bottomGap: CGFloat = 4

    private let panel: OverlayPanel
    private let hosting: OverlayHostingView<TabBarContent>
    private let state: TabBarState
    private let onSelect: (WindowID) -> Void

    init(onSelect: @escaping (WindowID) -> Void) {
        let panel = OverlayPanel(level: .floating, collectionBehavior: [.moveToActiveSpace, .transient])
        let state = TabBarState()
        let hosting = OverlayHostingView(rootView: TabBarContent(state: state))
        self.panel = panel
        self.state = state
        self.hosting = hosting
        self.onSelect = onSelect

        let background = NSVisualEffectView()
        background.material = .titlebar
        background.blendingMode = .behindWindow
        // The panel is never key, and the default state would draw the flat "inactive window" look.
        background.state = .active
        background.maskImage = OverlayStyle.roundedMask(radius: Self.cornerRadius)
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.masksToBounds = true

        hosting.sizingOptions = []
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.onMouseDown = { [weak self] point in self?.click(at: point) }
        background.addSubview(hosting)
        panel.contentView = background
    }

    func apply(_ model: TabBarModel) {
        let frame = Displays.cocoaRect(Self.panelRect(for: model.frame))
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        if !Self.same(state.tabs, model.tabs) { state.tabs = model.tabs }
        if state.active != model.active { state.active = model.active }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        panel.close()
    }

    private static func panelRect(for strip: CGRect) -> CGRect {
        CGRect(x: strip.minX.rounded(), y: strip.minY.rounded(),
               width: strip.width.rounded(), height: max(strip.height - bottomGap, 1).rounded())
    }

    /// Icons come from a per-app cache, so comparing them by identity is enough.
    private static func same(_ a: [TabItem], _ b: [TabItem]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { x, y in
            x.windowID == y.windowID && x.title == y.title && x.icon === y.icon
        }
    }

    /// The segments share the width equally, exactly as `TabBarContent` lays them out.
    private func click(at point: CGPoint) {
        let count = state.tabs.count
        let width = hosting.bounds.width
        guard count > 0, width > 0 else { return }
        let index = min(max(Int(point.x / (width / CGFloat(count))), 0), count - 1)
        onSelect(state.tabs[index].windowID)
    }
}

// MARK: - Views

@MainActor
private final class TabBarState: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var active = 0
}

private struct TabBarContent: View {
    @ObservedObject var state: TabBarState

    var body: some View {
        GeometryReader { proxy in
            let count = max(state.tabs.count, 1)
            let width = proxy.size.width / CGFloat(count)
            HStack(spacing: 0) {
                ForEach(Array(state.tabs.enumerated()), id: \.element.windowID) { index, tab in
                    TabSegment(
                        tab: tab,
                        isActive: index == state.active,
                        // A divider only between two inactive neighbors, like a segmented control.
                        showsSeparator: index < count - 1 && index != state.active && index + 1 != state.active,
                        showsTitle: width >= TabSegment.minimumTitleWidth
                    )
                    .frame(width: width, height: proxy.size.height)
                }
            }
        }
    }
}

private struct TabSegment: View {
    /// Narrower segments show only the icon.
    static let minimumTitleWidth: CGFloat = 64

    let tab: TabItem
    let isActive: Bool
    let showsSeparator: Bool
    let showsTitle: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            icon
            if showsTitle, !tab.title.isEmpty {
                Text(verbatim: tab.title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.white.opacity(0.9))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.15), radius: 1, y: 0.5)
                    .padding(2)
            }
        }
        .overlay(alignment: .trailing) {
            if showsSeparator {
                Rectangle().fill(Color.primary.opacity(0.2)).frame(width: 1, height: 12)
            }
        }
    }

    @ViewBuilder private var icon: some View {
        if let image = tab.icon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
                .opacity(isActive ? 1 : 0.75)
        } else {
            Image(systemName: "macwindow").font(.system(size: 11))
        }
    }
}
