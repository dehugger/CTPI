# Coffee's Touchpad Improvements (CTPI)

A World of Warcraft addon for playing on a **trackpad**. CTPI keeps the camera
in always-on mouselook (like Guild Wars 2's Action Camera), so you steer by
just moving your fingers, aim with a center-screen reticle, and click to
interact. It adds a minimal HUD around the aim point, an over-the-shoulder
camera, and keyboard control for quest and gossip windows so you rarely have
to unlock the cursor at all.

Built for **WoW: Forever** (client 1.60.x, interface `16001`).
Originally written for TBC Classic Anniversary (2.5.x).

Author: **coffeeofdoom**

---

## Features

- **Always-on mouselook.** The camera follows the trackpad, no holding a
  button. The cursor frees itself automatically when you open a window, type
  in chat, place a ground spell or drag something, then re-locks.
- **Look to target.** Whatever is at screen center is soft-targeted: enemies,
  friendlies (optional, for healers) and interactables (NPCs, nodes,
  mailboxes, corpses).
- **Configurable mouse buttons.** Left and right click can each be Interact,
  Hold to run, Autorun or nothing. While you're autorunning, left-click (when
  it's on Interact) cancels the autorun.
- **Click to lock (great for ranged).** Optionally, left-clicking an enemy
  locks it as your hard target, or locks it and starts attacking (Auto Shot
  on hunters), so your target stays put while you look around.
- **Look-at label.** A short label under the aim point with the name of what
  you're looking at, colored by type (red enemy, green friendly, gold
  interactable), plus icons for what clicking will do and your target-lock
  key. Adjustable text size and backdrop. The full game tooltip is available
  as an alternative.
- **HUD arcs.** A dotted resource arc (energy / rage / mana), a matching GCD
  arc that drains over each global cooldown, and combo points as an inner
  ring. Sides, radius, ring spacing and position are all adjustable. Works
  with or without the reticle.
- **Reticle.** Dot, cross or ticks, any size, color and opacity.
- **Over-the-shoulder camera.** Slides the camera sideways so your character
  isn't standing on the aim point. Off, always, follows your manual cursor
  toggle, or follows your target lock.
- **Quest / gossip keys.** NPC dialogs stay locked and show a numbered list:
  up/down to select, right / space / enter to choose, left to back out, 1-9
  to pick directly.
- **Target tools.** Lock the looked-at mob as your hard target, set or clear
  focus, all from the keyboard.
- **Quick toggles.** A minimap button (and minimap addon dropdown entry) with
  a click-to-flip menu of the switches you change mid-play.

---

## Install

1. Download **`CTPI-<version>.zip`** from the
   [latest release](https://github.com/dehugger/CTPI/releases/latest).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`. The zip
   already contains a folder named `CTPI`, so you end up with
   `AddOns/CTPI/CTPI.toc`.
3. Fully restart the game (a `/reload` doesn't pick up a newly added addon).
4. Type `/ctpi` to open the settings.

> **Don't use the green Code > Download ZIP button.** GitHub names that
> folder `CTPI-main`, and WoW needs the folder to be named exactly `CTPI`
> (the wrong name can even stop the launcher from starting the game). If you
> already did, rename the folder to `CTPI`.

---

## Recommended settings outside the addon

| Where | Setting | Value | Why |
|---|---|---|---|
| macOS > Trackpad > Point & Click | Secondary click | **Click or tap with two fingers** | Gives you a real right-click for CTPI to bind. |
| WoW > Options > Mouse | Mouse Look Speed | ~5.5, to taste | The actual camera sensitivity while mouselooking. |
| WoW > Options > Mouse | Click-to-Move | **Off** | So a stray click doesn't walk you somewhere. |
| WoW > Options > Mouse | Interact on Left Click | **Off** | CTPI handles interacting itself. The built-in one doesn't interact while the camera is locked. |
| WoW > Options > Combat | Sticky Targeting | **On** | Keeps a locked target until you pick another. |

---

## Default controls

| Input | Does |
|---|---|
| Move fingers | Turn the camera |
| Left click | Interact with what you're looking at (attack / talk / loot / use) |
| Left click on an enemy (optional) | Lock it as your target, or lock + attack |
| Left click while autorunning | Stop autorunning (out of combat) |
| Right click | Toggle autorun |
| Shift-Tab | Lock the looked-at enemy as your target |
| Ctrl-Tab | Set focus (your hostile target, else the looked-at mob) |
| In NPC dialogs | Up/Down select, Right/Space/Enter choose, Left back, 1-9 pick, Esc close |

Optional keybinds under **Key Bindings > AddOns > Coffee's Touchpad Improvements**:

- **Toggle CTPI (master)**: turn everything on or off
- **Toggle free cursor (CTPI)**: free the cursor to click on UI. Also drives
  the shoulder camera's "Cursor key" mode.
- **Toggle CTPI quick menu**: open the quick toggles (frees the cursor while
  it's open). Also on the minimap button and `/ctpi menu`.

---

## Settings (`/ctpi`)

The settings window has five tabs and previews changes live while it's open.

- **Reticle:** show/hide, shape, size, opacity, color, position.
- **Label:** compact label / full tooltip / off, position, text size, click
  hint style (icons + words, icons, text), dark backdrop.
- **HUD:** GCD (arc or swipe on the reticle, side, empty track in combat),
  resource arc (side, radius, hide when idle), combo points (inner ring, row
  above, off), arc group offset and ring gap.
- **Camera:** shoulder camera mode and offset, switch shoulder.
- **Behavior:** left/right click actions, left-click on enemies (interact /
  lock / lock + attack), left-click stops autorun, look to target toggles, cursor unlock on focus loss, quest/gossip keys, debug
  messages.

---

## Slash commands

```
/ctpi                       open settings
/ctpi menu                  quick toggles menu
/ctpi minimap               show / hide the minimap button
/ctpi toggle                master on/off
/ctpi left <interact|run|autorun|none>
/ctpi right <interact|run|autorun|none>
/ctpi leftenemy <interact|lock|lockattack>   what left-click does to enemies
/ctpi softenemy             toggle look-to-target enemies
/ctpi softfriend            toggle look-to-heal friendlies
/ctpi softinteract          toggle look-to-interact (npcs, nodes, mailboxes)
/ctpi shoulder [off|always|cursor|target]   shoulder camera (no arg cycles)
/ctpi questkeys             toggle quest / gossip keys
/ctpi lockkey <KEY|none>    target lock key (default SHIFT-TAB)
/ctpi focuskey <KEY|none>   set focus key (default CTRL-TAB)
/ctpi clearfocuskey <KEY|none>
/ctpi focusunlock           toggle freeing the cursor when the window loses focus
/ctpi focusfps <n>          focus-loss fps threshold (0 = auto)
/ctpi block <FrameName>     also free the cursor while this frame is open
/ctpi unblock <FrameName>
/ctpi why                   explain why the cursor is (or isn't) locked
/ctpi debug                 print every lock/free change and what's being looked at
/ctpi reset                 restore defaults
```

---

## How it works, and its limits

- **Mouselook** is driven by a small loop using `MouselookStart` /
  `MouselookStop`, which aren't protected, so the camera logic works in combat.
  Under mouselook the cursor sits at screen center, which is where
  `INTERACTMOUSEOVER` and soft-targeting aim.
- **Mouse buttons** are bound with `SetOverrideBinding` to native actions
  (`INTERACTMOUSEOVER`, `MOVEFORWARD`, `TOGGLEAUTORUN`). Movement and
  interacting are protected, so an addon can only trigger them through native
  bindings. That's also why **one button can't do tap-to-interact and
  hold-to-run** at the same time.
- **Bindings can't change in combat.** Click actions, quest keys and the
  autorun cancel are set up out of combat, and anything that would leave a
  key in a weird state is handed back the moment combat starts.
- **Secret values.** Forever uses Midnight-era addon rules, where some unit
  data (names, health, power, sometimes whether a unit exists) is hidden from
  addons in combat. CTPI never branches on those values: the HUD arcs are
  built from tiny status bars that the game fills directly, and the label only
  displays names, never compares them.
- **Shoulder camera** uses the client's hidden `test_cameraOverShoulder`
  setting. The game may show a warning about experimental camera features.
  CTPI resets it on logout.

---

## Status

Tested in game on Forever: loading, mouselook and cursor freeing, the settings
window, the HUD arcs and combo ring, hold-to-run on the mouse buttons, and
left-click lock + attack.

Not yet confirmed in game: quest/gossip keys, the shoulder camera, the
autorun cancel, the click hint icons, and behavior with secret values in
combat. Bug reports welcome as issues, ideally with the output of `/ctpi why`
or `/ctpi debug`.

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

## License

[MIT](LICENSE)
