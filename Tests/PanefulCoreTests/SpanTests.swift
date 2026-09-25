import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct SpanTests {
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)
    /// 2 × 2 at gap 0: TL = 0, BL = 1, TR = 2, BR = 3, each 500 × 400.
    let grid = Geometry.zoneRects(Presets.grid2x2.root, in: CGRect(x: 0, y: 0, width: 1000, height: 800), gap: 0)

    @Test func neighboursInThirds() {
        let rects = Geometry.zoneRects(Presets.thirds.root, in: ultrawide, gap: 8)
        #expect(Geometry.span(from: 0, to: 1, in: rects) == [0, 1])
        #expect(Geometry.span(from: 1, to: 0, in: rects) == [0, 1])
        #expect(Geometry.span(from: 0, to: 2, in: rects) == [0, 1, 2])
    }

    @Test func sameZoneIsJustThatZone() {
        let rects = Geometry.zoneRects(Presets.thirds.root, in: ultrawide, gap: 8)
        #expect(Geometry.span(from: 1, to: 1, in: rects) == [1])
    }

    @Test func rowIn2x2() {
        // At gap 0 the bottom row touches the top row, and touching isn't overlapping.
        #expect(Geometry.span(from: 0, to: 2, in: grid) == [0, 2])
    }

    @Test func diagonalIn2x2IsTheWholeScreen() {
        #expect(Geometry.span(from: 0, to: 3, in: grid) == [0, 1, 2, 3])
    }

    @Test func unalignedRowsPullInNeighbours() {
        // Left column split 50/50, right column 30/70: the box over TL and TR half-covers BR, so BR joins,
        // and then the box covers BL too.
        let node = Node.split(.vertical, children: [
            .split(.horizontal, children: [.zone(0), .zone(1)], fractions: [0.5, 0.5]),
            .split(.horizontal, children: [.zone(2), .zone(3)], fractions: [0.3, 0.7]),
        ], fractions: [0.5, 0.5])
        let rects = Geometry.zoneRects(node, in: CGRect(x: 0, y: 0, width: 1000, height: 1000), gap: 0)
        #expect(Geometry.span(from: 0, to: 2, in: rects) == [0, 1, 2, 3])
        #expect(Geometry.span(from: 2, to: 3, in: rects) == [2, 3])
    }

    @Test func unionCoversTheGapBetweenZones() {
        let rects = Geometry.zoneRects(Presets.thirds.root, in: ultrawide, gap: 8)
        #expect(Geometry.union(of: [0, 1], in: rects) == CGRect(x: 8, y: 39, width: 2280, height: 1311))
        #expect(Geometry.union(of: [1], in: rects) == rects[1])
        #expect(Geometry.union(of: [], in: rects) == nil)
    }
}
