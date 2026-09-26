# Split on Drop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Holding the split key (Control by default) during a Shift-drag splits the zone under the cursor into top and bottom halves. The window drops into the half under the cursor, and any window already in that zone moves to the other half.

**Architecture:** The split is a working-copy change inside `Arrangement` (in PanefulCore). It uses `Node.splitting` along `.horizontal`, a per-arrangement zone-ID counter, and a set of split-created zones. When a split-created zone and its previous sibling are both empty, it collapses. The app asks `TilingController` for a preview, which runs the split on a copy of the arrangement, and draws it with the existing overlay. Releasing calls a split snap.

**Tech Stack:** Swift 6.4, SwiftPM, Swift Testing, AppKit. Command Line Tools only.

**Spec:** `docs/superpowers/specs/2026-09-26-split-drop-design.md`

## Global Constraints
- No Xcode, no SwiftUI macros, no third-party dependencies, macOS 14 minimum.
- New logic goes in `PanefulCore`, tests first. The app target is wiring only.
- The saved layout never changes. A split lives only in `Arrangement.working`.
- Zone IDs are never reused.
- There are three modifier keys (snap, span, split), always distinct. Choosing a key that's already in use swaps the two.
- The minimum zone size is `TilingController.minZoneSize` (100 pt).
- Run `swift test` with the explicit TestingMacros flag already in `Package.swift`; leave that flag as it is.

## Review Focus
- **The dragged window is already in the zone it splits** (re-dropping W into its own zone's top half). W lands in the top half, and the bottom half stays empty. Test: `redroppingTheOccupantIntoItsOwnZone`.
- **The dragged window is the only one in another split's half.** Leaving that half must collapse the other split, and must never collapse the new halves. Test: `splittingElsewhereCollapsesTheWindowsOldSplit`.
- **Reset Arrangement with windows in halves.** Windows in split-created zones are untiled, and no window points at a missing zone. Test: `resetUntilesWindowsInSplitZones`.
- **The split key held together with the span key.** Split wins. This is app wiring, checked by hand in Task 4.
- **Too small to split.** The drop is a plain snap and nothing changes. Test: `refusesZonesTooSmallToSplit`, plus the fallback in `TilingController.snap(_:splitting:…)`.

---

### Task 1: Split key setting

**Files:**
- Modify: `Sources/PanefulCore/Settings.swift`
- Test: `Tests/PanefulCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces: `Settings.splitModifier: ModifierKey` (read-only outside, default `.control`) and `Settings.setSplitModifier(_:)`. `setModifier` and `setSpanModifier` now swap with whichever of the other two keys holds the chosen value.

- [ ] **Step 1: Write the failing tests.** Add them to `SettingsTests`, and add `#expect(settings.splitModifier == .control)` to `defaults` and `partialFileKeepsKnownValues`.

```swift
    @Test func unknownSplitKeyFallsBackToControl() throws {
        #expect(try store(containing: #"{"splitModifier": "hyper"}"#).load().splitModifier == .control)
    }

    @Test func splitKeyEqualToAnotherKeyOnLoadFallsBack() throws {
        let fromModifier = try store(containing: #"{"modifier": "control"}"#).load()
        #expect(fromModifier.modifier == .control)
        #expect(fromModifier.spanModifier == .option)
        #expect(fromModifier.splitModifier == .shift)
        let fromSpan = try store(containing: #"{"spanModifier": "control"}"#).load()
        #expect(fromSpan.spanModifier == .control)
        #expect(fromSpan.splitModifier == .option)
    }

    @Test func settingTheSplitKeyToTheModifierSwapsThem() {
        var settings = Settings()
        settings.setSplitModifier(.shift)
        #expect(settings.splitModifier == .shift)
        #expect(settings.modifier == .control)
        #expect(settings.spanModifier == .option)
    }

    @Test func settingTheSpanKeyToTheSplitKeySwapsThem() {
        var settings = Settings()
        settings.setSpanModifier(.control)
        #expect(settings.spanModifier == .control)
        #expect(settings.splitModifier == .option)
        #expect(settings.modifier == .shift)
    }

    @Test func settingTheModifierToTheSplitKeySwapsThem() {
        var settings = Settings()
        settings.setModifier(.control)
        #expect(settings.modifier == .control)
        #expect(settings.splitModifier == .shift)
    }
```

`settingAnUnusedKeyDoesNotSwap` currently sets the span key to `.control`, which is now used by the split key. Change it to `.command`:

```swift
    @Test func settingAnUnusedKeyDoesNotSwap() {
        var settings = Settings()
        settings.setSpanModifier(.command)
        #expect(settings.spanModifier == .command)
        #expect(settings.modifier == .shift)
        #expect(settings.splitModifier == .control)
    }
```

- [ ] **Step 2: Run the tests and confirm they fail.** `swift test --filter SettingsTests` should FAIL with "value of type 'Settings' has no member 'splitModifier'".

- [ ] **Step 3: Implement it** in `Settings.swift`:

```swift
    /// Held while dragging a window to show zones. The three keys are never the same.
    public private(set) var modifier: ModifierKey = .shift
    /// Held as well as `modifier` to stretch the drop target across zones.
    public private(set) var spanModifier: ModifierKey = .option
    /// Held as well as `modifier` to split the zone under the cursor into top and bottom halves.
    public private(set) var splitModifier: ModifierKey = .control
```

Add to the decoder, after the span line:

```swift
        splitModifier = (try? container.decodeIfPresent(ModifierKey.self, forKey: .splitModifier)) ?? .control
        if spanModifier == modifier { spanModifier = ModifierKey.allCases.first { $0 != modifier }! }
        if splitModifier == modifier || splitModifier == spanModifier {
            splitModifier = ModifierKey.allCases.first { $0 != modifier && $0 != spanModifier }!
        }
```

This replaces the existing single `if spanModifier == modifier` line. Replace the setters with:

```swift
    /// Sets the snap modifier. Whichever other key had it takes the old modifier, so the keys never match.
    public mutating func setModifier(_ key: ModifierKey) { setKey(\.modifier, to: key) }

    /// Sets the span key. Whichever other key had it takes the old span key, so the keys never match.
    public mutating func setSpanModifier(_ key: ModifierKey) { setKey(\.spanModifier, to: key) }

    /// Sets the split key. Whichever other key had it takes the old split key, so the keys never match.
    public mutating func setSplitModifier(_ key: ModifierKey) { setKey(\.splitModifier, to: key) }

    private mutating func setKey(_ role: WritableKeyPath<Settings, ModifierKey>, to key: ModifierKey) {
        let old = self[keyPath: role]
        for other in [\Settings.modifier, \.spanModifier, \.splitModifier] where other != role && self[keyPath: other] == key {
            self[keyPath: other] = old
        }
        self[keyPath: role] = key
    }
```

- [ ] **Step 4: Run the tests and confirm they pass.** `swift test --filter SettingsTests`.
- [ ] **Step 5: Commit** with `git commit -m "Add a split key setting, kept distinct from the modifier and span key"`.

---

### Task 2: Split a zone on drop, collapse empty halves

**Files:**
- Modify: `Sources/PanefulCore/Arrangement.swift`
- Modify: `Sources/PanefulCore/LayoutEditing.swift` (add `Node.zone(before:)`)
- Create: `Tests/PanefulCoreTests/SplitDropTests.swift`

**Interfaces:**
- Produces: `Arrangement.split(_ zone: ZoneID, dropping window: Window, intoTop: Bool, in frame: CGRect, gap: CGFloat, minSize: CGFloat) -> ZoneID?`, marked `@discardableResult`. It returns the half the window landed in, or nil with nothing changed.
- `assign` and `remove` collapse empty split halves.
- `reset()` and `rebased(on:)` untile windows in split-created zones.

- [ ] **Step 1: Write the failing tests** in `Tests/PanefulCoreTests/SplitDropTests.swift`. Halves on a 1000×800 screen at gap 0: zone 0 is on the left, zone 1 on the right.

```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct SplitDropTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func halves() -> Arrangement<String> { Arrangement(saved: Presets.halves) }

    @Test func droppingOnTheTopHalfKeepsTheZoneAsTheTop() {
        var arrangement = halves()
        #expect(arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100) == 1)
        let rects = arrangement.rects(in: screen, gap: 0)
        #expect(rects[1] == CGRect(x: 500, y: 0, width: 500, height: 400))
        #expect(rects[2] == CGRect(x: 500, y: 400, width: 500, height: 400))
        #expect(arrangement.zones(of: "x") == [1])
    }

    @Test func droppingOnTheBottomHalfLandsInTheNewZone() {
        var arrangement = halves()
        #expect(arrangement.split(1, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100) == 2)
        #expect(arrangement.zones(of: "x") == [2])
    }

    @Test func halvesAreEqualWithAGap() {
        var arrangement = halves()
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 8, minSize: 100)
        let rects = arrangement.rects(in: screen, gap: 8)
        #expect(rects[1]!.height == rects[2]!.height)
        #expect(rects[2]!.minY - rects[1]!.maxY == 8)
    }

    @Test func occupantMovesToTheOtherHalf() {
        var top = halves()
        top.assign("w", to: 1)
        top.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(top.zones(of: "w") == [2])

        var bottom = halves()
        bottom.assign("w", to: 1)
        bottom.split(1, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100)
        #expect(bottom.zones(of: "w") == [1])
    }

    @Test func stackedOccupantsAllMove() {
        var arrangement = halves()
        arrangement.assign("v", to: 1)
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.zones(of: "v") == [2])
        #expect(arrangement.zones(of: "w") == [2])
    }

    @Test func spanOverTheZoneGetsBothHalves() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.assign("s", to: [0, 1])
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.zones(of: "s") == [0, 1, 3])
    }

    @Test func draggedWindowLeavesItsOldZone() {
        var arrangement = halves()
        arrangement.assign("x", to: 0)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.zones(of: "x") == [1])
        #expect(arrangement.windows(in: 0).isEmpty)
    }

    @Test func redroppingTheOccupantIntoItsOwnZone() {
        var arrangement = halves()
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "w", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.zones(of: "w") == [1])
        #expect(arrangement.windows(in: 2).isEmpty)
        #expect(arrangement.working.zoneIDs.contains(2))
    }

    @Test func splittingInsideAStackFlattensIntoIt() {
        var arrangement = Arrangement<String>(saved: Presets.onePlusTwo)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.working == .split(.vertical, children: [
            .zone(0),
            .split(.horizontal, children: [.zone(1), .zone(3), .zone(2)], fractions: [0.25, 0.25, 0.5]),
        ], fractions: [0.6, 0.4]))
    }

    @Test func aHalfCanBeSplitAgain() {
        var arrangement = halves()
        arrangement.split(1, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.split(2, dropping: "y", intoTop: false, in: screen, gap: 0, minSize: 100) == 3)
        let rects = arrangement.rects(in: screen, gap: 0)
        #expect(rects[2]!.height == 200)
        #expect(rects[3]!.height == 200)
        #expect(arrangement.zones(of: "x") == [2])
    }

    @Test func refusesZonesTooSmallToSplit() {
        var arrangement = halves()
        arrangement.assign("w", to: 1)
        let short = CGRect(x: 0, y: 0, width: 1000, height: 150)
        #expect(arrangement.split(1, dropping: "x", intoTop: true, in: short, gap: 0, minSize: 100) == nil)
        #expect(arrangement.working == Presets.halves.root)
        #expect(arrangement.zones(of: "x") == nil)
        #expect(arrangement.zones(of: "w") == [1])
    }

    @Test func collapsesOnlyOnceBothHalvesAreEmpty() {
        var arrangement = halves()
        arrangement.assign("a", to: 0)
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        arrangement.remove("x")
        #expect(arrangement.working.zoneIDs.contains(2))
        arrangement.remove("w")
        #expect(arrangement.working == Presets.halves.root)
    }

    @Test func movingWindowsOutWithAssignCollapses() {
        var arrangement = halves()
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        arrangement.assign("x", to: 0)
        #expect(arrangement.working.zoneIDs.contains(2))
        arrangement.assign("w", to: 0)
        #expect(arrangement.working == Presets.halves.root)
    }

    @Test func aChainOfHalvesCollapsesFully() {
        var arrangement = halves()
        arrangement.assign("a", to: 0)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        arrangement.split(1, dropping: "y", intoTop: true, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.zones(of: "x") == [3])
        arrangement.remove("y")
        #expect(arrangement.working.zoneIDs == [0, 1, 3, 2])
        arrangement.remove("x")
        #expect(arrangement.working == Presets.halves.root)
    }

    @Test func splittingElsewhereCollapsesTheWindowsOldSplit() {
        var arrangement = Arrangement<String>(saved: Presets.thirds)
        arrangement.split(0, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100)
        #expect(arrangement.split(2, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100) == 4)
        #expect(arrangement.working.zoneIDs == [0, 1, 2, 4])
        #expect(arrangement.zones(of: "x") == [4])
    }

    @Test func zoneIDsAreNeverReused() {
        var arrangement = halves()
        arrangement.assign("a", to: 0)
        arrangement.split(1, dropping: "x", intoTop: false, in: screen, gap: 0, minSize: 100)
        arrangement.remove("x")
        #expect(arrangement.working == Presets.halves.root)
        #expect(arrangement.split(1, dropping: "y", intoTop: false, in: screen, gap: 0, minSize: 100) == 3)
    }

    @Test func rebasedUntilesWindowsInSplitZones() {
        var arrangement = halves()
        arrangement.assign("a", to: 0)
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        let rebased = arrangement.rebased(on: Presets.thirds)
        #expect(rebased.zones(of: "a") == [0])
        #expect(rebased.zones(of: "x") == [1])
        #expect(rebased.zones(of: "w") == nil)
    }

    @Test func resetUntilesWindowsInSplitZones() {
        var arrangement = halves()
        arrangement.assign("w", to: 1)
        arrangement.split(1, dropping: "x", intoTop: true, in: screen, gap: 0, minSize: 100)
        arrangement.reset()
        #expect(arrangement.working == Presets.halves.root)
        #expect(arrangement.zones(of: "x") == [1])
        #expect(arrangement.zones(of: "w") == nil)
    }
}
```

In `splittingElsewhereCollapsesTheWindowsOldSplit`, thirds gives zones 0, 1 and 2. The first split creates 3 below 0, with x in 3. Splitting 2 creates 4 with x in it. Zone 3 is now empty and so is its previous sibling 0, so zone 3 collapses.

- [ ] **Step 2: Run the tests and confirm they fail.** `swift test --filter SplitDropTests` should FAIL with "value of type 'Arrangement<String>' has no member 'split'".

- [ ] **Step 3: Implement it.** In `LayoutEditing.swift`, inside the `extension Node`, after `removing`:

```swift
    /// The zone just before `zone` in its split, if that sibling is a zone rather than a split.
    func zone(before zone: ZoneID) -> ZoneID? {
        guard case .split(_, let children, _) = self else { return nil }
        if let index = children.firstIndex(of: .zone(zone)) {
            guard index > 0, case .zone(let id) = children[index - 1] else { return nil }
            return id
        }
        return children.lazy.compactMap { $0.zone(before: zone) }.first
    }
```

In `Arrangement.swift`, update the type's doc comment to mention splits, and add the stored properties and init:

```swift
    private var zonesOf: [Window: Set<ZoneID>] = [:]
    /// Zones added by split drops. They exist only in the working tree.
    private var splitZones: Set<ZoneID> = []
    /// Only ever goes up, so a split never reuses a zone ID.
    private var nextZoneID: ZoneID

    public init(saved: Layout) {
        self.saved = saved
        self.working = saved.root
        self.nextZoneID = (saved.root.zoneIDs.max() ?? -1) + 1
    }
```

Collapse in `assign` and `remove`:

```swift
    public mutating func assign(_ window: Window, to zones: Set<ZoneID>) {
        guard !zones.isEmpty, zones.isSubset(of: working.zoneIDs) else { return }
        zonesOf[window] = zones
        collapseEmptySplits()
    }

    public mutating func remove(_ window: Window) {
        zonesOf[window] = nil
        if zonesOf.isEmpty { reset() } else { collapseEmptySplits() }
    }

    /// Restores the saved layout's boundaries, dropping split halves: windows in a split-created zone are untiled,
    /// the others keep their zones.
    public mutating func reset() {
        zonesOf = zonesOf.filter { $0.value.isDisjoint(with: splitZones) }
        splitZones = []
        working = saved.root
    }
```

Add `split` and the collapse helper, for example after `fit`:

```swift
    /// Splits `zone` into equal top and bottom halves and puts `window` in one. `zone` keeps the top half, and a new
    /// zone takes the bottom. Other windows in exactly `zone` move to the other half, and spans over it cover both.
    /// Returns the half `window` landed in, or nil (changing nothing) if a half would be shorter than `minSize`.
    @discardableResult
    public mutating func split(_ zone: ZoneID, dropping window: Window, intoTop: Bool, in frame: CGRect, gap: CGFloat, minSize: CGFloat) -> ZoneID? {
        guard working.zoneIDs.contains(zone) else { return nil }
        let newZone = nextZoneID
        let node = working.splitting(zone, along: .horizontal, newZone: newZone)
        let rects = Geometry.zoneRects(node, in: frame, gap: gap)
        guard let top = rects[zone], let bottom = rects[newZone], min(top.height, bottom.height) >= minSize else { return nil }
        working = node
        nextZoneID += 1
        splitZones.insert(newZone)
        let (landing, other) = intoTop ? (zone, newZone) : (newZone, zone)
        for (tiled, zones) in zonesOf where tiled != window && zones.contains(zone) {
            zonesOf[tiled] = zones == [zone] ? [other] : zones.union([newZone])
        }
        zonesOf[window] = [landing]
        collapseEmptySplits()
        return landing
    }

    /// Removes each split-created zone that is empty along with the zone before it; the zone before takes its space.
    private mutating func collapseEmptySplits() {
        let covered = Set(zonesOf.values.joined())
        while let zone = splitZones.first(where: { zone in
            !covered.contains(zone) && working.zone(before: zone).map { !covered.contains($0) } == true
        }), let node = working.removing(zone) {
            working = node
            splitZones.remove(zone)
        }
    }
```

Update `rebased(on:)`:

```swift
    /// A fresh arrangement for `saved`, keeping windows whose zones all still exist in it. Windows in split-created
    /// zones are dropped, since `saved` may use those IDs for other zones.
    public func rebased(on saved: Layout) -> Arrangement {
        var result = Arrangement(saved: saved)
        for (window, zones) in zonesOf where zones.isDisjoint(with: splitZones) { result.assign(window, to: zones) }
        return result
    }
```

- [ ] **Step 4: Run the tests and confirm they pass.** Run `swift test`: the full suite, including the existing ArrangementTests.
- [ ] **Step 5: Commit** with `git commit -m "Split a zone into top and bottom halves on drop, collapsing them once empty"`.

---

### Task 3: App wiring (drag, snap, menu)

**Files:**
- Modify: `Sources/Paneful/TilingController.swift`
- Modify: `Sources/Paneful/DragMonitor.swift`
- Modify: `Sources/Paneful/AppDelegate.swift`

**Interfaces:**
- Consumes: `Arrangement.split(...)`, `Settings.splitModifier` and `Settings.setSplitModifier(_:)`.
- Produces:
  - `TilingController.splitPreview(of: ZoneID, top: Bool, dropping: AXUIElement, on: Display) -> (rects: [ZoneID: CGRect], landing: CGRect)?`
  - `TilingController.snap(_: AXUIElement, splitting: ZoneID, top: Bool, on: Display)`
  - `TilingController.setSplitModifier(_:)`

- [ ] **Step 1: `TilingController`.** Add this after `snap(_:to:on:)`:

```swift
    /// What a split drop of `window` onto `zone` would look like: the display's zone rects after the split and the
    /// half it would land in. Nil if the zone is too small to split.
    func splitPreview(of zone: ZoneID, top: Bool, dropping window: AXUIElement, on display: Display) -> (rects: [ZoneID: CGRect], landing: CGRect)? {
        guard var arrangement = arrangements[display.id],
              let landing = arrangement.split(zone, dropping: window, intoTop: top, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize)
        else { return nil }
        let rects = arrangement.rects(in: display.visibleFrame, gap: gap)
        return rects[landing].map { (rects, $0) }
    }

    /// Splits `zone` into top and bottom halves and tiles `window` in one; windows already in the zone move to the
    /// other half. A zone too small to split gets a plain snap.
    func snap(_ window: AXUIElement, splitting zone: ZoneID, top: Bool, on display: Display) {
        guard var arrangement = arrangements[display.id] else { return }
        guard arrangement.split(zone, dropping: window, intoTop: top, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) != nil else {
            return snap(window, to: [zone], on: display)
        }
        if !isTiled(window) { sizesBeforeSnap[window] = WindowAccess.frame(of: window)?.size }
        for id in arrangements.keys where id != display.id { arrangements[id]?.remove(window) }
        arrangements[display.id] = arrangement
        refit(display)
    }
```

After `setSpanModifier`, add:

```swift
    func setSplitModifier(_ modifier: ModifierKey) {
        settings.setSplitModifier(modifier)
        save()
    }
```

- [ ] **Step 2: `DragMonitor`.**
  - Doc comment: after the span sentence, add "Holding the split key instead splits the zone under the cursor into top and bottom halves, and the window drops into the half under the cursor."
  - Change the `.moving` case so the target carries an optional split half:

```swift
        /// `anchor` is where the span key went down, kept only while it's held on that display. `splitTop` is set
        /// when the drop splits `zones` (a single zone): true for its top half.
        case moving(AXUIElement, target: (display: Display, zones: Set<ZoneID>, splitTop: Bool?)?, anchor: (displayID: String, zone: ZoneID)?)
```

  - In `updateMove`, after `let zone = …`, add:

```swift
        // The split key wins over the span key. A zone too small to split falls through to a plain target.
        if flags.contains(tiling.settings.splitModifier.flags), let zone, let rect = rects[zone] {
            let top = cursor.y < rect.midY
            if let preview = tiling.splitPreview(of: zone, top: top, dropping: window, on: display) {
                gesture = .moving(window, target: (display: display, zones: [zone], splitTop: top), anchor: nil)
                overlay.show(on: display, rects: preview.rects, highlighted: preview.landing)
                return
            }
        }
```

  - Update the existing plain assignment to `target: zones.map { (display: display, zones: $0, splitTop: nil) }`.
  - In `release`, handle the split case:

```swift
        case .moving(let window, let target?, _):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [tiling] in
                if let top = target.splitTop, let zone = target.zones.first {
                    tiling.snap(window, splitting: zone, top: top, on: target.display)
                } else {
                    tiling.snap(window, to: target.zones, on: target.display)
                }
            }
```

- [ ] **Step 3: `AppDelegate`.** After the Span Key line, add:

```swift
        menu.addItem(parent("Split Key", keyMenu(selected: tiling.settings.splitModifier, action: #selector(chooseSplitModifier(_:)))))
```

Then, after `chooseSpanModifier`:

```swift
    @objc private func chooseSplitModifier(_ sender: NSMenuItem) {
        guard let modifier = sender.representedObject as? ModifierKey else { return }
        tiling.setSplitModifier(modifier)
    }
```

- [ ] **Step 4: Build.** `swift build` should end with "Build complete!". Ignore the `ld: warning: search path` lines.
- [ ] **Step 5: Commit** with `git commit -m "Split the zone under the cursor when the split key is held during a drag"`.

---

### Task 4: Docs, install, manual check

**Files:**
- Modify: `docs/history/README.md`: add a timeline row for "Split on drop", and add it to the follow-up list and test count in "Where it stands".
- Modify: `docs/history/design-decisions.md`: in Product decisions, add "Split halves are placement in the working copy, top/bottom only, collapsing once both are empty". In Architecture, add "`Arrangement` owns split-created zone IDs through its own counter; rebasing or Reset untiles windows in them".
- Modify: `CLAUDE.md`: extend the "Saved layout vs working copy" Arrangement bullet with one sentence on split drops. Add the split key to the DragMonitor bullet.

- [ ] **Step 1: Write the doc edits** above, with the known limitation: a display reconfiguration untiles windows in halves.
- [ ] **Step 2: Run the full suite.** `swift test` should PASS. Note the new test count for the README.
- [ ] **Step 3: Commit** with `git commit -m "Document split on drop"`.
- [ ] **Step 4: Install and hand over.** Run `scripts/install.sh`, then ask Adam to run the manual checklist from the spec on his three displays: preview, occupant, collapse, too small, Split Key menu with relaunch, Fill Zones and keyboard moves, and split plus span held together.
- [ ] **Step 5: Merge.** Once Adam confirms, run `git checkout main && git merge --ff-only split-drop`.
