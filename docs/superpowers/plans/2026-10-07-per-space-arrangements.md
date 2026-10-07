# Per-Space Arrangements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each Space keeps its own live state per display (working dividers, split halves, tiled windows), so resizing on one Space never moves a window on another.

**Architecture:** A new core type, `SpaceArrangements<Window>`, stores `Arrangement`s keyed by Space ID and display UUID, and drops any arrangement that has no tiled windows. `TilingController` swaps its `[String: Arrangement]` for it. Per-Space actions use the current Space's key; deliberate global edits (layout, gap, displays) touch every key. A new app file, `Spaces.swift`, reads the current Space ID through the private `CGSGetActiveSpace`.

**Tech Stack:** Swift 6.4, SwiftPM, Swift Testing, AppKit. Command Line Tools only.

**Spec:** `docs/superpowers/specs/2026-10-07-per-space-arrangements-design.md`

## Global Constraints
- No Xcode, no SwiftUI macros, no third-party dependencies, macOS 14 minimum.
- New logic goes in `PanefulCore`, tests first. The app target is wiring only.
- `Arrangement` doesn't change. Saved layouts, the editor, the menu and `settings.json` don't change.
- Zone IDs are never reused.
- `WindowAccess` stays the only file that calls the Accessibility API. `Spaces` is the only file that calls the private SkyLight functions.
- Run `swift test` with the explicit TestingMacros flag already in `Package.swift`; leave that flag as it is.
- The system `sed` is GNU sed. Use the Edit tool for in-place edits.

## Review Focus
- **A layout change leaves a Space with no tiled windows** (its only window was in a split half, which `rebased(on:)` untiles). That arrangement must be dropped, not kept as an empty entry. Test: `rebaseDropsArrangementsLeftEmpty`.
- **A window tiled on X, moved to Y with Mission Control, then dropped on Y.** It must be untiled from X, or X's next resize moves it on Y. Test: `untileExceptKeyRemovesItFromOtherSpacesAndDisplays`; manual check 5.
- **A display unplugged while several Spaces hold state for it.** Every Space's entry for it goes. Test: `keepDropsDisconnectedDisplaysOnEverySpace`.
- **The Space changes partway through a multi-display action** (Fill Zones, Reset). Each action reads the Space once and uses it for every display. This is app wiring, checked by reading Task 2's code.
- **The private call fails and returns 0.** Everything then lives under Space 0, which is today's behaviour. There's no special case to test: 0 is just another key.

---

### Task 1: `SpaceArrangements` in core

**Files:**
- Create: `Sources/PanefulCore/SpaceArrangements.swift`
- Test: `Tests/PanefulCoreTests/SpaceArrangementsTests.swift`

**Interfaces:**
- Consumes: `Arrangement<Window>` (`init(saved:)`, `tiledWindows`, `zones(of:)`, `remove(_:)`, `rebased(on:)`), from `Sources/PanefulCore/Arrangement.swift`.
- Produces:
  - `public struct SpaceArrangements<Window: Hashable>` with `public init()`
  - `public struct Key: Hashable, Sendable { public let space: Int; public let display: String; public init(space: Int, display: String) }`
  - `public var keys: [Key]`
  - `public func arrangement(_ key: Key, saved: Layout) -> Arrangement<Window>`
  - `public mutating func store(_ arrangement: Arrangement<Window>, at key: Key)`
  - `public mutating func untile(_ window: Window, except key: Key? = nil)`
  - `public func location(of window: Window, on space: Int) -> (display: String, zones: Set<ZoneID>)?`
  - `public mutating func rebase(display: String, on saved: Layout)`
  - `public mutating func keep(displays: Set<String>)`

- [ ] **Step 1: Write the failing tests** in `Tests/PanefulCoreTests/SpaceArrangementsTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PanefulCore

@Suite struct SpaceArrangementsTests {
    typealias Key = SpaceArrangements<String>.Key
    let ultrawide = CGRect(x: 0, y: 31, width: 3440, height: 1327)
    /// The middle display on Space X, the same display on Space Y, and the left display on Space X.
    let x = Key(space: 8, display: "middle")
    let y = Key(space: 7, display: "middle")
    let side = Key(space: 8, display: "left")

    /// Tiles `window` in `zone` of Halves under `key`.
    func tile(_ window: String, in zone: ZoneID, at key: Key, _ arrangements: inout SpaceArrangements<String>) {
        var arrangement = arrangements.arrangement(key, saved: Presets.halves)
        arrangement.assign(window, to: zone)
        arrangements.store(arrangement, at: key)
    }

    @Test func missingKeyGivesAFreshArrangement() {
        let arrangements = SpaceArrangements<String>()
        let arrangement = arrangements.arrangement(x, saved: Presets.thirds)
        #expect(arrangement.working == Presets.thirds.root)
        #expect(arrangement.tiledWindows.isEmpty)
        #expect(arrangements.keys.isEmpty)
    }

    @Test func storedArrangementIsReadBack() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 1, at: x, &arrangements)
        #expect(arrangements.arrangement(x, saved: Presets.halves).zones(of: "a") == [1])
        #expect(arrangements.keys == [x])
    }

    @Test func arrangementWithNoTiledWindowsIsDropped() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 0, at: x, &arrangements)
        var arrangement = arrangements.arrangement(x, saved: Presets.halves)
        arrangement.remove("a")
        arrangements.store(arrangement, at: x)
        #expect(arrangements.keys.isEmpty)
    }

    @Test func movingADividerOnOneSpaceLeavesTheOtherSpaceAlone() {
        var arrangements = SpaceArrangements<String>()
        tile("onX", in: 0, at: x, &arrangements)
        tile("onY", in: 0, at: y, &arrangements)
        var onY = arrangements.arrangement(y, saved: Presets.halves)
        onY.moveEdge(.right, of: [0], to: 2000, in: ultrawide, gap: 8, minSize: 100)
        arrangements.store(onY, at: y)
        #expect(arrangements.arrangement(y, saved: Presets.halves).rects(in: ultrawide, gap: 8)[0]!.maxX == 2000)
        #expect(arrangements.arrangement(x, saved: Presets.halves).working == Presets.halves.root)
    }

    @Test func untileExceptKeyRemovesItFromOtherSpacesAndDisplays() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 0, at: x, &arrangements)
        tile("b", in: 1, at: x, &arrangements)
        tile("a", in: 1, at: y, &arrangements)
        tile("a", in: 0, at: side, &arrangements)
        arrangements.untile("a", except: y)
        #expect(arrangements.arrangement(x, saved: Presets.halves).zones(of: "a") == nil)
        #expect(arrangements.arrangement(x, saved: Presets.halves).zones(of: "b") == [1])
        #expect(arrangements.arrangement(y, saved: Presets.halves).zones(of: "a") == [1])
        #expect(!arrangements.keys.contains(side))
    }

    @Test func untileWithNoKeyRemovesItEverywhere() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 0, at: x, &arrangements)
        tile("a", in: 0, at: y, &arrangements)
        arrangements.untile("a")
        #expect(arrangements.keys.isEmpty)
    }

    @Test func locationIsFoundOnlyOnItsOwnSpace() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 1, at: x, &arrangements)
        let found = arrangements.location(of: "a", on: 8)
        #expect(found?.display == "middle")
        #expect(found?.zones == [1])
        #expect(arrangements.location(of: "a", on: 7) == nil)
    }

    @Test func rebaseChangesTheDisplayOnEverySpace() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 0, at: x, &arrangements)
        tile("b", in: 0, at: y, &arrangements)
        tile("c", in: 0, at: side, &arrangements)
        arrangements.rebase(display: "middle", on: Presets.thirds)
        #expect(arrangements.arrangement(x, saved: Presets.halves).saved == Presets.thirds)
        #expect(arrangements.arrangement(y, saved: Presets.halves).saved == Presets.thirds)
        #expect(arrangements.arrangement(x, saved: Presets.halves).zones(of: "a") == [0])
        #expect(arrangements.arrangement(side, saved: Presets.halves).saved == Presets.halves)
    }

    @Test func rebaseDropsArrangementsLeftEmpty() {
        var arrangements = SpaceArrangements<String>()
        var arrangement = arrangements.arrangement(x, saved: Presets.halves)
        arrangement.split(0, dropping: "a", intoTop: false, in: ultrawide, gap: 8, minSize: 100)
        arrangements.store(arrangement, at: x)
        arrangements.rebase(display: "middle", on: Presets.halves)
        #expect(arrangements.keys.isEmpty)
    }

    @Test func keepDropsDisconnectedDisplaysOnEverySpace() {
        var arrangements = SpaceArrangements<String>()
        tile("a", in: 0, at: x, &arrangements)
        tile("b", in: 0, at: y, &arrangements)
        tile("c", in: 0, at: side, &arrangements)
        arrangements.keep(displays: ["left"])
        #expect(arrangements.keys == [side])
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail.** `swift test --filter SpaceArrangementsTests` should FAIL with "cannot find 'SpaceArrangements' in scope".

- [ ] **Step 3: Implement it** in `Sources/PanefulCore/SpaceArrangements.swift`:

```swift
/// Every display's arrangement on every Space, keyed by Space ID and display UUID, so each Space has its own
/// working dividers, split halves and tiled windows. An arrangement with no tiled windows isn't kept: it equals a
/// fresh one for its saved layout, because removing its last window resets it.
public struct SpaceArrangements<Window: Hashable> {
    public struct Key: Hashable, Sendable {
        public let space: Int
        public let display: String

        public init(space: Int, display: String) {
            self.space = space
            self.display = display
        }
    }

    private var stored: [Key: Arrangement<Window>] = [:]

    public init() {}

    /// The keys of arrangements with tiled windows.
    public var keys: [Key] { Array(stored.keys) }

    /// The arrangement under `key`, or a fresh one for `saved` if there's none.
    public func arrangement(_ key: Key, saved: Layout) -> Arrangement<Window> {
        stored[key] ?? Arrangement(saved: saved)
    }

    /// Keeps `arrangement` under `key`, or drops it if it has no tiled windows.
    public mutating func store(_ arrangement: Arrangement<Window>, at key: Key) {
        stored[key] = arrangement.tiledWindows.isEmpty ? nil : arrangement
    }

    /// Untiles `window` everywhere except under `key`, so it's tiled on one display of one Space at most.
    public mutating func untile(_ window: Window, except key: Key? = nil) {
        for other in stored.keys where other != key {
            guard var arrangement = stored[other] else { continue }
            arrangement.remove(window)
            store(arrangement, at: other)
        }
    }

    /// The display and zones `window` is tiled in on `space`.
    public func location(of window: Window, on space: Int) -> (display: String, zones: Set<ZoneID>)? {
        for (key, arrangement) in stored where key.space == space {
            if let zones = arrangement.zones(of: window) { return (key.display, zones) }
        }
        return nil
    }

    /// Rebases `display`'s arrangement on every Space on `saved` (see `Arrangement.rebased(on:)`).
    public mutating func rebase(display: String, on saved: Layout) {
        for key in stored.keys where key.display == display {
            guard let arrangement = stored[key] else { continue }
            store(arrangement.rebased(on: saved), at: key)
        }
    }

    /// Drops the arrangements of displays not in `displays`, on every Space.
    public mutating func keep(displays: Set<String>) {
        stored = stored.filter { displays.contains($0.key.display) }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass.** Run `swift test`: the full suite, which should be 179 tests (169 + 10), all passing.
- [ ] **Step 5: Commit** with `git commit -m "Add SpaceArrangements: arrangements keyed by Space and display"`.

---

### Task 2: Read the current Space, and key TilingController's arrangements by it

**Files:**
- Create: `Sources/Paneful/Spaces.swift`
- Modify: `Sources/Paneful/TilingController.swift` (the stored `arrangements`, and every method that reads or writes it)

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces: `Spaces.current() -> Int`. `TilingController`'s public methods keep their signatures, so `DragMonitor`, `AppDelegate` and the editor don't change.

- [ ] **Step 1: Create `Sources/Paneful/Spaces.swift`:**

```swift
import CoreGraphics

// Private SkyLight functions, re-exported by CoreGraphics. They're read-only and work with SIP on.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") private func CGSGetActiveSpace(_ connection: Int32) -> Int

/// The only place Paneful calls the private Space functions.
enum Spaces {
    /// The current Space's ID, or 0 if the window server doesn't give one, which puts everything on one shared Space.
    /// With "Displays have separate Spaces" off, every display is on this Space. It's read fresh on each call, so
    /// Paneful needs no Space-change notification.
    static func current() -> Int {
        CGSGetActiveSpace(CGSMainConnectionID())
    }
}
```

- [ ] **Step 2: Swap the storage and add the key helpers in `TilingController`.** Replace

```swift
    private var arrangements: [String: Arrangement<AXUIElement>] = [:]
```

with

```swift
    private typealias Key = SpaceArrangements<AXUIElement>.Key
    /// Each Space's arrangement per display, so resizing on one Space never moves windows on another.
    private var arrangements = SpaceArrangements<AXUIElement>()
```

and add these private helpers just above `private func save()`:

```swift
    private func spaceKey(_ display: Display, space: Int = Spaces.current()) -> Key {
        Key(space: space, display: display.id)
    }

    /// The arrangement under `key`, or a fresh one from the display's saved layout.
    private func liveArrangement(_ key: Key) -> Arrangement<AXUIElement> {
        arrangements.arrangement(key, saved: settings.layout(forDisplay: key.display))
    }

    private func refitAll() {
        arrangements.keys.forEach { refit($0) }
    }
```

- [ ] **Step 3: Rewrite the methods that use `arrangements`.** Replace each of these whole methods in `TilingController.swift` with the version below. Their doc comments stay, except where a new comment is shown.

```swift
    /// Re-reads connected displays. Every Space's arrangements restart from saved layouts, keeping tiled windows,
    /// which are re-fitted.
    func refreshDisplays() {
        displays = Displays.current()
        arrangements.keep(displays: Set(displays.map(\.id)))
        for display in displays {
            arrangements.rebase(display: display.id, on: settings.layout(forDisplay: display.id))
        }
        refitAll()
    }
```

```swift
    func zoneRects(for display: Display) -> [ZoneID: CGRect] {
        liveArrangement(spaceKey(display)).rects(in: display.visibleFrame, gap: gap)
    }
```

```swift
    /// Tiles `window` in `zones` (one zone, or a span), filling their combined rect.
    func snap(_ window: AXUIElement, to zones: Set<ZoneID>, on display: Display) {
        let key = spaceKey(display)
        var arrangement = liveArrangement(key)
        guard let rect = Geometry.union(of: zones, in: arrangement.rects(in: display.visibleFrame, gap: gap)) else { return }
        // Moving between zones keeps the size from before the first snap.
        if !isTiled(window) { sizesBeforeSnap[window] = WindowAccess.frame(of: window)?.size }
        // Only other displays and Spaces untile it: assign replaces its zones here, so moving a display's only
        // window between zones doesn't empty the display and reset it.
        arrangements.untile(window, except: key)
        arrangement.assign(window, to: zones)
        arrangements.store(arrangement, at: key)
        WindowAccess.setFrame(rect, of: window, within: display.visibleFrame)
    }
```

```swift
    func splitPreview(of zone: ZoneID, top: Bool, dropping window: AXUIElement, on display: Display) -> (rects: [ZoneID: CGRect], landing: CGRect)? {
        var arrangement = liveArrangement(spaceKey(display))
        guard let landing = arrangement.split(zone, dropping: window, intoTop: top, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize)
        else { return nil }
        let rects = arrangement.rects(in: display.visibleFrame, gap: gap)
        return rects[landing].map { (rects, $0) }
    }
```

```swift
    func snap(_ window: AXUIElement, splitting zone: ZoneID, top: Bool, on display: Display) {
        let key = spaceKey(display)
        var arrangement = liveArrangement(key)
        guard arrangement.split(zone, dropping: window, intoTop: top, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) != nil else {
            return snap(window, to: [zone], on: display)
        }
        if !isTiled(window) { sizesBeforeSnap[window] = WindowAccess.frame(of: window)?.size }
        arrangements.untile(window, except: key)
        arrangements.store(arrangement, at: key)
        refit(key)
    }
```

```swift
    func untile(_ window: AXUIElement) {
        arrangements.untile(window)
    }
```

```swift
    /// Puts untiled visible windows into every display's empty zones on the current Space: each goes to the nearest
    /// free zone on the display its centre is on. Leftover windows and tiled windows are left alone.
    func fillZones() {
        forgetClosedWindows()
        let space = Spaces.current()
        let untiled = WindowAccess.visibleWindows().filter { !isTiled($0) }.compactMap { window in
            WindowAccess.frame(of: window).map { (window, CGPoint(x: $0.midX, y: $0.midY)) }
        }
        for display in displays {
            let arrangement = liveArrangement(spaceKey(display, space: space))
            let empty = arrangement.rects(in: display.visibleFrame, gap: gap).filter { arrangement.windows(in: $0.key).isEmpty }
            let windows = untiled.filter { display.frame.contains($0.1) }
            for (window, zone) in Geometry.fill(empty: empty, windows: windows) {
                snap(window, to: [zone], on: display)
            }
        }
    }
```

```swift
    /// Untiles windows that were closed or minimised since Paneful last moved them, on every Space, so a display left
    /// with no tiled windows goes back to its saved layout before the overlay shows it.
    func forgetClosedWindows() {
        for key in arrangements.keys {
            var arrangement = liveArrangement(key)
            for window in arrangement.tiledWindows
            where WindowAccess.isGone(window) || WindowAccess.isMinimized(window) || WindowAccess.frame(of: window) == nil {
                arrangement.remove(window)
            }
            arrangements.store(arrangement, at: key)
        }
    }
```

```swift
    func pressCandidates(at point: CGPoint) -> [AXUIElement] {
        var candidates: [AXUIElement] = []
        if let hit = WindowAccess.window(at: point) { candidates.append(hit) }
        guard let display = display(containing: point) else { return candidates }
        let arrangement = liveArrangement(spaceKey(display))
        let reach = Self.resizeHandleReach
        for (zone, rect) in arrangement.rects(in: display.visibleFrame, gap: gap)
        where rect.insetBy(dx: -reach, dy: -reach).contains(point) {
            for window in arrangement.windows(in: zone) where !candidates.contains(window) {
                candidates.append(window)
            }
        }
        return candidates
    }
```

```swift
    @discardableResult
    func followResize(of window: AXUIElement, moves: [EdgeMove]) -> Bool {
        let space = Spaces.current()
        guard let (display, zones) = location(of: window, space: space) else { return false }
        let key = spaceKey(display, space: space)
        var arrangement = liveArrangement(key)
        let before = arrangement.rects(in: display.visibleFrame, gap: gap)
        var linked = false
        for move in moves {
            if arrangement.moveEdge(move.edge, of: zones, to: move.position, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) {
                linked = true
            }
        }
        guard linked else { return false }
        arrangements.store(arrangement, at: key)
        refit(key, changedFrom: before, except: window)
        return true
    }
```

```swift
    func finishResize(of window: AXUIElement) {
        let space = Spaces.current()
        guard let (display, _) = location(of: window, space: space) else { return }
        let key = spaceKey(display, space: space)
        refit(key)
        var arrangement = liveArrangement(key)
        var moved = false
        for tiled in arrangement.tiledWindows {
            guard let zones = arrangement.zones(of: tiled), let actual = WindowAccess.frame(of: tiled) else { continue }
            if arrangement.fit(zones, toAtLeast: actual.size, in: display.visibleFrame, gap: gap, minSize: Self.minZoneSize) {
                moved = true
            }
        }
        guard moved else { return }
        arrangements.store(arrangement, at: key)
        refit(key)
    }
```

```swift
    /// Where `window` is tiled on `space` (the current Space by default).
    private func location(of window: AXUIElement, space: Int = Spaces.current()) -> (display: Display, zones: Set<ZoneID>)? {
        guard let (id, zones) = arrangements.location(of: window, on: space),
              let display = displays.first(where: { $0.id == id }) else { return nil }
        return (display, zones)
    }
```

```swift
    /// Restores the saved layouts' boundaries on the current Space. Other Spaces keep theirs.
    func resetArrangements() {
        let space = Spaces.current()
        for display in displays {
            let key = spaceKey(display, space: space)
            var arrangement = liveArrangement(key)
            arrangement.reset()
            arrangements.store(arrangement, at: key)
            refit(key)
        }
    }
```

```swift
    func setLayout(_ layout: Layout, for display: Display) {
        settings.layouts[display.id] = layout
        save()
        arrangements.rebase(display: display.id, on: layout)
        for key in arrangements.keys where key.display == display.id { refit(key) }
    }

    func setGap(_ gap: Double) {
        settings.gap = gap
        save()
        refitAll()
    }
```

```swift
    /// Moves the tiled windows under `key` to their zone rects. Given `old` rects, it moves only windows whose
    /// (combined) rect changed. Windows that were closed, minimised or whose app quit are untiled instead.
    private func refit(_ key: Key, changedFrom old: [ZoneID: CGRect]? = nil, except skipped: AXUIElement? = nil) {
        guard let display = displays.first(where: { $0.id == key.display }) else { return }
        var arrangement = liveArrangement(key)
        let rects = arrangement.rects(in: display.visibleFrame, gap: gap)
        for window in arrangement.tiledWindows where window != skipped {
            guard let zones = arrangement.zones(of: window), let rect = Geometry.union(of: zones, in: rects),
                  old.flatMap({ Geometry.union(of: zones, in: $0) }) != rect else { continue }
            if WindowAccess.isGone(window) || WindowAccess.isMinimized(window) || !WindowAccess.setFrame(rect, of: window, within: display.visibleFrame) {
                arrangement.remove(window)
            }
        }
        arrangements.store(arrangement, at: key)
    }
```

`dragOut`, `moveFocusedWindow` and `isTiled` keep their code. They go through `isTiled`, `untile`, `location(of:)`, `zoneRects(for:)` and `snap`, which now use the current Space.

- [ ] **Step 4: Build and test.** `swift build` should end with "Build complete!" (ignore the `ld: warning: search path` lines). Then `grep -n "arrangements\[" Sources/Paneful/TilingController.swift` should print nothing, and `swift test` should pass all 179 tests.
- [ ] **Step 5: Commit** with `git commit -m "Keep each Space's arrangements separate"`.

---

### Task 3: Docs, install, manual check

**Files:**
- Modify: `CLAUDE.md`, `docs/history/README.md`, `docs/history/issues-and-fixes.md`, `docs/history/design-decisions.md`, `docs/history/macos-gotchas.md`
- Modify: the memory file `paneful-project.md`, in the auto-memory directory

- [ ] **Step 1: Write the doc edits:**
  - **`CLAUDE.md`, Architecture, "Saved layout vs working copy":** `Arrangement<Window>` holds one display's working tree **on one Space**. `SpaceArrangements` keys them by Space ID and display UUID, and drops empty ones. Per-Space actions use the current Space (`Spaces.current()`); layout, gap and display changes touch every Space.
  - **`CLAUDE.md`:** a bullet saying `Spaces.swift` is the only file that calls the private SkyLight functions (`CGSGetActiveSpace`).
  - **`issues-and-fixes.md`:** a new section, "Per-Space arrangements", with issue 23: "Resizing on one Space moved a window on another".
    - Symptom: the screenshots' scenario.
    - Root cause: arrangements were keyed by display only, and Accessibility can set the frames of windows on other Spaces.
    - Found by: Adam's screenshots, then the probe.
    - Fix: `SpaceArrangements`.
    - Commit: the hash of Task 2's commit.
  - **`design-decisions.md`:** a product row, "Live state per Space, saved layouts per display", with why: saved Space IDs can change after a reboot. An architecture bullet on the private Space ID, and that 0 falls back to one shared Space.
  - **`macos-gotchas.md`:** under Accessibility: Accessibility can still set frames of windows on other Spaces. A new "Spaces" item: `CGSGetActiveSpace(CGSMainConnectionID())` via `@_silgen_name` links through CoreGraphics (not Foundation alone), changes per Space, and gave a separate ID for a full-screen Space. With "Displays have separate Spaces" off (`defaults read com.apple.spaces spans-displays` = 1), there's one current Space.
  - **`docs/history/README.md`:**
    - a Timeline row dated 2026-10-07;
    - update the follow-up count and the test count (179);
    - Code map: `SpaceArrangements.swift` and `Spaces.swift`;
    - Known limitations: replace "A window moved to another Space is still considered tiled" with: "A window moved to another Space through Mission Control stays tiled on its old Space until it's dropped into a zone somewhere; until then, a resize on the old Space can still move it." Add: "With 'Displays have separate Spaces' turned on, the active display's Space is used for every display."
  - **Memory, `paneful-project.md`:** a dated line: per-Space arrangements built on branch `per-space-arrangements`, pending Adam's check.
- [ ] **Step 2: Run the full suite.** `swift test` should PASS with 179 tests.
- [ ] **Step 3: Commit** with `git commit -m "Document per-Space arrangements"`.
- [ ] **Step 4: Install and hand over.** Run `scripts/install.sh` (if codesign seems to hang, a keychain dialog is waiting). Then ask Adam to run the spec's manual checklist on his displays with two Spaces:
  1. Tile a window on X. On Y, tile two windows and resize them. Go back to X: its window hasn't moved.
  2. Shift-drag on each Space: the overlay shows that Space's own dividers.
  3. Reset Arrangement on Y leaves X's adjusted dividers alone.
  4. A layout change and a gap change apply on both Spaces.
  5. Move a window tiled on X to Y with Mission Control, then drop it into a zone on Y. Back on X, its old zone is empty.
  6. Split halves made on Y don't appear on X.
- [ ] **Step 5: Merge.** Once Adam confirms, run `git checkout main && git merge --ff-only per-space-arrangements`, then update the memory line to "merged". Push only if Adam asks.
