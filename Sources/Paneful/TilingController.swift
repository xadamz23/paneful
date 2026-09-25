import AppKit
import PanefulCore

/// Owns settings and each display's arrangement, and moves windows into zones.
final class TilingController {
    private let store: SettingsStore
    private(set) var settings: Settings
    private(set) var displays: [Display] = []
    private var arrangements: [String: Arrangement<AXUIElement>] = [:]
    /// Each tiled window's size from before it was first snapped, given back when it's dragged out of its zone.
    private var sizesBeforeSnap: [AXUIElement: CGSize] = [:]

    /// No zone gets narrower (or shorter) than this while resizing.
    static let minZoneSize: CGFloat = 100
    /// macOS resize handles reach a few points outside a window, into the gap.
    private static let resizeHandleReach: CGFloat = 6

    init(store: SettingsStore) {
        self.store = store
        settings = store.load()
        refreshDisplays()
    }

    var gap: CGFloat { CGFloat(settings.gap) }

    /// Re-reads connected displays. Arrangements restart from saved layouts, keeping tiled windows, which are re-fitted.
    func refreshDisplays() {
        displays = Displays.current()
        let old = arrangements
        arrangements = [:]
        for display in displays {
            let layout = settings.layout(forDisplay: display.id)
            arrangements[display.id] = old[display.id]?.rebased(on: layout) ?? Arrangement(saved: layout)
            refit(display)
        }
    }

    func display(containing point: CGPoint) -> Display? {
        displays.first { $0.frame.contains(point) }
    }

    func zoneRects(for display: Display) -> [ZoneID: CGRect] {
        arrangements[display.id]?.rects(in: display.visibleFrame, gap: gap) ?? [:]
    }

    /// Tiles `window` in `zones` (one zone, or a span), filling their combined rect.
    func snap(_ window: AXUIElement, to zones: Set<ZoneID>, on display: Display) {
        guard let rect = Geometry.union(of: zones, in: zoneRects(for: display)) else { return }
        // Moving between zones keeps the size from before the first snap.
        if !isTiled(window) { sizesBeforeSnap[window] = WindowAccess.frame(of: window)?.size }
        // Only other displays untile it: assign replaces its zones here, so moving a display's only window
        // between zones doesn't empty the display and reset it.
        for id in arrangements.keys where id != display.id { arrangements[id]?.remove(window) }
        arrangements[display.id]?.assign(window, to: zones)
        WindowAccess.setFrame(rect, of: window, within: display.visibleFrame)
    }

    func untile(_ window: AXUIElement) {
        for id in arrangements.keys { arrangements[id]?.remove(window) }
    }

    /// A tiled window was dragged out of its zone and let go at `point`: untile it and give it back the size it
    /// had before it was snapped, keeping the grabbed spot under the cursor and the window on the display.
    func dragOut(_ window: AXUIElement, releasedAt point: CGPoint) {
        guard isTiled(window) else { return }
        untile(window)
        guard let size = sizesBeforeSnap.removeValue(forKey: window),
              let current = WindowAccess.frame(of: window),
              let display = display(containing: point) else { return }
        let restored = Geometry.restoredFrame(from: current, to: size, grab: point, within: display.visibleFrame)
        WindowAccess.setFrame(restored, of: window, within: display.visibleFrame)
    }

    /// Untiles windows that were closed or minimised since Paneful last moved them, so a display left with no
    /// tiled windows goes back to its saved layout before the overlay shows it.
    func forgetClosedWindows() {
        for (id, arrangement) in arrangements {
            for window in arrangement.tiledWindows
            where WindowAccess.isGone(window) || WindowAccess.isMinimized(window) || WindowAccess.frame(of: window) == nil {
                arrangements[id]?.remove(window)
            }
        }
    }

    func isTiled(_ window: AXUIElement) -> Bool {
        location(of: window) != nil
    }

    /// Windows a press at `point` might move or resize: the window under the cursor, plus tiled windows whose
    /// zone is within resize-handle reach, because the handles extend into the gap outside the window.
    func pressCandidates(at point: CGPoint) -> [AXUIElement] {
        var candidates: [AXUIElement] = []
        if let hit = WindowAccess.window(at: point) { candidates.append(hit) }
        guard let display = display(containing: point), let arrangement = arrangements[display.id] else { return candidates }
        let reach = Self.resizeHandleReach
        for (zone, rect) in arrangement.rects(in: display.visibleFrame, gap: gap)
        where rect.insetBy(dx: -reach, dy: -reach).contains(point) {
            for window in arrangement.windows(in: zone) where !candidates.contains(window) {
                candidates.append(window)
            }
        }
        return candidates
    }

    /// Follows one step of a live resize of a tiled window: moves the dividers under the dragged edges to their
    /// new positions and refits the other windows whose zones changed; the resized window itself is left to the
    /// user's drag. Returns whether any dragged edge sat on a divider.
    @discardableResult
    func followResize(of window: AXUIElement, moves: [EdgeMove]) -> Bool {
        guard let (display, zones) = location(of: window), var arrangement = arrangements[display.id] else { return false }
        let before = arrangement.rects(in: display.visibleFrame, gap: gap)
        var linked = false
        for move in moves {
            if arrangement.moveEdge(move.edge, of: zones, to: move.position, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) {
                linked = true
            }
        }
        guard linked else { return false }
        arrangements[display.id] = arrangement
        refit(display, changedFrom: before, except: window)
        return true
    }

    /// Ends a linked resize: snaps every tiled window on the display to its zone, then grows the zones of windows
    /// that refused to shrink (a minimum size) until they fit, so nothing overlaps or hangs off the screen.
    func finishResize(of window: AXUIElement) {
        guard let (display, _) = location(of: window) else { return }
        refit(display)
        guard var arrangement = arrangements[display.id] else { return }
        var moved = false
        for tiled in arrangement.tiledWindows {
            guard let zones = arrangement.zones(of: tiled), let actual = WindowAccess.frame(of: tiled) else { continue }
            if arrangement.fit(zones, toAtLeast: actual.size, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) {
                moved = true
            }
        }
        guard moved else { return }
        arrangements[display.id] = arrangement
        refit(display)
    }

    private func location(of window: AXUIElement) -> (display: Display, zones: Set<ZoneID>)? {
        for display in displays {
            if let zones = arrangements[display.id]?.zones(of: window) { return (display, zones) }
        }
        return nil
    }

    func resetArrangements() {
        for display in displays {
            arrangements[display.id]?.reset()
            refit(display)
        }
    }

    func setLayout(_ layout: Layout, for display: Display) {
        settings.layouts[display.id] = layout
        save()
        arrangements[display.id] = arrangements[display.id]?.rebased(on: layout) ?? Arrangement(saved: layout)
        refit(display)
    }

    func setGap(_ gap: Double) {
        settings.gap = gap
        save()
        displays.forEach { refit($0) }
    }

    func setModifier(_ modifier: ModifierKey) {
        settings.setModifier(modifier)
        save()
    }

    func setSpanModifier(_ modifier: ModifierKey) {
        settings.setSpanModifier(modifier)
        save()
    }

    /// Moves tiled windows on `display` to their zone rects. Given `old` rects, it moves only windows whose
    /// (combined) rect changed. Windows that were closed, minimised or whose app quit are untiled instead.
    private func refit(_ display: Display, changedFrom old: [ZoneID: CGRect]? = nil, except skipped: AXUIElement? = nil) {
        guard let arrangement = arrangements[display.id] else { return }
        let rects = arrangement.rects(in: display.visibleFrame, gap: gap)
        for window in arrangement.tiledWindows where window != skipped {
            guard let zones = arrangement.zones(of: window), let rect = Geometry.union(of: zones, in: rects),
                  old.flatMap({ Geometry.union(of: zones, in: $0) }) != rect else { continue }
            if WindowAccess.isGone(window) || WindowAccess.isMinimized(window) || !WindowAccess.setFrame(rect, of: window, within: display.visibleFrame) {
                arrangements[display.id]?.remove(window)
            }
        }
    }

    private func save() {
        do { try store.save(settings) } catch { NSLog("Paneful: failed to save settings: \(error)") }
    }
}
