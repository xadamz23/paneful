import CoreGraphics

extension Geometry {
    /// The zone next to the block `zones` covers, toward `edge`: of the zones wholly past that edge that overlap the
    /// block on the other axis, the nearest ones along the direction, then the one whose centre is closest to the
    /// block's centre on the other axis, then the lowest ID. Nil at the display's edge.
    public static func neighbour(of zones: Set<ZoneID>, toward edge: Edge, in rects: [ZoneID: CGRect]) -> ZoneID? {
        guard let block = union(of: zones, in: rects) else { return nil }
        let horizontal = edge.axis == .vertical
        // How far past the block's edge a rect starts; negative if it isn't wholly past it.
        let distance = { (rect: CGRect) -> CGFloat in
            switch edge {
            case .left: return block.minX - rect.maxX
            case .right: return rect.minX - block.maxX
            case .top: return block.minY - rect.maxY
            case .bottom: return rect.minY - block.maxY
            }
        }
        let overlapsAcross = { (rect: CGRect) -> Bool in
            horizontal ? rect.minY < block.maxY && rect.maxY > block.minY : rect.minX < block.maxX && rect.maxX > block.minX
        }
        let candidates = rects.filter { !zones.contains($0.key) && distance($0.value) >= 0 && overlapsAcross($0.value) }
        guard let nearest = candidates.values.map(distance).min() else { return nil }
        let offCentre = { (rect: CGRect) -> CGFloat in horizontal ? abs(rect.midY - block.midY) : abs(rect.midX - block.midX) }
        return candidates
            .filter { distance($0.value) < nearest + 0.5 }
            .min { (offCentre($0.value), $0.key) < (offCentre($1.value), $1.key) }?
            .key
    }
}
