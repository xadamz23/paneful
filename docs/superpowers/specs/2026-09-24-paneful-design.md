# Paneful — Design Spec

## Context
Adam wants a personal macOS window manager (installed only on his own Mac) to replace BentoBox. Core need: drag a window while holding a modifier to drop it into user-defined zones, and have adjacent tiled windows resize together (widen one → neighbour narrows) without ever changing the saved zone layout. Multiple displays, each with its own layout. A configurable gap applies between zones and at screen edges.

Success: BentoBox can be uninstalled without being missed; resizing a tiled window never leaves a gap or overlap with its neighbour; saved layouts never drift.

**Out of scope (v1):** keyboard shortcuts, drag-to-edge snapping, App Store / notarization, pinwheel (non-guillotine) layouts.

## Environment
- Empty dir `/Users/us10060870/me/code/personal/paneful`, not yet a git repo.
- Command Line Tools only (no Xcode), Swift 6.4. Build via SwiftPM + bundle script.

## Architecture
Menu bar app (`LSUIElement`, no Dock icon). SwiftPM package with two targets:
- **PanefulCore** — pure Swift, unit-tested: LayoutModel, Geometry, Arrangement, Settings codec.
- **Paneful** — AppKit/SwiftUI app: WindowAccess, DragMonitor, Overlay, LinkedResizer, Editor, MenuBar.

| Unit | Responsibility | Depends on |
|---|---|---|
| LayoutModel | Split-tree `Layout` types + presets | — |
| Geometry | Tree + visible frame + gap → zone rects; AX (top-left) ↔ AppKit (bottom-left) conversion | LayoutModel |
| Arrangement | Per-display working copy of the tree (adjusted fractions) + zone→window membership; divider lookup/move | LayoutModel, Geometry |
| WindowAccess | Only AX-touching unit: window under cursor, get/set frame, AXObserver move/resize/destroy/minimise notifications | — |
| DragMonitor | CGEventTap (mouse down/drag/up, flagsChanged); shows overlay, snaps on release | WindowAccess, Arrangement, Overlay |
| Overlay | Per-display borderless, click-through NSWindows drawing zones + highlighted zone | Geometry |
| LinkedResizer | On tiled-window resize: detect moved edge → move divider → apply to affected windows; suppress self-triggered events | WindowAccess, Arrangement |
| Settings/Persistence | JSON in `~/Library/Application Support/Paneful/`: layouts keyed by stable display ID, gap, modifier | LayoutModel |
| Editor (phase 3) | SwiftUI layout editor | LayoutModel, Settings |
| MenuBar | Status item + permission onboarding | all |

## Data model
- `Layout` = name + root `Node`. `Node` = `.zone(id)` | `.split(axis: .horizontal|.vertical, children: [Node], fractions: [Double])`.
- A **divider** = boundary between two adjacent children of a split. Presets are predefined trees: Halves, Thirds, 60/40, 40/60, 2×2, 1+2, 3 columns.
- **Gap** (single setting, 0–40 px, default 8): inset visible frame by `gap` on all sides; siblings separated by `gap`; fractions apply to the space after gaps. Same function drives overlay and window frames.
- **Arrangement** = per-display working copy of the saved tree + zone membership (a zone may hold multiple stacked windows). Saved layout is never mutated by resizing.
  - Reset Arrangement → copy saved tree, re-snap all tiled windows.
  - Display config change → rebuild from saved layouts, re-fit windows (adjustments lost).

## Behaviour
**Snapping:** modifier (Shift default; Shift/Option/Control/Command selectable) held while a window is actually moving (title-bar drag) → overlay on the display under the cursor. Modifier may be pressed mid-drag. Release over zone → remove window from any previous zone, set frame to the zone's *current* rect. Release outside zones or modifier released first → hide overlay, no-op.

**Linked resizing:** on tiled-window resize:
1. Compare new frame to zone rect → which edge moved.
2. Find divider on that edge (nearest ancestor split where zone borders a sibling on that side).
3. Set that divider's fraction from the new edge; clamp so no zone < ~100 px.
4. Recompute rects; apply to all windows in changed zones; mark own changes and ignore their events for ~250 ms.
5. If a window refuses the size (min size / Terminal grid), read back real frame and move divider to match.

**Outer edge** (edge facing screen border, no neighbour): allowed; window keeps its size and stays tiled; re-fitted on next divider move touching it or Reset.

**Leaving tiled state:** plain drag without modifier, close, minimise, moved to another Space/display → removed from zone.

**Ignored:** full-screen and Stage Manager windows.

## UI
- **Overlay:** translucent rounded rects inset by gap (exact landing rect), hovered zone highlighted; follows cursor across displays, each showing its own layout.
- **Menu bar:** Edit Layouts… | Reset Arrangement | Modifier ▸ | Launch at Login | Quit. Before the editor exists: Layout ▸ submenu to pick a preset per display.
- **Editor (phase 3):** display picker; preset strip; canvas at display aspect ratio — drag dividers, select zone → Split Horizontally / Split Vertically / Remove (merge into sibling); gap slider with live preview; Save writes layout for display and resets its arrangement.
- **Permissions:** first run without Accessibility → one prompt with button opening the right System Settings pane; polls until granted. If revoked while running → features pause, menu icon shows warning.

## Build & signing
- `scripts/build-app.sh`: `swift build -c release`, assemble `Paneful.app` (Info.plist, `LSUIElement=YES`), codesign with self-signed "Paneful Dev" certificate so Accessibility permission survives rebuilds.
- `scripts/install.sh`: copy to `/Applications`, relaunch.
- One-time manual step for Adam: create the certificate in Keychain Access (exact steps provided).

## Phases
1. PanefulCore model + geometry + gap, WindowAccess, DragMonitor, Overlay, preset menu per display, persistence, permissions.
2. LinkedResizer.
3. Visual editor.

## Verification
- `swift test` for PanefulCore: presets, tree → rects with gap, coordinate conversion, divider lookup from moved edge, clamping, arrangement vs saved layout, reset.
- `scripts/build-app.sh && scripts/install.sh`, then a manual checklist per phase: Adam drags real windows (Finder, Safari, Terminal, an Electron app) across both displays, resizes shared edges, plugs/unplugs a display, and reports results; iterate.
