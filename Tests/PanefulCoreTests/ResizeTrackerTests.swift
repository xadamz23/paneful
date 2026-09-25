import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct ResizeTrackerTests {
    /// Bottom-left zone of 2 × 2 on a PA248QV with a 4 pt gap.
    let start = CGRect(x: -1916, y: 602, width: 954, height: 594)

    @Test func noChangeMovesNothing() {
        var tracker = ResizeTracker(start: start)
        #expect(tracker.moves(to: start).isEmpty)
    }

    @Test func rightEdgeDrag() {
        var tracker = ResizeTracker(start: start)
        #expect(tracker.moves(to: CGRect(x: -1916, y: 602, width: 1000, height: 594)) == [EdgeMove(edge: .right, position: -916)])
    }

    @Test func leftEdgeDragIgnoresTornReadsOfTheRightEdge() {
        // Dragging the left edge; position and size are read separately, so the right edge appears to wobble.
        var tracker = ResizeTracker(start: start)
        #expect(tracker.moves(to: CGRect(x: -1856, y: 602, width: 894, height: 594)) == [EdgeMove(edge: .left, position: -1856)])
        #expect(tracker.moves(to: CGRect(x: -1856, y: 602, width: 875, height: 594)) == [EdgeMove(edge: .left, position: -1856)])
        #expect(tracker.moves(to: CGRect(x: -1662, y: 602, width: 700, height: 594)) == [EdgeMove(edge: .left, position: -1662)])
    }

    @Test func untouchedEdgeIsNeverFollowed() {
        // A Terminal-like window sits short of its zone; only its right edge is dragged.
        var tracker = ResizeTracker(start: CGRect(x: -1916, y: 602, width: 954, height: 584))
        #expect(tracker.moves(to: CGRect(x: -1916, y: 602, width: 1100, height: 584)) == [EdgeMove(edge: .right, position: -816)])
    }

    @Test func cornerDragFollowsOneEdgePerAxis() {
        var tracker = ResizeTracker(start: start)
        #expect(tracker.moves(to: CGRect(x: -1916, y: 602, width: 1000, height: 500)) == [
            EdgeMove(edge: .right, position: -916),
            EdgeMove(edge: .bottom, position: 1102),
        ])
    }

    @Test func axisLocksLazily() {
        // Starts as a pure right-edge drag, then the user also pulls the top edge.
        var tracker = ResizeTracker(start: start)
        _ = tracker.moves(to: CGRect(x: -1916, y: 602, width: 1000, height: 594))
        #expect(tracker.moves(to: CGRect(x: -1916, y: 560, width: 1010, height: 636)) == [
            EdgeMove(edge: .right, position: -906),
            EdgeMove(edge: .top, position: 560),
        ])
    }

    @Test func slowDragTracksEveryPoint() {
        // 1 pt per event must never be lost: the divider ends exactly under the window's edge.
        let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)
        var arrangement = Arrangement<String>(saved: Presets.halves)
        let zone = arrangement.rects(in: ultrawide, gap: 8)[0]!
        var tracker = ResizeTracker(start: zone)
        var frame = zone
        for _ in 0..<50 {
            frame.size.width += 1
            for move in tracker.moves(to: frame) {
                arrangement.moveEdge(move.edge, of: 0, to: move.position, in: ultrawide, gap: 8, minSize: 100)
            }
        }
        #expect(arrangement.rects(in: ultrawide, gap: 8)[0]!.maxX == frame.maxX)
    }
}
