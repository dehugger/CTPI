# Changelog

## 2.2.1 (unreleased, testing)

- **Minimize / tab-out detection fixed:** the old check needed FPS below 20,
  but the game's background cap is around 30, so it never fired. CTPI now
  sets the background FPS cap to 8 while it runs (restored on logout or when
  the option is turned off) and treats a steady ~8 fps as "not in the window".
- **Less lag:** mouse bindings are applied as a diff instead of cleared and
  re-set (each change makes the default UI redraw every action button's
  keybind text), with a short hysteresis when the reticle leaves an enemy.
  The look-at label and HUD arcs only redraw when something changed.
- **Target lock fixes:** click bindings are put in place at combat start even
  if a window had the cursor free, the left-click binding never swaps while
  the button is held, and the lock key no longer clears your target when
  nothing hostile is under the reticle.
- **Looting with lock mode fixed:** what left-click does is now decided from
  exactly what's under the reticle (the mouseover unit), re-checked
  continuously instead of only on soft-target changes. Corpses and NPCs
  always get interact, so looting and skinning work without toggling the
  lock off. (A live mob next to a corpse used to win, and the choice could
  stay stuck on "enemy" after a kill.)
- **Loot in combat with lock mode:** a secure state driver re-points
  left-click while in combat (corpse / friendly under the reticle: interact;
  live enemy: lock / attack). Probed at login; falls back to the old
  behavior if the client's secure snippets don't work. `/ctpi why` shows
  which one is active.
- **Interact key** (`/ctpi interactkey <KEY>`): an optional keyboard interact
  that also works in combat, when left-click is in lock mode.

## 2.2.0

- **Left-click on enemies** (Behavior tab, `/ctpi leftenemy`): while left is
  Interact, clicking an enemy can **lock** it as your hard target, or **lock +
  attack** (hunters start Auto Shot, everyone else starts auto attack). Out of
  combat it only applies with an enemy under the reticle, so looting and
  talking still work; in combat left-click stays in enemy mode.
- The look-at label shows the lock / attack action on enemies.

## 2.1.0

- **Mouse buttons:** left and right click can each be Interact, Hold to run,
  Autorun or nothing (`/ctpi left|right ...`). Replaces the old "left-click
  interacts" checkbox; existing settings carry over.
- **Left-click stops autorun:** while autorunning with left on Interact, left
  is temporarily bound to move forward so a tap cancels the autorun (out of
  combat).
- **Quest / gossip keys** (`Dialog.lua`): NPC dialogs keep the camera locked
  and show a numbered list. Up/Down select, Right/Space/Enter choose, Left
  backs out, 1-9 pick directly. Keys only exist while a dialog is open and
  are handed back when combat starts.
- **GCD arc:** the GCD is now a dotted arc that drains over each global
  cooldown, by default mirroring the resource arc on the opposite side. The
  old swipe on the reticle is still available, and is used automatically if
  the GCD timing is ever secret.
- **Combo points as an inner ring** inside the resource arc (or the old row).
- **Ring stacking:** arcs on the same side stack as rings (GCD outside,
  resource middle, combo inside) with an adjustable gap.
- **Arc group offset:** X/Y offset for all arcs together, independent of the
  reticle. Resource and GCD arcs can also sit above.
- **Label readability:** text size slider, icon click hints (mouse button +
  cursor icon + lock icon), dark backdrop. Label settings moved to their own
  tab.

## 2.0.0

- Settings split into tabs.
- Look-at label replaces the tooltip by default (name colored by type plus a
  click hint). It reads only the soft-target tokens; the old `mouseover` and
  `target` fallbacks caused stale tooltips.
- GCD swipe and dotted resource arc around the aim point.
- Over-the-shoulder camera with off / always / cursor key / target lock modes.

## 1.9.0

- Ported to WoW: Forever (interface `16001`, modern API, Midnight-era addon
  rules): secret value handling, modern options panel registration, modern
  frame names for cursor freeing, `/ctpi why` and `/ctpi debug`.

## 1.8.0 and earlier

- TBC Classic Anniversary (2.5.x) versions, originally named FreeLook.
