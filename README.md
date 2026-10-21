<p align="center">
  <img src="Packaging/AppIcon-preview.png" width="160" alt="Rambla icon: sunset over the Rambla of Montevideo with a strip of windows">
</p>

<h1 align="center">Rambla</h1>

<p align="center">
  A free, open-source <b>scrolling window manager</b> for macOS.<br>
  Your windows line up along an endless horizontal promenade, like the <i>rambla</i> of Montevideo.
</p>

<p align="center"><a href="https://rambla-mac.vercel.app"><b>rambla-mac.vercel.app</b></a> · <a href="README.es.md">Leer en español</a> · <a href="docs/MANUAL.en.md">User manual</a></p>

---

Every window is a column on one horizontal strip that keeps going past the edges of your screen. Opening a window adds a column next to the one you are using **instead of shrinking everything else**, and the strip slides to show whatever you focus. It is the [niri](https://github.com/YaLTeR/niri) / PaperWM idea, built as a light native Mac app and inspired by the paid [ChainYourMac](https://chainyourmac.com).

> The interface is in Spanish for now. Translations are welcome.

## Features

- **One strip per display and per Space**, with spring animations and its own focus and scroll position.
- **New windows open beside the focused one**; the strip scrolls to the focused window (centering: never, only when it overflows, always).
- **Column widths**: presets (25/33/50/66/75 %), full width, wider/narrower, center, and **pin a column** to the left or right edge.
- **Stacks and tabs**: put several windows in one column, stacked vertically or as tabs with a clickable tab bar.
- **Trackpad**: a three- or four-finger swipe slides the strip and settles on the nearest column.
- **Strip indicator**: a frosted bar with one icon per column while you navigate; click a tile to jump, drag it to reorder.
- **Mouse**: drag a window onto another column to reorder; resize it to set the column width.
- **Focus border** and **dim inactive windows** (optional), focus follows mouse / mouse follows focus (optional).
- **Per-app rules** (tile or float, initial width, where new windows open) and per-display on/off.
- **Remembers the layout** across restarts; launch at login.
- **Plays well with [Rectangle](https://rectangleapp.com)**: default shortcuts use ⌃⌘, so they never clash with Rectangle's ⌃⌥, and if Rectangle (or any other app) moves a window, that window leaves the strip and stays where it was put. The Mac page of the settings lists any shortcut that collides with your Rectangle setup.
- **Automation**: `rambla://` URLs, a `rambla` command-line tool and Raycast script export.
- **Light**: native Swift (AppKit + SwiftUI settings), no Electron, no polling — about 0 % CPU and ~12 MB of memory when idle.

## Requirements

macOS 14 Sonoma or later on Apple silicon, and the Accessibility permission.

## Install

1. Download **[Rambla.dmg](https://github.com/Coru29/rambla/releases/latest/download/Rambla.dmg)** from [Releases](https://github.com/Coru29/rambla/releases) (or build it, below) and drag **Rambla** to Applications.
2. Open it and allow it in **System Settings → Privacy & Security → Accessibility**.
3. Rambla is not notarized by Apple. If macOS says it cannot verify the developer, right-click the app → **Open**, or run `xattr -dr com.apple.quarantine /Applications/Rambla.app`.

## Default shortcuts

All of them can be changed in **Settings → Atajos**.

| Shortcut | Action |
|---|---|
| ⌃⌘← / ⌃⌘→ (or ⌃⌘H / ⌃⌘L) | Focus the column to the left / right |
| ⌃⌘↑ / ⌃⌘↓ (or ⌃⌘K / ⌃⌘J) | Focus the window above / below in a stack |
| ⌃⌘A / ⌃⌘E | First / last column |
| ⌃⌘1 … ⌃⌘9 | Jump to column N |
| ⌃⌘⇧ + arrows (or H J K L) | Move the column / the window inside its stack |
| ⌃⌘N | Send the window to the next display |
| ⌃⌘R | Cycle preset widths |
| ⌃⌘M | Full width (again to restore) |
| ⌃⌘C | Center the column |
| ⌃⌘= / ⌃⌘- | Wider / narrower |
| ⌃⌘⇧= / ⌃⌘⇧- | Taller / shorter (in a stack) |
| ⌃⌘0 | Equalize heights |
| ⌃⌘P / ⌃⌘⇧P | Pin the column to the left / right edge |
| ⌃⌘[ / ⌃⌘] | Stack into the column on the left / right |
| ⌃⌘⇧[ / ⌃⌘⇧] | Pop out of the stack to the left / right |
| ⌃⌘⇧T | Toggle stack ⇄ tabs |
| ⌃⌘T | Float / put back in the strip |

## Trackpad

macOS also receives every swipe and Rambla cannot stop it. If you use the four-finger swipe (default), set **System Settings → Trackpad → More Gestures → Swipe between full-screen applications** to *Off* (switch desktops with ⌃← / ⌃→), or pick three fingers in Rambla and keep the system one on four. **Settings → Mac** tells you if they collide.

## Recommended macOS settings

Rambla checks these for you in **Settings → Mac**:

- **Displays have separate Spaces**: on (macOS default).
- **Automatically rearrange Spaces based on most recent use**: off.
- **Stage Manager** and **drag windows to screen edges to tile**: off.
- With two displays, placing the second one **above or below** the main one works best. Side by side works too: windows only slide halfway toward the other display before they are parked.

## Automation

```sh
open -g "rambla://focus-left"        # any action id, e.g. focus-3, cycle-width, toggle-pause
rambla focus-right                   # after Settings → Automatización → Install the `rambla` command
rambla list                          # all actions
```

Settings → Automatización can also export one Raycast script per action.

## Build from source

Only the Xcode **Command Line Tools** are needed (Swift 6); Xcode itself is not required.

```sh
git clone https://github.com/Coru29/rambla && cd rambla
scripts/test.sh        # unit tests (Swift Testing)
scripts/build.sh       # build/Rambla.app
scripts/dmg.sh         # build/Rambla.dmg
scripts/install.sh     # copy to /Applications and launch
scripts/e2e.sh         # live end-to-end checks with a throwaway test app (needs the Accessibility permission)
```

The first build creates a local self-signed code-signing identity in `.signing/` (never committed), so macOS keeps the Accessibility permission across rebuilds.

## How it works

- `RamblaCore` is a pure Swift library with the model (strips, columns), the layout engine, the strip operations, preferences and shortcut tables. It has no AppKit and is covered by unit tests.
- The app runs **one thread per managed app** for all Accessibility calls, so a frozen app never blocks the others. Everything is event-driven (AX notifications, workspace notifications, Carbon hot keys); the only timer runs while an animation is playing.
- macOS moves windows that are fully off screen back into view, so windows outside the visible part of the strip are **parked with 1 pt visible** at a screen edge. When Rambla quits or pauses, every parked window is brought back on screen.
- Private APIs are kept to the minimum that yabai and AeroSpace also use (window ids, Spaces, focusing an exact window), loaded at runtime so a missing symbol degrades instead of crashing. SIP stays on.

## Credits

Inspired by [niri](https://github.com/YaLTeR/niri), [PaperWM](https://github.com/paperwm/PaperWM), [PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon), [Paneru](https://github.com/karinushka/paneru) and [ChainYourMac](https://chainyourmac.com). Techniques learned from [yabai](https://github.com/koekeishiya/yabai), [AeroSpace](https://github.com/nikitabobko/AeroSpace) and [Rectangle](https://github.com/rxhanson/Rectangle).

## License

[MIT](LICENSE)
