import CoreGraphics

/// Follows a user's resize of a window and reports only the edges they are dragging: at most one per axis,
/// chosen the first time that axis changes and kept for the rest of the drag.
///
/// A window's position and size are read separately, so during a live resize the two can come from slightly
/// different moments, making the edge opposite the dragged one appear to wobble. A trailing-edge drag never
/// changes the window's origin, so an origin change means the leading edge is being dragged.
public struct ResizeTracker: Sendable {
    public let start: CGRect
    private var horizontal: Edge?
    private var vertical: Edge?

    public init(start: CGRect) {
        self.start = start
    }

    /// Records `frame` and returns where the dragged edges now are, in `Edge.allCases` order.
    public mutating func moves(to frame: CGRect) -> [EdgeMove] {
        horizontal = horizontal ?? draggedEdge(leading: .left, trailing: .right, in: frame)
        vertical = vertical ?? draggedEdge(leading: .top, trailing: .bottom, in: frame)
        return [horizontal, vertical].compactMap { $0 }.map { EdgeMove(edge: $0, position: $0.coordinate(of: frame)) }
    }

    private func draggedEdge(leading: Edge, trailing: Edge, in frame: CGRect) -> Edge? {
        if abs(leading.coordinate(of: frame) - leading.coordinate(of: start)) > 0.5 { return leading }
        if abs(trailing.coordinate(of: frame) - trailing.coordinate(of: start)) > 0.5 { return trailing }
        return nil
    }
}
