import CoreGraphics

/// One display's live state: a working copy of the saved layout (which linked resizing will adjust
/// in Phase 2) plus which windows sit in which zone. The saved layout itself is never changed here.
public struct Arrangement<Window: Hashable> {
    public let saved: Layout
    public private(set) var working: Node
    private var zoneOf: [Window: ZoneID] = [:]

    public init(saved: Layout) {
        self.saved = saved
        self.working = saved.root
    }

    public var tiledWindows: [Window] { Array(zoneOf.keys) }

    public func zone(of window: Window) -> ZoneID? { zoneOf[window] }

    public func windows(in zone: ZoneID) -> [Window] {
        zoneOf.filter { $0.value == zone }.map(\.key)
    }

    /// Puts `window` in `zone`, leaving any zone it was in. Ignored if the zone doesn't exist.
    public mutating func assign(_ window: Window, to zone: ZoneID) {
        guard working.zoneIDs.contains(zone) else { return }
        zoneOf[window] = zone
    }

    public mutating func remove(_ window: Window) {
        zoneOf[window] = nil
    }

    /// Restores the saved layout's boundaries; windows keep their zones.
    public mutating func reset() {
        working = saved.root
    }

    /// A fresh arrangement for `saved`, keeping windows whose zones still exist in it.
    public func rebased(on saved: Layout) -> Arrangement {
        var result = Arrangement(saved: saved)
        for (window, zone) in zoneOf { result.assign(window, to: zone) }
        return result
    }

    public func rects(in frame: CGRect, gap: CGFloat) -> [ZoneID: CGRect] {
        Geometry.zoneRects(working, in: frame, gap: gap)
    }
}
