import Foundation
import CoreGraphics

public typealias WindowID = UInt32

public enum HDirection: String, Codable, Sendable { case left, right }
public enum VDirection: String, Codable, Sendable { case up, down }
public enum PinSide: String, Codable, Sendable { case left, right }
public enum ColumnMode: String, Codable, Sendable { case stacked, tabbed }
public enum CenterMode: String, Codable, CaseIterable, Sendable { case never, onOverflow, always }
public enum InsertPosition: String, Codable, CaseIterable, Sendable { case afterFocused, start, end }

public enum ColumnWidth: Codable, Equatable, Sendable {
    case fraction(Double)
    case points(Double)

    /// A fraction f occupies f*(available+gap)-gap, so N columns of 1/N plus gaps fill `available` exactly.
    public func resolve(available: Double, gap: Double) -> Double {
        switch self {
        case .fraction(let f): return max(1, f * (available + gap) - gap)
        case .points(let p): return max(1, p)
        }
    }

    public func asFraction(available: Double, gap: Double) -> Double {
        switch self {
        case .fraction(let f): return f
        case .points(let p): return (p + gap) / (available + gap)
        }
    }
}

public struct Column: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var windows: [WindowID]
    public var heightWeights: [Double]      // parallel to `windows`
    public var active: Int                  // index into `windows`
    public var mode: ColumnMode
    public var width: ColumnWidth
    public var widthBeforeFull: ColumnWidth?
    public var heightFraction: Double?      // single-window height (nil = full / original)
    public var pinned: PinSide?

    public init(id: UUID = UUID(), windows: [WindowID], width: ColumnWidth, mode: ColumnMode = .stacked) {
        self.id = id
        self.windows = windows
        self.heightWeights = Array(repeating: 1, count: windows.count)
        self.active = 0
        self.mode = mode
        self.width = width
    }

    public var activeWindow: WindowID? { windows.indices.contains(active) ? windows[active] : windows.first }
}

public struct Strip: Codable, Equatable, Sendable {
    public var columns: [Column]
    public var focused: Int?                // index into `columns`
    public var scroll: Double               // strip-space x shown at the scroll area's left edge

    public init(columns: [Column] = [], focused: Int? = nil, scroll: Double = 0) {
        self.columns = columns
        self.focused = focused
        self.scroll = scroll
    }

    /// A column whose windows are all hidden (minimized, app hidden, inactive native tab) takes no space.
    public func isCollapsed(_ column: Int, hidden: Set<WindowID>) -> Bool {
        columns[column].windows.allSatisfy { hidden.contains($0) }
    }

    /// Navigation order: left-pinned column, unpinned columns in array order, right-pinned column; collapsed ones skipped.
    public func visualOrder(hidden: Set<WindowID>) -> [Int] {
        let open = columns.indices.filter { !isCollapsed($0, hidden: hidden) }
        let left = open.filter { columns[$0].pinned == .left }
        let middle = open.filter { columns[$0].pinned == nil }
        let right = open.filter { columns[$0].pinned == .right }
        return left + middle + right
    }
}
