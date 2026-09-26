# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Paneful is Adam's personal macOS menu bar window manager (a BentoBox replacement):
- Hold a modifier (Shift by default) while dragging a window to drop it into zones.
- Windows that share an edge resize together.
- Each display has its own layout, which can be edited visually.

It's only ever installed on Adam's Mac: no App Store, no notarisation. Project history, every bug we've hit and its root cause, and platform gotchas are in `docs/history/`. Read `docs/history/macos-gotchas.md` before touching window moving, the build or the editor UI.

## Commands

The toolchain is **Command Line Tools only: no Xcode**. Swift 6.4 and SwiftPM.

```bash
swift build                                            # debug build
swift test                                             # all PanefulCore unit tests (Swift Testing)
swift test --filter LayoutEditingTests                 # one suite
swift test --filter "LayoutEditingTests/splitSideBySide"   # one test
scripts/install.sh      # release build, sign, replace /Applications/Paneful.app, relaunch
scripts/build-app.sh    # build and sign build/Paneful.app only
```

There's no linter. The `ld: warning: search path '/Library/Developer/CommandLineTools/Developer/…' not found` lines are harmless.

- **Signing.** `install.sh` signs with the self-signed "Paneful Dev" identity, which `scripts/make-signing-cert.sh` creates once in the login keychain. The stable signature is what keeps the Accessibility permission across rebuilds; ad-hoc signing loses it every time. If codesign seems to hang, a keychain dialog is waiting for Adam to click "Always Allow".
- **Tests.** The test target loads the Swift Testing macro plugin explicitly in `Package.swift` (`-load-plugin-library …/libTestingMacros.dylib`), because without Xcode the build backend intermittently omits it. Keep that flag. XCTest isn't available.

## Architecture

There are two SwiftPM targets:

- **`PanefulCore`** is pure Swift with no AppKit, and is fully unit-tested. All geometry uses **Accessibility coordinates**: origin at the top-left of the primary display, y going down.
- **`Paneful`** is the AppKit/SwiftUI app (`LSUIElement`, so menu bar only). It's thin and has no automated tests: Adam verifies it by hand with a checklist.

The ideas that span several files:

- **Layouts are split trees** (`Layout.swift`). A node is `.zone(id)` or `.split(axis, children, fractions)`.
  - `.vertical` means vertical dividers, with children left to right. `.horizontal` means children top to bottom.
  - Every boundary between siblings is a **divider**. Linked resizing and the editor both just move dividers (`Dividers.swift` `movingEdge`, clamped by `minExtent` to 100 pt zones).
  - Same-axis nesting is always **flattened** (`LayoutEditing.swift` `flattened()`): after every split and remove, and when `Settings` loads a layout. Nesting would tie dividers together.
- **Saved layout vs working copy.**
  - `Settings.layouts[displayUUID]` is the saved layout, and resizing never writes to it.
  - `Arrangement<Window>` holds a display's working tree (the adjusted fractions, back to the saved layout once its last window is removed) plus which zones each window covers: a set, one zone or a span (`Geometry.span`). A span's edge can sit on dividers in different splits, so `Arrangement.moveEdge` always moves every divider tied to it by a tiled span, and aligns them if one clamps. `Arrangement.split` (split drops) adds top/bottom halves to the working tree only, with IDs from the arrangement's own counter; an empty split-created zone collapses once the zone before it is empty too, and `rebased`/`reset` untile windows in split zones.
  - Windows are matched to zones by **zone ID**. So `Arrangement.rebased(on:)` keeps windows whose zone IDs all survive a layout change, and zone IDs must never be reused (`LayoutDraft.nextZoneID`).
- **`Geometry.zoneRects`** turns a tree, a display's visible frame and the gap into zone rects. One gap is used both between zones and at the screen edges, and each boundary is rounded once so neighbours share edges exactly. The overlay, snapping, refits and the editor canvas all use this one function.
- **`TilingController`** is the app's hub. It owns the settings, the displays (`Displays.current()`, keyed by display UUID) and each display's `Arrangement`. It snaps windows, refits them, follows live resizes (`followResize`) and finishes them (`finishResize`, which grows zones for windows that refused to shrink via `Arrangement.fit`). When a tiled window is dragged out of its zone, `dragOut` gives it back the size from before its first snap (`sizesBeforeSnap`, placed with `Geometry.restoredFrame`). Everything the menu, the drag monitor and the editor do goes through it.
- **`WindowAccess`** is the **only** file that calls the Accessibility API. It hard-won several rules:
  - `setFrame` first moves a window onto the target display if it isn't inside it, because macOS ignores resizing a window whose bottom hangs off its screen.
  - It then sets size, position, size, because some apps ignore a resize that comes straight after a move.
  - Setters report success even when they did nothing.
- **`DragMonitor`** uses a global `NSEvent` monitor. It turns each press into a gesture: `pending` becomes `moving` (the modifier shows the overlay and release snaps; holding the span key too stretches the target from an anchor zone; holding the split key instead splits the zone under the cursor and previews the halves via `TilingController.splitPreview`) or `resizing` (a tiled window's edge drag, where dividers follow live).
  - It classifies by watching candidate windows' frames change, and must keep watching until mouse-up: a dragged window's position is reported about 37 events late.
  - `ResizeTracker` locks one dragged edge per axis, because torn position/size reads make the opposite edge appear to move.
- **Keyboard moves and Fill Zones** both end in `TilingController.snap`, so they behave like a drop. `HotKeys` (Carbon) sends Ctrl+Option + arrows to `moveFocusedWindow(toward:)`, which uses `Geometry.neighbour` on the window's own display only. `fillZones()` pairs untiled `WindowAccess.visibleWindows()` with empty zones through `Geometry.fill`.
- **The editor** consists of `EditorModel`, `EditorView` (with `LayoutCanvas`) and `EditorWindowController`. The pure pieces are in core: `LayoutDraft`, `Node.splitting` and `removing`, `dividerHandle`, and `DividerDrag`. Nothing reaches the screen until Save, which calls `setLayout` and then `setGap`.
- **Presets** are static fractions. The exception is `Presets.available(for:gap:)`, which adds a computed "Thirds · 1440 middle" preset on ultrawides (at least twice as wide as tall). The menu and the editor must list presets through `available`, not `Presets.all`.

## Hard constraints

- **No SwiftUI macros.** `@State`, `@Observable`, `@Entry` and `#Preview` don't compile without Xcode (the SwiftUIMacros plugin is missing). Keep view state in `ObservableObject` models with `@Published` and `@ObservedObject`.
- **App target language mode.** It uses `.swiftLanguageMode(.v5)` because AppKit callbacks aren't isolation-annotated. `PanefulCore` is Swift 6.
- **No third-party dependencies**, and macOS 14 as the minimum.
- **Put new logic in `PanefulCore`** and write the tests first, with the app calling into it. The hard bugs came from real displays and apps, so after app-side changes, rebuild with `scripts/install.sh` and ask Adam to verify on his three displays:
  - a 3440×1440 Sceptre O35 as the primary;
  - a 1920×1200 PA248QV on each side, at x = −1920 and x = 3440.

## Debugging the app

- **`NSLog` output shows as `<private>` in `log show`.** For temporary diagnostics, append lines to a file such as `/tmp/paneful-debug.log`, ask Adam to reproduce one scenario, read the file, and remove the logging before committing.
- **To test Accessibility hypotheses, write a throwaway `swiftc` script** that finds the real window (`AXUIElementCreateApplication(pid)`, then `kAXWindowsAttribute`), sets frames, and reads them back after each call. The terminal already has Accessibility trust.
- **The system `sed` is GNU sed**, so `sed -i ''` fails. Use the Edit tool for in-place edits.
- **Adam's settings:** `~/Library/Application Support/Paneful/settings.json`. macOS's own tiling (Desktop & Dock) is turned off, because it conflicts with Paneful.

## Workflow conventions

- Specs live in `docs/superpowers/specs/` and one plan per feature in `docs/superpowers/plans/`. Work happens on a feature branch and is merged to `main` locally with `--ff-only`. There's no remote.
- In Adam's terminal, text written just before a multiple-choice question can be hidden, so put content to review in the question's preview.
