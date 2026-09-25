import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct NavigationTests {
    let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
    /// Thirds at gap 8: A = 0, B = 1, C = 2.
    var thirds: [ZoneID: CGRect] { Geometry.zoneRects(Presets.thirds.root, in: frame, gap: 8) }
    /// 2 × 2 at gap 8: TL = 0, BL = 1, TR = 2, BR = 3.
    var grid: [ZoneID: CGRect] { Geometry.zoneRects(Presets.grid2x2.root, in: frame, gap: 8) }

    @Test func thirdsLeftAndRight() {
        #expect(Geometry.neighbour(of: [0], toward: .right, in: thirds) == 1)
        #expect(Geometry.neighbour(of: [1], toward: .right, in: thirds) == 2)
        #expect(Geometry.neighbour(of: [2], toward: .left, in: thirds) == 1)
        #expect(Geometry.neighbour(of: [1], toward: .left, in: thirds) == 0)
    }

    @Test func thirdsEdgesGoNowhere() {
        #expect(Geometry.neighbour(of: [2], toward: .right, in: thirds) == nil)
        #expect(Geometry.neighbour(of: [0], toward: .left, in: thirds) == nil)
        #expect(Geometry.neighbour(of: [1], toward: .top, in: thirds) == nil)
        #expect(Geometry.neighbour(of: [1], toward: .bottom, in: thirds) == nil)
    }

    @Test func gridAllFourDirections() {
        #expect(Geometry.neighbour(of: [0], toward: .right, in: grid) == 2)
        #expect(Geometry.neighbour(of: [0], toward: .bottom, in: grid) == 1)
        #expect(Geometry.neighbour(of: [3], toward: .top, in: grid) == 2)
        #expect(Geometry.neighbour(of: [3], toward: .left, in: grid) == 1)
        #expect(Geometry.neighbour(of: [2], toward: .left, in: grid) == 0)
    }

    @Test func gridEdgesGoNowhere() {
        #expect(Geometry.neighbour(of: [0], toward: .top, in: grid) == nil)
        #expect(Geometry.neighbour(of: [0], toward: .left, in: grid) == nil)
        #expect(Geometry.neighbour(of: [3], toward: .bottom, in: grid) == nil)
        #expect(Geometry.neighbour(of: [3], toward: .right, in: grid) == nil)
    }

    @Test func onePlusTwo() {
        let rects = Geometry.zoneRects(Presets.onePlusTwo.root, in: frame, gap: 8)
        // 1 and 2 are equally far from the left zone's centre, so the lower ID wins.
        #expect(Geometry.neighbour(of: [0], toward: .right, in: rects) == 1)
        #expect(Geometry.neighbour(of: [1], toward: .left, in: rects) == 0)
        #expect(Geometry.neighbour(of: [2], toward: .left, in: rects) == 0)
        #expect(Geometry.neighbour(of: [1], toward: .bottom, in: rects) == 2)
        #expect(Geometry.neighbour(of: [2], toward: .top, in: rects) == 1)
    }

    @Test func unevenColumnPicksTheZoneNearestTheCentre() {
        // Right column split 30 / 70: zone 2's centre (y 650) is nearer the left zone's centre (y 500) than zone 1's (y 150).
        let node = Node.split(.vertical, children: [
            .zone(0),
            .split(.horizontal, children: [.zone(1), .zone(2)], fractions: [0.3, 0.7]),
        ], fractions: [0.5, 0.5])
        let rects = Geometry.zoneRects(node, in: CGRect(x: 0, y: 0, width: 1000, height: 1000), gap: 0)
        #expect(Geometry.neighbour(of: [0], toward: .right, in: rects) == 2)
    }

    @Test func spanMovesToTheZonePastItsEdge() {
        #expect(Geometry.neighbour(of: [0, 1], toward: .right, in: thirds) == 2)
        #expect(Geometry.neighbour(of: [0, 1], toward: .left, in: thirds) == nil)
        #expect(Geometry.neighbour(of: [1, 2], toward: .left, in: thirds) == 0)
    }

    @Test func spanAcrossTopRowMovesDownToLowestID() {
        // BL and BR are equally far from the span's centre.
        #expect(Geometry.neighbour(of: [0, 2], toward: .bottom, in: grid) == 1)
        #expect(Geometry.neighbour(of: [0, 2], toward: .top, in: grid) == nil)
    }

    @Test func touchingZonesAtGapZeroAreNeighbours() {
        let rects = Geometry.zoneRects(Presets.grid2x2.root, in: frame, gap: 0)
        // BR only touches TL at a corner, so it's not a candidate.
        #expect(Geometry.neighbour(of: [0], toward: .right, in: rects) == 2)
        #expect(Geometry.neighbour(of: [0], toward: .bottom, in: rects) == 1)
    }

    @Test func unknownZonesGoNowhere() {
        #expect(Geometry.neighbour(of: [9], toward: .right, in: thirds) == nil)
        #expect(Geometry.neighbour(of: [], toward: .right, in: thirds) == nil)
    }
}
