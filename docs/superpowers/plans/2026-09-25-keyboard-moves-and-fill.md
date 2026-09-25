# Keyboard Moves and Fill Zones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ctrl+Option + an arrow key moves the focused window one zone left, right, up or down on its own display, and a "Fill Zones" menu item fills every display's empty zones with untiled windows.

**Architecture:**
- Two pure functions in `PanefulCore`, both written test-first:
  - `Geometry.neighbour` (`Navigation.swift`) picks the zone next to a window's block in a direction.
  - `Geometry.fill` (`Fill.swift`) pairs untiled windows with empty zones, nearest first.
- The app wires them up:
  - `HotKeys.swift` registers Carbon hotkeys.
  - `WindowAccess` finds the focused and visible windows.
  - `TilingController` calls the existing `snap(_:to:on:)`, so keyboard and fill snaps behave exactly like drops.

**Tech Stack:** Swift 6.4, SwiftPM, Swift Testing, AppKit, Carbon (`RegisterEventHotKey`). Command Line Tools only, with no Xcode.

**Spec:** `docs/superpowers/specs/2026-09-25-keyboard-moves-and-fill-design.md`

## Global Constraints

- **Branch:** work on `keyboard-moves-and-fill`, one commit per task. Commit messages must not mention AI or co-authorship. Don't push; there's no remote.
- **Where code goes:**
  - New logic goes in `PanefulCore`, test first.
  - The app target is wiring and is verified by hand.
  - `WindowAccess` stays the only file that calls the Accessibility API.
- **Platform rules:**
  - No SwiftUI macros.
  - No third-party dependencies.
  - macOS 14 is the minimum.
  - The app target stays in `.swiftLanguageMode(.v5)`.
- **Geometry:** all geometry uses Accessibility coordinates (top-left origin, y down). Directions reuse `Edge`: ← `.left`, → `.right`, ↑ `.top`, ↓ `.bottom`.
- **Hotkeys:** fixed at Ctrl+Option + ←/→/↑/↓, swallowed, and registered only while Accessibility is trusted.
- **Keyboard moves never change display.** At the display's edge nothing happens. Ties go to the lowest zone ID.
- **Fill Zones:**
  - It fills empty zones only.
  - Leftover windows are left untiled and unmoved.
  - Tiled windows are never touched.
  - Ties go by zone ID, then by window order.
- **Tests:** run them with `swift test`. Ignore the `ld: warning: search path …` lines.

## Review Focus

1. **The focused window is Paneful's own editor, a dialog or a sheet, or there's no window at all.** The keys must do nothing. This is app-side (`WindowAccess.focusedWindow`), so it's in the Task 3 manual checklist.
2. **A window on a side display, pressed toward the ultrawide.** It must stay put and never jump displays. Pinned by `edgesGoNowhere` tests in Task 1, and by the Task 3 checklist.
3. **Fill Zones while a tiled window has been closed.** Its zone must count as empty. `fillZones` calls `forgetClosedWindows()` first; this is in the Task 4 checklist.
4. **Ties:** a span over a whole row pressed down, and a window exactly between two zone centres. The result must be the same every time. Pinned by `spanAcrossTopRowMovesDownToLowestID` (Task 1) and `tiesGoToTheLowestZoneThenTheFirstWindow` (Task 2).
5. **Accessibility permission revoked while running.** The hotkeys must stop, so apps get Ctrl+Option+arrows back. `HotKeys.stop()` is called from `updateTrust`; this is in the Task 3 checklist.

---

### Task 1: Zone neighbour in a direction

**Files:**
- Create: `Sources/PanefulCore/Navigation.swift`
- Test: `Tests/PanefulCoreTests/NavigationTests.swift`

**Interfaces:**
- Consumes: `Geometry.union(of: Set<ZoneID>, in: [ZoneID: CGRect]) -> CGRect?` (in `Span.swift`), `Edge` and `Edge.axis` (in `Edge.swift`, where `axis` is internal to the module).
- Produces: `Geometry.neighbour(of zones: Set<ZoneID>, toward edge: Edge, in rects: [ZoneID: CGRect]) -> ZoneID?`

Zone IDs used in the tests:
- **Thirds:** A = 0, B = 1, C = 2.
- **2 × 2** (`Presets.grid2x2`): TL = 0, BL = 1, TR = 2, BR = 3.
- **1 + 2:** left = 0, top-right = 1, bottom-right = 2.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PanefulCoreTests/NavigationTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct NavigationTests {
    let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
    /// Thirds at gap 8: A = 0, B = 1, C = 2.
    var thirds: [ZoneID: CGRect] { Geometry.zoneRects(Presets.thirds.root, in: frame, gap: 8) }
    /// 2 × 2 at gap 8: TL = 0, BL = 1, TR = 2, BR = 3.
    var grid: [ZoneID: CGRect] { Geometry.zoneRects(Presets.grid2x2.root, in: frame, gap: 8) }

    @Test func thirdsLeftAndRight() {
        #expect(Geometry.neighbour(of: [0], toward: .right, in: thirds) == 1)
        #expect(Geometry.neighbour(of: [1], toward: .right, in: thirds) == 2)
        #expect(Geometry.neighbour(of: [2], toward: .left, in: thirds) == 1)
        #expect(Geometry.neighbour(of: [1], toward: .left, in: thirds) == 0)
    }

    @Test func thirdsEdgesGoNowhere() {
        #expect(Geometry.neighbour(of: [2], toward: .right, in: thirds) == nil)
        #expect(Geometry.neighbour(of: [0], toward: .left, in: thirds) == nil)
        #expect(Geometry.neighbour(of: [1], toward: .top, in: thirds) == nil)
        #expect(Geometry.neighbour(of: [1], toward: .bottom, in: thirds) == nil)
    }

    @Test func gridAllFourDirections() {
        #expect(Geometry.neighbour(of: [0], toward: .right, in: grid) == 2)
        #expect(Geometry.neighbour(of: [0], toward: .bottom, in: grid) == 1)
        #expect(Geometry.neighbour(of: [3], toward: .top, in: grid) == 2)
        #expect(Geometry.neighbour(of: [3], toward: .left, in: grid) == 1)
        #expect(Geometry.neighbour(of: [2], toward: .left, in: grid) == 0)
    }

    @Test func gridEdgesGoNowhere() {
        #expect(Geometry.neighbour(of: [0], toward: .top, in: grid) == nil)
        #expect(Geometry.neighbour(of: [0], toward: .left, in: grid) == nil)
        #expect(Geometry.neighbour(of: [3], toward: .bottom, in: grid) == nil)
        #expect(Geometry.neighbour(of: [3], toward: .right, in: grid) == nil)
    }

    @Test func onePlusTwo() {
        let rects = Geometry.zoneRects(Presets.onePlusTwo.root, in: frame, gap: 8)
        // 1 and 2 are equally far from the left zone's centre, so the lower ID wins.
        #expect(Geometry.neighbour(of: [0], toward: .right, in: rects) == 1)
        #expect(Geometry.neighbour(of: [1], toward: .left, in: rects) == 0)
        #expect(Geometry.neighbour(of: [2], toward: .left, in: rects) == 0)
        #expect(Geometry.neighbour(of: [1], toward: .bottom, in: rects) == 2)
        #expect(Geometry.neighbour(of: [2], toward: .top, in: rects) == 1)
    }

    @Test func unevenColumnPicksTheZoneNearestTheCentre() {
        // Right column split 30 / 70: zone 2's centre (y 650) is nearer the left zone's centre (y 500) than zone 1's (y 150).
        let node = Node.split(.vertical, children: [
            .zone(0),
            .split(.horizontal, children: [.zone(1), .zone(2)], fractions: [0.3, 0.7]),
        ], fractions: [0.5, 0.5])
        let rects = Geometry.zoneRects(node, in: CGRect(x: 0, y: 0, width: 1000, height: 1000), gap: 0)
        #expect(Geometry.neighbour(of: [0], toward: .right, in: rects) == 2)
    }

    @Test func spanMovesToTheZonePastItsEdge() {
        #expect(Geometry.neighbour(of: [0, 1], toward: .right, in: thirds) == 2)
        #expect(Geometry.neighbour(of: [0, 1], toward: .left, in: thirds) == nil)
        #expect(Geometry.neighbour(of: [1, 2], toward: .left, in: thirds) == 0)
    }

    @Test func spanAcrossTopRowMovesDownToLowestID() {
        // BL and BR are equally far from the span's centre.
        #expect(Geometry.neighbour(of: [0, 2], toward: .bottom, in: grid) == 1)
        #expect(Geometry.neighbour(of: [0, 2], toward: .top, in: grid) == nil)
    }

    @Test func touchingZonesAtGapZeroAreNeighbours() {
        let rects = Geometry.zoneRects(Presets.grid2x2.root, in: frame, gap: 0)
        // BR only touches TL at a corner, so it's not a candidate.
        #expect(Geometry.neighbour(of: [0], toward: .right, in: rects) == 2)
        #expect(Geometry.neighbour(of: [0], toward: .bottom, in: rects) == 1)
    }

    @Test func unknownZonesGoNowhere() {
        #expect(Geometry.neighbour(of: [9], toward: .right, in: thirds) == nil)
        #expect(Geometry.neighbour(of: [], toward: .right, in: thirds) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter NavigationTests`
Expected: a build failure, because `Geometry` has no member `neighbour`.

- [ ] **Step 3: Write the implementation**

Create `Sources/PanefulCore/Navigation.swift`:

```swift
import CoreGraphics

extension Geometry {
    /// The zone next to the block `zones` covers, toward `edge`: of the zones wholly past that edge that overlap the
    /// block on the other axis, the nearest ones along the direction, then the one whose centre is closest to the
    /// block's centre on the other axis, then the lowest ID. Nil at the display's edge.
    public static func neighbour(of zones: Set<ZoneID>, toward edge: Edge, in rects: [ZoneID: CGRect]) -> ZoneID? {
        guard let block = union(of: zones, in: rects) else { return nil }
        let horizontal = edge.axis == .vertical
        // How far past the block's edge a rect starts; negative if it isn't wholly past it.
        let distance = { (rect: CGRect) -> CGFloat in
            switch edge {
            case .left: return block.minX - rect.maxX
            case .right: return rect.minX - block.maxX
            case .top: return block.minY - rect.maxY
            case .bottom: return rect.minY - block.maxY
            }
        }
        let overlapsAcross = { (rect: CGRect) -> Bool in
            horizontal ? rect.minY < block.maxY && rect.maxY > block.minY : rect.minX < block.maxX && rect.maxX > block.minX
        }
        let candidates = rects.filter { !zones.contains($0.key) && distance($0.value) >= 0 && overlapsAcross($0.value) }
        guard let nearest = candidates.values.map(distance).min() else { return nil }
        let offCentre = { (rect: CGRect) -> CGFloat in horizontal ? abs(rect.midY - block.midY) : abs(rect.midX - block.midX) }
        return candidates
            .filter { distance($0.value) < nearest + 0.5 }
            .min { (offCentre($0.value), $0.key) < (offCentre($1.value), $1.key) }?
            .key
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter NavigationTests`
Expected: all 10 tests pass.

Then run `swift test`.
Expected: all tests pass, 138 in total.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore/Navigation.swift Tests/PanefulCoreTests/NavigationTests.swift
git commit -m "Find the zone next to a window in a direction"
```

---

### Task 2: Fill pairing

**Files:**
- Create: `Sources/PanefulCore/Fill.swift`
- Test: `Tests/PanefulCoreTests/FillTests.swift`

**Interfaces:**
- Produces: `Geometry.fill<W>(empty: [ZoneID: CGRect], windows: [(W, CGPoint)]) -> [(W, ZoneID)]`. Each point is a window's centre. Each window and each zone appears at most once in the result.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PanefulCoreTests/FillTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct FillTests {
    /// Thirds at gap 0 on 1200 × 800: A = 0, B = 1, C = 2, with centres at x 200, 600 and 1000, all at y 400.
    let thirds = Geometry.zoneRects(Presets.thirds.root, in: CGRect(x: 0, y: 0, width: 1200, height: 800), gap: 0)

    private func fill(_ empty: [ZoneID: CGRect], _ windows: [(String, CGPoint)]) -> [String: ZoneID] {
        Dictionary(uniqueKeysWithValues: Geometry.fill(empty: empty, windows: windows))
    }

    @Test func eachWindowGoesToTheZoneItIsOver() {
        let windows = [("right", CGPoint(x: 950, y: 400)), ("left", CGPoint(x: 150, y: 400)), ("middle", CGPoint(x: 620, y: 400))]
        #expect(fill(thirds, windows) == ["left": 0, "middle": 1, "right": 2])
    }

    @Test func theClosestPairIsMadeFirst() {
        // Both are over A. "near" is 10 from A's centre, so it gets A; "far" takes the next nearest zone, B.
        let windows = [("far", CGPoint(x: 350, y: 400)), ("near", CGPoint(x: 210, y: 400))]
        #expect(fill(thirds, windows) == ["near": 0, "far": 1])
    }

    @Test func moreWindowsThanZonesLeavesTheRestOut() {
        let empty = thirds.filter { $0.key == 1 }
        let windows = [("a", CGPoint(x: 100, y: 400)), ("b", CGPoint(x: 590, y: 400)), ("c", CGPoint(x: 1100, y: 400))]
        #expect(fill(empty, windows) == ["b": 1])
    }

    @Test func moreZonesThanWindows() {
        #expect(fill(thirds, [("only", CGPoint(x: 1000, y: 400))]) == ["only": 2])
    }

    @Test func nothingToFill() {
        #expect(fill([:], [("a", .zero)]) == [:])
        #expect(fill(thirds, []) == [:])
    }

    @Test func tiesGoToTheLowestZoneThenTheFirstWindow() {
        // Exactly between A's and B's centres.
        #expect(fill(thirds, [("x", CGPoint(x: 400, y: 400))]) == ["x": 0])
        let windows = [("first", CGPoint(x: 600, y: 400)), ("second", CGPoint(x: 600, y: 400))]
        #expect(fill(thirds.filter { $0.key == 1 }, windows) == ["first": 1])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter FillTests`
Expected: a build failure, because `Geometry` has no member `fill`.

- [ ] **Step 3: Write the implementation**

Create `Sources/PanefulCore/Fill.swift`:

```swift
import CoreGraphics

extension Geometry {
    /// Pairs windows (by centre) with `empty` zones, closest pair first, until zones or windows run out, so each
    /// window moves as little as possible. Ties go to the lower zone ID, then the earlier window.
    public static func fill<W>(empty: [ZoneID: CGRect], windows: [(W, CGPoint)]) -> [(W, ZoneID)] {
        var zones = empty
        var remaining = windows
        var pairs: [(W, ZoneID)] = []
        while !zones.isEmpty && !remaining.isEmpty {
            var best: (distance: CGFloat, zone: ZoneID, index: Int)?
            for (index, (_, centre)) in remaining.enumerated() {
                for (zone, rect) in zones {
                    let candidate = (distance: hypot(centre.x - rect.midX, centre.y - rect.midY), zone: zone, index: index)
                    if best.map({ candidate < $0 }) ?? true { best = candidate }
                }
            }
            guard let best else { break }
            pairs.append((remaining.remove(at: best.index).0, best.zone))
            zones[best.zone] = nil
        }
        return pairs
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter FillTests`
Expected: all 6 tests pass.

Then run `swift test`.
Expected: all tests pass, 144 in total.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanefulCore/Fill.swift Tests/PanefulCoreTests/FillTests.swift
git commit -m "Pair untiled windows with empty zones, nearest first"
```

---

### Task 3: Keyboard moves in the app

**Files:**
- Create: `Sources/Paneful/HotKeys.swift`
- Modify: `Sources/Paneful/WindowAccess.swift` (add `focusedWindow()` and an `isStandard` helper)
- Modify: `Sources/Paneful/TilingController.swift` (add `moveFocusedWindow(toward:)`)
- Modify: `Sources/Paneful/AppDelegate.swift` (own `HotKeys`; start and stop it in `updateTrust`)

**Interfaces:**
- Consumes: `Geometry.neighbour(of:toward:in:)` (Task 1). Existing code: `Geometry.zone(at:in:gap:)`, `TilingController.snap(_:to:on:)`, `location(of:)`, `display(containing:)`, `zoneRects(for:)`.
- Produces:
  - `WindowAccess.focusedWindow() -> AXUIElement?`
  - `WindowAccess.isStandard(_:) -> Bool` (private)
  - `HotKeys(onPress: @escaping (Edge) -> Void)` with `start()` and `stop()`
  - `TilingController.moveFocusedWindow(toward: Edge)`

There are no automated tests for this task; the app target is verified by hand.

- [ ] **Step 1: Add `focusedWindow()` to `WindowAccess`**

In `Sources/Paneful/WindowAccess.swift`, replace the last line of `window(at:)`:

```swift
        return attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole ? window : nil
```

with:

```swift
        return isStandard(window) ? window : nil
```

Then add this after `window(at:)`:

```swift
    /// The frontmost app's focused window, if it's a standard window that isn't minimised or full screen.
    /// Nil when Paneful itself is frontmost.
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let value = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        return isStandard(window) && !isMinimized(window) && !isFullScreen(window) ? window : nil
    }

    private static func isStandard(_ window: AXUIElement) -> Bool {
        attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
    }
```

- [ ] **Step 2: Add `moveFocusedWindow(toward:)` to `TilingController`**

In `Sources/Paneful/TilingController.swift`, add this after `dragOut(_:releasedAt:)`:

```swift
    /// Moves the focused window one zone toward `edge` on the display it's tiled on, never onto another display;
    /// at the display's edge nothing happens. An untiled window is snapped into the zone under its centre instead.
    func moveFocusedWindow(toward edge: Edge) {
        guard let window = WindowAccess.focusedWindow() else { return }
        if let (display, zones) = location(of: window) {
            guard let zone = Geometry.neighbour(of: zones, toward: edge, in: zoneRects(for: display)) else { return }
            snap(window, to: [zone], on: display)
        } else {
            guard let frame = WindowAccess.frame(of: window) else { return }
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            guard let display = display(containing: centre),
                  let zone = Geometry.zone(at: centre, in: zoneRects(for: display), gap: gap) else { return }
            snap(window, to: [zone], on: display)
        }
    }
```

- [ ] **Step 3: Create `HotKeys.swift`**

Create `Sources/Paneful/HotKeys.swift`:

```swift
import Carbon.HIToolbox
import PanefulCore

/// Ctrl+Option + the arrow keys. Carbon hotkeys need no extra permission, and apps never see the keystrokes.
final class HotKeys {
    private static let keys: [(code: Int, edge: Edge)] = [
        (kVK_LeftArrow, .left), (kVK_RightArrow, .right), (kVK_UpArrow, .top), (kVK_DownArrow, .bottom),
    ]
    /// Tags Paneful's hotkeys ("Pnfl").
    private static let signature: OSType = 0x506E_666C

    private let onPress: (Edge) -> Void
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init(onPress: @escaping (Edge) -> Void) {
        self.onPress = onPress
    }

    func start() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard let context, id.signature == HotKeys.signature, HotKeys.keys.indices.contains(Int(id.id)) else {
                return OSStatus(eventNotHandledErr)
            }
            Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue().onPress(HotKeys.keys[Int(id.id)].edge)
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)

        for (index, key) in Self.keys.enumerated() {
            var hotKey: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key.code), UInt32(controlKey | optionKey),
                                EventHotKeyID(signature: Self.signature, id: UInt32(index)),
                                GetApplicationEventTarget(), 0, &hotKey)
            if let hotKey { hotKeys.append(hotKey) }
        }
    }

    func stop() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
```

- [ ] **Step 4: Wire `HotKeys` into `AppDelegate`**

In `Sources/Paneful/AppDelegate.swift`, add this after the `dragMonitor` property:

```swift
    private lazy var hotKeys = HotKeys { [tiling = self.tiling] edge in tiling.moveFocusedWindow(toward: edge) }
```

In `updateTrust()`, replace:

```swift
        if trusted { dragMonitor.start() } else { dragMonitor.stop() }
```

with:

```swift
        if trusted {
            dragMonitor.start()
            hotKeys.start()
        } else {
            dragMonitor.stop()
            hotKeys.stop()
        }
```

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | grep -v 'ld: warning'`
Expected: `Build complete!` with no errors.

Then run `swift test`.
Expected: all 144 tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Paneful/HotKeys.swift Sources/Paneful/WindowAccess.swift Sources/Paneful/TilingController.swift Sources/Paneful/AppDelegate.swift
git commit -m "Move the focused window between zones with Ctrl+Option+arrows"
```

- [ ] **Step 7: Manual check (Adam)**

Run `scripts/install.sh`, then check on the three displays:
- [ ] **Sceptre in Thirds:**
  - a window in A: → goes to B, → goes to C, and → again does nothing;
  - from A, ←, ↑ and ↓ all do nothing.
- [ ] **A PA248QV in 2 × 2:**
  - from TL: → goes to TR, then ↓ goes to BR, ← goes to BL, and ↑ goes to TL;
  - every edge press does nothing.
- [ ] **A PA248QV in 1 + 2:** → from the left zone goes to top-right, then ↓ goes to bottom-right, and ← goes back to the left zone.
- [ ] **A window at a side display's inner edge**, pressed toward the ultrawide: it stays on its display.
- [ ] **A spanning window:**
  - one spanning Thirds A+B, pressed →, goes to C;
  - one spanning the 2 × 2 top row, pressed ↓, goes to BL.
- [ ] **An untiled window:** any arrow snaps it into the zone under its centre, and the next arrow moves it.
- [ ] **After a keyboard move:** resizing the shared edge still resizes the neighbour.
- [ ] **Dragging out a window that was snapped by keyboard** restores its size from before the snap.
- [ ] **With Paneful's editor focused**, the arrows do nothing and the editor doesn't react.
- [ ] **Accessibility revoked in System Settings:** Ctrl+Option+arrows reach apps again. Re-grant it afterwards.

---

### Task 4: Fill Zones in the app

**Files:**
- Modify: `Sources/Paneful/WindowAccess.swift` (add `visibleWindows()`)
- Modify: `Sources/Paneful/TilingController.swift` (add `fillZones()`)
- Modify: `Sources/Paneful/AppDelegate.swift` (add the "Fill Zones" menu item)

**Interfaces:**
- Consumes: `Geometry.fill(empty:windows:)` (Task 2) and `WindowAccess.isStandard(_:)` (Task 3). Existing code: `forgetClosedWindows()`, `isTiled(_:)`, `snap(_:to:on:)`, `Arrangement.windows(in:)`.
- Produces: `WindowAccess.visibleWindows() -> [AXUIElement]` and `TilingController.fillZones()`.

There are no automated tests for this task; the app target is verified by hand.

- [ ] **Step 1: Add `visibleWindows()` to `WindowAccess`**

In `Sources/Paneful/WindowAccess.swift`, add this after `focusedWindow()`:

```swift
    /// Standard windows of visible regular apps, except Paneful's, that aren't minimised or full screen.
    /// Accessibility lists only the current Space's windows, so windows on other Spaces never appear.
    static func visibleWindows() -> [AXUIElement] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != getpid() }
            .flatMap { app in
                attribute(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
            }
            .filter { isStandard($0) && !isMinimized($0) && !isFullScreen($0) }
    }
```

- [ ] **Step 2: Add `fillZones()` to `TilingController`**

In `Sources/Paneful/TilingController.swift`, add this after `moveFocusedWindow(toward:)`:

```swift
    /// Puts untiled visible windows into every display's empty zones: each goes to the nearest free zone on the
    /// display its centre is on. Leftover windows and tiled windows are left alone.
    func fillZones() {
        forgetClosedWindows()
        let untiled = WindowAccess.visibleWindows().filter { !isTiled($0) }.compactMap { window in
            WindowAccess.frame(of: window).map { (window, CGPoint(x: $0.midX, y: $0.midY)) }
        }
        for display in displays {
            guard let arrangement = arrangements[display.id] else { continue }
            let empty = zoneRects(for: display).filter { arrangement.windows(in: $0.key).isEmpty }
            let windows = untiled.filter { display.frame.contains($0.1) }
            for (window, zone) in Geometry.fill(empty: empty, windows: windows) {
                snap(window, to: [zone], on: display)
            }
        }
    }
```

- [ ] **Step 3: Add the menu item**

In `Sources/Paneful/AppDelegate.swift` `menuNeedsUpdate(_:)`, replace:

```swift
        menu.addItem(item("Reset Arrangement", #selector(resetArrangement)))
```

with:

```swift
        menu.addItem(item("Fill Zones", #selector(fillZones)))
        menu.addItem(item("Reset Arrangement", #selector(resetArrangement)))
```

Then add this after `resetArrangement()`:

```swift
    @objc private func fillZones() {
        tiling.fillZones()
    }
```

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | grep -v 'ld: warning'`
Expected: `Build complete!` with no errors.

Then run `swift test`.
Expected: all 144 tests still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Paneful/WindowAccess.swift Sources/Paneful/TilingController.swift Sources/Paneful/AppDelegate.swift
git commit -m "Fill every display's empty zones from the menu"
```

- [ ] **Step 6: Manual check (Adam)**

Run `scripts/install.sh`, then:
- [ ] **Sceptre in Thirds, nothing tiled, three windows roughly left, middle and right:** Fill Zones puts each into the zone it's over.
- [ ] **Partly filled** (B tiled, two untiled windows): A and C fill, and B's window doesn't move.
- [ ] **Over-full** (four untiled windows, one empty zone): only the nearest window moves, and the others stay exactly where they were.
- [ ] **Each display fills from its own windows.** No window moves to another display.
- [ ] **Close a tiled window, then Fill Zones:** its zone fills.
- [ ] **Minimised windows, hidden apps' windows and windows on another Space** are never pulled in.
- [ ] **Dragging out a filled window** restores its size from before the fill.

---

### Task 5: Docs

**Files:**
- Modify: `docs/history/README.md`
- Modify: `docs/history/design-decisions.md`
- Modify: `docs/history/macos-gotchas.md`
- Modify: `CLAUDE.md`

There's no code in this task. Match each file's existing style.

- [ ] **Step 1: `docs/history/README.md`**
  - **Timeline:** add a row after "Auto-reset empty displays":

    ```markdown
    | 2026-09-25 | Keyboard moves and Fill Zones | Ctrl+Option + an arrow moves the focused window to the zone left, right, above or below, on its own display only; at an edge nothing happens, and an untiled window first snaps into the zone under its centre. Carbon hotkeys need no extra permission and are swallowed. "Fill Zones" in the menu puts untiled windows into every display's empty zones, nearest first, leaving extra windows alone. Both go through `snap`, so they behave exactly like a drop. |
    ```
  - **Where it stands:** change "plus four follow-ups: …" to five, adding "moving windows between zones by keyboard and filling empty zones". Update the test count to 144.
  - **Code map:**
    - under `Sources/PanefulCore/`, add ``- `Navigation.swift`, `Fill.swift`: the zone next to a window in a direction, and pairing untiled windows with empty zones.``
    - under `Sources/Paneful/`, add ``- `HotKeys.swift`: the Ctrl+Option + arrow hotkeys.``

- [ ] **Step 2: `docs/history/design-decisions.md`**
  - In the first product row, change "Shortcuts and edge-snapping were left out of v1." to "Edge-snapping was left out; keyboard moves came later (Ctrl+Option + arrows)."
  - Add these product rows at the end of the table:

    ```markdown
    | **Keyboard moves with Ctrl+Option + arrows, within one display** | Moving a window one zone over shouldn't need the mouse. Keys are spatial (the zone physically left, right, above or below), stop at the display's edge rather than wrapping or changing display, and a span moves into the single zone past its edge. The keys are fixed, not a setting. |
    | **Fill Zones fills empty zones only, nearest first** | After a reboot or reconnect, one click tiles the untiled windows with the least movement. Tiled windows and leftover windows are left alone, so nothing is rearranged unexpectedly. |
    ```
  - Under Architecture decisions, add:

    ```markdown
    - **Hotkeys use Carbon `RegisterEventHotKey`**, not an `NSEvent` key monitor or an event tap: no extra permission, and the keystroke is swallowed so apps never see it.
    ```

- [ ] **Step 3: `docs/history/macos-gotchas.md`**
  - In the Accessibility API section, add:

    ```markdown
    - **An app's `kAXWindowsAttribute` lists only its windows on the current Space.** Windows on other Spaces don't appear (confirmed with a probe script), so enumerating visible windows needs no `CGWindowList` filter.
    ```
  - Add a new section after "Watching the mouse":

    ```markdown
    ## Hotkeys

    - **Carbon `RegisterEventHotKey` still works** on macOS 27 from a SwiftPM-built app. It needs no Accessibility or Input Monitoring permission, and the keystroke is consumed. VoiceOver also uses Ctrl+Option, but only while it's on.
    ```

- [ ] **Step 4: `CLAUDE.md`**

  In the Architecture list, add after the `DragMonitor` bullet:

  ```markdown
  - **Keyboard moves and Fill Zones** both end in `TilingController.snap`, so they behave like a drop. `HotKeys` (Carbon) sends Ctrl+Option + arrows to `moveFocusedWindow(toward:)`, which uses `Geometry.neighbour` on the window's own display only. `fillZones()` pairs untiled `WindowAccess.visibleWindows()` with empty zones through `Geometry.fill`.
  ```

- [ ] **Step 5: Commit**

```bash
git add docs/history CLAUDE.md
git commit -m "Document keyboard moves and Fill Zones"
```
