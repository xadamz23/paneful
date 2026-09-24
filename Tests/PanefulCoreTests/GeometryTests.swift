import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct GeometryTests {
    /// The ultrawide's usable area in Accessibility coordinates: below a 31 pt menu bar, above an 82 pt Dock.
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)

    @Test func halvesWithoutGapSplitFrameInTwo() {
        let rects = Geometry.zoneRects(Presets.halves.root, in: ultrawide, gap: 0)
        #expect(rects[0] == CGRect(x: 0, y: 31, width: 1720, height: 1327))
        #expect(rects[1] == CGRect(x: 1720, y: 31, width: 1720, height: 1327))
    }

    @Test func halvesWithGapInsetEdgesAndSeparateZones() {
        let rects = Geometry.zoneRects(Presets.halves.root, in: ultrawide, gap: 8)
        #expect(rects[0] == CGRect(x: 8, y: 39, width: 1708, height: 1311))
        #expect(rects[1] == CGRect(x: 1724, y: 39, width: 1708, height: 1311))
    }

    @Test func thirdsWithGap() {
        let rects = Geometry.zoneRects(Presets.thirds.root, in: ultrawide, gap: 8)
        #expect(rects[0] == CGRect(x: 8, y: 39, width: 1136, height: 1311))
        #expect(rects[1] == CGRect(x: 1152, y: 39, width: 1136, height: 1311))
        #expect(rects[2] == CGRect(x: 2296, y: 39, width: 1136, height: 1311))
    }

    @Test func thirdsTileExactlyWithoutDrift() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let rects = Geometry.zoneRects(Presets.thirds.root, in: frame, gap: 0)
        #expect(rects[0]!.minX == 0)
        #expect(rects[0]!.maxX == rects[1]!.minX)
        #expect(rects[1]!.maxX == rects[2]!.minX)
        #expect(rects[2]!.maxX == 1000)
        #expect([rects[0]!.width, rects[1]!.width, rects[2]!.width] == [333, 334, 333])
    }

    @Test func grid2x2OnLeftDisplay() {
        // Left PA248QV in Accessibility coordinates.
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1200)
        let rects = Geometry.zoneRects(Presets.grid2x2.root, in: left, gap: 10)
        #expect(rects[0] == CGRect(x: -1910, y: 10, width: 945, height: 585))
        #expect(rects[1] == CGRect(x: -1910, y: 605, width: 945, height: 585))
        #expect(rects[2] == CGRect(x: -955, y: 10, width: 945, height: 585))
        #expect(rects[3] == CGRect(x: -955, y: 605, width: 945, height: 585))
    }

    @Test func pointInsideZone() {
        let rects = Geometry.zoneRects(Presets.halves.root, in: ultrawide, gap: 8)
        #expect(Geometry.zone(at: CGPoint(x: 1000, y: 500), in: rects, gap: 8) == 0)
        #expect(Geometry.zone(at: CGPoint(x: 3000, y: 500), in: rects, gap: 8) == 1)
    }

    @Test func pointInGapPicksNearerZone() {
        // Zone 0 ends at x = 1716 and zone 1 starts at x = 1724, so the gap's midpoint is 1720.
        let rects = Geometry.zoneRects(Presets.halves.root, in: ultrawide, gap: 8)
        #expect(Geometry.zone(at: CGPoint(x: 1719, y: 500), in: rects, gap: 8) == 0)
        #expect(Geometry.zone(at: CGPoint(x: 1720, y: 500), in: rects, gap: 8) == 1)
        // Outer gap: within half a gap of zone 0's left edge (x = 8) counts, further out does not.
        #expect(Geometry.zone(at: CGPoint(x: 4, y: 500), in: rects, gap: 8) == 0)
        #expect(Geometry.zone(at: CGPoint(x: 3, y: 500), in: rects, gap: 8) == nil)
    }
}
