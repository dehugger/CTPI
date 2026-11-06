local addonName, ns = ...

-- =====================================================================
-- CTPI / Camera.lua
-- Over-the-shoulder camera. Slides the camera sideways so your character
-- isnt standing on the reticle (screen center is still the aim point, the
-- character just moves out of the way). Uses the client's hidden
-- test_cameraOverShoulder cvar, eased over a short tween so it glides
-- instead of snapping.
--
-- MODES (db.camera.mode)
--   "off"     never
--   "always"  whenever CTPI is on
--   "cursor"  follows the MANUAL cursor toggle: on while mouselook is
--             yours, off when you free the cursor with the CTPI free-cursor
--             key or turn the master off. windows auto-freeing the cursor
--             (bags, vendors, chat...) do NOT move the camera.
--   "target"  on when the target-lock key grabs a target, off when that
--             target is cleared (esc, or targeting nothing)
--
-- Notes
--   * CameraKeepCharacterCentered (a motion-sickness option) blocks the
--     shoulder offset, so it is lifted while the offset is active and put
--     back to your original value when it goes away.
--   * The shoulder cvar is reset on logout so it doesnt persist into the
--     next login (the client may warn about "experimental camera" cvars
--     that are saved non-default at startup).
-- =====================================================================

local CVAR      = "test_cameraOverShoulder"
local CENTERED  = "CameraKeepCharacterCentered"
local DURATION  = 0.35     -- seconds per glide

local cur = 0              -- offset currently applied
local goal = 0             -- offset we are gliding toward
local from, t0 = 0, 0
local savedCentered        -- your CameraKeepCharacterCentered, while lifted

local function apply(v)
  cur = v
  pcall(ns.SetCVar, CVAR, string.format("%.3f", v))
end

local function liftCentered()
  if savedCentered == nil then
    savedCentered = ns.GetCVar(CENTERED) or "0"
  end
  pcall(ns.SetCVar, CENTERED, 0)
end

local function restoreCentered()
  if savedCentered ~= nil then
    pcall(ns.SetCVar, CENTERED, savedCentered)
    savedCentered = nil
  end
end

local tween = CreateFrame("Frame")
tween:Hide()
tween:SetScript("OnUpdate", function(self)
  local t = (GetTime() - t0) / DURATION
  if t >= 1 then
    apply(goal)
    self:Hide()
    if goal == 0 then restoreCentered() end
    return
  end
  local e = t * t * (3 - 2 * t)   -- smoothstep: eases in and out
  apply(from + (goal - from) * e)
end)

local function glideTo(v, instant)
  if v ~= 0 then liftCentered() end
  if v == goal and (tween:IsShown() or cur == v) then return end
  goal = v
  if instant then
    tween:Hide()
    apply(v)
    if v == 0 then restoreCentered() end
    return
  end
  from, t0 = cur, GetTime()
  tween:Show()
end

-- set by the target-lock hook below, cleared when the target goes away
ns.shoulderTargetLocked = false

function ns.ShoulderWanted()
  local db = ns.db
  if not db or not db.enabled then return false end
  local mode = db.camera and db.camera.mode or "off"
  if mode == "always" then return true end
  if mode == "cursor" then return not ns.freeCursorHeld end
  if mode == "target" then return ns.shoulderTargetLocked and true or false end
  return false
end

function ns.UpdateShoulder(instant)
  if not ns.db then return end
  local on = ns.ShoulderWanted()
  glideTo(on and (ns.db.camera.offset or 1.2) or 0, instant)
end

-- ---------------------------------------------------------------------
-- target-lock tracking
-- ---------------------------------------------------------------------
local function targetExists()
  local e = UnitExists("target")
  if ns.IsSecret(e) then return nil end   -- cant tell
  return e and true or false
end

local function afterLockPressed()
  local e = targetExists()
  if e == nil then return end
  ns.shoulderTargetLocked = e
  ns.UpdateShoulder()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    cur = tonumber(ns.GetCVar(CVAR)) or 0
    goal = cur
    -- post-hook the secure lock button; runs after its /target fires
    if CTPILockButton and CTPILockButton.HookScript then
      CTPILockButton:HookScript("OnClick", function()
        C_Timer.After(0.1, afterLockPressed)
      end)
    end
    ns.UpdateShoulder(true)

  elseif event == "PLAYER_TARGET_CHANGED" then
    if ns.shoulderTargetLocked and targetExists() == false then
      ns.shoulderTargetLocked = false
      ns.UpdateShoulder()
    end

  elseif event == "PLAYER_LOGOUT" then
    tween:Hide()
    apply(0)
    restoreCentered()
  end
end)
