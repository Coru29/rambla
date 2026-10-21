import Foundation
import CoreGraphics

// Layout engine: turns a strip of columns into window frames. Pure logic, no AppKit.
// All geometry is in global AX coordinates (origin top-left, y grows downward), so `maxY` is the bottom edge.

public struct LayoutConfig: Equatable, Sendable {
    public var gap: Double = 8
    public var tabBarHeight: Double = 28
    /// Not used by `compute`: callers hand it to `Layout.reveal` when they scroll a column into view.
    public var centerMode: CenterMode = .never
    public var keepOriginalHeight = false
    /// How much of a parked window stays on its display, in points.
    public var sliver: Double = 1

    public init(gap: Double = 8, tabBarHeight: Double = 28, centerMode: CenterMode = .never,
                keepOriginalHeight: Bool = false, sliver: Double = 1) {
        self.gap = gap
        self.tabBarHeight = tabBarHeight
        self.centerMode = centerMode
        self.keepOriginalHeight = keepOriginalHeight
        self.sliver = sliver
    }
}

public struct LayoutInput: Sendable {
    public var strip: Strip
    /// Region available to the strip: the display's visible frame minus the outer margin.
    public var viewport: CGRect
    /// Full frame of the display the strip lives on. Visibility and parking are decided against it.
    public var display: CGRect
    public var otherDisplays: [CGRect]
    /// Windows that take no space: minimized, app hidden, inactive native tab.
    public var hidden: Set<WindowID>
    public var minSizes: [WindowID: CGSize]
    public var originalHeights: [WindowID: Double]
    public var config: LayoutConfig

    public init(strip: Strip, viewport: CGRect, display: CGRect, otherDisplays: [CGRect] = [], hidden: Set<WindowID> = [],
                minSizes: [WindowID: CGSize] = [:], originalHeights: [WindowID: Double] = [:], config: LayoutConfig = .init()) {
        self.strip = strip
        self.viewport = viewport
        self.display = display
        self.otherDisplays = otherDisplays
        self.hidden = hidden
        self.minSizes = minSizes
        self.originalHeights = originalHeights
        self.config = config
    }
}

public enum Placement: Equatable, Sendable {
    /// The window sits at this frame, possibly extending past a screen edge.
    case visible(CGRect)
    /// The window is moved out of the way with only a sliver left on the display.
    case parked(CGRect)

    public var frame: CGRect {
        switch self {
        case .visible(let frame), .parked(let frame): return frame
        }
    }
}

/// Strip-space geometry (x measured from the scroll area's left edge, before scrolling). Parallel to `strip.columns`.
public struct StripMetrics: Equatable, Sendable {
    /// Left edge of each column. Pinned and collapsed columns get the x of the next slot.
    public var xs: [Double]
    /// Width of each column; 0 for pinned and collapsed columns.
    public var widths: [Double]
    /// Right edge of the last laid-out column (0 when there is none).
    public var total: Double
    /// The scroll area: the viewport minus the pinned columns.
    public var area: CGRect

    /// True for columns that scroll with the strip (not pinned, not collapsed).
    public func isLaidOut(_ i: Int) -> Bool { widths.indices.contains(i) && widths[i] > 0 }
}

public struct LayoutResult: Equatable, Sendable {
    /// One entry per non-hidden window of every non-collapsed column.
    public var placements: [WindowID: Placement]
    /// Screen rect of each laid-out and pinned column, even when its windows are parked (unclamped).
    public var columnFrames: [UUID: CGRect]
    /// Tab bar rects of tabbed columns that are not parked.
    public var tabBars: [UUID: CGRect]
    public var metrics: StripMetrics
}

public enum Layout {

    // MARK: - Metrics

    /// Strip-space x and width of every column, plus the scroll area. Widths resolve against the area, so
    /// pinned columns (which shrink it) are sized first; a column is never narrower than its visible windows' minimum.
    public static func metrics(_ input: LayoutInput) -> StripMetrics {
        buildMetrics(input, slots: resolveSlots(input))
    }

    // MARK: - Scrolling

    /// The scroll value that brings `column` into view according to `mode`. Columns that are not laid out
    /// (pinned, collapsed, out of range) have nothing to reveal and leave `current` untouched.
    public static func reveal(_ m: StripMetrics, column: Int, current: Double, mode: CenterMode) -> Double {
        guard m.xs.indices.contains(column), m.isLaidOut(column) else { return current }
        let w = Double(m.area.width)
        let xi = m.xs[column], wi = m.widths[column]
        let maxScroll = max(0, m.total - w)
        func clamped(_ value: Double) -> Double { min(max(value, 0), maxScroll) }
        switch mode {
        case .never:
            if wi >= w { return clamped(xi) }
            if xi < current { return clamped(xi) }
            if xi + wi > current + w { return clamped(xi + wi - w) }
            return clamped(current)
        case .onOverflow:
            if m.total <= w { return 0 }
            return clamped(xi + wi / 2 - w / 2)
        case .always:
            return xi + wi / 2 - w / 2
        }
    }

    /// Snaps `scroll` to the left edge of the nearest laid-out column (clamped to the strip) and reports
    /// which column then shows the most. Ties go to the lower index. Column is nil without laid-out columns.
    public static func settle(_ m: StripMetrics, scroll: Double) -> (scroll: Double, column: Int?) {
        let laidOut = m.xs.indices.filter { m.isLaidOut($0) }
        guard var nearest = laidOut.first else { return (0, nil) }
        let w = Double(m.area.width)
        for i in laidOut where abs(m.xs[i] - scroll) < abs(m.xs[nearest] - scroll) { nearest = i }
        let target = min(max(m.xs[nearest], 0), max(0, m.total - w))

        var best: Int?
        var bestVisible = -1.0
        for i in laidOut {
            let visible = max(0, min(m.xs[i] + m.widths[i], target + w) - max(m.xs[i], target))
            if visible > bestVisible { best = i; bestVisible = visible }
        }
        return (target, best)
    }

    /// Where a dragged column lands when released at `stripX` (strip space): the index it ends up at once
    /// removed from `dragging` and re-inserted. Nil when the pointer is not over another laid-out column.
    public static func dropIndex(_ m: StripMetrics, stripX: Double, dragging: Int) -> Int? {
        let gap = columnGap(of: m)
        for i in m.xs.indices where i != dragging && m.isLaidOut(i) {
            let left = m.xs[i], width = m.widths[i]
            guard stripX >= left, stripX < left + width + gap else { continue }
            let position = stripX < left + width / 2 ? i : i + 1
            return dragging < position ? position - 1 : position
        }
        return nil
    }

    // MARK: - Compute

    /// Target frames for every window of the strip at `input.strip.scroll`: visible at their real frame, or
    /// parked with a sliver on the display when their column is (nearly) off it. Pinned columns never park.
    public static func compute(_ input: LayoutInput) -> LayoutResult {
        let slots = resolveSlots(input)
        let m = buildMetrics(input, slots: slots)
        let strip = input.strip
        let area = slots.area
        let areaMinY = Double(area.minY), areaHeight = Double(area.height)

        var placements: [WindowID: Placement] = [:]
        var columnFrames: [UUID: CGRect] = [:]
        var tabBars: [UUID: CGRect] = [:]

        for i in strip.columns.indices where !strip.isCollapsed(i, hidden: input.hidden) {
            let column = strip.columns[i]
            let x: Double, w: Double
            let isPinned = i == slots.leftPin || i == slots.rightPin
            if i == slots.leftPin {
                x = Double(input.viewport.minX); w = slots.leftWidth
            } else if i == slots.rightPin {
                w = slots.rightWidth; x = Double(input.viewport.maxX) - w
            } else {
                x = Double(area.minX) + m.xs[i] - strip.scroll; w = m.widths[i]
            }
            let rect = CGRect(x: x, y: areaMinY, width: w, height: areaHeight)
            columnFrames[column.id] = rect

            // Pinned columns stay put; the others are parked once (nearly) off the display.
            let side = isPinned ? nil : parkedSide(of: rect, display: input.display, others: input.otherDisplays)
            for (id, frame) in windowFrames(of: column, in: rect, input) {
                if let side {
                    placements[id] = .parked(parkingFrame(for: frame, side: side, display: input.display,
                                                          others: input.otherDisplays, sliver: input.config.sliver))
                } else {
                    placements[id] = .visible(frame)
                }
            }
            if column.mode == .tabbed, side == nil {
                tabBars[column.id] = CGRect(x: x, y: areaMinY, width: w, height: input.config.tabBarHeight)
            }
        }
        return LayoutResult(placements: placements, columnFrames: columnFrames, tabBars: tabBars, metrics: m)
    }

    // MARK: - Parking

    /// Where to park `frame` so that only `sliver` points stay on `display`, keeping its size and y. Tries the
    /// edge of `side`, then the edge of the opposite side, and returns the first that overlaps none of `others`
    /// (touching edges do not overlap). Falls back to the first candidate when both are taken.
    /// There are no bottom-corner candidates: macOS clamps a window's y so its title bar stays above the Dock.
    public static func parkingFrame(for frame: CGRect, side: HDirection, display: CGRect, others: [CGRect], sliver: Double) -> CGRect {
        let width = Double(frame.width)
        func edge(_ s: HDirection) -> CGRect {
            let x = s == .right ? Double(display.maxX) - sliver : Double(display.minX) + sliver - width
            return CGRect(origin: CGPoint(x: x, y: Double(frame.minY)), size: frame.size)
        }
        let candidates = [edge(side), edge(side == .right ? .left : .right)]
        return candidates.first { candidate in !others.contains { overlaps(candidate, $0) } } ?? candidates[0]
    }
}

// MARK: - Internals

extension Layout {
    /// Where the columns live: the (at most one per side) pinned slots at the viewport edges and the scroll area between them.
    private struct Slots {
        var leftPin: Int?
        var rightPin: Int?
        var leftWidth = 0.0
        var rightWidth = 0.0
        var area: CGRect
    }

    private static func resolveSlots(_ input: LayoutInput) -> Slots {
        let strip = input.strip, gap = input.config.gap, viewport = input.viewport
        // The model keeps one pinned column per side. Should it ever hold more, only the first takes the slot
        // and the others stay in the strip, so no window can disappear.
        func firstOpen(_ side: PinSide) -> Int? {
            strip.columns.indices.first { strip.columns[$0].pinned == side && !strip.isCollapsed($0, hidden: input.hidden) }
        }
        let left = firstOpen(.left), right = firstOpen(.right)
        let leftWidth = left.map { strip.columns[$0].width.resolve(available: Double(viewport.width), gap: gap) } ?? 0
        let rightWidth = right.map { strip.columns[$0].width.resolve(available: Double(viewport.width), gap: gap) } ?? 0

        var minX = Double(viewport.minX), maxX = Double(viewport.maxX)
        if left != nil { minX += leftWidth + gap }
        if right != nil { maxX -= rightWidth + gap }
        let area = CGRect(x: minX, y: Double(viewport.minY), width: max(0, maxX - minX), height: Double(viewport.height))
        return Slots(leftPin: left, rightPin: right, leftWidth: leftWidth, rightWidth: rightWidth, area: area)
    }

    private static func buildMetrics(_ input: LayoutInput, slots: Slots) -> StripMetrics {
        let strip = input.strip, gap = input.config.gap
        var xs: [Double] = [], widths: [Double] = []
        var cursor = 0.0, total = 0.0
        for i in strip.columns.indices {
            xs.append(cursor)
            // Pinned and collapsed columns take no strip space and consume no gap.
            guard i != slots.leftPin, i != slots.rightPin, !strip.isCollapsed(i, hidden: input.hidden) else {
                widths.append(0)
                continue
            }
            let column = strip.columns[i]
            let minWidth = column.windows
                .filter { !input.hidden.contains($0) }
                .compactMap { input.minSizes[$0]?.width }
                .max() ?? 0
            let width = max(column.width.resolve(available: Double(slots.area.width), gap: gap), Double(minWidth))
            widths.append(width)
            total = cursor + width
            cursor += width + gap
        }
        return StripMetrics(xs: xs, widths: widths, total: total, area: slots.area)
    }

    /// The gap the metrics were built with, recovered as the distance between the first two laid-out columns
    /// (0 with fewer than two, where it cannot matter for anything but the strip's trailing edge).
    private static func columnGap(of m: StripMetrics) -> Double {
        let laidOut = m.xs.indices.filter { m.isLaidOut($0) }
        guard laidOut.count >= 2 else { return 0 }
        return m.xs[laidOut[1]] - (m.xs[laidOut[0]] + m.widths[laidOut[0]])
    }

    /// The side a column must be parked on, or nil if it stays visible. `column` is its screen rect.
    private static func parkedSide(of column: CGRect, display: CGRect, others: [CGRect]) -> HDirection? {
        let x = Double(column.minX), w = Double(column.width)
        if x >= Double(display.maxX) - 1 { return .right }
        if x + w <= Double(display.minX) + 1 { return .left }

        // Toward a neighboring display a column may peek out by at most half its width.
        let y = Double(column.minY), h = Double(column.height)
        let beyondRight = x + w - Double(display.maxX)
        if beyondRight > w / 2 {
            let part = CGRect(x: Double(display.maxX), y: y, width: beyondRight, height: h)
            if others.contains(where: { overlaps(part, $0) }) { return .right }
        }
        let beyondLeft = Double(display.minX) - x
        if beyondLeft > w / 2 {
            let part = CGRect(x: x, y: y, width: beyondLeft, height: h)
            if others.contains(where: { overlaps(part, $0) }) { return .left }
        }
        return nil
    }

    /// Frames of the column's non-hidden windows inside its screen rect `rect`.
    private static func windowFrames(of column: Column, in rect: CGRect, _ input: LayoutInput) -> [(WindowID, CGRect)] {
        let config = input.config
        let shown = column.windows.indices.filter { !input.hidden.contains(column.windows[$0]) }
        guard !shown.isEmpty else { return [] }
        let x = Double(rect.minX), y = Double(rect.minY), w = Double(rect.width), h = Double(rect.height)

        if column.mode == .tabbed {
            let frame = CGRect(x: x, y: y + config.tabBarHeight, width: w, height: max(0, h - config.tabBarHeight))
            return shown.map { (column.windows[$0], frame) }
        }

        if shown.count == 1 {
            let id = column.windows[shown[0]]
            var height = h
            if let fraction = column.heightFraction {
                height = min(fraction * h, h)
            } else if config.keepOriginalHeight, let original = input.originalHeights[id] {
                height = min(original, h)
            }
            return [(id, CGRect(x: x, y: y, width: w, height: height))]
        }

        // Stacked: the height left after the gaps is shared out by weight, top to bottom.
        let available = max(0, h - config.gap * Double(shown.count - 1))
        let weights = shown.map { $0 < column.heightWeights.count ? max(0, column.heightWeights[$0]) : 1 }
        let sum = weights.reduce(0, +)
        var top = y
        var frames: [(WindowID, CGRect)] = []
        for (n, index) in shown.enumerated() {
            let share = sum > 0 ? weights[n] / sum : 1 / Double(shown.count)
            let height = available * share
            frames.append((column.windows[index], CGRect(x: x, y: top, width: w, height: height)))
            top += height + config.gap
        }
        return frames
    }

    /// True when the rects share area; touching edges do not count.
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let shared = a.intersection(b)
        return !shared.isNull && shared.width > 0 && shared.height > 0
    }
}
