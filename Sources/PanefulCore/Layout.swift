public typealias ZoneID = Int

/// How a split lays out its children.
/// `.vertical`: vertical dividers, children left to right.
/// `.horizontal`: horizontal dividers, children top to bottom.
public enum Axis: String, Codable, Sendable {
    case horizontal, vertical
}

public indirect enum Node: Codable, Equatable, Sendable {
    case zone(ZoneID)
    case split(Axis, children: [Node], fractions: [Double])

    /// Zone IDs in depth-first order.
    public var zoneIDs: [ZoneID] {
        switch self {
        case .zone(let id): return [id]
        case .split(_, let children, _): return children.flatMap(\.zoneIDs)
        }
    }

    /// Every split has at least two children with matching positive fractions summing to 1, and zone IDs are unique.
    public var isValid: Bool {
        Set(zoneIDs).count == zoneIDs.count && structureIsValid
    }

    private var structureIsValid: Bool {
        switch self {
        case .zone:
            return true
        case .split(_, let children, let fractions):
            return children.count >= 2
                && fractions.count == children.count
                && fractions.allSatisfy { $0 > 0 }
                && abs(fractions.reduce(0, +) - 1) < 1e-6
                && children.allSatisfy(\.structureIsValid)
        }
    }
}

public struct Layout: Codable, Equatable, Sendable {
    public var name: String
    public var root: Node

    public init(name: String, root: Node) {
        self.name = name
        self.root = root
    }
}
