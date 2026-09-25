import AppKit
import PanefulCore

/// Watches global mouse events and turns each press into one gesture:
/// - moving a window: holding the modifier shows its display's zones. Releasing over one snaps the window there;
///   releasing anywhere else untiles it.
/// - resizing a tiled window: the dividers under the dragged edges follow live, resizing the neighbouring windows.
final class DragMonitor {
    private enum Gesture {
        case none
        /// Pressed; waiting for one of the candidate windows to move or resize.
        case pending(candidates: [(window: AXUIElement, frame: CGRect)])
        case moving(AXUIElement, target: (display: Display, zone: ZoneID)?)
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
        let modifierHeld = event.modifierFlags.contains(tiling.settings.modifier.flags)
        switch event.type {
        case .leftMouseDown:
            press()
        case .leftMouseDragged:
            drag(modifierHeld: modifierHeld)
        case .flagsChanged:
            if case .moving(let window, _) = gesture { updateMove(window, modifierHeld: modifierHeld) }
        case .leftMouseUp:
            release()
        default:
            break
        }
    }

    private func press() {
        // A mouse-up swallowed by Mission Control or a Space switch must not leave the last gesture behind.
        overlay.hide()
        let candidates = tiling.pressCandidates(at: cursor).compactMap { window in
            WindowAccess.frame(of: window).map { (window: window, frame: $0) }
        }
        gesture = candidates.isEmpty ? .none : .pending(candidates: candidates)
    }

    private func drag(modifierHeld: Bool) {
        switch gesture {
        case .none:
            break
        case .pending(let candidates):
            classify(candidates, modifierHeld: modifierHeld)
        case .moving(let window, _):
            updateMove(window, modifierHeld: modifierHeld)
        case .resizing(let window, var tracker, let linked):
            guard let frame = WindowAccess.frame(of: window) else { return }
            let moved = tiling.followResize(of: window, moves: tracker.moves(to: frame))
            gesture = .resizing(window, tracker: tracker, linked: linked || moved)
        }
    }

    /// Decides what the press is doing from the first candidate whose frame changed:
    /// same size means moving, a new size means resizing.
    private func classify(_ candidates: [(window: AXUIElement, frame: CGRect)], modifierHeld: Bool) {
        for candidate in candidates {
            guard let frame = WindowAccess.frame(of: candidate.window), frame != candidate.frame else { continue }
            if WindowAccess.isFullScreen(candidate.window) {
                gesture = .none
            } else if frame.size == candidate.frame.size {
                gesture = .moving(candidate.window, target: nil)
                updateMove(candidate.window, modifierHeld: modifierHeld)
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

    private func updateMove(_ window: AXUIElement, modifierHeld: Bool) {
        guard modifierHeld, let display = tiling.display(containing: cursor) else {
            gesture = .moving(window, target: nil)
            overlay.hide()
            return
        }
        let rects = tiling.zoneRects(for: display)
        let zone = Geometry.zone(at: cursor, in: rects, gap: tiling.gap)
        gesture = .moving(window, target: zone.map { (display, $0) })
        overlay.show(on: display, rects: rects, highlighted: zone)
    }

    private func release() {
        let finished = gesture
        gesture = .none
        overlay.hide()
        // Let the window server and the app finish the drag first, or they can overwrite our frames.
        switch finished {
        case .moving(let window, let target?):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [tiling] in
                tiling.snap(window, to: target.zone, on: target.display)
            }
        case .moving(let window, nil):
            tiling.untile(window)
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
