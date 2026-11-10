local addonName, ns = ...

-- =====================================================================
-- CTPI / Look.lua
-- "What am I looking at, and what happens if I click it?"
--
--   compact (default)  two short lines under the reticle: the name, colored
--                      by what kind of thing it is, and a click hint.
--                      repainted every tick straight from the soft-target
--                      tokens, so it cant get stuck on something old.
--   full               the games own unit tooltip at the same spot
--   off
--
-- Only the soft-target tokens are read. 1.x also fell back to "mouseover"
-- and "target", and since your hard target always "exists" that is what
-- left old stuff on screen after you looked away.
--
-- Secret values: UnitExists / UnitName / UnitIsDead etc can be secret in
-- combat. names go straight into SetText (allowed); anything we would
-- have to branch on is only trusted when it is a plain value.
-- =====================================================================

local TOKENS = { "softinteract", "softenemy", "softfriend" }

local COLORS = {
  softenemy    = { 1.00, 0.40, 0.34 },
  softfriend   = { 0.45, 1.00, 0.45 },
  softinteract = { 1.00, 0.82, 0.25 },
}

local function plainTrue(v)
  return (not ns.IsSecret(v)) and v and true or false
end

-- best token for "what the reticle is on". a token we KNOW exists beats one
-- we cant read; returns token, unsure
local function resolve()
  local maybe
  for _, t in ipairs(TOKENS) do
    local e = UnitExists(t)
    if ns.IsSecret(e) then
      maybe = maybe or t
    elseif e then
      return t, false
    end
  end
  if maybe then return maybe, true end
end
ns.ResolveLook = resolve

-- ---------------------------------------------------------------------
-- click hint. styles (db.tooltip.hintStyle):
--   "icons"      mouse-button icon + action cursor icon + a short word
--   "iconsonly"  just the icons (keys still show as text)
--   "text"       the old "click: attack" wording
-- icons are the game's own cursor art, so they match what the hand cursor
-- would show if it werent hidden by mouselook.
-- ---------------------------------------------------------------------
local ACTION_ICON = {
  attack   = "Interface\\Cursor\\Attack",
  talk     = "Interface\\Cursor\\Speak",
  loot     = "Interface\\Cursor\\Pickup",
  use      = "Interface\\Cursor\\Interact",
  interact = "Interface\\Cursor\\Interact",
}
local ACTION_WORD = { attack = "Attack", talk = "Talk", loot = "Loot", use = "Use", interact = "Interact" }
local BUTTON_ATLAS = { click = "NPE_LeftClick", ["right-click"] = "NPE_RightClick" }
local LOCK_ICON = "Interface\\PetBattles\\PetBattle-LockIcon"

local function iconSize()
  return math.floor((ns.db.tooltip.fontSize or 14) * 1.35 + 0.5)
end
local function tex(path, s) return "|T" .. path .. ":" .. s .. ":" .. s .. "|t" end
local function atlas(name, s) return "|A:" .. name .. ":" .. s .. ":" .. s .. "|a" end

-- what the interact button (INTERACTMOUSEOVER) will do to this token
local function actionFor(token)
  if token == "softenemy" then return "attack" end
  if token ~= "softinteract" then return nil end
  if UnitIsGameObject and plainTrue(UnitIsGameObject(token)) then return "use" end
  if plainTrue(UnitIsDead(token)) then return "loot" end
  if plainTrue(UnitIsPlayer(token)) then return "interact" end
  return "talk"
end

local function clickHint(token)
  local db = ns.db
  local style = db.tooltip.hintStyle or "icons"
  local s = iconSize()
  local parts = {}
  local btn = ns.InteractButtonLabel and ns.InteractButtonLabel()
  local act = btn and actionFor(token)
  local enemyMode = token == "softenemy" and ns.EnemyClickMode and ns.EnemyClickMode()
  local spellHint = enemyMode and ns.EnemyClickHint and ns.EnemyClickHint()
  local hardLocked = enemyMode and ns.HardLocked and ns.HardLocked()
  if hardLocked then
    -- locked on your target: clicks wont switch to this one
    if style == "text" then
      parts[#parts + 1] = "locked   right-click: unlock"
    else
      local p = tex(LOCK_ICON, s)
      if style == "icons" then p = p .. " Locked" end
      parts[#parts + 1] = p
      local u = atlas("NPE_RightClick", s)
      if style == "icons" then u = u .. " Unlock" end
      parts[#parts + 1] = u
    end
  elseif spellHint then
    -- context click: show what a click / shift-click will actually cast
    local function one(id)
      local icon = ns.SpellIcon(id)
      local name = ns.SpellName(id)
      if style == "text" then return name:lower() end
      local t = icon and tex(icon, s) or ""
      if style == "icons" then t = t .. " " .. name end
      return t
    end
    local main = (style == "text" and "click: " or atlas("NPE_LeftClick", s)) .. one(spellHint.main)
    parts[#parts + 1] = main
    if spellHint.shift then
      parts[#parts + 1] = (style == "text" and "shift: " or "|cFFc8a25eShift|r ") .. one(spellHint.shift)
    end
  elseif enemyMode then
    -- left-click locks (and maybe attacks) instead of plain interact
    local word = (enemyMode == "lockattack") and "Lock + attack" or "Lock"
    if style == "text" then
      parts[#parts + 1] = "click: " .. word:lower()
    else
      local p = atlas("NPE_LeftClick", s) .. tex(LOCK_ICON, s)
      if enemyMode == "lockattack" then p = p .. tex(ACTION_ICON.attack, s) end
      if style == "icons" then p = p .. " " .. word end
      parts[#parts + 1] = p
    end
  elseif act then
    if style == "text" then
      parts[#parts + 1] = btn .. ": " .. act:lower()
    else
      local how = BUTTON_ATLAS[btn] and atlas(BUTTON_ATLAS[btn], s) or ("|cFFc8a25e" .. btn .. "|r ")
      local p = how .. tex(ACTION_ICON[act], s)
      if style == "icons" then p = p .. " " .. ACTION_WORD[act] end
      parts[#parts + 1] = p
    end
  end
  if token == "softenemy" and not enemyMode and db.lockKey and db.lockKey ~= "" then -- (click locks in enemy mode)
    if style == "text" then
      parts[#parts + 1] = db.lockKey:lower() .. ": lock"
    else
      parts[#parts + 1] = tex(LOCK_ICON, s) .. " |cFFc8a25e" .. db.lockKey .. "|r"
    end
  end
  return table.concat(parts, "      ")
end

-- ---------------------------------------------------------------------
-- compact label
-- ---------------------------------------------------------------------
local label, nameFS, hintFS
local previewing = false

local function outline(fs)
  local f, s = fs:GetFont()
  if f then fs:SetFont(f, s, "OUTLINE") end
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.9)
end

local plate   -- optional dark backdrop behind the two lines

function ns.BuildLook()
  if label then return end
  label = CreateFrame("Frame", "CTPILookLabel", UIParent)
  label:SetFrameStrata("TOOLTIP")
  label:SetSize(320, 36)
  plate = label:CreateTexture(nil, "BACKGROUND")
  plate:SetColorTexture(0, 0, 0, 0.5)
  nameFS = label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameFS:SetPoint("TOP", label, "TOP", 0, 0)
  outline(nameFS)
  hintFS = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hintFS:SetPoint("TOP", nameFS, "BOTTOM", 0, -4)
  hintFS:SetTextColor(0.88, 0.88, 0.88)
  outline(hintFS)
  plate:SetPoint("TOP", nameFS, "TOP", 0, 5)
  plate:SetPoint("BOTTOM", hintFS, "BOTTOM", 0, -5)
  label:Hide()
  ns.LayoutLook()
end

-- size the backdrop to the wider of the two lines. string widths can come
-- back secret when the name is secret; then fall back to a fixed width.
local function fitPlate()
  if not plate then return end
  if not ns.db.tooltip.backdrop then plate:Hide(); return end
  local w1, w2 = nameFS:GetStringWidth(), hintFS:GetStringWidth()
  local w
  if ns.IsSecret(w1) or ns.IsSecret(w2) then
    w = 240
  else
    w = math.max(w1 or 0, w2 or 0)
  end
  plate:SetWidth(w + 20)
  plate:Show()
end

function ns.LayoutLook()
  if not label then return end
  local T = ns.db.tooltip
  local size = T.fontSize or 14
  local font = (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"
  nameFS:SetFont(font, size, "OUTLINE")
  hintFS:SetFont(font, math.max(9, math.floor(size * 0.85 + 0.5)), "OUTLINE")
  label:SetWidth(math.max(320, size * 24))
  resetDrawn()   -- settings changed: redraw next tick
  label:ClearAllPoints()
  label:SetPoint("TOP", UIParent, "CENTER", T.x or 0, T.y or -24)
end

-- ---------------------------------------------------------------------
-- full mode (game tooltip)
-- ---------------------------------------------------------------------
local ttOwner = CreateFrame("Frame", "CTPITooltipAnchor", UIParent)
local lastKey, lastPaint = nil, 0

local function hideFull()
  if GameTooltip:GetOwner() == ttOwner then GameTooltip:Hide() end
  lastKey = nil
end

local function paintFull(token, unsure)
  local guid = UnitGUID(token)
  local now = GetTime()
  local key, repaint
  if unsure or ns.IsSecret(guid) then
    key = "secret:" .. token        -- cant compare, so repaint on a timer
    repaint = (key ~= lastKey) or (now - lastPaint) >= 0.3
  elseif guid then
    key = guid
    repaint = (key ~= lastKey) or (now - lastPaint) >= 1.0
  else
    hideFull(); return
  end
  if not repaint then return end
  lastKey, lastPaint = key, now
  local T = ns.db.tooltip
  GameTooltip:SetOwner(ttOwner, "ANCHOR_NONE")
  GameTooltip:SetClampedToScreen(true)
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("TOP", UIParent, "CENTER", T.x or 0, T.y or -24)
  GameTooltip:SetUnit(token)
  if (GameTooltip:NumLines() or 0) > 0 then GameTooltip:Show() else GameTooltip:Hide() end
end

-- ---------------------------------------------------------------------
-- update (called every reconcile tick and on soft-target events)
-- ---------------------------------------------------------------------
local lastDbg
-- what's currently drawn, so an unchanged label isnt re-laid-out every tick
-- (SetText with inline icons is the expensive bit)
local drawnName, drawnToken, drawnSig

local function resetDrawn() drawnName, drawnToken, drawnSig = nil, nil, nil end

local function hintSig(token)
  local em = (token == "softenemy" and ns.EnemyClickMode) and ns.EnemyClickMode() or ""
  local btn = ns.InteractButtonLabel and ns.InteractButtonLabel() or ""
  local h = (token == "softenemy" and ns.EnemyClickHint) and ns.EnemyClickHint()
  local hs = h and (tostring(h.main) .. "/" .. tostring(h.shift)) or ""
  if token == "softenemy" and ns.HardLocked and ns.HardLocked() then hs = hs .. "|L" end
  return token .. "|" .. (actionFor(token) or "") .. "|" .. tostring(em) .. "|" .. btn .. "|" .. hs
end

function ns.UpdateLook(looking)
  if not label or not ns.db then return end
  local mode = ns.db.tooltip.mode or "compact"
  local token, unsure
  if looking and mode ~= "off" then token, unsure = resolve() end

  if ns.debug and token ~= lastDbg then   -- /ctpi debug: report what resolved
    lastDbg = token
    local n = token and UnitName(token)
    if ns.IsSecret(n) then n = "<secret>" end
    print("|cFFc8a25eCTPI|r look -> " .. (token and (token .. " = " .. tostring(n)) or "nothing"))
  end

  -- compact
  if mode == "compact" and token then
    local name = UnitName(token)
    if ns.IsSecret(name) or name then
      local changed = false
      if ns.IsSecret(name) then
        nameFS:SetText(name); drawnName = nil; changed = true   -- cant compare a secret
      elseif name ~= drawnName then
        nameFS:SetText(name); drawnName = name; changed = true
      end
      if token ~= drawnToken then
        local c = COLORS[token]
        nameFS:SetTextColor(c[1], c[2], c[3])
        drawnToken = token
      end
      local sig = hintSig(token)
      if sig ~= drawnSig then
        hintFS:SetText(clickHint(token)); drawnSig = sig; changed = true
      end
      if changed then fitPlate() end
      label:Show()
    else
      label:Hide(); resetDrawn()
    end
  elseif mode == "compact" and previewing then
    resetDrawn()
    nameFS:SetText("Something you're looking at")
    local c = COLORS.softenemy
    nameFS:SetTextColor(c[1], c[2], c[3])
    hintFS:SetText(clickHint("softenemy"))
    fitPlate()
    label:Show()
  else
    if label:IsShown() then label:Hide(); resetDrawn() end
  end

  -- full
  if mode == "full" and token then
    paintFull(token, unsure)
  else
    hideFull()
  end
end

function ns.SetLookPreview(on)
  previewing = on and true or false
  ns.LayoutLook()
  ns.UpdateLook(IsMouselooking())
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED",
                     "PLAYER_SOFT_INTERACT_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function()
  lastKey = nil   -- full mode: force a repaint
  if ns.db then ns.UpdateLook(IsMouselooking()) end
end)
