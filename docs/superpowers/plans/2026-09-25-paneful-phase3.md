# Paneful Phase 3 — Visual Layout Editor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Edit Layouts…" window. For each display you can start from a preset, drag dividers, split zones side by side or top/bottom, remove zones, and set the gap. Nothing on screen changes until you click Save.

**Architecture:** The editing operations live in `PanefulCore` and are pure and unit-tested:
- `Node.splitting` and `Node.removing` change a layout tree.
- `Node.dividerHandle(at:)` finds which divider sits under a point.
- `LayoutDraft` is the editor's working copy of a layout: selection, edits, revert, and the "Custom" name.

The app adds three pieces:
- An `EditorModel` (`ObservableObject`), which picks the display, holds the draft and the draft gap, and handles Save, Revert and the unsaved-changes prompt.
- SwiftUI views: `EditorView` for the form and `LayoutCanvas` for drawing zones, clicking to select and dragging dividers.
- An `EditorWindowController`, which hosts the views in an `NSWindow`.

Save goes through the existing `TilingController.setLayout` and `setGap`. **Tech Stack:** Swift 6.4 (Command Line Tools only), SwiftPM, Swift Testing, AppKit and SwiftUI.

**Spec:** `docs/superpowers/specs/2026-09-24-paneful-design.md`, the "UI › Editor (phase 3)" section, plus the details Adam approved in chat on 2026-09-25:
- Click a zone to select it. Splitting makes two equal halves.
- Remove merges the zone into its neighbour, and is disabled when only one zone is left.
- Divider drags stop at 100 pt zones.
- Nothing on screen changes until Save. On Save, that display's windows refit, and windows in removed zones are untiled.
- Revert discards unsaved edits.
- Switching display, or closing the window, with unsaved edits asks Save / Discard / Cancel.
- The gap slider is the global gap: previewed on the canvas, applied on Save.
- An edited layout is named "Custom", and the Layout menu shows "Custom" ticked for that display.

## Global Constraints

- All earlier constraints still apply:
  - No Xcode and no dependencies. Swift Testing, with the test target's explicit TestingMacros plugin flag kept.
  - macOS 14 floor.
  - Accessibility (top-left) coordinates in `PanefulCore`.
  - Commit messages never mention AI or co-authors, and nothing is pushed.
- **SwiftUI without macros.** Without Xcode, the SwiftUI macro plugin is missing, so `@State`, `@Observable`, `@Entry` and `#Preview` do not compile. Use `ObservableObject` with `@Published` and `@ObservedObject` (property wrappers, not macros). Keep all view state, including the canvas's drag state, in `EditorModel`.
- Editing never changes the screen until Save. Save writes `Settings.layouts[displayID]` (through `TilingController.setLayout`) and the gap (through `setGap`).
- The minimum zone size while dragging a divider is `TilingController.minZoneSize` (100 pt).
- An edited layout's name is exactly `"Custom"` (`LayoutDraft.customName`). A preset applied unchanged keeps its preset name.

## Review Focus

1. **Removing a zone that holds tiled windows.** After Save, those windows are untiled and left where they are, while windows in zones that still exist refit. Test: Task 4 manual item 6.
2. **Long edit sequences.** Split and remove in any order must never produce an invalid tree or a duplicate zone ID. Test: Task 1 `editSequenceStaysValid`.
3. **Unsaved edits on close or display switch.** The Save / Discard / Cancel prompt appears, and Cancel keeps the window open with the edits intact. Test: Task 4 manual items 8 and 9.
4. **Thin gaps on a scaled-down canvas.** A gap of 0–8 pt is under 2 px on the canvas, so dividers must still be grabbable. Tests: Task 2 `toleranceWidensThinGaps`; Task 4 manual item 3.
5. **Custom layouts persist and the menu reflects them.** After relaunch, the display still has the Custom layout and the menu ticks "Custom". Choosing a preset from the menu replaces it. Tests: Task 3 `splitNamesTheLayoutCustom`; Task 4 manual item 7.

## File Structure

```
Sources/PanefulCore/
  LayoutEditing.swift   NEW  Node.splitting, Node.removing, Node.dividerHandle
  LayoutDraft.swift     NEW  LayoutDraft (editor working copy)
Tests/PanefulCoreTests/
  LayoutEditingTests.swift  NEW
  LayoutDraftTests.swift    NEW
Sources/Paneful/
  EditorModel.swift            NEW  ObservableObject behind the window
  EditorView.swift             NEW  SwiftUI form + LayoutCanvas
  EditorWindowController.swift NEW  NSWindow hosting EditorView
  AppDelegate.swift            MOD  "Edit Layouts…" item, "Custom" tick
```

---

### Task 1: Split and remove zones

**Files:**
- Create: `Sources/PanefulCore/LayoutEditing.swift`
- Test: `Tests/PanefulCoreTests/LayoutEditingTests.swift`

**Interfaces:**
- Consumes: `Node`, `Axis`, `ZoneID`, `Node.zoneIDs`, `Node.isValid`, `Presets` and `Geometry.zoneRects` (Phase 1).
- Produces:
  - `public func Node.splitting(_ zone: ZoneID, along axis: Axis) -> Node`. The new zone gets ID `max(zoneIDs) + 1` and sits after the original.
  - `public func Node.removing(_ zone: ZoneID) -> Node?`. The removed zone's fraction goes to the previous sibling, or the next one if it was first. A split left with one child collapses into that child. It returns nil when `zone` is the only zone.

- [ ] **Step 1: Write the failing tests**

`Tests/PanefulCoreTests/LayoutEditingTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct LayoutEditingTests {
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)

    private func rects(_ node: Node) -> [ZoneID: CGRect] {
        Geometry.zoneRects(node, in: ultrawide, gap: 8)
    }

    @Test func splitSideBySide() {
        let split = Presets.halves.root.splitting(0, along: .vertical)
        #expect(split.zoneIDs == [0, 2, 1])
        #expect(rects(split)[0] == CGRect(x: 8, y: 39, width: 850, height: 1311))
        #expect(rects(split)[2] == CGRect(x: 866, y: 39, width: 850, height: 1311))
        #expect(rects(split)[1] == rects(Presets.halves.root)[1])
    }

    @Test func splitTopBottom() {
        let split = Presets.halves.root.splitting(1, along: .horizontal)
        #expect(split.zoneIDs == [0, 1, 2])
        #expect(rects(split)[1] == CGRect(x: 1724, y: 39, width: 1708, height: 652))
        #expect(rects(split)[2] == CGRect(x: 1724, y: 699, width: 1708, height: 651))
    }

    @Test func splitSingleZone() {
        #expect(Node.zone(0).splitting(0, along: .vertical) == .split(.vertical, children: [.zone(0), .zone(1)], fractions: [0.5, 0.5]))
    }

    @Test func removeFromPairCollapsesToTheSibling() {
        #expect(Presets.halves.root.removing(1) == .zone(0))
        #expect(Presets.halves.root.removing(0) == .zone(1))
    }

    @Test func removeMiddleGivesItsSpaceToThePreviousZone() throws {
        guard case .split(_, let children, let fractions) = try #require(Presets.thirds.root.removing(1)) else {
            Issue.record("expected a split"); return
        }
        #expect(children == [.zone(0), .zone(2)])
        #expect(abs(fractions[0] - 2.0 / 3) < 1e-9)
        #expect(abs(fractions[1] - 1.0 / 3) < 1e-9)
    }

    @Test func removeFirstGivesItsSpaceToTheNextZone() throws {
        guard case .split(_, let children, let fractions) = try #require(Presets.thirds.root.removing(0)) else {
            Issue.record("expected a split"); return
        }
        #expect(children == [.zone(1), .zone(2)])
        #expect(abs(fractions[0] - 2.0 / 3) < 1e-9)
    }

    @Test func removeNestedCollapsesItsColumn() {
        #expect(Presets.grid2x2.root.removing(1) == .split(.vertical, children: [
            .zone(0),
            .split(.horizontal, children: [.zone(2), .zone(3)], fractions: [0.5, 0.5]),
        ], fractions: [0.5, 0.5]))
    }

    @Test func removeOnlyZoneIsRefused() {
        #expect(Node.zone(0).removing(0) == nil)
    }

    @Test func removeUnknownZoneChangesNothing() {
        #expect(Presets.halves.root.removing(7) == Presets.halves.root)
    }

    @Test func editSequenceStaysValid() throws {
        var node = Presets.halves.root
        node = node.splitting(0, along: .vertical)      // 0 2 | 1
        node = node.splitting(2, along: .horizontal)    // 0 (2/3) | 1
        node = try #require(node.removing(1))
        node = node.splitting(0, along: .horizontal)    // (0/4) (2/3)
        node = try #require(node.removing(3))
        node = node.splitting(4, along: .vertical)
        #expect(node.isValid)
        #expect(Set(node.zoneIDs).count == node.zoneIDs.count)
        #expect(node.zoneIDs.sorted() == [0, 2, 4, 5])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test`
Expected: the build fails with "value of type 'Node' has no member 'splitting'" (and similar for `removing`).

- [ ] **Step 3: Implement**

`Sources/PanefulCore/LayoutEditing.swift`:
```swift
import CoreGraphics

extension Node {
    /// Splits `zone` into two equal zones along `axis`. The new zone gets the next free ID and sits after the original.
    public func splitting(_ zone: ZoneID, along axis: Axis) -> Node {
        let newZone = (zoneIDs.max() ?? -1) + 1
        return replacingZone(zone, with: .split(axis, children: [.zone(zone), .zone(newZone)], fractions: [0.5, 0.5]))
    }

    /// Removes `zone`, giving its space to the zone before it (or after it, if it was first). A split left with one
    /// child collapses into that child. Returns nil if `zone` is the only zone.
    public func removing(_ zone: ZoneID) -> Node? {
        switch self {
        case .zone(let id):
            return id == zone ? nil : self
        case .split(let axis, var children, var fractions):
            guard let index = children.firstIndex(of: .zone(zone)) else {
                return .split(axis, children: children.map { $0.removing(zone) ?? $0 }, fractions: fractions)
            }
            let share = fractions.remove(at: index)
            children.remove(at: index)
            fractions[max(index - 1, 0)] += share
            return children.count == 1 ? children[0] : .split(axis, children: children, fractions: fractions)
        }
    }

    private func replacingZone(_ zone: ZoneID, with replacement: Node) -> Node {
        switch self {
        case .zone(let id):
            return id == zone ? replacement : self
        case .split(let axis, let children, let fractions):
            return .split(axis, children: children.map { $0.replacingZone(zone, with: replacement) }, fractions: fractions)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass (71 in total).

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore/LayoutEditing.swift Tests/PanefulCoreTests/LayoutEditingTests.swift
git commit -m "Add splitting and removing zones"
```

---

### Task 2: Find the divider under a point

**Files:**
- Modify: `Sources/PanefulCore/LayoutEditing.swift` (add `dividerHandle`)
- Test: `Tests/PanefulCoreTests/LayoutEditingTests.swift` (add tests)

**Interfaces:**
- Consumes: `Node.divider(for:of:)` (Phase 2, internal in the same module); `Geometry.zoneRects`; `Edge`.
- Produces: `public func Node.dividerHandle(at point: CGPoint, in frame: CGRect, gap: CGFloat, tolerance: CGFloat) -> (zone: ZoneID, edge: Edge)?`.
  - `edge` is always `.right` or `.bottom`: the handle belongs to the zone *before* the divider.
  - A handle is the gap strip beside a zone's right or bottom edge, widened by `tolerance` on each side. It only counts if that edge has a divider.

- [ ] **Step 1: Write the failing tests**

Append to the `LayoutEditingTests` suite, before its closing brace:
```swift

    @Test func handleInTheGapBetweenHalves() {
        // Zone 0 ends at x = 1716 and zone 1 starts at 1724.
        let handle = Presets.halves.root.dividerHandle(at: CGPoint(x: 1720, y: 500), in: ultrawide, gap: 8, tolerance: 2)
        #expect(handle?.zone == 0)
        #expect(handle?.edge == .right)
    }

    @Test func noHandleInsideAZone() {
        #expect(Presets.halves.root.dividerHandle(at: CGPoint(x: 1000, y: 500), in: ultrawide, gap: 8, tolerance: 2) == nil)
    }

    @Test func noHandleOnAnOuterEdge() {
        #expect(Presets.halves.root.dividerHandle(at: CGPoint(x: 3436, y: 500), in: ultrawide, gap: 8, tolerance: 2) == nil)
    }

    @Test func bottomHandleInALeftColumn() {
        // 2 × 2: zone 0 is (8, 39, 1708, 652), so the left column's row gap is y 691...699.
        let handle = Presets.grid2x2.root.dividerHandle(at: CGPoint(x: 500, y: 695), in: ultrawide, gap: 8, tolerance: 2)
        #expect(handle?.zone == 0)
        #expect(handle?.edge == .bottom)
    }

    @Test func toleranceWidensThinGaps() {
        // With no gap, zones 0 and 1 meet at x = 1720; only the tolerance makes that line grabbable.
        #expect(Presets.halves.root.dividerHandle(at: CGPoint(x: 1719, y: 500), in: ultrawide, gap: 0, tolerance: 3)?.zone == 0)
        #expect(Presets.halves.root.dividerHandle(at: CGPoint(x: 1719, y: 500), in: ultrawide, gap: 0, tolerance: 0) == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test`
Expected: the build fails with "value of type 'Node' has no member 'dividerHandle'".

- [ ] **Step 3: Implement**

Add inside the `extension Node` in `Sources/PanefulCore/LayoutEditing.swift`, after `removing(_:)`:
```swift

    /// The divider under `point`, as the zone before it and that zone's edge (`.right` or `.bottom`). A divider's
    /// handle is the gap beside the zone, widened by `tolerance` either side, since a gap can be too thin to hit.
    public func dividerHandle(at point: CGPoint, in frame: CGRect, gap: CGFloat, tolerance: CGFloat) -> (zone: ZoneID, edge: Edge)? {
        for (zone, rect) in Geometry.zoneRects(self, in: frame, gap: gap).sorted(by: { $0.key < $1.key }) {
            let right = CGRect(x: rect.maxX - tolerance, y: rect.minY, width: gap + 2 * tolerance, height: rect.height)
            if right.contains(point), divider(for: .right, of: zone) != nil { return (zone, .right) }
            let bottom = CGRect(x: rect.minX, y: rect.maxY - tolerance, width: rect.width, height: gap + 2 * tolerance)
            if bottom.contains(point), divider(for: .bottom, of: zone) != nil { return (zone, .bottom) }
        }
        return nil
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass (76 in total).

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore/LayoutEditing.swift Tests/PanefulCoreTests/LayoutEditingTests.swift
git commit -m "Find the divider handle under a point"
```

---

### Task 3: The editor's layout draft

**Files:**
- Create: `Sources/PanefulCore/LayoutDraft.swift`
- Test: `Tests/PanefulCoreTests/LayoutDraftTests.swift`

**Interfaces:**
- Consumes: `Node.splitting`, `Node.removing` (Task 1); `Node.movingEdge` (Phase 2); `Layout`, `Presets`.
- Produces: `public struct LayoutDraft`, with:
  - `static let customName = "Custom"`, `let original: Layout`, `private(set) var layout: Layout` and `var selected: ZoneID?`;
  - `var isDirty: Bool` and `var canRemove: Bool`;
  - `mutating func apply(_ preset: Layout)`, `splitSelected(along: Axis)`, `removeSelected()`, `moveDivider(_ edge: Edge, of zone: ZoneID, to position: CGFloat, in frame: CGRect, gap: CGFloat, minSize: CGFloat)` and `revert()`.

- [ ] **Step 1: Write the failing tests**

`Tests/PanefulCoreTests/LayoutDraftTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct LayoutDraftTests {
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)

    @Test func startsCleanWithNothingSelected() {
        let draft = LayoutDraft(original: Presets.halves)
        #expect(draft.layout == Presets.halves)
        #expect(!draft.isDirty)
        #expect(draft.selected == nil)
        #expect(!draft.canRemove)
    }

    @Test func applyingAPresetKeepsItsName() {
        var draft = LayoutDraft(original: Presets.halves)
        draft.selected = 1
        draft.apply(Presets.thirds)
        #expect(draft.layout == Presets.thirds)
        #expect(draft.isDirty)
        #expect(draft.selected == nil)
    }

    @Test func splitNamesTheLayoutCustom() {
        var draft = LayoutDraft(original: Presets.halves)
        draft.selected = 0
        draft.splitSelected(along: .vertical)
        #expect(draft.layout.name == LayoutDraft.customName)
        #expect(draft.layout.root.zoneIDs == [0, 2, 1])
        #expect(draft.selected == 0)
        #expect(draft.isDirty)
    }

    @Test func splitWithoutASelectionDoesNothing() {
        var draft = LayoutDraft(original: Presets.halves)
        draft.splitSelected(along: .vertical)
        #expect(!draft.isDirty)
    }

    @Test func removeClearsTheSelectionAndStopsAtOneZone() {
        var draft = LayoutDraft(original: Presets.halves)
        draft.selected = 1
        #expect(draft.canRemove)
        draft.removeSelected()
        #expect(draft.layout.root == .zone(0))
        #expect(draft.selected == nil)
        draft.selected = 0
        #expect(!draft.canRemove)
        draft.removeSelected()
        #expect(draft.layout.root == .zone(0))
    }

    @Test func movingADividerNamesTheLayoutCustom() {
        var draft = LayoutDraft(original: Presets.halves)
        draft.moveDivider(.right, of: 0, to: 2000, in: ultrawide, gap: 8, minSize: 100)
        #expect(draft.layout.name == LayoutDraft.customName)
        #expect(Geometry.zoneRects(draft.layout.root, in: ultrawide, gap: 8)[0]!.maxX == 2000)
    }

    @Test func revertRestoresTheOriginal() {
        var draft = LayoutDraft(original: Presets.grid2x2)
        draft.selected = 3
        draft.removeSelected()
        draft.revert()
        #expect(draft.layout == Presets.grid2x2)
        #expect(!draft.isDirty)
        #expect(draft.selected == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test`
Expected: the build fails with "cannot find 'LayoutDraft' in scope".

- [ ] **Step 3: Implement**

`Sources/PanefulCore/LayoutDraft.swift`:
```swift
import CoreGraphics

/// The editor's working copy of one display's layout. Edits other than applying a preset rename it "Custom".
public struct LayoutDraft: Sendable {
    public static let customName = "Custom"

    public let original: Layout
    public private(set) var layout: Layout
    public var selected: ZoneID?

    public init(original: Layout) {
        self.original = original
        self.layout = original
    }

    public var isDirty: Bool { layout != original }

    /// A zone is selected and it isn't the last one.
    public var canRemove: Bool { selected != nil && layout.root.zoneIDs.count > 1 }

    public mutating func apply(_ preset: Layout) {
        layout = preset
        selected = nil
    }

    public mutating func splitSelected(along axis: Axis) {
        guard let selected else { return }
        edit(layout.root.splitting(selected, along: axis))
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
    }

    private mutating func edit(_ root: Node) {
        layout = Layout(name: Self.customName, root: root)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass (83 in total).

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore/LayoutDraft.swift Tests/PanefulCoreTests/LayoutDraftTests.swift
git commit -m "Add the layout editor's draft"
```

---

### Task 4: The Edit Layouts window

**Files:**
- Create: `Sources/Paneful/EditorModel.swift`, `Sources/Paneful/EditorView.swift`, `Sources/Paneful/EditorWindowController.swift`
- Modify: `Sources/Paneful/AppDelegate.swift`

**Interfaces:**
- Consumes:
  - From Tasks 1–3: `LayoutDraft` and `Node.dividerHandle`.
  - From Phases 1–2: `TilingController.displays`, `settings`, `setLayout(_:for:)`, `setGap(_:)` and `minZoneSize`; `Display` (`id`, `name`, `visibleFrame`); `Presets.all`; `Geometry.zoneRects`.
- Produces: `EditorWindowController(tiling:)` with `show()`, and the "Edit Layouts…" menu item.

- [ ] **Step 1: Write the model**

`Sources/Paneful/EditorModel.swift`:
```swift
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
```

- [ ] **Step 2: Write the views**

`Sources/Paneful/EditorView.swift`:
```swift
import PanefulCore
import SwiftUI

// No @State / @Observable / #Preview here: those are macros, and their plugin ships only with Xcode.

struct EditorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Display", selection: Binding(get: { model.displayID }, set: { model.select(displayID: $0) })) {
                ForEach(model.displays, id: \.id) { display in
                    Text(display.name).tag(display.id)
                }
            }
            .frame(maxWidth: 360)

            HStack {
                Text("Presets")
                ForEach(Presets.all, id: \.name) { preset in
                    Button(preset.name) { model.draft.apply(preset) }
                }
            }

            if let display = model.display {
                LayoutCanvas(model: model, frame: display.visibleFrame)
            }

            HStack {
                Text("Selected zone")
                Button("Split side by side") { model.draft.splitSelected(along: .vertical) }
                Button("Split top / bottom") { model.draft.splitSelected(along: .horizontal) }
                Button("Remove") { model.draft.removeSelected() }
                    .disabled(!model.draft.canRemove)
            }
            .disabled(model.draft.selected == nil)

            HStack {
                Text("Gap")
                Slider(value: $model.gap, in: 0...40, step: 1)
                    .frame(maxWidth: 240)
                Text("\(Int(model.gap)) px")
                    .monospacedDigit()
            }

            HStack {
                Spacer()
                Button("Revert") { model.revert() }
                    .disabled(!model.hasChanges)
                Button("Save") { model.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasChanges)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 540)
    }
}

/// The draft layout drawn in its display's shape, with the draft gap. Click a zone to select it;
/// drag the gap between zones to move that divider.
struct LayoutCanvas: View {
    @ObservedObject var model: EditorModel
    /// The display's usable area, in Accessibility coordinates (top-left origin, like SwiftUI).
    let frame: CGRect

    /// How close, in canvas points, a press must be to a divider to grab it.
    private static let handleReach: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / frame.width, proxy.size.height / frame.height)
            let gap = CGFloat(model.gap)
            let rects = Geometry.zoneRects(model.draft.layout.root, in: frame, gap: gap)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: frame.width * scale, height: frame.height * scale)
                ForEach(rects.keys.sorted(), id: \.self) { zone in
                    let rect = canvasRect(rects[zone]!, scale: scale)
                    let isSelected = zone == model.draft.selected
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(isSelected ? 0.45 : 0.18))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: isSelected ? 2 : 1))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in drag(value, scale: scale, gap: gap) }
                .onEnded { value in endDrag(value, scale: scale, rects: rects) })
        }
        .aspectRatio(frame.width / frame.height, contentMode: .fit)
    }

    private func canvasRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: (rect.minX - frame.minX) * scale, y: (rect.minY - frame.minY) * scale,
               width: rect.width * scale, height: rect.height * scale)
    }

    private func displayPoint(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX + point.x / scale, y: frame.minY + point.y / scale)
    }

    private func drag(_ value: DragGesture.Value, scale: CGFloat, gap: CGFloat) {
        if model.dragging == nil {
            // Grab the divider under the press, if there is one.
            let start = displayPoint(value.startLocation, scale: scale)
            model.dragging = model.draft.layout.root.dividerHandle(at: start, in: frame, gap: gap, tolerance: Self.handleReach / scale)
        }
        guard let (zone, edge) = model.dragging else { return }
        let point = displayPoint(value.location, scale: scale)
        // Keep the gap centred on the cursor: the zone's edge sits half a gap before it.
        let position = (edge == .right ? point.x : point.y) - gap / 2
        model.draft.moveDivider(edge, of: zone, to: position, in: frame, gap: gap, minSize: TilingController.minZoneSize)
    }

    private func endDrag(_ value: DragGesture.Value, scale: CGFloat, rects: [ZoneID: CGRect]) {
        defer { model.dragging = nil }
        guard model.dragging == nil else { return }
        // A press that grabbed no divider is a click: select the zone under it, or nothing.
        let point = displayPoint(value.location, scale: scale)
        model.draft.selected = rects.first { $0.value.contains(point) }?.key
    }
}
```

- [ ] **Step 3: Write the window controller**

`Sources/Paneful/EditorWindowController.swift`:
```swift
import AppKit
import SwiftUI

/// The Edit Layouts window.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let model: EditorModel

    init(tiling: TilingController) {
        model = EditorModel(tiling: tiling)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Paneful Layouts"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("EditorWindowController is not loaded from a nib")
    }

    func show() {
        if window?.isVisible != true { model.reload() }
        // Paneful is a menu bar app, so it has to bring itself forward.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.confirmDiscardingChanges()
    }
}
```

- [ ] **Step 4: Add the menu items**

In `Sources/Paneful/AppDelegate.swift`:

Add a property below `private lazy var dragMonitor = …`:
```swift
    private lazy var editor = EditorWindowController(tiling: tiling)
```

In `menuNeedsUpdate(_:)`, replace
```swift
        menu.addItem(header)
        for display in tiling.displays {
            let current = tiling.settings.layout(forDisplay: display.id)
            let submenu = NSMenu()
```
with
```swift
        menu.addItem(header)
        menu.addItem(item("Edit Layouts…", #selector(openEditor)))
        for display in tiling.displays {
            let current = tiling.settings.layout(forDisplay: display.id)
            let submenu = NSMenu()
            if !Presets.all.contains(current) {
                // An edited layout: shown ticked above the presets, which would replace it.
                let custom = NSMenuItem(title: current.name, action: nil, keyEquivalent: "")
                custom.state = .on
                submenu.addItem(custom)
                submenu.addItem(.separator())
            }
```

Add next to the other `@objc` actions:
```swift
    @objc private func openEditor() {
        editor.show()
    }
```

- [ ] **Step 5: Build, test and install**

Run: `swift build 2>&1 | grep -E "error|warning: [^s]" | grep -v "search path"; swift test 2>&1 | tail -1; scripts/install.sh`
Expected: no errors, all 83 tests pass, and the app relaunches.

- [ ] **Step 6: Manual checklist (Adam runs it and reports each item as pass or fail)**

1. Choose Layouts ▸ Edit Layouts…. The window comes to the front, showing the display picker, the preset buttons, a canvas in the ultrawide's shape with its current layout, the zone buttons, the gap slider, and Revert and Save (both disabled).
2. Click Thirds. The canvas shows three zones, and Revert and Save become enabled. Click Revert, and the canvas goes back to the saved layout.
3. Drag the gap between two zones. The divider follows the cursor and stops at about 100 pt zones. Set the gap slider to 0 and check the divider is still grabbable.
4. Click a zone. It highlights. Split side by side, then split top / bottom. The zones split into equal halves. Remove merges a zone into its neighbour, and it's disabled once only one zone is left.
5. Move the gap slider. The canvas gaps change live, but windows on screen don't move until you click Save. After Save, tiled windows on that display refit.
6. Tile windows in two zones, then remove one of those zones in the editor and click Save. The window in the removed zone stays where it is, now untiled (a plain resize moves nothing else), and the other window refits.
7. After saving an edited layout, the Layouts ▸ (display) submenu shows "Custom" ticked above the presets. Shift-drag shows the custom zones. Quit and relaunch, and it's still Custom. Choosing a preset from the menu replaces it.
8. Make an edit, then pick another display in the picker. The Save / Discard / Cancel prompt appears. Cancel stays on the same display with the edit intact, Discard switches, and Save saves and then switches.
9. Make an edit, then close the window. The same prompt appears, and Cancel keeps the window open.
10. Edit the PA248QV layouts. Each display's canvas matches its shape, and saving one display doesn't change the others.

Fix any failures (use superpowers:systematic-debugging), rebuild with `scripts/install.sh`, and repeat the failed items.

- [ ] **Step 7: Commit**

```bash
git add Sources/Paneful
git commit -m "Add the Edit Layouts window"
```
