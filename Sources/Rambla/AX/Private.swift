import AppKit
import ApplicationServices
import RamblaCore

/// Undocumented macOS functions, resolved at runtime with dlsym so a missing symbol degrades instead of crashing.
/// Verified on macOS 26.6.2: window ids, Spaces, and focusing one exact window (needed since
/// macOS 14's cooperative activation ignores `activate()` calls from background apps).
enum Private {
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias CopyDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CurrentSpaceFn = @convention(c) (Int32, CFString) -> UInt64
    private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
    private typealias PostEventRecordFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ names: [String], _ type: T.Type) -> T? {
        for name in names {
            if let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) ?? skyLight.flatMap({ dlsym($0, name) }) {
                return unsafeBitCast(pointer, to: type)
            }
        }
        Log.error("Private symbol missing: \(names.joined(separator: "/"))")
        return nil
    }

    private static let getWindow = symbol(["_AXUIElementGetWindow"], GetWindowFn.self)
    private static let mainConnection = symbol(["SLSMainConnectionID", "CGSMainConnectionID"], MainConnectionFn.self)
    private static let copyDisplaySpaces = symbol(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], CopyDisplaySpacesFn.self)
    private static let currentSpaceFn = symbol(["SLSManagedDisplayGetCurrentSpace", "CGSManagedDisplayGetCurrentSpace"], CurrentSpaceFn.self)
    private static let spacesForWindows = symbol(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], SpacesForWindowsFn.self)
    private static let getPSN = symbol(["GetProcessForPID"], GetPSNFn.self)
    private static let setFront = symbol(["_SLPSSetFrontProcessWithOptions"], SetFrontFn.self)
    private static let postEventRecord = symbol(["SLPSPostEventRecordTo"], PostEventRecordFn.self)

    private static let connection: Int32 = mainConnection?() ?? 0

    static func windowID(of element: AXUIElement) -> WindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        guard getWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    struct DisplaySpaces {
        /// Display UUID, or "Main" when "Displays have separate Spaces" is off.
        let displayUUID: String
        let current: UInt64
        /// Space id → space UUID (stable across restarts), for every space on the display.
        let uuids: [UInt64: String]
        /// Native full-screen spaces (type 4).
        let fullscreen: Set<UInt64>
    }

    static func displaySpaces() -> [DisplaySpaces] {
        guard let copyDisplaySpaces, let array = copyDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        return array.compactMap { display in
            guard let uuid = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any],
                  let currentID = (current["ManagedSpaceID"] as? NSNumber)?.uint64Value else { return nil }
            var uuids: [UInt64: String] = [:]
            var fullscreen: Set<UInt64> = []
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
                uuids[id] = space["uuid"] as? String ?? "\(id)"
                if (space["type"] as? NSNumber)?.intValue == 4 { fullscreen.insert(id) }
            }
            return DisplaySpaces(displayUUID: uuid, current: currentID, uuids: uuids, fullscreen: fullscreen)
        }
    }

    static func currentSpace(displayUUID: String) -> UInt64? {
        guard let currentSpaceFn else { return nil }
        let id = currentSpaceFn(connection, displayUUID as CFString)
        return id == 0 ? nil : id
    }

    /// Spaces that contain each window (empty when unknown).
    static func spaces(for windows: [WindowID]) -> [WindowID: [UInt64]] {
        guard let spacesForWindows else { return [:] }
        var result: [WindowID: [UInt64]] = [:]
        for id in windows {
            let list = [NSNumber(value: id)] as CFArray
            let spaces = spacesForWindows(connection, 7, list)?.takeRetainedValue() as? [NSNumber] ?? []
            result[id] = spaces.map(\.uint64Value)
        }
        return result
    }

    /// Makes `window` the key window of its app and brings the app to the front, like yabai/AeroSpace do.
    static func focus(pid: pid_t, window: WindowID) -> Bool {
        guard let getPSN, let setFront, let postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == noErr else { return false }
        guard setFront(&psn, window, 0x200 /* kCPSUserGenerated */) == 0 else { return false }
        var bytes = [UInt8](repeating: 0, count: 0xF8)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        withUnsafeBytes(of: window.littleEndian) { raw in
            for (offset, byte) in raw.enumerated() { bytes[0x3C + offset] = byte }
        }
        for offset in 0x20..<0x30 { bytes[offset] = 0xFF }
        bytes[0x08] = 0x01
        _ = bytes.withUnsafeMutableBufferPointer { postEventRecord(&psn, $0.baseAddress!) }
        bytes[0x08] = 0x02
        _ = bytes.withUnsafeMutableBufferPointer { postEventRecord(&psn, $0.baseAddress!) }
        return true
    }

    /// Brings Rambla itself to the front without raising any of its windows, so the keyboard goes to it: what
    /// `NSApp.activate()` does, for when cooperative activation ignores that from an app in the background.
    @discardableResult
    static func activateOwnProcess() -> Bool {
        guard let getPSN, let setFront else { return false }
        var psn = ProcessSerialNumber()
        guard getPSN(getpid(), &psn) == noErr else { return false }
        return setFront(&psn, 0, 0x400 /* kCPSNoWindows */) == 0
    }
}
