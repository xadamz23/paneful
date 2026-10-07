import AppKit
import PanefulCore

/// Owns settings and each Space's arrangement per display, and moves windows into zones.
final class TilingController {
    private let store: SettingsStore
    private(set) var settings: Settings
    private(set) var displays: [Display] = []
    private typealias Key = SpaceArrangements<AXUIElement>.Key
    /// Each Space's arrangement per display, so resizing on one Space never moves windows on another.
    private var arrangements = SpaceArrangements<AXUIElement>()
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

    /// Re-reads connected displays. Every Space's arrangements restart from saved layouts, keeping tiled windows,
    /// which are re-fitted.
    func refreshDisplays() {
        displays = Displays.current()
        arrangements.keep(displays: Set(displays.map(\.id)))
        for display in displays {
            arrangements.rebase(display: display.id, on: settings.layout(forDisplay: display.id))
        }
        refitAll()
    }

    func display(containing point: CGPoint) -> Display? {
        displays.first { $0.frame.contains(point) }
    }

    func zoneRects(for display: Display) -> [ZoneID: CGRect] {
        liveArrangement(spaceKey(display)).rects(in: display.visibleFrame, gap: gap)
    }

    /// Tiles `window` in `zones` (one zone, or a span), filling their combined rect.
    func snap(_ window: AXUIElement, to zones: Set<ZoneID>, on display: Display) {
        let key = spaceKey(display)
        var arrangement = liveArrangement(key)
        guard let rect = Geometry.union(of: zones, in: arrangement.rects(in: display.visibleFrame, gap: gap)) else { return }
        // Moving between zones keeps the size from before the first snap.
        if !isTiled(window) { sizesBeforeSnap[window] = WindowAccess.frame(of: window)?.size }
        // Only other displays and Spaces untile it: assign replaces its zones here, so moving a display's only
        // window between zones doesn't empty the display and reset it.
        arrangements.untile(window, except: key)
        arrangement.assign(window, to: zones)
        arrangements.store(arrangement, at: key)
        WindowAccess.setFrame(rect, of: window, within: display.visibleFrame)
    }

    /// What a split drop of `window` onto `zone` would look like: the display's zone rects after the split and the
    /// half it would land in. Nil if the zone is too small to split.
    func splitPreview(of zone: ZoneID, top: Bool, dropping window: AXUIElement, on display: Display) -> (rects: [ZoneID: CGRect], landing: CGRect)? {
        var arrangement = liveArrangement(spaceKey(display))
        guard let landing = arrangement.split(zone, dropping: window, intoTop: top, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize)
        else { return nil }
        let rects = arrangement.rects(in: display.visibleFrame, gap: gap)
        return rects[landing].map { (rects, $0) }
    }

    /// Splits `zone` into top and bottom halves and tiles `window` in one; windows already in the zone move to the
    /// other half. A zone too small to split gets a plain snap.
    func snap(_ window: AXUIElement, splitting zone: ZoneID, top: Bool, on display: Display) {
        let key = spaceKey(display)
        var arrangement = liveArrangement(key)
        guard arrangement.split(zone, dropping: window, intoTop: top, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) != nil else {
            return snap(window, to: [zone], on: display)
        }
        if !isTiled(window) { sizesBeforeSnap[window] = WindowAccess.frame(of: window)?.size }
        arrangements.untile(window, except: key)
        arrangements.store(arrangement, at: key)
        refit(key)
    }

    func untile(_ window: AXUIElement) {
        arrangements.untile(window)
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

    /// Moves the focused window one zone toward `edge` on the display it's tiled on, never onto another display;
    /// at the display's edge nothing happens. An untiled window is snapped into the zone under its centre instead.
    func moveFocusedWindow(toward edge: Edge) {
        guard let window = WindowAccess.focusedWindow(), let frame = WindowAccess.frame(of: window) else { return }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        // A tiled window moved to another display without a drag counts as untiled there, so it never jumps back.
        if let (display, zones) = location(of: window), display.frame.contains(centre) {
            guard let zone = Geometry.neighbour(of: zones, toward: edge, in: zoneRects(for: display)) else { return }
            snap(window, to: [zone], on: display)
        } else {
            guard let display = display(containing: centre),
                  let zone = Geometry.zone(at: centre, in: zoneRects(for: display), gap: gap) else { return }
            snap(window, to: [zone], on: display)
        }
    }

    /// Puts untiled visible windows into every display's empty zones on the current Space: each goes to the nearest
    /// free zone on the display its centre is on. Leftover windows and tiled windows are left alone.
    func fillZones() {
        forgetClosedWindows()
        let space = Spaces.current()
        let untiled = WindowAccess.visibleWindows().filter { !isTiled($0) }.compactMap { window in
            WindowAccess.frame(of: window).map { (window, CGPoint(x: $0.midX, y: $0.midY)) }
        }
        for display in displays {
            let arrangement = liveArrangement(spaceKey(display, space: space))
            let empty = arrangement.rects(in: display.visibleFrame, gap: gap).filter { arrangement.windows(in: $0.key).isEmpty }
            let windows = untiled.filter { display.frame.contains($0.1) }
            for (window, zone) in Geometry.fill(empty: empty, windows: windows) {
                snap(window, to: [zone], on: display)
            }
        }
    }

    /// Untiles windows that were closed or minimised since Paneful last moved them, on every Space, so a display left
    /// with no tiled windows goes back to its saved layout before the overlay shows it.
    func forgetClosedWindows() {
        for key in arrangements.keys {
            var arrangement = liveArrangement(key)
            for window in arrangement.tiledWindows
            where WindowAccess.isGone(window) || WindowAccess.isMinimized(window) || WindowAccess.frame(of: window) == nil {
                arrangement.remove(window)
            }
            arrangements.store(arrangement, at: key)
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
        guard let display = display(containing: point) else { return candidates }
        let arrangement = liveArrangement(spaceKey(display))
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
        let space = Spaces.current()
        guard let (display, zones) = location(of: window, space: space) else { return false }
        let key = spaceKey(display, space: space)
        var arrangement = liveArrangement(key)
        let before = arrangement.rects(in: display.visibleFrame, gap: gap)
        var linked = false
        for move in moves {
            if arrangement.moveEdge(move.edge, of: zones, to: move.position, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) {
                linked = true
            }
        }
        guard linked else { return false }
        arrangements.store(arrangement, at: key)
        refit(key, changedFrom: before, except: window)
        return true
    }

    /// Ends a linked resize: snaps every tiled window on the display to its zone, then grows the zones of windows
    /// that refused to shrink (a minimum size) until they fit, so nothing overlaps or hangs off the screen.
    func finishResize(of window: AXUIElement) {
        let space = Spaces.current()
        guard let (display, _) = location(of: window, space: space) else { return }
        let key = spaceKey(display, space: space)
        refit(key)
        var arrangement = liveArrangement(key)
        var moved = false
        for tiled in arrangement.tiledWindows {
            guard let zones = arrangement.zones(of: tiled), let actual = WindowAccess.frame(of: tiled) else { continue }
            if arrangement.fit(zones, toAtLeast: actual.size, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) {
                moved = true
            }
        }
        guard moved else { return }
        arrangements.store(arrangement, at: key)
        refit(key)
    }

    /// Where `window` is tiled on `space` (the current Space by default).
    private func location(of window: AXUIElement, space: Int = Spaces.current()) -> (display: Display, zones: Set<ZoneID>)? {
        guard let (id, zones) = arrangements.location(of: window, on: space),
              let display = displays.first(where: { $0.id == id }) else { return nil }
        return (display, zones)
    }

    /// Restores the saved layouts' boundaries on the current Space. Other Spaces keep theirs.
    func resetArrangements() {
        let space = Spaces.current()
        for display in displays {
            let key = spaceKey(display, space: space)
            var arrangement = liveArrangement(key)
            arrangement.reset()
            arrangements.store(arrangement, at: key)
            refit(key)
        }
    }

    func setLayout(_ layout: Layout, for display: Display) {
        settings.layouts[display.id] = layout
        save()
        arrangements.rebase(display: display.id, on: layout)
        for key in arrangements.keys where key.display == display.id { refit(key) }
    }

    func setGap(_ gap: Double) {
        settings.gap = gap
        save()
        refitAll()
    }

    func setModifier(_ modifier: ModifierKey) {
        settings.setModifier(modifier)
        save()
    }

    func setSpanModifier(_ modifier: ModifierKey) {
        settings.setSpanModifier(modifier)
        save()
    }

    func setSplitModifier(_ modifier: ModifierKey) {
        settings.setSplitModifier(modifier)
        save()
    }

    /// Moves the tiled windows under `key` to their zone rects. Given `old` rects, it moves only windows whose
    /// (combined) rect changed. Windows that were closed, minimised or whose app quit are untiled instead.
    private func refit(_ key: Key, changedFrom old: [ZoneID: CGRect]? = nil, except skipped: AXUIElement? = nil) {
        guard let display = displays.first(where: { $0.id == key.display }) else { return }
        var arrangement = liveArrangement(key)
        let rects = arrangement.rects(in: display.visibleFrame, gap: gap)
        for window in arrangement.tiledWindows where window != skipped {
            guard let zones = arrangement.zones(of: window), let rect = Geometry.union(of: zones, in: rects),
                  old.flatMap({ Geometry.union(of: zones, in: $0) }) != rect else { continue }
            if WindowAccess.isGone(window) || WindowAccess.isMinimized(window) || !WindowAccess.setFrame(rect, of: window, within: display.visibleFrame) {
                arrangement.remove(window)
            }
        }
        arrangements.store(arrangement, at: key)
    }

    private func refitAll() {
        arrangements.keys.forEach { refit($0) }
    }

    private func spaceKey(_ display: Display, space: Int = Spaces.current()) -> Key {
        Key(space: space, display: display.id)
    }

    /// The arrangement under `key`, or a fresh one from the display's saved layout.
    private func liveArrangement(_ key: Key) -> Arrangement<AXUIElement> {
        arrangements.arrangement(key, saved: settings.layout(forDisplay: key.display))
    }

    private func save() {
        do { try store.save(settings) } catch { NSLog("Paneful: failed to save settings: \(error)") }
    }
}
