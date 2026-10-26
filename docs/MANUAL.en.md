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
12. [Stacked strips](#12-stacked-strips)
13. [Visual aids](#13-visual-aids)
14. [Settings](#14-settings)
15. [Automation](#15-automation)
16. [Common problems](#16-common-problems)
17. [Uninstall](#17-uninstall)

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

> Rambla is not notarized by Apple, so macOS will not open it the first time. Go to **System Settings → Privacy & Security** and click **Open Anyway**. On macOS 14, right-clicking the app and choosing **Open** is enough.

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
| **Strip** | The row of columns. Every display and every desktop (Space) has its own. |
| **Stacked strips** | Several strips one above the other on the same display and desktop. You see one at a time (chapter 12). |
| **Column** | A place on the strip. It usually holds one window, but it can hold several (a stack or tabs). |
| **Focused window** | The one receiving the keyboard. Its column is always fully visible. |
| **Parked windows** | The ones outside the screen. macOS does not let a window leave the screen completely, so Rambla leaves **1 point** of them visible at the edge. If you see a thin line at the edge of the screen, that's it. The windows of the stacked strips you do not see are parked too. |
| **Floating windows** | The ones that are not on the strip: dialogs, panels, windows that cannot be resized, and the ones you (or Rectangle) took out. Rambla leaves them alone, unless you change strips (chapter 9). |
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
| ⌃⌥⌘↑ / ⌃⌥⌘↓ | Go to the strip above / below (see [Stacked strips](#12-stacked-strips)) |
| ⌃⌥⌘⇧↑ / ⌃⌥⌘⇧↓ | Send the focused window to the strip above / below and follow it |
| ⌃⌘O | Open the overview of the strip |

You can also focus as usual: with a click, ⌘Tab, the Dock or Mission Control. The strip slides all the same. If you use stacked strips, a window of another strip may take you to that strip: see [chapter 12](#12-stacked-strips).

**Overview.** **⌃⌘O** (or a long move down on the trackpad or with the mouse buttons, see chapter 10) shows the whole strip of the display at a glance: every window with its app and title, the stacks, the tabs and the pinned columns. A bar on top marks the part that is on screen now. If you have several stacked strips, you see a row per strip ([chapter 12](#12-stacked-strips)). Click a window to go there, or pick it with the arrows and press ↩; 1 … 9 jump to that column. To change the order, drag a window to another place, or choose it and press ⇧← or ⇧→ (⌃⌘⇧← → too): its column moves in the strip (pinned ones stay at their edge). Esc, ⌘W, a click outside or ⌃⌘O again close it. While it is open, Rambla's focus shortcuts (⌃⌘ + arrows, ⌃⌘1 … 9) move the selection instead of the strip, and the ones that change strips (⌃⌥⌘↑ / ⌃⌥⌘↓) move it to the row above or below.

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

- Rambla's shortcuts use **⌃⌘** and Rectangle's use **⌃⌥**, so they don't clash. (The ones that change strips use ⌃⌥⌘ with ↑ and ↓, and Rectangle uses ⌃⌥⌘ only with ← and →.) With Rectangle's Spectacle set a couple do: the Mac page tells you which.
- If you use Rectangle on a window of the strip (left half, maximize, center…), **that window leaves the strip and stays floating where Rectangle put it**. Rambla does not fight Rectangle.
- To put it back on the strip: ⌃⌘T with that window focused, or **Rearrange Windows** in the menu, which brings back every window that left this way, each one to the strip it came from. They also come back by themselves when Rambla restarts or updates; the ones you took out with ⌃⌘T stay floating.
- The same happens with Rectangle's snap areas (dragging a window to the edge of the screen).
- Settings → Mac warns you if any of Rambla's shortcuts matches one of your Rectangle's.
- If you don't want this behavior, turn off "When another app (like Rectangle) moves a window, take it out of the strip" in Settings → General.

**Floating windows and stacked strips.** If you use several stacked strips ([chapter 12](#12-stacked-strips)), not every floating window behaves the same when you change strips:

- The ones that float because of an app rule, dialogs, panels, windows that cannot be resized, Picture in Picture and Quick Look **are seen on every strip**.
- The ones that float because of ⌃⌘T, and the ones Rambla left floating because another app moved them (Rectangle), **go with their strip**: they are parked with it and come back to their place when you return.

## 10. Mouse and trackpad

**Reorder with the mouse.** Grab a window by its title bar and drop it on another column. It moves to that place, before or after depending on which side of the column you drop it. If you drop it on another display, it moves to that display's strip.

**Swipe with the trackpad.** Swipe left or right with **four fingers** (you can change it to three): the strip follows your fingers and settles on a column when you let go. A short quick swipe is enough to reach the next one. While those fingers are on the trackpad, the app under the pointer does not scroll. On a Force Touch trackpad you feel a gentle tap each time the strip is about to pass a column (in a quick swipe, as soon as it starts), and another with the swipes up and down (to switch strips, only if there is a strip that way); if you would rather not, turn off **Haptic feedback** in Settings → Trackpad & Mouse.

> macOS uses that gesture to switch desktops too, and Rambla cannot block it. Watch out for a trap in System Settings: for **"Swipe between full-screen applications"**, the **three-finger** option also keeps the four-finger swipe on, without showing it. Pick one of these setups:
>
> - **Four fingers for Rambla (recommended):** in Settings → Trackpad & Mouse, click **Turn Off in macOS**. Rambla turns off only the macOS four-finger swipe, and three fingers still switch desktops. By hand, the closest you can get is setting "Swipe between full-screen applications" to **Off** in System Settings → Trackpad → More Gestures, and switching desktops with ⌃← / ⌃→.
> - **Three fingers for Rambla:** in System Settings → Trackpad → More Gestures, set "Swipe between full-screen applications" to **four fingers** and "Swipe between pages" to **two fingers**. Then choose three fingers in Settings → Trackpad & Mouse. This option does not work if you use "three finger drag".
>
> Settings → Trackpad & Mouse (and the Mac page) tells you if Rambla's gesture collides with the system's.

**Up and down on the trackpad.** With the same fingers you can also swipe up or down. What it does is chosen in Settings → Trackpad & Mouse → **Swiping up or down**:

- **Switches strips** (the default). A short swipe down, and letting go, shows the strip above; a short swipe up, the strip below (see [Stacked strips](#12-stacked-strips)). A long swipe up gives the focused column the whole width of the screen, without macOS's full screen (like ⌃⌘M), or gives back the width it had if it already had the full one. A long swipe down opens the **overview**. The long ones act right away, without waiting for you to let go. If you come back before letting go, nothing happens.
- **Changes the width** (the old gesture). **Up**, the focused column takes the whole width of the screen, without macOS's full screen (like ⌃⌘M). **Down** and letting go, it goes back to the width it had; keep going down a good stretch and the **overview** opens.

With **Natural direction** (on by default), the content follows your fingers: move them down and the strip above appears, like dragging a page down to see what is above. Without it, it is the other way around. The long swipes do not change with this option.

macOS opens Mission Control with the swipe up, and its three-finger option keeps the four-finger one on too: Settings → Trackpad & Mouse warns you and turns it off with **Turn Off in macOS** (Mission Control keeps working with three fingers and ⌃↑). If you do not want these gestures, turn off **Swipes up and down** on the same page. That switch is for the trackpad only: the mouse button gestures have their own, below.

**Move the strip with the mouse wheel.** Hold **⌃⌘** and turn the wheel: each notch focuses the next column. With a Magic Mouse, or two fingers on a trackpad, holding ⌃⌘ slides the strip like the gesture, and it settles when you let go. Without the keys, the wheel scrolls as usual. You can change the keys in Settings → Trackpad & Mouse.

**Mouse button gestures.** In Settings → Trackpad & Mouse → Mouse buttons, turn on **Mouse button gestures** and choose the buttons: click the **Buttons** field, press the ones you want together (both side buttons, 4 and 5, for example) and let go. Then hold those buttons and move the mouse:

- **Sideways**, the strip follows the pointer and settles on a column when you let go. A short quick move reaches the next one.
- **A little down** and letting go, it shows the strip above; **a little up**, the strip below. That is with the buttons' **Natural direction**, which is on by default; without it, it is the other way around.
- **Up a good stretch**, the focused column takes the full width or, if it already had it, goes back to the width it had.
- **Down a good stretch**, the **overview** opens.

That is with **Switches strips** (the default). With **Changes the width**, **up** the focused column takes the full width and **down**, once you let go, it goes back to the width it had; keep going down a good stretch and the **overview** opens. That option is in the Trackpad section of the same page and applies to the mouse buttons too.

With a single button (the middle one, say), a click without moving still works as usual. With several, each button on its own keeps doing its job too: Rambla waits a moment for the other one and, if it does not come, hands the click to the app. Sensitivity and direction are in the same section.

> **With Mac Mouse Fix or another app that uses the mouse buttons:** pick a combination that app does not use, like 4 + 5 together. Rambla gets the buttons and the wheel before those apps, so ⌃⌘ + wheel works even though Mac Mouse Fix zooms with ⌘ + wheel. If one of those apps restarts, Rambla gets back in front within a few seconds.

**Mouse follows focus / focus follows mouse.** Two options in Settings → Appearance, off by default. The first moves the pointer to the center of the window you focus with a shortcut. The second focuses the window under the pointer, without moving the strip.

## 11. Multiple displays and desktops

- **Every display and every desktop has its own strip** (or several stacked ones, [chapter 12](#12-stacked-strips)), with its own focus and scroll. When you switch desktops, Rambla picks up that desktop's strip as you left it.
- If you move a window to another desktop from Mission Control, Rambla moves it to that desktop's strip.
- **⌃⌘N** sends the focused window to the next display. If you open the overview on a display without windows (on none of its strips), it reminds you how to bring one.
- You can turn Rambla off for a display in Settings → Displays. Nothing is arranged there.
- **Recommended**: keep "Displays have separate Spaces" on (the macOS default). With two monitors, ideally place the second one **above or below** the main one in System Settings → Displays → Arrange. Side by side works too: windows peek at most halfway toward the other monitor, and those beyond that side are parked on the opposite edge (they still come and go through their own side).
- **Full-screen** windows (green button) leave the strip while they are full screen and come back to their place when you exit.
- **Minimized** windows and windows of **hidden** apps (⌘H) leave their place without taking space and reappear in the same spot, even if you plug in another display or open the lid meanwhile.
- If you **unplug a display** (taking a laptop off its dock, for example) and more than 15 seconds go by, its windows join the strip of the display macOS moves them to. If you close the Mac's lid, the ones on its screen join right away. With stacked strips, each strip joins the one in the same place, as [chapter 12](#12-stacked-strips) explains. **When you plug it back in, they go back to their places**, in the same order and with their widths. The ones that go back are those on screen at that moment: a minimized one, or one on another desktop, stays where it is. Windows you opened meanwhile stay where they are. Until it returns, Rambla remembers its arrangement for up to a month, even across restarts; after the Mac restarts, it recognizes each window by its title.

## 12. Stacked strips

Want to keep work and home apart on the same screen? With stacked strips you can have **more than one strip per display and per desktop, one above the other**. You see one at a time. The usual one is the one at the bottom: keep your work there, and put home above it.

```
            ┊ Music ┊ Chat ┊ Shopping ┊     ← home (out of sight)
          ┌───────────────────────────┐
  ┊ Mail ┊│  Safari   │   Terminal    │┊ Notes ┊   ← work (in view)
          └───────────────────────────┘
```

You switch between them with a swipe, a shortcut or the overview. The switch is quick, it does not go through Mission Control and it does not use macOS desktops. Inside each strip everything works as usual, and each one keeps its own focus, scroll and pinned columns. The windows of the strips you do not see are parked at the edge of the screen, like the columns that are out of view. If macOS or an app moves one, Rambla parks it again: it never floats because of that.

> Do not mix them up with the stacks of [chapter 7](#7-stacks-and-tabs), which pile windows inside a column. Here whole strips are stacked.

Try this:

1. Press **⌃⌥⌘↑**. An empty strip appears above, and the windows you had leave the view: they are still on the strip below.
2. Open an app that is not open yet. It appears on the new strip, and so do its new windows (⌘N). An app that already has windows below, though, takes you down to them.
3. Press **⌃⌥⌘↓** to go back to the strip below, and **⌃⌥⌘↑** to go back up to the one that kept its window.

### How they come and go

- Above the highest strip that has windows you can always go up to a **new, empty strip**. It exists only once you go up there or send it a window.
- An empty strip that is above every strip with windows **goes away by itself** as soon as you stop seeing it.
- Empty strips below or in the middle **stay**. That way "work below, home above" does not flip over when one of the two is empty for a while. The bottom one, the usual one, is always there.
- You cannot go up from an empty strip that is already the highest, or down from the bottom one: nothing happens.

### Switching strips

**With the trackpad or the mouse buttons.** A short swipe down, and letting go, shows the strip above; a short swipe up, the strip below. That is with natural direction, which is on by default; without it, it is the other way around. The long swipes do what they always did: up, full width, and down, the overview. If you prefer the old gesture, choose **Changes the width** in Settings → Trackpad & Mouse → **Swiping up or down**. The details are in [chapter 10](#10-mouse-and-trackpad).

**With the keyboard.**

| Shortcut | What it does |
|---|---|
| ⌃⌥⌘↑ / ⌃⌥⌘↓ | Go to the strip above / below |
| ⌃⌥⌘⇧↑ / ⌃⌥⌘⇧↓ | Send the focused window to the strip above / below and follow it |

They act on the strip of the focused window or, if no window is focused, on the strip of the display under the pointer. They are in Settings → Shortcuts, in the **Navigate** group, and you change them like any other. Rectangle uses ⌃⌥⌘ only with ← and →, so they do not clash. They are also automation actions (`strip-up`, `strip-down`, `send-strip-up` and `send-strip-down`), so they work with the `rambla` command, with links and with Raycast ([chapter 15](#15-automation)).

**From the overview**, as explained below.

When you switch strips, a panel with all the strips of the display shows up for a moment ([chapter 13](#13-visual-aids)).

While it switches, a frosted-glass veil crosses the screen and hides the jump of the windows. It comes down from above when you go to the strip above, and up from below when you go to the strip below. It follows **Animations** and **Speed** in Settings → General: with animations off there is no veil, and with macOS's **Reduce motion** it fades in and out without moving.

### Sending windows to another strip

- With **⌃⌥⌘⇧↑ / ⌃⌥⌘⇧↓**, the focused window (on its own, not its whole column) goes to the strip above or below. It lands next to that strip's focused column, with its width, and you go with it. If you send it up from the highest strip, a new strip is created, unless it is that strip's only window: then nothing happens.
- From the overview you can send whole columns, with their stack or tabs (below).
- If the strip it came from ends up empty, the rules above apply.

### Focus from outside

Rambla does not leave you typing into a window you cannot see, and it does not change your strip because of something macOS did on its own. This is how it behaves when the focus comes from outside:

- **You choose a window of another strip** (from the Window menu, with ⌘`, in Mission Control, or by bringing it back from the Dock): Rambla goes to that strip and shows it. Mission Control has one exception (see [Limits](#limits)).
- **You reach an app with ⌘Tab, the Dock or a notification:** it works like macOS's own desktops. If the app has windows on the strip you see, you stay on that strip and Rambla focuses the last of those windows you used. If they are all on another strip, it goes to that strip.
- **macOS moves the focus by itself,** because you closed or minimized a window, or hid or quit an app: Rambla does not change strips. It focuses the last window you used, on the strip you see, of the app macOS handed the focus to; if there is none, the last of any app. If the strip ended up empty, Rambla takes the keyboard, as on an empty strip.
- **A new window opens:** it joins the strip you see on the display where it appears, even if its app has windows on another strip.

### The overview with several strips

With more than one strip, **⌃⌘O** (or a long swipe down) shows **one row per strip** of the display, the highest on top. Each row is like the usual overview. The bar for what is on screen shows only on the strip you see, and the rows shrink to fit. A strip without windows is an **Empty** card that cannot be chosen. With a single strip, it looks as it always did.

- **Choosing** a window of another row (with a click, or with the arrows and ↩) takes you to that strip and focuses it.
- **↑ and ↓** go through the windows of a stack and, past its edge, to the row above or below. The shortcuts that change strips (⌃⌥⌘↑ / ⌃⌥⌘↓) and a short swipe up or down take the selection straight to the row above or below, without going through the stack. They do not change the strip behind.
- **To send a column to another strip**, with its stack or tabs: drag it to another row, or choose it and press **⇧↑ / ⇧↓** (⌃⌥⌘⇧↑ / ⌃⌥⌘⇧↓ too). It lands after that strip's focused column, or where you drop it if you dragged it. From the highest strip, ⇧↑ sends it to a new strip above.
- **New strip.** While you drag a column, a **New strip** row appears on top: drop it there and a strip is created with that column. It is not offered for the only column of the top strip, neither when dragging nor with ⇧↑. If the top strip is empty, just drop it there.

### An empty strip

When you reach an empty strip:

- The **Empty strip** hint shows up for a moment. It says you can open anything there, how to bring a window from the nearest strip that has some and how to go back to it. To go back it names the shortcut, and the swipe only when the trackpad's swipe switches strips: with the trackpad and its **Swipes up and down** on, and **Switches strips** chosen. It names the shortcuts you have set, and if one is unassigned, that part is left out; with neither a shortcut nor the swipe, it does not say how to go back. It shows even if the strip indicator is off.
- Rambla **keeps the keyboard**, showing nothing. That way, what you type does not reach a window you cannot see. As soon as you open an app or choose a window, the keyboard goes back to it.
- If that strip is the highest one and you leave it, it goes away.

### Floating windows

- The ones that float because of an **app rule** (a calculator or a small chat, say), **dialogs**, **panels**, windows that **cannot be resized**, **Picture in Picture** and **Quick Look** do not belong to any strip: they are seen on all of them.
- The ones that float because of **⌃⌘T**, and the ones Rambla left floating because another app moved them (Rectangle), **go with the strip of their display**. When you switch, they are parked with the strip you leave, and they come back to their place when you return to it.
- With one of those floating windows focused, **⌃⌥⌘⇧↑ / ⌃⌥⌘⇧↓** takes it along with you: the strip changes and it stays in view.
- **Rearrange Windows** puts the ones Rambla left floating back on the strip they came from, not the one you are looking at.
- If Rambla restarts or pauses, or you use **Bring All Windows on Screen**, the ones that were parked with a strip come back to their place, in view. From then on they are part of the strip you see.

### Displays and restarts

- **Every display and every desktop (Space) has its own strips** and its own strip in view. When you return to a desktop, you see the strip you left.
- **Displays do not change together.** The short swipe acts on the display under the pointer, and the shortcuts on the strip of the focused window (or of the display under the pointer, if no window is focused). Full width still acts on the focused column, wherever the pointer is.
- **A window that changes display or desktop** goes to the strip in view there. That happens if you send it with ⌃⌘N, drag it to another display or move it to another desktop from Mission Control.
- **If you unplug a display** (or close the Mac's lid), each of its strips joins the one in the same place, counting from the bottom, on the display where macOS puts the windows. If that strip does not exist, it is created. The ones not in view are parked. **When you plug it back in,** each strip gets its windows back and the display shows the strip it had. If the window you were typing in ends up on a strip you do not see, the keyboard goes to a window in view.
- **When Rambla or the Mac restarts,** the strips are put back together, each window on its own, and each display shows the one it had in view. The rest are parked. The strips of an unplugged display or of a desktop you have not visited are kept for up to a month, as always.
- **When you quit Rambla or pause it,** the windows of all the strips come back into view, so none is lost. When you open it again or resume it, each one goes back to its strip.

### Limits

- **Mission Control and App Exposé show the windows of every strip**, because they are on the same desktop. Choosing one there takes you to its strip.
- **One exception in Mission Control:** if you choose the window of an app that was not in front and that app also has windows on the strip you see, Rambla takes it as a ⌘Tab. You stay on this strip, with the last window of that app you used here. To go to the other strip, use a swipe, a shortcut or the overview.
- **With a display that has another on each side** (the middle one of three in a row) there is no free edge to park at. The windows of the other strips sit on the neighbor display on the nearer side. Parked columns already had this limit. With two displays it does not happen.
- **Dialogs and panels are seen on every strip**: they belong to none.
- **When you unplug a display,** the windows of its strips you do not see can show on the remaining display for up to 15 seconds (2 with the Mac's lid closed). Then they join their strip and, if it is not the one in view, they are parked.

## 13. Visual aids

- **Strip indicator**: when you navigate with shortcuts or swipe, a frosted bar appears at the bottom with one icon per column. It highlights the focused one and marks the visible ones. It stays while you hold ⌃⌘. Click an icon to go to that column or drag it to reorder. It can be turned off in Settings → Appearance.
- **Strips panel**: when you switch strips, a frosted panel shows up for a moment at the bottom with a row per strip of the display, the highest on top. Each row shows the icons of the apps of its columns; the strip you see is highlighted, and a strip without windows says "Empty". It does not show if there is a single strip, and it is turned off with the strip indicator.
- **Empty strip hint**: when you reach a strip without windows, it says how to bring one and how to go back (see [chapter 12](#12-stacked-strips)). It shows even if the strip indicator is off.
- **Focus border**: a colored border around the focused window. Off by default. Color and width are set in Appearance.
- **Dim inactive windows**: slightly darkens everything except the focused window. Off by default. The intensity is set in Appearance.

## 14. Settings

Open them from the menu bar icon → **Settings…**. While the window is open, Rambla shows up in the Dock.

| Section | What it is for |
|---|---|
| **General** | Enable or pause, launch at login, animations and their speed, centering, width of new windows, keep original height, gaps between windows and margin, preset widths, adjustment step, what to do when another app moves a window |
| **Shortcuts** | Change any shortcut (each action takes two). Click the shortcut and press the new combination: ⎋ cancels and ⌫ clears it. It warns you if it clashes with Rectangle or if macOS doesn't allow it. **Restore Defaults** brings everything back. |
| **Trackpad & Mouse** | The trackpad gesture (fingers, sensitivity, natural direction, the swipes up and down and whether they switch strips or change the width, haptic feedback), conflicts with macOS, the mouse wheel and the mouse buttons |
| **Appearance** | Strip indicator (and the strips panel), focus border, dim inactive windows, mouse ↔ focus |
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

## 15. Automation

Every action has a short name, for example `focus-left`, `cycle-width`, `focus-3`, `pin-left` or `toggle-pause`. `rambla list` prints them all.

**Links:**

```sh
open -g "rambla://focus-left"
open -g "rambla://cycle-width"
```

Links run every action except `close-window`: any web page can open a link, so none can close your windows. That action runs only from the `rambla` command and from its Raycast script.

**Terminal:** install the command in Settings → Automation → **Install `rambla` Command**.

```sh
rambla focus-right
rambla toggle-pause
rambla list
```

**Raycast:** in Settings → Automation → **Export Raycast Scripts…** choose a folder and add it in Raycast (Settings → Extensions → Script Commands → Add Directories). You get one command per action, for example "Rambla: Cycle width".

The links also work in Apple Shortcuts, Alfred, Keyboard Maestro, BetterTouchTool or any tool that can open a URL.

## 16. Common problems

**I see a thin line at the edge of the screen.** Those are parked windows: macOS does not let a window hide completely, so Rambla leaves 1 point visible. Click there and the strip slides to that window. If it belongs to a stacked strip you do not see, what "Focus from outside" says in [chapter 12](#12-stacked-strips) applies.

**I lost a window.** If you use stacked strips, it may be on another strip: the overview (**⌃⌘O**) shows them all. If not, Rambla's menu → **Bring All Windows on Screen**. Rambla also brings them back when it quits or pauses.

**Mission Control shows windows I do not see on the screen.** Those are the ones of the other stacked strips, which are still on the same desktop. See the limits in [chapter 12](#12-stacked-strips).

**A window is not on the strip.** Rambla leaves dialogs, panels and windows that cannot be resized floating. If it is a normal window, check whether you took it out with ⌃⌘T or with Rectangle (in that case, ⌃⌘T puts it back) and whether it has a **Float** rule in Settings → Apps.

**A window left the strip by itself.** Another app moved it (Rectangle, a double-click on the title bar, the green button with ⌥). That is on purpose: Rambla does not fight other apps. Put it back with ⌃⌘T.

**Swiping on the trackpad switches desktops.** macOS uses the same gesture, even when System Settings says three fingers: see [section 10](#10-mouse-and-trackpad).

**A shortcut does nothing.** Another app may already use it. Check Settings → Shortcuts, which flags the ones macOS did not let Rambla register, and pick another one.

**Rambla asks for the Accessibility permission again.** In System Settings → Privacy & Security → Accessibility, remove Rambla with "−" and add it again from Applications.

**Something looks wrong.** Try **Rearrange Windows**. If it persists, **Show Log** shows what happened; that information helps when reporting the problem on [GitHub](https://github.com/Coru29/rambla/issues).

## 17. Uninstall

1. Rambla's menu → **Quit Rambla**. Every window comes back on screen.
2. Delete **Rambla** from Applications.
3. In System Settings → Privacy & Security → Accessibility, remove Rambla with "−".
4. To leave nothing behind, also delete:

   ```sh
   rm -rf ~/Library/Application\ Support/Rambla ~/Library/Logs/Rambla
   defaults delete io.github.coru29.Rambla
   sudo rm -f /usr/local/bin/rambla   # only if you installed the command
   ```
