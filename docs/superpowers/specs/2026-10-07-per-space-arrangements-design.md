# Paneful — Per-Space Arrangements — Design Spec

## Context
Adam tiled a window on Space X, then tiled and resized windows on Space Y. When he went back to X, its window had resized too.

The cause: `TilingController.arrangements` is keyed by display UUID only, so every Space on a display shares one `Arrangement`, with one set of working dividers, split halves and tiled windows. A resize on Y moves those shared dividers, and `refit` then sets the frame of every tiled window on that display. That includes X's window: Accessibility can set the frame of a window on another Space, even though `kAXWindowsAttribute` doesn't list it.

Success:
- Each Space has its own live state per display: its working dividers, its split halves, which windows are tiled where, and the auto-reset when its last window leaves.
- Resizing, splitting, dropping, Fill Zones and Reset on one Space never move a window on another Space.
- Saved layouts, the editor, the menu and `settings.json` don't change.

**Out of scope:**
- **Saved layouts per Space.** Space IDs are private window-server numbers that can change after a reboot, so saving them is a separate feature.
- **Noticing a window moved to another Space through Mission Control.** As today, it stays tiled where it was until it's dropped into a zone somewhere.
- **"Displays have separate Spaces" turned on.** Adam has it off (`spans-displays = 1`), so all displays switch Spaces together and there's one current Space. With it on, the active display's Space ID would be used for every display.

## Identifying the Space
- A new `Spaces.current() -> Int` in the app target returns `CGSGetActiveSpace(CGSMainConnectionID())`.
  - Both calls are private SkyLight functions, declared with `@_silgen_name`. CoreGraphics re-exports them, so the app links them through AppKit, with no third-party dependency.
  - They're read-only and work with SIP on.
  - A probe on 2026-10-07 confirmed the ID changes with the Space and stays stable per Space: 8, then 7, back to 8, then 77 for a full-screen Space.
- **It's read fresh on every call**, so no Space-change notification is needed. Every gesture, hotkey and menu action works on the Space that's current at that moment.
- **If the call fails, it returns 0.** All state then lives under Space 0, which is exactly today's behaviour.

## Behaviour
**Current Space only:**
- Drops (plain, span and split), the split preview, the overlay's zone rects, drag-out, keyboard moves, following and finishing a resize, press candidates, Fill Zones and Reset Arrangement.
- `isTiled` and `location(of:)` look only at the current Space.

**Every Space:**
- **A layout change** (menu or editor Save) rebases every Space's arrangement for that display, then refits them.
- **A gap change** refits every Space.
- **A display reconfiguration** (`refreshDisplays`) rebases every Space's arrangement for each display that's still connected, drops arrangements for displays that are gone, and refits them all.
- **`forgetClosedWindows`** checks every Space.

All four are deliberate, global edits. Moving windows on other Spaces to match is what Adam would expect.

**Tiling a window on one Space untiles it everywhere else.** Today, snapping untiles the window from other displays. Now it also untiles it from every other Space, so a window moved to Y through Mission Control and then dropped into a zone on Y no longer belongs to X.

**Empty arrangements are dropped.** An arrangement with no tiled windows already equals a fresh one for its saved layout, because `remove` resets it. So dropping it loses nothing, and the state for removed Spaces never piles up.

**Unchanged:**
- `sizesBeforeSnap` stays global. A window's size from before its first snap is the same on every Space.
- Split-zone IDs stay per arrangement, so each Space has its own never-reused counter.

## Architecture
The new logic is in `PanefulCore` and written test-first. The app changes are wiring.

| Unit | Change |
|---|---|
| `SpaceArrangements<Window>` (new, core) | Arrangements keyed by Space ID and display UUID. It provides: the arrangement for a key (or a fresh one from a given saved layout); storing an arrangement back, dropping it if it has no tiled windows; tiling a window under a key after untiling it from every other key; untiling a window everywhere; a window's display and zones on one Space; rebasing one display's arrangements on every Space; dropping displays no longer connected; and listing every stored key. `Arrangement` doesn't change. |
| `Spaces` (new, app) | `current()`, wrapping the private call. |
| `TilingController` | Holds a `SpaceArrangements<AXUIElement>` instead of `[String: Arrangement]`. Each method works on the current Space's key or on every key, as listed above. `refit` takes a Space as well as a display. |
| `DragMonitor`, `AppDelegate`, editor, `Settings`, `OverlayController` | No change. |

## Verification
- **`swift test`:** every existing test passes unchanged. New `SpaceArrangementsTests` check:
  - A missing key gives a fresh arrangement from the saved layout.
  - Tiling under one key untiles the window from other Spaces and other displays.
  - A window's location is found only on its own Space.
  - Moving a divider under one key leaves the same display's arrangement on another Space untouched.
  - Rebasing a display changes it on every Space and leaves other displays alone.
  - Dropping disconnected displays removes their keys on every Space.
  - An arrangement stored with no tiled windows is dropped, and reading it back gives a fresh one.
- **Manual check** (after `scripts/install.sh`), on Adam's three displays with two Spaces:
  1. Tile a window on X. On Y, tile two windows and resize them. Go back to X: its window hasn't moved.
  2. Shift-drag on each Space: the overlay shows that Space's own dividers.
  3. Reset Arrangement on Y leaves X's adjusted dividers alone.
  4. A layout change and a gap change apply on both Spaces.
  5. Move a window tiled on X to Y with Mission Control, then drop it into a zone on Y. Back on X, its old zone is empty (Fill Zones or a drop can use it).
  6. Split halves made on Y don't appear on X.
