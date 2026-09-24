import CoreGraphics

public enum Geometry {
    /// Rects for every zone of `node` inside `frame`, with `gap` between zones and around the edges.
    /// All coordinates are Accessibility coordinates (top-left origin).
    public static func zoneRects(_ node: Node, in frame: CGRect, gap: CGFloat) -> [ZoneID: CGRect] {
        var rects: [ZoneID: CGRect] = [:]
        place(node, in: frame.insetBy(dx: gap, dy: gap), gap: gap, into: &rects)
        return rects
    }

    /// The zone under `point`. Each zone's rect is grown by half the gap, so a point in a gap belongs to the nearer zone.
    public static func zone(at point: CGPoint, in rects: [ZoneID: CGRect], gap: CGFloat) -> ZoneID? {
        rects.first { $0.value.insetBy(dx: -gap / 2, dy: -gap / 2).contains(point) }?.key
    }

    private static func place(_ node: Node, in rect: CGRect, gap: CGFloat, into rects: inout [ZoneID: CGRect]) {
        switch node {
        case .zone(let id):
            rects[id] = rect
        case .split(let axis, let children, let fractions):
            let isVertical = axis == .vertical
            let start = isVertical ? rect.minX : rect.minY
            let length = isVertical ? rect.width : rect.height
            let available = length - gap * CGFloat(children.count - 1)
            var begin = start
            var cumulative = 0.0
            for (index, child) in children.enumerated() {
                cumulative += fractions[index]
                // Round each boundary once so neighbours share it exactly; the last child ends flush with the rect.
                let end = index == children.count - 1
                    ? start + length
                    : (start + available * cumulative + gap * CGFloat(index)).rounded()
                let childRect = isVertical
                    ? CGRect(x: begin, y: rect.minY, width: end - begin, height: rect.height)
                    : CGRect(x: rect.minX, y: begin, width: rect.width, height: end - begin)
                place(child, in: childRect, gap: gap, into: &rects)
                begin = end + gap
            }
        }
    }
}
