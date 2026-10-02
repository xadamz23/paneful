# Paneful

A small macOS menu bar window manager that tiles windows into zones, in the style of BentoBox.

- **Drop into zones.** Hold Shift while dragging a window. The display's zones appear, and releasing drops the window into the one under the cursor.
- **Span zones.** Hold Option as well to stretch the window across several zones, from the one where you pressed to the one under the cursor.
- **Split on drop.** Hold Control as well to split the zone under the cursor into top and bottom halves, then drop into one of them.
- **Linked resizing.** Windows that share an edge resize together: widen one and its neighbour narrows. Your saved layout never changes.
- **Restore on drag-out.** Drag a tiled window out of its zone and it gets back the size it had before you first snapped it.
- **Keyboard moves.** Ctrl+Option + an arrow key moves the focused window to the neighbouring zone on its display.
- **Fill Zones.** Puts untiled windows into each display's empty zones, nearest first.
- **One layout per display.** Pick a preset (Halves, Thirds, 60 / 40, 40 / 60, 2 × 2, 1 + 2, and "Thirds · 1440 middle" on ultrawides), or edit one visually in **Edit Layouts…**.

You can change the modifier, span key, split key and the gap between zones from the menu bar icon.

Paneful is a personal project, built for one Mac and a three-display setup. It isn't notarised or distributed. You're welcome to build it yourself, but expect rough edges.

## Requirements

- macOS 14 or later.
- Swift 6 toolchain. The Xcode Command Line Tools are enough; Xcode isn't needed.
- Accessibility permission, which Paneful asks for on first launch (System Settings › Privacy & Security › Accessibility).
- macOS's own window tiling turned off (System Settings › Desktop & Dock), because it conflicts with Paneful.

## Build and install

```bash
scripts/make-signing-cert.sh   # once: creates a self-signed "Paneful Dev" code-signing identity
scripts/install.sh             # release build, sign, install to /Applications/Paneful.app, relaunch
```

The stable self-signed identity keeps the Accessibility permission across rebuilds; ad-hoc signing would lose it every time. If `codesign` seems to hang, a keychain dialog is waiting for you to click "Always Allow".

To build `build/Paneful.app` without installing it, run `scripts/build-app.sh`.

## Development

```bash
swift build                              # debug build
swift test                               # all unit tests (Swift Testing)
swift test --filter LayoutEditingTests   # one suite
```

The code is split into two targets:

- **`PanefulCore`**: pure Swift logic with no AppKit, fully unit-tested. Layouts are split trees, and all geometry uses Accessibility coordinates.
- **`Paneful`**: the thin AppKit and SwiftUI menu bar app. `WindowAccess.swift` is the only file that talks to the Accessibility API.

Settings are stored in `~/Library/Application Support/Paneful/settings.json`.

## Documentation

- [`docs/history/`](docs/history/README.md): how the project was built, every bug hit and its root cause, design decisions, and macOS gotchas.
- [`docs/superpowers/specs/`](docs/superpowers/specs/) and [`docs/superpowers/plans/`](docs/superpowers/plans/): the design specs and implementation plans.
- [`CLAUDE.md`](CLAUDE.md): a detailed architecture overview.
