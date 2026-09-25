import AppKit
import PanefulCore

/// State behind the Edit Layouts window: which display is being edited, its draft layout and the draft gap.
/// Nothing reaches the screen until `save()`.
final class EditorModel: ObservableObject {
    private let tiling: TilingController

    @Published private(set) var displays: [Display] = []
    @Published private(set) var displayID = ""
    @Published var draft = LayoutDraft(original: Presets.halves)
    @Published var gap: Double = 8

    /// The divider being dragged on the canvas, if any. Lives here because `@State` isn't available without Xcode.
    var dragging: (zone: ZoneID, edge: Edge)?

    init(tiling: TilingController) {
        self.tiling = tiling
    }

    var display: Display? { displays.first { $0.id == displayID } }

    var hasChanges: Bool { draft.isDirty || gap != tiling.settings.gap }

    /// Reloads displays and the current display's saved layout, dropping unsaved edits.
    func reload() {
        displays = tiling.displays
        load(display?.id ?? displays.first?.id ?? "")
    }

    /// Switches to another display, first asking what to do with unsaved edits.
    func select(displayID id: String) {
        guard id != displayID, confirmDiscardingChanges() else { return }
        load(id)
    }

    func save() {
        guard let display else { return }
        if gap != tiling.settings.gap { tiling.setGap(gap) }
        if draft.isDirty { tiling.setLayout(draft.layout, for: display) }
        load(displayID)
    }

    func revert() {
        load(displayID)
    }

    /// Whether the current edits may be dropped: there are none, or the user chose Save or Discard.
    func confirmDiscardingChanges() -> Bool {
        guard hasChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to the layout for \(display?.name ?? "this display")?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func load(_ id: String) {
        displayID = id
        draft = LayoutDraft(original: tiling.settings.layout(forDisplay: id))
        gap = tiling.settings.gap
        dragging = nil
    }
}
