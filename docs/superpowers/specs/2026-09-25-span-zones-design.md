# Paneful — Span Zones — Design Spec

## Context
Today a window dropped with the snap modifier always fills exactly one zone. Adam wants to drop a window across several zones, for example the left and middle zones of Thirds, without editing the layout. While dragging with the snap modifier (Shift), he holds a second key, the **span key** (Option by default), which stretches the target across zones. Releasing drops the window into the combined rect.

Success:
- Shift+Option-dragging over two neighbouring zones shows one landing rect covering both, and releasing fills it exactly.
- A spanning window resizes with its neighbours just like a single-zone window.
- Nothing changes for drags without the span key.

**Out of scope:** spans that aren't rectangles, and saving spans in the layout (a span is placement only; the saved layout never changes).

## Behaviour

**Choosing the span (anchor + current):**
- With the snap modifier and the span key held, the zone under the cursor when the span key goes down becomes the **anchor**. Pressing it mid-drag works too.
- The span is the smallest block of whole zones covering the anchor and the zone now under the cursor.
  - It's built from the two zones' bounding box, then any zone that overlaps the box is added and the box grows, repeated until stable. So a span never half-covers a zone.
  - Examples: in Thirds, A → B gives A+B, and A → C gives all three. In 2 × 2, TL → BR gives the whole screen.
- Moving back over the anchor shrinks the span to that one zone.
- Releasing the span key, or moving to another display, drops the anchor. The target goes back to a single zone, and pressing the span key again sets a new anchor.
- The span key without the snap modifier does nothing special. It's a plain drag, so a tiled window is untiled and its pre-snap size restored.

**Overlay:** the zones in the span are drawn as one highlighted rounded rect, which is the exact landing rect. The other zones are drawn as now.

**Snapping:** the window is untiled from wherever it was and assigned to the span's set of zones. Its frame is the union of those zones' current rects. As today, a window can share zones with other windows (stacked).

**Linked resizing:**
- A spanning window's edge moves the divider under that edge for **every** zone in the span whose edge lies on the span's outer edge. The neighbours follow live.
  - Example: in 2 × 2, a window spanning TL+TR has its bottom edge over two separate row dividers (one per column). Dragging it moves both.
- A span's outer edge against the screen resizes freely, the same as an outer edge today.
- Moving a divider *inside* a span (from a window stacked in one of its zones) doesn't change the span's rect.
- Refusing windows: `finishResize` grows a spanning window's block until it fits, using the same trailing-then-leading rule as today, applied to the block's edges.

**Layout changes (preset, editor Save, display changes):** a spanning window stays tiled only if all its zones still exist in the new layout; otherwise it's untiled. Reset Arrangement refits it to its span.

**Restore on drag-out:** unchanged. The pre-snap size is recorded on the first snap, single or span.

## Settings and menu
- `Settings.spanModifier`, a `ModifierKey`, defaults to `.option`.
  - It's decoded tolerantly, like `modifier`: a missing or unknown value becomes Option.
  - If a loaded file has both keys equal, the span key falls back to the first other key.
- The two keys can never be equal. Setting either key to the other's value swaps them.
- The menu gets a "Span Key ▸" submenu after "Modifier ▸", listing the same four keys.

## Architecture
All the new logic is in `PanefulCore` and written test-first. The app changes are wiring.

| Unit | Change |
|---|---|
| `Span.swift` (new, core) | `Geometry.span(from:to:in:) -> Set<ZoneID>`, the block-closure rule. `Geometry.union(of:in:)`, the bounding rect of a set of zones. "Overlap" means positive width and height, so zones touching at gap 0 don't count. |
| `Arrangement` | Maps each window to a `Set<ZoneID>`, and a normal snap is a set of one. `assign(_:to:)` takes a set (the single-zone form stays, as a wrapper) and is ignored unless every zone exists. `zones(of:)` replaces `zone(of:)`. `windows(in:)` includes spanning windows. `rect(of:in:gap:)` is the union. `rebased(on:)` keeps a window only if all its zones survive. `moveEdge` and `fit` take a zone set and act on the block's edges. |
| `Settings` | `spanModifier`, plus the `setModifier` and `setSpanModifier` swapping setters. |
| `DragMonitor` | `.moving` carries the target zone set and the anchor. `updateMove` computes the span when both keys are held. |
| `OverlayController` | Highlights a landing rect (`CGRect?`) instead of a zone ID. |
| `TilingController` | Snaps to a zone set, and uses per-window union rects in `refit`, `followResize` and `finishResize`. The modifier setters go through `Settings`. |
| `AppDelegate` | The Span Key ▸ submenu. |

## Verification
- **`swift test`:** every existing test passes unchanged, since single-zone is the one-element case. New tests:
  - **`SpanTests`:**
    - Thirds A→B, A→C and back to A.
    - 2 × 2 TL→TR and TL→BR.
    - Unaligned rows pulling in neighbours.
    - Gap 0.
    - The same zone.
  - **`ArrangementTests`:**
    - A set assign, and the union rect.
    - `windows(in:)` with spans.
    - `rebased` dropping a broken span.
    - A span's bottom edge moving two dividers.
    - An internal divider leaving the span's rect alone.
    - `fit` growing a span.
  - **`SettingsTests`:**
    - The default, and a missing key.
    - Equal keys on load.
    - Swapping.
- **Manual, after `scripts/install.sh`, on the three displays:**
  - **Snapping:** Thirds A+B on the Sceptre, and 2 × 2 TL+TR on a PA248QV. Check there's one landing rect.
  - **Mid-drag:** press Option mid-drag, then move back to the anchor.
  - **Linked resizing:** the span's shared edge, including the 2 × 2 bottom edge moving both row dividers.
  - **Minimum sizes:** a window with a minimum size spanning two zones.
  - **Menu:** Span Key ▸ swapping with Modifier ▸.
  - **Layout changes:** Reset and a preset change.
