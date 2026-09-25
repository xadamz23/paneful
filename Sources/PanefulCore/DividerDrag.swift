import CoreGraphics

/// A divider being dragged on the editor canvas. It moves by the cursor's travel since the grab, so an
/// off-centre grab doesn't make it jump, and not at all until the cursor has moved past a threshold, so a
/// click near a divider stays a click.
public struct DividerDrag: Sendable {
    public let zone: ZoneID
    public let edge: Edge
    /// Where the zone's edge was when grabbed.
    public let grabbedAt: CGFloat
    public let start: CGPoint
    public private(set) var hasMoved = false

    public init(zone: ZoneID, edge: Edge, grabbedAt: CGFloat, start: CGPoint) {
        self.zone = zone
        self.edge = edge
        self.grabbedAt = grabbedAt
        self.start = start
    }

    /// The zone edge's new position for the cursor at `point`, or nil until the cursor has moved more than `threshold`.
    public mutating func position(for point: CGPoint, threshold: CGFloat) -> CGFloat? {
        if !hasMoved {
            guard hypot(point.x - start.x, point.y - start.y) > threshold else { return nil }
            hasMoved = true
        }
        return grabbedAt + (edge.axis == .vertical ? point.x - start.x : point.y - start.y)
    }
}
