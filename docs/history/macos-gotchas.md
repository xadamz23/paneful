# macOS and Toolchain Gotchas

Lessons that aren't specific to Paneful's features. Read this before touching window moving, the build, or the editor UI. The full stories are in [issues-and-fixes.md](issues-and-fixes.md).

## Accessibility API (moving and reading windows)

- **Moving across displays, check your coordinates.** Accessibility uses a top-left origin on the primary display with y going down. AppKit (`NSScreen`, `NSEvent.mouseLocation`) uses a bottom-left origin with y going up. Paneful converts only at the app boundary, through `Coordinates.flip`, and all core geometry is in Accessibility coordinates. Displays to the left of the primary have negative x.
- **macOS won't resize a window whose bottom hangs below its screen.** It happens in every app, and every call still reports success. Move the window fully onto the target display first.
- **A window whose bottom reaches its screen's bottom ignores a small shrink in height (Edge: 1196 → 1192 ignored, → 1150 works).** It's then easily left hanging off the screen. `setFrame` checks the frame afterwards and, if needed, shrinks to half height first (issue 22).
- **Some apps ignore a resize that comes straight after a move (Ghostty).** Use the order **size → position → size**, the same as Rectangle.
- **Setters report success even when they did nothing.** Always read the frame back when checking behaviour.
- **A dragged window's position is reported late.** During a title-bar drag, the Accessibility position lagged about 37 mouse events behind the visible window. Never give up early on "has this window moved?".
- **Don't move a window the user is still dragging.** Changing its frame mid-drag fights the window server. Act on mouse-up, after a short delay so the drag finishes first (`DragMonitor` waits 50 ms).
- **Position and size are two separate reads, so they can be torn.** During a live left-edge or top-edge resize the opposite edge seems to wobble. Decide which edge is being dragged once, and follow only that edge (`ResizeTracker`).
- **Frames are whole points.** Compare consecutive frames with a tolerance below 1, or slow 1 pt drags get lost.
- **`AXEnhancedUserInterface`** makes some apps (Chrome, Electron) animate or misplace resizes. Turn it off around the resize and restore it afterwards.
- **Set a messaging timeout.** `AXUIElementSetMessagingTimeout` on the system-wide element (0.25 s) stops a hung app from freezing Paneful.
- **Windows from an app that has quit** fail with `.cannotComplete`, not `.invalidUIElement`. Check `NSRunningApplication(processIdentifier:)?.isTerminated`.
- **`AXUIElement` is `Hashable`** with `CFEqual` semantics, so fresh elements for the same window compare equal. It works as a dictionary key.
- **An app's `kAXWindowsAttribute` lists only its windows on the current Space.** Windows on other Spaces don't appear (confirmed with a probe script), so enumerating visible windows needs no `CGWindowList` filter.
- **Accessibility can still set the frame of a window on another Space.** A stored `AXUIElement` keeps working after you switch Spaces, so anything that refits stored windows reaches every Space (issue 23).

## Spaces

- **There's no public API for the current Space.** `CGSGetActiveSpace(CGSMainConnectionID())`, declared with `@_silgen_name`, returns its ID. It links through CoreGraphics (Foundation alone gives undefined symbols), is read-only and works with SIP on.
- **The ID changes with the Space and stays stable per Space.** A full-screen app gets its own Space and ID.
- **"Displays have separate Spaces"** is off on Adam's Mac (`defaults read com.apple.spaces spans-displays` prints 1), so every display switches Space together and there's one current Space.

## Watching the mouse

- `NSEvent.addGlobalMonitorForEvents` sees mouse-down, drag, mouse-up and modifier changes in other apps. It needs no extra permission for mouse events, and it never sees events aimed at Paneful's own windows. That's useful, because the editor and overlay can't trigger it.
- macOS's own window tiling (Desktop & Dock settings) reacts to Option-drag and to dragging a window to a screen edge. Turn it off, or it fights Paneful.

## Hotkeys

- **Carbon `RegisterEventHotKey` still works** on macOS 27 from a SwiftPM-built app. It needs no Accessibility or Input Monitoring permission, and the keystroke is consumed. VoiceOver also uses Ctrl+Option, but only while it's on.
- **A hotkey conflict can't be detected.** Registering a combo another process holds still returns `noErr`. Only when both sides pass `kEventHotKeyExclusive` does the second get `eventHotKeyExistsErr` (−9878), and a non-exclusive holder is invisible even to an exclusive registration. Tested with a probe against the running Paneful and against a second probe process. Apps using event taps don't register at all.

## Debugging the app

- **`NSLog` output shows as `<private>`** in `log show`. For temporary diagnostics, append to a file such as `/tmp/paneful-debug.log`, and remove the logging afterwards.
- **To test Accessibility ideas fast, write a small `swiftc` script** that finds the real window (`AXUIElementCreateApplication(pid)`, then `kAXWindowsAttribute`), sets frames, and reads them back after each call. The terminal already has Accessibility access. This beat round trips through the app for the hardest bug.
- **Ask for one reproduction at a time.** Each scenario gets its own reproduction, with the log cleared first, so the log stays readable.

## SwiftPM and Swift Testing without Xcode

- Only Command Line Tools are installed (Swift 6.4, macOS 27 SDK). **Swift Testing** (`import Testing`) works; **XCTest** does not.
- **The TestingMacros plugin is loaded explicitly** in `Package.swift` (`-load-plugin-library …/plugins/testing/libTestingMacros.dylib`), because the build backend intermittently forgets it. If Xcode is ever installed, revisit that hard-coded path.
- **SwiftPM can't build a target with no source files.** Add a placeholder.
- The `ld: warning: search path '/Library/Developer/CommandLineTools/Developer/…' not found` lines are harmless.
- **The system `sed` is GNU sed,** so `sed -i ''` fails. Use the Edit tool or a small Python script for in-place edits.

## SwiftUI without Xcode

- **SwiftUI macros don't compile**, because the macro plugin ships only with Xcode. That rules out `@State`, `@Observable`, `@Entry` and `#Preview`.
- **What does work:** `ObservableObject` with `@Published` and `@ObservedObject`, plus `@GestureState`. Keep view state in a model object.
- **Menu bar app windows need `NSApp.activate()`** to come to the front, because the app is `LSUIElement`.
- **With no main menu, Cmd-W and Esc do nothing.** The editor's `NSWindow` subclass handles them itself: `cancelOperation(_:)` for Esc and `performKeyEquivalent(with:)` for Cmd-W, both calling `performClose`, so `windowShouldClose` still asks about unsaved edits.
- **A `Picker` bound through a custom `Binding`** that refuses a change keeps showing the refused value until something publishes. Call `objectWillChange.send()`, deferred to the next run loop.

## Signing and Accessibility permission

- macOS ties the Accessibility permission to the app's code signature. With ad-hoc signing, every rebuild loses it.
- **`scripts/make-signing-cert.sh`** creates a self-signed "Paneful Dev" code-signing identity in the login keychain, once. The app's designated requirement then pins that certificate, so the permission survives rebuilds.
- **OpenSSL 3** (Homebrew) needs `pkcs12 -export -legacy`, or `security import` can't read the file. LibreSSL, the system `openssl`, doesn't need it.
- **If `codesign` hangs,** a keychain dialog is probably waiting behind other windows. Enter the login password and click **Always Allow**.
- `security find-identity -p codesigning` lists the identity as `CSSMERR_TP_NOT_TRUSTED`. That's expected for a self-signed certificate and doesn't stop local signing.
