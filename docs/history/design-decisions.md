# Design Decisions

The choices that shape Paneful, and why we made them. The full design is in the [spec](../superpowers/specs/2026-09-24-paneful-design.md).

## Product decisions (Adam's)

| Decision | Why |
|---|---|
| **Zone layouts, not keyboard shortcuts or drag-to-edge** | BentoBox is what Adam uses. Edge-snapping was left out; keyboard moves came later (Ctrl+Option + arrows). |
| **Linked resizing, using zone-snapped windows only** | Only windows dropped into zones are linked. It's predictable, and it never grabs a window you didn't mean to move. |
| **Saved layouts never change when you resize** | Resizing adjusts a per-display *working copy*. Reset Arrangement, or plugging a display in or out, goes back to the saved layout. |
| **A dropped window fills the zone's *current* slot** | After you've resized, a new window fits the adjusted space, with no overlap. |
| **An outer edge (screen side) resizes freely and the window stays tiled** | It's fitted back into its zone on the next divider move or Reset. |
| **One gap for both between zones and screen edges** | A single setting, 0–40 pt, default 8. Adam uses 4. |
| **A layout per display** | Three displays: the ultrawide in the middle, and a PA248QV on each side. |
| **A visual editor, presets you can tweak, and nothing applied until Save** | The editor is only a preview until you click Save. Edited layouts are named "Custom". |
| **A window dragged out of its zone gets back its pre-snap size** | It's restored when you let go, not mid-drag. The top edge stays where you dropped it, and the spot you grabbed stays under the cursor. Moving a window between zones keeps its original size. |
| **An ultrawide preset whose middle is exactly 1440 pt** | "Thirds · 1440 middle" is offered only on displays at least twice as wide as tall. Its fractions are computed for the display and gap when it's offered. |
| **Span zones with a second key, as a block of whole zones** | Shift+Option-drag covers the anchor zone and the one under the cursor, never half a zone. A span is only where the window sits: the saved layout doesn't change, and a span whose zone is removed untiles its window. |
| **A display with no tiled windows goes back to its saved layout** | Once its last window is dragged out, moved to another display, closed or minimised, the next window lands in a saved-size zone without a Reset. Moving the only window to another zone on the same display keeps the adjusted sizes, because the zones never become empty. |
| **Keyboard moves with Ctrl+Option + arrows, within one display** | Moving a window one zone over shouldn't need the mouse. Keys are spatial (the zone physically left, right, above or below), stop at the display's edge rather than wrapping or changing display, and a span moves into the single zone past its edge. The keys are fixed, not a setting. |
| **Split on drop with a third key, top/bottom halves, working copy only** | Shift+Control-drag (Split Key ▸) splits the zone under the cursor into equal top and bottom halves, and a window already there moves to the other half, so two windows can share a zone without editing the layout. The halves disappear once both are empty, and a layout change, display change or Reset untiles windows in them. Halves under 100 pt give a plain snap. |
| **Fill Zones fills empty zones only, nearest first** | After a reboot or reconnect, one click tiles the untiled windows with the least movement. Tiled windows and leftover windows are left alone, so nothing is rearranged unexpectedly. |

## Architecture decisions

- **Layouts are split trees, not a list of rectangles.**
  - A node is either a zone or a split (an axis, its children, and their fractions).
  - Every boundary is a *divider*, so linked resizing is just "move one divider". Gaps and overlaps become impossible by construction, and the editor's "drag a divider" maps directly onto it.
  - The cost: "pinwheel" layouts (four rectangles interlocking around a centre) can't be expressed. That's fine in practice.
- **Same-axis splits are always flattened.** A side-by-side split never contains another side-by-side split, so each divider moves on its own (issue 16). This is enforced after every edit and when a layout is loaded.
- **Pure core, thin app.**
  - `PanefulCore` has no AppKit and is fully unit-tested: layout, geometry, divider maths, the resize tracker, editing and settings.
  - The app target, `Paneful`, only talks to macOS, and is checked by hand.
  - This split is what let most bugs be pinned down with a failing test.
- **One unit talks to the Accessibility API** (`WindowAccess`). Every Accessibility quirk we found is handled in one place.
- **Hotkeys use Carbon `RegisterEventHotKey`**, not an `NSEvent` key monitor or an event tap: no extra permission, and the keystroke is swallowed so apps never see it.
- **Windows are matched to zones by ID**, as a set per window (one zone, or a span), through `Arrangement<AXUIElement>`. That's why zone IDs must never be reused (issue 14). Each `Arrangement` has its own counter for split-drop zones, and rebasing or Reset untiles windows in them, because a new saved layout may reuse those IDs.
- **Presets are static fractions, with one exception.** `Presets.available(for:gap:)` adds the computed ultrawide preset, so the menu and the editor both list presets through it rather than `Presets.all`.
- **Settings are forgiving.** A missing, corrupt, partial or out-of-range settings file falls back field by field. A single bad saved layout no longer resets the others. An invalid layout falls back to Halves.

## Deliberate deviations from the spec

| Spec said | We did | Why |
|---|---|---|
| Detect drags with a `CGEventTap` | `NSEvent.addGlobalMonitorForEvents` | Same events, less code, and no extra permission needed. |
| Detect resizes with Accessibility notifications, plus 250 ms suppression of Paneful's own changes | Read the dragged window's frame on each mouse event | It works in every app. Paneful never moves the window being dragged, so there's no feedback loop and no suppression is needed. |
| A separate `LinkedResizer` unit | Logic in `TilingController`, state in `DragMonitor` | No class was needed for that little state. |
| Notice minimise, close and Space moves with observers | Check lazily, the next time Paneful tries to move the window | Simpler. Space moves still aren't detected (a known limitation). |
| Presets "Thirds" and "3 columns" | One preset, "Thirds" | They were the same layout. |
| Create the certificate in Keychain Access | `scripts/make-signing-cert.sh` | Less error-prone than clicking through Keychain Access. |
| Gap slider only in the editor | Also a Gap ▸ menu from Phase 1 | The gap needed to be settable before the editor existed. |
| A Layout ▸ preset submenu only until the editor exists | A preset submenu per display, kept alongside Edit Layouts… | A layout change is one click away, without opening the editor. |
| Release without the modifier → no-op | A tiled window dragged without the modifier is untiled, and its pre-snap size restored | Dragging a window out of its zone should give back the size it had before you tiled it. |
| SwiftUI editor | SwiftUI without `@State`, `@Observable` or `#Preview` | The SwiftUI macros need Xcode. All view state lives in `EditorModel`. |

## Tooling decisions

- **No Xcode.** Everything is built with SwiftPM and Command Line Tools, with a script that assembles and signs the `.app`. The trade-offs:
  - The TestingMacros workaround.
  - No SwiftUI macros.
  - No debugger. Temporary file logging and Accessibility scripts took its place.
- **macOS 14 as the minimum version**, with no third-party dependencies.
- **Self-signed code signing** keeps the Accessibility permission across rebuilds. There's no notarisation or App Store: Paneful is only ever installed on Adam's Mac.
