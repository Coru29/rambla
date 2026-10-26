import AppKit
import RamblaCore

struct DisplayInfo: Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    /// Full display bounds in AX coordinates (origin top-left of the primary display, y down).
    let frame: CGRect
    /// Bounds minus menu bar and Dock, in AX coordinates.
    let visible: CGRect
    let currentSpace: UInt64?
    /// Stable key of the current Space (its UUID), used to persist strips across restarts.
    let currentSpaceKey: String
    /// Every Space of the display, by id and by key (empty when macOS does not say).
    let spaceIDs: Set<UInt64>
    let spaceKeys: Set<String>
    let isFullscreenSpace: Bool
    let screen: NSScreen

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        lhs.id == rhs.id && lhs.uuid == rhs.uuid && lhs.frame == rhs.frame && lhs.visible == rhs.visible
            && lhs.currentSpace == rhs.currentSpace
    }
}

enum Displays {
    /// AX and Cocoa share the primary display's top edge; flipping uses its height.
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func axRect(_ cocoa: CGRect) -> CGRect {
        CGRect(x: cocoa.minX, y: primaryHeight - cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }

    static func cocoaRect(_ ax: CGRect) -> CGRect {
        CGRect(x: ax.minX, y: primaryHeight - ax.maxY, width: ax.width, height: ax.height)
    }

    static func axPoint(_ cocoa: CGPoint) -> CGPoint {
        CGPoint(x: cocoa.x, y: primaryHeight - cocoa.y)
    }

    static func uuid(of id: CGDirectDisplayID) -> String {
        guard let cfuuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "display-\(id)" }
        return CFUUIDCreateString(nil, cfuuid) as String
    }

    static func current() -> [DisplayInfo] {
        let spaces = Private.displaySpaces()
        let screens = NSScreen.screens
        return screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            let uuid = uuid(of: id)
            let entry = entry(for: uuid, in: spaces)
            let current = entry?.current ?? Private.currentSpace(displayUUID: uuid)
            let key = current.flatMap { entry?.uuids[$0] } ?? current.map { "\($0)" } ?? "none"
            return DisplayInfo(
                id: id, uuid: uuid, name: screen.localizedName,
                frame: axRect(screen.frame), visible: axRect(screen.visibleFrame),
                currentSpace: current, currentSpaceKey: key,
                spaceIDs: Set(entry?.uuids.keys.map { $0 } ?? []), spaceKeys: Set(entry?.uuids.values.map { $0 } ?? []),
                isFullscreenSpace: current.map { entry?.fullscreen.contains($0) ?? false } ?? false,
                screen: screen
            )
        }
    }

    /// The Space display `uuid` shows now, read from the WindowServer the way `current()` reads it: a `DisplayInfo`
    /// has it as of the last reconcile, a moment after a desktop change. Nil when macOS does not say.
    static func currentSpace(of uuid: String) -> UInt64? {
        entry(for: uuid, in: Private.displaySpaces())?.current ?? Private.currentSpace(displayUUID: uuid)
    }

    /// The Spaces of display `uuid` among `spaces`. With "Displays have separate Spaces" off there is a single "Main"
    /// entry for every display.
    private static func entry(for uuid: String, in spaces: [Private.DisplaySpaces]) -> Private.DisplaySpaces? {
        spaces.first { $0.displayUUID.caseInsensitiveCompare(uuid) == .orderedSame }
            ?? spaces.first { $0.displayUUID == "Main" }
    }

    /// The display whose frame contains the largest part of `rect` (nil if none intersects).
    static func best(for rect: CGRect, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.max { area($0.frame.intersection(rect)) < area($1.frame.intersection(rect)) }
            .flatMap { area($0.frame.intersection(rect)) > 0 ? $0 : nil }
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}
