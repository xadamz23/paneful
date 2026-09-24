# Paneful Phase 2 — Linked Resizing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dragging the edge of a tiled window moves the divider under that edge, and the windows on the other side follow live. Zones never get smaller than 100 px. The saved layout never changes.

**Architecture:** The divider logic lives in `PanefulCore` and is pure and unit-tested:
- `Edge` and `EdgeMove`, plus `Geometry.movedEdges` and `Geometry.overflowingEdges`, which compare a window's frame with its zone.
- `Node.movingEdge`, which finds the nearest divider on a zone's edge and moves it, clamped to the minimum zone size.
- `Arrangement.moveEdge`, which changes only the working tree.

In the app, `DragMonitor` classifies each mouse press as a move or a resize by watching candidate windows' frames change. During a resize it passes each new frame to `TilingController.followResize`, which moves dividers and refits the other tiled windows whose zones changed. On mouse-up, `TilingController.finishResize` snaps every window to its zone. Windows that refused to shrink then push their divider back.

**Tech Stack:** Swift 6.4 (Command Line Tools only), SwiftPM, Swift Testing, AppKit, ApplicationServices.

**Spec:** `docs/superpowers/specs/2026-09-24-paneful-design.md`, section "Linked resizing" and Phase 2. Phase 1 plan for context: `docs/superpowers/plans/2026-09-24-paneful-phase1.md`.

## Global Constraints

- All Phase 1 constraints still apply:
  - No Xcode and no dependencies. Swift Testing, with the test target's explicit TestingMacros plugin flag kept in `Package.swift`.
  - macOS 14 floor.
  - Accessibility coordinates in `PanefulCore`.
  - Commit messages never mention AI or co-authors, and nothing is pushed.
- Resizing changes only `Arrangement.working`. `Arrangement.saved` and `Settings.layouts` are never written by resizing.
- The minimum zone size along the resized axis is **100 pt** (`TilingController.minZoneSize`).
- Neighbours follow **live** during the drag, not only on release.
- An outer edge has no neighbour. Resizing it moves nothing else, and the window stays tiled.
- All windows stacked in a zone resize together.

**Deliberate deviations from the spec:**
- The spec's resize detection used Accessibility observers with a 250 ms self-event suppression. Instead, the resized window's frame is read on each `leftMouseDragged` event from the existing global monitor. Paneful never sets the frame of the window being dragged, so no feedback loop can occur and no suppression is needed.
- Leaving the tiled state on close, minimise or app quit is detected when Paneful next tries to move the window (in `refit`), not through observers. Moving a window to another Space is not detected.
- The spec lists `LinkedResizer` as a unit. Its session state lives in `DragMonitor.Gesture` and its logic in `TilingController`, so no separate class is needed.
- This plan folds in four minor issues deferred from the Phase 1 review: an Accessibility messaging timeout, drag state reset on mouse-down, per-entry layout decoding, and pruning windows whose app has quit.

## Review Focus

1. **Resize handles in the gap.** macOS lets you grab a window's resize handle a few points *outside* the window, in the gap. Linking must still work. Test: Task 5 manual item 2.
2. **Dragging past the minimum.** The neighbour must stop at 100 pt and never be left overlapping after release. Tests: Task 2 `clampsToMinimumZoneSize` and `nestedSplitsKeepEveryZoneAboveMinimum`; Task 5 manual item 4.
3. **Neighbours with a minimum size larger than their new zone.** Some apps enforce a minimum width. After release, the divider must move back so that nothing overlaps. Tests: Task 1 `overflowOnlyCountsEdgesPastTheZone`; Task 5 manual item 5.
4. **Resizing an outer edge or an untiled window.** Nothing else should move. Tests: Task 2 `outerEdgeHasNoDivider`; Task 5 manual items 6 and 7.
5. **Ordinary drags inside a tiled window** (text selection, file drags, scrollbars). These must not resize anything or show the overlay, and must not add lag. Test: Task 5 manual item 8.

## File Structure

```
Sources/PanefulCore/
  Edge.swift            NEW  Edge, EdgeMove, Geometry.movedEdges / overflowingEdges
  Dividers.swift        NEW  Node.movingEdge (+ divider lookup, subtree helpers, minimum extents)
  Arrangement.swift     MOD  moveEdge
  Settings.swift        MOD  per-entry layout decoding
Tests/PanefulCoreTests/
  EdgeTests.swift       NEW
  DividerTests.swift    NEW
  ArrangementTests.swift MOD
  SettingsTests.swift   MOD
Sources/Paneful/
  WindowAccess.swift    MOD  configureTimeout, isGone, isMinimized
  TilingController.swift MOD minZoneSize, pressCandidates, isTiled, followResize, finishResize, smarter refit
  DragMonitor.swift     REWRITE  gesture state machine (pending / moving / resizing)
  AppDelegate.swift     MOD  call WindowAccess.configureTimeout() at launch
```

---

### Task 1: Edges and edge comparison

**Files:**
- Create: `Sources/PanefulCore/Edge.swift`
- Test: `Tests/PanefulCoreTests/EdgeTests.swift`

**Interfaces:**
- Consumes: `Axis` (Phase 1 `Layout.swift`).
- Produces:
  - `public enum Edge: CaseIterable, Sendable { case left, right, top, bottom }`, with internal `axis: Axis` (`.vertical` for left and right, `.horizontal` for top and bottom), `isTrailing: Bool` (true for right and bottom) and `coordinate(of: CGRect) -> CGFloat`.
  - `public struct EdgeMove: Equatable, Sendable { edge: Edge; position: CGFloat }`.
  - `Geometry.movedEdges(from rect: CGRect, to frame: CGRect, tolerance: CGFloat = 1) -> [EdgeMove]`.
  - `Geometry.overflowingEdges(of frame: CGRect, beyond rect: CGRect, tolerance: CGFloat = 1) -> [EdgeMove]`.
  - Results always come in `Edge.allCases` order: left, right, top, bottom.

- [ ] **Step 1: Write the failing tests**

`Tests/PanefulCoreTests/EdgeTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct EdgeTests {
    /// Halves zone 0 on the ultrawide with an 8 pt gap.
    let zone = CGRect(x: 8, y: 39, width: 1708, height: 1311)

    @Test func unchangedFrameMovesNoEdges() {
        #expect(Geometry.movedEdges(from: zone, to: zone).isEmpty)
    }

    @Test func subPointJitterIsIgnored() {
        #expect(Geometry.movedEdges(from: zone, to: zone.insetBy(dx: 0.5, dy: 0.5)).isEmpty)
    }

    @Test func rightEdgeDrag() {
        let frame = CGRect(x: 8, y: 39, width: 2008, height: 1311)
        #expect(Geometry.movedEdges(from: zone, to: frame) == [EdgeMove(edge: .right, position: 2016)])
    }

    @Test func leftEdgeDrag() {
        let frame = CGRect(x: 108, y: 39, width: 1608, height: 1311)
        #expect(Geometry.movedEdges(from: zone, to: frame) == [EdgeMove(edge: .left, position: 108)])
    }

    @Test func cornerDragMovesTwoEdges() {
        let frame = CGRect(x: 8, y: 39, width: 1808, height: 1211)
        #expect(Geometry.movedEdges(from: zone, to: frame) == [
            EdgeMove(edge: .right, position: 1816),
            EdgeMove(edge: .bottom, position: 1250),
        ])
    }

    @Test func overflowOnlyCountsEdgesPastTheZone() {
        // Refused to shrink: its right edge sticks out past the zone.
        let bigger = CGRect(x: 8, y: 39, width: 1808, height: 1311)
        #expect(Geometry.overflowingEdges(of: bigger, beyond: zone) == [EdgeMove(edge: .right, position: 1816)])
        // Smaller than its zone (Terminal's character grid) is not an overflow.
        let smaller = CGRect(x: 8, y: 39, width: 1600, height: 1300)
        #expect(Geometry.overflowingEdges(of: smaller, beyond: zone).isEmpty)
    }

    @Test func edgeCoordinatesAndAxes() {
        #expect(Edge.left.coordinate(of: zone) == 8)
        #expect(Edge.right.coordinate(of: zone) == 1716)
        #expect(Edge.top.coordinate(of: zone) == 39)
        #expect(Edge.bottom.coordinate(of: zone) == 1350)
        #expect(Edge.left.axis == .vertical && Edge.bottom.axis == .horizontal)
        #expect(Edge.right.isTrailing && Edge.bottom.isTrailing && !Edge.left.isTrailing && !Edge.top.isTrailing)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test`
Expected: the build fails with "cannot find 'EdgeMove' in scope" and "type 'Geometry' has no member 'movedEdges'", or similar.

- [ ] **Step 3: Implement**

`Sources/PanefulCore/Edge.swift`:
```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass (43 in total).

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore/Edge.swift Tests/PanefulCoreTests/EdgeTests.swift
git commit -m "Add edges and window-vs-zone edge comparison"
```

---

### Task 2: Moving dividers

**Files:**
- Create: `Sources/PanefulCore/Dividers.swift`
- Modify: `Sources/PanefulCore/Arrangement.swift` (add `moveEdge`)
- Test: `Tests/PanefulCoreTests/DividerTests.swift`, `Tests/PanefulCoreTests/ArrangementTests.swift`

**Interfaces:**
- Consumes: `Edge.axis`, `Edge.isTrailing` (Task 1); `Node`, `Presets` (Phase 1); `Geometry.zoneRects` (Phase 1).
- Produces:
  - `public func Node.movingEdge(_ edge: Edge, of zone: ZoneID, to position: CGFloat, in frame: CGRect, gap: CGFloat, minSize: CGFloat) -> Node?`. It returns `nil` when that edge has no divider (an outer edge) or there's no room.
  - `public mutating func Arrangement.moveEdge(_ edge: Edge, of zone: ZoneID, to position: CGFloat, in frame: CGRect, gap: CGFloat, minSize: CGFloat) -> Bool`. It returns true when the working tree changed or was re-clamped, and false when there's no divider. It's `@discardableResult`.

`position` is where the **zone's** edge should be: its right edge for `.right`, its left edge for `.left`, and so on. For a trailing edge, the divider's leading child ends at `position`. For a leading edge, it ends at `position − gap`.

- [ ] **Step 1: Write the failing tests**

`Tests/PanefulCoreTests/DividerTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct DividerTests {
    /// The ultrawide's usable area in Accessibility coordinates.
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)
    let gap: CGFloat = 8
    let minSize: CGFloat = 100

    private func rects(_ node: Node) -> [ZoneID: CGRect] {
        Geometry.zoneRects(node, in: ultrawide, gap: gap)
    }

    private func move(_ node: Node, _ edge: Edge, of zone: ZoneID, to position: CGFloat) -> Node? {
        node.movingEdge(edge, of: zone, to: position, in: ultrawide, gap: gap, minSize: minSize)
    }

    @Test func rightEdgeMovesSharedDivider() throws {
        let after = rects(try #require(move(Presets.halves.root, .right, of: 0, to: 2000)))
        #expect(after[0]!.maxX == 2000)
        #expect(after[1]!.minX == 2008)
        #expect(after[1]!.maxX == 3432)
    }

    @Test func leftEdgeOfNeighbourMovesSameDivider() throws {
        let after = rects(try #require(move(Presets.halves.root, .left, of: 1, to: 2008)))
        #expect(after[0]!.maxX == 2000)
        #expect(after[1]!.minX == 2008)
    }

    @Test func outerEdgeHasNoDivider() {
        #expect(move(Presets.halves.root, .left, of: 0, to: 100) == nil)
        #expect(move(Presets.halves.root, .top, of: 0, to: 100) == nil)
        #expect(move(Presets.halves.root, .right, of: 1, to: 3000) == nil)
    }

    @Test func clampsToMinimumZoneSize() throws {
        let narrow = rects(try #require(move(Presets.halves.root, .right, of: 0, to: 50)))
        #expect(narrow[0]!.width == 100)
        let wide = rects(try #require(move(Presets.halves.root, .right, of: 0, to: 3430)))
        #expect(wide[1]!.width == 100)
    }

    @Test func thirdsMoveOnlyTheDividerOnThatEdge() throws {
        let before = rects(Presets.thirds.root)
        let after = rects(try #require(move(Presets.thirds.root, .right, of: 1, to: 2400)))
        #expect(after[0] == before[0])
        #expect(after[1]!.maxX == 2400)
        #expect(after[2]!.minX == 2408)
        #expect(after[2]!.maxX == 3432)
    }

    @Test func grid2x2BottomEdgeMovesOnlyItsColumn() throws {
        let before = rects(Presets.grid2x2.root)
        let after = rects(try #require(move(Presets.grid2x2.root, .bottom, of: 0, to: 400)))
        #expect(after[0]!.maxY == 400)
        #expect(after[1]!.minY == 408)
        #expect(after[2] == before[2])
        #expect(after[3] == before[3])
    }

    @Test func grid2x2RightEdgeMovesTheColumnDivider() throws {
        let after = rects(try #require(move(Presets.grid2x2.root, .right, of: 1, to: 1500)))
        #expect(after[0]!.maxX == 1500)
        #expect(after[1]!.maxX == 1500)
        #expect(after[2]!.minX == 1508)
        #expect(after[3]!.minX == 1508)
    }

    @Test func nearestDividerWins() throws {
        // 1 + 2: zone 1's bottom edge sits on the nested divider, its left edge on the root one.
        let original = rects(Presets.onePlusTwo.root)
        let bottom = rects(try #require(move(Presets.onePlusTwo.root, .bottom, of: 1, to: 500)))
        #expect(bottom[1]!.maxY == 500)
        #expect(bottom[2]!.minY == 508)
        #expect(bottom[0] == original[0])
        let left = rects(try #require(move(Presets.onePlusTwo.root, .left, of: 1, to: 1808)))
        #expect(left[0]!.maxX == 1800)
        #expect(left[1]!.minX == 1808)
        #expect(left[2]!.minX == 1808)
    }

    @Test func nestedSplitsKeepEveryZoneAboveMinimum() throws {
        let nested = Node.split(.vertical, children: [
            .zone(0),
            .split(.vertical, children: [.zone(1), .zone(2)], fractions: [0.5, 0.5]),
        ], fractions: [0.5, 0.5])
        let after = rects(try #require(move(nested, .right, of: 0, to: 3430)))
        #expect(after[1]!.width >= 100)
        #expect(after[2]!.width >= 100)
    }

    @Test func noRoomLeavesLayoutAlone() {
        let tiny = CGRect(x: 0, y: 0, width: 150, height: 150)
        #expect(Presets.halves.root.movingEdge(.right, of: 0, to: 70, in: tiny, gap: 8, minSize: 100) == nil)
    }

    @Test func movedTreeStaysValid() throws {
        #expect(try #require(move(Presets.thirds.root, .right, of: 0, to: 900)).isValid)
    }
}
```

Append to the `ArrangementTests` suite in `Tests/PanefulCoreTests/ArrangementTests.swift`, before its closing brace:
```swift

    @Test func moveEdgeChangesWorkingButNeverSaved() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        let frame = CGRect(x: 0, y: 31, width: 3440, height: 1327)
        #expect(arrangement.moveEdge(.right, of: 0, to: 2000, in: frame, gap: 8, minSize: 100))
        #expect(arrangement.rects(in: frame, gap: 8)[0]!.maxX == 2000)
        #expect(arrangement.saved == Presets.halves)
        arrangement.reset()
        #expect(arrangement.working == Presets.halves.root)
    }

    @Test func moveOuterEdgeChangesNothing() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        let frame = CGRect(x: 0, y: 31, width: 3440, height: 1327)
        #expect(!arrangement.moveEdge(.left, of: 0, to: 300, in: frame, gap: 8, minSize: 100))
        #expect(arrangement.working == Presets.halves.root)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test`
Expected: the build fails with "value of type 'Node' has no member 'movingEdge'" and "value of type 'Arrangement<String>' has no member 'moveEdge'".

- [ ] **Step 3: Implement**

`Sources/PanefulCore/Dividers.swift`:
```swift
import CoreGraphics

extension Node {
    /// Moves the divider under `edge` of `zone` so that the zone's edge lands at `position` (clamped so every zone
    /// stays at least `minSize` along that axis). Returns nil if that edge has no divider, or there's no room.
    public func movingEdge(_ edge: Edge, of zone: ZoneID, to position: CGFloat, in frame: CGRect, gap: CGFloat, minSize: CGFloat) -> Node? {
        guard let (path, index) = divider(for: edge, of: zone),
              case .split(let axis, let children, var fractions) = subnode(at: path) else { return nil }

        // The split's rect is the bounding box of its zones' rects.
        let rects = Geometry.zoneRects(self, in: frame, gap: gap)
        guard let bounds = subnode(at: path).zoneIDs.compactMap({ rects[$0] }).reduce(CGRect?.none, { $0?.union($1) ?? $1 }) else { return nil }
        let isVertical = axis == .vertical
        let start = isVertical ? bounds.minX : bounds.minY
        let length = isVertical ? bounds.width : bounds.height
        let available = length - gap * CGFloat(children.count - 1)

        // Where child `index` must end: at the zone's edge, or one gap before the next child's leading edge.
        let end = edge.isTrailing ? position : position - gap
        let before = fractions[..<index].reduce(0, +)
        let pair = fractions[index] + fractions[index + 1]
        let lower = children[index].minExtent(along: axis, minSize: minSize, gap: gap) / available
        let upper = pair - children[index + 1].minExtent(along: axis, minSize: minSize, gap: gap) / available
        guard lower <= upper else { return nil }

        let fraction = min(max((end - start - gap * CGFloat(index)) / available - before, lower), upper)
        fractions[index] = fraction
        fractions[index + 1] = pair - fraction
        return replacing(at: path, with: .split(axis, children: children, fractions: fractions))
    }

    /// The divider nearest to `zone` on `edge`: the path of its split and the index of the child before it.
    func divider(for edge: Edge, of zone: ZoneID) -> (path: [Int], index: Int)? {
        var found: (path: [Int], index: Int)?
        var node = self
        var path: [Int] = []
        while case .split(let axis, let children, _) = node,
              let childIndex = children.firstIndex(where: { $0.zoneIDs.contains(zone) }) {
            if axis == edge.axis {
                if edge.isTrailing, childIndex < children.count - 1 { found = (path, childIndex) }
                if !edge.isTrailing, childIndex > 0 { found = (path, childIndex - 1) }
            }
            path.append(childIndex)
            node = children[childIndex]
        }
        return found
    }

    func subnode(at path: [Int]) -> Node {
        guard let first = path.first, case .split(_, let children, _) = self else { return self }
        return children[first].subnode(at: Array(path.dropFirst()))
    }

    func replacing(at path: [Int], with replacement: Node) -> Node {
        guard let first = path.first, case .split(let axis, var children, let fractions) = self else { return replacement }
        children[first] = children[first].replacing(at: Array(path.dropFirst()), with: replacement)
        return .split(axis, children: children, fractions: fractions)
    }

    /// The smallest length along `axis` this subtree can take while every zone in it keeps `minSize`.
    /// Children of a same-axis split scale with their fractions, so the tightest child sets the minimum.
    func minExtent(along axis: Axis, minSize: CGFloat, gap: CGFloat) -> CGFloat {
        switch self {
        case .zone:
            return minSize
        case .split(let splitAxis, let children, let fractions):
            let childMinimums = children.map { $0.minExtent(along: axis, minSize: minSize, gap: gap) }
            guard splitAxis == axis else { return childMinimums.max() ?? minSize }
            let content = zip(childMinimums, fractions).map { $0 / $1 }.max() ?? minSize
            return content + gap * CGFloat(children.count - 1)
        }
    }
}
```

In `Sources/PanefulCore/Arrangement.swift`, add after `reset()`:
```swift

    /// Moves the divider under `edge` of `zone` (see `Node.movingEdge`). Only the working tree changes.
    /// Returns false if that edge has no divider.
    @discardableResult
    public mutating func moveEdge(_ edge: Edge, of zone: ZoneID, to position: CGFloat, in frame: CGRect, gap: CGFloat, minSize: CGFloat) -> Bool {
        guard let moved = working.movingEdge(edge, of: zone, to: position, in: frame, gap: gap, minSize: minSize) else { return false }
        working = moved
        return true
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass (56 in total).

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore Tests/PanefulCoreTests
git commit -m "Move dividers under a zone's edge, clamped to a minimum zone size"
```

---

### Task 3: One bad saved layout no longer wipes the others

**Files:**
- Modify: `Sources/PanefulCore/Settings.swift` (`init(from:)`)
- Test: `Tests/PanefulCoreTests/SettingsTests.swift`

**Interfaces:**
- Consumes and produces: the same `Settings` API. Only decoding changes. The encoded format is unchanged (a JSON object keyed by display UUID).

- [ ] **Step 1: Write the failing test**

Append to the `SettingsTests` suite, before its closing brace:
```swift

    @Test func oneBadLayoutKeepsTheOthers() throws {
        let thirds = String(decoding: try JSONEncoder().encode(Presets.thirds), as: UTF8.self)
        let settings = try store(containing: #"{"layouts": {"A": \#(thirds), "B": {"name": "x"}}}"#).load()
        #expect(settings.layout(forDisplay: "A") == Presets.thirds)
        #expect(settings.layouts["B"] == nil)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test`
Expected: `oneBadLayoutKeepsTheOthers` fails, because display A gets Halves.

- [ ] **Step 3: Implement**

In `Sources/PanefulCore/Settings.swift`, replace the line
```swift
        layouts = (try? container.decodeIfPresent([String: Layout].self, forKey: .layouts)) ?? [:]
```
with:
```swift
        // Decode each display's layout on its own, so one bad entry doesn't discard the rest.
        if let entries = try? container.nestedContainer(keyedBy: DisplayKey.self, forKey: .layouts) {
            for key in entries.allKeys {
                if let layout = try? entries.decode(Layout.self, forKey: key) { layouts[key.stringValue] = layout }
            }
        }
```
Then add inside `struct Settings`, after `layout(forDisplay:)`:
```swift

    private struct DisplayKey: CodingKey {
        let stringValue: String
        init(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass (57 in total), including the existing `saveThenLoadRoundTrips` and `corruptFileGivesDefaults`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore/Settings.swift Tests/PanefulCoreTests/SettingsTests.swift
git commit -m "Decode saved layouts per display"
```

---

### Task 4: Tiling controller support for linked resizing

**Files:**
- Modify: `Sources/Paneful/WindowAccess.swift`, `Sources/Paneful/TilingController.swift`, `Sources/Paneful/AppDelegate.swift`

**Interfaces:**
- Consumes: `Geometry.movedEdges` and `overflowingEdges` (Task 1); `Arrangement.moveEdge` (Task 2).
- Produces:
  - `WindowAccess.configureTimeout()`, `isGone(_:) -> Bool` and `isMinimized(_:) -> Bool`.
  - On `TilingController`: `static let minZoneSize: CGFloat = 100`, `pressCandidates(at: CGPoint) -> [AXUIElement]`, `isTiled(_:) -> Bool`, `@discardableResult followResize(of: AXUIElement, to: CGRect) -> Bool` and `finishResize(of: AXUIElement)`.
  - `refit` now skips windows whose rect didn't change and untiles windows that are closed, minimised or belong to an app that has quit.

- [ ] **Step 1: Add the window checks and a messaging timeout to `WindowAccess`**

In `Sources/Paneful/WindowAccess.swift`, add after `requestTrust()`:
```swift

    /// Caps every Accessibility call, so a hung app can stall Paneful for at most a quarter second.
    static func configureTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }
```
Then add after `isFullScreen(_:)`:
```swift

    static func isMinimized(_ window: AXUIElement) -> Bool {
        attribute(window, kAXMinimizedAttribute) as? Bool ?? false
    }

    /// True once the window's app has quit. Its elements then fail with .cannotComplete rather than .invalidUIElement.
    static func isGone(_ window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return true }
        return NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true
    }
```

- [ ] **Step 2: Call the timeout at launch**

In `Sources/Paneful/AppDelegate.swift` `applicationDidFinishLaunching`, add as the first line:
```swift
        WindowAccess.configureTimeout()
```

- [ ] **Step 3: Add the resizing API to `TilingController` and make `refit` selective**

In `Sources/Paneful/TilingController.swift`:

Add below `private var arrangements …`:
```swift

    /// No zone gets narrower (or shorter) than this while resizing.
    static let minZoneSize: CGFloat = 100
    /// macOS resize handles reach a few points outside a window, into the gap.
    private static let resizeHandleReach: CGFloat = 6
```

Add after `untile(_:)`:
```swift

    func isTiled(_ window: AXUIElement) -> Bool {
        location(of: window) != nil
    }

    /// Windows a press at `point` might move or resize: the window under the cursor, plus tiled windows whose
    /// zone is within resize-handle reach, because the handles extend into the gap outside the window.
    func pressCandidates(at point: CGPoint) -> [AXUIElement] {
        var candidates: [AXUIElement] = []
        if let hit = WindowAccess.window(at: point) { candidates.append(hit) }
        guard let display = display(containing: point), let arrangement = arrangements[display.id] else { return candidates }
        let reach = Self.resizeHandleReach
        for (zone, rect) in arrangement.rects(in: display.visibleFrame, gap: gap)
        where rect.insetBy(dx: -reach, dy: -reach).contains(point) {
            for window in arrangement.windows(in: zone) where !candidates.contains(window) {
                candidates.append(window)
            }
        }
        return candidates
    }

    /// Follows a live resize of a tiled window. It moves the dividers under the edges that moved and refits the
    /// other windows whose zones changed; the resized window itself is left to the user's drag.
    /// Returns whether any divider was involved.
    @discardableResult
    func followResize(of window: AXUIElement, to frame: CGRect) -> Bool {
        guard let (display, zone) = location(of: window), var arrangement = arrangements[display.id] else { return false }
        let before = arrangement.rects(in: display.visibleFrame, gap: gap)
        guard let rect = before[zone] else { return false }
        var linked = false
        for move in Geometry.movedEdges(from: rect, to: frame) {
            if arrangement.moveEdge(move.edge, of: zone, to: move.position, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) {
                linked = true
            }
        }
        guard linked else { return false }
        arrangements[display.id] = arrangement
        refit(display, changedFrom: before, except: window)
        return true
    }

    /// Ends a linked resize: snaps every tiled window on the display to its zone, then lets any window that
    /// refused to shrink (a minimum size) push its divider back so nothing overlaps.
    func finishResize(of window: AXUIElement) {
        guard let (display, _) = location(of: window) else { return }
        refit(display)
        guard var arrangement = arrangements[display.id] else { return }
        let rects = arrangement.rects(in: display.visibleFrame, gap: gap)
        var moved = false
        for tiled in arrangement.tiledWindows {
            guard let zone = arrangement.zone(of: tiled), let rect = rects[zone],
                  let actual = WindowAccess.frame(of: tiled) else { continue }
            for move in Geometry.overflowingEdges(of: actual, beyond: rect) {
                if arrangement.moveEdge(move.edge, of: zone, to: move.position, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) {
                    moved = true
                }
            }
        }
        guard moved else { return }
        arrangements[display.id] = arrangement
        refit(display)
    }

    private func location(of window: AXUIElement) -> (display: Display, zone: ZoneID)? {
        for display in displays {
            if let zone = arrangements[display.id]?.zone(of: window) { return (display, zone) }
        }
        return nil
    }
```

Replace the existing `refit(_:)` with:
```swift
    /// Moves tiled windows on `display` to their zone rects. Given `old` rects, it moves only windows whose rect
    /// changed. Windows that were closed, minimised or whose app quit are untiled instead.
    private func refit(_ display: Display, changedFrom old: [ZoneID: CGRect]? = nil, except skipped: AXUIElement? = nil) {
        guard let arrangement = arrangements[display.id] else { return }
        let rects = arrangement.rects(in: display.visibleFrame, gap: gap)
        for window in arrangement.tiledWindows where window != skipped {
            guard let zone = arrangement.zone(of: window), let rect = rects[zone], old?[zone] != rect else { continue }
            if WindowAccess.isGone(window) || WindowAccess.isMinimized(window) || !WindowAccess.setFrame(rect, of: window) {
                arrangements[display.id]?.remove(window)
            }
        }
    }
```

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | grep -E "error|warning: [^s]" | grep -v "search path"; swift test 2>&1 | tail -1`
Expected: no errors or warnings (other than the known `ld` search-path warnings), and the tests still pass (57).

- [ ] **Step 5: Commit**

```bash
git add Sources/Paneful
git commit -m "Add linked-resize support to the tiling controller"
```

---

### Task 5: Drag monitor gestures (move vs resize) and manual verification

**Files:**
- Modify: `Sources/Paneful/DragMonitor.swift` (replace everything above `extension ModifierKey`)

**Interfaces:**
- Consumes:
  - From Task 4: `TilingController.pressCandidates(at:)`, `isTiled(_:)`, `followResize(of:to:)` and `finishResize(of:)`.
  - From Phase 1: `display(containing:)`, `zoneRects(for:)`, `gap`, `settings.modifier`, `snap(_:to:on:)` and `untile(_:)`; `WindowAccess.frame(of:)` and `isFullScreen(_:)`; `OverlayController.show` and `hide`; `Geometry.zone(at:in:gap:)`.
- Produces: `DragMonitor` with the same public surface as before (`init(tiling:overlay:)`, `start()` and `stop()`). `AppDelegate` needs no changes.

- [ ] **Step 1: Replace the drag monitor**

In `Sources/Paneful/DragMonitor.swift`, replace everything from the top of the file down to (but not including) `extension ModifierKey {` with:
```swift
import AppKit
import PanefulCore

/// Watches global mouse events and turns each press into one gesture:
/// - moving a window: holding the modifier shows its display's zones. Releasing over one snaps the window there;
///   releasing anywhere else untiles it.
/// - resizing a tiled window: the dividers under the dragged edges follow live, resizing the neighbouring windows.
final class DragMonitor {
    private enum Gesture {
        case none
        /// Pressed; waiting for one of the candidate windows to move or resize.
        case pending(candidates: [(window: AXUIElement, frame: CGRect)], pressedAt: CGPoint)
        case moving(AXUIElement, target: (display: Display, zone: ZoneID)?)
        case resizing(AXUIElement, linked: Bool)
    }

    /// A press that has moved no window after the cursor travels this far is ignored (text selection, file drags).
    private static let classifyDistance: CGFloat = 24

    private let tiling: TilingController
    private let overlay: OverlayController
    private var monitor: Any?
    private var gesture = Gesture.none

    init(tiling: TilingController, overlay: OverlayController) {
        self.tiling = tiling
        self.overlay = overlay
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        gesture = .none
        overlay.hide()
    }

    private var cursor: CGPoint {
        Coordinates.flip(NSEvent.mouseLocation, primaryScreenHeight: Displays.primaryHeight)
    }

    private func handle(_ event: NSEvent) {
        let modifierHeld = event.modifierFlags.contains(tiling.settings.modifier.flags)
        switch event.type {
        case .leftMouseDown:
            press()
        case .leftMouseDragged:
            drag(modifierHeld: modifierHeld)
        case .flagsChanged:
            if case .moving(let window, _) = gesture { updateMove(window, modifierHeld: modifierHeld) }
        case .leftMouseUp:
            release()
        default:
            break
        }
    }

    private func press() {
        // A mouse-up swallowed by Mission Control or a Space switch must not leave the last gesture behind.
        overlay.hide()
        let candidates = tiling.pressCandidates(at: cursor).compactMap { window in
            WindowAccess.frame(of: window).map { (window: window, frame: $0) }
        }
        gesture = candidates.isEmpty ? .none : .pending(candidates: candidates, pressedAt: cursor)
    }

    private func drag(modifierHeld: Bool) {
        switch gesture {
        case .none:
            break
        case .pending(let candidates, let pressedAt):
            classify(candidates, pressedAt: pressedAt, modifierHeld: modifierHeld)
        case .moving(let window, _):
            updateMove(window, modifierHeld: modifierHeld)
        case .resizing(let window, let linked):
            guard let frame = WindowAccess.frame(of: window) else { return }
            let moved = tiling.followResize(of: window, to: frame)
            gesture = .resizing(window, linked: linked || moved)
        }
    }

    /// Decides what the press is doing from the first candidate whose frame changed:
    /// same size means moving, a new size means resizing.
    private func classify(_ candidates: [(window: AXUIElement, frame: CGRect)], pressedAt: CGPoint, modifierHeld: Bool) {
        for candidate in candidates {
            guard let frame = WindowAccess.frame(of: candidate.window), frame != candidate.frame else { continue }
            if WindowAccess.isFullScreen(candidate.window) {
                gesture = .none
            } else if frame.size == candidate.frame.size {
                gesture = .moving(candidate.window, target: nil)
                updateMove(candidate.window, modifierHeld: modifierHeld)
            } else if tiling.isTiled(candidate.window) {
                gesture = .resizing(candidate.window, linked: tiling.followResize(of: candidate.window, to: frame))
            } else {
                gesture = .none
            }
            return
        }
        if hypot(cursor.x - pressedAt.x, cursor.y - pressedAt.y) > Self.classifyDistance { gesture = .none }
    }

    private func updateMove(_ window: AXUIElement, modifierHeld: Bool) {
        guard modifierHeld, let display = tiling.display(containing: cursor) else {
            gesture = .moving(window, target: nil)
            overlay.hide()
            return
        }
        let rects = tiling.zoneRects(for: display)
        let zone = Geometry.zone(at: cursor, in: rects, gap: tiling.gap)
        gesture = .moving(window, target: zone.map { (display, $0) })
        overlay.show(on: display, rects: rects, highlighted: zone)
    }

    private func release() {
        let finished = gesture
        gesture = .none
        overlay.hide()
        // Let the window server and the app finish the drag first, or they can overwrite our frames.
        switch finished {
        case .moving(let window, let target?):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [tiling] in
                tiling.snap(window, to: target.zone, on: target.display)
            }
        case .moving(let window, nil):
            tiling.untile(window)
        case .resizing(let window, true):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [tiling] in
                tiling.finishResize(of: window)
            }
        default:
            break
        }
    }
}

```

- [ ] **Step 2: Build, test and install**

Run: `swift build 2>&1 | grep -E "error|warning: [^s]" | grep -v "search path"; swift test 2>&1 | tail -1; scripts/install.sh`
Expected: no errors, the tests pass (57), and the app relaunches still trusted.

- [ ] **Step 3: Manual checklist (Adam runs it and reports each item as pass or fail)**

Start from Halves on the ultrawide with gap 8, with two windows snapped left and right. macOS's built-in tiling stays off.
1. Drag the right edge of the left window to the right. The right window's left edge follows live, and the 8 pt gap stays constant. On release, both windows sit exactly in their zones.
2. Grab the same shared edge from the gap, slightly outside the left window. It still resizes both.
3. Drag the left edge of the right window. The left window follows.
4. Drag the shared edge almost to the screen edge. The other window stops shrinking at about 100 pt. After release there's no overlap.
5. Tile System Settings, which has a minimum width, and shrink it by dragging its neighbour's edge toward it. After release, the divider moves back to System Settings' minimum width with no overlap.
6. Drag the left window's outer (screen-side) edge. Nothing else moves, and the window keeps its new size. Then choose Reset Arrangement: everything goes back to the saved Halves.
7. Resize an untiled window. Nothing else moves.
8. Select text inside a tiled window by dragging, and drag a file out of a tiled Finder window. No window resizes, no overlay appears, and there's no lag.
9. Choose 2 × 2 on a PA248QV and tile four windows. Dragging the bottom edge of the top-left window moves only the left column's divider. Dragging its right edge moves the column divider for all four.
10. With two windows stacked in one zone, resize its shared edge. Both stacked windows follow.
11. After resizing, open the Layout menu. Halves is still checked. Quit and relaunch: the saved layout is unchanged (`cat ~/Library/Application\ Support/Paneful/settings.json` shows fractions 0.5 and 0.5).
12. Minimise a tiled window, then change the gap. The minimised window stays minimised and isn't pulled back.
13. Quit an app with a tiled window (e.g. TextEdit), then change the gap. No hang or error, and the other windows refit.
14. Phase 1 still works: Shift-drag a window into a zone, and plain-drag it back out.

Fix any failures (use superpowers:systematic-debugging), rebuild with `scripts/install.sh`, and repeat the failed items.

- [ ] **Step 4: Commit**

```bash
git add Sources/Paneful/DragMonitor.swift
git commit -m "Classify drags into moves and linked resizes"
```
