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
        #expect(arrangement.zones(of: "safari") == [1])
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
        #expect(arrangement.zones(of: "a") == nil)
    }

    @Test func removeUntilesWindow() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("a", to: 0)
        arrangement.remove("a")
        #expect(arrangement.zones(of: "a") == nil)
        #expect(arrangement.tiledWindows.isEmpty)
    }

    @Test func resetRestoresSavedTreeAndKeepsWindows() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("a", to: 1)
        arrangement.reset()
        #expect(arrangement.working == Presets.halves.root)
        #expect(arrangement.zones(of: "a") == [1])
    }

    @Test func rebasedKeepsWindowsWhoseZonesStillExist() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.assign("left", to: 0)
        arrangement.assign("right", to: 2)
        let rebased = arrangement.rebased(on: Presets.halves)
        #expect(rebased.saved == Presets.halves)
        #expect(rebased.working == Presets.halves.root)
        #expect(rebased.zones(of: "left") == [0])
        #expect(rebased.zones(of: "right") == nil)
    }

    @Test func rectsComeFromWorkingTree() {
        let arrangement = Arrangement<String>(saved: Presets.grid2x2)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(arrangement.rects(in: frame, gap: 8) == Geometry.zoneRects(Presets.grid2x2.root, in: frame, gap: 8))
    }

    @Test func moveEdgeChangesWorkingButNeverSaved() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        let frame = CGRect(x: 0, y: 31, width: 3440, height: 1327)
        let moved = arrangement.moveEdge(.right, of: [0], to: 2000, in: frame, gap: 8, minSize: 100)
        #expect(moved)
        #expect(arrangement.rects(in: frame, gap: 8)[0]!.maxX == 2000)
        #expect(arrangement.saved == Presets.halves)
        arrangement.reset()
        #expect(arrangement.working == Presets.halves.root)
    }

    @Test func moveOuterEdgeChangesNothing() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        let frame = CGRect(x: 0, y: 31, width: 3440, height: 1327)
        let moved = arrangement.moveEdge(.left, of: [0], to: 300, in: frame, gap: 8, minSize: 100)
        #expect(!moved)
        #expect(arrangement.working == Presets.halves.root)
    }

    // MARK: Linked resizing

    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)

    @Test func fitGrowsRightZoneTowardItsDividerWhenItOverflowsTheScreenEdge() {
        // Zone 1 was squeezed to 600 wide, but its window refuses to be narrower than 900.
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.moveEdge(.left, of: [1], to: 2832, in: ultrawide, gap: 8, minSize: 100)
        let moved = arrangement.fit([1], toAtLeast: CGSize(width: 900, height: 100), in: ultrawide, gap: 8, minSize: 100)
        #expect(moved)
        let rect = arrangement.rects(in: ultrawide, gap: 8)[1]!
        #expect(rect.width == 900)
        #expect(rect.maxX == 3432)
    }

    @Test func fitGrowsLeftZoneTowardItsDivider() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.moveEdge(.right, of: [0], to: 608, in: ultrawide, gap: 8, minSize: 100)
        let moved = arrangement.fit([0], toAtLeast: CGSize(width: 900, height: 100), in: ultrawide, gap: 8, minSize: 100)
        #expect(moved)
        let rect = arrangement.rects(in: ultrawide, gap: 8)[0]!
        #expect(rect.minX == 8)
        #expect(rect.width == 900)
    }

    @Test func fitLeavesZonesThatAlreadyHoldTheWindow() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        let moved = arrangement.fit([0], toAtLeast: CGSize(width: 1600, height: 1300), in: ultrawide, gap: 8, minSize: 100)
        #expect(!moved)
        #expect(arrangement.working == Presets.halves.root)
    }

    // MARK: Spans

    /// Thirds at gap 0 on 900 × 500: zones 0, 1, 2 are 300 wide.
    let narrow = CGRect(x: 0, y: 0, width: 900, height: 500)
    /// 2 × 2 at gap 0: TL = 0, BL = 1, TR = 2, BR = 3, each 500 × 400.
    let square = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func spanSitsInEachOfItsZones() {
        var arrangement = Arrangement<String>(saved: Presets.grid2x2)
        arrangement.assign("w", to: [0, 2])
        #expect(arrangement.zones(of: "w") == [0, 2])
        #expect(arrangement.windows(in: 0) == ["w"])
        #expect(arrangement.windows(in: 2) == ["w"])
        #expect(arrangement.windows(in: 1).isEmpty)
    }

    @Test func spanWithAnUnknownZoneIsIgnored() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("w", to: [0, 7])
        #expect(arrangement.zones(of: "w") == nil)
        arrangement.assign("w", to: [])
        #expect(arrangement.zones(of: "w") == nil)
    }

    @Test func rebasedDropsSpanWhoseZoneWasRemoved() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.assign("kept", to: [0, 1])
        arrangement.assign("broken", to: [1, 2])
        let rebased = arrangement.rebased(on: Presets.halves)
        #expect(rebased.zones(of: "kept") == [0, 1])
        #expect(rebased.zones(of: "broken") == nil)
    }

    @Test func spanBottomEdgeMovesBothRowDividers() {
        var arrangement = Arrangement<String>(saved: Presets.grid2x2)
        let moved = arrangement.moveEdge(.bottom, of: [0, 2], to: 600, in: square, gap: 0, minSize: 100)
        #expect(moved)
        let rects = arrangement.rects(in: square, gap: 0)
        #expect(rects[0]!.maxY == 600)
        #expect(rects[2]!.maxY == 600)
        #expect(rects[1]!.minY == 600)
        #expect(rects[3]!.minY == 600)
    }

    @Test func spanRightEdgeMovesOnlyTheOuterDivider() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        let moved = arrangement.moveEdge(.right, of: [0, 1], to: 700, in: narrow, gap: 0, minSize: 100)
        #expect(moved)
        let rects = arrangement.rects(in: narrow, gap: 0)
        #expect(rects[0] == CGRect(x: 0, y: 0, width: 300, height: 500))
        #expect(rects[1]!.maxX == 700)
        #expect(rects[2]!.minX == 700)
    }

    @Test func spanOuterEdgeAgainstTheScreenMovesNothing() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        let moved = arrangement.moveEdge(.left, of: [0, 1], to: 50, in: narrow, gap: 0, minSize: 100)
        #expect(!moved)
        #expect(arrangement.working == Presets.thirds.root)
    }

    @Test func internalDividerLeavesSpanAlone() {
        // A window stacked in zone 0 alone resizes its right edge, which is inside the [0, 1] span.
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.moveEdge(.right, of: [0], to: 400, in: narrow, gap: 0, minSize: 100)
        let rects = arrangement.rects(in: narrow, gap: 0)
        #expect(rects[0]!.maxX == 400)
        #expect(Geometry.union(of: [0, 1], in: rects) == CGRect(x: 0, y: 0, width: 600, height: 500))
    }

    @Test func spanEdgeMovesAreClampedAndStayValid() {
        var arrangement = Arrangement<String>(saved: Presets.grid2x2)
        arrangement.moveEdge(.bottom, of: [0, 2], to: 780, in: square, gap: 0, minSize: 100)
        let rects = arrangement.rects(in: square, gap: 0)
        #expect(rects[1]!.height == 100)
        #expect(rects[3]!.height == 100)
        #expect(arrangement.working.isValid)
    }

    @Test func neighbourResizeKeepsTheSpanStraight() {
        // BR's top edge is the right half of the span's bottom edge, so both row dividers move.
        var arrangement = Arrangement<String>(saved: Presets.grid2x2)
        arrangement.assign("span", to: [0, 2])
        arrangement.assign("br", to: 3)
        arrangement.moveEdge(.top, of: [3], to: 500, in: square, gap: 0, minSize: 100)
        let rects = arrangement.rects(in: square, gap: 0)
        #expect(rects[0]!.maxY == 500)
        #expect(rects[2]!.maxY == 500)
        #expect(rects[1]!.minY == 500)
    }

    @Test func stackedWindowMovingTheSpansOuterEdgeMovesAllOfIt() {
        var arrangement = Arrangement<String>(saved: Presets.grid2x2)
        arrangement.assign("span", to: [0, 2])
        arrangement.assign("tl", to: 0)
        arrangement.moveEdge(.bottom, of: [0], to: 500, in: square, gap: 0, minSize: 100)
        let rects = arrangement.rects(in: square, gap: 0)
        #expect(rects[0]!.maxY == 500)
        #expect(rects[2]!.maxY == 500)
    }

    @Test func unevenClampKeepsTheSpanStraight() {
        // The right column has two zones below TR, so its divider clamps at 500 while the left one could reach 700.
        let layout = Layout(name: "Custom", root: .split(.vertical, children: [
            .split(.horizontal, children: [.zone(0), .zone(1)], fractions: [0.5, 0.5]),
            .split(.horizontal, children: [.zone(2), .zone(3), .zone(4)], fractions: [0.5, 0.25, 0.25]),
        ], fractions: [0.5, 0.5]))
        var arrangement = Arrangement<String>(saved: layout)
        arrangement.moveEdge(.bottom, of: [0, 2], to: 750, in: square, gap: 0, minSize: 100)
        let rects = arrangement.rects(in: square, gap: 0)
        #expect(rects[0]!.maxY == 500)
        #expect(rects[2]!.maxY == 500)
        #expect(arrangement.working.isValid)
    }

    @Test func fitGrowsASpanTowardItsDivider() {
        // Span [1, 2] is 600 wide against the screen's right edge; its window refuses to be narrower than 700.
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        let moved = arrangement.fit([1, 2], toAtLeast: CGSize(width: 700, height: 100), in: narrow, gap: 0, minSize: 100)
        #expect(moved)
        let rects = arrangement.rects(in: narrow, gap: 0)
        #expect(Geometry.union(of: [1, 2], in: rects) == CGRect(x: 200, y: 0, width: 700, height: 500))
        #expect(rects[0]!.width == 200)
    }
}
