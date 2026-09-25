import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct DividerDragTests {
    /// Halves on the ultrawide with an 8 pt gap: zone 0's right edge is at x = 1716; the press lands 7 pt right of it.
    private func drag() -> DividerDrag {
        DividerDrag(zone: 0, edge: .right, grabbedAt: 1716, start: CGPoint(x: 1723, y: 600))
    }

    @Test func pressWithoutMovingMovesNothing() {
        var drag = drag()
        #expect(drag.position(for: CGPoint(x: 1723, y: 600), threshold: 10) == nil)
        #expect(drag.position(for: CGPoint(x: 1730, y: 600), threshold: 10) == nil)
        #expect(!drag.hasMoved)
    }

    @Test func movesByTravelFromTheGrabNotToTheCursor() {
        var drag = drag()
        #expect(drag.position(for: CGPoint(x: 1773, y: 600), threshold: 10) == 1766)
        #expect(drag.hasMoved)
    }

    @Test func onceMovingSmallStepsCount() {
        var drag = drag()
        _ = drag.position(for: CGPoint(x: 1773, y: 600), threshold: 10)
        #expect(drag.position(for: CGPoint(x: 1725, y: 640), threshold: 10) == 1718)
    }

    @Test func bottomEdgeFollowsVerticalTravel() {
        var drag = DividerDrag(zone: 0, edge: .bottom, grabbedAt: 691, start: CGPoint(x: 500, y: 695))
        #expect(drag.position(for: CGPoint(x: 520, y: 745), threshold: 10) == 741)
    }
}
