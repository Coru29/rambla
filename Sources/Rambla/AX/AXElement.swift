import AppKit
import ApplicationServices
import RamblaCore

/// Thin, synchronous wrappers over the Accessibility C API. Call them from the app's worker thread.
enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        guard let value = attribute(element, name), CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement]? {
        guard let value = attribute(element, name), CFGetTypeID(value) == CFArrayGetTypeID() else { return nil }
        return (value as! [CFTypeRef]).compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
        }
    }

    static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }

    /// Position and size in one round trip.
    static func frame(_ element: AXUIElement) -> CGRect? {
        var values: CFArray?
        let names = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(), &values) == .success,
              let array = values as? [CFTypeRef], array.count == 2,
              CFGetTypeID(array[0]) == AXValueGetTypeID(), CFGetTypeID(array[1]) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(array[0] as! AXValue, .cgPoint, &origin),
              AXValueGetValue(array[1] as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setPosition(_ element: AXUIElement, _ point: CGPoint) -> AXError {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return .failure }
        return set(element, kAXPositionAttribute, value)
    }

    @discardableResult
    static func setSize(_ element: AXUIElement, _ size: CGSize) -> AXError {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return .failure }
        return set(element, kAXSizeAttribute, value)
    }

    static func windows(of app: AXUIElement) -> [AXUIElement]? {
        elements(app, kAXWindowsAttribute)
    }

    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        element(app, kAXFocusedWindowAttribute)
    }

    static func title(_ window: AXUIElement) -> String {
        string(window, kAXTitleAttribute) ?? ""
    }

    static func traits(of window: AXUIElement, bundleID: String?, appIsRegular: Bool) -> WindowTraits {
        WindowTraits(
            role: string(window, kAXRoleAttribute),
            subrole: string(window, kAXSubroleAttribute),
            isResizable: isSettable(window, kAXSizeAttribute),
            isMinimized: bool(window, kAXMinimizedAttribute) ?? false,
            isFullscreen: bool(window, "AXFullScreen") ?? false,
            hasCloseButton: element(window, kAXCloseButtonAttribute) != nil,
            hasFullscreenButton: element(window, kAXFullScreenButtonAttribute) != nil,
            bundleID: bundleID,
            appIsRegular: appIsRegular
        )
    }

    static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    static func makeMain(_ window: AXUIElement) {
        set(window, kAXMainAttribute, kCFBooleanTrue)
    }

    static func close(_ window: AXUIElement) {
        if let button = element(window, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    /// Some apps animate (slowly) every programmatic move while this is on; Rectangle turns it off around moves.
    static func enhancedUserInterface(_ app: AXUIElement) -> Bool {
        bool(app, "AXEnhancedUserInterface") ?? false
    }

    static func setEnhancedUserInterface(_ app: AXUIElement, _ on: Bool) {
        set(app, "AXEnhancedUserInterface", on ? kCFBooleanTrue : kCFBooleanFalse)
    }
}

/// Hashable wrapper so AX elements can key dictionaries (CFEqual/CFHash semantics).
struct AXElementKey: Hashable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    static func == (lhs: AXElementKey, rhs: AXElementKey) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}
