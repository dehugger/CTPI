local addonName, ns = ...

-- =====================================================================
-- CTPI / HUD.lua
-- Info arranged around screen center (works with or without the reticle):
--   resource arc  dotted arc of your main power (energy, rage, mana...)
--   GCD arc       a matching dotted arc, by default on the opposite side,
--                 that drains over each global cooldown
--   GCD swipe     the older round swipe centered on the reticle (optional
--                 style, and the automatic fallback if the GCD timing ever
--                 comes back secret)
-- Combo points (Core.lua) can ride as an inner ring inside the resource arc.
-- Everything only shows while mouselook is on, or while the settings panel
-- is open as a preview.
--
-- Secret values: every dot is a tiny StatusBar covering its own slice of
-- the range, so the power value goes straight into SetValue and is never
-- compared on our side. The GCD arc needs real numbers to animate; GCD
-- spell 61304 is on Blizzard's whitelist, but if its timing is ever secret
-- we switch to the swipe, which takes a duration object natively.
-- =====================================================================

local GCD_SPELL = 61304
local ARC_DOTS  = 30
local CIRCLE    = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WHITE     = "Interface\\Buttons\\WHITE8X8"

-- power types that sit at 0 when idle (everything else idles at full)
local IDLE_AT_ZERO = {
  RAGE = true, RUNIC_POWER = true, FURY = true, PAIN = true,
  INSANITY = true, LUNAR_POWER = true, MAELSTROM = true,
}
local OPPOSITE = { left = "right", right = "left", below = "above", above = "below" }

local hud, swipe, powerArc, gcdArc
local previewing, previewTicker, previewStart = false, nil, 0
local lastMax, lastType
local gcdStart, gcdDur, gcdSecret = 0, 0, false

-- ---------------------------------------------------------------------
-- arc geometry, shared with the combo ring in Core.lua
--   frac 0..1 runs from the arc's start end to its finish end:
--   bottom -> top on left / right, left -> right below / above.
--   angles in degrees, 0 = right, 90 = up.
-- ---------------------------------------------------------------------
local CENTER_ANGLE = { left = 180, right = 0, below = 270, above = 90 }

function ns.ArcPoint(side, span, radius, frac)
  local center = CENTER_ANGLE[side] or 180
  local a
  if side == "left" or side == "above" then
    a = center + span / 2 - span * frac
  else
    a = center - span / 2 + span * frac
  end
  local rad = math.rad(a)
  return math.cos(rad) * radius, math.sin(rad) * radius
end

local function gcdSide()
  local s = ns.db.gcd.side or "opposite"
  if s == "opposite" then return OPPOSITE[ns.db.power.side or "left"] or "right" end
  return s
end

-- ---------------------------------------------------------------------
-- build
-- ---------------------------------------------------------------------
local function makeDots(parent, n, bgAlpha)
  local dots = {}
  for i = 1, n do
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(WHITE)
    b:SetMinMaxValues(i - 1, i)
    b:SetValue(0)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0, 0, 0, bgAlpha)
    ns.RoundMask(bg)
    local fill = b:GetStatusBarTexture()
    if fill then ns.RoundMask(fill) end
    dots[i] = b
  end
  return dots
end

local function placeDots(dots, parent, side, span, radius, size)
  local n = #dots
  for i, b in ipairs(dots) do
    local x, y = ns.ArcPoint(side, span, radius, (i - 0.5) / n)
    b:SetSize(size, size)
    b:ClearAllPoints()
    b:SetPoint("CENTER", parent, "CENTER", x, y)
  end
end

local function gcdRemaining()
  if previewing then
    local r = 1 - (GetTime() - previewStart) / 1.5
    return r > 0 and r or 0
  end
  if gcdDur <= 0 then return 0 end
  local r = 1 - (GetTime() - gcdStart) / gcdDur
  return r > 0 and r or 0
end

function ns.BuildHUD()
  if hud then return end
  hud = CreateFrame("Frame", "CTPIHUD", UIParent)
  hud:SetFrameStrata("HIGH")   -- under the reticle (TOOLTIP strata)
  hud:SetSize(1, 1)
  hud:Hide()

  swipe = CreateFrame("Cooldown", "CTPIGCD", hud, "CooldownFrameTemplate")
  pcall(swipe.SetDrawBling, swipe, false)
  pcall(swipe.SetDrawEdge, swipe, false)
  pcall(swipe.SetHideCountdownNumbers, swipe, true)
  pcall(swipe.SetUseCircularEdge, swipe, true)
  pcall(swipe.SetSwipeTexture, swipe, CIRCLE)

  powerArc = CreateFrame("Frame", nil, hud)
  powerArc:SetAllPoints(hud)
  powerArc.dots = makeDots(powerArc, ARC_DOTS, 0.45)

  -- GCD arc: dot i covers [(i-1)/N, i/N] of the remaining-fraction, fed
  -- every frame while shown (OnUpdate only runs while visible)
  gcdArc = CreateFrame("Frame", nil, hud)
  gcdArc:SetAllPoints(hud)
  gcdArc.dots = makeDots(gcdArc, ARC_DOTS, 0.35)
  for i, b in ipairs(gcdArc.dots) do
    b:SetMinMaxValues((i - 1) / ARC_DOTS, i / ARC_DOTS)
    b:SetStatusBarColor(0.88, 0.90, 1.00, 0.95)
  end
  gcdArc:SetScript("OnUpdate", function(self)
    local rem = gcdRemaining()
    for _, b in ipairs(self.dots) do b:SetValue(rem) end
  end)
  gcdArc:Hide()

  ns.LayoutHUD()
end

function ns.LayoutHUD()
  if not hud then return end
  local db = ns.db
  local r, G, P = db.reticle, db.gcd, db.power
  local H = db.hud or {}

  -- the arcs move as a group with their own offset; the swipe stays on the reticle
  hud:ClearAllPoints()
  hud:SetPoint("CENTER", UIParent, "CENTER", (r.x or 0) + (H.x or 0), (r.y or 0) + (H.y or 0))

  swipe:ClearAllPoints()
  swipe:SetPoint("CENTER", UIParent, "CENTER", r.x or 0, r.y or 0)
  swipe:SetSize(G.size or 28, G.size or 28)
  pcall(swipe.SetSwipeColor, swipe, 1, 1, 1, G.alpha or 0.3)

  local span, radius, dot = P.span or 110, P.radius or 34, P.dot or 4
  local gap = H.gap or 9
  local pSide, gSide = P.side or "left", gcdSide()
  placeDots(powerArc.dots, hud, pSide, span, radius, dot)
  -- same side as the resource arc: stack the GCD one ring further out
  -- instead of drawing on top of it. opposite sides mirror at equal radius.
  local gRadius = (gSide == pSide) and (radius + gap) or radius
  placeDots(gcdArc.dots, hud, gSide, span, gRadius, dot)

  lastMax, lastType = nil, nil   -- force ranges + color to refresh
  if ns.LayoutCombo then ns.LayoutCombo() end   -- the combo ring follows the arc
end

-- ---------------------------------------------------------------------
-- GCD timing
-- ---------------------------------------------------------------------
local function readGCD()
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, info = pcall(C_Spell.GetSpellCooldown, GCD_SPELL)
    if ok and type(info) == "table" then return info.startTime, info.duration end
  elseif GetSpellCooldown then
    local ok, s, d = pcall(GetSpellCooldown, GCD_SPELL)
    if ok then return s, d end
  end
end

-- the swipe frame is always kept fed, so it is ready as a style or fallback
local function feedSwipe()
  if not swipe or previewing then return end
  if C_Spell and C_Spell.GetSpellCooldownDuration and swipe.SetCooldownFromDurationObject then
    local ok, d = pcall(C_Spell.GetSpellCooldownDuration, GCD_SPELL)
    if ok and d and pcall(swipe.SetCooldownFromDurationObject, swipe, d, true) then return end
  end
  local s, d = readGCD()
  local function has(v) return ns.IsSecret(v) or v ~= nil end
  if has(s) and has(d) then pcall(swipe.SetCooldown, swipe, s, d) end
end

local function onCooldownEvent()
  local s, d = readGCD()
  if ns.IsSecret(s) or ns.IsSecret(d) then
    gcdSecret = true
  elseif s ~= nil and d ~= nil then
    gcdSecret = false
    if d > 0 then gcdStart, gcdDur = s, d else gcdStart, gcdDur = 0, 0 end
  end
  feedSwipe()
end

-- ---------------------------------------------------------------------
-- resource arc
-- ---------------------------------------------------------------------
local function updatePower()
  local P = ns.db.power
  if not P.show then powerArc:Hide(); return end

  local ok, ptype, ptoken = pcall(UnitPowerType, "player")
  if not ok or ns.IsSecret(ptype) or ptype == nil then powerArc:Hide(); return end
  if ns.IsSecret(ptoken) then ptoken = nil end

  local max = UnitPowerMax("player", ptype)
  if ns.IsSecret(max) or not max or max <= 0 then powerArc:Hide(); return end
  local cur = UnitPower("player", ptype)

  if max ~= lastMax then
    lastMax = max
    for i, b in ipairs(powerArc.dots) do
      b:SetMinMaxValues((i - 1) * max / ARC_DOTS, i * max / ARC_DOTS)
    end
  end
  if ptype ~= lastType then
    lastType = ptype
    local c = PowerBarColor and ((ptoken and PowerBarColor[ptoken]) or PowerBarColor[ptype])
    local cr, cg, cb = 1, 0.9, 0.3
    if type(c) == "table" and c.r then cr, cg, cb = c.r, c.g, c.b end
    for _, b in ipairs(powerArc.dots) do b:SetStatusBarColor(cr, cg, cb, 0.95) end
  end
  for _, b in ipairs(powerArc.dots) do b:SetValue(cur) end

  local show
  if not P.hideIdle or previewing or InCombatLockdown() then
    show = true
  elseif ns.IsSecret(cur) then
    show = false
  elseif ptoken and IDLE_AT_ZERO[ptoken] then
    show = cur > 0
  else
    show = cur < max
  end
  if show then powerArc:Show() else powerArc:Hide() end
end

-- ---------------------------------------------------------------------
-- per-tick update (from the reconcile loop in Core.lua)
-- ---------------------------------------------------------------------
local function updateGCDVisibility()
  local G = ns.db.gcd
  local style = G.style or "arc"
  local useArc   = G.show and style == "arc" and not gcdSecret
  local useSwipe = G.show and not useArc
  if useSwipe then swipe:Show() else swipe:Hide() end
  if useArc and (gcdRemaining() > 0 or (G.track and InCombatLockdown()) or previewing) then
    gcdArc:Show()
  else
    gcdArc:Hide()
  end
end

function ns.UpdateHUD(looking)
  if not hud or not ns.db then return end
  local vis = (looking or previewing) and true or false
  if vis then hud:Show() else hud:Hide(); return end
  updateGCDVisibility()
  updatePower()
end

-- settings-panel preview: loop a fake 1.5s GCD so things can be tuned
local function previewPulse()
  previewStart = GetTime()
  swipe:SetCooldown(previewStart, 1.5)
end

function ns.SetHUDPreview(on)
  previewing = on and true or false
  if previewTicker then previewTicker:Cancel(); previewTicker = nil end
  if not hud then return end
  if previewing then
    previewPulse()
    previewTicker = C_Timer.NewTicker(2, previewPulse)
  else
    swipe:SetCooldown(0, 0)
    onCooldownEvent()
  end
  ns.LayoutHUD()
  ns.UpdateHUD(IsMouselooking())
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "SPELL_UPDATE_COOLDOWN")
pcall(ev.RegisterEvent, ev, "ACTIONBAR_UPDATE_COOLDOWN")
ev:SetScript("OnEvent", onCooldownEvent)
