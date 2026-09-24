import CoreGraphics

extension Node {
    /// Moves the divider under `edge` of `zone` so that the zone's edge lands at `position` (clamped so every zone
    /// stays at least `minSize` along that axis). Returns nil if that edge has no divider, or there's no room.
    public func movingEdge(_ edge: Edge, of zone: ZoneID, to position: CGFloat, in frame: CGRect, gap: CGFloat, minSize: CGFloat) -> Node? {
        guard let (path, index) = divider(for: edge, of: zone),
              case .split(let axis, let children, var fractions) = subnode(at: path) else { return nil }

        // The split's rect is the bounding box of its zones' rects.
        let rects = Geometry.zoneRects(self, in: frame, gap: gap)
        guard let bounds = subnode(at: path).zoneIDs.compactMap({ rects[$0] }).reduce(CGRect?.none, { $0?.union($1) ?? $1 }) else { return nil }
        let isVertical = axis == .vertical
        let start = isVertical ? bounds.minX : bounds.minY
        let length = isVertical ? bounds.width : bounds.height
        let available = length - gap * CGFloat(children.count - 1)

        // Where child `index` must end: at the zone's edge, or one gap before the next child's leading edge.
        let end = edge.isTrailing ? position : position - gap
        let before = fractions[..<index].reduce(0, +)
        let pair = fractions[index] + fractions[index + 1]
        let lower = children[index].minExtent(along: axis, minSize: minSize, gap: gap) / available
        let upper = pair - children[index + 1].minExtent(along: axis, minSize: minSize, gap: gap) / available
        guard lower <= upper else { return nil }

        let fraction = min(max((end - start - gap * CGFloat(index)) / available - before, lower), upper)
        fractions[index] = fraction
        fractions[index + 1] = pair - fraction
        return replacing(at: path, with: .split(axis, children: children, fractions: fractions))
    }

    /// The divider nearest to `zone` on `edge`: the path of its split and the index of the child before it.
    func divider(for edge: Edge, of zone: ZoneID) -> (path: [Int], index: Int)? {
        var found: (path: [Int], index: Int)?
        var node = self
        var path: [Int] = []
        while case .split(let axis, let children, _) = node,
              let childIndex = children.firstIndex(where: { $0.zoneIDs.contains(zone) }) {
            if axis == edge.axis {
                if edge.isTrailing, childIndex < children.count - 1 { found = (path, childIndex) }
                if !edge.isTrailing, childIndex > 0 { found = (path, childIndex - 1) }
            }
            path.append(childIndex)
            node = children[childIndex]
        }
        return found
    }

    func subnode(at path: [Int]) -> Node {
        guard let first = path.first, case .split(_, let children, _) = self else { return self }
        return children[first].subnode(at: Array(path.dropFirst()))
    }

    func replacing(at path: [Int], with replacement: Node) -> Node {
        guard let first = path.first, case .split(let axis, var children, let fractions) = self else { return replacement }
        children[first] = children[first].replacing(at: Array(path.dropFirst()), with: replacement)
        return .split(axis, children: children, fractions: fractions)
    }

    /// The smallest length along `axis` this subtree can take while every zone in it keeps `minSize`.
    /// Children of a same-axis split scale with their fractions, so the tightest child sets the minimum.
    func minExtent(along axis: Axis, minSize: CGFloat, gap: CGFloat) -> CGFloat {
        switch self {
        case .zone:
            return minSize
        case .split(let splitAxis, let children, let fractions):
            let childMinimums = children.map { $0.minExtent(along: axis, minSize: minSize, gap: gap) }
            guard splitAxis == axis else { return childMinimums.max() ?? minSize }
            let content = zip(childMinimums, fractions).map { $0 / $1 }.max() ?? minSize
            return content + gap * CGFloat(children.count - 1)
        }
    }
}
