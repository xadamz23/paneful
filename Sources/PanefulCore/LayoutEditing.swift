import CoreGraphics

extension Node {
    /// Splits `zone` into two equal zones along `axis`. The new zone sits after the original and gets `newZone`
    /// as its ID, or the next free ID if none is given.
    public func splitting(_ zone: ZoneID, along axis: Axis, newZone: ZoneID? = nil) -> Node {
        let newZone = newZone ?? (zoneIDs.max() ?? -1) + 1
        return replacingZone(zone, with: .split(axis, children: [.zone(zone), .zone(newZone)], fractions: [0.5, 0.5])).flattened()
    }

    /// Removes `zone`, giving its space to the zone before it (or after it, if it was first). A split left with one
    /// child collapses into that child. Returns nil if `zone` is the only zone.
    public func removing(_ zone: ZoneID) -> Node? {
        removingWithoutFlattening(zone)?.flattened()
    }

    private func removingWithoutFlattening(_ zone: ZoneID) -> Node? {
        switch self {
        case .zone(let id):
            return id == zone ? nil : self
        case .split(let axis, var children, var fractions):
            guard let index = children.firstIndex(of: .zone(zone)) else {
                return .split(axis, children: children.map { $0.removingWithoutFlattening(zone) ?? $0 }, fractions: fractions)
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

    /// Merges each split's same-axis child splits into it, scaling their fractions, so every divider moves on its own.
    func flattened() -> Node {
        guard case .split(let axis, let children, let fractions) = self else { return self }
        var flatChildren: [Node] = []
        var flatFractions: [Double] = []
        for (child, fraction) in zip(children.map { $0.flattened() }, fractions) {
            if case .split(let childAxis, let grandchildren, let childFractions) = child, childAxis == axis {
                flatChildren += grandchildren
                flatFractions += childFractions.map { $0 * fraction }
            } else {
                flatChildren.append(child)
                flatFractions.append(fraction)
            }
        }
        return .split(axis, children: flatChildren, fractions: flatFractions)
    }

    /// Whether any split has a child split along the same axis. Such nesting ties dividers together.
    var hasSameAxisNesting: Bool {
        guard case .split(let axis, let children, _) = self else { return false }
        return children.contains { child in
            if case .split(let childAxis, _, _) = child, childAxis == axis { return true }
            return child.hasSameAxisNesting
        }
    }
}
