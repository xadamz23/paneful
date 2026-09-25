import CoreGraphics

extension Geometry {
    /// The bounding rect of `zones`' rects, or nil if none of them has one.
    public static func union(of zones: Set<ZoneID>, in rects: [ZoneID: CGRect]) -> CGRect? {
        zones.compactMap { rects[$0] }.reduce(CGRect?.none) { $0?.union($1) ?? $1 }
    }

    /// The zones a window dragged with the span key covers: the smallest block of whole zones containing `anchor`
    /// and `current`. Starting from their bounding box, any zone overlapping the box joins it and grows it, until
    /// none does, so a span never half-covers a zone.
    public static func span(from anchor: ZoneID, to current: ZoneID, in rects: [ZoneID: CGRect]) -> Set<ZoneID> {
        var zones = Set([anchor, current].filter { rects[$0] != nil })
        guard var box = union(of: zones, in: rects) else { return [] }
        while let next = rects.first(where: { !zones.contains($0.key) && overlaps($0.value, box) }) {
            zones.insert(next.key)
            box = box.union(next.value)
        }
        return zones
    }

    /// Whether two rects share some area. Rects that only touch (at gap 0) don't.
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let shared = a.intersection(b)
        return !shared.isNull && shared.width > 0 && shared.height > 0
    }
}
