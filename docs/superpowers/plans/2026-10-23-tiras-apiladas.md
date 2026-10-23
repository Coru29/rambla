# Stacked Strips ("Tiras apiladas") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every display and Space can hold several strips stacked vertically, one in view at a time. They are switched with the vertical swipe, shortcuts and the overview. Windows of the other strips stay parked out of sight, and everything survives restarts and display changes.

**Architecture:**
- `StripKey` gains a `level`. `strips` keeps the strip of every level, and `activeLevels` says which level of each (display, Space) stack is in view.
- So `currentKeys`, `isCurrent` and `display(for:)` see only the levels in view, while everything that scans "all strips" sees every level: removing windows, the managed set, saving and gathering.
- Levels not in view are laid out with `Layout.shelved`, which parks every window on a side edge with the 1 pt sliver.
- Pure rules live in RamblaCore with tests: stack navigation, gestures, focus routing, saved state, overview rows. The app wires them.

**Tech Stack:** Swift 6.3 toolchain (language mode 5), SwiftPM, Command Line Tools only, Swift Testing (`scripts/test.sh`), AppKit, SwiftUI, Accessibility.

**Spec:** `docs/superpowers/specs/2026-10-23-tiras-apiladas-design.md` (Spanish). It builds on `docs/superpowers/specs/2026-10-21-scroll-design.md`. Executors read both.

## Global Constraints

**Git and builds**
- Work happens on branch `feat/tiras-apiladas`, which the controller creates.
- Commit at the end of every task:
  - The message follows Conventional Commits (a hook enforces it) and ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  - The git identity is already configured (coru <acoru2002@gmail.com>). Never commit `.signing/`.
- Before every commit, `swift build` and `scripts/test.sh` must both be green.
- **Never** run any of these, because they replace or restart the window manager the user is working with right now. Only the controller runs live tests.
  - `scripts/install.sh`
  - `scripts/e2e.sh`
  - `scripts/e2e-lid.sh`
  - anything that quits or launches `/Applications/Rambla.app`

**Code and copy**
- Code comments and identifiers are in English. UI copy is in Spanish through `String(localized:)`.
- Every new UI string gets its English translation in `Packaging/en.lproj/Localizable.strings`, in the section for its source file (`/* Rambla/… .swift */`).
- Match the surrounding style: doc comments say what a thing does and why. No new dependencies.

**Behavior**
- Zero CPU when idle: no polling, and no repeating timers beyond the existing ones.
- Gesture thresholds stay as they are:
  - trackpad: short swipe 0.1 and long swipe 0.3 of the trackpad height, and clearly vertical (|dy| > 2|dx|);
  - mouse buttons: short 40 pt and long 160 pt.
- The parking sliver stays at 1 pt.
- Default shortcuts:

  | Shortcut | Action |
  |---|---|
  | ⌃⌥⌘↑ | `strip-up` |
  | ⌃⌥⌘↓ | `strip-down` |
  | ⌃⌥⌘⇧↑ | `send-strip-up` |
  | ⌃⌥⌘⇧↓ | `send-strip-down` |

  None may collide with Rectangle's default set (`KeysTests`).
- Spanish words: a strip is a "tira" ("la tira de arriba", "la tira de abajo", "Tira vacía", "Tira nueva", "Vacía").

## Review Focus

1. **A shelved window is moved by macOS or by its app.** Examples: an app restoring its frame, a display change, a window coming back from the Dock. Expected: it goes back to its parking spot and never floats. Only the user focusing it changes levels.
   - Pinned by: Task 6 behavior 6, and the e2e step in Task 12.
2. **Quit, pause or "Traer todas las ventanas" with shelved levels.** Expected: every window of every level comes back into view, and resuming shelves them again.
   - Pinned by: the e2e pause step in Task 12.
3. **⌘Tab to an app with windows in both levels.** Expected: no level switch; the app's most recently used window in the level in view gets the focus. A Rambla-made switch must not bounce back because the old app reports its focus late.
   - Pinned by: `FocusRouteTests` (Task 7) and the e2e focus step in Task 12.
4. **Restart, and files from older versions.** Expected: a `state.json` without levels loads as level 0, and a saved active level beyond the restored ones is clamped to the top.
   - Pinned by: `oldSavedStripDecodesAsLevelZero` (Task 5), `restoredActiveClampsToTop` (Task 1), and the e2e restart step with `--state-file` in Task 12.
5. **A display unplugged while its upper level has windows.** Expected: those windows join the same level on the remaining display, parked out of sight, and go back when the display returns.
   - Pinned by: `unpluggedLevelFindsTheWindow` (Task 5), Task 8 behavior, and the lid test the controller runs with the user.

---

## File Structure

**New**

| File | Holds |
|---|---|
| `Sources/RamblaCore/StripLevels.swift` | stack navigation and cleanup rules |
| `Sources/RamblaCore/FocusRoute.swift` | where focus that lands on another level goes |
| `Sources/RamblaCore/OverviewStack.swift` | the overview's rows (one per level) and the selection across them |
| `Sources/Rambla/Engine/WindowManager+Levels.swift` | switching levels, shelving, sending windows, level actions, gesture entry points |
| `Tests/RamblaCoreTests/StripLevelsTests.swift` | tests for `StripLevels` |
| `Tests/RamblaCoreTests/FocusRouteTests.swift` | tests for `FocusRoute` |
| `Tests/RamblaCoreTests/OverviewStackTests.swift` | tests for `OverviewStack` |

**Modified**

- **RamblaCore:**
  - `Layout.swift`
  - `TrackpadSwipe.swift`
  - `MouseButtonGesture.swift`
  - `Preferences.swift`
  - `Actions.swift`
  - `Keys.swift`
  - `SavedState.swift`
- **Engine:**
  - `WindowManager.swift`
  - `WindowManager+Commands.swift`
  - `WindowManager+Input.swift`
  - `StateStore.swift`
- **Input:**
  - `GestureTracker.swift`
  - `MouseButtonTracker.swift`
- **App:** `AppDelegate.swift`
- **Overlay:**
  - `OverlayCoordinator.swift`
  - `IndicatorController.swift`
  - `OverviewController.swift`
- **Settings:** `TrackpadView.swift`
- **Localization:** `Packaging/en.lproj/Localizable.strings`
- **Docs:**
  - `docs/MANUAL.md` and `docs/MANUAL.en.md`
  - `README.md` and `README.es.md`
  - the main spec
- **Scripts:**
  - `scripts/testhost.swift`
  - `scripts/e2e-check.swift`
  - `scripts/e2e.sh`

---

### Task 1: Stack rules (`StripLevels`)

**Files:**
- Create: `Sources/RamblaCore/StripLevels.swift`
- Test: `Tests/RamblaCoreTests/StripLevelsTests.swift`

**Interfaces:**
- Produces:

```swift
public enum StripLevels {
    /// Where a move from `active` goes. Levels 0...`top` exist; `occupied` are the ones with at least one window.
    /// Up: the next level, or a new one above `top` when `active` is the top and has windows. Down: the previous one.
    /// Nil at either end.
    public static func target(from active: Int, up: Bool, top: Int, occupied: Set<Int>) -> Int?
    /// The levels to remove, ascending: those above both the highest occupied level and `active`. Never 0.
    public static func droppable(top: Int, occupied: Set<Int>, active: Int) -> [Int]
    /// The level a restored stack shows: `saved` (nil means 0), lowered to `top` when it is above it.
    public static func restoredActive(_ saved: Int?, top: Int) -> Int
}
```

- [ ] **Step 1: Write the failing tests**

```swift
@Test func upFromAnOccupiedTopOpensANewLevel() {
    #expect(StripLevels.target(from: 0, up: true, top: 0, occupied: [0]) == 1)
}
@Test func upFromAnEmptyTopGoesNowhere() {
    #expect(StripLevels.target(from: 1, up: true, top: 1, occupied: [0]) == nil)
    #expect(StripLevels.target(from: 0, up: true, top: 0, occupied: []) == nil)
}
@Test func upInsideTheStackReachesEmptyMiddleLevels() {
    #expect(StripLevels.target(from: 0, up: true, top: 2, occupied: [0, 2]) == 1)
}
@Test func downStopsAtZero() {
    #expect(StripLevels.target(from: 0, up: false, top: 1, occupied: [0, 1]) == nil)
    #expect(StripLevels.target(from: 2, up: false, top: 2, occupied: []) == 1)
}
@Test func emptyLevelsAboveEverythingAreDropped() {
    #expect(StripLevels.droppable(top: 2, occupied: [0], active: 0) == [1, 2])
    #expect(StripLevels.droppable(top: 2, occupied: [0], active: 2) == [])
    #expect(StripLevels.droppable(top: 2, occupied: [0], active: 1) == [2])
    #expect(StripLevels.droppable(top: 3, occupied: [0, 2], active: 0) == [3])
    #expect(StripLevels.droppable(top: 1, occupied: [], active: 0) == [1])
}
@Test func emptyLevelsBelowAnOccupiedOneStay() {
    #expect(StripLevels.droppable(top: 2, occupied: [2], active: 2) == [])
    #expect(StripLevels.droppable(top: 2, occupied: [2], active: 0) == [])
}
@Test func restoredActiveClampsToTop() {
    #expect(StripLevels.restoredActive(nil, top: 2) == 0)
    #expect(StripLevels.restoredActive(1, top: 2) == 1)
    #expect(StripLevels.restoredActive(3, top: 1) == 1)
}
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh --filter StripLevels`. Expected: the build fails because `StripLevels` is not defined.
- [ ] **Step 3: Implement `StripLevels`** as specified.
- [ ] **Step 4: Run the tests to verify they pass.** Run `scripts/test.sh --filter StripLevels`, then `scripts/test.sh` and `swift build`. Expected: everything is green.
- [ ] **Step 5: Commit** with the message `feat(core): rules for moving between stacked strips`.

### Task 2: Layout for a strip that is not in view (`Layout.shelved`)

**Files:**
- Modify: `Sources/RamblaCore/Layout.swift`
- Test: `Tests/RamblaCoreTests/LayoutTests.swift` (reuse its helpers to build inputs)

**Interfaces:**
- Produces: `public static func shelved(_ input: LayoutInput) -> LayoutResult`

`shelved` works from `compute(input)`:

| Part of the result | In `shelved` |
|---|---|
| `.visible(frame)` placement | becomes `.parked(parking(for: frame, side: frame.midX < display.midX ? .left : .right, display: input.display, others: input.otherDisplays, sliver: input.config.sliver).frame)` |
| `.parked` placement | stays as it is |
| `tabBars` | empty |
| `exits` | empty |
| `columnFrames` and `metrics` | as `compute` gives them |

Windows that `compute` leaves out (the hidden ones) stay out. Document it the way `compute` is documented.

- [ ] **Step 1: Write the failing tests**
  - **`shelvedParksEveryWindowWithASliver`:** three fitting columns on a 1000×800 display. Every placement is `.parked` and shows exactly `sliver` on the display. Columns whose center is left of the display's center park on the left edge, the others on the right edge.
  - **`shelvedAvoidsANeighborDisplay`:** with a display touching the right edge, every window parks on the left edge.
  - **`shelvedKeepsParkedWindowsAndDropsTabBars`:** a tabbed column has no tab bar in the result, and a placement already `.parked` in `compute` is unchanged.
  - **`shelvedLeavesHiddenWindowsOut`:** a window in `input.hidden` has no placement.
- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh --filter Layout`. Expected: it fails to build.
- [ ] **Step 3: Implement `shelved`.**
- [ ] **Step 4: Run the tests to verify they pass.** Run `scripts/test.sh` and `swift build`. Expected: green.
- [ ] **Step 5: Commit** with the message `feat(core): layout for a strip that is not in view`.

### Task 3: Vertical gestures that change strips

**Files:**
- Modify:
  - `Sources/RamblaCore/Preferences.swift`
  - `Sources/RamblaCore/TrackpadSwipe.swift`
  - `Sources/RamblaCore/MouseButtonGesture.swift`
- Test:
  - `Tests/RamblaCoreTests/TrackpadSwipeTests.swift`
  - `Tests/RamblaCoreTests/MouseButtonGestureTests.swift`
  - `Tests/RamblaCoreTests/PreferencesTests.swift`

**Interfaces:**
- Produces:

```swift
/// What a short vertical swipe (trackpad, or the mouse buttons) does.
public enum VerticalGesture: String, Codable, CaseIterable, Sendable { case strips, width }
// Preferences: public var verticalGesture: VerticalGesture = .strips   (decodeIfPresent, like every field)

// TrackpadVertical
public init(mode: VerticalGesture = .width)
public enum Command: Equatable, Sendable {
    case fullWidth, previousWidth, overview   // width mode, as today (overview in both modes)
    case toggleWidth                          // strips mode: a long swipe up
    case strip(up: Bool)                      // strips mode: a short swipe, decided on lift; `up`: the fingers went up
    case armed(up: Bool)                      // strips mode: the swipe just became a short vertical one (haptic cue)
}
public static let longStart = 0.3             // `overviewStart` stays as an alias of it

// MouseButtonGesture
public init(buttons: [Int], vertical: VerticalGesture = .width)
// Command gains: case strip(up: Bool), case toggleWidth   (`up`: the pointer moved up)
```

**Trackpad behavior in strips mode** (width mode stays exactly as it is, and its existing tests keep passing):
1. The swipe turns vertical as it does today (`TrackpadSwipe.kind` gives `.up` or `.down`).
2. On that first vertical move, `moved` returns `.armed(up:)`.
   - If that move is already at the long distance (|dy| ≥ 0.3), it returns the long command instead.
3. While going up, dy ≥ 0.3 returns `.toggleWidth`, once. While going down, dy ≤ −0.3 returns `.overview`, once.
4. After a long command the swipe is done: no more commands, and `lifted` returns nil.
5. When `lifted(dy:)` is called on a swipe that is not done:

   | Direction | Condition | Result |
   |---|---|---|
   | up | dy ≥ 0.1 | `.strip(up: true)` |
   | down | dy ≤ −0.1 | `.strip(up: false)` |
   | either | anything else | nil |

6. `isVertical` is true once the swipe is going up or down, or is done.

**Mouse-button behavior in strips mode** (width mode is unchanged):
1. When armed, a clearly vertical move of at least 40 pt starts:
   - a new `goingUp` phase when y < 0 (up);
   - the existing `goingDown` phase when y > 0.
2. Long moves act at once:
   - in `goingUp`, |y| ≥ 160 gives `.toggleWidth` and the press is spent;
   - in `goingDown`, y ≥ 160 gives `.overview`, as today.
   - A first vertical step that is already ≥ 160 gives the long command at once.
3. On release before the long distance:
   - `goingUp` with |y| ≥ 40 gives `.strip(up: true)`;
   - `goingDown` with y ≥ 40 gives `.strip(up: false)`;
   - less than that gives nothing.

- [ ] **Step 1: Write the failing tests**

```swift
// TrackpadSwipeTests (strips mode)
@Test func shortSwipeDownChangesStripOnLift() {
    var v = TrackpadVertical(mode: .strips)
    #expect(v.moved(.down, dy: -0.12) == .armed(up: false))
    #expect(v.moved(.down, dy: -0.2) == nil)
    #expect(v.lifted(dy: -0.2) == .strip(up: false))
}
@Test func shortSwipeUpChangesStripOnLift() {
    var v = TrackpadVertical(mode: .strips)
    #expect(v.moved(.up, dy: 0.12) == .armed(up: true))
    #expect(v.lifted(dy: 0.15) == .strip(up: true))
}
@Test func longSwipeUpTogglesWidthOnce() {
    var v = TrackpadVertical(mode: .strips)
    _ = v.moved(.up, dy: 0.12)
    #expect(v.moved(.up, dy: 0.31) == .toggleWidth)
    #expect(v.moved(.up, dy: 0.5) == nil)
    #expect(v.lifted(dy: 0.5) == nil)
}
@Test func longSwipeDownOpensTheOverviewInStripsMode() {
    var v = TrackpadVertical(mode: .strips)
    _ = v.moved(.down, dy: -0.12)
    #expect(v.moved(.down, dy: -0.31) == .overview)
    #expect(v.lifted(dy: -0.4) == nil)
}
@Test func comingBackBeforeLiftingDoesNothing() {
    var v = TrackpadVertical(mode: .strips)
    _ = v.moved(.down, dy: -0.12)
    #expect(v.lifted(dy: -0.05) == nil)
}
@Test func aFastSwipeGoesStraightToTheLongCommand() {
    var v = TrackpadVertical(mode: .strips)
    #expect(v.moved(.up, dy: 0.35) == .toggleWidth)
}
// MouseButtonGestureTests (strips mode): use the file's helpers to press the chord and drag.
//   stripsModeShortDragUpChangesStripOnRelease    → drag (0, -60), release → [.strip(up: true)]
//   stripsModeShortDragDownChangesStripOnRelease  → drag (0, 60), release → [.strip(up: false)]
//   stripsModeLongDragUpTogglesWidth              → drag (0, -60) then (0, -110) → [.toggleWidth]; release → []
//   stripsModeLongDragDownOpensTheOverview        → drag (0, 170) → [.overview]
//   stripsModeBackNearTheStartDoesNothing         → drag (0, 60), drag (0, -40), release → []
// PreferencesTests
//   verticalGestureDefaultsToStrips: decoding "{}" gives .strips; a stored "width" round-trips.
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh --filter "TrackpadSwipe|MouseButtonGesture|Preferences"`. Expected: it fails to build.
- [ ] **Step 3: Implement** the modes and the preference. Keep the width-mode code paths as they are.
- [ ] **Step 4: Run the tests to verify they pass.** Run `scripts/test.sh` and `swift build`. Expected: green, including every existing gesture test.
- [ ] **Step 5: Commit** with the message `feat(core): the vertical swipe can change strips; a long one maximizes`.

### Task 4: Actions and default shortcuts

**Files:**
- Modify:
  - `Sources/RamblaCore/Actions.swift`
  - `Sources/RamblaCore/Keys.swift`
  - `Sources/Rambla/Engine/WindowManager+Commands.swift`
  - `Packaging/en.lproj/Localizable.strings`
- Test:
  - `Tests/RamblaCoreTests/KeysTests.swift`
  - `Tests/RamblaCoreTests/CommandPolicyTests.swift`
  - any test that counts or lists every action

**Interfaces:**
- Produces:

| Case | Raw value | Title (Spanish) | English translation |
|---|---|---|---|
| `Action.stripUp` | `"strip-up"` | "Ir a la tira de arriba" | "Go to the strip above" |
| `Action.stripDown` | `"strip-down"` | "Ir a la tira de abajo" | "Go to the strip below" |
| `Action.sendStripUp` | `"send-strip-up"` | "Mandar a la tira de arriba" | "Send to the strip above" |
| `Action.sendStripDown` | `"send-strip-down"` | "Mandar a la tira de abajo" | "Send to the strip below" |

All four are in group `.navigate`, listed after `sendNextDisplay`.

**Default shortcuts** in `DefaultShortcuts`:
- ⌃⌥⌘↑ and ⌃⌥⌘↓ for going up and down;
- ⌃⌥⌘⇧↑ and ⌃⌥⌘⇧↓ for sending.

Extend the doc comment of `DefaultShortcuts`: ⌃⌥⌘ moves between the stacked strips, and ⇧ takes the focused window along.

**Engine:** `perform(_:)` in `WindowManager+Commands.swift` has an exhaustive switch. Until Task 6, list the four cases next to `.overview, .toggleFloat, .togglePause` (no-ops).

- [ ] **Step 1: Write the failing tests**
  - **`stripShortcutDefaults`:** the four exact default combos (key codes `KeyCode.up` and `KeyCode.down` with the modifiers above).
  - **`newActionsParseTheirIDs`:** `Action.parse("strip-up") == .stripUp`, and the same for the other three.
  - **`linksMayChangeStrips`:** `CommandPolicy.allows("send-strip-down", from: .url)`.
  - **Existing test:** `defaultsDoNotCollideWithRectangleAlternate` stays green. If the Spectacle-set test lists expected conflicts and one of the new combos appears there, stop and report instead of changing the expectation.
- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh --filter "Keys|CommandPolicy"`. Expected: it fails to build.
- [ ] **Step 3: Implement** the cases, titles, group, defaults, the engine no-ops and the English strings (`Packaging/en.lproj/Localizable.strings`, RamblaCore section).
- [ ] **Step 4: Run the tests to verify they pass.** Run `scripts/test.sh` and `swift build`. Expected: green.
- [ ] **Step 5: Commit** with the message `feat(core): shortcuts to change strips and send windows between them`.

### Task 5: Saved strips remember their level

**Files:**
- Modify:
  - `Sources/RamblaCore/SavedState.swift`
  - `Sources/Rambla/Engine/StateStore.swift` (call sites only, level 0, same behavior)
- Test:
  - `Tests/RamblaCoreTests/SavedStateTests.swift`
  - `Tests/RamblaCoreTests/StripArchiveTests.swift`

**Interfaces:**
- Produces:

```swift
// SavedStrip
public var level: Int            // 0 in files without it
public var activeLevel: Int?     // the stack's level in view when it was saved; nil in files without it
public init(displayUUID:spaceKey:strip:lastSeen:session:refs:unplugged:level: Int = 0, activeLevel: Int? = nil)
func isFor(displayUUID: String, spaceKey: String, level: Int) -> Bool

// StripArchive
public mutating func store(_ strip: SavedStrip, at now: Date)              // replaces only the same display, Space and level
public func stack(displayUUID: String, spaceKey: String) -> [SavedStrip]  // every level archived for them, by level
public mutating func takeStack(displayUUID: String, spaceKey: String) -> [SavedStrip]
/// For a display back with its desktop under a new key: the levels of the one Space archived unplugged for it, when
/// that Space is not among `spaces`; [] otherwise (replaces `strayStrip`).
public func strayStack(displayUUID: String, spaces: Set<String>) -> [SavedStrip]
/// The level of the unplugged strip saved in `session` that holds `id`.
public func unpluggedLevel(of id: WindowID, session: String) -> Int?
public func merged(into live: SavedState, at now: Date) -> SavedState     // a live strip replaces only the archived one of its display, Space and level
```

**Changes:**
- `take(displayUUID:spaceKey:)`, `strip(displayUUID:spaceKey:)` and `strayStrip` are replaced by the stack functions.
- In `StateStore.restoreFromSavedState`, use `stack(...).first` and `takeStack`, which behave as before while every strip is level 0. Task 8 makes the call sites level-aware.

- [ ] **Step 1: Write the failing tests**
  - **`oldSavedStripDecodesAsLevelZero`:** JSON without `level` or `activeLevel` decodes to level 0 and activeLevel nil.
  - **`levelRoundTrips`:** level 2 with activeLevel 1 encodes and decodes unchanged.
  - **`storeReplacesOnlyTheSameLevel`:** storing L0 and L1 of the same display and Space keeps both; storing L1 again replaces only L1.
  - **`takeStackReturnsEveryLevelInOrder`:** it also leaves nothing of that stack in the archive.
  - **`strayStackNeedsASingleArchivedSpace`:**
    - two levels of one unplugged Space that is not in `spaces` are returned;
    - with a second unplugged Space for the same display, the result is [];
    - with the Space in `spaces`, the result is [].
  - **`unpluggedLevelFindsTheWindow`:** an unplugged L1 strip in session "S" with a ref for window 7:
    - session "S" gives 1;
    - session "T" gives nil;
    - the same strip with `unplugged == false` gives nil.
  - **`mergedKeepsLevelsApart`:** a live L0 and an archived L1 of the same display and Space both end up in the result, while an archived L0 there is dropped.
- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh --filter "SavedState|StripArchive"`. Expected: it fails to build.
- [ ] **Step 3: Implement** the changes and fix the `StateStore` call sites (level 0).
- [ ] **Step 4: Run the tests to verify they pass.** Run `scripts/test.sh` and `swift build`. Expected: green.
- [ ] **Step 5: Commit** with the message `feat(core): saved strips remember their level`.

### Task 6: Stacked strips in the engine: switching, shelving, sending

**Files:**
- Create: `Sources/Rambla/Engine/WindowManager+Levels.swift`
- Modify:
  - `Sources/Rambla/Engine/WindowManager.swift`
  - `Sources/Rambla/Engine/WindowManager+Commands.swift`
  - `Sources/Rambla/Engine/WindowManager+Input.swift` (`stripKeyUnderPointer` stays level-aware through `currentKey`)
  - `Sources/Rambla/Engine/StateStore.swift` (compile fixes only)
- Tests: the app target has no unit tests. The pure parts were tested in Tasks 1–5. The controller runs the live tests after Task 7.

**Interfaces:**
- Consumes:
  - `StripLevels` (Task 1)
  - `Layout.shelved` (Task 2)
  - the four actions (Task 4)
- Produces (internal, used by Tasks 7–11):

```swift
struct StackKey: Hashable { let displayUUID: String; let spaceID: UInt64; func level(_ level: Int) -> StripKey }
struct StripKey: Hashable, Codable { let displayUUID: String; let spaceID: UInt64; var level: Int = 0; var stack: StackKey }
var activeLevels: [StackKey: Int]                          // missing: 0
func activeLevel(of stack: StackKey) -> Int
func topLevel(of stack: StackKey) -> Int                   // highest level with a strip; 0 when none
func occupiedLevels(of stack: StackKey) -> Set<Int>
func isCurrentStack(_ stack: StackKey) -> Bool             // its display shows that Space and is managed
func switchLevel(of stack: StackKey, to level: Int, focusing window: WindowID? = nil)
@discardableResult func stepLevel(up: Bool, on stack: StackKey) -> Bool
func sendFocusedWindow(up: Bool)
func moveColumn(id: UUID, from key: StripKey, toLevel level: Int, at index: Int?)
func shelve(_ key: StripKey)
var levelHook: ((StackKey) -> Void)?                       // a level change on that stack (indicator, Task 10)
var emptyLevelHook: ((StackKey) -> Void)?                  // arrived at an empty level (hint, Task 10)
```

**Required behavior:**

1. **Only the levels in view are "current."**
   - `currentKey(of:)` returns the key of the active level.
   - `display(for:)` returns nil unless `key.level` is its stack's active level, so `apply`, `currentKeys`, `isCurrent`, the overlays and the gestures act only on levels in view.
   - `stripKey(forSpace:)`, used for Space moves, returns the active level of that stack.
2. **Space keys per stack.** `spaceKeys` is keyed by `StackKey` (one Space UUID per stack); update every use.
3. **`switchLevel(of:to:focusing:)`**, in this order:
   1. Same level: only focus `window` if one was given.
   2. Set `activeLevels[stack]`, and create the target's strip if it has none.
   3. `apply(new, animate: false)`: the incoming windows jump into place, behind the others.
   4. `shelve(old)`.
   5. Drop `StripLevels.droppable(...)`: remove those strips and their `results` and `hidden` entries.
   6. Focus `window ?? strips[new]?.focusedWindow` with `focus(window:in:)`.
      - If there is none, Rambla takes the keyboard so no hidden window gets the typing: `focusedWindow = nil`, then activate Rambla's own process. `NSApp.activate()` may be ignored by cooperative activation; if so, `_SLPSSetFrontProcessWithOptions` on Rambla's PSN through a new `Private.activateOwnProcess()`.
      - Then `emptyLevelHook?(stack)`.
   7. `levelHook?(stack)`, `onStateChanged?()`, `scheduleSave()`.
   8. Log `"Strip level \(level) of display \(uuid.prefix(8))"`.
4. **`shelve(key)`:**
   - Lays out `Layout.shelved(layoutInput(...))` on the stack's display, skipping frozen and `heldForReturn` windows.
   - Writes only the frames that differ from `requested` or the known frame, after cancelling their animations, and records `requested`.
   - Sets `results[key]` to the shelved result.
5. **`reconcile()`:** after applying the current keys, `shelve` every other level of every current stack. This puts back anything that drifted and costs nothing when nothing did.
6. **`externalFrameChange` on a window whose key is not current but whose stack is:**
   - It never floats and never adopts a size.
   - With the mouse down, ignore it.
   - In the grace period, do as today (the reconcile at the end shelves it again).
   - Otherwise log `"Window \(id) of strip level \(level) moved by \(…): back to its place"` and `shelve(key)`.
7. **`focusChanged` on a window of a non-current level of a current stack:** call `switchLevel(of:to:focusing:)` to its level. Task 7 refines this.
8. **Actions.** `perform(_:)` handles these four before the strip guard:
   - `.stripUp` and `.stripDown` → `stepLevel` on `activeStripKey()?.stack`, or on the stack under the mouse when no strip is active.
   - `.sendStripUp` and `.sendStripDown` → `sendFocusedWindow(up:)`.
9. **`sendFocusedWindow(up:)`:**
   1. Target = `StripLevels.target`.
   2. Remove the focused window from its strip, keeping its column width.
   3. Insert it `.afterFocused` in the target level's strip.
   4. `switchLevel(of:to:focusing: id)`.
10. **`moveColumn(id:from:toLevel:at:)`:**
    1. Move the whole column (all its windows, width, mode and pin cleared) to index `at`, or after the target's focused column when nil.
    2. `apply` a source in view, and `shelve` a target not in view.
    3. Drop droppable levels, then `onStateChanged?()`.
11. **`gatherAll`** keeps iterating every strip, so shelved windows come back on quit and pause. **`removeWindow`** and the managed sets already see every level. Check both.
12. **`dumpJSON`:**
    - each strip gets `"level"` and `"active"` (`isCurrent(key)`);
    - a new top-level `"stacks"` lists `[{display, space, active, top}]`.

- [ ] **Step 1: Implement** behaviors 1–12.
- [ ] **Step 2: Build and test.** Run `swift build` and `scripts/test.sh`. Expected: green.
- [ ] **Step 3: Self-check by reading.**
  - Every remaining `strips[...]` lookup that must mean "in view" goes through `currentKeys`, `isCurrent` or `display(for:)`.
  - Every one that must mean "any level" iterates all keys.
  - List any you changed in the report.
- [ ] **Step 4: Commit** with the message `feat(levels): stacked strips per display and Space`.

### Task 7: Focus that lands on another strip

**Files:**
- Create:
  - `Sources/RamblaCore/FocusRoute.swift`
  - `Tests/RamblaCoreTests/FocusRouteTests.swift`
- Modify: `Sources/Rambla/Engine/WindowManager.swift`

**Interfaces:**
- Produces:

```swift
public enum FocusRoute: Equatable, Sendable {
    case none                    // in view, or a late report right after Rambla switched: nothing special to do
    case switchLevel             // go to the window's level
    case redirect(WindowID)      // focus this window of the level in view instead
    case takeKeyboard            // nothing in view to give the focus to: Rambla takes the keyboard (as on an empty strip)
    /// `windowLevel`: where the focused window is; `active`: the level in view. `byActivation`: its app was just
    /// activated (⌘Tab, the Dock, a notification). `afterLoss`: a window in view just closed or was minimized, or an
    /// app was just hidden or quit, so macOS moved the focus by itself. `appWindowsInView`: that app's windows in the
    /// level in view, most recently used first; `windowsInView`: every window there, most recently used first.
    /// `sinceOwnSwitch`: seconds since Rambla itself switched this stack's level (nil: long ago).
    public static func decide(windowLevel: Int, active: Int, byActivation: Bool, afterLoss: Bool,
                              appWindowsInView: [WindowID], windowsInView: [WindowID],
                              sinceOwnSwitch: Double?) -> FocusRoute
    public static let lateReportWindow = 0.6
}
```

**Rules, in order:**
1. Same level → `.none`.
2. After a loss → `.redirect(appWindowsInView.first ?? windowsInView.first)`, or `.takeKeyboard` when both are empty. macOS moving the focus by itself never changes the level.
3. Not by activation and `sinceOwnSwitch < lateReportWindow` → `.none`. The app that was in front reports focus on its window, now shelved, before the new one takes over.
4. By activation and `appWindowsInView` is not empty → `.redirect(first)`.
5. Otherwise → `.switchLevel`.

**Engine:**
- The `didActivateApplication` observer records `(pid, time)`. `byActivation` means the same pid within 0.5 s.
- Rambla records the time of each loss:
  - a window in view destroyed;
  - a window in view minimized;
  - `didHideApplication`;
  - `didTerminateApplication`.
- `afterLoss` means within `lateReportWindow` of a loss.
- `focusChanged` keeps `lastFocusedAt[WindowID]` for windows focused in view.
- `appWindowsInView` and `windowsInView` come from the active level's strip: windows that are not hidden, by `lastFocusedAt` descending, `appWindowsInView` limited to that pid.
- `switchLevel` records the time of Rambla's own switches per stack.
- How each route acts:

  | Route | Action |
  |---|---|
  | `.redirect` | `focus(window:in:)` |
  | `.switchLevel` | `switchLevel(of:to:focusing:)` |
  | `.takeKeyboard` | the same keyboard take-over as an empty level (Task 6, behavior 3) |

- [ ] **Step 1: Write the failing tests**
  - **`aWindowInViewNeedsNothing`:** same level gives `.none`.
  - **`activationWithAWindowInViewRedirectsToTheLastUsed`:** `appWindowsInView: [5, 9]` gives `.redirect(5)`.
  - **`activationWithoutWindowsInViewSwitches`:** gives `.switchLevel`.
  - **`focusWithoutActivationSwitches`:** Mission Control or ⌘` give `.switchLevel`, even with windows in view.
  - **`aLateReportRightAfterOwnSwitchIsIgnored`:** `sinceOwnSwitch: 0.2`, not by activation, gives `.none`; with `0.8` it gives `.switchLevel`; by activation at 0.2 it follows the activation rules.
  - **`aCloseKeepsTheSameAppWhenItCan`:** `afterLoss`, `appWindowsInView: [8]`, `windowsInView: [3, 8]` gives `.redirect(8)`.
  - **`aCloseThatHandsTheFocusToAnotherStripStays`:** `afterLoss`, `appWindowsInView: []`, `windowsInView: [3, 4]` gives `.redirect(3)`, even by activation (quitting an app activates the next one).
  - **`aCloseWithNothingLeftInViewTakesTheKeyboard`:** `afterLoss` with both lists empty gives `.takeKeyboard`.
- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh --filter FocusRoute`. Expected: it fails to build.
- [ ] **Step 3: Implement** `FocusRoute` and the engine wiring.
- [ ] **Step 4: Run the tests to verify they pass.** Run `scripts/test.sh` and `swift build`. Expected: green.
- [ ] **Step 5: Commit** with the message `feat(levels): focus on a window of another strip goes to it`.

### Task 8: Saving, restoring and displays with levels

**Files:**
- Modify:
  - `Sources/Rambla/Engine/StateStore.swift`
  - `Sources/Rambla/Engine/WindowManager.swift`
  - `Sources/Rambla/App/AppDelegate.swift` (`--state-file`)

**Interfaces:**
- Consumes:
  - Task 5's `SavedStrip` fields and `StripArchive` stack functions
  - `StripLevels.restoredActive`
  - Task 6's keys

**Required behavior:**
1. **`saveNow`** saves every strip that has columns, with `level: key.level` and `activeLevel: activeLevel(of: key.stack)`. A stack not rebuilt yet whose archive still has entries keeps the file's version. `restoredKeys` becomes `restoredStacks: Set<StackKey>`.
2. **`archiveStrip`** stores the level and the stack's active level. Archiving every key of a display or Space archives every level. Drop the stack's `activeLevels` entry once none of its levels remain.
3. **`restoreFromSavedState`, per current stack not rebuilt yet:**
   1. **Find the saved levels.** Use `archive.stack(display, spaceKey)`, or `strayStack` for a returning display whose Space came back under another key.
   2. **Match the windows.** Match level by level in ascending order, removing matched windows from the pool. The existing guards and wait rules stay, counting all levels.
   3. **Rebuild.** Build every level's strip, then set `activeLevels[stack] = StripLevels.restoredActive(saved activeLevel of the most recently seen entry, top: highest restored level)`.
   4. **Lay out.** `takeStack`, `apply` the active level, `shelve` the others.
   5. **Log one line per level.**
   6. **Take-back for a returning display.** It works per level in the same way, over the unplugged entries.
4. **Orphans in `reconcile()`.**
   - The level is `archive.unpluggedLevel(of: id, session: StateStore.session)`, or the active level when it is nil.
   - Insert into `stack.level(level)`. A level that is not in view gets shelved by the end of that reconcile.
5. **`heldForReturn`** looks at archived strips of every level.
6. **Test mode only (`--only-bundle`):** a `--state-file PATH` launch argument makes `StateStore` read and write that file instead of skipping state. Normal mode is unchanged.

- [ ] **Step 1: Implement** behaviors 1–6.
- [ ] **Step 2: Build and test.** Run `swift build` and `scripts/test.sh`. Expected: green.
- [ ] **Step 3: Commit** with the message `feat(levels): stacked strips survive restarts and display changes`.

### Task 9: Gestures and settings

**Files:**
- Modify:
  - `Sources/Rambla/Input/GestureTracker.swift`
  - `Sources/Rambla/Input/MouseButtonTracker.swift`
  - `Sources/Rambla/App/AppDelegate.swift`
  - `Sources/Rambla/Engine/WindowManager+Input.swift`
  - `Sources/Rambla/Settings/Views/TrackpadView.swift`
  - `Packaging/en.lproj/Localizable.strings`

**Interfaces:**
- Consumes:
  - `TrackpadVertical(mode:)` and `MouseButtonGesture(buttons:vertical:)` (Task 3)
  - `stepLevel(up:on:)` and `StripLevels.target` (Tasks 1 and 6)
- Produces:

```swift
// WindowManager+Input
/// A short vertical swipe: the fingers (or the pointer) went up when `fingersUp`. With the device's natural direction
/// the content follows them, so going down shows the strip above. Acts on the stack under the pointer.
func stripSwipe(fingersUp: Bool, onTrackpad: Bool)
/// The swipe just became a short vertical one: a haptic tap when there is a strip that way (trackpad, haptics on).
func stripSwipeArmed(fingersUp: Bool)
/// A long swipe up: the focused column's full width, or back to its width (like ⌃⌘M).
func toggleWidthBySwipe(onTrackpad: Bool)
```

**Required behavior:**
- **Gesture trackers.**
  - `GestureTracker.configure` takes the mode, and `perform` maps the new commands to the three engine functions.
  - `MouseButtonTracker` builds its gesture with `prefs.verticalGesture` and handles `.strip` and `.toggleWidth`.
  - Changing the preference reconfigures both trackers, the way `fingers` does now.
- **Direction.** `up = natural ? !fingersUp : fingersUp`, using `prefs.trackpad.natural` or `prefs.mouseButtons.natural`.
- **Haptics.** `Haptics.gesture()` on armed when there is a target, and on the long commands as today. Only on the trackpad, and only with haptics on.
- **Settings (`TrackpadView`).**
  - Rename the vertical toggle to "Gestos hacia arriba y abajo".
  - Below it, add a picker "Deslizar hacia arriba o abajo" with "Cambia de tira" (`.strips`) and "Cambia el ancho" (`.width`), bound to `verticalGesture` and disabled when the toggle is off.
  - Rewrite the trackpad footer and the mouse-buttons footer for the current mode, in the existing style:
    - **strips:** a short swipe changes strip on lift, a long one up maximizes or restores, a long one down opens the overview;
    - **width:** what they say today.
  - Add the English translations.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Build and test.** Run `swift build` and `scripts/test.sh`. Expected: green.
- [ ] **Step 3: Commit** with the message `feat(levels): the vertical swipe changes strips`.

### Task 10: Levels indicator and the empty-strip hint

**Files:**
- Modify:
  - `Sources/Rambla/Overlay/IndicatorController.swift`
  - `Sources/Rambla/Overlay/OverlayCoordinator.swift`
  - `Packaging/en.lproj/Localizable.strings`

**Interfaces:**
- Consumes:
  - `levelHook` and `emptyLevelHook` (Task 6)
  - `topLevel`, `activeLevel` and `strips`
- Produces:

```swift
struct LevelRow: Identifiable { let id: Int /* level */; let icons: [NSImage]; let isActive: Bool }
func showLevels(_ rows: [LevelRow], on screen: NSScreen)      // IndicatorController; rows highest level first
```

**The levels panel.**
- It uses the same frosted panel and the same place as the indicator: above the Dock, centered. It fades 0.8 s after the last call and is not interactive.
- Each row shows one icon per column, up to 8, taken from the app of the column's first window that is not hidden. An empty row says "Vacía".
- The active row is brighter and outlined in the accent color, like the focused tile. The other rows are at 45 % opacity.
- A call to `show` (the strip indicator) replaces it, and the other way around.

**`OverlayCoordinator`.**
- **On `levelHook`:** build rows for levels 0...top of the stack and show them on its display, if `prefs.indicatorEnabled`.
- **On `emptyLevelHook`:** `hint.show("Tira vacía", detail:)`. The detail is "Abrí acá lo que quieras, o traé la ventana enfocada con \(combo of send-strip-up). Para volver, deslizá hacia arriba o usá \(combo of strip-down)."
  - Use `KeyNames.display` of the current bindings.
  - Leave out a clause whose shortcut is unbound.
- Add the English translations.

- [ ] **Step 1: Implement.** Render the panel offscreen once (`NSHostingController.sizeThatFits`, `cacheDisplay`), check the size and the look, and say so in the report.
- [ ] **Step 2: Build and test.** Run `swift build` and `scripts/test.sh`. Expected: green.
- [ ] **Step 3: Commit** with the message `feat(levels): indicator of the stacked strips and a hint on an empty one`.

### Task 11: The overview shows every strip of the stack

**Files:**
- Create:
  - `Sources/RamblaCore/OverviewStack.swift`
  - `Tests/RamblaCoreTests/OverviewStackTests.swift`
- Modify:
  - `Sources/Rambla/Overlay/OverviewController.swift`
  - `Sources/Rambla/Overlay/OverlayCoordinator.swift`
  - `Packaging/en.lproj/Localizable.strings`

**Interfaces:**
- Consumes:
  - `Overview` (existing)
  - `switchLevel(of:to:focusing:)` and `moveColumn(id:from:toLevel:at:)` (Task 6)
- Produces:

```swift
public struct OverviewStack: Equatable, Sendable {
    public struct Row: Equatable, Sendable { public var level: Int; public var overview: Overview }
    public private(set) var rows: [Row]                 // highest level first
    public private(set) var selectedRow: Int
    /// The selection starts in the row of `activeLevel`, on that overview's own selection; when that row has no cards,
    /// in the nearest row that has.
    public init(rows: [Row], activeLevel: Int)
    public var selectedWindow: WindowID? { get }
    /// Left, right, first and last stay in the row. Up and down move inside the chosen card's stack and, past its top
    /// or bottom window, to the row above or below (skipping rows without cards), on the card whose drawn center is
    /// nearest; `drawn` holds each row's drawn cards, parallel to `rows`.
    public mutating func move(_ move: Overview.Move, drawn: [Overview.Drawn])
    public mutating func select(row: Int, _ selection: Overview.Selection)
}
```

**Tests (`OverviewStackTests`):**
- `selectionStartsOnTheActiveRow`
- `selectionOfAnEmptyActiveRowGoesToTheNearestRowWithCards`
- `upFromTheTopWindowGoesToTheNearestCardAbove`
- `downFromTheBottomWindowGoesToTheRowBelow`
- `upInsideAStackStaysInTheCard`
- `upAtTheTopRowStays`
- `leftAndRightStayInTheRow`

**Controller and view.**
- **Content.** `OverviewContent` holds an `OverviewStack` plus one items map. Every row uses the same card scale, chosen so the widest row fits the width and all rows fit 85 % of the screen's height. Rows are separated by 24 pt.
- **What each row shows.**
  - Only the row of the active level shows the viewport bar.
  - An empty row shows a "Vacía" placeholder card that cannot be chosen.
  - With a single row, the overview looks exactly like today.
- **Choosing.** Choosing a window in another row hides the overview, then calls `switchLevel(of:to:focusing:)` with that window.
- **Dragging.**
  - A card dragged vertically more than half a row's height lifts into the row under the pointer, where the cards make room as they do now. Dropping calls `moveColumn(id:from:toLevel:at:)` with that row's slot.
  - While any card is dragged, a "Tira nueva" row appears above the top row, unless the top row is an empty level. Dropping there moves the column to `top + 1`.
  - Within one row, reordering works as today.
- **Keys.**
  - ⇧↑ and ⇧↓ send the chosen card's column to the level above or below, after that level's focused column, and the overview shows the result with the card still chosen.
  - ↑ and ↓ use `OverviewStack.move`.
- **When it opens.** The overview opens when any level of the stack has windows. Only a stack with no windows at all shows the empty-display hint, as today.
- **English translations:** "Tira nueva" → "New strip", "Vacía" → "Empty".

- [ ] **Step 1: Write the failing `OverviewStackTests`.** Build them on `Overview(strip:metrics:pinnedWidths:gap:hidden:focused:)` with small strips and drawn rows from `drawn(scale:minimumWidth:minimumGap:)`.
- [ ] **Step 2: Run the tests to verify they fail.** Run `scripts/test.sh --filter OverviewStack`. Expected: it fails to build.
- [ ] **Step 3: Implement** `OverviewStack`, then the controller, view and coordinator changes. Render the overview offscreen with two rows to check it, and say so in the report.
- [ ] **Step 4: Run the tests to verify they pass.** Run `scripts/test.sh` and `swift build`. Expected: green.
- [ ] **Step 5: Commit** with the message `feat(overview): the overview shows every stacked strip`.

### Task 12: Live tests

**Files:**
- Modify:
  - `scripts/testhost.swift`: a `focus N` command that does `windows[N-1].makeKeyAndOrderFront(nil)` and `NSApp.activate()`.
  - `scripts/e2e-check.swift`: `check-levels COUNT ACTIVE`, `check-shelved` and `level-of ID`.
  - `scripts/e2e.sh`: a stacked-strips scenario before the final quit.
- **The implementer only writes the scripts; the controller runs them.**

**New checks in `scripts/e2e-check.swift`:**
- **`check-levels COUNT ACTIVE`:** the current display's stack, from the `dump` "stacks" entry, has COUNT levels and ACTIVE in view.
- **`check-shelved`:** every window of a non-current level of a current stack shows at most `sliver + 1` pt on its display and nothing on any other display, measured with CGWindowList bounds.

**Scenario steps** (4 TestHost windows):
1. `strip-up`: `check-levels 2 1`, `check-shelved`.
2. `strip-down`: `check-levels 1 0`, `check-placed`.
3. `focus-2` and then `send-strip-up`: `check-levels 2 1`; one window placed and 3 shelved.
4. `host "focus 1"`: TestHost is already frontmost, so this is no activation. Then `check-levels 2 0`.
5. `debug-external-move` on a shelved window. After the grace period it is shelved again and not floating.
6. `toggle-pause` twice: on pause the windows are gathered (`check-gathered`); on resume `check-shelved`.
7. `debug-neighbor` on the right: `check-shelved`, so no shelved window shows on the fake display.
8. Restart with `--state-file`:
   1. Quit Rambla (SIGTERM).
   2. Relaunch it with `--only-bundle` and the same `--state-file`.
   3. `check-levels 2 0`, and `level-of` the sent window is 1.
- [ ] **Step 1: Write the scripts.**
- [ ] **Step 2: Compile the checker.** Run `swiftc -O scripts/e2e-check.swift -o .build/e2e-check`. Expected: it compiles.
- [ ] **Step 3: Commit** with the message `test(e2e): live checks for stacked strips`.

### Task 13: Documentation

**Files:**
- Modify:
  - `docs/MANUAL.md` and `docs/MANUAL.en.md`
  - `README.md` and `README.es.md`
  - `docs/superpowers/specs/2026-10-21-scroll-design.md`
  - the welcome pages, only if they describe the vertical swipe (`grep -rn "ancho completo" Sources/Rambla/Onboarding`)

**What to write:**
- **Manual.** Describe the stacked strips, following the design document's "Comportamiento" in the manual's voice:
  - the gestures in both modes;
  - the shortcuts;
  - what happens with focus, ⌘Tab and Mission Control;
  - the overview rows;
  - an empty strip;
  - displays.
- **READMEs.** A short feature bullet.
- **Main spec.**
  - Update these sections: Trackpad, Mouse, Acciones y atajos, Vista general, Pantallas, Persistencia, Estacionamiento.
  - Point to the new design document instead of repeating it.
- [ ] **Step 1: Write.**
- [ ] **Step 2: Commit** with the message `docs: stacked strips`.
