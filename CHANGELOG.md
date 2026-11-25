# Changelog

## 3.1.0

- **Combo lock:** in combat, with a live hostile target, nothing under the
  reticle can take your target away: not another mob, not a corpse, not a
  party member walking through your crosshair. Left-click acts on the target
  you have. Combo points live on the target, so this is what keeps them.
  Auto (default) turns it on for rogues and druids in cat form; it can be on
  for everyone or off (Behavior tab, quick menu). When the target dies the
  lock lets go, so looting mid-fight still works.
- **Two-tap unlock:** unlocking a locked target takes two right-clicks in a
  row (a left-click in between cancels it), so a stray right-click can't drop
  your target. The label shows "Right-click again to unlock" after the first.
  One-click unlock is a checkbox away.
- `/ctpi why` shows the combo lock and the aim driver's current state.
- **Cast on what you look at** (Class tab, `/ctpi reticle`): list spells
  like Kick, Gouge, Blind, Sap and CTPI writes a macro for each that casts on
  whatever's under the reticle without changing your target (falls back to
  your target when you're looking at nothing), then swaps those macros onto
  your bars where the plain spells were. Builders and finishers stay on your
  target, so combo points stay put. "Spells back" / `/ctpi reticle undo`
  reverses the swap. Defaults per class (interrupts and CC).
- **Ground spells at the crosshair** (Class tab "Ground" list, rogue default
  Distract): "Put on my bars" also swaps in `/cast [@cursor]` macros for
  these, and while the camera is locked CTPI keeps the game's cursor
  centering on, so the hidden cursor sits on the crosshair and the spell
  lands where you're looking, no placing. Your own centering settings come
  back when the camera lets go and on logout. Ground spells not on the list
  still free the cursor to place them by hand.
- **Flip camera 180** as a click choice (left, right, Shift-click,
  Shift-right-click), using the game's own Flip Camera.
- **Tab lock / unlock** (Behavior tab, quick menu, `/ctpi tab`, off by
  default): your Target Nearest Enemy key unlocks a locked target, and
  otherwise targets what's under the reticle (or the nearest enemy when
  you're looking at nothing). It flips mid-combat along with the lock.
- **Switching apps:** coming back no longer re-grabs the mouse on frame rate
  alone (it could grab it while another app was still in front). The camera
  re-locks once you click or press a movement key in the game window.
- **Shift-click and Shift-right-click actions** (Behavior tab, quick menu):
  each can be Default (your normal click with Shift held, which rogue
  Sap / Garrote rely on), Interact, Hold run, Autorun, Free cursor (same as
  the free-cursor key; a Shift-click in the world locks the camera again),
  Clear target (one press), Target look (targets what's under the
  reticle), or Radial.
- **Shift-click to open the radial:** set either one to Radial and a
  shift-click opens the ring instead of holding the modifier. Let go without
  moving and it stays open until a click picks a section; right-click or a click in the middle closes
  it. Or flick it: hold the shift-click, move toward a section, and let go
  to cast it. The cursor is hidden while a ring is open, so the pointer from the
  ring's center works like a thumbstick ("Hide cursor" on the Class tab).
  With any Shift-click action set, holding Shift no longer opens the ring (it
  would swallow the Shift-click); use Shift-click: Radial, or Ctrl / Alt as
  the hold key.
- **Debug window** (`/ctpi debug`, quick menu, Behavior tab): replaces the
  chat messages. The top half is a live readout (cursor locked or free and
  why, focus and fps, combat, target, combo points, what's under the
  reticle, what left- and right-click are bound to right now, the aim
  driver's state, combo / hard lock, the radial). The bottom half logs every
  change with a timestamp: cursor lock / free, binding swaps, target swaps,
  which CTPI button a click fired, combat, focus lost / back, the radial.
  Copy puts the state and log in a box to Cmd-C. It doesn't free the cursor,
  and it reopens after a /reload if it was open.

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
- **Console-style radial:** the radial is now a sectioned ring around the
  reticle, bigger by default. The direction you move picks the section (it
  lights up, with a pointer showing your direction) and any click casts it;
  not moving picks nothing. Works the same wherever the cursor shows up, and
  in combat (a secure click handler reads the direction).
- **Radial only while the camera is locked:** it no longer opens while you're
  typing, in free-cursor mode, with a window open, or with CTPI off.
- **Faster, steadier background detection:** measures each frame instead of
  the game's one-second fps average. Lets go of the cursor about half a second
  after the window goes to the background, re-locks a quarter second after
  you're back, and a single long frame (a hitch) can't trip it.
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
