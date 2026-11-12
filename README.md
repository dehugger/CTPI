# Coffee's Touchpad Improvements (CTPI)

**Play World of Warcraft: Forever comfortably on a trackpad.** CTPI keeps the
camera in always-on mouselook, like an action-camera game: you steer by moving
your fingers, aim with the middle of the screen, and click whatever you're
looking at. Everything around that is built to keep you from ever needing to
unlock the cursor: context-aware clicks, a radial spell menu, keyboard quest
dialogs, and a small HUD at the aim point.

Built for **WoW: Forever** (interface `16001`). Works on any input device, but
designed around a MacBook trackpad.

Author: **coffeeofdoom**
License: [MIT](LICENSE)

---

## Features

**Camera and cursor**
- Always-on mouselook. The cursor frees itself whenever you open a window,
  type, drag something or place a ground spell, then locks again.
- Detects when the game window is in the background or minimized and lets go
  of the cursor.
- Optional over-the-shoulder camera (always, on your free-cursor key, or while
  a target is locked).

**Clicking**
- Look at things to target them (soft targeting for enemies, friendlies and
  interactables).
- Left / right click can each be Interact, Hold to run, Autorun or nothing.
- **Click to lock:** left-clicking an enemy locks it as your target and starts
  your attack: auto attack, Auto Shot, or a spell you choose (casters).
- **Hard lock:** in combat your target sticks while you look around;
  right-click unlocks. Corpses under the reticle still loot, even mid-fight.
- **Healers:** optionally, in combat, left-clicking a friendly casts your heal.
- **Rogues:** in stealth, a click picks pockets on humanoids you haven't robbed
  yet and opens with Ambush otherwise (Shift: Sap / Garrote). Clicks never break
  stealth with auto attack.
- **Druids:** clicks cast in caster form and attack in cat / bear.

**Radial menu**
- Hold **Shift** (or Ctrl / Alt) while the camera is locked and a sectioned
  ring of spells opens around your cursor. Slide into a section and click.
  Works in combat.
- Different rings by context, set up per class: e.g. a stealth ring and a
  combat ring for rogues, one per form for druids. Fully editable.

**HUD at the aim point**
- Reticle (dot / cross / ticks).
- Look-at label: the name of what you're looking at, colored by type, with
  icons for what a click will do.
- Dotted arcs: your resource (energy / rage / mana), the GCD and your casts /
  channels, and combo points as an inner ring.

**Quality of life**
- Quest and gossip dialogs by keyboard (arrows, space, 1-9) without unlocking.
- Optional interact key (loot / talk from the keyboard, in combat too).
- Quick toggles menu from the minimap button, the minimap addon dropdown, or a
  keybind.
- Guided setup on first login.

---

## Install

**CurseForge / Wago app:** install as usual.

**Manually:** download **`CTPI-<version>.zip`** from the
[latest release](https://github.com/dehugger/CTPI/releases/latest) and unzip it
into `World of Warcraft/_forever_/Interface/AddOns/`. The zip contains a folder
named `CTPI`, so you end up with `AddOns/CTPI/CTPI.toc`. Fully restart the game.

> Don't use GitHub's green **Code > Download ZIP** button: it names the folder
> `CTPI-main`, and WoW needs the folder to be named exactly `CTPI`.

The setup opens on your first login. Run it again any time with `/ctpi setup`.

---

## Using it

| Input | Does |
|---|---|
| Move fingers | Turn the camera |
| Left click | Interact with what you're looking at, or lock + attack an enemy |
| Right click | Autorun by default; **unlocks** your target while hard-locked in combat |
| Hold Shift | Radial spell menu |
| Shift-Tab | Lock the looked-at enemy as your target |
| Ctrl-Tab | Set focus |
| In NPC dialogs | Up / Down select, Right / Space / Enter choose, Left back, 1-9 pick, Esc close |

Keybinds (Key Bindings > AddOns > Coffee's Touchpad Improvements): master
toggle, free cursor, quick menu. The setup can set these for you.

### Settings

- `/ctpi` opens the settings: Reticle, Label, HUD, Camera, Behavior and Class
  tabs. Changes preview live while the window is open.
- The **quick menu** (minimap button, its keybind, or `/ctpi menu`) flips the
  common switches.
- The **Class** tab sets what a click does for your class and edits the radial
  rings. Ring conditions are macro conditions (`[stealth]`, `[combat]`, ...)
  plus druid form names: `[{cat}]`, `[{bear}]`, `[{moonkin}]`, `[{travel}]`.

### Slash commands

```
/ctpi                     settings
/ctpi setup               guided setup
/ctpi menu                quick toggles
/ctpi toggle              master on / off
/ctpi radial              radial menu on / off
/ctpi left|right <interact|run|autorun|none>
/ctpi leftenemy <interact|lock|lockattack>
/ctpi shoulder [off|always|cursor|target]
/ctpi lockkey|focuskey|clearfocuskey|interactkey <KEY|none>
/ctpi softenemy|softfriend|softinteract
/ctpi questkeys           quest / gossip keys on / off
/ctpi focusunlock         free the cursor when the window loses focus
/ctpi minimap             show / hide the minimap button
/ctpi block|unblock <FrameName>
/ctpi why                 explain what the cursor and clicks are doing
/ctpi debug               chat messages for every lock / free change
/ctpi reset               restore defaults
```

---

## How it works, and its limits

WoW protects movement, targeting and casting from addons, so CTPI only ever
uses the sanctioned routes:

- **Mouse buttons** are bound to native actions or to secure macro buttons.
  That's why one button can't do "tap to interact, hold to run": a binding does
  one thing.
- **In combat, bindings can't change** from addon code. CTPI uses a secure
  state driver (the same system the default action bars use for stance
  paging) to switch left-click between lock / attack, loot and heal mid-fight.
  It reacts to game state (dead, friendly, hostile, combat, stealth, forms,
  modifiers), never to addon logic like health or cooldowns.
- **Out of combat** CTPI can look at anything: that's how the rogue stealth
  click tells humanoids from beasts and remembers who you've already robbed.
- **Secret values:** in combat Forever hides some unit data from addons. The
  HUD arcs are built from status bars the game fills directly, and the label
  only displays names, so nothing breaks when values go secret.
- **Game settings CTPI changes**, and puts back: the background frame rate cap
  (set to 8 so focus loss is detectable) and the hidden over-the-shoulder
  camera setting.
  Your own values are restored on logout or when you turn the feature off.

**Known limits**
- In-combat looting, right-click unlock and the healer click need the client's
  secure snippets. `/ctpi why` reports whether they work on your build; without
  them CTPI falls back to simpler behavior (left-click keeps your target in
  combat, Esc clears it).
- Spell names in class presets are English; on other client languages, edit
  them on the Class tab.
- Focus-loss detection only works in windowed / borderless mode.

---

## Feedback

Bug reports and ideas: [GitHub issues](https://github.com/dehugger/CTPI/issues).
Please include what `/ctpi why` prints. See [CHANGELOG.md](CHANGELOG.md) for
version history.
