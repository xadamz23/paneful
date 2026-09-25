import CoreGraphics

extension Node {
    /// Splits `zone` into two equal zones along `axis`. The new zone gets the next free ID and sits after the original.
    public func splitting(_ zone: ZoneID, along axis: Axis) -> Node {
        let newZone = (zoneIDs.max() ?? -1) + 1
        return replacingZone(zone, with: .split(axis, children: [.zone(zone), .zone(newZone)], fractions: [0.5, 0.5]))
    }

    /// Removes `zone`, giving its space to the zone before it (or after it, if it was first). A split left with one
    /// child collapses into that child. Returns nil if `zone` is the only zone.
    public func removing(_ zone: ZoneID) -> Node? {
        switch self {
        case .zone(let id):
            return id == zone ? nil : self
        case .split(let axis, var children, var fractions):
            guard let index = children.firstIndex(of: .zone(zone)) else {
                return .split(axis, children: children.map { $0.removing(zone) ?? $0 }, fractions: fractions)
            }
            let share = fractions.remove(at: index)
            children.remove(at: index)
            fractions[max(index - 1, 0)] += share
            return children.count == 1 ? children[0] : .split(axis, children: children, fractions: fractions)
        }
    }

    /// The divider under `point`, as the zone before it and that zone's edge (`.right` or `.bottom`). A divider's
    /// handle is the gap beside the zone, widened by `tolerance` either side, since a gap can be too thin to hit.
    public func dividerHandle(at point: CGPoint, in frame: CGRect, gap: CGFloat, tolerance: CGFloat) -> (zone: ZoneID, edge: Edge)? {
        for (zone, rect) in Geometry.zoneRects(self, in: frame, gap: gap).sorted(by: { $0.key < $1.key }) {
            let right = CGRect(x: rect.maxX - tolerance, y: rect.minY, width: gap + 2 * tolerance, height: rect.height)
            if right.contains(point), divider(for: .right, of: zone) != nil { return (zone, .right) }
            let bottom = CGRect(x: rect.minX, y: rect.maxY - tolerance, width: rect.width, height: gap + 2 * tolerance)
            if bottom.contains(point), divider(for: .bottom, of: zone) != nil { return (zone, .bottom) }
        }
        return nil
    }

    private func replacingZone(_ zone: ZoneID, with replacement: Node) -> Node {
        switch self {
        case .zone(let id):
            return id == zone ? replacement : self
        case .split(let axis, let children, let fractions):
            return .split(axis, children: children.map { $0.replacingZone(zone, with: replacement) }, fractions: fractions)
        }
    }
}
