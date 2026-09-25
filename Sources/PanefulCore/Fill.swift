import CoreGraphics

extension Geometry {
    /// Pairs windows (by centre) with `empty` zones, closest pair first, until zones or windows run out, so each
    /// window moves as little as possible. Ties go to the lower zone ID, then the earlier window.
    public static func fill<W>(empty: [ZoneID: CGRect], windows: [(W, CGPoint)]) -> [(W, ZoneID)] {
        var zones = empty
        var remaining = windows
        var pairs: [(W, ZoneID)] = []
        while !zones.isEmpty && !remaining.isEmpty {
            var best: (distance: CGFloat, zone: ZoneID, index: Int)?
            for (index, (_, centre)) in remaining.enumerated() {
                for (zone, rect) in zones {
                    let candidate = (distance: hypot(centre.x - rect.midX, centre.y - rect.midY), zone: zone, index: index)
                    if best.map({ candidate < $0 }) ?? true { best = candidate }
                }
            }
            guard let best else { break }
            pairs.append((remaining.remove(at: best.index).0, best.zone))
            zones[best.zone] = nil
        }
        return pairs
    }
}
