import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct ArrangementTests {
    @Test func startsFromSavedLayoutWithNoWindows() {
        let arrangement = Arrangement<String>(saved: Presets.thirds)
        #expect(arrangement.working == Presets.thirds.root)
        #expect(arrangement.tiledWindows.isEmpty)
    }

    @Test func assignMovesWindowBetweenZones() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("safari", to: 0)
        arrangement.assign("safari", to: 1)
        #expect(arrangement.zone(of: "safari") == 1)
        #expect(arrangement.windows(in: 0).isEmpty)
        #expect(arrangement.windows(in: 1) == ["safari"])
    }

    @Test func zoneHoldsStackedWindows() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("a", to: 0)
        arrangement.assign("b", to: 0)
        #expect(Set(arrangement.windows(in: 0)) == ["a", "b"])
    }

    @Test func ignoresUnknownZone() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("a", to: 7)
        #expect(arrangement.zone(of: "a") == nil)
    }

    @Test func removeUntilesWindow() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("a", to: 0)
        arrangement.remove("a")
        #expect(arrangement.zone(of: "a") == nil)
        #expect(arrangement.tiledWindows.isEmpty)
    }

    @Test func resetRestoresSavedTreeAndKeepsWindows() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("a", to: 1)
        arrangement.reset()
        #expect(arrangement.working == Presets.halves.root)
        #expect(arrangement.zone(of: "a") == 1)
    }

    @Test func rebasedKeepsWindowsWhoseZonesStillExist() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.assign("left", to: 0)
        arrangement.assign("right", to: 2)
        let rebased = arrangement.rebased(on: Presets.halves)
        #expect(rebased.saved == Presets.halves)
        #expect(rebased.working == Presets.halves.root)
        #expect(rebased.zone(of: "left") == 0)
        #expect(rebased.zone(of: "right") == nil)
    }

    @Test func rectsComeFromWorkingTree() {
        let arrangement = Arrangement<String>(saved: Presets.grid2x2)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(arrangement.rects(in: frame, gap: 8) == Geometry.zoneRects(Presets.grid2x2.root, in: frame, gap: 8))
    }

    @Test func moveEdgeChangesWorkingButNeverSaved() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        let frame = CGRect(x: 0, y: 31, width: 3440, height: 1327)
        let moved = arrangement.moveEdge(.right, of: 0, to: 2000, in: frame, gap: 8, minSize: 100)
        #expect(moved)
        #expect(arrangement.rects(in: frame, gap: 8)[0]!.maxX == 2000)
        #expect(arrangement.saved == Presets.halves)
        arrangement.reset()
        #expect(arrangement.working == Presets.halves.root)
    }

    @Test func moveOuterEdgeChangesNothing() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        let frame = CGRect(x: 0, y: 31, width: 3440, height: 1327)
        let moved = arrangement.moveEdge(.left, of: 0, to: 300, in: frame, gap: 8, minSize: 100)
        #expect(!moved)
        #expect(arrangement.working == Presets.halves.root)
    }

    // MARK: Linked resizing

    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)

    @Test func followResizeMovesOnlyTheEdgeThatMovedSinceLastFrame() {
        // A Terminal-like window sits 10 pt short of its zone's bottom (character grid); the user drags only its right edge.
        var arrangement = Arrangement<String>(saved: Presets.grid2x2)
        let zone = arrangement.rects(in: ultrawide, gap: 8)[0]!
        let before = CGRect(x: zone.minX, y: zone.minY, width: zone.width, height: zone.height - 10)
        let after = CGRect(x: zone.minX, y: zone.minY, width: zone.width + 200, height: zone.height - 10)
        let linked = arrangement.followResize(of: 0, from: before, to: after, in: ultrawide, gap: 8, minSize: 100)
        #expect(linked)
        let rects = arrangement.rects(in: ultrawide, gap: 8)
        #expect(rects[0]!.maxX == after.maxX)
        #expect(rects[0]!.maxY == zone.maxY)   // row divider untouched
    }

    @Test func followResizeOfOuterEdgeLinksNothing() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        let zone = arrangement.rects(in: ultrawide, gap: 8)[0]!
        let after = CGRect(x: zone.minX + 50, y: zone.minY, width: zone.width - 50, height: zone.height)
        let linked = arrangement.followResize(of: 0, from: zone, to: after, in: ultrawide, gap: 8, minSize: 100)
        #expect(!linked)
        #expect(arrangement.working == Presets.halves.root)
    }

    @Test func fitGrowsRightZoneTowardItsDividerWhenItOverflowsTheScreenEdge() {
        // Zone 1 was squeezed to 600 wide, but its window refuses to be narrower than 900.
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.moveEdge(.left, of: 1, to: 2832, in: ultrawide, gap: 8, minSize: 100)
        let moved = arrangement.fit(1, toAtLeast: CGSize(width: 900, height: 100), in: ultrawide, gap: 8, minSize: 100)
        #expect(moved)
        let rect = arrangement.rects(in: ultrawide, gap: 8)[1]!
        #expect(rect.width == 900)
        #expect(rect.maxX == 3432)
    }

    @Test func fitGrowsLeftZoneTowardItsDivider() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.moveEdge(.right, of: 0, to: 608, in: ultrawide, gap: 8, minSize: 100)
        let moved = arrangement.fit(0, toAtLeast: CGSize(width: 900, height: 100), in: ultrawide, gap: 8, minSize: 100)
        #expect(moved)
        let rect = arrangement.rects(in: ultrawide, gap: 8)[0]!
        #expect(rect.minX == 8)
        #expect(rect.width == 900)
    }

    @Test func fitLeavesZonesThatAlreadyHoldTheWindow() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        let moved = arrangement.fit(0, toAtLeast: CGSize(width: 1600, height: 1300), in: ultrawide, gap: 8, minSize: 100)
        #expect(!moved)
        #expect(arrangement.working == Presets.halves.root)
    }
}
