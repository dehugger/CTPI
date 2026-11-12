# Changelog

## 3.0.1

- **Cursor no longer jumps up and to the left.** 3.0.0 turned on the game's
  CursorFreelookCentering to bring the cursor to the radial ring; on high-DPI
  screens it parks the cursor off-center instead. The setting is left alone
  now (any value 3.0.0 changed is put back), and the radial ring opens
  wherever the cursor actually is, kept clear of the screen edges.
- **Left-click works again with CTPI toggled off.** The 3.0.0 setup turned off
  the game's Interact on Left Click, which is what left-click does when CTPI
  is off. It's no longer in the setup, and it's turned back on once for
  anyone the 3.0.0 setup changed.
- **Pick Pocket no longer changes your target:** the stealth click casts it
  straight on whatever's under the reticle. Shift-click Sap still targets the
  mob. Robbed mobs are remembered by who you clicked, not your target.
- **Cursor return setting** (quick menu, `/ctpi cursor game|stay|center`):
  where the cursor reappears when the camera lets go. `/ctpi why` now shows
  where it last appeared and the game's cursor-centering settings.

## 3.0.0

**New**
- **Radial menu:** hold Shift (or Ctrl / Alt) for a ring of spells around the
  aim point; the camera lets go, the cursor appears in the middle, click a
  spell. Works in combat. Rings are per class and switch by context, e.g.
  stealth vs combat for rogues and one per form for druids. Edit them on the
  new **Class** tab (spell names or full /macro lines, macro conditions plus
  `{cat}` / `{bear}` / `{moonkin}` / `{travel}` form tokens).
- **Class profiles:** what a lock + attack click does is now per class: auto
  attack, Auto Shot, a spell of your choice (casters), or druid by form
  (cast in caster / moonkin, attack in cat / bear).
- **Healer click:** optionally, in combat, left-clicking a friendly casts your
  heal (Class tab).
- **Casts on the GCD arc:** your casts fill it (gold) and channels drain it
  (teal).
- **Guided setup:** a six-step setup on first login (and once after this
  update): recommended game settings, play style, mouse buttons, camera and
  HUD, and keybinds you set by pressing them. `/ctpi setup` reruns it.
- The quick menu gets radial, cast arc and "Run setup" entries.

**Fixed**
- Rogue stealth click didn't switch to Pick Pocket / Ambush: stealth is now
  detected several ways (including Classic-style stealth stances), and
  `/ctpi why` shows what CTPI sees.
- A startup error (the look-at label's layout ran before a helper existed)
  silently stopped part of the login setup: the target lock / focus keys
  weren't bound until after your first fight.

**For CurseForge**
- `.pkgmeta` for the BigWigs packager; TOC category and notes.
- README rewritten as the project description.

## 2.3.0

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
- **Context-aware enemy click** (lock + attack mode): the click is rewritten
  out of combat to fit the situation. Rogues in stealth: Pick Pocket on a
  humanoid you haven't robbed yet (Shift: Sap), otherwise Ambush (Shift:
  Garrote); also Ambush / Garrote when stealthed in combat after Vanish.
  Auto attack never fires while stealthed. The look-at label shows the
  spells. Toggle under Behavior.
- Enemy clicks now target exactly what's under the reticle first, then the
  soft enemy.
- **Quick toggles menu** (`QuickMenu.lua`): a compact click-to-flip list
  of the common switches (enabled, free cursor, left-click on enemies, hard
  lock, rogue openers, shoulder camera, label, HUD pieces, look to target,
  focus unlock, debug). Open it from the new minimap button (left-click;
  right-click opens all settings; drag to move), the minimap addon dropdown,
  a keybind ("Toggle CTPI quick menu"), or `/ctpi menu`. `/ctpi minimap`
  shows / hides the button.
- **Hard lock** (Behavior, on by default): in combat with a live hostile
  target, left-click acts on that target instead of retargeting to whatever
  is under the reticle (corpses still loot), and right-click becomes
  "unlock" (clears the target). Releases on its own when the target dies or
  combat ends. Uses the secure aim header; without it, the in-combat click
  just keeps an existing hostile target.
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
