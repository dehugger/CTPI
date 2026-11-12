local addonName, ns = ...

-- =====================================================================
-- CTPI / Radial.lua
-- Hold a modifier (Shift by default) while the camera is locked and a
-- sectioned ring opens around the reticle. It works like a console radial:
-- the direction you move picks the section (it lights up, and a pointer
-- shows your direction), and a click casts it. Not moving picks nothing.
-- Let go of the modifier and the ring closes and the camera locks again.
--
-- Two layers:
--   * the visible ring sits around the reticle (plain addon frames)
--   * the click is an invisible, screen-covering secure button centered on
--     wherever the cursor appeared, so "direction moved" = "cursor relative
--     to that button's center", whatever spot the cursor showed up at
--
-- Which ring opens depends on context: each class has rings with a macro
-- condition ("[stealth]", "[{cat}]", "" = default); the first match wins.
--
-- How it stays combat-safe:
--   * a secure state driver on CTPIRadialHeader picks the ring ("1".."6",
--     or "0" for none) and a restricted snippet shows it at the cursor,
--     unless CTPI says the ring is blocked right now (typing, free-cursor
--     mode, a window open, CTPI off: addon code updates that flag out of
--     combat)
--   * each ring is one big SecureActionButton. A restricted pre-click
--     snippet works out which section the cursor is in (the section whose
--     direction is closest to the cursor's, no trig needed), loads that
--     section's macro and lets the click through; the middle is a dead zone
--   * the section highlight is plain addon code reading the cursor
-- Without secure snippets (some client builds), each ring falls back to a
-- visibility driver and small clickable buttons on the icons.
-- Ring contents / layout can only change out of combat.
-- =====================================================================

local MAX_RINGS, MAX_SLOTS = 6, 8
local SEGMENTS = 96            -- line pieces that draw the band
local INNER = 0.55             -- inner radius as a fraction of the outer
local PIE = 4000               -- the invisible click area (bigger than any screen)
local DEAD = 18                -- move at least this far (px) to pick a section
local ringFrames = {}
local pending = false

local MOD_COND = { shift = "mod:shift", ctrl = "mod:ctrl", alt = "mod:alt" }

local COLOR_BASE  = { 0.07, 0.06, 0.05, 0.80 }
local COLOR_ALT   = { 0.11, 0.09, 0.07, 0.80 }
local COLOR_HOVER = { 0.80, 0.60, 0.28, 0.92 }
local COLOR_EDGE  = { 0.78, 0.64, 0.37, 0.55 }

local header = CreateFrame("Frame", "CTPIRadialHeader", UIParent, "SecureHandlerStateTemplate")
header:SetAllPoints(UIParent)   -- full screen (mouse disabled), so it can read the cursor position
header:SetAttribute("_onstate-radial", [[
  for i = 1, 6 do
    local r = self:GetFrameRef("ring" .. i)
    if r then r:Hide() end
  end
  if newstate ~= "0" and not self:GetAttribute("ctpi-block") then
    local r = self:GetFrameRef("ring" .. newstate)
    if r then
      local mx, my = self:GetMousePosition()
      if mx and my then
        local w, h = self:GetWidth(), self:GetHeight()
        -- the click layer centers on the cursor; the visible ring stays at
        -- the reticle
        r:ClearAllPoints()
        r:SetPoint("CENTER", self, "BOTTOMLEFT", mx * w, my * h)
      end
      r:Show()
    end
  end
]])
local headerDriver = false
local blockFlag = nil

-- the pie click: pick the section from the cursor direction
local PIE_PRECLICK = [[
  local mx, my = self:GetMousePosition()
  if not mx then return false end
  local dx, dy = mx - 0.5, my - 0.5
  local dead = self:GetAttribute("ctpi-dead") or 0
  if dx * dx + dy * dy < dead * dead then return false end
  local n = self:GetAttribute("ctpi-n") or 0
  local best, pick = -10, nil
  for k = 1, n do
    local d = dx * (self:GetAttribute("ctpi-ux" .. k) or 0) + dy * (self:GetAttribute("ctpi-uy" .. k) or 0)
    if d > best then best, pick = d, k end
  end
  if not pick then return false end
  self:SetAttribute("macrotext", self:GetAttribute("ctpi-m" .. pick))
]]

-- ---------------------------------------------------------------------
-- frames (created at load, out of combat)
-- ---------------------------------------------------------------------
local function makeFallbackSlot(ring, i, j)
  local b = CreateFrame("Button", "CTPIRadial" .. i .. "Slot" .. j, ring, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "macro")
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

    -- the click layer: one huge secure button centered on the cursor
    local pie = CreateFrame("Button", "CTPIRadial" .. i .. "Pie", r, "SecureActionButtonTemplate")
    pie:SetSize(PIE, PIE)
    pie:SetPoint("CENTER", r, "CENTER", 0, 0)
    pie:RegisterForClicks("AnyUp", "AnyDown")
    pie:SetAttribute("type", "macro")
    pie:Hide()
    r.pie = pie

    r.slots = {}
    for j = 1, MAX_SLOTS do r.slots[j] = makeFallbackSlot(r, i, j) end

    -- visuals: a plain child frame parked around the reticle
    local v = CreateFrame("Frame", nil, r)
    v:SetSize(200, 200)
    v:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    v:SetFrameLevel(pie:GetFrameLevel() + 2)
    v.segs, v.edges, v.icons, v.labels = {}, {}, {}, {}
    if v.CreateLine then
      for s = 1, SEGMENTS do
        local l = v:CreateLine(nil, "BACKGROUND")
        v.segs[s] = l
      end
      for k = 1, MAX_SLOTS do
        local e = v:CreateLine(nil, "BORDER")
        e:SetThickness(1.5)
        e:SetColorTexture(COLOR_EDGE[1], COLOR_EDGE[2], COLOR_EDGE[3], COLOR_EDGE[4])
        v.edges[k] = e
      end
    end
    for k = 1, MAX_SLOTS do
      local ic = v:CreateTexture(nil, "ARTWORK")
      ns.RoundMask(ic)
      v.icons[k] = ic
      local lb = v:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      local f, sz = lb:GetFont()
      if f then lb:SetFont(f, sz, "OUTLINE") end
      v.labels[k] = lb
    end
    if v.CreateLine then
      local ptr = v:CreateLine(nil, "OVERLAY")
      ptr:SetThickness(3)
      ptr:SetColorTexture(1, 0.85, 0.45, 0.9)
      ptr:Hide()
      v.pointer = ptr
    end
    v.center = v:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    v.center:SetPoint("CENTER", v, "CENTER", 0, 0)
    local f, sz = v.center:GetFont()
    if f then v.center:SetFont(f, sz, "OUTLINE") end
    r.v = v

    r:HookScript("OnShow", function(self)
      -- fallback driver: addon code enforces "only while the camera is locked"
      if not headerDriver and not InCombatLockdown() and blockFlag then
        self:Hide(); return
      end
      if IsMouselooking() then MouselookStop() end
      if ns.RecordFreeCursor then C_Timer.After(0, ns.RecordFreeCursor) end
      -- out of combat, re-place under the now-visible cursor (corrects the
      -- secure placement, and is the only placement without snippets)
      if not InCombatLockdown() then
        C_Timer.After(0, function()
          if InCombatLockdown() or not self:IsShown() then return end
          local x, y = GetCursorPosition()
          local sc = UIParent:GetEffectiveScale()
          self:ClearAllPoints()
          self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc, y / sc)
        end)
      end
      self.hover = -1
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
-- drawing + hover highlight
-- ---------------------------------------------------------------------
local function sectionAngle(k, n) return math.rad(90 - (k - 1) * 360 / n) end   -- top, clockwise

local function paint(r, hover)
  local v, n = r.v, r.n or 0
  if n == 0 then return end
  for s, l in ipairs(v.segs) do
    local k = l.section
    local c = (k == hover) and COLOR_HOVER or ((k % 2 == 0) and COLOR_ALT or COLOR_BASE)
    l:SetColorTexture(c[1], c[2], c[3], c[4])
  end
  for k = 1, n do
    v.labels[k]:SetTextColor(k == hover and 1 or 0.85, k == hover and 0.85 or 0.85, k == hover and 0.45 or 0.85)
    v.icons[k]:SetAlpha(k == hover and 1 or 0.8)
  end
  v.center:SetText(hover and r.names[hover] or (r.ringName or ""))
end

-- which section the cursor is in (same rule as the secure click), or nil
local function hoverSection(r)
  local n = r.n or 0
  if n == 0 then return nil end
  local cx, cy = r:GetCenter()          -- where the cursor started
  if not cx then return nil end
  local x, y = GetCursorPosition()
  local sc = r:GetEffectiveScale()
  local dx, dy = x / sc - cx, y / sc - cy
  local v = r.v
  if v.pointer then
    local len = math.sqrt(dx * dx + dy * dy)
    if len >= DEAD then
      local inner = (r.outer or 160) * INNER
      v.pointer:SetStartPoint("CENTER", v, 0, 0)
      v.pointer:SetEndPoint("CENTER", v, dx / len * inner * 0.85, dy / len * inner * 0.85)
      v.pointer:Show()
    else
      v.pointer:Hide()
    end
  end
  if dx * dx + dy * dy < DEAD * DEAD then return nil end
  local best, pick = -math.huge, nil
  for k = 1, n do
    local a = sectionAngle(k, n)
    local d = dx * math.cos(a) + dy * math.sin(a)
    if d > best then best, pick = d, k end
  end
  return pick
end

local function layoutRing(r, outer, entries, ringName, useSecure)
  local v, n = r.v, #entries
  local inner = outer * INNER
  local mid, band = (outer + inner) / 2, outer - inner
  r.n, r.outer, r.ringName = n, outer, ringName
  r.names = {}
  local ret = ns.db.reticle
  v:SetSize(outer * 2, outer * 2)
  v:ClearAllPoints()
  v:SetPoint("CENTER", UIParent, "CENTER", ret.x or 0, ret.y or 0)

  -- band: SEGMENTS short thick lines around the middle radius
  local step = 2 * math.pi / SEGMENTS
  for s, l in ipairs(v.segs) do
    local a0 = math.pi / 2 - (s - 1) * step
    local a1 = a0 - step * 1.15      -- slight overlap so there are no gaps
    l:SetThickness(band)
    l:SetStartPoint("CENTER", v, math.cos(a0) * mid, math.sin(a0) * mid)
    l:SetEndPoint("CENTER", v, math.cos(a1) * mid, math.sin(a1) * mid)
    -- section of this piece: angle measured clockwise from the top, with
    -- sections centered on their direction
    local deg = ((s - 0.5) * 360 / SEGMENTS + (n > 0 and 180 / n or 0)) % 360
    l.section = (n > 0) and (math.floor(deg / (360 / n)) % n + 1) or 0
    if n > 0 then l:Show() else l:Hide() end
  end
  -- section edges
  for k, e in ipairs(v.edges) do
    if k <= n and n > 1 then
      local a = sectionAngle(k, n) + math.pi / n   -- boundary between k and k-1
      e:SetStartPoint("CENTER", v, math.cos(a) * inner, math.sin(a) * inner)
      e:SetEndPoint("CENTER", v, math.cos(a) * outer, math.sin(a) * outer)
      e:Show()
    else
      e:Hide()
    end
  end
  -- icons on the band, names just outside
  local iconSize = math.max(18, math.min(40, band * 0.62))
  for k = 1, MAX_SLOTS do
    local ic, lb, slot = v.icons[k], v.labels[k], r.slots[k]
    local e = entries[k]
    if e then
      local a = sectionAngle(k, n)
      ic:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      ic:SetSize(iconSize, iconSize)
      ic:ClearAllPoints()
      ic:SetPoint("CENTER", v, "CENTER", math.cos(a) * mid, math.sin(a) * mid)
      ic:Show()
      lb:SetText(e.name)
      lb:ClearAllPoints()
      lb:SetPoint("CENTER", v, "CENTER", math.cos(a) * (outer + 14), math.sin(a) * (outer + 10))
      lb:Show()
      r.names[k] = e.name
      -- fallback click target on the icon
      if not useSecure then
        slot:SetAttribute("macrotext", e.macro)
        slot:SetSize(iconSize * 1.4, iconSize * 1.4)
        slot:ClearAllPoints()
        slot:SetPoint("CENTER", v, "CENTER", math.cos(a) * mid, math.sin(a) * mid)
        slot:Show()
      else
        slot:Hide()
      end
      r.pie:SetAttribute("ctpi-m" .. k, e.macro)
      r.pie:SetAttribute("ctpi-ux" .. k, math.cos(a))
      r.pie:SetAttribute("ctpi-uy" .. k, math.sin(a))
    else
      ic:Hide(); lb:Hide(); slot:Hide()
    end
  end
  r.pie:SetAttribute("ctpi-n", n)
  r.pie:SetAttribute("ctpi-dead", DEAD / PIE)   -- in the pie's 0..1 coordinates
  if useSecure and n > 0 then r.pie:Show() else r.pie:Hide() end
  paint(r, nil)
end

-- hover highlight while a ring is open
local hoverDriver = CreateFrame("Frame")
hoverDriver:SetScript("OnUpdate", function()
  for _, r in ipairs(ringFrames) do
    if r:IsShown() then
      local h = hoverSection(r)
      if h ~= r.hover then r.hover = h; paint(r, h) end
    end
  end
end)

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
-- (re)build: contents, layout and drivers. out of combat only.
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

local wrapped = {}

function ns.RebuildRadial()
  if InCombatLockdown() then pending = true; return end
  pending = false
  buildFrames()
  for _, r in ipairs(ringFrames) do UnregisterStateDriver(r, "visibility"); r:Hide() end
  if headerDriver then UnregisterStateDriver(header, "radial"); headerDriver = false end

  local db = ns.db
  local cfg = ns.ClassConfig()
  if not (db and db.enabled and db.radial.enabled and cfg) then return end

  -- secure path: wrap each pie's click once (needs working snippets)
  local useSecure = ns.secureAimOK and true or false
  if useSecure then
    for _, r in ipairs(ringFrames) do
      if not wrapped[r] then
        local ok = pcall(SecureHandlerWrapScript, r.pie, "OnClick", header, PIE_PRECLICK)
        if ok then wrapped[r] = true else useSecure = false end
      end
    end
  end

  local mod = MOD_COND[db.radial.mod or "shift"] or "mod:shift"
  local outer = db.radial.radius or 170

  -- default (empty condition) rings go last so specific ones win
  local order = {}
  for _, rg in ipairs(cfg.rings or {}) do
    if (rg.cond or "") ~= "" then order[#order + 1] = rg end
  end
  for _, rg in ipairs(cfg.rings or {}) do
    if (rg.cond or "") == "" then order[#order + 1] = rg end
  end

  local prior, headerCond = "", ""
  for i, rg in ipairs(order) do
    if i > MAX_RINGS then break end
    local r = ringFrames[i]
    local entries = {}
    for k = 1, MAX_SLOTS do   -- not ipairs: edited slot lists can have gaps
      local text = ((rg.slots or {})[k] or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" and (text:sub(1, 1) == "/" or spellKnown(text)) then
        local macro, spell = slotMacro(text)
        entries[#entries + 1] = {
          macro = macro,
          name = spell or text:match("^/%a+%s+(.+)$") or text,
          icon = spell and ns.SpellIcon(spell),
        }
      end
    end
    layoutRing(r, outer, entries, rg.name or "", useSecure)
    local groups = conditionGroups(rg.cond)
    if #entries > 0 then
      if useSecure then
        headerCond = headerCond .. clause(mod, groups, tostring(i))
      else
        RegisterStateDriver(r, "visibility", prior .. clause(mod, groups, "show") .. "hide")
      end
    elseif useSecure then
      headerCond = headerCond .. clause(mod, groups, "0")   -- empty ring still blocks later ones
    end
    prior = prior .. clause(mod, groups, "hide")
  end
  if useSecure and headerCond ~= "" then
    RegisterStateDriver(header, "radial", headerCond .. "0")
    headerDriver = true
  end
end

-- out of combat, every tick: the ring may only open while the camera is
-- actually locked (not while typing, in free-cursor mode, with a window
-- open, or with CTPI off). an already-open ring keeps itself open.
function ns.TickRadial()
  if InCombatLockdown() then return end
  local db = ns.db
  local block = (not db or not db.enabled) or ns.IsTyping() or ns.freeCursorHeld
    or (not IsMouselooking() and not ns.RadialOpen())
  block = block and true or nil
  if block == blockFlag then return end
  blockFlag = block
  if headerDriver then
    header:SetAttribute("ctpi-block", block)
    if block and ns.IsTyping() then
      SecureHandlerExecute(header, [[
        for i = 1, 6 do local r = self:GetFrameRef("ring" .. i); if r then r:Hide() end end
      ]])
    end
  end
end

-- ---------------------------------------------------------------------
-- cursor centering: 3.0.0 turned on CursorFreelookCentering, which parks
-- the cursor off-center on high-DPI screens. only put back what it changed.
-- ---------------------------------------------------------------------
function ns.ApplyFreelookCentering()
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
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
                     "UPDATE_SHAPESHIFT_FORMS", "PLAYER_TALENT_UPDATE", "LEARNED_SPELL_IN_TAB" }) do
  pcall(ev.RegisterEvent, ev, e)
end
local rebuildQueued = false
ev:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then ns.ApplyFreelookCentering() end
  if event == "PLAYER_REGEN_ENABLED" and not pending then return end
  -- spell / form events can come in bursts; rebuild once
  if rebuildQueued then return end
  rebuildQueued = true
  C_Timer.After(0.3, function() rebuildQueued = false; ns.RebuildRadial() end)
end)
