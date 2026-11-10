local addonName, ns = ...

-- =====================================================================
-- CTPI / Compat.lua
-- Small shims so the rest of the addon runs on WoW Forever (modern
-- Mainline API, interface 16001, Midnight-era addon rules) and still
-- degrades sanely on the old 2.5.x client. Loaded first.
--
-- SECRET VALUES: on Forever some unit APIs (UnitExists, UnitGUID,
-- UnitName, UnitPower...) can return "secret" values, mostly around
-- combat. Addon code cant test, compare or do math on those without
-- erroring, but it CAN pass them straight into widget setters
-- (StatusBar:SetValue, GameTooltip:SetUnit on the token, etc).
-- Anything that reads unit data checks ns.IsSecret first.
-- =====================================================================

local issecretvalue = issecretvalue

function ns.IsSecret(v)
  if issecretvalue then return issecretvalue(v) and true or false end
  return false
end

-- cvars: C_CVar on modern clients, the old globals as fallback
function ns.GetCVar(name)
  if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
  if GetCVar then return GetCVar(name) end
end

function ns.SetCVar(name, value)
  if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, tostring(value)) end
  if SetCVar then return SetCVar(name, value) end
end

-- "is the user typing somewhere". the chat helpers have moved around in
-- modern builds, so try both, then fall back to any focused edit box.
function ns.IsTyping()
  local getActive = ChatEdit_GetActiveWindow
    or (ChatFrameUtil and ChatFrameUtil.GetActiveWindow)
  if getActive and getActive() then return true end
  if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return true end
  return false
end

-- anything on the cursor (item, spell, macro, mount, money...)
function ns.CursorBusy()
  if GetCursorInfo then return GetCursorInfo() ~= nil end
  if CursorHasItem and CursorHasItem() then return true end
  if CursorHasSpell and CursorHasSpell() then return true end
  return false
end

function ns.SpellTargeting()
  return (SpellIsTargeting and SpellIsTargeting()) and true or false
end

-- "am I stealthed?" asked every way we know. Forever might report rogue
-- stealth like retail (IsStealthed) or like Classic (a stance / form), so
-- any of these counts. Returns stealthed, how (for /ctpi why).
local STEALTH_AURAS = { 1784, 1785, 1786, 1787, 115191, 5215, 1856, 11327 } -- stealth, prowl, vanish
function ns.PlayerStealthed()
  if IsStealthed and IsStealthed() then return true, "IsStealthed" end
  if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    for _, id in ipairs(STEALTH_AURAS) do
      local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
      if ok and a and not ns.IsSecret(a) then return true, "aura " .. id end
    end
  end
  if AuraUtil and AuraUtil.FindAuraByName then
    for _, n in ipairs({ "Stealth", "Prowl", "Vanish" }) do
      local ok, a = pcall(AuraUtil.FindAuraByName, n, "player", "HELPFUL")
      if ok and a and not ns.IsSecret(a) then return true, "aura " .. n end
    end
  end
  local _, class = UnitClass("player")
  if class == "ROGUE" and GetShapeshiftForm then
    local f = GetShapeshiftForm()
    if not ns.IsSecret(f) and (f or 0) > 0 then return true, "stance " .. f end
  end
  return false, "none"
end

-- combo points. modern clients keep them as player power; the old client
-- keeps them per-target. read both and take whichever this build fills.
-- if either comes back secret we hand that back untouched (display only).
function ns.GetComboPoints()
  local a, b
  if UnitPower and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
    local ok, v = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
    if ok then a = v end
  end
  if GetComboPoints then
    local ok, v = pcall(GetComboPoints, "player", "target")
    if ok then b = v end
  end
  if ns.IsSecret(a) then return a end
  if ns.IsSecret(b) then return b end
  return math.max(tonumber(a) or 0, tonumber(b) or 0)
end
