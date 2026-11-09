local addonName, ns = ...

-- =====================================================================
-- CTPI / Secure.lua
-- Mouse-button bindings while mouselook is engaged. Mostly NATIVE action
-- bindings (SetOverrideBinding); the left-click-on-enemies option points
-- BUTTON1 at a secure macro button instead (SetOverrideBindingClick).
--
-- PERFORMANCE: every binding change fires UPDATE_BINDINGS, which makes the
-- default UI redraw the hotkey text on every action button. So bindings are
-- applied as a diff (only keys whose action actually changed are touched)
-- and never cleared + re-set wholesale.
--
--   LEFT  (BUTTON1) -> db.leftAction   (default INTERACTMOUSEOVER)
--   RIGHT (BUTTON2) -> db.rightAction  (default TOGGLEAUTORUN)
--   each one of:
--     INTERACTMOUSEOVER  interact with whatever the reticle is over
--                        (attack / npc / vendor / mailbox / corpse / node)
--     MOVEFORWARD        hold to run
--     TOGGLEAUTORUN      tap to run / tap to stop
--     ""                 nothing (game default for that button)
--     "NATIVE"           (left only, experimental) leave BUTTON1 unbound and
--                        turn on the game's own interactOnLeftClick, so the
--                        game handles it: tap interacts, hold runs (the
--                        game treats left-held-while-mouselooking as move)
--   one action per button: movement and interact are protected, so an
--   addon cant split a tap from a hold on the same button.
--
-- Both are bound only while mouselooking; cleared when the cursor frees
-- (dialog / panel) so normal UI clicking works.
--
-- HARD RULE: SetOverrideBinding* is out-of-combat only. Guarded by
-- InCombatLockdown(); re-synced on PLAYER_REGEN_ENABLED (Core.lua).
-- =====================================================================

local owner = CreateFrame("Frame", "CTPIBindingOwner", UIParent)
ns.secureOwner = owner

-- diff-based override bindings. bound[key] = "A:<ACTION>" | "C:<button>" | nil
local function makeBinder(ownerFrame)
  local bound = {}
  return function(key, kind, value)
    local desc = kind and (kind .. ":" .. value) or nil
    if bound[key] == desc then return end
    if not desc then
      SetOverrideBinding(ownerFrame, true, key, nil)
    elseif kind == "C" then
      SetOverrideBindingClick(ownerFrame, true, key, value)
    else
      SetOverrideBinding(ownerFrame, true, key, value)
    end
    bound[key] = desc
  end
end
local setClick = makeBinder(owner)

local CLICK_ACTIONS = { INTERACTMOUSEOVER = true, MOVEFORWARD = true, TOGGLEAUTORUN = true }

-- "NATIVE" left-click leans on the game's interactOnLeftClick. turn it on
-- while that mode is picked, and put your old value back when it isnt.
-- out of combat only (called from the binding functions, which guard it).
local function applyNativeClick()
  local db = ns.db
  if not db then return end
  if db.leftAction == "NATIVE" then
    if db.savedInteractOnLeftClick == nil then
      db.savedInteractOnLeftClick = ns.GetCVar("interactOnLeftClick") or "0"
    end
    if ns.GetCVar("interactOnLeftClick") ~= "1" then pcall(ns.SetCVar, "interactOnLeftClick", 1) end
  elseif db.savedInteractOnLeftClick ~= nil then
    pcall(ns.SetCVar, "interactOnLeftClick", db.savedInteractOnLeftClick)
    db.savedInteractOnLeftClick = nil
  end
end
ns.ApplyNativeClick = applyNativeClick

-- ---------------------------------------------------------------------
-- Left-click on enemies (db.leftEnemy): "interact" | "lock" | "lockattack".
-- Only applies while left-click is Interact. When an enemy is under the
-- reticle, BUTTON1 is pointed at a secure macro button instead:
--   lock        /target the looked-at enemy (a hard target, so it stays put)
--   lockattack  same, then start attacking it (hunters: Auto Shot)
-- Bindings cant change in combat, so out of combat the swap follows what
-- you're looking at, and on entering combat left-click goes into enemy mode
-- for the whole fight (PLAYER_REGEN_DISABLED is the last moment to switch).
-- ---------------------------------------------------------------------
local enemyBtn = CreateFrame("Button", "CTPIEnemyClickButton", UIParent, "SecureActionButtonTemplate")
enemyBtn:RegisterForClicks("AnyUp", "AnyDown")
enemyBtn:SetAttribute("type", "macro")

local function enemyMacro()
  local db = ns.db
  local lock = "/target [@softenemy,harm,nodead] softenemy"
  if not db or db.leftEnemy ~= "lockattack" then return lock end
  local _, class = UnitClass("player")
  if class == "HUNTER" then
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(75))
      or (GetSpellInfo and GetSpellInfo(75)) or "Auto Shot"
    if ns.IsSecret(name) then name = "Auto Shot" end
    return lock .. "\n/cast [@target,harm,nodead] !" .. name
  end
  return lock .. "\n/startattack [@target,harm,nodead]"
end

function ns.UpdateEnemyMacro()
  if InCombatLockdown() then return end
  enemyBtn:SetAttribute("macrotext", enemyMacro())
end

-- ---------------------------------------------------------------------
-- What's under the reticle, for choosing what left-click does out of
-- combat. Keyed off "mouseover" first: under mouselook that's exactly the
-- unit at screen center, i.e. exactly what INTERACTMOUSEOVER will act on.
-- (the soft-target tokens reach a wide cone, so a live mob NEXT to a
-- corpse used to win and turn your loot click into a lock.)
--   "enemy"  a living hostile unit
--   "other"  something we know isnt that: a corpse, an npc, a player
--   "none"   nothing under the reticle; fall back to the soft targets
-- ---------------------------------------------------------------------
local function plain(v) return (not ns.IsSecret(v)) and v end

local function aimState()
  local mo = UnitExists("mouseover")
  if ns.IsSecret(mo) then return "none" end
  if mo then
    local dead = UnitIsDead("mouseover")
    if ns.IsSecret(dead) or dead then return "other" end   -- corpses: loot / skin
    local harm = UnitCanAttack("player", "mouseover")
    if ns.IsSecret(harm) then return "none" end
    return harm and "enemy" or "other"
  end
  if plain(UnitExists("softinteract")) then return "other" end   -- interactable wins
  if plain(UnitExists("softenemy")) then return "enemy" end
  return "none"
end

-- left-click's current aim out of combat. a known enemy flips to enemy mode
-- right away; a known non-enemy (corpse, npc) flips back right away; empty
-- space waits 0.15s first, so sweeping across a gap between two mobs doesnt
-- flip the binding twice.
local enemyUnder = false
local lastEnemyAt = 0

local function wantEnemy()
  local st = aimState()
  local now = GetTime()
  if st == "enemy" then lastEnemyAt = now; return true end
  if st == "other" then return false end
  return (now - lastEnemyAt) < 0.15
end

-- "lock" / "lockattack" when left-click is acting on enemies right now, else nil
function ns.EnemyClickMode()
  local db = ns.db
  if not db or db.leftAction ~= "INTERACTMOUSEOVER" or ns.autorunSwap then return nil end
  local m = db.leftEnemy or "interact"
  if m == "interact" then return nil end
  return m
end

function ns.ApplyClickBindings()
  if InCombatLockdown() then return end
  applyNativeClick()
  local db = ns.db
  if not db then return end
  if not ns.combatEnemyMode then enemyUnder = wantEnemy() end   -- always a fresh look
  local left = db.leftAction
  if ns.autorunSwap then left = "MOVEFORWARD" end   -- left-click cancels autorun (below)
  if ns.EnemyClickMode() and (ns.combatEnemyMode or enemyUnder) then
    setClick("BUTTON1", "C", "CTPIEnemyClickButton")
  elseif left and CLICK_ACTIONS[left] then
    setClick("BUTTON1", "A", left)
  else
    setClick("BUTTON1", nil)
  end
  if CLICK_ACTIONS[db.rightAction] then
    setClick("BUTTON2", "A", db.rightAction)
  else
    setClick("BUTTON2", nil)
  end
end

-- polled from the reconcile loop (Core.lua) and on mouseover / soft-target
-- changes. with the diff binder this is free unless the aim actually changed.
-- never re-aims while the left button is held: swapping a binding mid-press
-- splits the press across two actions (down on one, up on the other).
function ns.TickClickAim()
  if not ns.EnemyClickMode() or InCombatLockdown() or ns.combatEnemyMode
     or not IsMouselooking() then return end
  local want = wantEnemy()
  if want == enemyUnder then return end
  if IsMouseButtonDown and IsMouseButtonDown("LeftButton") then return end   -- next tick
  ns.ApplyClickBindings()
end

-- what currently interacts ("click" / "right-click" / a key / nil), for the
-- look-at label's hint
function ns.InteractButtonLabel()
  local db = ns.db
  if not db then return nil end
  local leftInteracts = (db.leftAction == "INTERACTMOUSEOVER" or db.leftAction == "NATIVE")
    and not ns.autorunSwap and not (ns.combatEnemyMode and ns.EnemyClickMode())
  if leftInteracts then return "click" end
  if db.rightAction == "INTERACTMOUSEOVER" then return "right-click" end
  if db.interactKey and db.interactKey ~= "" then return db.interactKey end
  return nil
end

function ns.RemoveClickBindings()
  if InCombatLockdown() then return end
  setClick("BUTTON1", nil)
  setClick("BUTTON2", nil)
end

-- =====================================================================
-- Target / focus tools. Keyboard-bound secure buttons -- they fire under
-- mouselook (unlike mouse-button clicks, which need the cursor mouselook
-- hides) and use static unit tokens only, so they're combat-legal. Bound on
-- a SEPARATE owner so they persist regardless of mouselook engage/disengage.
-- SetOverrideBindingClick is out-of-combat only; re-synced on regen (Core).
--   lock  -> /target [@softenemy]      grab the looked-at mob as hard target
--            (Sticky Targeting then holds it; Esc clears it natively)
--   focus -> /focus  [@target,harm][@softenemy]   harmful target, else look-at
--   clrf  -> /clearfocus
-- =====================================================================
local toolOwner = CreateFrame("Frame", "CTPIToolBindingOwner", UIParent)
local setTool = makeBinder(toolOwner)
local toolKeys = {}   -- key -> true for keys we've bound, so a rebind can drop old ones

local function secureMacroButton(name, macrotext)
  local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
  -- modern clients (Forever) only act on the half of a keybound click that
  -- matches the ActionButtonUseKeyDown cvar, so "AnyDown" alone can silently
  -- do nothing. register both halves; it still fires once per press.
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "macro")
  b:SetAttribute("macrotext", macrotext)
  return b
end

-- only retargets when something hostile is actually under the reticle;
-- the old "/target [@softenemy]" could clear your target when it wasnt
secureMacroButton("CTPILockButton",       "/target [@softenemy,harm,nodead] softenemy")
secureMacroButton("CTPIFocusButton",      "/focus [@target,harm][@softenemy]")
secureMacroButton("CTPIClearFocusButton", "/clearfocus")

function ns.ApplyToolBindings()
  if InCombatLockdown() then return end
  local db = ns.db
  if not db then return end
  local want = {}
  if db.lockKey and db.lockKey ~= "" then want[db.lockKey] = "CTPILockButton" end
  if db.focusKey and db.focusKey ~= "" then want[db.focusKey] = "CTPIFocusButton" end
  if db.clearFocusKey and db.clearFocusKey ~= "" then want[db.clearFocusKey] = "CTPIClearFocusButton" end
  -- interact key: loot / skin / talk from the keyboard, including in combat
  -- when left-click is in lock mode. a native action, not a button click.
  if db.interactKey and db.interactKey ~= "" then want[db.interactKey] = "=INTERACTMOUSEOVER" end
  for key in pairs(toolKeys) do
    if not want[key] then setTool(key, nil); toolKeys[key] = nil end
  end
  for key, target in pairs(want) do
    if target:sub(1, 1) == "=" then setTool(key, "A", target:sub(2))
    else setTool(key, "C", target) end
    toolKeys[key] = true
  end
end

-- =====================================================================
-- Left-click cancels autorun.
-- Stopping autorun is a protected action, but pressing MOVEFORWARD does it
-- natively. So while you're autorunning (and left-click is Interact), the
-- left button is quietly rebound to MOVEFORWARD: a tap stops the autorun,
-- and once you've stopped moving it goes back to Interact.
--
-- Out of combat only: bindings can't change in combat, so on entering
-- combat (PLAYER_REGEN_DISABLED, the last moment it's allowed) left goes
-- back to Interact, and the swap resumes after combat if you're still
-- autorunning.
--
-- Autorun detection: hooks on the autorun functions the keybinds call,
-- plus a fallback for right-click autorun (started moving while the right
-- button is down), and "stopped moving" always clears it.
-- =====================================================================
local autoRunning = false

local function wantSwap()
  local db = ns.db
  return db and db.leftStopsAutorun and db.leftAction == "INTERACTMOUSEOVER"
    and autoRunning and not InCombatLockdown()
end

local function syncAutorunSwap()
  if InCombatLockdown() then return end
  local want = wantSwap() and true or false
  if want ~= (ns.autorunSwap and true or false) then
    ns.autorunSwap = want
    if ns.RefreshBindings then ns.RefreshBindings() end
  end
end
ns.SyncAutorunSwap = syncAutorunSwap

local function setAuto(v)
  autoRunning = v and true or false
  syncAutorunSwap()
end

if ToggleAutoRun then hooksecurefunc("ToggleAutoRun", function() setAuto(not autoRunning) end) end
if StartAutoRun  then hooksecurefunc("StartAutoRun",  function() setAuto(true)  end) end
if StopAutoRun   then hooksecurefunc("StopAutoRun",   function() setAuto(false) end) end

local aev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
                     "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN",
                     "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED",
                     "UPDATE_MOUSEOVER_UNIT" }) do
  pcall(aev.RegisterEvent, aev, e)
end
aev:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_STARTED_MOVING" then
    -- fallback if the hooks dont fire: right-click autorun just started
    local db = ns.db
    if db and db.rightAction == "TOGGLEAUTORUN" and IsMouseButtonDown
       and IsMouseButtonDown("RightButton") then
      setAuto(true)
    end
  elseif event == "PLAYER_STOPPED_MOVING" then
    setAuto(false)
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- last moment bindings can change. left goes back to Interact (or enemy
    -- mode), and the click bindings are put in place even if the cursor is
    -- free right now: combat often starts with a loot window / bag / dialog
    -- open, and nothing can bind them again until combat ends. (clicks on UI
    -- windows still go to the windows; only world clicks use these.)
    ns.autorunSwap = false
    if ns.EnemyClickMode() then ns.combatEnemyMode = true end
    if ns.db and ns.db.enabled then ns.ApplyClickBindings() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    ns.combatEnemyMode = false
    if ns.UpdateEnemyMacro then ns.UpdateEnemyMacro() end
    if ns.RefreshBindings then ns.RefreshBindings() end
    syncAutorunSwap()
  elseif event == "PLAYER_LOGIN" then
    ns.UpdateEnemyMacro()
  elseif event == "PLAYER_SOFT_ENEMY_CHANGED" or event == "PLAYER_SOFT_INTERACT_CHANGED"
      or event == "UPDATE_MOUSEOVER_UNIT" then
    ns.TickClickAim()   -- react right away instead of waiting for the next tick
  end
end)
