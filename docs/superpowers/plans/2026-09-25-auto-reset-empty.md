# Auto-reset a display's arrangement when its last tiled window leaves

## Context
Resizing adjusts each display's working copy (`Arrangement.working`). The adjustment stays until Reset Arrangement is picked from the menu, even after every window has left, so the next window dropped there lands in the old adjusted zone. Adam wants a display with no tiled windows to go back to its saved layout on its own.

Decided with Adam: moving the only tiled window to another zone on the **same** display keeps the adjusted sizes, because the zones never actually become empty. The reset happens only when a display really has no tiled windows left: its last window is dragged out, moved to another display, closed or minimised.

## Approach

### Core (test-first) — `Sources/PanefulCore/Arrangement.swift`
- `remove(_:)`: after removing the window, if `zonesOf` is empty, set `working = saved.root`. This keeps the rule "an arrangement with no windows is at its saved layout".
- Every other way a window leaves already goes through `remove`, so they all get the reset:
  - `TilingController.untile`, used by `snap` and `dragOut`;
  - `refit`, which untiles closed or minimised windows;
  - `rebased`, which starts a fresh arrangement anyway.
- New tests in `Tests/PanefulCoreTests/ArrangementTests.swift`, next to `removeUntilesWindow`. Each one moves a divider first with `moveEdge`, as `moveEdgeChangesWorkingButNeverSaved` does:
  - `removingTheLastWindowRestoresTheSavedTree`
  - `removingOneOfTwoWindowsKeepsTheWorkingTree`
  - `reassigningTheOnlyWindowKeepsTheWorkingTree`: `assign` to another zone never resets.

### App — `Sources/Paneful/TilingController.swift`
- **`snap`** currently calls `untile(window)`, which would empty the display and reset it mid-snap. The landing rect is computed before that call, so the window would land in an adjusted rect while the arrangement is back at the saved one.
  - Change: remove the window only from the *other* displays' arrangements, then `assign` on the target. `assign` already replaces the window's zones.
  - Moving from display A to display B still empties A and resets it.
- **Closed windows aren't noticed until the next refit**, so a display whose last window was closed would still look adjusted.
  - Add `forgetClosedWindows()`, which removes (via `remove`, so the reset follows) every tiled window where `WindowAccess.isGone`, `WindowAccess.isMinimized` is true, or `WindowAccess.frame(of:) == nil`.
  - Nothing moves on screen: an empty display has no windows to refit.
- **`Sources/Paneful/DragMonitor.swift`:** in `classify`, call `tiling.forgetClosedWindows()` when a press becomes `.moving`, before `updateMove`. The overlay and the snap then both see the reset layout. It costs a few Accessibility reads per tiled window, once per window drag.

### Docs
- `docs/history/design-decisions.md`: add a product-decision row.
- `docs/history/README.md`: add a timeline row and update the test count.
- `CLAUDE.md`: one clause in "Saved layout vs working copy" saying the working copy resets when the last window leaves.
- Save this plan as `docs/superpowers/plans/2026-09-25-auto-reset-empty.md`.

### Workflow
- Work on a new branch, `auto-reset-empty`, off `main`.
- Commit only after Adam has tested; merge `--ff-only` when he asks.

## Verification
1. Run `swift test`. The three new tests fail before the `remove` change and pass after it, and all existing tests still pass.
2. Run `scripts/install.sh`, then Adam checks:
   - Thirds on the Sceptre with two windows. Resize the shared edge, drag both out with no Shift, then Shift-drag one back in. The overlay and the landing zone should be at the saved thirds.
   - Same setup, but close both windows (Cmd-W) instead. The next Shift-drag should show the saved zones.
   - One window, resized. Shift-drag it to another zone on the same display. It should keep the adjusted sizes.
   - The last window on a PA248QV, Shift-dragged onto the Sceptre. The PA248QV should reset; check by dropping a new window there.
