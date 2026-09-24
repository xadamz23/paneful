# Paneful Phase 1 — Drop Windows into Zones — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu bar app where holding a modifier while dragging a window shows that display's zones, and releasing over a zone snaps the window into it, with a configurable gap. Layouts are presets chosen per display from the menu.

**Architecture:** SwiftPM package with two targets. `PanefulCore` is pure Swift: split-tree layouts, presets, zone geometry with gap, coordinate flipping, the per-display `Arrangement`, and settings persistence. It is fully unit-tested. `Paneful` is the AppKit menu bar app: display discovery, the Accessibility wrapper, the tiling controller, the zone overlay and the drag monitor. It is verified by building the `.app` and running a manual checklist.

**Tech Stack:** Swift 6.4 (Command Line Tools only, no Xcode), SwiftPM, Swift Testing (`import Testing`), AppKit, ApplicationServices (Accessibility API), ServiceManagement.

**Spec:** `docs/superpowers/specs/2026-09-24-paneful-design.md`. This plan covers spec Phase 1. Phases 2 (linked resizing) and 3 (visual editor) get their own plans.

## Global Constraints

- No Xcode and no third-party dependencies. Build with `swift build` / `swift test`. Tests use Swift Testing, not XCTest (XCTest is unavailable without Xcode).
- Platform floor: macOS 14 (`.macOS(.v14)`, `LSMinimumSystemVersion` 14.0).
- App name `Paneful`, bundle ID `com.adamstahl.paneful`, menu bar only (`LSUIElement` = true).
- Settings file: `~/Library/Application Support/Paneful/settings.json`.
- Gap: a single value from 0 to 40 px, default 8. It applies between zones and at screen edges.
- Modifier: Shift, Option, Control or Command, default Shift.
- All geometry in `PanefulCore` uses **Accessibility coordinates**: origin at the top-left of the primary display, y increasing downward. Conversion from AppKit's bottom-left coordinates happens only in the app target, through `Coordinates.flip`.
- Resizing never mutates a saved `Layout`. (Phase 1 has no resizing, but no API may write `Arrangement.working` back into `Settings`.)
- Commit messages must not mention AI or co-authors. Never push.
- Split trees: `.vertical` means vertical dividers with children laid out left to right. `.horizontal` means horizontal dividers with children laid out top to bottom.

**Deliberate deviations from the spec** (already agreed as simplifications):
- The drag detection uses `NSEvent.addGlobalMonitorForEvents` rather than a raw `CGEventTap`. It gets the same events with less code and needs no extra permission for mouse events.
- The spec's "Thirds" and "3 columns" are the same layout, so there is one preset, "Thirds". "1+2" uses a 60/40 split.
- Phase 1 adds a **Gap ▸** menu (0, 4, 8, 12, 16, 24, 32, 40), because the gap slider only arrives with the editor in Phase 3.
- The permission prompt is the system's own Accessibility prompt, which includes an "Open System Settings" button. The menu also gets a "Grant Accessibility Access…" item while access is missing.
- The signing certificate is created by `scripts/make-signing-cert.sh` rather than by clicking through Keychain Access.

## Review Focus

1. **Dropping into a gap.** Releasing the mouse in the gap between two zones, or within half a gap of the screen edge, should snap to the nearer zone rather than do nothing. Test: Task 2 `pointInGapPicksNearerZone`.
2. **Non-primary displays.** Displays at negative x (the left PA248QV at x = −1920) or offset y (+240 in AppKit) should get correct zone rects and a correct flip. Test: Task 2 `grid2x2OnLeftDisplay`, `flipSecondaryDisplay`.
3. **Rounding with thirds.** Uneven fractions must never produce 1 px gaps or overlaps between neighbours, and the last zone must end flush with the edge. Test: Task 2 `thirdsTileExactlyWithoutDrift`.
4. **Bad settings files.** A missing, corrupt, partial or out-of-range settings file, or a saved layout that is invalid, should fall back to defaults (or Halves) rather than crash. Tests: Task 4 `corruptFileGivesDefaults`, `partialFileKeepsKnownValues`, `gapIsClamped`, `invalidSavedLayoutFallsBackToHalves`.
5. **Switching layouts with windows tiled.** When a display's layout changes, windows whose zone ID still exists should stay tiled, and the rest should become untiled. Test: Task 3 `rebasedKeepsWindowsWhoseZonesStillExist`.

## File Structure

```
Package.swift
.gitignore
Sources/PanefulCore/
  Layout.swift          Axis, Node, Layout, Node.zoneIDs, Node.isValid
  Presets.swift         Built-in layouts
  Geometry.swift        zoneRects (with gap), zone(at:) hit test
  Coordinates.swift     AppKit <-> Accessibility flip
  Arrangement.swift     Per-display working tree + window membership
  Settings.swift        Settings, ModifierKey, SettingsStore
Tests/PanefulCoreTests/
  LayoutTests.swift  GeometryTests.swift  CoordinatesTests.swift
  ArrangementTests.swift  SettingsTests.swift
Sources/Paneful/
  main.swift            App entry
  AppDelegate.swift     Status item, menu, permission polling
  Displays.swift        Display model + discovery
  WindowAccess.swift    The only file that calls the Accessibility API
  TilingController.swift Settings + arrangements + snap/untile/reset/refit
  OverlayController.swift Zone overlay windows + view
  DragMonitor.swift     Global mouse monitoring -> overlay + snap
Resources/Info.plist
scripts/build-app.sh  scripts/install.sh  scripts/make-signing-cert.sh
```

---

### Task 1: Package scaffold, layout model and presets

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/PanefulCore/Layout.swift`, `Sources/PanefulCore/Presets.swift`
- Test: `Tests/PanefulCoreTests/LayoutTests.swift`

**Interfaces:**
- Produces: `typealias ZoneID = Int`; `enum Axis { case horizontal, vertical }`; `indirect enum Node { case zone(ZoneID); case split(Axis, children: [Node], fractions: [Double]) }` with `var zoneIDs: [ZoneID]` and `var isValid: Bool`; `struct Layout { var name: String; var root: Node }`; `enum Presets` with `halves, thirds, sixtyForty, fortySixty, grid2x2, onePlusTwo, all`. Everything is `Codable, Equatable, Sendable` and `public`.

- [ ] **Step 1: Create the package and `.gitignore`**

`Package.swift` (the app target is added in Task 5, because SwiftPM rejects targets with no sources):
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Paneful",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PanefulCore"),
        .testTarget(name: "PanefulCoreTests", dependencies: ["PanefulCore"]),
    ]
)
```

`.gitignore`:
```
.build/
build/
.DS_Store
```

- [ ] **Step 2: Write the failing tests**

`Tests/PanefulCoreTests/LayoutTests.swift`:
```swift
import Foundation
import Testing
@testable import PanefulCore

@Suite struct LayoutTests {
    @Test(arguments: Presets.all)
    func presetsAreValid(_ layout: Layout) {
        #expect(layout.root.isValid, "\(layout.name)")
    }

    @Test func presetNamesAreUnique() {
        #expect(Set(Presets.all.map(\.name)).count == Presets.all.count)
    }

    @Test func zoneIDsAreDepthFirst() {
        #expect(Presets.grid2x2.root.zoneIDs == [0, 1, 2, 3])
        #expect(Presets.onePlusTwo.root.zoneIDs == [0, 1, 2])
    }

    @Test func rejectsMalformedSplits() {
        let z0 = Node.zone(0), z1 = Node.zone(1)
        #expect(!Node.split(.vertical, children: [z0, z1], fractions: [0.5, 0.2]).isValid)   // doesn't sum to 1
        #expect(!Node.split(.vertical, children: [z0, z1], fractions: [1.0]).isValid)        // count mismatch
        #expect(!Node.split(.vertical, children: [z0, z1], fractions: [1.0, 0]).isValid)     // zero-size child
        #expect(!Node.split(.vertical, children: [z0], fractions: [1.0]).isValid)            // single child
        #expect(!Node.split(.vertical, children: [z0, z0], fractions: [0.5, 0.5]).isValid)   // duplicate zone ID
        let nestedBad = Node.split(.vertical, children: [z0, .split(.horizontal, children: [z1, .zone(2)], fractions: [0.9, 0.9])], fractions: [0.5, 0.5])
        #expect(!nestedBad.isValid)
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(Presets.onePlusTwo)
        #expect(try JSONDecoder().decode(Layout.self, from: data) == Presets.onePlusTwo)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test`
Expected: the build fails with "cannot find 'Presets' in scope" (and similar for `Node` and `Layout`).

- [ ] **Step 4: Implement the layout model**

`Sources/PanefulCore/Layout.swift`:
```swift
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
```

`Sources/PanefulCore/Presets.swift`:
```swift
public enum Presets {
    public static let halves = Layout(
        name: "Halves",
        root: .split(.vertical, children: [.zone(0), .zone(1)], fractions: [0.5, 0.5]))

    public static let thirds = Layout(
        name: "Thirds",
        root: .split(.vertical, children: [.zone(0), .zone(1), .zone(2)], fractions: [1.0 / 3, 1.0 / 3, 1.0 / 3]))

    public static let sixtyForty = Layout(
        name: "60 / 40",
        root: .split(.vertical, children: [.zone(0), .zone(1)], fractions: [0.6, 0.4]))

    public static let fortySixty = Layout(
        name: "40 / 60",
        root: .split(.vertical, children: [.zone(0), .zone(1)], fractions: [0.4, 0.6]))

    public static let grid2x2 = Layout(
        name: "2 × 2",
        root: .split(.vertical, children: [
            .split(.horizontal, children: [.zone(0), .zone(1)], fractions: [0.5, 0.5]),
            .split(.horizontal, children: [.zone(2), .zone(3)], fractions: [0.5, 0.5]),
        ], fractions: [0.5, 0.5]))

    /// Large zone on the left, two stacked on the right.
    public static let onePlusTwo = Layout(
        name: "1 + 2",
        root: .split(.vertical, children: [
            .zone(0),
            .split(.horizontal, children: [.zone(1), .zone(2)], fractions: [0.5, 0.5]),
        ], fractions: [0.6, 0.4]))

    public static let all: [Layout] = [halves, thirds, sixtyForty, fortySixty, grid2x2, onePlusTwo]
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test`
Expected: all `LayoutTests` pass, with `presetsAreValid` run once for each of the 6 presets.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources/PanefulCore Tests/PanefulCoreTests
git commit -m "Add split-tree layout model and presets"
```

---

### Task 2: Geometry (zone rects with gap, hit testing) and coordinate flipping

**Files:**
- Create: `Sources/PanefulCore/Geometry.swift`, `Sources/PanefulCore/Coordinates.swift`
- Test: `Tests/PanefulCoreTests/GeometryTests.swift`, `Tests/PanefulCoreTests/CoordinatesTests.swift`

**Interfaces:**
- Consumes: `Node`, `ZoneID`, `Presets` (Task 1).
- Produces: `Geometry.zoneRects(_ node: Node, in frame: CGRect, gap: CGFloat) -> [ZoneID: CGRect]`; `Geometry.zone(at point: CGPoint, in rects: [ZoneID: CGRect], gap: CGFloat) -> ZoneID?`; `Coordinates.flip(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect`; `Coordinates.flip(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint`.

The test data is your real displays. In AppKit coordinates the ultrawide is (0, 0, 3440, 1440) with visible frame (0, 82, 3440, 1327), the right PA248QV is (3440, 240, 1920, 1200) and the left one is (−1920, 240, 1920, 1200).

- [ ] **Step 1: Write the failing tests**

`Tests/PanefulCoreTests/GeometryTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct GeometryTests {
    /// The ultrawide's usable area in Accessibility coordinates: below a 31 pt menu bar, above an 82 pt Dock.
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)

    @Test func halvesWithoutGapSplitFrameInTwo() {
        let rects = Geometry.zoneRects(Presets.halves.root, in: ultrawide, gap: 0)
        #expect(rects[0] == CGRect(x: 0, y: 31, width: 1720, height: 1327))
        #expect(rects[1] == CGRect(x: 1720, y: 31, width: 1720, height: 1327))
    }

    @Test func halvesWithGapInsetEdgesAndSeparateZones() {
        let rects = Geometry.zoneRects(Presets.halves.root, in: ultrawide, gap: 8)
        #expect(rects[0] == CGRect(x: 8, y: 39, width: 1708, height: 1311))
        #expect(rects[1] == CGRect(x: 1724, y: 39, width: 1708, height: 1311))
    }

    @Test func thirdsWithGap() {
        let rects = Geometry.zoneRects(Presets.thirds.root, in: ultrawide, gap: 8)
        #expect(rects[0] == CGRect(x: 8, y: 39, width: 1136, height: 1311))
        #expect(rects[1] == CGRect(x: 1152, y: 39, width: 1136, height: 1311))
        #expect(rects[2] == CGRect(x: 2296, y: 39, width: 1136, height: 1311))
    }

    @Test func thirdsTileExactlyWithoutDrift() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let rects = Geometry.zoneRects(Presets.thirds.root, in: frame, gap: 0)
        #expect(rects[0]!.minX == 0)
        #expect(rects[0]!.maxX == rects[1]!.minX)
        #expect(rects[1]!.maxX == rects[2]!.minX)
        #expect(rects[2]!.maxX == 1000)
        #expect([rects[0]!.width, rects[1]!.width, rects[2]!.width] == [333, 334, 333])
    }

    @Test func grid2x2OnLeftDisplay() {
        // Left PA248QV in Accessibility coordinates.
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1200)
        let rects = Geometry.zoneRects(Presets.grid2x2.root, in: left, gap: 10)
        #expect(rects[0] == CGRect(x: -1910, y: 10, width: 945, height: 585))
        #expect(rects[1] == CGRect(x: -1910, y: 605, width: 945, height: 585))
        #expect(rects[2] == CGRect(x: -955, y: 10, width: 945, height: 585))
        #expect(rects[3] == CGRect(x: -955, y: 605, width: 945, height: 585))
    }

    @Test func pointInsideZone() {
        let rects = Geometry.zoneRects(Presets.halves.root, in: ultrawide, gap: 8)
        #expect(Geometry.zone(at: CGPoint(x: 1000, y: 500), in: rects, gap: 8) == 0)
        #expect(Geometry.zone(at: CGPoint(x: 3000, y: 500), in: rects, gap: 8) == 1)
    }

    @Test func pointInGapPicksNearerZone() {
        // Zone 0 ends at x = 1716 and zone 1 starts at x = 1724, so the gap's midpoint is 1720.
        let rects = Geometry.zoneRects(Presets.halves.root, in: ultrawide, gap: 8)
        #expect(Geometry.zone(at: CGPoint(x: 1719, y: 500), in: rects, gap: 8) == 0)
        #expect(Geometry.zone(at: CGPoint(x: 1720, y: 500), in: rects, gap: 8) == 1)
        // Outer gap: within half a gap of zone 0's left edge (x = 8) counts, further out does not.
        #expect(Geometry.zone(at: CGPoint(x: 4, y: 500), in: rects, gap: 8) == 0)
        #expect(Geometry.zone(at: CGPoint(x: 3, y: 500), in: rects, gap: 8) == nil)
    }
}
```

`Tests/PanefulCoreTests/CoordinatesTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct CoordinatesTests {
    let primaryHeight: CGFloat = 1440

    @Test func flipPrimaryVisibleFrame() {
        let appKit = CGRect(x: 0, y: 82, width: 3440, height: 1327)
        #expect(Coordinates.flip(appKit, primaryScreenHeight: primaryHeight) == CGRect(x: 0, y: 31, width: 3440, height: 1327))
    }

    @Test func flipSecondaryDisplay() {
        let rightAppKit = CGRect(x: 3440, y: 240, width: 1920, height: 1200)
        let leftAppKit = CGRect(x: -1920, y: 240, width: 1920, height: 1200)
        #expect(Coordinates.flip(rightAppKit, primaryScreenHeight: primaryHeight) == CGRect(x: 3440, y: 0, width: 1920, height: 1200))
        #expect(Coordinates.flip(leftAppKit, primaryScreenHeight: primaryHeight) == CGRect(x: -1920, y: 0, width: 1920, height: 1200))
    }

    @Test func flipIsItsOwnInverse() {
        let rect = CGRect(x: -500, y: 123, width: 640, height: 480)
        #expect(Coordinates.flip(Coordinates.flip(rect, primaryScreenHeight: primaryHeight), primaryScreenHeight: primaryHeight) == rect)
    }

    @Test func flipPoint() {
        #expect(Coordinates.flip(CGPoint(x: 100, y: 1440), primaryScreenHeight: primaryHeight) == CGPoint(x: 100, y: 0))
        #expect(Coordinates.flip(CGPoint(x: -100, y: 0), primaryScreenHeight: primaryHeight) == CGPoint(x: -100, y: 1440))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test`
Expected: the build fails with "cannot find 'Geometry' in scope" and "cannot find 'Coordinates' in scope".

- [ ] **Step 3: Implement**

`Sources/PanefulCore/Geometry.swift`:
```swift
import CoreGraphics

public enum Geometry {
    /// Rects for every zone of `node` inside `frame`, with `gap` between zones and around the edges.
    /// All coordinates are Accessibility coordinates (top-left origin).
    public static func zoneRects(_ node: Node, in frame: CGRect, gap: CGFloat) -> [ZoneID: CGRect] {
        var rects: [ZoneID: CGRect] = [:]
        place(node, in: frame.insetBy(dx: gap, dy: gap), gap: gap, into: &rects)
        return rects
    }

    /// The zone under `point`. Each zone's rect is grown by half the gap, so a point in a gap belongs to the nearer zone.
    public static func zone(at point: CGPoint, in rects: [ZoneID: CGRect], gap: CGFloat) -> ZoneID? {
        rects.first { $0.value.insetBy(dx: -gap / 2, dy: -gap / 2).contains(point) }?.key
    }

    private static func place(_ node: Node, in rect: CGRect, gap: CGFloat, into rects: inout [ZoneID: CGRect]) {
        switch node {
        case .zone(let id):
            rects[id] = rect
        case .split(let axis, let children, let fractions):
            let isVertical = axis == .vertical
            let start = isVertical ? rect.minX : rect.minY
            let length = isVertical ? rect.width : rect.height
            let available = length - gap * CGFloat(children.count - 1)
            var begin = start
            var cumulative = 0.0
            for (index, child) in children.enumerated() {
                cumulative += fractions[index]
                // Round each boundary once so neighbours share it exactly; the last child ends flush with the rect.
                let end = index == children.count - 1
                    ? start + length
                    : (start + available * cumulative + gap * CGFloat(index)).rounded()
                let childRect = isVertical
                    ? CGRect(x: begin, y: rect.minY, width: end - begin, height: rect.height)
                    : CGRect(x: rect.minX, y: begin, width: rect.width, height: end - begin)
                place(child, in: childRect, gap: gap, into: &rects)
                begin = end + gap
            }
        }
    }
}
```

`Sources/PanefulCore/Coordinates.swift`:
```swift
import CoreGraphics

/// Converts between AppKit global coordinates (bottom-left origin, y up) and Accessibility
/// global coordinates (top-left origin of the primary display, y down). Each flip is its own inverse.
public enum Coordinates {
    public static func flip(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func flip(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore Tests/PanefulCoreTests
git commit -m "Add zone geometry with gap and coordinate flipping"
```

---

### Task 3: Arrangement

**Files:**
- Create: `Sources/PanefulCore/Arrangement.swift`
- Test: `Tests/PanefulCoreTests/ArrangementTests.swift`

**Interfaces:**
- Consumes: `Layout`, `Node`, `ZoneID` (Task 1); `Geometry.zoneRects` (Task 2).
- Produces: `struct Arrangement<Window: Hashable>` with `init(saved: Layout)`, `let saved: Layout`, `private(set) var working: Node`, `var tiledWindows: [Window]`, `func zone(of: Window) -> ZoneID?`, `func windows(in: ZoneID) -> [Window]`, `mutating func assign(_: Window, to: ZoneID)` (ignored if the zone doesn't exist), `mutating func remove(_: Window)`, `mutating func reset()`, `func rebased(on: Layout) -> Arrangement`, `func rects(in frame: CGRect, gap: CGFloat) -> [ZoneID: CGRect]`. The app uses `Arrangement<AXUIElement>` (`AXUIElement` is `Hashable` with CFEqual semantics). Tests use `String`.

- [ ] **Step 1: Write the failing tests**

`Tests/PanefulCoreTests/ArrangementTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct ArrangementTests {
    @Test func startsFromSavedLayoutWithNoWindows() {
        let arrangement = Arrangement<String>(saved: Presets.thirds)
        #expect(arrangement.working == Presets.thirds.root)
        #expect(arrangement.tiledWindows.isEmpty)
    }

    @Test func assignMovesWindowBetweenZones() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("safari", to: 0)
        arrangement.assign("safari", to: 1)
        #expect(arrangement.zone(of: "safari") == 1)
        #expect(arrangement.windows(in: 0).isEmpty)
        #expect(arrangement.windows(in: 1) == ["safari"])
    }

    @Test func zoneHoldsStackedWindows() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("a", to: 0)
        arrangement.assign("b", to: 0)
        #expect(Set(arrangement.windows(in: 0)) == ["a", "b"])
    }

    @Test func ignoresUnknownZone() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("a", to: 7)
        #expect(arrangement.zone(of: "a") == nil)
    }

    @Test func removeUntilesWindow() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("a", to: 0)
        arrangement.remove("a")
        #expect(arrangement.zone(of: "a") == nil)
        #expect(arrangement.tiledWindows.isEmpty)
    }

    @Test func resetRestoresSavedTreeAndKeepsWindows() {
        var arrangement = Arrangement<String>(saved: Presets.halves)
        arrangement.assign("a", to: 1)
        arrangement.reset()
        #expect(arrangement.working == Presets.halves.root)
        #expect(arrangement.zone(of: "a") == 1)
    }

    @Test func rebasedKeepsWindowsWhoseZonesStillExist() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.assign("left", to: 0)
        arrangement.assign("right", to: 2)
        let rebased = arrangement.rebased(on: Presets.halves)
        #expect(rebased.saved == Presets.halves)
        #expect(rebased.working == Presets.halves.root)
        #expect(rebased.zone(of: "left") == 0)
        #expect(rebased.zone(of: "right") == nil)
    }

    @Test func rectsComeFromWorkingTree() {
        let arrangement = Arrangement<String>(saved: Presets.grid2x2)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(arrangement.rects(in: frame, gap: 8) == Geometry.zoneRects(Presets.grid2x2.root, in: frame, gap: 8))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test`
Expected: the build fails with "cannot find 'Arrangement' in scope".

- [ ] **Step 3: Implement**

`Sources/PanefulCore/Arrangement.swift`:
```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore/Arrangement.swift Tests/PanefulCoreTests/ArrangementTests.swift
git commit -m "Add per-display arrangement"
```

---

### Task 4: Settings and persistence

**Files:**
- Create: `Sources/PanefulCore/Settings.swift`
- Test: `Tests/PanefulCoreTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `Layout`, `Node.isValid`, `Presets.halves` (Task 1).
- Produces: `enum ModifierKey: String, CaseIterable { case shift, option, control, command }`; `struct Settings { var gap: Double; var modifier: ModifierKey; var layouts: [String: Layout]; init(); func layout(forDisplay id: String) -> Layout }`; `struct SettingsStore { let url: URL; init(url:); static var defaultURL: URL; func load() -> Settings; func save(_: Settings) throws }`.

- [ ] **Step 1: Write the failing tests**

`Tests/PanefulCoreTests/SettingsTests.swift`:
```swift
import Foundation
import Testing
@testable import PanefulCore

@Suite struct SettingsTests {
    private func tempStore() -> SettingsStore {
        SettingsStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json"))
    }

    private func store(containing json: String) throws -> SettingsStore {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.url)
        return store
    }

    @Test func defaults() {
        let settings = Settings()
        #expect(settings.gap == 8)
        #expect(settings.modifier == .shift)
        #expect(settings.layouts.isEmpty)
    }

    @Test func missingFileGivesDefaults() {
        #expect(tempStore().load() == Settings())
    }

    @Test func corruptFileGivesDefaults() throws {
        #expect(try store(containing: "not json").load() == Settings())
        #expect(try store(containing: "[1, 2]").load() == Settings())
    }

    @Test func partialFileKeepsKnownValues() throws {
        let settings = try store(containing: #"{"gap": 12}"#).load()
        #expect(settings.gap == 12)
        #expect(settings.modifier == .shift)
        #expect(settings.layouts.isEmpty)
    }

    @Test func unknownModifierFallsBackToShift() throws {
        let settings = try store(containing: #"{"gap": 4, "modifier": "hyper"}"#).load()
        #expect(settings.gap == 4)
        #expect(settings.modifier == .shift)
    }

    @Test func gapIsClamped() throws {
        #expect(try store(containing: #"{"gap": 100}"#).load().gap == 40)
        #expect(try store(containing: #"{"gap": -5}"#).load().gap == 0)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = tempStore()
        var settings = Settings()
        settings.gap = 16
        settings.modifier = .option
        settings.layouts["B04199E5-A47E-4E90-8D02-B248A7B36CBE"] = Presets.thirds
        try store.save(settings)
        #expect(store.load() == settings)
    }

    @Test func unknownDisplayGetsHalves() {
        #expect(Settings().layout(forDisplay: "nope") == Presets.halves)
    }

    @Test func savedLayoutIsReturned() {
        var settings = Settings()
        settings.layouts["A"] = Presets.grid2x2
        #expect(settings.layout(forDisplay: "A") == Presets.grid2x2)
    }

    @Test func invalidSavedLayoutFallsBackToHalves() {
        var settings = Settings()
        settings.layouts["A"] = Layout(name: "Bad", root: .split(.vertical, children: [.zone(0), .zone(1)], fractions: [0.5, 0.2]))
        #expect(settings.layout(forDisplay: "A") == Presets.halves)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test`
Expected: the build fails with "cannot find 'Settings' in scope" and "cannot find 'SettingsStore' in scope".

- [ ] **Step 3: Implement**

`Sources/PanefulCore/Settings.swift`:
```swift
import Foundation

public enum ModifierKey: String, Codable, CaseIterable, Sendable {
    case shift, option, control, command
}

public struct Settings: Codable, Equatable, Sendable {
    /// Space in points between zones and at screen edges, 0 to 40.
    public var gap: Double = 8
    public var modifier: ModifierKey = .shift
    /// Saved layout per display, keyed by display UUID.
    public var layouts: [String: Layout] = [:]

    public init() {}

    /// Missing or unreadable values fall back to their defaults, so an old or hand-edited file never blocks launch.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gap = min(max((try? container.decodeIfPresent(Double.self, forKey: .gap)) ?? 8, 0), 40)
        modifier = (try? container.decodeIfPresent(ModifierKey.self, forKey: .modifier)) ?? .shift
        layouts = (try? container.decodeIfPresent([String: Layout].self, forKey: .layouts)) ?? [:]
    }

    /// The saved layout for a display, or Halves if none is saved or the saved one is invalid.
    public func layout(forDisplay id: String) -> Layout {
        if let layout = layouts[id], layout.root.isValid { return layout }
        return Presets.halves
    }
}

public struct SettingsStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paneful")
            .appendingPathComponent("settings.json")
    }

    /// Missing or corrupt files yield default settings.
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return settings
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore/Settings.swift Tests/PanefulCoreTests/SettingsTests.swift
git commit -m "Add settings with tolerant decoding and persistence"
```

---

### Task 5: App skeleton, bundle and signing scripts, permission handling

**Files:**
- Modify: `Package.swift` (add the executable target)
- Create: `Sources/Paneful/main.swift`, `Sources/Paneful/AppDelegate.swift`, `Sources/Paneful/WindowAccess.swift` (trust functions only for now), `Resources/Info.plist`, `scripts/build-app.sh`, `scripts/install.sh`, `scripts/make-signing-cert.sh`

**Interfaces:**
- Produces: `WindowAccess.isTrusted() -> Bool` and `WindowAccess.requestTrust()`. Also `AppDelegate`, which owns `statusItem` and a 2-second trust timer calling `updateTrust()`, and whose menu is rebuilt in `menuNeedsUpdate(_:)`. Tasks 6 and 7 extend both.

- [ ] **Step 1: Add the app target to `Package.swift`**

Replace the `targets:` array so the file reads:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Paneful",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Paneful", targets: ["Paneful"])],
    targets: [
        .target(name: "PanefulCore"),
        .executableTarget(
            name: "Paneful",
            dependencies: ["PanefulCore"],
            // AppKit callbacks (event monitors, timers) are main-thread but not annotated for Swift 6 isolation.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "PanefulCoreTests", dependencies: ["PanefulCore"]),
    ]
)
```

- [ ] **Step 2: Write the entry point, the trust wrapper and a minimal delegate**

`Sources/Paneful/main.swift`:
```swift
import AppKit

// Create the application before the delegate, which reads NSScreen during init.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

`Sources/Paneful/WindowAccess.swift`:
```swift
import AppKit
import ApplicationServices

/// The only place Paneful talks to the Accessibility API.
enum WindowAccess {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Adds Paneful to the Accessibility list and shows the system prompt, which links to System Settings.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
```

`Sources/Paneful/AppDelegate.swift`:
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var trustTimer: Timer?
    private var wasTrusted: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if !WindowAccess.isTrusted() { WindowAccess.requestTrust() }
        // Polling also catches permission being revoked while running.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updateTrust() }
        updateTrust()
    }

    private func updateTrust() {
        let trusted = WindowAccess.isTrusted()
        guard trusted != wasTrusted else { return }
        wasTrusted = trusted
        let symbol = trusted ? "rectangle.split.3x1" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Paneful")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !WindowAccess.isTrusted() {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        menu.addItem(item("Quit Paneful", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
```

- [ ] **Step 3: Write `Info.plist` and the scripts**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Paneful</string>
    <key>CFBundleIdentifier</key><string>com.adamstahl.paneful</string>
    <key>CFBundleName</key><string>Paneful</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

`scripts/build-app.sh`:
```bash
#!/bin/bash
# Builds build/Paneful.app from the SwiftPM package and signs it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Paneful
BIN="$(swift build -c release --show-bin-path)/Paneful"
APP=build/Paneful.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Paneful"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="Paneful Dev"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: '$IDENTITY' certificate not found; ad-hoc signing. Accessibility permission will reset on every rebuild. Run scripts/make-signing-cert.sh once." >&2
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
```

`scripts/install.sh`:
```bash
#!/bin/bash
# Builds Paneful, replaces /Applications/Paneful.app and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
pkill -x Paneful || true
rm -rf /Applications/Paneful.app
cp -R build/Paneful.app /Applications/
open /Applications/Paneful.app
```

`scripts/make-signing-cert.sh`:
```bash
#!/bin/bash
# One-time: creates a self-signed "Paneful Dev" code-signing identity in your login keychain,
# so Paneful's signature, and with it the Accessibility permission, stays the same across rebuilds.
set -euo pipefail
NAME="Paneful Dev"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "'$NAME' already exists."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem"

# macOS's `security import` can't read OpenSSL 3's default PKCS#12 encryption.
LEGACY=""
if openssl version | grep -q '^OpenSSL 3'; then LEGACY="-legacy"; fi
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:paneful

security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P paneful -T /usr/bin/codesign
echo "Created '$NAME'."
```

Run: `chmod +x scripts/*.sh`

- [ ] **Step 4: Build and check the bundle**

Run: `swift build && scripts/build-app.sh && plutil -lint build/Paneful.app/Contents/Info.plist && codesign -dv build/Paneful.app 2>&1 | grep -E 'Identifier|Authority|Signature'`
Expected: the build succeeds and plutil prints `OK`. Codesign shows `Identifier=com.adamstahl.paneful`, plus either `Authority=Paneful Dev`, or `Signature=adhoc` together with the warning if the certificate doesn't exist yet.

- [ ] **Step 5: Adam creates the signing certificate (manual, one time)**

Ask Adam to run `! scripts/make-signing-cert.sh`. It writes to his login keychain, so he has to run it himself.
Then run: `security find-identity -p codesigning | grep "Paneful Dev"`
Expected: one line containing `"Paneful Dev"`. It may also say `CSSMERR_TP_NOT_TRUSTED`, which is fine for local signing.
Then run: `scripts/build-app.sh && codesign -dv build/Paneful.app 2>&1 | grep Authority`
Expected: `Authority=Paneful Dev`.

- [ ] **Step 6: Install and launch**

Run: `scripts/install.sh && sleep 2 && pgrep -x Paneful`
Expected: prints a PID.
Manual check (Adam):
1. A warning-triangle icon appears in the menu bar, and the system Accessibility prompt appears.
2. After granting access in System Settings, the icon changes to the split-rectangle within about 2 seconds.
3. The menu shows "Quit Paneful", which quits the app.
4. Re-run `scripts/install.sh`. The app relaunches **still trusted**, which confirms the stable signature.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/Paneful Resources scripts
git commit -m "Add menu bar app skeleton with build, install and signing scripts"
```

---

### Task 6: Displays, window access, tiling controller and menus

**Files:**
- Create: `Sources/Paneful/Displays.swift`, `Sources/Paneful/TilingController.swift`
- Modify: `Sources/Paneful/WindowAccess.swift` (add window lookup and frame functions), `Sources/Paneful/AppDelegate.swift` (replace the whole file)

**Interfaces:**
- Consumes: `Arrangement`, `Settings`, `SettingsStore`, `Presets`, `Coordinates`, `ModifierKey` (Tasks 1–4).
- Produces:
  - `struct Display { id: String; name: String; screen: NSScreen; frame: CGRect; visibleFrame: CGRect }`, where both frames are in Accessibility coordinates.
  - `Displays.current() -> [Display]` and `Displays.primaryHeight: CGFloat`.
  - `WindowAccess.window(at: CGPoint) -> AXUIElement?`, `frame(of:) -> CGRect?`, `setFrame(_:of:) -> Bool` (false if the window is gone) and `isFullScreen(_:) -> Bool`.
  - `TilingController` with `settings`, `displays`, `gap: CGFloat`, `display(containing:)`, `zoneRects(for:)`, `snap(_:to:on:)`, `untile(_:)`, `resetArrangements()`, `setLayout(_:for:)`, `setGap(_:)`, `setModifier(_:)` and `refreshDisplays()`.
  - `ModifierKey.title` (AppKit-side extension).

- [ ] **Step 1: Add the display model**

`Sources/Paneful/Displays.swift`:
```swift
import AppKit
import PanefulCore

struct Display {
    /// Stable across reboots and reconnects: the display's UUID.
    let id: String
    let name: String
    let screen: NSScreen
    /// Whole display, in Accessibility coordinates.
    let frame: CGRect
    /// Usable area (excluding the menu bar and Dock), in Accessibility coordinates.
    let visibleFrame: CGRect
}

enum Displays {
    /// Height of the primary display, which anchors both coordinate systems.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func current() -> [Display] {
        let primaryHeight = self.primaryHeight
        return NSScreen.screens.map { screen in
            Display(
                id: uuid(of: screen),
                name: screen.localizedName,
                screen: screen,
                frame: Coordinates.flip(screen.frame, primaryScreenHeight: primaryHeight),
                visibleFrame: Coordinates.flip(screen.visibleFrame, primaryScreenHeight: primaryHeight))
        }
    }

    private static func uuid(of screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return "display-\(number)" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
```

- [ ] **Step 2: Add window lookup and frame functions to `WindowAccess`**

Append inside `enum WindowAccess` in `Sources/Paneful/WindowAccess.swift`:
```swift
    /// The standard window under a point (Accessibility coordinates), excluding Paneful's own windows.
    static func window(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != getpid() else { return nil }

        let window: AXUIElement
        if attribute(element, kAXRoleAttribute) as? String == kAXWindowRole {
            window = element
        } else if let value = attribute(element, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
            window = value as! AXUIElement
        } else {
            return nil
        }
        return attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole ? window : nil
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute),
              let size = attribute(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    /// Moves and resizes a window. Returns false if the window no longer exists.
    @discardableResult
    static func setFrame(_ frame: CGRect, of window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = AXUIElementCreateApplication(pid)
        // With AXEnhancedUserInterface on, some apps (Chrome, Electron) animate and land in the wrong place.
        let enhanced = attribute(app, "AXEnhancedUserInterface") as? Bool ?? false
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer { if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) } }

        var origin = frame.origin
        var size = frame.size
        let positionValue = AXValueCreate(.cgPoint, &origin)!
        let sizeValue = AXValueCreate(.cgSize, &size)!
        // Position, size, position: moving first lets the size fit on the target display; the second move
        // corrects apps that clamped the position against their old size.
        guard AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) != .invalidUIElement else { return false }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        return true
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        attribute(window, "AXFullScreen") as? Bool ?? false
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
```

- [ ] **Step 3: Add the tiling controller**

`Sources/Paneful/TilingController.swift`:
```swift
import AppKit
import PanefulCore

/// Owns settings and each display's arrangement, and moves windows into zones.
final class TilingController {
    private let store: SettingsStore
    private(set) var settings: Settings
    private(set) var displays: [Display] = []
    private var arrangements: [String: Arrangement<AXUIElement>] = [:]

    init(store: SettingsStore) {
        self.store = store
        settings = store.load()
        refreshDisplays()
    }

    var gap: CGFloat { CGFloat(settings.gap) }

    /// Re-reads connected displays. Arrangements restart from saved layouts, keeping tiled windows, which are re-fitted.
    func refreshDisplays() {
        displays = Displays.current()
        let old = arrangements
        arrangements = [:]
        for display in displays {
            let layout = settings.layout(forDisplay: display.id)
            arrangements[display.id] = old[display.id]?.rebased(on: layout) ?? Arrangement(saved: layout)
            refit(display)
        }
    }

    func display(containing point: CGPoint) -> Display? {
        displays.first { $0.frame.contains(point) }
    }

    func zoneRects(for display: Display) -> [ZoneID: CGRect] {
        arrangements[display.id]?.rects(in: display.visibleFrame, gap: gap) ?? [:]
    }

    func snap(_ window: AXUIElement, to zone: ZoneID, on display: Display) {
        guard let rect = zoneRects(for: display)[zone] else { return }
        untile(window)
        arrangements[display.id]?.assign(window, to: zone)
        WindowAccess.setFrame(rect, of: window)
    }

    func untile(_ window: AXUIElement) {
        for id in arrangements.keys { arrangements[id]?.remove(window) }
    }

    func resetArrangements() {
        for display in displays {
            arrangements[display.id]?.reset()
            refit(display)
        }
    }

    func setLayout(_ layout: Layout, for display: Display) {
        settings.layouts[display.id] = layout
        save()
        arrangements[display.id] = arrangements[display.id]?.rebased(on: layout) ?? Arrangement(saved: layout)
        refit(display)
    }

    func setGap(_ gap: Double) {
        settings.gap = gap
        save()
        displays.forEach(refit)
    }

    func setModifier(_ modifier: ModifierKey) {
        settings.modifier = modifier
        save()
    }

    private func refit(_ display: Display) {
        guard let arrangement = arrangements[display.id] else { return }
        let rects = arrangement.rects(in: display.visibleFrame, gap: gap)
        for window in arrangement.tiledWindows {
            guard let zone = arrangement.zone(of: window), let rect = rects[zone] else { continue }
            if !WindowAccess.setFrame(rect, of: window) { arrangements[display.id]?.remove(window) }
        }
    }

    private func save() {
        do { try store.save(settings) } catch { NSLog("Paneful: failed to save settings: \(error)") }
    }
}
```

- [ ] **Step 4: Replace `AppDelegate.swift` with the full menu**

`Sources/Paneful/AppDelegate.swift`:
```swift
import AppKit
import PanefulCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let tiling = TilingController(store: SettingsStore(url: SettingsStore.defaultURL))
    private var statusItem: NSStatusItem!
    private var trustTimer: Timer?
    private var wasTrusted: Bool?

    private static let gapChoices: [Double] = [0, 4, 8, 12, 16, 24, 32, 40]

    private struct LayoutChoice {
        let displayID: String
        let layout: Layout
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.tiling.refreshDisplays() }

        if !WindowAccess.isTrusted() { WindowAccess.requestTrust() }
        // Polling also catches permission being revoked while running.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updateTrust() }
        updateTrust()
    }

    private func updateTrust() {
        let trusted = WindowAccess.isTrusted()
        guard trusted != wasTrusted else { return }
        wasTrusted = trusted
        let symbol = trusted ? "rectangle.split.3x1" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Paneful")
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !WindowAccess.isTrusted() {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let header = NSMenuItem(title: "Layouts", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for display in tiling.displays {
            let current = tiling.settings.layout(forDisplay: display.id)
            let submenu = NSMenu()
            for preset in Presets.all {
                let choice = item(preset.name, #selector(chooseLayout(_:)))
                choice.representedObject = LayoutChoice(displayID: display.id, layout: preset)
                choice.state = preset == current ? .on : .off
                submenu.addItem(choice)
            }
            menu.addItem(parent(display.name, submenu))
        }
        menu.addItem(.separator())

        let gapMenu = NSMenu()
        for gap in Self.gapChoices {
            let choice = item("\(Int(gap)) px", #selector(chooseGap(_:)))
            choice.representedObject = gap
            choice.state = gap == tiling.settings.gap ? .on : .off
            gapMenu.addItem(choice)
        }
        menu.addItem(parent("Gap", gapMenu))

        let modifierMenu = NSMenu()
        for modifier in ModifierKey.allCases {
            let choice = item(modifier.title, #selector(chooseModifier(_:)))
            choice.representedObject = modifier
            choice.state = modifier == tiling.settings.modifier ? .on : .off
            modifierMenu.addItem(choice)
        }
        menu.addItem(parent("Modifier", modifierMenu))

        menu.addItem(item("Reset Arrangement", #selector(resetArrangement)))
        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit Paneful", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func parent(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? LayoutChoice,
              let display = tiling.displays.first(where: { $0.id == choice.displayID }) else { return }
        tiling.setLayout(choice.layout, for: display)
    }

    @objc private func chooseGap(_ sender: NSMenuItem) {
        guard let gap = sender.representedObject as? Double else { return }
        tiling.setGap(gap)
    }

    @objc private func chooseModifier(_ sender: NSMenuItem) {
        guard let modifier = sender.representedObject as? ModifierKey else { return }
        tiling.setModifier(modifier)
    }

    @objc private func resetArrangement() {
        tiling.resetArrangements()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Paneful: launch at login failed: \(error)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

extension ModifierKey {
    var title: String {
        switch self {
        case .shift: "Shift"
        case .option: "Option"
        case .control: "Control"
        case .command: "Command"
        }
    }
}
```

- [ ] **Step 5: Build, install and verify the menu and persistence**

Run: `swift build && swift test && scripts/install.sh`
Expected: the build succeeds with no errors, all tests pass, and the app relaunches.
Manual check (Adam):
1. The menu shows "Layouts", then **Sceptre O35**, **PA248QV (1)** and **PA248QV (2)**, each with six presets and **Halves** checked.
2. Choose Thirds on Sceptre O35 and 2 × 2 on PA248QV (1). Choose Gap ▸ 16 and Modifier ▸ Option. Reopening the menu shows those checkmarks.
3. Launch at Login gets a checkmark when clicked, and Paneful appears under System Settings ▸ General ▸ Login Items.

Then run: `cat ~/Library/Application\ Support/Paneful/settings.json`
Expected: `"gap" : 16`, `"modifier" : "option"`, and two different UUID keys under `layouts`.
Then run: `scripts/install.sh` and reopen the menu.
Expected: the same checkmarks, which shows the settings persisted.
Finally, set Gap back to 8 and Modifier back to Shift from the menu.

- [ ] **Step 6: Commit**

```bash
git add Sources/Paneful
git commit -m "Add display discovery, window access, tiling controller and menus"
```

---

### Task 7: Zone overlay and drag monitoring

**Files:**
- Create: `Sources/Paneful/OverlayController.swift`, `Sources/Paneful/DragMonitor.swift`
- Modify: `Sources/Paneful/AppDelegate.swift` (own a `DragMonitor`, start and stop it with trust)

**Interfaces:**
- Consumes: `TilingController.display(containing:)`, `zoneRects(for:)`, `gap`, `settings.modifier`, `snap(_:to:on:)`, `untile(_:)` (Task 6); `WindowAccess.window(at:)`, `frame(of:)`, `isFullScreen(_:)` (Task 6); `Geometry.zone(at:in:gap:)`, `Coordinates.flip` (Task 2); `Displays.primaryHeight` (Task 6).
- Produces: `OverlayController` with `show(on: Display, rects: [ZoneID: CGRect], highlighted: ZoneID?)` and `hide()`; `DragMonitor(tiling:overlay:)` with `start()` and `stop()`; `ModifierKey.flags: NSEvent.ModifierFlags`.

- [ ] **Step 1: Write the overlay**

`Sources/Paneful/OverlayController.swift`:
```swift
import AppKit
import PanefulCore

/// Click-through windows that draw the zones on the display under the cursor.
final class OverlayController {
    private var windows: [String: NSWindow] = [:]

    func show(on display: Display, rects: [ZoneID: CGRect], highlighted: ZoneID?) {
        for (id, window) in windows where id != display.id { window.orderOut(nil) }
        let window = windows[display.id] ?? makeWindow()
        windows[display.id] = window
        if window.frame != display.screen.frame { window.setFrame(display.screen.frame, display: false) }

        // Zone rects are in Accessibility coordinates; the view wants AppKit coordinates relative to the screen.
        let origin = display.screen.frame.origin
        let view = window.contentView as! ZoneOverlayView
        view.zones = rects.map { id, rect in
            (id: id, rect: Coordinates.flip(rect, primaryScreenHeight: Displays.primaryHeight).offsetBy(dx: -origin.x, dy: -origin.y))
        }
        view.highlighted = highlighted
        view.needsDisplay = true
        window.orderFrontRegardless()
    }

    func hide() {
        windows.values.forEach { $0.orderOut(nil) }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = ZoneOverlayView()
        return window
    }
}

final class ZoneOverlayView: NSView {
    var zones: [(id: ZoneID, rect: CGRect)] = []
    var highlighted: ZoneID?

    override func draw(_ dirtyRect: NSRect) {
        for zone in zones {
            let isHighlighted = zone.id == highlighted
            let path = NSBezierPath(roundedRect: zone.rect, xRadius: 10, yRadius: 10)
            NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.35 : 0.12).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.9 : 0.4).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}
```

- [ ] **Step 2: Write the drag monitor**

`Sources/Paneful/DragMonitor.swift`:
```swift
import AppKit
import PanefulCore

/// Watches global mouse events. Holding the modifier while dragging a window shows its display's zones;
/// releasing over a zone snaps the window there. A drag that ends anywhere else untiles the window.
final class DragMonitor {
    private let tiling: TilingController
    private let overlay: OverlayController
    private var monitor: Any?

    private var window: AXUIElement?
    private var startFrame: CGRect?
    private var isMoving = false
    private var target: (display: Display, zone: ZoneID)?

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
        endDrag()
    }

    private var cursor: CGPoint {
        Coordinates.flip(NSEvent.mouseLocation, primaryScreenHeight: Displays.primaryHeight)
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            window = WindowAccess.window(at: cursor)
            startFrame = window.flatMap(WindowAccess.frame(of:))
            isMoving = false
        case .leftMouseDragged, .flagsChanged:
            update(modifierHeld: event.modifierFlags.contains(tiling.settings.modifier.flags))
        case .leftMouseUp:
            finishDrag()
        default:
            break
        }
    }

    private func update(modifierHeld: Bool) {
        guard let window, let startFrame else { return }
        if !isMoving {
            guard let frame = WindowAccess.frame(of: window) else { return }
            if frame.size != startFrame.size {
                // Resizing, not moving: stop tracking this drag.
                endDrag()
                return
            }
            isMoving = frame.origin != startFrame.origin
            guard isMoving else { return }
        }
        guard modifierHeld, !WindowAccess.isFullScreen(window), let display = tiling.display(containing: cursor) else {
            target = nil
            overlay.hide()
            return
        }
        let rects = tiling.zoneRects(for: display)
        let zone = Geometry.zone(at: cursor, in: rects, gap: tiling.gap)
        target = zone.map { (display, $0) }
        overlay.show(on: display, rects: rects, highlighted: zone)
    }

    private func finishDrag() {
        defer { endDrag() }
        guard let window, isMoving else { return }
        if let target {
            // Let the window server finish the drag before resizing, or it can overwrite our frame.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [tiling] in
                tiling.snap(window, to: target.zone, on: target.display)
            }
        } else {
            tiling.untile(window)
        }
    }

    private func endDrag() {
        window = nil
        startFrame = nil
        isMoving = false
        target = nil
        overlay.hide()
    }
}

extension ModifierKey {
    var flags: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .option: .option
        case .control: .control
        case .command: .command
        }
    }
}
```

- [ ] **Step 3: Wire the monitor into `AppDelegate`**

In `Sources/Paneful/AppDelegate.swift`, add a property below `private let tiling = …`:
```swift
    private lazy var dragMonitor = DragMonitor(tiling: tiling, overlay: OverlayController())
```

Replace `updateTrust()` with:
```swift
    private func updateTrust() {
        let trusted = WindowAccess.isTrusted()
        guard trusted != wasTrusted else { return }
        wasTrusted = trusted
        if trusted { dragMonitor.start() } else { dragMonitor.stop() }
        let symbol = trusted ? "rectangle.split.3x1" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Paneful")
    }
```

- [ ] **Step 4: Build and install**

Run: `swift build && swift test && scripts/install.sh`
Expected: the build succeeds, all tests pass, and the app relaunches trusted.

- [ ] **Step 5: Manual checklist (Adam runs it and reports each item as pass or fail)**

Use the defaults (Halves everywhere, gap 8, Shift) unless an item says otherwise.
1. Hold Shift and drag a Safari window by its title bar on the ultrawide. Two zone outlines appear, and the zone under the cursor is highlighted and follows the cursor.
2. Release over the right zone. The window fills that zone with an 8 px gap from the screen edges and the menu bar and Dock areas.
3. Start a drag without Shift, then press Shift partway through. The overlay appears.
4. Shift-drag, then let go of Shift before releasing the mouse. The overlay disappears, and the window stays where you dropped it without snapping.
5. Shift-drag across to each PA248QV. The overlay moves to that display. After choosing 2 × 2 on one of them, that display shows four zones.
6. Release in the gap between two zones. The window snaps into the zone on the side you released on.
7. Hold Shift while resizing a window by its edge. No overlay appears.
8. Snap Terminal, Finder and one Electron app (VS Code or Slack). Each lands in its zone. Terminal may be a few pixels short because it sizes to its character grid, which is acceptable in Phase 1.
9. With two windows snapped, choose Gap ▸ 24. Both refit with the larger gap. Then choose Gap ▸ 8.
10. Switch the ultrawide from Thirds to Halves with windows in zones 0 and 2. The zone 0 window refits to the left half, and the zone 2 window is left alone because it's no longer tiled.
11. Close a snapped window, then choose Reset Arrangement. No crash, and the other windows refit.
12. Choose Modifier ▸ Option. Shift-drag shows no overlay and Option-drag does. Then set it back to Shift.
13. A plain drag of a snapped window, then Gap ▸ 24: the dragged window does **not** jump back into its zone, because it's untiled.

Fix any failures (use superpowers:systematic-debugging), rebuild with `scripts/install.sh`, and repeat the failed items.

- [ ] **Step 6: Commit**

```bash
git add Sources/Paneful
git commit -m "Add zone overlay and modifier-drag snapping"
```
