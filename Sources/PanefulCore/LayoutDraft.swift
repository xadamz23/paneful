import CoreGraphics

/// The editor's working copy of one display's layout. Edits other than applying a preset rename it "Custom".
public struct LayoutDraft: Sendable {
    public static let customName = "Custom"

    public let original: Layout
    public private(set) var layout: Layout
    public var selected: ZoneID?
    /// IDs only ever go up, so a removed zone's ID (which Save uses to match windows) is never handed out again.
    private var nextZoneID: ZoneID

    public init(original: Layout) {
        self.original = original
        self.layout = original
        nextZoneID = (original.root.zoneIDs.max() ?? -1) + 1
    }

    public var isDirty: Bool { layout != original }

    /// A zone is selected and it isn't the last one.
    public var canRemove: Bool { selected != nil && layout.root.zoneIDs.count > 1 }

    public mutating func apply(_ preset: Layout) {
        layout = preset
        selected = nil
        nextZoneID = max(nextZoneID, (preset.root.zoneIDs.max() ?? -1) + 1)
    }

    public mutating func splitSelected(along axis: Axis) {
        guard let selected else { return }
        edit(layout.root.splitting(selected, along: axis, newZone: nextZoneID))
        nextZoneID += 1
    }

    public mutating func removeSelected() {
        guard let selected, let root = layout.root.removing(selected) else { return }
        edit(root)
        self.selected = nil
    }

    public mutating func moveDivider(_ edge: Edge, of zone: ZoneID, to position: CGFloat, in frame: CGRect, gap: CGFloat, minSize: CGFloat) {
        guard let root = layout.root.movingEdge(edge, of: zone, to: position, in: frame, gap: gap, minSize: minSize) else { return }
        edit(root)
    }

    public mutating func revert() {
        layout = original
        selected = nil
        nextZoneID = (original.root.zoneIDs.max() ?? -1) + 1
    }

    private mutating func edit(_ root: Node) {
        layout = Layout(name: Self.customName, root: root)
    }
}
