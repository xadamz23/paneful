import CoreGraphics

/// One display's live state: a working copy of the saved layout (which linked resizing adjusts)
/// plus which zones each window covers: one zone, or a span of several. The saved layout itself is never changed here.
public struct Arrangement<Window: Hashable> {
    public let saved: Layout
    public private(set) var working: Node
    private var zonesOf: [Window: Set<ZoneID>] = [:]

    public init(saved: Layout) {
        self.saved = saved
        self.working = saved.root
    }

    public var tiledWindows: [Window] { Array(zonesOf.keys) }

    public func zones(of window: Window) -> Set<ZoneID>? { zonesOf[window] }

    /// Windows covering `zone`, including spans that contain it.
    public func windows(in zone: ZoneID) -> [Window] {
        zonesOf.filter { $0.value.contains(zone) }.map(\.key)
    }

    /// Puts `window` in `zones` (one zone, or a span), leaving wherever it was. Ignored unless every zone exists.
    public mutating func assign(_ window: Window, to zones: Set<ZoneID>) {
        guard !zones.isEmpty, zones.isSubset(of: working.zoneIDs) else { return }
        zonesOf[window] = zones
    }

    public mutating func assign(_ window: Window, to zone: ZoneID) {
        assign(window, to: [zone])
    }

    public mutating func remove(_ window: Window) {
        zonesOf[window] = nil
    }

    /// Restores the saved layout's boundaries; windows keep their zones.
    public mutating func reset() {
        working = saved.root
    }

    /// Moves the dividers under `edge` of the block `zones` covers (see `Node.movingEdge`), along with every divider
    /// a span ties to them, so a span's edges stay straight: a span's edge can sit on dividers in different splits.
    /// If any of them is clamped, they all stop where it did. Only the working tree changes.
    /// Returns false if that edge has no divider.
    @discardableResult
    public mutating func moveEdge(_ edge: Edge, of zones: Set<ZoneID>, to position: CGFloat, in frame: CGRect, gap: CGFloat, minSize: CGFloat) -> Bool {
        let before = rects(in: frame, gap: gap)
        let linked = linkedDividers(under: edge, of: zones, rects: before)
        // One zone per divider, facing it through `edge`, to move it with `Node.movingEdge`.
        var handles: [DividerID: ZoneID] = [:]
        for zone in working.zoneIDs.sorted() {
            if let divider = dividerID(edge, of: zone), linked.contains(divider), handles[divider] == nil { handles[divider] = zone }
        }
        guard let start = handles.values.first.flatMap({ before[$0] }).map(edge.coordinate(of:)) else { return false }

        let move = { (arrangement: inout Arrangement, target: CGFloat) in
            for zone in handles.values {
                if let node = arrangement.working.movingEdge(edge, of: zone, to: target, in: frame, gap: gap, minSize: minSize) {
                    arrangement.working = node
                }
            }
        }
        move(&self, position)
        let after = rects(in: frame, gap: gap)
        let reached = handles.values.compactMap { after[$0].map(edge.coordinate(of:)) }
        if let shortest = reached.min(by: { abs($0 - start) < abs($1 - start) }), reached.contains(where: { $0 != shortest }) {
            move(&self, shortest)
        }
        return true
    }

    /// A divider: its split's path and the index of the child before it.
    private struct DividerID: Hashable {
        let path: [Int]
        let index: Int
    }

    private func dividerID(_ edge: Edge, of zone: ZoneID) -> DividerID? {
        working.divider(for: edge, of: zone).map { DividerID(path: $0.path, index: $0.index) }
    }

    /// The dividers under `edge` of the block `zones` covers.
    private func dividers(under edge: Edge, of zones: Set<ZoneID>, rects: [ZoneID: CGRect]) -> Set<DividerID> {
        guard let block = Geometry.union(of: zones, in: rects) else { return [] }
        return Set(zones.compactMap { zone in
            guard let rect = rects[zone], edge.coordinate(of: rect) == edge.coordinate(of: block) else { return nil }
            return dividerID(edge, of: zone)
        })
    }

    /// The dividers under `edge` of `zones`, plus every divider a tiled span ties to them: all the dividers under
    /// one edge of a span move together.
    private func linkedDividers(under edge: Edge, of zones: Set<ZoneID>, rects: [ZoneID: CGRect]) -> Set<DividerID> {
        var linked = dividers(under: edge, of: zones, rects: rects)
        let sides: [Edge] = edge.axis == .vertical ? [.left, .right] : [.top, .bottom]
        let spanEdges = zonesOf.values.filter { $0.count > 1 }.flatMap { span in
            sides.map { dividers(under: $0, of: span, rects: rects) }
        }
        var grew = true
        while grew {
            grew = false
            for under in spanEdges where !under.isDisjoint(with: linked) && !under.isSubset(of: linked) {
                linked.formUnion(under)
                grew = true
            }
        }
        return linked
    }

    /// Grows the block `zones` covers until it's at least `size` along each axis, for a window that refuses to shrink
    /// to it. It moves the dividers on the block's trailing side if there are any, otherwise those on its leading side,
    /// so a block against the screen's right or bottom edge grows back toward its neighbour.
    /// Returns whether any divider moved.
    @discardableResult
    public mutating func fit(_ zones: Set<ZoneID>, toAtLeast size: CGSize, in displayFrame: CGRect, gap: CGFloat, minSize: CGFloat) -> Bool {
        var moved = false
        for (extent, trailing, leading) in [(size.width, Edge.right, Edge.left), (size.height, Edge.bottom, Edge.top)] {
            guard let rect = Geometry.union(of: zones, in: rects(in: displayFrame, gap: gap)) else { return moved }
            let current = trailing == .right ? rect.width : rect.height
            guard extent > current + 1 else { continue }
            if moveEdge(trailing, of: zones, to: leading.coordinate(of: rect) + extent, in: displayFrame, gap: gap, minSize: minSize)
                || moveEdge(leading, of: zones, to: trailing.coordinate(of: rect) - extent, in: displayFrame, gap: gap, minSize: minSize) {
                moved = true
            }
        }
        return moved
    }

    /// A fresh arrangement for `saved`, keeping windows whose zones all still exist in it.
    public func rebased(on saved: Layout) -> Arrangement {
        var result = Arrangement(saved: saved)
        for (window, zones) in zonesOf { result.assign(window, to: zones) }
        return result
    }

    public func rects(in frame: CGRect, gap: CGFloat) -> [ZoneID: CGRect] {
        Geometry.zoneRects(working, in: frame, gap: gap)
    }
}
