import CoreGraphics

/// One display's live state: a working copy of the saved layout (which linked resizing will adjust
/// in Phase 2) plus which windows sit in which zone. The saved layout itself is never changed here.
public struct Arrangement<Window: Hashable> {
    public let saved: Layout
    public private(set) var working: Node
    private var zoneOf: [Window: ZoneID] = [:]

    public init(saved: Layout) {
        self.saved = saved
        self.working = saved.root
    }

    public var tiledWindows: [Window] { Array(zoneOf.keys) }

    public func zone(of window: Window) -> ZoneID? { zoneOf[window] }

    public func windows(in zone: ZoneID) -> [Window] {
        zoneOf.filter { $0.value == zone }.map(\.key)
    }

    /// Puts `window` in `zone`, leaving any zone it was in. Ignored if the zone doesn't exist.
    public mutating func assign(_ window: Window, to zone: ZoneID) {
        guard working.zoneIDs.contains(zone) else { return }
        zoneOf[window] = zone
    }

    public mutating func remove(_ window: Window) {
        zoneOf[window] = nil
    }

    /// Restores the saved layout's boundaries; windows keep their zones.
    public mutating func reset() {
        working = saved.root
    }

    /// Moves the divider under `edge` of `zone` (see `Node.movingEdge`). Only the working tree changes.
    /// Returns false if that edge has no divider.
    @discardableResult
    public mutating func moveEdge(_ edge: Edge, of zone: ZoneID, to position: CGFloat, in frame: CGRect, gap: CGFloat, minSize: CGFloat) -> Bool {
        guard let moved = working.movingEdge(edge, of: zone, to: position, in: frame, gap: gap, minSize: minSize) else { return false }
        working = moved
        return true
    }

    /// Follows one step of a user's resize of a window in `zone`: moves the dividers under the edges that moved
    /// between `previous` and `frame`. Comparing against the previous frame rather than the zone keeps edges the
    /// user didn't touch (a window sitting short of its zone, like Terminal's character grid) from moving dividers.
    /// Returns whether any moved edge sat on a divider.
    @discardableResult
    public mutating func followResize(of zone: ZoneID, from previous: CGRect, to frame: CGRect, in displayFrame: CGRect, gap: CGFloat, minSize: CGFloat) -> Bool {
        var linked = false
        for move in Geometry.movedEdges(from: previous, to: frame) {
            if moveEdge(move.edge, of: zone, to: move.position, in: displayFrame, gap: gap, minSize: minSize) { linked = true }
        }
        return linked
    }

    /// Grows `zone` until it's at least `size` along each axis, for a window that refuses to shrink to its zone.
    /// It moves the divider on the zone's trailing side if there is one, otherwise the one on its leading side,
    /// so a zone against the screen's right or bottom edge grows back toward its neighbour.
    /// Returns whether any divider moved.
    @discardableResult
    public mutating func fit(_ zone: ZoneID, toAtLeast size: CGSize, in displayFrame: CGRect, gap: CGFloat, minSize: CGFloat) -> Bool {
        var moved = false
        for (extent, trailing, leading) in [(size.width, Edge.right, Edge.left), (size.height, Edge.bottom, Edge.top)] {
            guard let rect = rects(in: displayFrame, gap: gap)[zone] else { return moved }
            let current = trailing == .right ? rect.width : rect.height
            guard extent > current + 1 else { continue }
            if moveEdge(trailing, of: zone, to: leading.coordinate(of: rect) + extent, in: displayFrame, gap: gap, minSize: minSize)
                || moveEdge(leading, of: zone, to: trailing.coordinate(of: rect) - extent, in: displayFrame, gap: gap, minSize: minSize) {
                moved = true
            }
        }
        return moved
    }

    /// A fresh arrangement for `saved`, keeping windows whose zones still exist in it.
    public func rebased(on saved: Layout) -> Arrangement {
        var result = Arrangement(saved: saved)
        for (window, zone) in zoneOf { result.assign(window, to: zone) }
        return result
    }

    public func rects(in frame: CGRect, gap: CGFloat) -> [ZoneID: CGRect] {
        Geometry.zoneRects(working, in: frame, gap: gap)
    }
}
