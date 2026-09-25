# Paneful — Keyboard Moves and Fill Zones — Design Spec

## Context
Today the only way to put a window in a zone is to drag it with the snap modifier. Adam wants two faster ways:
- **Keyboard moves:** Ctrl+Option + an arrow key moves the focused window to the zone to its left, right, above or below, without the mouse.
- **Fill Zones:** one menu action puts untiled windows into every display's empty zones, for example after a reboot or after reconnecting a display.

Success:
- On the Sceptre in Thirds, Ctrl+Option+→ on a window in A moves it to B straight away.
- Keyboard moves never take a window to another display.
- One click on Fill Zones fills the empty zones on every display. Each window moves as little as possible.
- Nothing about drag-snapping changes.

**Out of scope:**
- choosing different keys (they're fixed);
- moving windows between displays by keyboard;
- stacking extra windows during a fill;
- a hotkey for Fill Zones.

## Behaviour

**Keyboard moves (Ctrl+Option + ← → ↑ ↓):**
- The keys act on the **focused window**: the frontmost app's focused window. They do nothing if it isn't a standard window, or if it's minimised or full screen.
- **A tiled window** moves to the zone next to it in that direction, **on the display it's tiled on**.
  - "Next to it" means the zones lying wholly past the window's edge (the edge of its block, if it spans) that overlap the window's range on the other axis. Of those, the nearest along the direction wins: the adjacent column or row.
  - If several remain, the one whose centre is nearest the window's centre on the other axis wins. Ties go to the lowest zone ID.
  - Examples:
    - Thirds: A → B → C, and → from C does nothing.
    - 2 × 2: TR ← goes to TL, and TL ↓ goes to BL.
    - 1 + 2: → from 0 goes to 1 or 2, whichever is nearer the window's vertical centre, and ← from 1 or 2 goes to 0.
- **At the display's edge nothing happens.** There's no wrapping, and the window never leaves the display.
- **A spanning window** leaves its span and moves into the single zone just past the span's edge, chosen by the same rule. For example, a window spanning Thirds A+B pressed → goes to C.
- **An untiled window:** the first press snaps it into the zone under its centre, on the display containing that centre, whatever the arrow. Later presses move it by direction. If its centre is on no display, nothing happens.
- A keyboard move is a snap, like a drop:
  - the pre-snap size is recorded on the first snap, so dragging the window out later restores it;
  - a stacked zone stays stacked;
  - linked resizing then works as usual.
- The hotkeys are swallowed, so apps never see Ctrl+Option+arrows. They're registered only while Accessibility is trusted. VoiceOver also uses Ctrl+Option, but only while it's on.

**Fill Zones (menu item, all displays):**
- It first untiles windows that were closed or minimised (`forgetClosedWindows`), so their zones count as empty.
- For each display:
  - **Empty zones** are zones no tiled window covers, including spans.
  - **Candidate windows** are untiled, standard, non-minimised, non-full-screen windows of visible regular apps, on the current Space, whose centre is on this display. Paneful's own windows are excluded.
  - Pairing is **greedy nearest**: repeatedly pair the closest (window centre, empty-zone centre) pair until zones or windows run out. Each window and zone is used once. Ties go by zone ID, then by order of the window list.
  - Each pair is snapped as a drop would be.
- Leftover windows stay untiled and aren't moved. Tiled windows aren't touched.

## Menu
"Fill Zones" goes just above "Reset Arrangement".

## Architecture
New logic lives in `PanefulCore` and is written test-first. The app changes are wiring.

| Unit | Change |
|---|---|
| `Navigation.swift` (new, core) | `Geometry.neighbour(of: Set<ZoneID>, toward: Edge, in: [ZoneID: CGRect]) -> ZoneID?`, the direction rule above. Directions reuse `Edge`: ↑ is `.top`, ↓ is `.bottom`. It uses `Geometry.union` for the block. |
| `Fill.swift` (new, core) | `Geometry.fill<W: Hashable>(empty: [ZoneID: CGRect], windows: [(W, CGPoint)]) -> [(W, ZoneID)]`, the greedy nearest pairing. Windows are an ordered list, so ties are deterministic. |
| `WindowAccess` | `focusedWindow()` and `visibleWindows()`. It stays the only file that calls the Accessibility API. |
| `HotKeys.swift` (new, app) | Carbon `RegisterEventHotKey` and `InstallEventHandler` for the four keys, with `start()` and `stop()`. It calls a closure with the `Edge`. |
| `TilingController` | `moveFocusedWindow(toward:)` and `fillZones()`, both through the existing `snap(_:to:on:)`. The untiled first press uses `Geometry.zone(at:in:gap:)`. |
| `AppDelegate` | Starts and stops `HotKeys` next to `DragMonitor` in `updateTrust`. Adds the Fill Zones item. |

**Current Space only.** Accessibility's window list appears to cover only the current Space. The probe on 2026-09-25 matched every standard window to an on-screen window. If a check with a window on another Space shows otherwise, `visibleWindows()` also drops windows that `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` doesn't list, matched by pid and frame.

## Verification
- **`swift test`:** all existing tests, plus:
  - **`NavigationTests`:**
    - Thirds left, right and both edges.
    - 2 × 2 in all four directions, including the edges.
    - 1 + 2: 0 → nearer of 1 or 2 by centre, and 1 and 2 → 0.
    - A span [A B] → C.
    - A span [TL TR] moving down.
    - Up and down with no zone above or below.
  - **`FillTests`:**
    - Nearest pairing across the screen.
    - More windows than zones: the nearest win and the rest are unassigned.
    - More zones than windows.
    - No zones.
    - Ties.
- **Manual, after `scripts/install.sh`, on the three displays:**
  - arrows in Thirds on the Sceptre, and in 2 × 2 and 1 + 2 on a PA248QV, including every edge;
  - a spanning window;
  - an untiled window's first press;
  - a window on a side display never leaving it;
  - linked resizing after a keyboard move;
  - dragging out after a keyboard snap restores the pre-snap size;
  - Fill Zones on an empty display, a partly filled display, and a display with more windows than zones.
