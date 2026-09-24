import CoreGraphics

public enum Edge: CaseIterable, Sendable {
    case left, right, top, bottom

    /// The split axis whose dividers this edge can sit on.
    var axis: Axis {
        switch self {
        case .left, .right: return .vertical
        case .top, .bottom: return .horizontal
        }
    }

    /// Right and bottom edges face the next sibling in a split; left and top face the previous one.
    var isTrailing: Bool { self == .right || self == .bottom }

    public func coordinate(of rect: CGRect) -> CGFloat {
        switch self {
        case .left: return rect.minX
        case .right: return rect.maxX
        case .top: return rect.minY
        case .bottom: return rect.maxY
        }
    }
}

/// An edge of a window and where it now is.
public struct EdgeMove: Equatable, Sendable {
    public let edge: Edge
    public let position: CGFloat

    public init(edge: Edge, position: CGFloat) {
        self.edge = edge
        self.position = position
    }
}

extension Geometry {
    /// Edges of `frame` that differ from `rect` by more than `tolerance`, in `Edge.allCases` order.
    public static func movedEdges(from rect: CGRect, to frame: CGRect, tolerance: CGFloat = 1) -> [EdgeMove] {
        Edge.allCases.compactMap { edge in
            let position = edge.coordinate(of: frame)
            return abs(position - edge.coordinate(of: rect)) > tolerance ? EdgeMove(edge: edge, position: position) : nil
        }
    }

    /// Edges of `frame` that stick out past `rect`, as happens when a window refuses to shrink to its zone.
    public static func overflowingEdges(of frame: CGRect, beyond rect: CGRect, tolerance: CGFloat = 1) -> [EdgeMove] {
        movedEdges(from: rect, to: frame, tolerance: tolerance).filter { move in
            let zoneEdge = move.edge.coordinate(of: rect)
            return move.edge.isTrailing ? move.position > zoneEdge : move.position < zoneEdge
        }
    }
}
