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
    var dragging: DividerDrag?
    /// The gap as loaded, so a gap changed from the menu meanwhile doesn't count as an edit here.
    private var loadedGap: Double = 8

    init(tiling: TilingController) {
        self.tiling = tiling
    }

    var display: Display? { displays.first { $0.id == displayID } }

    var hasChanges: Bool { draft.isDirty || gap != loadedGap }

    /// Reloads displays and the current display's saved layout, dropping unsaved edits.
    func reload() {
        displays = tiling.displays
        load(display?.id ?? displays.first?.id ?? "")
    }

    /// Reloads if there are no unsaved edits, picking up changes made from the menu or to the displays.
    func reloadIfUnchanged() {
        if !hasChanges { reload() }
    }

    /// Switches to another display, first asking what to do with unsaved edits.
    func select(displayID id: String) {
        guard id != displayID else { return }
        guard confirmDiscardingChanges() else {
            // The pop-up already shows the display that was picked; redraw it with the one still being edited.
            DispatchQueue.main.async { self.objectWillChange.send() }
            return
        }
        load(id)
    }

    func save() {
        guard let display else { return }
        // Layout first: setLayout untiles windows in removed zones before setGap refits what's still tiled.
        if draft.isDirty { tiling.setLayout(draft.layout, for: display) }
        if gap != loadedGap { tiling.setGap(gap) }
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
        loadedGap = gap
        dragging = nil
    }
}
