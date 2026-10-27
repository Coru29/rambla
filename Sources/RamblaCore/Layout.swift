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
    /// Full frame of the display the strip lives on. Visibility and parking are decided against it, except on a side
    /// with a pinned column, where the scroll area's edge decides.
    public var display: CGRect
    public var otherDisplays: [CGRect]
    /// The visible frames of `otherDisplays`, in the same order (below their menu bars). Without them, their frames
    /// stand in.
    public var otherVisible: [CGRect]
    /// Windows that take no space: minimized, app hidden, inactive native tab.
    public var hidden: Set<WindowID>
    public var minSizes: [WindowID: CGSize]
    public var originalHeights: [WindowID: Double]
    public var config: LayoutConfig

    public init(strip: Strip, viewport: CGRect, display: CGRect, otherDisplays: [CGRect] = [], otherVisible: [CGRect] = [],
                hidden: Set<WindowID> = [], minSizes: [WindowID: CGSize] = [:], originalHeights: [WindowID: Double] = [:],
                config: LayoutConfig = .init()) {
        self.strip = strip
        self.viewport = viewport
        self.display = display
        self.otherDisplays = otherDisplays
        self.otherVisible = otherVisible
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
    /// Windows parked on the edge away from their side (a neighbor display sits on that side), with the frame where
    /// they leave the display and come back on their own side. Animations go through it instead of crossing the display.
    public var exits: [WindowID: CGRect] = [:]
}

public enum Layout {

    // MARK: - Metrics

    /// Strip-space x and width of every column, plus the scroll area. Widths resolve against the area, so
    /// pinned columns (which shrink it) are sized first; a column is never wider than the area, unless its visible
    /// windows' minimum needs it to be.
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

    /// Snaps `scroll` to the left edge of the nearest laid-out column (clamped to the strip) and reports the column
    /// it lands on (see below). Ties go to the lower index. Column is nil without laid-out columns.
    public static func settle(_ m: StripMetrics, scroll: Double) -> (scroll: Double, column: Int?) {
        settle(m, scroll: scroll, velocity: 0)
    }

    /// How long a released strip keeps gliding at its release speed before it snaps (seconds).
    static let flickGlide = 0.1
    /// Release speeds from this many scroll-area widths per second on count as a flick.
    static let flickSpeed = 0.3
    /// The farthest a release glides, in scroll-area widths: a stalled main thread can deliver queued events at once
    /// and spike the measured speed.
    static let maxGlide = 1.5

    /// Like `settle(_:scroll:)` for a strip let go while moving at `velocity` (scroll units per second, positive
    /// toward later columns). The strip glides on for `flickGlide` before snapping, so a fast flick can pass
    /// several columns, and a flick always lands at least on the next column in its direction: a short quick
    /// swipe changes column, like swiping between desktops.
    ///
    /// The column it returns is the one the strip lands on: `focused` when the target is its stop too (a strip that
    /// fits on screen, or the columns that share the end of the strip), otherwise the first column whose stop the
    /// target is. Not the most visible one: at the end of a strip a wide column before a narrow last one shows
    /// more, and focusing it would scroll the strip back, so the last column could never be reached.
    public static func settle(_ m: StripMetrics, scroll: Double, velocity: Double,
                              focused: Int? = nil) -> (scroll: Double, column: Int?) {
        let laidOut = m.xs.indices.filter { m.isLaidOut($0) }
        guard !laidOut.isEmpty else { return (0, nil) }
        let w = Double(m.area.width)
        let maxScroll = max(0, m.total - w)
        let stops = laidOut.map { min(max(m.xs[$0], 0), maxScroll) }

        let glided = scroll + min(max(velocity * flickGlide, -maxGlide * w), maxGlide * w)
        var target = stops[0]
        for stop in stops where abs(stop - glided) < abs(target - glided) { target = stop }
        let epsilon = 0.5
        if abs(velocity) >= flickSpeed * w {
            if velocity > 0, target <= scroll + epsilon, let next = stops.first(where: { $0 > scroll + epsilon }) {
                target = next
            } else if velocity < 0, target >= scroll - epsilon, let previous = stops.last(where: { $0 < scroll - epsilon }) {
                target = previous
            }
        }

        if let focused, let index = laidOut.firstIndex(of: focused), abs(stops[index] - target) < epsilon {
            return (target, focused)
        }
        let landed = laidOut.indices.first { abs(stops[$0] - target) < epsilon }.map { laidOut[$0] }
        return (target, landed)
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
    /// parked with a sliver on the display when their column is (nearly) off it, or, on a side with a pinned
    /// column, as soon as it pokes past the scroll area into the pin. Pinned columns themselves never park.
    public static func compute(_ input: LayoutInput) -> LayoutResult {
        let slots = resolveSlots(input)
        let m = buildMetrics(input, slots: slots)
        let strip = input.strip
        let area = slots.area
        let areaMinY = Double(area.minY), areaHeight = Double(area.height)

        var placements: [WindowID: Placement] = [:]
        var columnFrames: [UUID: CGRect] = [:]
        var tabBars: [UUID: CGRect] = [:]
        var exits: [WindowID: CGRect] = [:]
        let walls = Self.walls(input)

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
            let side = isPinned ? nil : parkedSide(of: rect, display: input.display, others: input.otherDisplays,
                                                   walls: walls, slots: slots)
            for (id, frame) in windowFrames(of: column, in: rect, input) {
                if let side {
                    let park = parking(for: frame, side: side, display: input.display, others: input.otherDisplays,
                                       sliver: input.config.sliver)
                    placements[id] = .parked(park.frame)
                    if park.edge != side {
                        exits[id] = exitFrame(for: frame, side: side, display: input.display, slots: slots, walls: walls)
                    }
                } else {
                    placements[id] = .visible(frame)
                }
            }
            if column.mode == .tabbed, side == nil {
                tabBars[column.id] = CGRect(x: x, y: areaMinY, width: w, height: input.config.tabBarHeight)
            }
        }
        return LayoutResult(placements: placements, columnFrames: columnFrames, tabBars: tabBars, metrics: m, exits: exits)
    }

    /// Target frames for every window of a strip that is not in view, all parked with a sliver on the display so
    /// nothing of it shows. Windows `compute` leaves visible (pinned ones too) park at the edge on the side of the
    /// display their center is on, or at the other edge when a neighbor display touches it (`shelvedFrame`); windows
    /// `compute` already parks stay as they are, and hidden ones stay out. Nothing shows to put a tab bar on or to
    /// animate across the display, so there are no tab bars and no exits. The column frames and metrics are
    /// `compute`'s: the strip keeps its place for when it comes back into view.
    public static func shelved(_ input: LayoutInput) -> LayoutResult {
        var result = compute(input)
        result.placements = result.placements.mapValues { placement in
            guard case .visible(let frame) = placement else { return placement }
            return .parked(shelvedFrame(for: frame, display: input.display, others: input.otherDisplays,
                                        sliver: input.config.sliver))
        }
        result.tabBars = [:]
        result.exits = [:]
        return result
    }

    /// Where a window on `display` parks while its strip is out of view: at the edge on the side of the display its
    /// center is on, or at the other edge when a neighbor display overlaps that one (`parkingFrame`), keeping its size
    /// and y. The floating windows that go with their strip park the same way (`FloatShelf`).
    public static func shelvedFrame(for frame: CGRect, display: CGRect, others: [CGRect], sliver: Double) -> CGRect {
        let side: HDirection = frame.midX < display.midX ? .left : .right
        return parking(for: frame, side: side, display: display, others: others, sliver: sliver).frame
    }

    // MARK: - Transitions

    /// How a window gets to its placement when the strip animates.
    public enum Transition: Equatable, Sendable {
        /// Straight there, without animation.
        case jump
        /// Animated from `from` (nil: where the window is now).
        case animate(from: CGRect?)
        /// Animated out to `through`, then straight to its placement.
        case exit(through: CGRect)
    }

    /// How window `id`, now at `current` (nil when unknown), gets to its placement in `result`, the layout that
    /// replaces `previous` on `display` (`others` are the other displays). A window out of sight (at most a sliver of
    /// it on the display) that stays out of sight jumps: it would otherwise cross the display when it changes edges. A
    /// window parked on the edge away from its side leaves and comes back through its own side (`LayoutResult.exits`).
    /// One that comes from another display where it was out of sight too (parked there, or taken back by a display
    /// that returns) comes in through the edge on its side, instead of crossing the displays in between.
    public static func transition(of id: WindowID, at current: CGRect?, to result: LayoutResult, from previous: LayoutResult?,
                                  display: CGRect, others: [CGRect] = [], sliver: Double,
                                  walls: [CGRect] = []) -> Transition {
        guard let placement = result.placements[id], let current else { return .animate(from: nil) }
        func shown(on d: CGRect) -> Double { current.intersects(d) ? Double(current.intersection(d).width) : 0 }
        let outOfSight = shown(on: display) <= sliver + 1
        switch placement {
        case .parked:
            if outOfSight { return .jump }
            if let exit = result.exits[id] { return .exit(through: exit) }
        case .visible(let frame):
            guard outOfSight else { break }
            if let exit = previous?.exits[id] {
                // Its size may have changed meanwhile: centered where it left, and never further over a lower neighbor
                // than a peek (`wallPeek`).
                let w = Double(frame.width), y = Double(frame.minY), h = Double(frame.height)
                var x = Double(exit.midX) - w / 2
                if exit.midX > display.midX {
                    if walled(.right, width: w, display: display, y: y, height: h, walls: walls) {
                        x = min(x, edgeX(.right, width: w, display: display, y: y, height: h, walls: walls))
                    }
                } else if walled(.left, width: w, display: display, y: y, height: h, walls: walls) {
                    x = max(x, edgeX(.left, width: w, display: display, y: y, height: h, walls: walls))
                }
                return .animate(from: CGRect(x: x, y: y, width: w, height: h))
            }
            if shown(on: display) < 0.5, others.allSatisfy({ shown(on: $0) <= sliver + 1 }) {
                let x = edgeX(current.midX > display.midX ? .right : .left, width: Double(frame.width), display: display,
                              y: Double(frame.minY), height: Double(frame.height), walls: walls)
                return .animate(from: CGRect(x: x, y: Double(frame.minY), width: frame.width, height: frame.height))
            }
        }
        return .animate(from: nil)
    }

    // MARK: - Parking

    /// Where to park `frame` so that only `sliver` points stay on `display`, keeping its size and y. Tries the
    /// edge of `side`, then the edge of the opposite side, and returns the first that overlaps none of `others`
    /// (touching edges do not overlap). Falls back to the first candidate when both are taken.
    /// There are no bottom-corner candidates: macOS clamps a window's y so its title bar stays above the Dock.
    public static func parkingFrame(for frame: CGRect, side: HDirection, display: CGRect, others: [CGRect], sliver: Double) -> CGRect {
        parking(for: frame, side: side, display: display, others: others, sliver: sliver).frame
    }

    /// `parkingFrame`, with the edge it uses.
    static func parking(for frame: CGRect, side: HDirection, display: CGRect, others: [CGRect], sliver: Double)
        -> (frame: CGRect, edge: HDirection) {
        let width = Double(frame.width)
        func edge(_ s: HDirection) -> (frame: CGRect, edge: HDirection) {
            let x = s == .right ? Double(display.maxX) - sliver : Double(display.minX) + sliver - width
            return (CGRect(origin: CGPoint(x: x, y: Double(frame.minY)), size: frame.size), s)
        }
        let candidates = [edge(side), edge(side == .right ? .left : .right)]
        return candidates.first { candidate in !others.contains { overlaps(candidate.frame, $0) } } ?? candidates[0]
    }

    /// Where a window parked away from `side` leaves the display on `side`: as far out as a column may peek toward a
    /// neighbor display, kept just under half so it still shows on this display; next to a pinned column, flush with
    /// the scroll area instead (strip columns never slide under a pin).
    private static func exitFrame(for frame: CGRect, side: HDirection, display: CGRect, slots: Slots,
                                  walls: [CGRect]) -> CGRect {
        let w = Double(frame.width)
        let x: Double
        switch side {
        case .right where slots.rightPin != nil: x = Double(slots.area.maxX) - w
        case .left where slots.leftPin != nil: x = Double(slots.area.minX)
        default: x = edgeX(side, width: w, display: display, y: Double(frame.minY), height: Double(frame.height), walls: walls)
        }
        return CGRect(x: x, y: Double(frame.minY), width: w, height: Double(frame.height))
    }

    /// Where a window `width` wide sits as it leaves or comes in through `side`: just under the most of it that may be
    /// out, half, or `wallPeek` toward a lower neighbor (`walls`).
    static func edgeX(_ side: HDirection, width: Double, display: CGRect, y: Double, height: Double,
                      walls: [CGRect]) -> Double {
        let out = walled(side, width: width, display: display, y: y, height: height, walls: walls) ? wallPeek : 0.5
        switch side {
        case .right: return Double(display.maxX) - width * (1 - out) - 1
        case .left: return Double(display.minX) - width * out + 1
        }
    }

    /// The most of a window's width that may reach over a lower neighbor (`walls`): under half, with room to spare.
    /// At exactly half, macOS or the app can take the window for one of that display, and push it down below its menu
    /// bar.
    public static let wallPeek = 0.45

    /// Whether a lower neighbor (`walls`) is beyond `side` of `display`, where a window `width` wide and `height` tall
    /// at `y` would reach out.
    static func walled(_ side: HDirection, width: Double, display: CGRect, y: Double, height: Double,
                       walls: [CGRect]) -> Bool {
        let probe = side == .right ? CGRect(x: Double(display.maxX), y: y, width: width / 2, height: height)
                                   : CGRect(x: Double(display.minX) - width / 2, y: y, width: width / 2, height: height)
        return walls.contains { overlaps(probe, $0) }
    }

    /// The other displays a window of the strip may reach over only a little (`wallPeek`): those whose visible area
    /// begins below the strip's top (they sit lower, or their menu bar is taller). macOS, or the app (VS Code does),
    /// pushes a window that reaches half over one down below that menu bar, and the window jumps back up as Rambla puts
    /// it in place again.
    public static func walls(_ input: LayoutInput) -> [CGRect] {
        let top = Double(input.viewport.minY)
        return input.otherDisplays.indices.filter { index in
            let visible = input.otherVisible.indices.contains(index) ? input.otherVisible[index] : input.otherDisplays[index]
            return Double(visible.minY) > top + 1
        }.map { input.otherDisplays[$0] }
    }
}

// MARK: - Internals

extension Layout {
    // A column showing at most 1 pt counts as off-screen; a fixed test, not `config.sliver` (what a parked window leaves behind).
    private static let parkThreshold = 1.0
    // Rounding slack: a column revealed flush against a pin must not look like it pokes under it.
    private static let edgeNoise = 1e-6
    // Windows never get less height than this: AX cannot size an empty window.
    private static let minHeight = 1.0

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
            // Never wider than the scroll area, so a wide window beside a pin is not parked while focused; only a
            // window that cannot be narrower makes its column wider.
            let wanted = min(column.width.resolve(available: Double(slots.area.width), gap: gap), Double(slots.area.width))
            let width = max(wanted, Double(minWidth))
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
    ///
    /// A side with a pinned column uses the scroll area's edge instead of the display's, and parks a column that pokes
    /// past it at all: strip columns never slide under a pin, so nothing peeks there. The other sides use the display's
    /// edge, and toward a neighboring display let a column peek out by at most half its width.
    private static func parkedSide(of column: CGRect, display: CGRect, others: [CGRect], walls: [CGRect],
                                   slots: Slots) -> HDirection? {
        let x = Double(column.minX), w = Double(column.width)
        let area = slots.area

        if slots.rightPin != nil {
            if x + w > Double(area.maxX) + edgeNoise { return .right }
        } else if x >= Double(display.maxX) - parkThreshold {
            return .right
        }
        if slots.leftPin != nil {
            if x < Double(area.minX) - edgeNoise { return .left }
        } else if x + w <= Double(display.minX) + parkThreshold {
            return .left
        }

        let y = Double(column.minY), h = Double(column.height)
        // Toward a lower neighbor (`walls`) a smaller peek: parked once more than `wallPeek` of it would reach over.
        if slots.rightPin == nil {
            let beyond = x + w - Double(display.maxX)
            let part = CGRect(x: Double(display.maxX), y: y, width: max(beyond, 0), height: h)
            if beyond > w * wallPeek, walls.contains(where: { overlaps(part, $0) }) { return .right }
            if beyond > w / 2, others.contains(where: { overlaps(part, $0) }) { return .right }
        }
        if slots.leftPin == nil {
            let beyond = Double(display.minX) - x
            let part = CGRect(x: x, y: y, width: max(beyond, 0), height: h)
            if beyond > w * wallPeek, walls.contains(where: { overlaps(part, $0) }) { return .left }
            if beyond > w / 2, others.contains(where: { overlaps(part, $0) }) { return .left }
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
            let frame = CGRect(x: x, y: y + config.tabBarHeight, width: w, height: max(minHeight, h - config.tabBarHeight))
            return shown.map { (column.windows[$0], frame) }
        }

        if shown.count == 1 {
            let id = column.windows[shown[0]]
            var height = h
            if let fraction = column.heightFraction {
                height = fraction * h
            } else if config.keepOriginalHeight, let original = input.originalHeights[id] {
                height = original
            }
            return [(id, CGRect(x: x, y: y, width: w, height: max(minHeight, min(height, h))))]
        }

        // Stacked: the height left after the gaps is shared out by weight, top to bottom. A window squeezed below
        // the minimum (zero weight) keeps the minimum and pushes the ones under it down by the difference.
        let available = max(0, h - config.gap * Double(shown.count - 1))
        let weights = shown.map { $0 < column.heightWeights.count ? max(0, column.heightWeights[$0]) : 1 }
        let sum = weights.reduce(0, +)
        var top = y
        var frames: [(WindowID, CGRect)] = []
        for (n, index) in shown.enumerated() {
            let share = sum > 0 ? weights[n] / sum : 1 / Double(shown.count)
            let height = max(minHeight, available * share)
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
