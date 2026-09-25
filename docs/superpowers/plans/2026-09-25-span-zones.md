# Span Zones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Holding the span key (Option by default) during a Shift-drag stretches the drop target across a block of zones; the window then tiles and resizes as that block.

**Architecture:** `Arrangement` maps each window to a `Set<ZoneID>` (a normal snap is a set of one). A new `Span.swift` in core computes the block of whole zones between an anchor and the current zone, and the union rect of a zone set. `moveEdge` and `fit` act on a zone set's outer edges. The app wiring (DragMonitor, overlay, TilingController, the menu) passes zone sets and landing rects around.

**Tech Stack:** Swift 6.4, SwiftPM, Swift Testing, AppKit. Command Line Tools only.

**Spec:** `docs/superpowers/specs/2026-09-25-span-zones-design.md`

## Global Constraints

- **No commits.** Adam wants to test before anything is committed, so leave all work uncommitted on branch `span-zones`.
- New logic goes in `PanefulCore`, test first. The app target is wiring and is verified by hand.
- There are no SwiftUI macros, no third-party dependencies, and macOS 14 is the minimum. The app target stays in `.swiftLanguageMode(.v5)`.
- All geometry uses Accessibility coordinates (top-left origin, y down).
- The span key defaults to `.option`. It can never equal the snap modifier: setting either one to the other's value swaps them.
- "Overlap" for the span closure means an intersection with positive width **and** height. At gap 0, zones that only touch don't overlap.
- Run the tests with `swift test`. Ignore the `ld: warning: search path …` lines.

## Review Focus

1. **Span-edge moves where one column clamps and another doesn't.** The tree must stay valid and each column must respect `minSize`. Tested in Task 2 (`spanEdgeMovesAreClampedAndStayValid`).
2. **A window stacked in one zone of a span moving the span's internal divider.** The span's rect must stay the same. Tested in Task 2 (`internalDividerLeavesSpanAlone`).
3. **A settings file with both keys equal** (for example hand-edited, or an old file where `modifier` is `option`). The span key must fall back to another key. Tested in Task 3 (`equalKeysOnLoadFallBack`).
4. **The span key released, or the cursor moved to another display, mid-drag.** The anchor must reset and the target must go back to one zone. This is app-side, so it's in the Task 4 manual checklist.
5. **A layout change removing one zone of a span.** The window must be untiled, not squeezed into what's left. Tested in Task 2 (`rebasedDropsSpanWhoseZoneWasRemoved`).

---

### Task 1: Span geometry

**Files:**
- Create: `Sources/PanefulCore/Span.swift`
- Test: `Tests/PanefulCoreTests/SpanTests.swift`

**Interfaces:**
- Produces: `Geometry.union(of zones: Set<ZoneID>, in rects: [ZoneID: CGRect]) -> CGRect?`, and `Geometry.span(from anchor: ZoneID, to current: ZoneID, in rects: [ZoneID: CGRect]) -> Set<ZoneID>`.

- [ ] **Step 1: Write the failing tests**

```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct SpanTests {
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)
    /// 2 × 2 at gap 0: TL = 0, BL = 1, TR = 2, BR = 3, each 500 × 400.
    let grid = Geometry.zoneRects(Presets.grid2x2.root, in: CGRect(x: 0, y: 0, width: 1000, height: 800), gap: 0)

    @Test func neighboursInThirds() {
        let rects = Geometry.zoneRects(Presets.thirds.root, in: ultrawide, gap: 8)
        #expect(Geometry.span(from: 0, to: 1, in: rects) == [0, 1])
        #expect(Geometry.span(from: 1, to: 0, in: rects) == [0, 1])
        #expect(Geometry.span(from: 0, to: 2, in: rects) == [0, 1, 2])
    }

    @Test func sameZoneIsJustThatZone() {
        let rects = Geometry.zoneRects(Presets.thirds.root, in: ultrawide, gap: 8)
        #expect(Geometry.span(from: 1, to: 1, in: rects) == [1])
    }

    @Test func rowIn2x2() {
        // At gap 0 the bottom row touches the top row, and touching isn't overlapping.
        #expect(Geometry.span(from: 0, to: 2, in: grid) == [0, 2])
    }

    @Test func diagonalIn2x2IsTheWholeScreen() {
        #expect(Geometry.span(from: 0, to: 3, in: grid) == [0, 1, 2, 3])
    }

    @Test func unalignedRowsPullInNeighbours() {
        // Left column split 50/50, right column 30/70: the box over TL and TR half-covers BR, so BR joins,
        // and then the box covers BL too.
        let node = Node.split(.vertical, children: [
            .split(.horizontal, children: [.zone(0), .zone(1)], fractions: [0.5, 0.5]),
            .split(.horizontal, children: [.zone(2), .zone(3)], fractions: [0.3, 0.7]),
        ], fractions: [0.5, 0.5])
        let rects = Geometry.zoneRects(node, in: CGRect(x: 0, y: 0, width: 1000, height: 1000), gap: 0)
        #expect(Geometry.span(from: 0, to: 2, in: rects) == [0, 1, 2, 3])
        #expect(Geometry.span(from: 2, to: 3, in: rects) == [2, 3])
    }

    @Test func unionCoversTheGapBetweenZones() {
        let rects = Geometry.zoneRects(Presets.thirds.root, in: ultrawide, gap: 8)
        #expect(Geometry.union(of: [0, 1], in: rects) == CGRect(x: 8, y: 39, width: 2280, height: 1311))
        #expect(Geometry.union(of: [1], in: rects) == rects[1])
        #expect(Geometry.union(of: [], in: rects) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SpanTests`
Expected: a compile failure. `Geometry` has no member `span` or `union`.

- [ ] **Step 3: Write the implementation**

`Sources/PanefulCore/Span.swift`:

```swift
import CoreGraphics

extension Geometry {
    /// The bounding rect of `zones`' rects, or nil if none of them has one.
    public static func union(of zones: Set<ZoneID>, in rects: [ZoneID: CGRect]) -> CGRect? {
        zones.compactMap { rects[$0] }.reduce(CGRect?.none) { $0?.union($1) ?? $1 }
    }

    /// The zones a window dragged with the span key covers: the smallest block of whole zones containing `anchor`
    /// and `current`. Starting from their bounding box, any zone overlapping the box joins it and grows it, until
    /// none does, so a span never half-covers a zone.
    public static func span(from anchor: ZoneID, to current: ZoneID, in rects: [ZoneID: CGRect]) -> Set<ZoneID> {
        var zones = Set([anchor, current].filter { rects[$0] != nil })
        guard var box = union(of: zones, in: rects) else { return [] }
        while let next = rects.first(where: { !zones.contains($0.key) && overlaps($0.value, box) }) {
            zones.insert(next.key)
            box = box.union(next.value)
        }
        return zones
    }

    /// Whether two rects share some area. Rects that only touch (at gap 0) don't.
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let shared = a.intersection(b)
        return !shared.isNull && shared.width > 0 && shared.height > 0
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SpanTests`
Expected: PASS (6 tests).

---

### Task 2: Arrangement holds zone sets

**Files:**
- Modify: `Sources/PanefulCore/Arrangement.swift` (whole file)
- Modify: `Tests/PanefulCoreTests/ArrangementTests.swift` (existing call sites, plus new tests)
- Modify: `Tests/PanefulCoreTests/ResizeTrackerTests.swift:61` (the call site)

**Interfaces:**
- Consumes: `Geometry.union(of:in:)` from Task 1.
- Produces:
  - `assign(_:to zones: Set<ZoneID>)`, and `assign(_:to zone: ZoneID)`.
  - `zones(of:) -> Set<ZoneID>?`. This replaces `zone(of:)`, which is removed.
  - `windows(in:)`, now including spans.
  - `moveEdge(_:of zones: Set<ZoneID>, to:in:gap:minSize:) -> Bool`
  - `fit(_ zones: Set<ZoneID>, toAtLeast:in:gap:minSize:) -> Bool`
  - `rebased(on:)`, which keeps a window only if all its zones survive.

- [ ] **Step 1: Update the existing call sites to the new API**

These are mechanical renames. The behaviour they check is unchanged. In `ArrangementTests.swift`:
- `arrangement.zone(of: "safari") == 1` becomes `arrangement.zones(of: "safari") == [1]`.
- `arrangement.zone(of: "a") == nil` (both places) becomes `arrangement.zones(of: "a") == nil`.
- `arrangement.zone(of: "a") == 1` becomes `arrangement.zones(of: "a") == [1]`.
- `rebased.zone(of: "left") == 0` becomes `rebased.zones(of: "left") == [0]`.
- `rebased.zone(of: "right") == nil` becomes `rebased.zones(of: "right") == nil`.
- Every `moveEdge(…, of: N, …)` becomes `moveEdge(…, of: [N], …)`.
- Every `fit(N, toAtLeast:` becomes `fit([N], toAtLeast:`.

In `ResizeTrackerTests.swift:61`, `of: 0` becomes `of: [0]`.

- [ ] **Step 2: Add the failing span tests** to the end of `ArrangementTests`, before the final `}`:

```swift
    // MARK: Spans

    /// Thirds at gap 0 on 900 × 500: zones 0, 1, 2 are 300 wide.
    let narrow = CGRect(x: 0, y: 0, width: 900, height: 500)
    /// 2 × 2 at gap 0: TL = 0, BL = 1, TR = 2, BR = 3, each 500 × 400.
    let square = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func spanSitsInEachOfItsZones() {
        var arrangement = Arrangement<String>(saved: Presets.grid2x2)
        arrangement.assign("w", to: [0, 2])
        #expect(arrangement.zones(of: "w") == [0, 2])
        #expect(arrangement.windows(in: 0) == ["w"])
        #expect(arrangement.windows(in: 2) == ["w"])
        #expect(arrangement.windows(in: 1).isEmpty)
    }

    @Test func spanWithAnUnknownZoneIsIgnored() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("w", to: [0, 7])
        #expect(arrangement.zones(of: "w") == nil)
        arrangement.assign("w", to: [])
        #expect(arrangement.zones(of: "w") == nil)
    }

    @Test func rebasedDropsSpanWhoseZoneWasRemoved() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.assign("kept", to: [0, 1])
        arrangement.assign("broken", to: [1, 2])
        let rebased = arrangement.rebased(on: Presets.halves)
        #expect(rebased.zones(of: "kept") == [0, 1])
        #expect(rebased.zones(of: "broken") == nil)
    }

    @Test func spanBottomEdgeMovesBothRowDividers() {
        var arrangement = Arrangement<String>(saved: Presets.grid2x2)
        let moved = arrangement.moveEdge(.bottom, of: [0, 2], to: 600, in: square, gap: 0, minSize: 100)
        #expect(moved)
        let rects = arrangement.rects(in: square, gap: 0)
        #expect(rects[0]!.maxY == 600)
        #expect(rects[2]!.maxY == 600)
        #expect(rects[1]!.minY == 600)
        #expect(rects[3]!.minY == 600)
    }

    @Test func spanRightEdgeMovesOnlyTheOuterDivider() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        let moved = arrangement.moveEdge(.right, of: [0, 1], to: 700, in: narrow, gap: 0, minSize: 100)
        #expect(moved)
        let rects = arrangement.rects(in: narrow, gap: 0)
        #expect(rects[0] == CGRect(x: 0, y: 0, width: 300, height: 500))
        #expect(rects[1]!.maxX == 700)
        #expect(rects[2]!.minX == 700)
    }

    @Test func spanOuterEdgeAgainstTheScreenMovesNothing() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        let moved = arrangement.moveEdge(.left, of: [0, 1], to: 50, in: narrow, gap: 0, minSize: 100)
        #expect(!moved)
        #expect(arrangement.working == Presets.thirds.root)
    }

    @Test func internalDividerLeavesSpanAlone() {
        // A window stacked in zone 0 alone resizes its right edge, which is inside the [0, 1] span.
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.moveEdge(.right, of: [0], to: 400, in: narrow, gap: 0, minSize: 100)
        let rects = arrangement.rects(in: narrow, gap: 0)
        #expect(rects[0]!.maxX == 400)
        #expect(Geometry.union(of: [0, 1], in: rects) == CGRect(x: 0, y: 0, width: 600, height: 500))
    }

    @Test func spanEdgeMovesAreClampedAndStayValid() {
        var arrangement = Arrangement<String>(saved: Presets.grid2x2)
        arrangement.moveEdge(.bottom, of: [0, 2], to: 780, in: square, gap: 0, minSize: 100)
        let rects = arrangement.rects(in: square, gap: 0)
        #expect(rects[1]!.height == 100)
        #expect(rects[3]!.height == 100)
        #expect(arrangement.working.isValid)
    }

    @Test func fitGrowsASpanTowardItsDivider() {
        // Span [1, 2] is 600 wide against the screen's right edge; its window refuses to be narrower than 700.
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        let moved = arrangement.fit([1, 2], toAtLeast: CGSize(width: 700, height: 100), in: narrow, gap: 0, minSize: 100)
        #expect(moved)
        let rects = arrangement.rects(in: narrow, gap: 0)
        #expect(Geometry.union(of: [1, 2], in: rects) == CGRect(x: 200, y: 0, width: 700, height: 500))
        #expect(rects[0]!.width == 200)
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter ArrangementTests`
Expected: a compile failure. There's no `zones(of:)`, and `of: [0]` / `fit([1]` don't type-check.

- [ ] **Step 4: Write the implementation**

Replace `Sources/PanefulCore/Arrangement.swift` with:

```swift
import CoreGraphics

/// One display's live state: a working copy of the saved layout (which linked resizing adjusts)
/// plus which zones each window covers: one zone, or a span of several. The saved layout itself is never changed here.
public struct Arrangement<Window: Hashable> {
    public let saved: Layout
    public private(set) var working: Node
    private var zonesOf: [Window: Set<ZoneID>] = [:]

    public init(saved: Layout) {
        self.saved = saved
        self.working = saved.root
    }

    public var tiledWindows: [Window] { Array(zonesOf.keys) }

    public func zones(of window: Window) -> Set<ZoneID>? { zonesOf[window] }

    /// Windows covering `zone`, including spans that contain it.
    public func windows(in zone: ZoneID) -> [Window] {
        zonesOf.filter { $0.value.contains(zone) }.map(\.key)
    }

    /// Puts `window` in `zones` (one zone, or a span), leaving wherever it was. Ignored unless every zone exists.
    public mutating func assign(_ window: Window, to zones: Set<ZoneID>) {
        guard !zones.isEmpty, zones.isSubset(of: working.zoneIDs) else { return }
        zonesOf[window] = zones
    }

    public mutating func assign(_ window: Window, to zone: ZoneID) {
        assign(window, to: [zone])
    }

    public mutating func remove(_ window: Window) {
        zonesOf[window] = nil
    }

    /// Restores the saved layout's boundaries; windows keep their zones.
    public mutating func reset() {
        working = saved.root
    }

    /// Moves the dividers under `edge` of the block `zones` covers (see `Node.movingEdge`): one for each zone whose
    /// edge lies on the block's edge, since in a span those can sit under different splits. Only the working tree
    /// changes. Returns false if that edge has no divider.
    @discardableResult
    public mutating func moveEdge(_ edge: Edge, of zones: Set<ZoneID>, to position: CGFloat, in frame: CGRect, gap: CGFloat, minSize: CGFloat) -> Bool {
        let rects = rects(in: frame, gap: gap)
        guard let block = Geometry.union(of: zones, in: rects) else { return false }
        var moved = false
        for zone in zones.sorted() where rects[zone].map({ edge.coordinate(of: $0) == edge.coordinate(of: block) }) == true {
            if let node = working.movingEdge(edge, of: zone, to: position, in: frame, gap: gap, minSize: minSize) {
                working = node
                moved = true
            }
        }
        return moved
    }

    /// Grows the block `zones` covers until it's at least `size` along each axis, for a window that refuses to shrink
    /// to it. It moves the dividers on the block's trailing side if there are any, otherwise those on its leading side,
    /// so a block against the screen's right or bottom edge grows back toward its neighbour.
    /// Returns whether any divider moved.
    @discardableResult
    public mutating func fit(_ zones: Set<ZoneID>, toAtLeast size: CGSize, in displayFrame: CGRect, gap: CGFloat, minSize: CGFloat) -> Bool {
        var moved = false
        for (extent, trailing, leading) in [(size.width, Edge.right, Edge.left), (size.height, Edge.bottom, Edge.top)] {
            guard let rect = Geometry.union(of: zones, in: rects(in: displayFrame, gap: gap)) else { return moved }
            let current = trailing == .right ? rect.width : rect.height
            guard extent > current + 1 else { continue }
            if moveEdge(trailing, of: zones, to: leading.coordinate(of: rect) + extent, in: displayFrame, gap: gap, minSize: minSize)
                || moveEdge(leading, of: zones, to: trailing.coordinate(of: rect) - extent, in: displayFrame, gap: gap, minSize: minSize) {
                moved = true
            }
        }
        return moved
    }

    /// A fresh arrangement for `saved`, keeping windows whose zones all still exist in it.
    public func rebased(on saved: Layout) -> Arrangement {
        var result = Arrangement(saved: saved)
        for (window, zones) in zonesOf { result.assign(window, to: zones) }
        return result
    }

    public func rects(in frame: CGRect, gap: CGFloat) -> [ZoneID: CGRect] {
        Geometry.zoneRects(working, in: frame, gap: gap)
    }
}
```

- [ ] **Step 5: Run the whole suite to verify it passes**

Run: `swift test`
Expected: PASS. That's the 102 old tests plus the 6 from Task 1 and the 9 from this task (117 in total).

---

### Task 3: The span key setting

**Files:**
- Modify: `Sources/PanefulCore/Settings.swift:9-24`
- Modify: `Tests/PanefulCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  - `Settings.spanModifier: ModifierKey`. `modifier` and `spanModifier` both become `public private(set)`.
  - `Settings.setModifier(_:)` and `Settings.setSpanModifier(_:)`, which swap when the new value equals the other key.

- [ ] **Step 1: Write the failing tests**

In `SettingsTests.swift`:
- In `defaults()`, add `#expect(settings.spanModifier == .option)`.
- In `partialFileKeepsKnownValues()`, add `#expect(settings.spanModifier == .option)`.
- In `saveThenLoadRoundTrips()`, replace `settings.modifier = .option` with:

```swift
        settings.setModifier(.command)
        settings.setSpanModifier(.control)
```

Add these tests:

```swift
    @Test func unknownSpanKeyFallsBackToOption() throws {
        #expect(try store(containing: #"{"spanModifier": "hyper"}"#).load().spanModifier == .option)
    }

    @Test func equalKeysOnLoadFallBack() throws {
        // An older file that set the snap modifier to Option, before the span key existed.
        let settings = try store(containing: #"{"modifier": "option"}"#).load()
        #expect(settings.modifier == .option)
        #expect(settings.spanModifier == .shift)
    }

    @Test func settingTheModifierToTheSpanKeySwapsThem() {
        var settings = Settings()
        settings.setModifier(.option)
        #expect(settings.modifier == .option)
        #expect(settings.spanModifier == .shift)
    }

    @Test func settingTheSpanKeyToTheModifierSwapsThem() {
        var settings = Settings()
        settings.setSpanModifier(.shift)
        #expect(settings.spanModifier == .shift)
        #expect(settings.modifier == .option)
    }

    @Test func settingAnUnusedKeyDoesNotSwap() {
        var settings = Settings()
        settings.setSpanModifier(.control)
        #expect(settings.spanModifier == .control)
        #expect(settings.modifier == .shift)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SettingsTests`
Expected: a compile failure. There's no `spanModifier` or `setModifier`.

- [ ] **Step 3: Write the implementation**

In `Settings.swift`, replace

```swift
    public var modifier: ModifierKey = .shift
```

with

```swift
    /// Held while dragging a window to show zones. Never the same key as `spanModifier`.
    public private(set) var modifier: ModifierKey = .shift
    /// Held as well as `modifier` to stretch the drop target across zones.
    public private(set) var spanModifier: ModifierKey = .option
```

In `init(from:)`, after the `modifier = …` line, add:

```swift
        spanModifier = (try? container.decodeIfPresent(ModifierKey.self, forKey: .spanModifier)) ?? .option
        if spanModifier == modifier { spanModifier = ModifierKey.allCases.first { $0 != modifier }! }
```

After `layout(forDisplay:)`, add:

```swift
    /// Sets the snap modifier. If it was the span key, the span key takes the old modifier, so the two never match.
    public mutating func setModifier(_ key: ModifierKey) {
        if key == spanModifier { spanModifier = modifier }
        modifier = key
    }

    /// Sets the span key. If it was the snap modifier, the modifier takes the old span key, so the two never match.
    public mutating func setSpanModifier(_ key: ModifierKey) {
        if key == modifier { modifier = spanModifier }
        spanModifier = key
    }
```

- [ ] **Step 4: Run the whole suite**

Run: `swift test`
Expected: all core tests pass (122). `swift build` now fails in `TilingController.setModifier` (`settings.modifier` is read-only). Task 4 fixes that.

---

### Task 4: App wiring

**Files:**
- Modify: `Sources/Paneful/TilingController.swift`
- Modify: `Sources/Paneful/DragMonitor.swift`
- Modify: `Sources/Paneful/OverlayController.swift`
- Modify: `Sources/Paneful/AppDelegate.swift`

**Interfaces:**
- Consumes:
  - `Geometry.span(from:to:in:)` and `Geometry.union(of:in:)` (Task 1).
  - `Arrangement.assign(_:to: Set<ZoneID>)`, `zones(of:)`, and `moveEdge`/`fit` with zone sets (Task 2).
  - `Settings.spanModifier`, `setModifier` and `setSpanModifier` (Task 3).
- Produces:
  - `TilingController.snap(_:to zones: Set<ZoneID>, on:)` and `TilingController.setSpanModifier(_:)`.
  - `OverlayController.show(on:rects:highlighted: CGRect?)`.

- [ ] **Step 1: `TilingController`**

Replace `snap`:

```swift
    /// Tiles `window` in `zones` (one zone, or a span), filling their combined rect.
    func snap(_ window: AXUIElement, to zones: Set<ZoneID>, on display: Display) {
        guard let rect = Geometry.union(of: zones, in: zoneRects(for: display)) else { return }
        // Moving between zones keeps the size from before the first snap.
        if !isTiled(window) { sizesBeforeSnap[window] = WindowAccess.frame(of: window)?.size }
        untile(window)
        arrangements[display.id]?.assign(window, to: zones)
        WindowAccess.setFrame(rect, of: window, within: display.visibleFrame)
    }
```

In `followResize`:
- The guard becomes `guard let (display, zones) = location(of: window), var arrangement = arrangements[display.id] else { return false }`.
- The move call becomes `arrangement.moveEdge(move.edge, of: zones, to: move.position, …)`.

In `finishResize`, the loop body becomes:

```swift
            guard let zones = arrangement.zones(of: tiled), let actual = WindowAccess.frame(of: tiled) else { continue }
            if arrangement.fit(zones, toAtLeast: actual.size, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) {
```

Replace `location(of:)`:

```swift
    private func location(of window: AXUIElement) -> (display: Display, zones: Set<ZoneID>)? {
        for display in displays {
            if let zones = arrangements[display.id]?.zones(of: window) { return (display, zones) }
        }
        return nil
    }
```

Replace `setModifier` and add `setSpanModifier`:

```swift
    func setModifier(_ modifier: ModifierKey) {
        settings.setModifier(modifier)
        save()
    }

    func setSpanModifier(_ modifier: ModifierKey) {
        settings.setSpanModifier(modifier)
        save()
    }
```

In `refit`, the `guard` inside the loop becomes:

```swift
            guard let zones = arrangement.zones(of: window), let rect = Geometry.union(of: zones, in: rects),
                  old.flatMap({ Geometry.union(of: zones, in: $0) }) != rect else { continue }
```

The doc comment on `refit` changes from "moves only windows whose rect changed" to "moves only windows whose (combined) rect changed".

- [ ] **Step 2: `OverlayController`**

Replace `show(on:rects:highlighted:)` and `ZoneOverlayView`:

```swift
    /// Draws `rects` on `display`, with `highlighted` (the landing rect: one zone, or a span) drawn over them.
    func show(on display: Display, rects: [ZoneID: CGRect], highlighted: CGRect?) {
        for (id, window) in windows where id != display.id { window.orderOut(nil) }
        let window = windows[display.id] ?? makeWindow()
        windows[display.id] = window
        if window.frame != display.screen.frame { window.setFrame(display.screen.frame, display: false) }

        // Zone rects are in Accessibility coordinates; the view wants AppKit coordinates relative to the screen.
        let origin = display.screen.frame.origin
        let local = { (rect: CGRect) in
            Coordinates.flip(rect, primaryScreenHeight: Displays.primaryHeight).offsetBy(dx: -origin.x, dy: -origin.y)
        }
        let view = window.contentView as! ZoneOverlayView
        view.zones = rects.values.map(local)
        view.highlighted = highlighted.map(local)
        view.needsDisplay = true
        window.orderFrontRegardless()
    }
```

```swift
final class ZoneOverlayView: NSView {
    var zones: [CGRect] = []
    var highlighted: CGRect?

    override func draw(_ dirtyRect: NSRect) {
        // Zones under the highlight are drawn as the one landing rect.
        for zone in zones where highlighted?.contains(zone) != true { draw(zone, isHighlighted: false) }
        if let highlighted { draw(highlighted, isHighlighted: true) }
    }

    private func draw(_ rect: CGRect, isHighlighted: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.35 : 0.12).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.9 : 0.4).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
```

- [ ] **Step 3: `DragMonitor`**

Update the doc comment at the top of the class:

```swift
/// Watches global mouse events and turns each press into one gesture:
/// - moving a window: holding the modifier shows its display's zones. Releasing over one snaps the window there;
///   releasing anywhere else untiles it. Holding the span key as well stretches the target from the zone it was
///   pressed over (the anchor) to the zone under the cursor.
/// - resizing a tiled window: the dividers under the dragged edges follow live, resizing the neighbouring windows.
```

Replace the `moving` case:

```swift
        /// `anchor` is where the span key went down, kept only while it's held on that display.
        case moving(AXUIElement, target: (display: Display, zones: Set<ZoneID>)?, anchor: (displayID: String, zone: ZoneID)?)
```

Pass the event's flags through instead of `modifierHeld`, because updating a move needs both keys:
- In `handle(_:)`, delete the `let modifierHeld = …` line.
  - `.leftMouseDragged` calls `drag(flags: event.modifierFlags)`.
  - `.flagsChanged` becomes `if case .moving(let window, _, _) = gesture { updateMove(window, flags: event.modifierFlags) }`.
- `drag(modifierHeld:)` becomes `drag(flags: NSEvent.ModifierFlags)`.
  - It calls `classify(candidates, flags: flags)`.
  - Its `case .moving(let window, _):` becomes `case .moving(let window, _, _):` and calls `updateMove(window, flags: flags)`.
- `classify(_:modifierHeld:)` becomes `classify(_:flags: NSEvent.ModifierFlags)`. Its moving branch becomes:

```swift
                gesture = .moving(candidate.window, target: nil, anchor: nil)
                updateMove(candidate.window, flags: flags)
```

Replace `updateMove` and add `spanAnchor(on:)`:

```swift
    private func updateMove(_ window: AXUIElement, flags: NSEvent.ModifierFlags) {
        guard flags.contains(tiling.settings.modifier.flags), let display = tiling.display(containing: cursor) else {
            gesture = .moving(window, target: nil, anchor: nil)
            overlay.hide()
            return
        }
        let rects = tiling.zoneRects(for: display)
        let zone = Geometry.zone(at: cursor, in: rects, gap: tiling.gap)
        // The anchor is set the first time the span key is seen held, and dropped when it's released.
        let anchor = flags.contains(tiling.settings.spanModifier.flags) ? spanAnchor(on: display) ?? zone : nil
        let zones = zone.map { zone in anchor.map { Geometry.span(from: $0, to: zone, in: rects) } ?? [zone] }
        gesture = .moving(window, target: zones.map { (display: display, zones: $0) }, anchor: anchor.map { (displayID: display.id, zone: $0) })
        overlay.show(on: display, rects: rects, highlighted: zones.flatMap { Geometry.union(of: $0, in: rects) })
    }

    /// The span anchor of the move in progress, if it was set on `display`. Moving to another display drops it.
    private func spanAnchor(on display: Display) -> ZoneID? {
        guard case .moving(_, _, let anchor?) = gesture, anchor.displayID == display.id else { return nil }
        return anchor.zone
    }
```

In `release()`:
- `case .moving(let window, let target?):` becomes `case .moving(let window, let target?, _):`, and its body calls `tiling.snap(window, to: target.zones, on: target.display)`.
- `case .moving(let window, nil):` becomes `case .moving(let window, nil, _):`.

- [ ] **Step 4: `AppDelegate`**

Replace the Modifier menu block (the `let modifierMenu = NSMenu()` through `menu.addItem(parent("Modifier", modifierMenu))`) with:

```swift
        menu.addItem(parent("Modifier", keyMenu(selected: tiling.settings.modifier, action: #selector(chooseModifier(_:)))))
        menu.addItem(parent("Span Key", keyMenu(selected: tiling.settings.spanModifier, action: #selector(chooseSpanModifier(_:)))))
```

Add after `parent(_:_:)`:

```swift
    private func keyMenu(selected: ModifierKey, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for key in ModifierKey.allCases {
            let choice = item(key.title, action)
            choice.representedObject = key
            choice.state = key == selected ? .on : .off
            menu.addItem(choice)
        }
        return menu
    }
```

Add after `chooseModifier(_:)`:

```swift
    @objc private func chooseSpanModifier(_ sender: NSMenuItem) {
        guard let modifier = sender.representedObject as? ModifierKey else { return }
        tiling.setSpanModifier(modifier)
    }
```

- [ ] **Step 5: Build and test**

Run: `swift build && swift test`
Expected: the build completes and all 122 tests pass.

- [ ] **Step 6: Install and hand over for manual testing**

Run: `scripts/install.sh`. If codesign seems to hang, a keychain dialog is waiting for "Always Allow".

Adam's checklist, on the three displays:
1. **Thirds on the Sceptre:** Shift-drag over A, press Option, then move to B. The overlay shows one landing rect over A+B. Release, and the window fills A+B exactly.
2. **Changing the span mid-drag:**
   - Move on to C (A+B+C).
   - Move back to A (A only).
   - Release Option while still over C: the target is C alone.
   - Press Option again: C becomes the new anchor.
3. **2 × 2 on a PA248QV:** span TL+TR. Drag the spanning window's bottom edge: both BL and BR follow live. On release, nothing overlaps.
4. **Linked resizing in Thirds:** a spanning window over A+B. Drag its right edge: C follows. Drag its left edge (the screen edge): it resizes freely and stays tiled.
5. **Minimum sizes:** span a window that has a minimum width into two narrow zones, then resize a neighbour to squeeze it. On release, the span grows to fit.
6. **Cursor to another display** with Shift+Option held: that display shows a single-zone target first, and the anchor resets.
7. **Menu:** Span Key ▸ shows Option ticked. Pick Shift: Modifier ▸ now shows Option, and Span Key ▸ Shift.
   - Set them back.
8. **Layout changes:**
   - Reset Arrangement refits the spanning window to its span.
   - Choosing Halves on a Thirds display with a B+C span untiles that window.
9. **Straight span edges (added after the final review):** with TL+TR spanned in 2 × 2, resize BL's and BR's top edges. The span's bottom edge stays straight. Then hold Shift+Option before grabbing a title bar and drag fast: the span starts at the zone you pressed on.
10. **Regression:** plain Shift-drag into one zone, drag-out size restore and a single-zone linked resize all behave as before.

---

### Task 5: Docs

**Files:**
- Modify: `docs/history/README.md`
- Modify: `docs/history/design-decisions.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: `docs/history/README.md`**
  - **Timeline:** add a row after the restore-on-drag-out row:

```markdown
| 2026-09-25 | Span zones | Holding the span key (Option by default, set in Span Key ▸) as well as the modifier stretches the drop target from the zone it was pressed over to the zone under the cursor, as the smallest block of whole zones covering both. A window now covers a set of zones, and a spanning window resizes with its neighbours: its edge moves every divider it sits on. |
```

  - **Code map:** in the `PanefulCore` list, after the `Coordinates.swift` line, add:

```markdown
  - `Span.swift`: the block of zones a span covers, and a zone set's combined rect.
```

  - **"Where it stands":** update the follow-ups sentence to list three follow-ups (add "spanning windows across zones"). Update the test count to what `swift test` reports.

- [ ] **Step 2: `docs/history/design-decisions.md`**
  - **Product decisions table:** add, after the ultrawide preset row:

```markdown
| **Span zones with a second key, as a block of whole zones** | Shift+Option-drag covers the anchor zone and the one under the cursor, never half a zone. A span is only where the window sits: the saved layout doesn't change, and a span whose zone is removed untiles its window. |
```

  - **Architecture decisions:** change the "Windows are matched to zones by ID" bullet to "Windows are matched to zones by ID, as a set per window (one zone, or a span), through `Arrangement<AXUIElement>`…". Keep the rest of the sentence.

- [ ] **Step 3: `CLAUDE.md`**
  - Line 45: "plus which windows sit in which zone." becomes "plus which zones each window covers: a set, one zone or a span (`Geometry.span`)."
  - Line 46: "keeps windows whose zone ID survives a layout change" becomes "keeps windows whose zone IDs all survive a layout change".
  - Line 53, the `DragMonitor` bullet: after "(the modifier shows the overlay and release snaps)", insert "; holding the span key too stretches the target from an anchor zone".

- [ ] **Step 4: Final check**

Run: `swift build && swift test`
Expected: all tests pass. Don't commit (see Global Constraints).
