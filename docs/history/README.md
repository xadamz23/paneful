# Paneful — Project History

Paneful is a personal macOS menu bar window manager, built to replace BentoBox. You hold a modifier (Shift by default) while dragging a window, zones appear, and you drop the window into one. Windows that share an edge resize together. Each display has its own layout, which you can edit visually.

It was built between 2026-09-24 and 2026-09-25 by Adam and Claude (Claude Code), in three phases.

| File | What's in it |
|---|---|
| [issues-and-fixes.md](issues-and-fixes.md) | Every real problem we hit: symptom, root cause, how we found it, fix, commit |
| [macos-gotchas.md](macos-gotchas.md) | Platform and toolchain lessons: Accessibility API, SwiftPM without Xcode, SwiftUI, signing |
| [design-decisions.md](design-decisions.md) | Key design choices and why, including deliberate deviations from the spec |
| [../superpowers/specs/2026-09-24-paneful-design.md](../superpowers/specs/2026-09-24-paneful-design.md) | The design spec everything was built from |
| [../superpowers/plans/](../superpowers/plans/) | The three implementation plans (one per phase) |

## How we got here

It started with a question: *"Realistically, how difficult would it be to build something like Rectangle and BentoBox, just for my Mac?"* The honest answer:
- The core is easy.
- Dropping windows into zones and resizing neighbours together is medium.
- Matching Rectangle's polish is an endless stream of edge cases.

For personal use, only the cases Adam actually hits need handling.

Adam chose:
- **Zone layouts** (BentoBox-style) over keyboard shortcuts or drag-to-edge snapping.
- **Linked resizing:** widening one window narrows its neighbour, and the saved zones never change.
- A **visual editor** with presets that can be tweaked.
- A **separate layout per display.** His setup is a 3440×1440 Sceptre O35 ultrawide in the middle, with a 1920×1200 PA248QV on each side.
- A single **gap** setting that applies between zones and at screen edges.

## Timeline

| When | Phase | What happened |
|---|---|---|
| 2026-09-24 | Design | Brainstormed requirements one question at a time, then wrote and approved the spec (`67a02c4`). |
| 2026-09-24 | Phase 1: drop into zones | Layout model, geometry, settings, menu bar app, overlay and drag-to-snap. Fixed a toolchain flake and an edge-of-screen dead zone. Merged. |
| 2026-09-24 → 25 | Phase 2: linked resizing | Divider maths, drag classification, live following of the neighbour. Manual testing found five real bugs, from delayed Accessibility updates to macOS refusing resizes. All fixed. Merged. |
| 2026-09-25 | Phase 3: visual editor | Split, remove and divider-drag logic, the Edit Layouts window, and "Custom" layouts. The review plus Adam's testing found zone-ID reuse and tied dividers. Fixed. Merged. |
| 2026-09-25 | Ultrawide preset | Added "Thirds · 1440 middle", offered only on displays at least twice as wide as tall. Its proportions are calculated for the display and gap when you pick it, so the middle is exactly 1440 px: 992 \| 1440 \| 992 on the Sceptre at a 4 pt gap. If the gap changes later, the middle drifts a few pixels until you pick the preset again. (`ce47bca`) |
| 2026-09-25 | Restore size on drag-out | A tiled window dragged out of its zone gets back the size it had before it was first snapped. Moving it between zones keeps that original size. The restore happens when you let go, not during the drag, because moving a window mid-drag fights the window server. `Geometry.restoredFrame` keeps the top edge where you dropped it, keeps the grabbed spot under the cursor, and keeps the window on the display. Sizes are remembered only while Paneful runs. (`f55190f`) |

## Where it stands

- All three spec phases are done and merged to `main`, plus two follow-ups: the ultrawide preset and restoring a window's size on drag-out. There are 102 unit tests, all passing.
- It's installed at `/Applications/Paneful.app`, signed with a self-signed "Paneful Dev" certificate.
- Settings live in `~/Library/Application Support/Paneful/settings.json`.
- macOS's own window tiling is turned off (System Settings › Desktop & Dock), because it conflicts with Paneful.

### Build, install, test

```bash
swift test                 # unit tests for PanefulCore
scripts/install.sh         # build, sign, copy to /Applications, relaunch
scripts/make-signing-cert.sh   # one-time: creates the "Paneful Dev" signing identity
```

`install.sh` keeps the same signature, so the Accessibility permission survives rebuilds. If codesign ever seems to hang, look for a hidden keychain dialog. See [macos-gotchas.md](macos-gotchas.md).

### Code map

- `Sources/PanefulCore/`: pure, unit-tested logic.
  - `Layout.swift`: the split-tree layout model.
  - `Presets.swift`: the fixed presets, plus the ultrawide one computed per display and gap (`Presets.available(for:gap:)`).
  - `Geometry.swift`: zone rectangles with the gap, hit-testing a point to a zone, and where a dragged-out window lands (`restoredFrame`).
  - `Coordinates.swift`: flips between AppKit and Accessibility coordinates.
  - `Arrangement.swift`: each display's working copy of its layout, plus which windows are tiled where.
  - `Dividers.swift`, `Edge.swift`, `ResizeTracker.swift`: linked resizing.
  - `LayoutEditing.swift`, `LayoutDraft.swift`, `DividerDrag.swift`: the editor.
  - `Settings.swift`: persistence.
- `Sources/Paneful/`: the AppKit and SwiftUI app.
  - `WindowAccess.swift`: the only code that talks to the Accessibility API.
  - `TilingController.swift`: owns settings and arrangements, and snaps, refits and follows resizes. It also gives windows dragged out of their zone back their pre-snap size.
  - `DragMonitor.swift`: turns mouse presses into moves or resizes.
  - `OverlayController.swift`, `AppDelegate.swift`: the zone overlay and the menu.
  - `Editor*.swift`: the layout editor window.

## How we worked

The process is worth repeating on the next project:

1. **Brainstorm, then spec, then a plan per phase.** Requirements were settled one question at a time. The spec was approved before any code. Each phase got its own plan with exact code, tests and a manual checklist.
2. **Test-driven for the pure logic.** Everything testable lives in `PanefulCore` and was written test-first: watch the test fail, then make it pass. The app target is thin and checked by hand.
3. **One fresh reviewer per phase.** After each phase, an independent reviewer on the most capable model checked the whole branch. It found real bugs every time.
4. **Adam's manual checklist is the real test.** Most of the hard bugs only appeared on real displays with real apps: timing, Accessibility quirks, and how Ghostty and Finder behave.
5. **Systematic debugging.** Instead of guessing, we added temporary logging to a file, reproduced once, read the evidence, and fixed the root cause. For Accessibility problems, a small `swiftc` script driving the real window from the terminal was the fastest way to test a hypothesis. After three failed fixes we stopped and rethought the problem, which is how the "bottom of the screen" root cause was found.
6. **Ledger and rulings.** During each phase, every judgement call that departed from the plan was logged, then reported at the end with what it would cost if it turned out wrong.

One collaboration quirk: in Adam's terminal, text written just before a multiple-choice question can be hidden. Designs to review were therefore put in the question's preview panel.

## Known limitations and deferred items

These are accepted for now, and none are blockers:

- **Things Paneful doesn't notice:**
  - A window moved to another **Space** is still considered tiled.
  - A **minimised** window stays untiled after it's restored, so you re-snap it.
  - A tiled window moved to another display *without dragging* (from a Window menu, say) stays tiled, and a later resize can jump its dividers to their limits.
- **Extra work:**
  - Pressing anywhere in a tiled zone checks all of that zone's windows, not only when you're near an edge.
  - While following a resize, Paneful checks whether each neighbour is still minimised or closed on every mouse event.
  - Finishing a resize re-snaps every window on that display, including an unrelated window whose outer edge you'd resized.
- **Small behaviour gaps:**
  - When two windows refuse to shrink onto the same divider, which one wins is arbitrary.
  - Choosing a preset moves tiled windows by zone number, so the window in zone 1 goes to the new zone 1.
  - **"Thirds · 1440 middle" is exact only at the gap it was picked with.** After a gap change:
    - the middle drifts a few points until you pick the preset again;
    - the saved fractions no longer match the ones the Layout menu computes, so the menu shows the layout ticked above the presets, as it does for a Custom layout.
  - **Pre-snap sizes are kept only while Paneful runs.** After a relaunch, dragging a window out leaves it at its zone size.
  - A window that's closed, minimised or untiled by a refit keeps its remembered size (`sizesBeforeSnap`) until Paneful quits. It's a tiny leak, and harmless.
- **Editor polish:**
  - The prompt says "layout" when only the gap changed.
  - "px" is really points.
  - A gap from the editor that isn't on the Gap menu leaves nothing ticked there.
  - Quitting with unsaved edits drops them without asking.
  - There's no Cmd-W or Esc to close the window, because it's a menu bar app with no main menu.
- **Minor timing oddities:**
  - A click within 50 ms of a snap finishing could be misread.
  - A zone can come out at 99 pt instead of 100 because of rounding.
