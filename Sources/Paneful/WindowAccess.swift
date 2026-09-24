import AppKit
import ApplicationServices

/// The only place Paneful talks to the Accessibility API.
enum WindowAccess {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Adds Paneful to the Accessibility list and shows the system prompt, which links to System Settings.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// The standard window under a point (Accessibility coordinates), excluding Paneful's own windows.
    static func window(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != getpid() else { return nil }

        let window: AXUIElement
        if attribute(element, kAXRoleAttribute) as? String == kAXWindowRole {
            window = element
        } else if let value = attribute(element, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
            window = value as! AXUIElement
        } else {
            return nil
        }
        return attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole ? window : nil
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute),
              let size = attribute(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    /// Moves and resizes a window. Returns false if the window no longer exists.
    @discardableResult
    static func setFrame(_ frame: CGRect, of window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = AXUIElementCreateApplication(pid)
        // With AXEnhancedUserInterface on, some apps (Chrome, Electron) animate and land in the wrong place.
        let enhanced = attribute(app, "AXEnhancedUserInterface") as? Bool ?? false
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer { if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) } }

        var origin = frame.origin
        var size = frame.size
        let positionValue = AXValueCreate(.cgPoint, &origin)!
        let sizeValue = AXValueCreate(.cgSize, &size)!
        // Position, size, position: moving first lets the size fit on the target display; the second move
        // corrects apps that clamped the position against their old size.
        guard AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) != .invalidUIElement else { return false }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        return true
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        attribute(window, "AXFullScreen") as? Bool ?? false
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
