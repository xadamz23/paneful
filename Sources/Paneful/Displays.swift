import AppKit
import PanefulCore

struct Display {
    /// Stable across reboots and reconnects: the display's UUID.
    let id: String
    let name: String
    let screen: NSScreen
    /// Whole display, in Accessibility coordinates.
    let frame: CGRect
    /// Usable area (excluding the menu bar and Dock), in Accessibility coordinates.
    let visibleFrame: CGRect
}

enum Displays {
    /// Height of the primary display, which anchors both coordinate systems.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func current() -> [Display] {
        let primaryHeight = self.primaryHeight
        return NSScreen.screens.map { screen in
            Display(
                id: uuid(of: screen),
                name: screen.localizedName,
                screen: screen,
                frame: Coordinates.flip(screen.frame, primaryScreenHeight: primaryHeight),
                visibleFrame: Coordinates.flip(screen.visibleFrame, primaryScreenHeight: primaryHeight))
        }
    }

    private static func uuid(of screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return "display-\(number)" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
