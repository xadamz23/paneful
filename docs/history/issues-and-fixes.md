# Issues and Fixes

Every real problem we hit, in the order we hit it. For each one: what Adam saw (the symptom), why it happened (the root cause), how we found out, what fixed it, and the commit.

**Where they came from:**
- Code review (an independent reviewer at the end of each phase)
- Manual testing (Adam on his real displays)
- Toolchain (the build and test tools)
- Plan self-review (caught before any code existed)

---

## Phase 1: Drop windows into zones

### 1. Swift Testing failed about half the time *(toolchain)*
- **Symptom:** `swift test` intermittently failed with `external macro implementation type 'TestingMacros…' could not be found; plugin for module 'TestingMacros' not found`, on both clean and incremental builds.
- **Root cause:** without Xcode, the default `swiftbuild` backend sometimes leaves the Swift Testing macro plugin out of the compile command. The plugin is at `/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib`. `--build-system native` is worse: it can't find the `Testing` module at all.
- **Found by:** running the suite repeatedly and seeing it pass and fail on the same code. The failing compile commands had no `-load-resolved-plugin` for TestingMacros.
- **Fix:** the test target in `Package.swift` loads the plugin explicitly with `-load-plugin-library`. That gave 5 green runs out of 5.
- **Commit:** `b5ec838`
- **Caveat:** the path is hard-coded to Command Line Tools, so installing Xcode may require updating or removing it.

### 2. A target with no source files won't build *(toolchain)*
- **Symptom:** the first test-first run failed with "unable to resolve module dependency", not with the expected "missing type" error.
- **Root cause:** SwiftPM rejects a target that has no source files.
- **Fix:** add an empty source file before the first failing-test run.

### 3. Plan code that wouldn't have compiled *(plan self-review)*
- **What:** three bugs in the plan's own code:
  - a `?:` whose two branches had different types (`NSApp` and `self`);
  - an `if let (a, b) = …` pattern I believed was invalid;
  - the app delegate created before `NSApplication`, so the screen list read in its initialiser could have been empty.
- **Fix:** corrected in the plan before execution. The tuple pattern turned out to compile fine in Swift 6.4, as a later check showed.

### 4. A dead strip along every screen edge *(code review)*
- **Symptom:** when you dragged a window to an edge zone, the cursor naturally stopped at the very edge of the display, or over the menu bar or Dock. Nothing was highlighted there, and letting go didn't snap.
- **Root cause:** hit-testing grew each zone by half a gap, so a point further out than that, or over the menu bar or Dock, matched no zone. The plan's own test even enforced this, contradicting its stated intent.
- **Fix:** `Geometry.zone(at:)` first clamps the point into the bounding box of the zones. Test: `pointAtScreenEdgePicksEdgeZone`.
- **Commit:** `a821999`

### 5. macOS's own tiling fights Paneful *(code review)*
- **Symptom (predicted):** on macOS 15 and later, holding Option while dragging, or dragging to a screen edge, triggers the system's tiling on top of Paneful's.
- **Fix:** no code change. Adam turned off both options in System Settings › Desktop & Dock. The default modifier is Shift.

---

## Phase 2: Linked resizing

### 6. A neighbour that refused to shrink hung off the screen *(code review, critical)*
- **Symptom:** a window with a minimum size, in a right-hand or bottom zone, could be left overflowing past the screen edge and onto the next display.
- **Root cause:** after you let go, the code pushed a divider back based on which edge overflowed. A refusing window keeps its left and top edges where they're put and overflows on the right and bottom. For a right-hand or bottom zone that edge is the screen edge, which has no divider, so nothing moved.
- **Fix:** `Arrangement.fit(_:toAtLeast:)` grows the zone to the window's actual size, trying the divider on the trailing side first and then the leading one. Tests: `fitGrowsRightZoneTowardItsDividerWhenItOverflowsTheScreenEdge` and others.
- **Commit:** `e837c78`

### 7. Terminal-style windows moved dividers nobody touched *(code review)*
- **Symptom:** apps that size to a character grid (Terminal, Ghostty) sit a few points short of their zone. Dragging only their right edge also shifted the row divider, a little more on every resize.
- **Root cause:** "which edges moved" was worked out by comparing the window with its **zone**, so the short edge always looked moved.
- **Fix:** compare with the window's **previous frame** instead (`e837c78`). This was later replaced by `ResizeTracker` (issue 12).

### 8. The install hung at codesign *(manual testing)*
- **Symptom:** `scripts/install.sh` sat at `build/Paneful.app: replacing existing signature` for more than 10 minutes.
- **Root cause:** macOS was showing a hidden keychain dialog asking to let `codesign` use the "Paneful Dev" key. The keychain itself was unlocked.
- **Fix:** in the dialog, enter the login password and click **Always Allow**. It hasn't come back since.

### 9. Shift-drag stopped showing zones at all *(manual testing, a Phase 2 regression)*
- **Symptom:** after installing Phase 2, holding Shift and dragging a window showed nothing.
- **Root cause:** Phase 2 decides whether a press is a *move* or a *resize* by watching the window's frame change. To avoid wasted work during text selection, it gave up after the cursor had travelled 24 pt with no change. But **Accessibility reports a dragged window's new position late**: about 37 mouse events in. So every window drag was written off as "not a window drag".
- **Found by:**
  - Temporary logging written to `/tmp/paneful-debug.log`. `NSLog` is useless here, because `log show` shows the text as `<private>`.
  - The log showed `start` and `now` frames identical for the whole 24 pt, then "gave up".
- **Fix:** keep checking until mouse-up, as Phase 1 did.
- **Commit:** `e201c12`

### 10. Slow drags made the divider fall behind *(manual testing)*
- **Symptom:** after resizing, windows "moved to a slightly different position" when you let go.
- **Root cause:** a slow drag moves the edge 1 pt per mouse event. The 1 pt jitter tolerance dropped those steps while still recording the new frame as "last seen", so the divider lagged further behind with every slow step.
- **Found by:** the same debug log, which showed `edges=[]` on the 1 pt steps.
- **Fix:** window frames come in whole points, so a tolerance of 0.5 between consecutive frames counts every real step. Test: `slowDragStillMovesTheDivider`, now `slowDragTracksEveryPoint`.
- **Commit:** `364915b`

### 11. Windows didn't fit the bottom zones *(manual testing, the hardest bug)*
- **Symptoms, in the order seen:**
  - In 2 × 2 on a PA248QV, the bottom two Ghostty windows came out about 70 pt too narrow.
  - A big window dropped into the bottom-left zone moved there but **kept its old size**.
  - After a first fix, the window came out at an **in-between size**, spilled onto the ultrawide, and hung below the screen.
  - It happened with **Finder** too.
- **Root causes (two):**
  1. **Ghostty ignores a resize that comes straight after a move.** Paneful set position, then size, then position.
  2. **macOS ignores resizing a window whose bottom hangs below its screen.** This applies to every app. Each call still reports success.
- **Found by:**
  - Logging each snap's requested frame against its read-back frame.
  - Small `swiftc` scripts, run from the terminal (which has Accessibility access), that drove the real Ghostty and Finder windows and read the frame back after every call.
- **What didn't work** (three attempts, which is when we stopped to rethink):
  - reordering the calls alone;
  - repeating the request;
  - nudging the size by 1 pt first;
  - pausing 50–150 ms before the final resize.
- **The breakthrough:** the stuck width was **982 in both apps**, from different starting widths, which pointed away from app quirks. Moving the stuck window up to y = 100 made the resize work immediately.
- **Fix:** in `WindowAccess.setFrame(_:of:within:)`:
  - if the window isn't already inside the target display, first move it to that display's top-left corner;
  - then set size, position, size.
  - Windows already inside the display skip the extra move, so neighbours following a live resize don't flicker.
- **Commit:** `e1cf100`

### 12. Outer-edge resizes eventually snapped back *(manual testing)*
- **Symptom:** dragging a window's screen-side edge (left or top) usually worked, but "eventually windows started snapping back on their own" to the screen edge.
- **Root cause:** **torn reads.**
  - Position and size are read with two separate Accessibility calls, so during a live drag they come from slightly different moments.
  - While the left edge was dragged, the right edge seemed to wobble: −962, then −981, −966, −978.
  - Paneful took that as a move of the shared divider and marked the resize as linked. On release it re-snapped everything, including the dragged window.
- **Found by:** the debug log of every resize step, which showed the right edge jumping around while only the left one was being dragged.
- **Fix:** `ResizeTracker`, in `PanefulCore`, locks one dragged edge per axis the first time that axis changes, and after that follows only that edge.
  - Rule: a change of origin means the left or top edge is being dragged. A right-edge or bottom-edge drag never changes the origin.
  - This also replaced the fix for issue 7.
  - Test: `leftEdgeDragIgnoresTornReadsOfTheRightEdge` and others.
- **Commit:** `e1cf100`

---

## Phase 3: Visual layout editor

### 13. SwiftUI's `@State` doesn't compile without Xcode *(toolchain)*
- **Symptom:** `plugin for module 'SwiftUIMacros' not found`.
- **Root cause:** in the macOS 27 SDK, `@State` is a Swift macro, and SwiftUI's macro plugin ships only with Xcode. `@Observable`, `@Entry` and `#Preview` are affected the same way.
- **Found by:** compiling a scratch SwiftUI file before writing the plan.
- **Fix:** keep SwiftUI, but hold all view state, including drag state, in an `ObservableObject` (`EditorModel`) with `@Published` and `@ObservedObject`. Those are property wrappers, not macros. The rule is written into the Phase 3 plan's constraints.

### 14. Removed zones' IDs were reused *(code review)*
- **Symptom (predicted):** remove zone 1, split another zone, and Save. The window that was in zone 1 jumps into the new zone instead of being untiled.
- **Root cause:** a new zone got ID `max(current IDs) + 1`, which can hand back a removed ID. Save matches windows to zones by ID.
- **Fix:** `LayoutDraft` hands out IDs from a counter that only goes up. Test: `removedZoneIDIsNotReusedBySplit`.
- **Commit:** `4aaf0d5`

### 15. A click near a divider moved it *(code review)*
- **Symptom:** clicking near a divider made it jump to the cursor. That also renamed the layout "Custom", marked it as changed, and swallowed the click.
- **Root cause:** the drag gesture fires on mouse-down, and the divider was moved to the cursor's absolute position. The grab area is ±6 canvas px, about ±30 pt on the ultrawide.
- **Fix:** `DividerDrag`, in `PanefulCore`:
  - the divider doesn't move until the cursor has travelled 2 px;
  - it then moves by the distance travelled since the grab, not to the cursor;
  - a press that never drags selects the zone it started on.
- **Commit:** `4aaf0d5`

### 16. Dragging one divider moved another *(code review, and Adam's report)*
- **Symptom:** on Adam's custom ultrawide layout, dragging the left divider also moved the edges of the windows to its right. Dragging a right-hand divider didn't.
- **Root cause:**
  - Splitting a zone side by side inside a side-by-side split *nested* a new split, instead of adding a sibling.
  - Moving the outer divider then scaled the nested split as a whole, dragging its inner divider along.
  - Adam's saved tree was `vertical[ H[0,4], vertical[ 3, H[2,5] ] ]`.
- **Fix:**
  - `Node.flattened()` merges same-axis child splits into their parent, scaling their fractions.
  - It runs after every split and remove, and when `Settings` loads a layout. That last part fixed Adam's already-saved layout with no need to rebuild it.
  - Tests: `draggingOneDividerOfASplitZoneLeavesTheOtherAlone`, `removeFlattensACollapsedSameAxisSplit` and `savedSameAxisNestingIsFlattenedOnLoad`.
- **Commit:** `4aaf0d5`

### 17. Smaller editor fixes *(code review)*
All in commit `4aaf0d5`:
- **Display picker after Cancel.** It kept showing the newly picked display after Cancel refused the switch, so Save would have written to the wrong display. Fix: redraw it with `objectWillChange.send()`.
- **Save order.** Saving the gap first moved windows in about-to-be-removed zones. Fix: save the layout first, then the gap.
- **A stale editor.** Changes made from the menu while the editor was open could be overwritten by Save. Fix: remember the gap as loaded, and reload when the window comes back to the front with no unsaved edits.

---

## Span zones

### 18. A span's edge came apart *(code review, critical)*
- **Symptom (predicted, then confirmed with probe tests):** in 2 × 2, a window spanning the top row. Resizing the bottom-right window's top edge moved only the right column's divider. The span's rect (the union of its zones) then grew past the left column's divider and overlapped the bottom-left window until Reset. A column hitting its 100 pt minimum while the other didn't had the same effect.
- **Root cause:** a span's bottom edge sits on two independent dividers, one per column. Nothing tied them together:
  - a neighbour's or stacked window's resize moved just one of them;
  - an uneven clamp left them at different heights.
- **Fix:** `Arrangement.moveEdge` collects every divider tied to the moved one through a tiled span's edge (`linkedDividers`) and moves them all. If any is clamped, it moves them all back to where the most-clamped one stopped, so a span's edges stay straight. `fit` goes through `moveEdge`, so refusing windows get the same treatment.
- **Tests:** `neighbourResizeKeepsTheSpanStraight`, `stackedWindowMovingTheSpansOuterEdgeMovesAllOfIt`, `unevenClampKeepsTheSpanStraight`.

### 19. The span anchored one zone too far *(code review)*
- **Symptom (predicted):** with Shift+Option held before pressing, a fast drag anchored the span on the zone the cursor had reached, not the one pressed on.
- **Root cause:** a move is only recognised once the window's reported frame changes, which lags about 37 mouse events behind (issue 9). The anchor was taken at that point.
- **Fix:** `DragMonitor` remembers where the press happened, and anchors there when the span key is held from the start.


---

## Keyboard moves and Fill Zones

### 20. A keyboard move could send a window back to another display *(code review)*
- **Symptom (predicted):** a tiled window moved to another display without dragging (from a Window menu, or the app restoring its own position) stays tiled on its old display. Pressing Ctrl+Option + an arrow then snapped it back onto that old display, even though keyboard moves must never change display.
- **Root cause:** `moveFocusedWindow` trusted the arrangement's record of where the window was tiled and never checked where the window actually was. Paneful doesn't notice non-drag display moves (a known limitation).
- **Fix:** a tiled window counts as tiled for a keyboard move only if its display contains the window's current centre. Otherwise it's treated as untiled and snapped into the zone under its centre on the display it's really on.
- **Verified:** by hand on Adam's displays. The check is app wiring, so there's no unit test.
- **Commit:** `3ba82c2`

### 21. Does Accessibility list windows on other Spaces? *(plan self-review)*
- **What:** Fill Zones must only pick up windows on the current Space. It wasn't known whether an app's `kAXWindowsAttribute` includes windows on other Spaces.
- **Found by:** a throwaway `swiftc` probe comparing each app's Accessibility windows with the on-screen `CGWindowList`. It was run again after Adam moved an Edge window to another Space: Edge then listed no windows.
- **Outcome:** Accessibility lists only the current Space's windows, so `visibleWindows()` needs no on-screen filter. Recorded in [macos-gotchas.md](macos-gotchas.md).

## Split on drop

### 22. A full-height window on a side display couldn't be resized *(Adam's testing)*
- **Symptom:** on a PA248QV set to Halves, Edge snapped into the right zone couldn't be resized from the shared vertical edge, from either side. Nothing moved.
- **Root cause:**
  - Edge was 1200 pt tall. `setFrame` first moves a window that's off the target display to the display's top-left corner, so Edge's bottom landed exactly on the screen's bottom edge.
  - In that position Edge ignores a small shrink in height. A probe on the real window showed 1196 → 1192, → 1190 and → 1180 all ignored, while → 1150 worked.
  - The move to y = 4 then left it 1200 pt tall and hanging 4 pt off the bottom. macOS refuses every resize of such a window, including the user's own edge drags.
  - This is not caused by the split: any snap of a full-height window into a zone just shorter than the screen can hit it.
- **Fix:** after size → position → size, `WindowAccess.setFrame` reads the frame back. If the window is still taller than the target and its bottom still reaches the screen's bottom, it shrinks it to half height, then sets the target size, then the position. It only does this in that case, so windows that refuse to shrink (a minimum size) aren't nudged on every live-resize step.
- **Verified:** with the probe (1196 → 1192), then by Adam on the display.
- **Commit:** `2a587dc`

## Per-Space arrangements

### 23. Resizing on one Space moved a window on another *(Adam's testing)*
- **Symptom:** Adam tiled a window on Space X, then tiled and resized windows on Space Y. Back on X, its window had resized too.
- **Root cause:** `TilingController` kept one `Arrangement` per display, shared by every Space. A resize on Y moved the shared dividers, and `refit` set the frame of every tiled window on that display. Accessibility can set the frame of a window on another Space, even though `kAXWindowsAttribute` doesn't list it.
- **Found by:** Adam's before/after screenshots, then a throwaway `swiftc` probe printing `CGSGetActiveSpace` while he switched Spaces (8 → 7 → 8, and 77 for a full-screen Space).
- **Fix:** `SpaceArrangements` keys arrangements by Space ID and display UUID. Per-Space actions use the current Space; layout, gap and display changes touch every Space. Tiling a window untiles it everywhere else.
- **Commit:** `d7b1774`
