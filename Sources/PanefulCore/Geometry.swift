import CoreGraphics

public enum Geometry {
    /// Rects for every zone of `node` inside `frame`, with `gap` between zones and around the edges.
    /// All coordinates are Accessibility coordinates (top-left origin).
    public static func zoneRects(_ node: Node, in frame: CGRect, gap: CGFloat) -> [ZoneID: CGRect] {
        var rects: [ZoneID: CGRect] = [:]
        place(node, in: frame.insetBy(dx: gap, dy: gap), gap: gap, into: &rects)
        return rects
    }

    /// The zone under `point`. Each zone's rect is grown by half the gap, so a point in a gap belongs to the nearer
    /// zone, and a point beyond the outermost zones (screen edge, menu bar, Dock) is pulled in to the nearest one.
    public static func zone(at point: CGPoint, in rects: [ZoneID: CGRect], gap: CGFloat) -> ZoneID? {
        guard let bounds = rects.values.reduce(CGRect?.none, { $0?.union($1) ?? $1 }) else { return nil }
        // Keep the point inside the half-open bounds so the last row and column still contain it.
        let clamped = CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX - 1),
            y: min(max(point.y, bounds.minY), bounds.maxY - 1))
        return rects.first { $0.value.insetBy(dx: -gap / 2, dy: -gap / 2).contains(clamped) }?.key
    }

    /// Where a window dragged out of its zone lands when given back its pre-snap `size`. The top edge stays put,
    /// the point that was grabbed stays under the cursor horizontally, and the frame is kept inside `bounds`.
    public static func restoredFrame(from current: CGRect, to size: CGSize, grab: CGPoint, within bounds: CGRect) -> CGRect {
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        let grabFraction = current.width > 0 ? (grab.x - current.minX) / current.width : 0
        let x = min(max(grab.x - grabFraction * width, bounds.minX), bounds.maxX - width)
        let y = min(max(current.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
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
