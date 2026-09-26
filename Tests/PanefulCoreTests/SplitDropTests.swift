import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct SplitDropTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func halves() -> Arrangement<String> { Arrangement(saved: Presets.halves) }

    @Test func droppingOnTheTopHalfKeepsTheZoneAsTheTop() {
        var arrangement = halves()
        #expect(arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100) == 1)
        let rects = arrangement.rects(in: screen, gap: 0)
        #expect(rects[1] == CGRect(x: 500, y: 0, width: 500, height: 400))
        #expect(rects[2] == CGRect(x: 500, y: 400, width: 500, height: 400))
        #expect(arrangement.zones(of: "x") == [1])
    }

    @Test func droppingOnTheBottomHalfLandsInTheNewZone() {
        var arrangement = halves()
        #expect(arrangement.split(1, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100) == 2)
        #expect(arrangement.zones(of: "x") == [2])
    }

    @Test func halvesAreEqualWithAGap() {
        var arrangement = halves()
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 8, minSize: 100)
        let rects = arrangement.rects(in: screen, gap: 8)
        #expect(rects[1]!.height == rects[2]!.height)
        #expect(rects[2]!.minY - rects[1]!.maxY == 8)
    }

    @Test func occupantMovesToTheOtherHalf() {
        var top = halves()
        top.assign("w", to: 1)
        top.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(top.zones(of: "w") == [2])

        var bottom = halves()
        bottom.assign("w", to: 1)
        bottom.split(1, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100)
        #expect(bottom.zones(of: "w") == [1])
    }

    @Test func stackedOccupantsAllMove() {
        var arrangement = halves()
        arrangement.assign("v", to: 1)
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.zones(of: "v") == [2])
        #expect(arrangement.zones(of: "w") == [2])
    }

    @Test func spanOverTheZoneGetsBothHalves() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.assign("s", to: [0, 1])
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.zones(of: "s") == [0, 1, 3])
    }

    @Test func draggedWindowLeavesItsOldZone() {
        var arrangement = halves()
        arrangement.assign("x", to: 0)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.zones(of: "x") == [1])
        #expect(arrangement.windows(in: 0).isEmpty)
    }

    @Test func redroppingTheOccupantIntoItsOwnZone() {
        var arrangement = halves()
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "w", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.zones(of: "w") == [1])
        #expect(arrangement.windows(in: 2).isEmpty)
        #expect(arrangement.working.zoneIDs.contains(2))
    }

    @Test func splittingInsideAStackFlattensIntoIt() {
        var arrangement = Arrangement<String>(saved: Presets.onePlusTwo)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.working == .split(.vertical, children: [
            .zone(0),
            .split(.horizontal, children: [.zone(1), .zone(3), .zone(2)], fractions: [0.25, 0.25, 0.5]),
        ], fractions: [0.6, 0.4]))
    }

    @Test func aHalfCanBeSplitAgain() {
        var arrangement = halves()
        arrangement.split(1, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.split(2, dropping: "y", intoTop: false, in: screen, gap: 0, minSize: 100) == 3)
        let rects = arrangement.rects(in: screen, gap: 0)
        #expect(rects[2]!.height == 200)
        #expect(rects[3]!.height == 200)
        #expect(arrangement.zones(of: "x") == [2])
    }

    @Test func refusesZonesTooSmallToSplit() {
        var arrangement = halves()
        arrangement.assign("w", to: 1)
        let short = CGRect(x: 0, y: 0, width: 1000, height: 150)
        #expect(arrangement.split(1, dropping: "x", intoTop: true, in: short, gap: 0, minSize: 100) == nil)
        #expect(arrangement.working == Presets.halves.root)
        #expect(arrangement.zones(of: "x") == nil)
        #expect(arrangement.zones(of: "w") == [1])
    }

    @Test func collapsesOnlyOnceBothHalvesAreEmpty() {
        var arrangement = halves()
        arrangement.assign("a", to: 0)
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        arrangement.remove("x")
        #expect(arrangement.working.zoneIDs.contains(2))
        arrangement.remove("w")
        #expect(arrangement.working == Presets.halves.root)
    }

    @Test func movingWindowsOutWithAssignCollapses() {
        var arrangement = halves()
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        arrangement.assign("x", to: 0)
        #expect(arrangement.working.zoneIDs.contains(2))
        arrangement.assign("w", to: 0)
        #expect(arrangement.working == Presets.halves.root)
    }

    @Test func aChainOfHalvesCollapsesFully() {
        var arrangement = halves()
        arrangement.assign("a", to: 0)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        arrangement.split(1, dropping: "y", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.zones(of: "x") == [3])
        arrangement.remove("y")
        #expect(arrangement.working.zoneIDs == [0, 1, 3, 2])
        arrangement.remove("x")
        #expect(arrangement.working == Presets.halves.root)
    }

    @Test func splittingElsewhereCollapsesTheWindowsOldSplit() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.split(0, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.split(2, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100) == 4)
        #expect(arrangement.working.zoneIDs == [0, 1, 2, 4])
        #expect(arrangement.zones(of: "x") == [4])
    }

    @Test func zoneIDsAreNeverReused() {
        var arrangement = halves()
        arrangement.assign("a", to: 0)
        arrangement.split(1, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100)
        arrangement.remove("x")
        #expect(arrangement.working == Presets.halves.root)
        #expect(arrangement.split(1, dropping: "y", intoTop: false, in: screen, gap: 0, minSize: 100) == 3)
    }

    @Test func rebasedUntilesWindowsInSplitZones() {
        var arrangement = halves()
        arrangement.assign("a", to: 0)
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        let rebased = arrangement.rebased(on: Presets.thirds)
        #expect(rebased.zones(of: "a") == [0])
        #expect(rebased.zones(of: "x") == [1])
        #expect(rebased.zones(of: "w") == nil)
    }

    @Test func resetUntilesWindowsInSplitZones() {
        var arrangement = halves()
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        arrangement.reset()
        #expect(arrangement.working == Presets.halves.root)
        #expect(arrangement.zones(of: "x") == [1])
        #expect(arrangement.zones(of: "w") == nil)
    }
}
