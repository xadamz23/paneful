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
}
