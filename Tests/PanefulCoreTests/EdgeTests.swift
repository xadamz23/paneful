import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct EdgeTests {
    /// Halves zone 0 on the ultrawide with an 8 pt gap.
    let zone = CGRect(x: 8, y: 39, width: 1708, height: 1311)

    @Test func edgeCoordinatesAndAxes() {
        #expect(Edge.left.coordinate(of: zone) == 8)
        #expect(Edge.right.coordinate(of: zone) == 1716)
        #expect(Edge.top.coordinate(of: zone) == 39)
        #expect(Edge.bottom.coordinate(of: zone) == 1350)
        #expect(Edge.left.axis == .vertical && Edge.bottom.axis == .horizontal)
        #expect(Edge.right.isTrailing && Edge.bottom.isTrailing && !Edge.left.isTrailing && !Edge.top.isTrailing)
    }
}
