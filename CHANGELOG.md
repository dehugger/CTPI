# Changelog

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
