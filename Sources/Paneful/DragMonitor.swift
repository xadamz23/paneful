import AppKit
import PanefulCore

/// Watches global mouse events and turns each press into one gesture:
/// - moving a window: holding the modifier shows its display's zones. Releasing over one snaps the window there;
///   releasing anywhere else untiles it. Holding the span key as well stretches the target from the zone it was
///   pressed over (the anchor) to the zone under the cursor. Holding the split key instead splits the zone under the
///   cursor into top and bottom halves, and the window drops into the half under the cursor.
/// - resizing a tiled window: the dividers under the dragged edges follow live, resizing the neighbouring windows.
final class DragMonitor {
    private enum Gesture {
        case none
        /// Pressed; waiting for one of the candidate windows to move or resize.
        case pending(candidates: [(window: AXUIElement, frame: CGRect)], pressedAt: CGPoint)
        /// `anchor` is where the span key went down, kept only while it's held on that display. `splitTop` is set
        /// when the drop splits `zones` (a single zone): true for its top half.
        case moving(AXUIElement, target: (display: Display, zones: Set<ZoneID>, splitTop: Bool?)?, anchor: (displayID: String, zone: ZoneID)?)
        /// The tracker decides which edges the user is dragging, so only those move dividers.
        case resizing(AXUIElement, tracker: ResizeTracker, linked: Bool)
    }

    private let tiling: TilingController
    private let overlay: OverlayController
    private var monitor: Any?
    private var gesture = Gesture.none

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
        gesture = .none
        overlay.hide()
    }

    private var cursor: CGPoint {
        Coordinates.flip(NSEvent.mouseLocation, primaryScreenHeight: Displays.primaryHeight)
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            press()
        case .leftMouseDragged:
            drag(flags: event.modifierFlags)
        case .flagsChanged:
            if case .moving(let window, _, _) = gesture { updateMove(window, flags: event.modifierFlags) }
        case .leftMouseUp:
            release()
        default:
            break
        }
    }

    private func press() {
        // A mouse-up swallowed by Mission Control or a Space switch must not leave the last gesture behind.
        overlay.hide()
        let pressedAt = cursor
        let candidates = tiling.pressCandidates(at: pressedAt).compactMap { window in
            WindowAccess.frame(of: window).map { (window: window, frame: $0) }
        }
        gesture = candidates.isEmpty ? .none : .pending(candidates: candidates, pressedAt: pressedAt)
    }

    private func drag(flags: NSEvent.ModifierFlags) {
        switch gesture {
        case .none:
            break
        case .pending(let candidates, let pressedAt):
            classify(candidates, pressedAt: pressedAt, flags: flags)
        case .moving(let window, _, _):
            updateMove(window, flags: flags)
        case .resizing(let window, var tracker, let linked):
            guard let frame = WindowAccess.frame(of: window) else { return }
            let moved = tiling.followResize(of: window, moves: tracker.moves(to: frame))
            gesture = .resizing(window, tracker: tracker, linked: linked || moved)
        }
    }

    /// Decides what the press is doing from the first candidate whose frame changed:
    /// same size means moving, a new size means resizing.
    private func classify(_ candidates: [(window: AXUIElement, frame: CGRect)], pressedAt: CGPoint, flags: NSEvent.ModifierFlags) {
        for candidate in candidates {
            guard let frame = WindowAccess.frame(of: candidate.window), frame != candidate.frame else { continue }
            if WindowAccess.isFullScreen(candidate.window) {
                gesture = .none
            } else if frame.size == candidate.frame.size {
                tiling.forgetClosedWindows()
                // A move is recognised some way into the drag, so a span key held from the start anchors where the press was.
                gesture = .moving(candidate.window, target: nil, anchor: flags.contains(tiling.settings.spanModifier.flags) ? zone(at: pressedAt) : nil)
                updateMove(candidate.window, flags: flags)
            } else if tiling.isTiled(candidate.window) {
                var tracker = ResizeTracker(start: candidate.frame)
                let linked = tiling.followResize(of: candidate.window, moves: tracker.moves(to: frame))
                gesture = .resizing(candidate.window, tracker: tracker, linked: linked)
            } else {
                gesture = .none
            }
            return
        }
    }

    private func updateMove(_ window: AXUIElement, flags: NSEvent.ModifierFlags) {
        guard flags.contains(tiling.settings.modifier.flags), let display = tiling.display(containing: cursor) else {
            gesture = .moving(window, target: nil, anchor: nil)
            overlay.hide()
            return
        }
        let rects = tiling.zoneRects(for: display)
        let zone = Geometry.zone(at: cursor, in: rects, gap: tiling.gap)
        // The split key wins over the span key. A zone too small to split falls through to a plain target.
        if flags.contains(tiling.settings.splitModifier.flags), let zone, let rect = rects[zone] {
            let top = cursor.y < rect.midY
            if let preview = tiling.splitPreview(of: zone, top: top, dropping: window, on: display) {
                gesture = .moving(window, target: (display: display, zones: [zone], splitTop: top), anchor: nil)
                overlay.show(on: display, rects: preview.rects, highlighted: preview.landing)
                return
            }
        }
        // The anchor is set the first time the span key is seen held, and dropped when it's released.
        let anchor = flags.contains(tiling.settings.spanModifier.flags) ? spanAnchor(on: display) ?? zone : nil
        let zones = zone.map { zone in anchor.map { Geometry.span(from: $0, to: zone, in: rects) } ?? [zone] }
        gesture = .moving(window, target: zones.map { (display: display, zones: $0, splitTop: nil) }, anchor: anchor.map { (displayID: display.id, zone: $0) })
        overlay.show(on: display, rects: rects, highlighted: zones.flatMap { Geometry.union(of: $0, in: rects) })
    }

    /// The zone under `point`, with its display.
    private func zone(at point: CGPoint) -> (displayID: String, zone: ZoneID)? {
        guard let display = tiling.display(containing: point),
              let zone = Geometry.zone(at: point, in: tiling.zoneRects(for: display), gap: tiling.gap) else { return nil }
        return (display.id, zone)
    }

    /// The span anchor of the move in progress, if it was set on `display`. Moving to another display drops it.
    private func spanAnchor(on display: Display) -> ZoneID? {
        guard case .moving(_, _, let anchor?) = gesture, anchor.displayID == display.id else { return nil }
        return anchor.zone
    }

    private func release() {
        let finished = gesture
        gesture = .none
        overlay.hide()
        // Let the window server and the app finish the drag first, or they can overwrite our frames.
        switch finished {
        case .moving(let window, let target?, _):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [tiling] in
                if let top = target.splitTop, let zone = target.zones.first {
                    tiling.snap(window, splitting: zone, top: top, on: target.display)
                } else {
                    tiling.snap(window, to: target.zones, on: target.display)
                }
            }
        case .moving(let window, nil, _):
            let releasedAt = cursor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [tiling] in
                tiling.dragOut(window, releasedAt: releasedAt)
            }
        case .resizing(let window, _, true):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [tiling] in
                tiling.finishResize(of: window)
            }
        default:
            break
        }
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
