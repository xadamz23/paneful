import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct DividerTests {
    /// The ultrawide's usable area in Accessibility coordinates.
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)
    let gap: CGFloat = 8
    let minSize: CGFloat = 100

    private func rects(_ node: Node) -> [ZoneID: CGRect] {
        Geometry.zoneRects(node, in: ultrawide, gap: gap)
    }

    private func move(_ node: Node, _ edge: Edge, of zone: ZoneID, to position: CGFloat) -> Node? {
        node.movingEdge(edge, of: zone, to: position, in: ultrawide, gap: gap, minSize: minSize)
    }

    @Test func rightEdgeMovesSharedDivider() throws {
        let after = rects(try #require(move(Presets.halves.root, .right, of: 0, to: 2000)))
        #expect(after[0]!.maxX == 2000)
        #expect(after[1]!.minX == 2008)
        #expect(after[1]!.maxX == 3432)
    }

    @Test func leftEdgeOfNeighbourMovesSameDivider() throws {
        let after = rects(try #require(move(Presets.halves.root, .left, of: 1, to: 2008)))
        #expect(after[0]!.maxX == 2000)
        #expect(after[1]!.minX == 2008)
    }

    @Test func outerEdgeHasNoDivider() {
        #expect(move(Presets.halves.root, .left, of: 0, to: 100) == nil)
        #expect(move(Presets.halves.root, .top, of: 0, to: 100) == nil)
        #expect(move(Presets.halves.root, .right, of: 1, to: 3000) == nil)
    }

    @Test func clampsToMinimumZoneSize() throws {
        let narrow = rects(try #require(move(Presets.halves.root, .right, of: 0, to: 50)))
        #expect(narrow[0]!.width == 100)
        let wide = rects(try #require(move(Presets.halves.root, .right, of: 0, to: 3430)))
        #expect(wide[1]!.width == 100)
    }

    @Test func thirdsMoveOnlyTheDividerOnThatEdge() throws {
        let before = rects(Presets.thirds.root)
        let after = rects(try #require(move(Presets.thirds.root, .right, of: 1, to: 2400)))
        #expect(after[0] == before[0])
        #expect(after[1]!.maxX == 2400)
        #expect(after[2]!.minX == 2408)
        #expect(after[2]!.maxX == 3432)
    }

    @Test func grid2x2BottomEdgeMovesOnlyItsColumn() throws {
        let before = rects(Presets.grid2x2.root)
        let after = rects(try #require(move(Presets.grid2x2.root, .bottom, of: 0, to: 400)))
        #expect(after[0]!.maxY == 400)
        #expect(after[1]!.minY == 408)
        #expect(after[2] == before[2])
        #expect(after[3] == before[3])
    }

    @Test func grid2x2RightEdgeMovesTheColumnDivider() throws {
        let after = rects(try #require(move(Presets.grid2x2.root, .right, of: 1, to: 1500)))
        #expect(after[0]!.maxX == 1500)
        #expect(after[1]!.maxX == 1500)
        #expect(after[2]!.minX == 1508)
        #expect(after[3]!.minX == 1508)
    }

    @Test func nearestDividerWins() throws {
        // 1 + 2: zone 1's bottom edge sits on the nested divider, its left edge on the root one.
        let original = rects(Presets.onePlusTwo.root)
        let bottom = rects(try #require(move(Presets.onePlusTwo.root, .bottom, of: 1, to: 500)))
        #expect(bottom[1]!.maxY == 500)
        #expect(bottom[2]!.minY == 508)
        #expect(bottom[0] == original[0])
        let left = rects(try #require(move(Presets.onePlusTwo.root, .left, of: 1, to: 1808)))
        #expect(left[0]!.maxX == 1800)
        #expect(left[1]!.minX == 1808)
        #expect(left[2]!.minX == 1808)
    }

    @Test func nestedSplitsKeepEveryZoneAboveMinimum() throws {
        let nested = Node.split(.vertical, children: [
            .zone(0),
            .split(.vertical, children: [.zone(1), .zone(2)], fractions: [0.5, 0.5]),
        ], fractions: [0.5, 0.5])
        let after = rects(try #require(move(nested, .right, of: 0, to: 3430)))
        #expect(after[1]!.width >= 100)
        #expect(after[2]!.width >= 100)
    }

    @Test func noRoomLeavesLayoutAlone() {
        let tiny = CGRect(x: 0, y: 0, width: 150, height: 150)
        #expect(Presets.halves.root.movingEdge(.right, of: 0, to: 70, in: tiny, gap: 8, minSize: 100) == nil)
    }

    @Test func movedTreeStaysValid() throws {
        #expect(try #require(move(Presets.thirds.root, .right, of: 0, to: 900)).isValid)
    }
}
