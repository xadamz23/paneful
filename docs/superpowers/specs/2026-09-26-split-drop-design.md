# Paneful — Split on Drop — Design Spec

## Context
Today a Shift-drag drops a window into one zone, and Shift+Option spans it across several. Adam wants two windows to share a zone without editing the layout. While dragging with the snap modifier, he holds a third key, the **split key** (Control by default). The zone under the cursor then previews as two equal halves, top and bottom, and releasing drops the window into the half under the cursor.

Success:
- Shift+Control-dragging over a zone shows it as two halves and highlights the one under the cursor. Releasing fills that half exactly.
- If the zone already held a window, that window moves into the other half. The two share a divider and resize together.
- Once both halves are empty, the zone is whole again.
- Nothing changes for drags without the split key.

**Out of scope:**
- Left/right splits, and splits other than 50/50.
- Saving splits in the layout. A split is placement only, in the working copy, and the saved layout never changes.
- Keeping split halves across layout or display changes.

## Behaviour

**Choosing the half:**
- With the snap modifier and the split key held, the target is the zone under the cursor (`Geometry.zone(at:)`, as now).
  - The half is **top** if the cursor is above the zone's mid-y, otherwise **bottom**.
  - Pressing or releasing the split key mid-drag updates the target straight away.
- If the span key is held as well, the split key wins: the target is a half of the zone under the cursor, not a span.
- If either half would be shorter than the minimum zone size (100 pt), the zone can't be split. The target is then the whole zone, as a plain snap.
- The split key without the snap modifier does nothing special. It's a plain drag.

**Overlay:**
- The overlay draws the display's zones with the target zone replaced by its two halves, exactly as they would be after the drop, gap included.
- The half under the cursor is highlighted.
- The overlay's API doesn't change: it gets the preview rects and the landing rect.

**Dropping into zone B:**
- B's working-tree node is split with `Node.splitting(B, along: .horizontal, newZone: N)`. B keeps the top half and the new zone N takes the bottom half.
  - If B sat in a top-to-bottom split, the halves join that split (flattening), so every divider still moves on its own.
- The dragged window is untiled from wherever it was and assigned to the half it was dropped on.
- **Occupant:** every other window that covered exactly `{B}` moves to the other half and is refitted.
- **Spans:** every window whose span includes B gets both B and N, so it still covers the same area.
- A half is an ordinary zone, so it can be split again, spanned, resized, filled by Fill Zones, and reached by keyboard moves.

**Collapsing:**
- After any change to which zones windows cover (assign, remove), Paneful looks for a **split-created zone** that is empty (no window covers it, spans included) and whose previous sibling in its split is an empty leaf zone. It removes that zone with `Node.removing`, which gives its space to the previous sibling. This repeats until nothing changes.
- A split-created zone is always placed right after the zone it came from, so its previous sibling is always part of the same original zone.
- If only one half is empty, the split stays, so the empty half can still be dropped into.
- When a display's last window leaves, the working tree resets to the saved layout, as now, and all its splits go with it.

**Zone IDs:**
- Each `Arrangement` has its own ID counter. It starts at the saved layout's highest ID + 1 and only ever goes up, so a split never reuses an ID.
- The arrangement remembers which zones it created. `reset()` (Reset Arrangement) forgets them and untiles any window covering one, the same as `rebased(on:)` below.

**Layout and display changes:**
- `rebased(on:)` untiles any window that covers a split-created zone. This is because the new saved layout could use that ID for a different zone.
- Windows in unsplit zones behave as now.
- **Known limitation:** a display reconfiguration (for example plugging in a display, and possibly waking from sleep) calls `refreshDisplays`, which rebases every arrangement. So windows in split halves are untiled and stay where they are. They can simply be dropped again.

**Restore on drag-out:** unchanged. The size from before the first snap is recorded however the window was first snapped.

## Settings and menu
- `Settings.splitModifier` is a `ModifierKey` and defaults to `.control`.
  - It's decoded tolerantly: a missing or unknown value becomes Control.
  - If a loaded file has two keys equal, the later key (span, then split) falls back to the first key not already used.
- **The three keys are always distinct.** Setting one key to another's value swaps them: the other key takes the old value. This generalises today's modifier/span swap.
- The menu gets a "Split Key ▸" submenu after "Span Key ▸", listing the same four keys.

## Architecture
All the new logic is in `PanefulCore` and written test-first. The app changes are wiring.

| Unit | Change |
|---|---|
| `Arrangement` | `split(_ zone:, dropping window:, intoTop:, in frame:, gap:, minSize:) -> ZoneID?` does the split, moves the occupant, extends spans, assigns the window, and returns the half it landed in. It returns nil and changes nothing if the halves would be too small. It also gets the ID counter, the set of split-created zones, collapsing in `assign` and `remove`, `reset()` clearing splits, and `rebased(on:)` dropping windows in split zones. |
| `Settings` | `splitModifier`, and the three-way swapping setters: `setModifier`, `setSpanModifier`, `setSplitModifier`. |
| `DragMonitor` | The `.moving` target can be a split: display, zone, and top/bottom. `updateMove` asks `TilingController` for the preview when the split key is held, and release calls the split snap. |
| `TilingController` | `splitPreview(of:top:on:)` runs the split on a copy of the arrangement and returns its rects and the landing rect. `snap(_:splitting:top:on:)` does the same bookkeeping as `snap`, then refits the display so the occupant moves. Also `setSplitModifier`. |
| `AppDelegate` | The Split Key ▸ submenu. |
| `OverlayController` | No change. |

## Verification
- **`swift test`:** every existing test passes unchanged. New tests:
  - **Split drop:**
    - Top and bottom drops land in the right half, and the rects are equal halves.
    - The occupant moves to the other half.
    - A span that includes the zone gets both halves.
    - Splitting inside a top-to-bottom split flattens into it.
    - A half can be split again.
    - Too small: returns nil and nothing changes.
    - IDs are never reused after a collapse and another split.
  - **Collapse:**
    - It happens only when both halves are empty.
    - The rects are back to the original afterwards.
    - One empty half keeps the split.
    - A chain of halves collapses fully.
  - **`rebased`:** it untiles windows in split zones and keeps the others.
  - **Settings:**
    - The split key's default, and a missing value.
    - Equal keys on load.
    - Three-way swaps.
- **Manual, after `scripts/install.sh`, on the three displays:**
  1. **Preview:** Shift-drag, then press Control over a zone. Two halves preview, and the one under the cursor highlights. Drop in the top half and the window fills it.
  2. **Occupant:** drop into an occupied zone. The occupant moves to the other half. Dragging the shared divider resizes both.
  3. **Collapse:** drag both windows out. The zone is whole again.
  4. **Too small:** in a zone under 200 pt tall, there's no split preview and the drop is a plain snap.
  5. **Menu:** Split Key ▸ swaps with a colliding key, and the setting survives a relaunch.
  6. **Other features:** Fill Zones and Ctrl+Option arrows reach the halves.
