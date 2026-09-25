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

    /// Caps every Accessibility call, so a hung app can stall Paneful for at most a quarter second.
    static func configureTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
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
        return isStandard(window) ? window : nil
    }

    /// The frontmost app's focused window, if it's a standard window that isn't minimised or full screen.
    /// Nil when Paneful itself is frontmost.
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let value = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        return isStandard(window) && !isMinimized(window) && !isFullScreen(window) ? window : nil
    }

    /// Standard windows of visible regular apps, except Paneful's, that aren't minimised or full screen.
    /// Accessibility lists only the current Space's windows, so windows on other Spaces never appear.
    static func visibleWindows() -> [AXUIElement] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != getpid() }
            .flatMap { app in
                attribute(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
            }
            .filter { isStandard($0) && !isMinimized($0) && !isFullScreen($0) }
    }

    private static func isStandard(_ window: AXUIElement) -> Bool {
        attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
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

    /// Moves and resizes a window onto the display area `bounds`. Returns false if the window no longer exists.
    @discardableResult
    static func setFrame(_ frame: CGRect, of window: AXUIElement, within bounds: CGRect) -> Bool {
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
        // macOS ignores resizing a window whose bottom hangs below its screen, so a window that isn't already
        // inside the target display is first moved to its top-left corner.
        if let current = self.frame(of: window), !bounds.contains(current) {
            var corner = bounds.origin
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &corner)!)
        }
        // Size, position, size. Some apps (Ghostty) silently ignore a resize that comes straight after a move,
        // so resize first. The second resize covers apps that clamped the first one to the old display.
        guard AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) != .invalidUIElement else { return false }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return true
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        attribute(window, "AXFullScreen") as? Bool ?? false
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        attribute(window, kAXMinimizedAttribute) as? Bool ?? false
    }

    /// True once the window's app has quit. Its elements then fail with .cannotComplete rather than .invalidUIElement.
    static func isGone(_ window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return true }
        return NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
