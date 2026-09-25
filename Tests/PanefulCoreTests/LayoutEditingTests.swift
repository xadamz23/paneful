import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct LayoutEditingTests {
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)

    private func rects(_ node: Node) -> [ZoneID: CGRect] {
        Geometry.zoneRects(node, in: ultrawide, gap: 8)
    }

    @Test func splitSideBySide() {
        let split = Presets.halves.root.splitting(0, along: .vertical)
        #expect(split.zoneIDs == [0, 2, 1])
        #expect(rects(split)[0] == CGRect(x: 8, y: 39, width: 850, height: 1311))
        #expect(rects(split)[2] == CGRect(x: 866, y: 39, width: 850, height: 1311))
        #expect(rects(split)[1] == rects(Presets.halves.root)[1])
    }

    @Test func splitTopBottom() {
        let split = Presets.halves.root.splitting(1, along: .horizontal)
        #expect(split.zoneIDs == [0, 1, 2])
        #expect(rects(split)[1] == CGRect(x: 1724, y: 39, width: 1708, height: 652))
        #expect(rects(split)[2] == CGRect(x: 1724, y: 699, width: 1708, height: 651))
    }

    @Test func splitSingleZone() {
        #expect(Node.zone(0).splitting(0, along: .vertical) == .split(.vertical, children: [.zone(0), .zone(1)], fractions: [0.5, 0.5]))
    }

    @Test func removeFromPairCollapsesToTheSibling() {
        #expect(Presets.halves.root.removing(1) == .zone(0))
        #expect(Presets.halves.root.removing(0) == .zone(1))
    }

    @Test func removeMiddleGivesItsSpaceToThePreviousZone() throws {
        guard case .split(_, let children, let fractions) = try #require(Presets.thirds.root.removing(1)) else {
            Issue.record("expected a split"); return
        }
        #expect(children == [.zone(0), .zone(2)])
        #expect(abs(fractions[0] - 2.0 / 3) < 1e-9)
        #expect(abs(fractions[1] - 1.0 / 3) < 1e-9)
    }

    @Test func removeFirstGivesItsSpaceToTheNextZone() throws {
        guard case .split(_, let children, let fractions) = try #require(Presets.thirds.root.removing(0)) else {
            Issue.record("expected a split"); return
        }
        #expect(children == [.zone(1), .zone(2)])
        #expect(abs(fractions[0] - 2.0 / 3) < 1e-9)
    }

    @Test func removeNestedCollapsesItsColumn() {
        #expect(Presets.grid2x2.root.removing(1) == .split(.vertical, children: [
            .zone(0),
            .split(.horizontal, children: [.zone(2), .zone(3)], fractions: [0.5, 0.5]),
        ], fractions: [0.5, 0.5]))
    }

    @Test func removeOnlyZoneIsRefused() {
        #expect(Node.zone(0).removing(0) == nil)
    }

    @Test func removeUnknownZoneChangesNothing() {
        #expect(Presets.halves.root.removing(7) == Presets.halves.root)
    }

    @Test func editSequenceStaysValid() throws {
        var node = Presets.halves.root
        node = node.splitting(0, along: .vertical)      // 0 2 | 1
        node = node.splitting(2, along: .horizontal)    // 0 (2/3) | 1
        node = try #require(node.removing(1))
        node = node.splitting(0, along: .horizontal)    // (0/4) (2/3)
        node = try #require(node.removing(3))
        node = node.splitting(4, along: .vertical)
        #expect(node.isValid)
        #expect(Set(node.zoneIDs).count == node.zoneIDs.count)
        #expect(node.zoneIDs.sorted() == [0, 2, 4, 5])
    }

    @Test func handleInTheGapBetweenHalves() {
        // Zone 0 ends at x = 1716 and zone 1 starts at 1724.
        let handle = Presets.halves.root.dividerHandle(at: CGPoint(x: 1720, y: 500), in: ultrawide, gap: 8, tolerance: 2)
        #expect(handle?.zone == 0)
        #expect(handle?.edge == .right)
    }

    @Test func noHandleInsideAZone() {
        #expect(Presets.halves.root.dividerHandle(at: CGPoint(x: 1000, y: 500), in: ultrawide, gap: 8, tolerance: 2) == nil)
    }

    @Test func noHandleOnAnOuterEdge() {
        #expect(Presets.halves.root.dividerHandle(at: CGPoint(x: 3436, y: 500), in: ultrawide, gap: 8, tolerance: 2) == nil)
    }

    @Test func bottomHandleInALeftColumn() {
        // 2 × 2: zone 0 is (8, 39, 1708, 652), so the left column's row gap is y 691...699.
        let handle = Presets.grid2x2.root.dividerHandle(at: CGPoint(x: 500, y: 695), in: ultrawide, gap: 8, tolerance: 2)
        #expect(handle?.zone == 0)
        #expect(handle?.edge == .bottom)
    }

    @Test func toleranceWidensThinGaps() {
        // With no gap, zones 0 and 1 meet at x = 1720; only the tolerance makes that line grabbable.
        #expect(Presets.halves.root.dividerHandle(at: CGPoint(x: 1719, y: 500), in: ultrawide, gap: 0, tolerance: 3)?.zone == 0)
        #expect(Presets.halves.root.dividerHandle(at: CGPoint(x: 1719, y: 500), in: ultrawide, gap: 0, tolerance: 0) == nil)
    }
}
