local addonName, ns = ...

-- =====================================================================
-- CTPI / Radial.lua
-- Hold a modifier (Shift by default) and a ring of spell buttons pops up
-- around screen center; the camera lets go, the cursor appears in the
-- middle, and you slide toward a spell and click it. Let go of the
-- modifier and the ring closes and the camera locks again.
--
-- Which ring shows depends on context: each class has a list of rings,
-- each with a macro condition ("[stealth]", "[{cat}]", "" = default). The
-- first ring whose condition matches wins.
--
-- Combat-safe by construction:
--   * the rings are protected frames whose visibility is driven by secure
--     state drivers ("[mod:shift,stealth] show; hide"), so the game itself
--     shows / hides them, in combat too
--   * the slots are SecureActionButtons; clicking one is a normal hardware
--     click, so casting works in combat
--   * freeing the cursor (MouselookStop) is not protected
-- The one thing that can't change in combat is the ring contents / layout;
-- edits made in combat apply when it ends.
--
-- Cursor position: the client's CursorFreelookCentering setting is turned
-- on while the radial is enabled (your value is restored on logout or when
-- disabled), so the cursor reappears at screen center when the camera lets
-- go, right in the middle of the ring.
-- =====================================================================

local MAX_RINGS, MAX_SLOTS = 6, 8
local ringFrames = {}
local pending = false

-- preferred driver: one secure state driver picks the ring ("1".."6" or
-- "0"), and a snippet shows it unless you're typing (holding Shift for a
-- capital letter in chat shouldn't pop the ring). needs secure snippets;
-- without them each ring gets a plain visibility driver instead.
local header = CreateFrame("Frame", "CTPIRadialHeader", UIParent, "SecureHandlerStateTemplate")
header:SetAttribute("_onstate-radial", [[
  for i = 1, 6 do
    local r = self:GetFrameRef("ring" .. i)
    if r then r:Hide() end
  end
  if newstate ~= "0" and not self:GetAttribute("ctpi-typing") then
    local r = self:GetFrameRef("ring" .. newstate)
    if r then r:Show() end
  end
]])
local headerDriver = false
local typingFlag = nil

local MOD_COND = { shift = "mod:shift", ctrl = "mod:ctrl", alt = "mod:alt" }

-- ---------------------------------------------------------------------
-- frames (created at load, out of combat)
-- ---------------------------------------------------------------------
local function makeSlot(ring, i, j)
  local b = CreateFrame("Button", "CTPIRadial" .. i .. "Slot" .. j, ring, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "macro")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(b)
  bg:SetColorTexture(0, 0, 0, 0.6)
  ns.RoundMask(bg)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 3, -3)
  icon:SetPoint("BOTTOMRIGHT", -3, 3)
  ns.RoundMask(icon)
  b.icon = icon
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  hl:SetColorTexture(1, 0.85, 0.45, 0.35)
  ns.RoundMask(hl)
  local name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetPoint("TOP", b, "BOTTOM", 0, -2)
  local f, sz = name:GetFont()
  if f then name:SetFont(f, sz, "OUTLINE") end
  b.label = name
  b:Hide()
  return b
end

local function buildFrames()
  if #ringFrames > 0 then return end
  for i = 1, MAX_RINGS do
    local r = CreateFrame("Frame", "CTPIRadial" .. i, UIParent)
    r:SetFrameStrata("DIALOG")
    r:SetSize(1, 1)
    r:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetPoint("CENTER", r, "CENTER", 0, 0)
    local f, sz = r.title:GetFont()
    if f then r.title:SetFont(f, sz, "OUTLINE") end
    r.slots = {}
    for j = 1, MAX_SLOTS do r.slots[j] = makeSlot(r, i, j) end
    -- free the cursor the moment a ring opens; re-lock when it closes
    r:HookScript("OnShow", function()
      if IsMouselooking() then MouselookStop() end
      ns.ForceReconcile()
    end)
    r:HookScript("OnHide", function() ns.ForceReconcile() end)
    r:Hide()
    ringFrames[i] = r
    SecureHandlerSetFrameRef(header, "ring" .. i, r)
  end
end

function ns.RadialOpen()
  for _, r in ipairs(ringFrames) do
    if r:IsShown() then return true end
  end
  return false
end

-- ---------------------------------------------------------------------
-- slot actions
-- ---------------------------------------------------------------------
local function spellKnown(name)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and info then return true end
    return false
  end
  return GetSpellInfo and GetSpellInfo(name) ~= nil
end

local function harmful(name)
  local f = (C_Spell and C_Spell.IsSpellHarmful) or IsHarmfulSpell
  if not f then return nil end
  local ok, v = pcall(f, name)
  if ok and not ns.IsSecret(v) then return v and true or false end
end
local function helpful(name)
  local f = (C_Spell and C_Spell.IsSpellHelpful) or IsHelpfulSpell
  if not f then return nil end
  local ok, v = pcall(f, name)
  if ok and not ns.IsSecret(v) then return v and true or false end
end

-- a slot is a spell name or a full "/macro" line. spells pick a sensible
-- target: harmful -> your hostile target, else the looked-at enemy;
-- helpful -> your friendly target, else the looked-at friendly, else you.
local function slotMacro(text)
  if text:sub(1, 1) == "/" then return ns.ExpandTokens(text), nil end
  if harmful(text) then
    return "/cast [@target,harm,nodead][@softenemy,harm,nodead][] " .. text, text
  elseif helpful(text) then
    return "/cast [@target,help,nodead][@softfriend,help,nodead][@player] " .. text, text
  end
  return "/cast " .. text, text
end

-- ---------------------------------------------------------------------
-- (re)build: contents, layout and visibility drivers. out of combat only.
-- ---------------------------------------------------------------------
local function conditionGroups(cond)
  local groups = {}
  for g in ns.ExpandTokens(cond or ""):gmatch("%[(.-)%]") do groups[#groups + 1] = g end
  if #groups == 0 then groups[1] = "" end
  return groups
end

local function clause(mod, groups, result)
  local parts = {}
  for _, g in ipairs(groups) do
    parts[#parts + 1] = "[" .. mod .. (g ~= "" and ("," .. g) or "") .. "]"
  end
  return table.concat(parts) .. " " .. result .. "; "
end

function ns.RebuildRadial()
  if InCombatLockdown() then pending = true; return end
  pending = false
  buildFrames()
  for _, r in ipairs(ringFrames) do UnregisterStateDriver(r, "visibility"); r:Hide() end
  if headerDriver then UnregisterStateDriver(header, "radial"); headerDriver = false end
  local useHeader = ns.secureAimOK
  local headerCond = ""

  local db = ns.db
  local cfg = ns.ClassConfig()
  if not (db and db.enabled and db.radial.enabled and cfg) then return end

  local mod = MOD_COND[db.radial.mod or "shift"] or "mod:shift"
  local radius, size = db.radial.radius or 110, db.radial.size or 44

  -- default (empty condition) rings go last so specific ones win
  local order = {}
  for _, rg in ipairs(cfg.rings or {}) do
    if (rg.cond or "") ~= "" then order[#order + 1] = rg end
  end
  for _, rg in ipairs(cfg.rings or {}) do
    if (rg.cond or "") == "" then order[#order + 1] = rg end
  end

  local prior = ""   -- earlier rings' conditions, as "hide" clauses
  for i, rg in ipairs(order) do
    if i > MAX_RINGS then break end
    local r = ringFrames[i]
    r.title:SetText(rg.name or "")
    local shown = {}
    for k = 1, MAX_SLOTS do   -- not ipairs: edited slot lists can have gaps
      local text = ((rg.slots or {})[k] or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" and (text:sub(1, 1) == "/" or spellKnown(text)) then
        shown[#shown + 1] = text
      end
    end
    for j, b in ipairs(r.slots) do
      local text = shown[j]
      if text then
        local macro, spell = slotMacro(text)
        b:SetAttribute("macrotext", macro)
        local icon = spell and ns.SpellIcon(spell)
        b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.label:SetText(spell or text:match("^/%a+%s+(.+)$") or text)
        b:SetSize(size, size)
        local a = math.rad(90 - (j - 1) * 360 / #shown)
        b:ClearAllPoints()
        b:SetPoint("CENTER", r, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
        b:Show()
      else
        b:Hide()
      end
    end
    local groups = conditionGroups(rg.cond)
    if #shown > 0 then
      if useHeader then
        headerCond = headerCond .. clause(mod, groups, tostring(i))
      else
        RegisterStateDriver(r, "visibility", prior .. clause(mod, groups, "show") .. "hide")
      end
    elseif useHeader then
      headerCond = headerCond .. clause(mod, groups, "0")   -- empty ring still blocks later ones
    end
    prior = prior .. clause(mod, groups, "hide")
  end
  if useHeader and headerCond ~= "" then
    RegisterStateDriver(header, "radial", headerCond .. "0")
    headerDriver = true
  end
end

-- out of combat: tell the secure handler when you're typing, and close an
-- open ring if typing started. (in combat attributes can't change; typing
-- in combat with the modifier held can still pop the ring.)
function ns.TickRadial()
  if not headerDriver or InCombatLockdown() then return end
  local t = ns.IsTyping() and true or nil
  if t ~= typingFlag then
    typingFlag = t
    header:SetAttribute("ctpi-typing", t)
    SecureHandlerExecute(header, [[
      if self:GetAttribute("ctpi-typing") then
        for i = 1, 6 do local r = self:GetFrameRef("ring" .. i); if r then r:Hide() end end
      end
    ]])
  end
end

-- ---------------------------------------------------------------------
-- cursor centering (so the cursor lands in the middle of the ring)
-- ---------------------------------------------------------------------
function ns.ApplyFreelookCentering()
  local db = ns.db
  if not db then return end
  if db.enabled and db.radial.enabled then
    if db.savedFreelookCentering == nil then
      db.savedFreelookCentering = ns.GetCVar("CursorFreelookCentering") or "0"
    end
    pcall(ns.SetCVar, "CursorFreelookCentering", 1)
  elseif db.savedFreelookCentering ~= nil then
    pcall(ns.SetCVar, "CursorFreelookCentering", db.savedFreelookCentering)
    db.savedFreelookCentering = nil
  end
end

local function restoreCentering()
  local db = ns.db
  if db and db.savedFreelookCentering ~= nil then
    pcall(ns.SetCVar, "CursorFreelookCentering", db.savedFreelookCentering)
    db.savedFreelookCentering = nil
  end
end

-- "you're in form N right now", for writing conditions in the editor
function ns.CurrentFormIndex()
  local f = GetShapeshiftForm and GetShapeshiftForm()
  if ns.IsSecret(f) then return nil end
  return f or 0
end

buildFrames()

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
                     "UPDATE_SHAPESHIFT_FORMS", "PLAYER_TALENT_UPDATE", "LEARNED_SPELL_IN_TAB" }) do
  pcall(ev.RegisterEvent, ev, e)
end
local rebuildQueued = false
ev:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGOUT" then restoreCentering(); return end
  if event == "PLAYER_LOGIN" then ns.ApplyFreelookCentering() end
  if event == "PLAYER_REGEN_ENABLED" and not pending then return end
  -- spell / form events can come in bursts; rebuild once
  if rebuildQueued then return end
  rebuildQueued = true
  C_Timer.After(0.3, function() rebuildQueued = false; ns.RebuildRadial() end)
end)
