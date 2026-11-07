local addonName, ns = ...

-- =====================================================================
-- CTPI / Secure.lua
-- Mouse-button bindings while mouselook is engaged. Both are NATIVE
-- action bindings (SetOverrideBinding) -- the binding type that fires
-- under mouselook. No SecureActionButton / macro click, which needs a
-- clean cursor that mouselook hides.
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

local function lookingAtEnemy()
  local e = UnitExists("softenemy")
  if ns.IsSecret(e) or not e then return false end
  local i = UnitExists("softinteract")
  if (not ns.IsSecret(i)) and i then return false end   -- an interactable wins (loot, npc)
  return true
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
  ClearOverrideBindings(owner)
  applyNativeClick()
  local db = ns.db
  if not db then return end
  local left = db.leftAction
  if ns.autorunSwap then left = "MOVEFORWARD" end   -- left-click cancels autorun (below)
  if ns.EnemyClickMode() and (ns.combatEnemyMode or lookingAtEnemy()) then
    SetOverrideBindingClick(owner, true, "BUTTON1", "CTPIEnemyClickButton")
    left = nil
  end
  if left and CLICK_ACTIONS[left] then
    SetOverrideBinding(owner, true, "BUTTON1", left)
  end
  if CLICK_ACTIONS[db.rightAction] then
    SetOverrideBinding(owner, true, "BUTTON2", db.rightAction)
  end
end

-- which mouse button interacts right now ("click" / "right-click" / nil),
-- for the look-at label's hint
function ns.InteractButtonLabel()
  local db = ns.db
  if not db then return nil end
  if (db.leftAction == "INTERACTMOUSEOVER" or db.leftAction == "NATIVE") and not ns.autorunSwap then
    return "click"
  end
  if db.rightAction == "INTERACTMOUSEOVER" then return "right-click" end
  return nil
end

function ns.RemoveClickBindings()
  if InCombatLockdown() then return end
  ClearOverrideBindings(owner)
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

secureMacroButton("CTPILockButton",       "/target [@softenemy]")
secureMacroButton("CTPIFocusButton",      "/focus [@target,harm][@softenemy]")
secureMacroButton("CTPIClearFocusButton", "/clearfocus")

function ns.ApplyToolBindings()
  if InCombatLockdown() then return end
  ClearOverrideBindings(toolOwner)
  local db = ns.db
  if not db then return end
  if db.lockKey and db.lockKey ~= "" then
    SetOverrideBindingClick(toolOwner, true, db.lockKey, "CTPILockButton")
  end
  if db.focusKey and db.focusKey ~= "" then
    SetOverrideBindingClick(toolOwner, true, db.focusKey, "CTPIFocusButton")
  end
  if db.clearFocusKey and db.clearFocusKey ~= "" then
    SetOverrideBindingClick(toolOwner, true, db.clearFocusKey, "CTPIClearFocusButton")
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
                     "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED" }) do
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
    -- last moment bindings can change: left back to Interact (or enemy mode)
    local changed = false
    if ns.autorunSwap then ns.autorunSwap = false; changed = true end
    if ns.EnemyClickMode() then ns.combatEnemyMode = true; changed = true end
    if changed and ns.RefreshBindings then ns.RefreshBindings() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    ns.combatEnemyMode = false
    if ns.UpdateEnemyMacro then ns.UpdateEnemyMacro() end
    if ns.RefreshBindings then ns.RefreshBindings() end
    syncAutorunSwap()
  elseif event == "PLAYER_LOGIN" then
    ns.UpdateEnemyMacro()
  elseif event == "PLAYER_SOFT_ENEMY_CHANGED" or event == "PLAYER_SOFT_INTERACT_CHANGED" then
    -- out of combat, follow what's under the reticle
    if ns.EnemyClickMode() and not InCombatLockdown() and IsMouselooking() then
      ns.ApplyClickBindings()
    end
  end
end)
