import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct EdgeTests {
    /// Halves zone 0 on the ultrawide with an 8 pt gap.
    let zone = CGRect(x: 8, y: 39, width: 1708, height: 1311)

    @Test func unchangedFrameMovesNoEdges() {
        #expect(Geometry.movedEdges(from: zone, to: zone).isEmpty)
    }

    @Test func subPointJitterIsIgnored() {
        #expect(Geometry.movedEdges(from: zone, to: zone.insetBy(dx: 0.5, dy: 0.5)).isEmpty)
    }

    @Test func rightEdgeDrag() {
        let frame = CGRect(x: 8, y: 39, width: 2008, height: 1311)
        #expect(Geometry.movedEdges(from: zone, to: frame) == [EdgeMove(edge: .right, position: 2016)])
    }

    @Test func leftEdgeDrag() {
        let frame = CGRect(x: 108, y: 39, width: 1608, height: 1311)
        #expect(Geometry.movedEdges(from: zone, to: frame) == [EdgeMove(edge: .left, position: 108)])
    }

    @Test func cornerDragMovesTwoEdges() {
        let frame = CGRect(x: 8, y: 39, width: 1808, height: 1211)
        #expect(Geometry.movedEdges(from: zone, to: frame) == [
            EdgeMove(edge: .right, position: 1816),
            EdgeMove(edge: .bottom, position: 1250),
        ])
    }

    @Test func overflowOnlyCountsEdgesPastTheZone() {
        // Refused to shrink: its right edge sticks out past the zone.
        let bigger = CGRect(x: 8, y: 39, width: 1808, height: 1311)
        #expect(Geometry.overflowingEdges(of: bigger, beyond: zone) == [EdgeMove(edge: .right, position: 1816)])
        // Smaller than its zone (Terminal's character grid) is not an overflow.
        let smaller = CGRect(x: 8, y: 39, width: 1600, height: 1300)
        #expect(Geometry.overflowingEdges(of: smaller, beyond: zone).isEmpty)
    }

    @Test func edgeCoordinatesAndAxes() {
        #expect(Edge.left.coordinate(of: zone) == 8)
        #expect(Edge.right.coordinate(of: zone) == 1716)
        #expect(Edge.top.coordinate(of: zone) == 39)
        #expect(Edge.bottom.coordinate(of: zone) == 1350)
        #expect(Edge.left.axis == .vertical && Edge.bottom.axis == .horizontal)
        #expect(Edge.right.isTrailing && Edge.bottom.isTrailing && !Edge.left.isTrailing && !Edge.top.isTrailing)
    }
}
