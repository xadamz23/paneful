import AppKit
import PanefulCore

/// Watches global mouse events. Holding the modifier while dragging a window shows its display's zones;
/// releasing over a zone snaps the window there. A drag that ends anywhere else untiles the window.
final class DragMonitor {
    private let tiling: TilingController
    private let overlay: OverlayController
    private var monitor: Any?

    private var window: AXUIElement?
    private var startFrame: CGRect?
    private var isMoving = false
    private var target: (display: Display, zone: ZoneID)?

    init(tiling: TilingController, overlay: OverlayController) {
        self.tiling = tiling
        self.overlay = overlay
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        endDrag()
    }

    private var cursor: CGPoint {
        Coordinates.flip(NSEvent.mouseLocation, primaryScreenHeight: Displays.primaryHeight)
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            window = WindowAccess.window(at: cursor)
            startFrame = window.flatMap(WindowAccess.frame(of:))
            isMoving = false
        case .leftMouseDragged, .flagsChanged:
            update(modifierHeld: event.modifierFlags.contains(tiling.settings.modifier.flags))
        case .leftMouseUp:
            finishDrag()
        default:
            break
        }
    }

    private func update(modifierHeld: Bool) {
        guard let window, let startFrame else { return }
        if !isMoving {
            guard let frame = WindowAccess.frame(of: window) else { return }
            if frame.size != startFrame.size {
                // Resizing, not moving: stop tracking this drag.
                endDrag()
                return
            }
            isMoving = frame.origin != startFrame.origin
            guard isMoving else { return }
        }
        guard modifierHeld, !WindowAccess.isFullScreen(window), let display = tiling.display(containing: cursor) else {
            target = nil
            overlay.hide()
            return
        }
        let rects = tiling.zoneRects(for: display)
        let zone = Geometry.zone(at: cursor, in: rects, gap: tiling.gap)
        target = zone.map { (display, $0) }
        overlay.show(on: display, rects: rects, highlighted: zone)
    }

    private func finishDrag() {
        defer { endDrag() }
        guard let window, isMoving else { return }
        if let target {
            // Let the window server finish the drag before resizing, or it can overwrite our frame.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [tiling] in
                tiling.snap(window, to: target.zone, on: target.display)
            }
        } else {
            tiling.untile(window)
        }
    }

    private func endDrag() {
        window = nil
        startFrame = nil
        isMoving = false
        target = nil
        overlay.hide()
    }
}

extension ModifierKey {
    var flags: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .option: .option
        case .control: .control
        case .command: .command
        }
    }
}
