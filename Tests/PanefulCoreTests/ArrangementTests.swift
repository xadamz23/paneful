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
}
