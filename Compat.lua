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
