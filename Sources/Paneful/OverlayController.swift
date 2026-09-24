import AppKit
import PanefulCore

/// Click-through windows that draw the zones on the display under the cursor.
final class OverlayController {
    private var windows: [String: NSWindow] = [:]

    func show(on display: Display, rects: [ZoneID: CGRect], highlighted: ZoneID?) {
        for (id, window) in windows where id != display.id { window.orderOut(nil) }
        let window = windows[display.id] ?? makeWindow()
        windows[display.id] = window
        if window.frame != display.screen.frame { window.setFrame(display.screen.frame, display: false) }

        // Zone rects are in Accessibility coordinates; the view wants AppKit coordinates relative to the screen.
        let origin = display.screen.frame.origin
        let view = window.contentView as! ZoneOverlayView
        view.zones = rects.map { id, rect in
            (id: id, rect: Coordinates.flip(rect, primaryScreenHeight: Displays.primaryHeight).offsetBy(dx: -origin.x, dy: -origin.y))
        }
        view.highlighted = highlighted
        view.needsDisplay = true
        window.orderFrontRegardless()
    }

    func hide() {
        windows.values.forEach { $0.orderOut(nil) }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = ZoneOverlayView()
        return window
    }
}

final class ZoneOverlayView: NSView {
    var zones: [(id: ZoneID, rect: CGRect)] = []
    var highlighted: ZoneID?

    override func draw(_ dirtyRect: NSRect) {
        for zone in zones {
            let isHighlighted = zone.id == highlighted
            let path = NSBezierPath(roundedRect: zone.rect, xRadius: 10, yRadius: 10)
            NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.35 : 0.12).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.9 : 0.4).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}
