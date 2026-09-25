import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct FillTests {
    /// Thirds at gap 0 on 1200 × 800: A = 0, B = 1, C = 2, with centres at x 200, 600 and 1000, all at y 400.
    let thirds = Geometry.zoneRects(Presets.thirds.root, in: CGRect(x: 0, y: 0, width: 1200, height: 800), gap: 0)

    private func fill(_ empty: [ZoneID: CGRect], _ windows: [(String, CGPoint)]) -> [String: ZoneID] {
        Dictionary(uniqueKeysWithValues: Geometry.fill(empty: empty, windows: windows))
    }

    @Test func eachWindowGoesToTheZoneItIsOver() {
        let windows = [("right", CGPoint(x: 950, y: 400)), ("left", CGPoint(x: 150, y: 400)), ("middle", CGPoint(x: 620, y: 400))]
        #expect(fill(thirds, windows) == ["left": 0, "middle": 1, "right": 2])
    }

    @Test func theClosestPairIsMadeFirst() {
        // Both are over A. "near" is 10 from A's centre, so it gets A; "far" takes the next nearest zone, B.
        let windows = [("far", CGPoint(x: 350, y: 400)), ("near", CGPoint(x: 210, y: 400))]
        #expect(fill(thirds, windows) == ["near": 0, "far": 1])
    }

    @Test func moreWindowsThanZonesLeavesTheRestOut() {
        let empty = thirds.filter { $0.key == 1 }
        let windows = [("a", CGPoint(x: 100, y: 400)), ("b", CGPoint(x: 590, y: 400)), ("c", CGPoint(x: 1100, y: 400))]
        #expect(fill(empty, windows) == ["b": 1])
    }

    @Test func moreZonesThanWindows() {
        #expect(fill(thirds, [("only", CGPoint(x: 1000, y: 400))]) == ["only": 2])
    }

    @Test func nothingToFill() {
        #expect(fill([:], [("a", .zero)]) == [:])
        #expect(fill(thirds, []) == [:])
    }

    @Test func tiesGoToTheLowestZoneThenTheFirstWindow() {
        // Exactly between A's and B's centres.
        #expect(fill(thirds, [("x", CGPoint(x: 400, y: 400))]) == ["x": 0])
        let windows = [("first", CGPoint(x: 600, y: 400)), ("second", CGPoint(x: 600, y: 400))]
        #expect(fill(thirds.filter { $0.key == 1 }, windows) == ["first": 1])
    }
}
