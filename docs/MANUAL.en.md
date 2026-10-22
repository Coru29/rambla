# Rambla manual

<p><a href="MANUAL.md">Leer en español</a></p>

Rambla arranges your windows on a **horizontal strip**, like a promenade that keeps going past the edges of your screen. This manual explains how to use it, from day one to the tricks.

> Rambla's interface follows your Mac's language: it is in Spanish on a Mac set to Spanish and in English otherwise. This manual uses the English names.

**Contents**

1. [The idea in 30 seconds](#1-the-idea-in-30-seconds)
2. [Install and permission](#2-install-and-permission)
3. [First steps](#3-first-steps)
4. [Concepts](#4-concepts)
5. [Moving around the strip](#5-moving-around-the-strip)
6. [Widths and heights](#6-widths-and-heights)
7. [Stacks and tabs](#7-stacks-and-tabs)
8. [Pinned columns](#8-pinned-columns)
9. [Floating windows and Rectangle](#9-floating-windows-and-rectangle)
10. [Mouse and trackpad](#10-mouse-and-trackpad)
11. [Multiple displays and desktops](#11-multiple-displays-and-desktops)
12. [Visual aids](#12-visual-aids)
13. [Settings](#13-settings)
14. [Automation](#14-automation)
15. [Common problems](#15-common-problems)
16. [Uninstall](#16-uninstall)

---

## 1. The idea in 30 seconds

On macOS, every new window lands on top of the others or makes you shrink them. Rambla does something else: **every window is a column**, and the columns sit side by side on a strip that can be wider than your screen. The screen is a small window that slides along that strip.

```
              what you see on screen
          ┌───────────────────────────┐
  ┊ Mail ┊│  Safari   │   Terminal    │┊ Notes ┊ Music ┊
          └───────────────────────────┘
   ← off screen                          off screen →
```

- You open a window: it appears **next to the one you are using**, without shrinking the others.
- You focus another window (with a shortcut, a click, ⌘Tab or the Dock): **the strip slides** until it is fully visible.

## 2. Install and permission

1. Open the `.dmg` and drag **Rambla** to the **Applications** folder.
2. Open Rambla from Applications. An icon appears in the menu bar: three windows on the promenade. The first time, a short guide (**Welcome**) also opens and walks you through the permission, the trackpad and the basic shortcuts; you can open it again from the menu at any time.
3. macOS asks for the **Accessibility** permission, which is what lets Rambla move other apps' windows. Go to **System Settings → Privacy & Security → Accessibility** and turn **Rambla** on. If the prompt does not show up, Rambla's menu has **Open Accessibility Settings…**.
4. That's it: Rambla notices the permission by itself and arranges your windows.

> Rambla is not notarized by Apple. If macOS says it cannot verify the developer, right-click the app and choose **Open**.

Rambla does not need Screen Recording, Input Monitoring, or SIP disabled.

### Updates

Rambla checks GitHub for a new version when it starts and once a day. When there is one, the menu shows **Update to Rambla X…**: it lists what is new and, if you accept, Rambla downloads itself, checks that the new version carries the same signature, replaces itself and reopens. The Accessibility permission is kept. You can also check by hand with **Check for Updates…** in the menu, or turn the automatic check off in Settings → General → **Check for updates automatically**.

## 3. First steps

When it starts, Rambla takes the windows on the current desktop and lines them up, left to right, in the order they were. Try this:

1. Press **⌃⌘→** and then **⌃⌘←** (Control + Command + arrow). Focus moves from one window to the other and the strip slides.
2. Press **⌃⌘R** a few times. The focused window cycles through widths: 25 %, 33 %, 50 %, 66 % and 75 % of the screen.
3. Open a new window in any app (for example ⌘N in Safari). It appears right after the one you had focused.
4. Press **⌃⌘⇧→**. The focused column moves one place to the right.

If you don't like something, everything can be changed in **Settings**: Rambla's menu → Settings…. To make Rambla stop arranging for a while, use **Pause Rambla** in the same menu.

## 4. Concepts

| Concept | What it is |
|---|---|
| **Strip** | The row of columns. There is one per display and per desktop (Space). |
| **Column** | A place on the strip. It usually holds one window, but it can hold several (a stack or tabs). |
| **Focused window** | The one receiving the keyboard. Its column is always fully visible. |
| **Parked windows** | The ones outside the screen. macOS does not let a window leave the screen completely, so Rambla leaves **1 point** of them visible at the edge. If you see a thin line at the edge of the screen, that's it. |
| **Floating windows** | The ones that are not on the strip: dialogs, panels, windows that cannot be resized, and the ones you (or Rectangle) took out. Rambla leaves them alone. |
| **Pinned column** | A column stuck to the left or right edge that does not move with the strip. |

## 5. Moving around the strip

| Shortcut | What it does |
|---|---|
| ⌃⌘← / ⌃⌘→ (or ⌃⌘H / ⌃⌘L) | Focus the column on the left / right |
| ⌃⌘↑ / ⌃⌘↓ (or ⌃⌘K / ⌃⌘J) | Focus the window above / below inside a stack or tabs |
| ⌃⌘A / ⌃⌘E | Go to the first / last column |
| ⌃⌘1 … ⌃⌘9 | Go straight to column 1 … 9 |
| ⌃⌘⇧← / ⌃⌘⇧→ (or ⌃⌘⇧H / ⌃⌘⇧L) | Move the focused column left / right |
| ⌃⌘⇧↑ / ⌃⌘⇧↓ (or ⌃⌘⇧K / ⌃⌘⇧J) | Move the window up / down inside its stack |
| ⌃⌘N | Send the window to the strip of the next display |

You can also focus as usual: with a click, ⌘Tab, the Dock or Mission Control. The strip slides all the same.

**Centering.** By default the strip moves just enough for the focused column to be fully visible. In Settings → General you can make it center the column **always** or **only when the strip does not fit on the screen**. **⌃⌘C** centers the focused column at any time.

## 6. Widths and heights

| Shortcut | What it does |
|---|---|
| ⌃⌘R | Cycle through the preset widths (25, 33, 50, 66 and 75 %, editable) |
| ⌃⌘M | Full width. Press it again to go back to the width it had. |
| ⌃⌘= / ⌃⌘- | Wider / narrower, in 5 % steps (configurable) |
| ⌃⌘⇧= / ⌃⌘⇧- | Taller / shorter: in a stack it changes the window's share |
| ⌃⌘0 | Equalize the heights of the stack |

- **With the mouse**: if you resize a window by dragging its edge, Rambla adopts that width for the column.
- **New windows** keep their own width by default. In Settings → General you can set a fixed one (33, 50 or 66 %).
- **Keep original height**: turn it on in General if you prefer windows to keep the height they open with, aligned to the top, instead of taking the full height.
- Some apps have a minimum width (Safari, for example). Rambla detects it by itself and fits the rest around it.

## 7. Stacks and tabs

A column can hold several windows.

| Shortcut | What it does |
|---|---|
| ⌃⌘[ / ⌃⌘] | Put the focused window into the column on the left / right (stack) |
| ⌃⌘⇧[ / ⌃⌘⇧] | Take it out of the stack into a new column, to the left / right |
| ⌃⌘⇧T | Switch the column between **stack** (one above the other) and **tabs** |

- **Stack**: the windows share the height. With ⌃⌘⇧= / ⌃⌘⇧- you give the focused one more or less room, and ⌃⌘0 equalizes them.
- **Tabs**: the windows take the same place and a bar with each one's icon and title appears on top. Click a tab or use ⌃⌘↑ / ⌃⌘↓ to switch.
- **macOS's own tabs** (Finder's or Terminal's) take a single column.

## 8. Pinned columns

**⌃⌘P** pins the focused column to the **left** edge and **⌃⌘⇧P** to the **right** edge. The column stays in view, at full height, and the rest of the strip slides in the remaining space. It is useful to keep music, chat or a to-do list always visible.

- Press the shortcut again to release it; it goes back to its place on the strip.
- There is one pinned column per side.

## 9. Floating windows and Rectangle

**⌃⌘T** takes the focused window off the strip: it is centered, floating, and Rambla does not touch it anymore. Press it again with that window focused to put it back on the strip, next to the focused column.

**Rambla gets along with Rectangle.** You can keep using Rectangle as always:

- Rambla's shortcuts use **⌃⌘** and Rectangle's use **⌃⌥**, so they don't clash. With Rectangle's Spectacle set a couple do: the Mac page tells you which.
- If you use Rectangle on a window of the strip (left half, maximize, center…), **that window leaves the strip and stays floating where Rectangle put it**. Rambla does not fight Rectangle.
- To put it back on the strip: ⌃⌘T with that window focused, or **Rearrange Windows** in the menu, which brings back every window that left this way. They also come back by themselves when Rambla restarts or updates; the ones you took out with ⌃⌘T stay floating.
- The same happens with Rectangle's snap areas (dragging a window to the edge of the screen).
- Settings → Mac warns you if any of Rambla's shortcuts matches one of your Rectangle's.
- If you don't want this behavior, turn off "When another app (like Rectangle) moves a window, take it out of the strip" in Settings → General.

## 10. Mouse and trackpad

**Reorder with the mouse.** Grab a window by its title bar and drop it on another column. It moves to that place, before or after depending on which side of the column you drop it. If you drop it on another display, it moves to that display's strip.

**Swipe with the trackpad.** Swipe left or right with **four fingers** (you can change it to three): the strip follows your fingers and settles on a column when you let go. A short quick swipe is enough to reach the next one.

> macOS uses that gesture to switch desktops too, and Rambla cannot block it. Watch out for a trap in System Settings: for **"Swipe between full-screen applications"**, the **three-finger** option also keeps the four-finger swipe on, without showing it. Pick one of these setups:
>
> - **Four fingers for Rambla (recommended):** in Settings → Trackpad & Mouse, click **Turn Off in macOS**. Rambla turns off only the macOS four-finger swipe, and three fingers still switch desktops. By hand, the closest you can get is setting "Swipe between full-screen applications" to **Off** in System Settings → Trackpad → More Gestures, and switching desktops with ⌃← / ⌃→.
> - **Three fingers for Rambla:** in System Settings → Trackpad → More Gestures, set "Swipe between full-screen applications" to **four fingers** and "Swipe between pages" to **two fingers**. Then choose three fingers in Settings → Trackpad & Mouse. This option does not work if you use "three finger drag".
>
> Settings → Trackpad & Mouse (and the Mac page) tells you if Rambla's gesture collides with the system's.

**Full width from the trackpad.** Swipe **up** with the same fingers and the focused column takes the whole width of the screen, without macOS's full screen (like ⌃⌘M). Swipe **down** to go back to the width it had. macOS opens Mission Control with that gesture, and its three-finger option keeps the four-finger one on too: Settings → Trackpad & Mouse warns you and turns it off with **Turn Off in macOS** (Mission Control keeps working with three fingers and ⌃↑). You can turn this gesture off on the same page.

**Move the strip with the mouse wheel.** Hold **⌃⌘** and turn the wheel: each notch focuses the next column. With a Magic Mouse, or two fingers on a trackpad, holding ⌃⌘ slides the strip like the gesture, and it settles when you let go. Without the keys, the wheel scrolls as usual. You can change the keys in Settings → Trackpad & Mouse.

**Mouse follows focus / focus follows mouse.** Two options in Settings → Appearance, off by default. The first moves the pointer to the center of the window you focus with a shortcut. The second focuses the window under the pointer, without moving the strip.

## 11. Multiple displays and desktops

- **Every display and every desktop has its own strip**, with its own focus and scroll. When you switch desktops, Rambla picks up that desktop's strip as you left it.
- If you move a window to another desktop from Mission Control, Rambla moves it to that desktop's strip.
- **⌃⌘N** sends the focused window to the next display.
- You can turn Rambla off for a display in Settings → Displays. Nothing is arranged there.
- **Recommended**: keep "Displays have separate Spaces" on (the macOS default). With two monitors, ideally place the second one **above or below** the main one in System Settings → Displays → Arrange. Side by side works too, but windows can only peek halfway toward the other monitor before they are parked.
- **Full-screen** windows (green button) leave the strip while they are full screen and come back to their place when you exit.
- **Minimized** windows and windows of **hidden** apps (⌘H) leave their place without taking space and reappear in the same spot.

## 12. Visual aids

- **Strip indicator**: when you navigate with shortcuts or swipe, a frosted bar appears at the bottom with one icon per column. It highlights the focused one and marks the visible ones. It stays while you hold ⌃⌘. Click an icon to go to that column or drag it to reorder. It can be turned off in Settings → Appearance.
- **Focus border**: a colored border around the focused window. Off by default. Color and width are set in Appearance.
- **Dim inactive windows**: slightly darkens everything except the focused window. Off by default. The intensity is set in Appearance.

## 13. Settings

Open them from the menu bar icon → **Settings…**. While the window is open, Rambla shows up in the Dock.

| Section | What it is for |
|---|---|
| **General** | Enable or pause, launch at login, animations and their speed, centering, width of new windows, keep original height, gaps between windows and margin, preset widths, adjustment step, what to do when another app moves a window |
| **Shortcuts** | Change any shortcut (each action takes two). Click the shortcut and press the new combination: ⎋ cancels and ⌫ clears it. It warns you if it clashes with Rectangle or if macOS doesn't allow it. **Restore Defaults** brings everything back. |
| **Trackpad & Mouse** | The trackpad gesture (fingers, sensitivity, natural direction, swipe up for full width), conflicts with macOS and the mouse wheel |
| **Appearance** | Strip indicator, focus border, dim inactive windows, mouse ↔ focus |
| **Apps** | Per-app rules: always float (great for calculators, players or small chats), initial width, and where its windows open (next to the focused one, at the start or at the end) |
| **Displays** | Turn Rambla on or off for each monitor |
| **Mac** | Checks the macOS settings that affect Rambla (permission, Spaces, Stage Manager, gestures, Rectangle) and takes you to the right System Settings pane |
| **Automation** | Install the `rambla` command and export Raycast scripts |
| **About** | Version, project link and log |

### The menu bar menu

| Item | What it does |
|---|---|
| Pause / Resume Rambla | Stops arranging and brings every window back on screen. When resumed, the strip is put back together. |
| Rearrange Windows | Re-checks every window, brings back to the strip the ones another app (like Rectangle) took out, and applies the order again |
| Bring All Windows on Screen | Rescues any window parked at an edge |
| Float / Unfloat Current Window | Same as ⌃⌘T |
| Settings… | Opens the settings |
| Welcome… | Opens the first-run guide again: permission, trackpad and basic shortcuts |
| User Manual | Opens this manual |
| Show Log | Opens the activity log, useful if something goes wrong |

## 14. Automation

Every action has a short name, for example `focus-left`, `cycle-width`, `focus-3`, `pin-left` or `toggle-pause`. `rambla list` prints them all.

**Links:**

```sh
open -g "rambla://focus-left"
open -g "rambla://cycle-width"
```

**Terminal:** install the command in Settings → Automation → **Install `rambla` Command**.

```sh
rambla focus-right
rambla toggle-pause
rambla list
```

**Raycast:** in Settings → Automation → **Export Raycast Scripts…** choose a folder and add it in Raycast (Settings → Extensions → Script Commands → Add Directories). You get one command per action, for example "Rambla: Cycle width".

The links also work in Apple Shortcuts, Alfred, Keyboard Maestro, BetterTouchTool or any tool that can open a URL.

## 15. Common problems

**I see a thin line at the edge of the screen.** Those are parked windows: macOS does not let a window hide completely, so Rambla leaves 1 point visible. Click there and the strip slides to that window.

**I lost a window.** Rambla's menu → **Bring All Windows on Screen**. Rambla also brings them back when it quits or pauses.

**A window is not on the strip.** Rambla leaves dialogs, panels and windows that cannot be resized floating. If it is a normal window, check whether you took it out with ⌃⌘T or with Rectangle (in that case, ⌃⌘T puts it back) and whether it has a **Float** rule in Settings → Apps.

**A window left the strip by itself.** Another app moved it (Rectangle, a double-click on the title bar, the green button with ⌥). That is on purpose: Rambla does not fight other apps. Put it back with ⌃⌘T.

**Swiping on the trackpad switches desktops.** macOS uses the same gesture, even when System Settings says three fingers: see [section 10](#10-mouse-and-trackpad).

**A shortcut does nothing.** Another app may already use it. Check Settings → Shortcuts, which flags the ones macOS did not let Rambla register, and pick another one.

**Rambla asks for the Accessibility permission again.** In System Settings → Privacy & Security → Accessibility, remove Rambla with "−" and add it again from Applications.

**Something looks wrong.** Try **Rearrange Windows**. If it persists, **Show Log** shows what happened; that information helps when reporting the problem on [GitHub](https://github.com/Coru29/rambla/issues).

## 16. Uninstall

1. Rambla's menu → **Quit Rambla**. Every window comes back on screen.
2. Delete **Rambla** from Applications.
3. In System Settings → Privacy & Security → Accessibility, remove Rambla with "−".
4. To leave nothing behind, also delete:

   ```sh
   rm -rf ~/Library/Application\ Support/Rambla ~/Library/Logs/Rambla
   defaults delete io.github.coru29.Rambla
   sudo rm -f /usr/local/bin/rambla   # only if you installed the command
   ```
