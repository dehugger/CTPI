local addonName, ns = ...

-- labels shown in Game Menu > Key Bindings (must be globals)
BINDING_HEADER_CTPI            = "Coffee's Touchpad Improvements"
BINDING_NAME_CTPI_TOGGLE       = "Toggle CTPI (master)"
BINDING_NAME_CTPI_FREECURSOR   = "Toggle free cursor (CTPI)"

-- =====================================================================
-- Coffee's Touchpad Improvements (CTPI) / Core.lua
-- Always-on mouselook engine + reticle + cursor-release logic.
--
-- DESIGN
--   Every ~throttle seconds we ask one question: "should the cursor be
--   free right now?" (typing, a panel is open, placing a ground spell,
--   dragging something...). If yes -> MouselookStop. If no -> MouselookStart.
--   That single reconciliation loop also re-engages mouselook after a
--   click drops it, so re-engaging is free.
--
--   MouselookStart/Stop/IsMouselooking are NOT protected, so this whole
--   file is combat-safe. The click bindings live in Secure.lua and are the
--   only part that has to respect combat lockdown.
-- =====================================================================

local MouselookStart, MouselookStop, IsMouselooking =
      MouselookStart, MouselookStop, IsMouselooking

-- ---------------------------------------------------------------------
-- Frames whose presence means "the user needs a normal cursor".
-- Users can add their own via /ctpi block <FrameName>.
-- ---------------------------------------------------------------------
ns.blockFrames = {
  "GameMenuFrame", "MerchantFrame", "MailFrame", "OpenMailFrame",
  "BankFrame", "WorldMapFrame", "QuestFrame", "QuestLogFrame",
  "GossipFrame", "TradeFrame", "CharacterFrame", "SpellBookFrame",
  "TalentFrame", "PVPParentFrame", "FriendsFrame", "WhoFrame",
  "TaxiFrame", "LootFrame", "AuctionFrame", "TradeSkillFrame",
  "CraftFrame", "ClassTrainerFrame", "MacroFrame", "OptionsFrame",
  "VideoOptionsFrame", "InterfaceOptionsFrame", "GuildRegistrarFrame",
  "PetStableFrame", "ItemTextFrame", "StackSplitFrame",
  "KeyBindingFrame", "SettingsPanel", "ChatConfigFrame",
  "ColorPickerFrame", "DressUpFrame", "ReadyCheckFrame",
  -- modern / Forever UI names (any that dont exist on a build are skipped)
  "PlayerSpellsFrame", "ClassTalentFrame", "ProfessionsBookFrame",
  "PVEFrame", "AuctionHouseFrame", "ProfessionsFrame",
  "ProfessionsCustomerOrdersFrame", "CommunitiesFrame", "GuildFrame",
  "CollectionsJournal", "EncounterJournal", "AchievementFrame",
  "CalendarFrame", "InspectFrame", "ChannelFrame", "HelpFrame",
  "EditModeManagerFrame", "QuickKeybindFrame", "BarberShopFrame",
  "WardrobeFrame", "TransmogFrame", "ItemSocketingFrame",
  "ItemUpgradeFrame", "PlayerChoiceFrame", "GenericTraitFrame",
  "BankPanel", "AccountBankPanel", "ContainerFrameCombinedBags",
  "AddonList",
  "CTPIConfigFrame",   -- our own config window
}

-- IsVisible, not IsShown: modern UI has child panels (BankPanel etc) that
-- stay "shown" while their parent window is closed, which read as always-open
local function visible(f)
  if type(f) ~= "table" then return false end
  if f.IsVisible then return f:IsVisible() and true or false end
  if f.IsShown then return f:IsShown() and true or false end
  return false
end
ns.IsFrameVisible = visible

local function anyStaticPopup()
  for i = 1, 4 do
    local f = _G["StaticPopup"..i]
    if visible(f) then return true end
  end
  return false
end

local function anyBagOpen()
  for i = 1, 13 do
    local f = _G["ContainerFrame"..i]
    if visible(f) then return true end
  end
  return false
end

-- temporary hold-to-free flag, toggled by the binding in Bindings.xml
ns.freeCursorHeld = false

-- ---------------------------------------------------------------------
-- Focus-loss heuristic. WoW exposes no window-focus event, so we infer it.
-- In windowed / borderless mode (where OnUpdate keeps firing while we're
-- tabbed out) the FPS gets pinned to the background cap (maxfpsbk); we watch
-- for that and free the cursor so the OS can use it in another app. Keyed off
-- maxfpsbk so it catches the throttle, not a normal combat dip, and suppressed
-- around loading screens. Fullscreen alt-tab freezes OnUpdate entirely, so
-- this code never runs there and never needs to.
-- ---------------------------------------------------------------------
local focusLost = false
local lowSince = nil
local inLoadingScreen = false
local suppressUntil = 0

local function focusThreshold()
  local db = ns.db
  if db and db.focusFpsThreshold and db.focusFpsThreshold > 0 then
    return db.focusFpsThreshold
  end
  local bk = tonumber(ns.GetCVar("maxfpsbk")) or 0  -- background FPS cap
  if bk > 0 then return math.min(bk + 4, 20) end
  return 12
end

local function updateFocusState()
  local db = ns.db
  if not (db and db.unlockOnFocusLoss) or inLoadingScreen or GetTime() < suppressUntil then
    focusLost, lowSince = false, nil
    return
  end
  local fps = GetFramerate() or 60
  if fps < focusThreshold() then
    local now = GetTime()
    lowSince = lowSince or now
    if (now - lowSince) >= (db.focusDwell or 1.25) then focusLost = true end
  else
    focusLost, lowSince = false, nil
  end
end
ns.SetLoadingScreen = function(v) inLoadingScreen = v end
ns.SuppressFocusFor = function(sec) suppressUntil = GetTime() + (sec or 3) end

-- returns true + a short reason when the cursor should be free
local function shouldFreeCursor()
  local db = ns.db
  if not db.enabled then return true, "master toggle is off" end
  if ns.freeCursorHeld then return true, "free-cursor key is toggled" end
  if focusLost then return true, "window focus lost (low fps heuristic)" end
  if ns.SpellTargeting() then return true, "placing a ground spell" end
  if ns.IsTyping() then return true, "typing / an edit box has focus" end
  if ns.CursorBusy() then return true, "something is on the cursor" end
  if anyStaticPopup() then return true, "a popup is open" end
  if anyBagOpen() then return true, "a bag is open" end
  -- NPC dialogs stay locked while the dialog keys are active (Dialog.lua)
  local skip = ns.DialogSkipFrames and ns.DialogSkipFrames()
  for _, name in ipairs(ns.blockFrames) do
    if not (skip and skip[name]) and visible(_G[name]) then return true, "frame open: " .. name end
  end
  if db.extraBlock then
    for name in pairs(db.extraBlock) do
      if visible(_G[name]) then return true, "frame open (custom): " .. name end
    end
  end
  return false, nil
end
ns.ShouldFreeCursor = shouldFreeCursor
ns.FocusThreshold = function() return focusThreshold() end

-- ---------------------------------------------------------------------
-- Reticle
--   Screen center is where mouselook locks the cursor, which is exactly
--   where INTERACTMOUSEOVER and soft-target resolve. (0,0) marks the real
--   aim point. Users can offset it, but center is the true target point.
-- ---------------------------------------------------------------------
local reticle
local combo

local function clearParts()
  if reticle and reticle.parts then
    for _, t in ipairs(reticle.parts) do
      t:Hide()
      t:SetParent(nil)
    end
  end
  if reticle then reticle.parts = {} end
end

local function roundMask(tex)
  -- round off a square via a circular mask; if masks arent supported on
  -- this client it stays square instead of throwing
  pcall(function()
    local mask = tex:GetParent():CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
                    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
  end)
end

ns.RoundMask = roundMask

-- (re)build the reticle textures for the current shape/size/color
local function buildReticleParts()
  if not reticle then return end
  local r = ns.db.reticle
  clearParts()

  local function part(w, h, px, py, round)
    local t = reticle:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(r.r, r.g, r.b, r.alpha)
    t:SetSize(w, h)
    t:SetPoint("CENTER", reticle, "CENTER", px or 0, py or 0)
    table.insert(reticle.parts, t)
    if round then roundMask(t) end
    return t
  end

  local size = r.size or 6
  if r.shape == "cross" then
    local len = size * 3
    local th  = math.max(2, math.floor(size * 0.34))
    part(len, th)   -- horizontal bar
    part(th, len)   -- vertical bar
  elseif r.shape == "ticks" then
    local len = math.max(3, size * 1.6)
    local th  = math.max(2, math.floor(size * 0.34))
    local off = math.max(2, size) + len / 2
    part(th, len, 0,  off)   -- top
    part(th, len, 0, -off)   -- bottom
    part(len, th,  off, 0)   -- right
    part(len, th, -off, 0)   -- left
  else -- "dot"
    part(size, size, 0, 0, true)
  end
end

local function buildReticleFrame()
  if reticle then return end
  reticle = CreateFrame("Frame", "CTPIReticle", UIParent)
  reticle:SetFrameStrata("TOOLTIP")
  reticle:SetSize(64, 64)   -- container; parts are centered within
  reticle.parts = {}
  reticle:Hide()
end

-- full refresh: geometry + position. called on login and on any config change.
local function refreshReticle()
  if not reticle then return end
  local r = ns.db.reticle
  buildReticleParts()
  reticle:ClearAllPoints()
  reticle:SetPoint("CENTER", UIParent, "CENTER", r.x or 0, r.y or 0)
  if ns.LayoutCombo then ns.LayoutCombo() end   -- ring inside the arc, or row above
  if ns.LayoutHUD then ns.LayoutHUD() end
  if ns.LayoutLook then ns.LayoutLook() end
end
ns.RefreshReticle = refreshReticle

local function updateReticle(looking)
  if not reticle then return end
  local vis = (looking or ns.reticlePreview) and ns.db.reticle.show
  if vis then reticle:Show() else reticle:Hide() end
end

-- keep the reticle visible while the config panel is open (mouselook is off
-- then, so it would normally hide) so changes preview live
-- (also drives the HUD + look-label previews)
function ns.PreviewReticle(on)
  ns.reticlePreview = on and true or false
  updateReticle(IsMouselooking())
  if ns.SetHUDPreview then ns.SetHUDPreview(on) end
  if ns.SetLookPreview then ns.SetLookPreview(on) end
end

-- ---------------------------------------------------------------------
-- Combo points (rogue / druid). A row of pips at the reticle. Reads both
-- the modern player-power value and the old per-target GetComboPoints
-- (whichever this client fills, see Compat.lua). Polled in the reconcile
-- loop (no event-name guessing across client builds).
-- ---------------------------------------------------------------------
local COMBO_MAX = 5
local lastCP = -1

local function buildComboFrame()
  if combo then return end
  combo = CreateFrame("Frame", "CTPIComboFrame", UIParent)
  combo:SetFrameStrata("TOOLTIP")
  combo:SetSize(64, 12)
  combo.pips = {}
  local pip, gap = 7, 4
  local totalW = COMBO_MAX * pip + (COMBO_MAX - 1) * gap
  -- each pip is a tiny StatusBar spanning [i-1, i]. feeding the same combo
  -- count to every pip fills the first N and leaves the rest empty with no
  -- comparisons on our side, so it keeps working when Forever hands us a
  -- secret number (StatusBar:SetValue accepts those natively).
  for i = 1, COMBO_MAX do
    local b = CreateFrame("StatusBar", nil, combo)
    b:SetSize(pip, pip)
    local x = -totalW / 2 + (i - 1) * (pip + gap) + pip / 2
    b:SetPoint("CENTER", combo, "CENTER", x, 0)
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    b:SetStatusBarColor(0.95, 0.25, 0.2, 0.95)        -- lit
    b:SetMinMaxValues(i - 1, i)
    b:SetValue(0)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0.35, 0.35, 0.35, 0.35)          -- empty
    roundMask(bg)
    local fill = b:GetStatusBarTexture()
    if fill then roundMask(fill) end
    combo.pips[i] = b
  end
  combo:Hide()
end

-- "ring": an inner arc just inside the resource arc (same side + span, so
-- each pip lines up with a stretch of the energy dots). "row": the old
-- horizontal row above the reticle.
local function layoutCombo()
  if not combo then return end
  local db = ns.db
  local r = db.reticle
  combo:ClearAllPoints()
  if (db.combo.layout or "ring") == "ring" then
    local H = db.hud or {}   -- the ring moves with the arcs
    combo:SetPoint("CENTER", UIParent, "CENTER", (r.x or 0) + (H.x or 0), (r.y or 0) + (H.y or 0))
    local P = db.power
    local gap = (db.hud and db.hud.gap) or 9      -- one ring inside the resource arc
    local radius = math.max(12, (P.radius or 34) - gap)
    for i = 1, COMBO_MAX do
      local x, y = ns.ArcPoint(P.side or "left", P.span or 110, radius, (i - 0.5) / COMBO_MAX)
      local b = combo.pips[i]
      b:SetSize(6, 6)
      b:ClearAllPoints()
      b:SetPoint("CENTER", combo, "CENTER", x, y)
    end
  else
    combo:SetPoint("CENTER", UIParent, "CENTER", r.x or 0, (r.y or 0) + 24)
    local pip, gap = 7, 4
    local totalW = COMBO_MAX * pip + (COMBO_MAX - 1) * gap
    for i = 1, COMBO_MAX do
      local b = combo.pips[i]
      b:SetSize(pip, pip)
      b:ClearAllPoints()
      b:SetPoint("CENTER", combo, "CENTER", -totalW / 2 + (i - 1) * (pip + gap) + pip / 2, 0)
    end
  end
end
ns.LayoutCombo = layoutCombo

local function updateCombo()
  if not combo then return end
  if not (ns.db and ns.db.combo and ns.db.combo.show) then combo:Hide(); lastCP = -1; return end
  local cp = ns.GetComboPoints()
  if ns.IsSecret(cp) then
    -- cant read it, can only display it. push it to the pips every tick and
    -- show the row while in combat (which is when secrets show up anyway)
    lastCP = -1
    for i = 1, COMBO_MAX do combo.pips[i]:SetValue(cp) end
    if InCombatLockdown() then combo:Show() else combo:Hide() end
    return
  end
  if ns.reticlePreview and cp == 0 then   -- settings preview: 3 sample points
    lastCP = -1
    for i = 1, COMBO_MAX do combo.pips[i]:SetValue(3) end
    combo:Show()
    return
  end
  if cp ~= lastCP then
    lastCP = cp
    for i = 1, COMBO_MAX do combo.pips[i]:SetValue(cp) end
  end
  if cp > 0 then combo:Show() else combo:Hide() end
end
ns.UpdateCombo = updateCombo

-- (the look-at label / tooltip lives in Look.lua)

-- ---------------------------------------------------------------------
-- The reconciliation loop
-- ---------------------------------------------------------------------
local warnedML = false
local function engage()
  if not IsMouselooking() then MouselookStart() end
  if ns.debug and not warnedML and not IsMouselooking() then
    warnedML = true
    print("|cFFc8a25eCTPI|r MouselookStart() was called but IsMouselooking() is still false")
  end
  updateReticle(true)
  ns.ApplyClickBindings()   -- Secure.lua (no-op in combat)
end

local function disengage()
  if IsMouselooking() then MouselookStop() end
  updateReticle(false)
  if ns.UpdateLook then ns.UpdateLook(false) end
  ns.RemoveClickBindings()  -- Secure.lua (no-op in combat)
end

local accum = 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(self, elapsed)
  accum = accum + elapsed
  if accum < (ns.db and ns.db.throttle or 0.05) then return end
  accum = 0
  if not ns.db then return end
  updateFocusState()        -- heuristic window-focus check (cheap)
  local free, why = shouldFreeCursor()
  if ns.debug and why ~= ns.lastWhy then   -- /ctpi debug: narrate state changes
    ns.lastWhy = why
    print("|cFFc8a25eCTPI|r cursor " .. (free and ("free: " .. why) or "locked (mouselook)"))
  end
  if free then
    if IsMouselooking() then disengage() end
  else
    if not IsMouselooking() then engage() end
  end
  local looking = IsMouselooking()
  if ns.UpdateLook then ns.UpdateLook(looking) end   -- Look.lua
  if ns.UpdateHUD then ns.UpdateHUD(looking) end     -- HUD.lua
  updateCombo()           -- poll combo points (cheap; no event-name guessing)
end)

function ns.ForceReconcile() accum = 999 end

-- re-apply the mouse bindings to match current state (out of combat)
function ns.RefreshBindings()
  if InCombatLockdown() then return end
  if IsMouselooking() then ns.ApplyClickBindings() else ns.RemoveClickBindings() end
end

-- ---------------------------------------------------------------------
-- Soft-target: looking at a mob auto-targets it. Secure cvars -> SetCVar
-- only, never in combat. Wrapped in pcall in case a cvar is absent on a
-- given client build.
-- ---------------------------------------------------------------------
local function setCVarSafe(name, value)
  pcall(ns.SetCVar, name, value)
end

local softTargetPending = false

local function applySoftTarget()
  if InCombatLockdown() then
    softTargetPending = true   -- secure cvars cant be set in combat; do it on exit
    return
  end
  softTargetPending = false
  local db = ns.db

  -- enemy soft-target -> softenemy token (look to target a mob)
  if db.softTargetEnemy then
    setCVarSafe("SoftTargetEnemy", 3)        -- 0 off / 1 gamepad / 2 KBM / 3 always
    setCVarSafe("SoftTargetIconEnemy", 1)    -- reticle marker over the soft target
    setCVarSafe("SoftTargetNameplateEnemy", 1)
  else
    setCVarSafe("SoftTargetEnemy", 0)
    setCVarSafe("SoftTargetIconEnemy", 0)
    setCVarSafe("SoftTargetNameplateEnemy", 0)
  end

  -- friend soft-target -> softfriend token (look to heal an ally). independent
  -- of enemy on purpose: a healer can run friend-only. companion cvars are
  -- pcall-guarded since not every build exposes the friend icon/nameplate ones.
  if db.softTargetFriend then
    setCVarSafe("SoftTargetFriend", 3)
    setCVarSafe("SoftTargetIconFriend", 1)
  else
    setCVarSafe("SoftTargetFriend", 0)
    setCVarSafe("SoftTargetIconFriend", 0)
  end

  -- interact soft-target -> softinteract token (vendors / nodes / mailboxes).
  -- powers left-click interact, so this stays on by default even for healers.
  if db.softTargetInteract then
    setCVarSafe("SoftTargetInteract", 3)
    setCVarSafe("SoftTargetIconInteract", 1)
    setCVarSafe("SoftTargetIconGameObject", 1)   -- modern clients: icon on nodes / mailboxes
  else
    setCVarSafe("SoftTargetInteract", 0)
    setCVarSafe("SoftTargetIconInteract", 0)
    setCVarSafe("SoftTargetIconGameObject", 0)
  end
end
ns.ApplySoftTarget = applySoftTarget

-- ---------------------------------------------------------------------
-- SavedVariables + events
-- ---------------------------------------------------------------------
local DB_VERSION = 8

local defaults = {
  enabled      = true,
  throttle     = 0.05,
  extraBlock   = {},
  -- mouse buttons while mouselooking: INTERACTMOUSEOVER | MOVEFORWARD (hold
  -- to run) | TOGGLEAUTORUN (tap to run) | "" (nothing). see Secure.lua
  leftAction   = "INTERACTMOUSEOVER",
  leftStopsAutorun = true,         -- while autorunning, left-click stops it (Secure.lua)
  leftEnemy    = "interact",       -- left-click on enemies: interact | lock | lockattack
  rightAction  = "TOGGLEAUTORUN",
  softTargetEnemy    = true,       -- look-to-target a mob (softenemy)
  softTargetFriend   = false,      -- look-to-heal an ally (softfriend), opt-in
  softTargetInteract = true,       -- vendors / nodes / mailboxes (softinteract)
  unlockOnFocusLoss  = true,       -- free cursor when the window loses focus (heuristic)
  focusFpsThreshold  = 0,          -- 0 = auto-derive from maxfpsbk; else absolute FPS
  focusDwell         = 1.25,       -- seconds at low FPS before we call it focus-lost
  lockKey            = "SHIFT-TAB", -- grab look-at mob as hard target ("" = unbound)
  focusKey           = "CTRL-TAB",  -- set focus to target/look-at ("" = unbound)
  clearFocusKey      = "",          -- clear focus ("" = unbound)
  tooltip = {
    mode = "compact", -- "compact" (name + click hint) | "full" (game tooltip) | "off"
    fontSize  = 16,       -- compact label text size (hint is 85% of this)
    hintStyle = "icons",  -- "icons" | "iconsonly" | "text"
    backdrop  = true,     -- dark plate behind the compact label
    x = 0,            -- offset from screen center (label TOP anchors here)
    y = -24,
  },
  gcd = {
    show  = true,
    style = "arc",      -- "arc" (dotted arc, see HUD.lua) | "swipe" (round swipe on the reticle)
    side  = "opposite", -- arc side: "opposite" (of the resource arc) | left | right | below | above
    track = true,       -- arc: keep the empty track visible in combat
    size  = 28,         -- swipe size
    alpha = 0.30,       -- swipe opacity
  },
  power = {
    show     = true,  -- dotted resource arc (energy / rage / mana)
    side     = "left", -- "left" | "right" | "below" | "above"
    radius   = 34,
    span     = 110,   -- degrees of arc
    dot      = 4,
    hideIdle = true,  -- hide out of combat when full (or empty, for rage etc)
  },
  dialog = {
    keys = true,      -- quest / gossip by keyboard, camera stays locked (Dialog.lua)
  },
  hud = {
    x = 0,            -- offset of the arcs + combo ring from the reticle
    y = 0,
    gap = 9,          -- spacing between stacked rings (GCD / resource / combo)
  },
  camera = {
    mode   = "off",   -- "off" | "always" | "cursor" | "target"  (see Camera.lua)
    offset = 1.2,     -- shoulder offset; negative = other shoulder
  },
  combo = {
    show   = true,    -- rogue/druid combo-point pips at the reticle
    layout = "ring",  -- "ring" (inside the resource arc) | "row" (above the reticle)
  },
  reticle = {
    show  = true,
    shape = "dot",   -- "dot" | "cross" | "ticks"
    size  = 6,
    r = 1, g = 1, b = 1,
    alpha = 0.35,
    x = 0, y = 0,    -- offset from screen center
  },
  dbVersion = DB_VERSION,
}

local function copyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      copyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local ev = CreateFrame("Frame")
local handlers = {}

function handlers:ADDON_LOADED(_, name)
  if name ~= addonName then return end
  ev:UnregisterEvent("ADDON_LOADED")
  CTPIDB = CTPIDB or {}

  -- migrate pre-1.0 (FreeLook) configs: drop the old flat crosshair* keys and
  -- adopt the structured reticle table. only runs once.
  if (CTPIDB.dbVersion or 0) < 5 then
    CTPIDB.crosshair, CTPIDB.crosshairScale, CTPIDB.crosshairColor = nil, nil, nil
    CTPIDB.standardMove, CTPIDB.pickpocket, CTPIDB.combatMacro = nil, nil, nil
    CTPIDB.reticle = nil   -- rebuild from defaults below
    CTPIDB.dbVersion = DB_VERSION
  end

  -- v5 -> v6: the single softTarget flag split into enemy / friend / interact.
  -- carry the old value onto enemy + interact; friend starts off (opt-in).
  if (CTPIDB.dbVersion or 0) < 6 then
    if CTPIDB.softTarget ~= nil then
      CTPIDB.softTargetEnemy    = CTPIDB.softTarget
      CTPIDB.softTargetInteract = CTPIDB.softTarget
      CTPIDB.softTarget = nil
    end
    CTPIDB.dbVersion = DB_VERSION
  end

  -- v6 -> v7: tooltip.show (bool) became tooltip.mode
  if (CTPIDB.dbVersion or 0) < 7 then
    if type(CTPIDB.tooltip) == "table" and CTPIDB.tooltip.show ~= nil then
      if CTPIDB.tooltip.show == false then CTPIDB.tooltip.mode = "off" end
      CTPIDB.tooltip.show = nil
    end
    CTPIDB.dbVersion = DB_VERSION
  end

  -- v7 -> v8: interactLeft (bool) became leftAction
  if (CTPIDB.dbVersion or 0) < 8 then
    if CTPIDB.interactLeft == false then CTPIDB.leftAction = "" end
    CTPIDB.interactLeft = nil
    CTPIDB.dbVersion = DB_VERSION
  end

  -- the experimental "NATIVE" left-click was removed (the game doesnt
  -- interact on tap while mouselooking, so it only ever ran). same behavior:
  if CTPIDB.leftAction == "NATIVE" then CTPIDB.leftAction = "MOVEFORWARD" end

  copyDefaults(CTPIDB, defaults)
  ns.db = CTPIDB
end

function handlers:PLAYER_LOGIN()
  applySoftTarget()
  buildReticleFrame()
  buildComboFrame()
  if ns.BuildHUD then ns.BuildHUD() end
  if ns.BuildLook then ns.BuildLook() end
  refreshReticle()
  updateCombo()
  if ns.BuildOptionsCategory then ns.BuildOptionsCategory() end
  if ns.ApplyToolBindings then ns.ApplyToolBindings() end
  ns.ForceReconcile()
  print("|cFFc8a25eCTPI|r loaded. |cFFFFFF00/ctpi|r for settings. Master is "
        .. (ns.db.enabled and "|cFF00FF00on|r" or "|cFFFF0000off|r") .. ".")
end

-- when we leave combat, re-sync override bindings, and apply any soft-target
-- toggle that was deferred because secure cvars cant be set in combat
function handlers:PLAYER_REGEN_ENABLED()
  ns.RefreshBindings()
  if ns.ApplyToolBindings then ns.ApplyToolBindings() end
  if softTargetPending then applySoftTarget() end
end


-- loading screens tank FPS too, which would false-trigger the focus heuristic.
-- bracket them out. LOADING_SCREEN_* may not exist on every build, so they're
-- registered defensively; PLAYER_ENTERING_WORLD is the reliable backstop.
-- if the client refuses one of our calls, say so instead of failing silently
local function reportBlocked(event, who, fn)
  if who == addonName then
    print("|cFFc8a25eCTPI|r |cFFFF4444" .. event .. "|r: " .. tostring(fn))
  end
end
function handlers:ADDON_ACTION_BLOCKED(e, who, fn)   reportBlocked(e, who, fn) end
function handlers:ADDON_ACTION_FORBIDDEN(e, who, fn) reportBlocked(e, who, fn) end

function handlers:LOADING_SCREEN_ENABLED()  ns.SetLoadingScreen(true)  end
function handlers:LOADING_SCREEN_DISABLED() ns.SetLoadingScreen(false); ns.SuppressFocusFor(3) end
function handlers:PLAYER_ENTERING_WORLD()   ns.SetLoadingScreen(false); ns.SuppressFocusFor(3) end

ev:SetScript("OnEvent", function(self, event, ...)
  if handlers[event] then handlers[event](handlers, event, ...) end
end)
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "ADDON_ACTION_BLOCKED")
pcall(ev.RegisterEvent, ev, "ADDON_ACTION_FORBIDDEN")
pcall(ev.RegisterEvent, ev, "LOADING_SCREEN_ENABLED")
pcall(ev.RegisterEvent, ev, "LOADING_SCREEN_DISABLED")

-- ---------------------------------------------------------------------
-- Slash commands. Most tuning lives in the /ctpi panel; these are the
-- quick toggles and power-user bits.
-- ---------------------------------------------------------------------
local function p(msg) print("|cFFc8a25eCTPI|r: " .. msg) end

SLASH_CTPI1 = "/ctpi"
SlashCmdList["CTPI"] = function(msg)
  local db = ns.db
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()

  if cmd == "" or cmd == "config" or cmd == "options" then
    if ns.ToggleConfig then ns.ToggleConfig() end

  elseif cmd == "toggle" then
    db.enabled = not db.enabled
    ns.ForceReconcile()
    if ns.RefreshDialogKeys then ns.RefreshDialogKeys() end
    if ns.UpdateShoulder then ns.UpdateShoulder() end
    p("master " .. (db.enabled and "|cFF00FF00on|r" or "|cFFFF0000off|r"))

  elseif cmd == "run" then
    if InCombatLockdown() then p("cant change this in combat"); return end
    db.rightAction = (rest:lower() == "hold") and "MOVEFORWARD" or "TOGGLEAUTORUN"
    ns.RefreshBindings()
    p("right-click run = |cFFFFFF00" ..
      (db.rightAction == "MOVEFORWARD" and "hold" or "autorun (tap)") .. "|r")

  elseif cmd == "left" or cmd == "right" then
    if InCombatLockdown() then p("cant change this in combat"); return end
    local map = { interact = "INTERACTMOUSEOVER", run = "MOVEFORWARD", hold = "MOVEFORWARD",
                  autorun = "TOGGLEAUTORUN", none = "" }
    local key = rest:lower()
    local v = map[key]
    if v == nil then
      p("usage: /ctpi " .. cmd .. " <interact|run|autorun|none>")
      return
    end
    db[cmd .. "Action"] = v
    ns.RefreshBindings()
    if ns.ApplyNativeClick then ns.ApplyNativeClick() end   -- also when mouselook is off right now
    p(cmd .. "-click = |cFFFFFF00" .. key .. "|r")

  elseif cmd == "leftenemy" then
    if InCombatLockdown() then p("cant change this in combat"); return end
    local v = rest:lower()
    if v ~= "interact" and v ~= "lock" and v ~= "lockattack" then
      p("usage: /ctpi leftenemy <interact|lock|lockattack>"); return
    end
    db.leftEnemy = v
    if ns.UpdateEnemyMacro then ns.UpdateEnemyMacro() end
    ns.RefreshBindings()
    p("left-click on enemies = |cFFFFFF00" .. v .. "|r")

  elseif cmd == "softenemy" or cmd == "softtarget" then
    db.softTargetEnemy = not db.softTargetEnemy
    applySoftTarget()
    p("soft-target enemies " .. (db.softTargetEnemy and "on" or "off"))

  elseif cmd == "softfriend" then
    db.softTargetFriend = not db.softTargetFriend
    applySoftTarget()
    p("soft-target friendlies (look to heal) " .. (db.softTargetFriend and "on" or "off"))

  elseif cmd == "softinteract" then
    db.softTargetInteract = not db.softTargetInteract
    applySoftTarget()
    p("soft-target interact " .. (db.softTargetInteract and "on" or "off"))

  elseif cmd == "focusunlock" then
    db.unlockOnFocusLoss = not db.unlockOnFocusLoss
    ns.ForceReconcile()
    p("unlock cursor on focus loss " .. (db.unlockOnFocusLoss and "on" or "off")
      .. " |cFF888888(windowed/borderless only, ~" .. tostring(db.focusDwell or 1.25) .. "s lag)|r")

  elseif cmd == "focusfps" and rest ~= "" then
    local n = tonumber(rest)
    if n and n >= 0 then
      db.focusFpsThreshold = n
      p("focus FPS threshold = |cFFFFFF00" .. (n == 0 and "auto (from maxfpsbk)" or tostring(n)) .. "|r")
    else
      p("usage: /ctpi focusfps <number>  (0 = auto)")
    end

  elseif cmd == "lockkey" or cmd == "focuskey" or cmd == "clearfocuskey" then
    if InCombatLockdown() then p("cant change keybinds in combat"); return end
    local field = (cmd == "lockkey" and "lockKey")
      or (cmd == "focuskey" and "focusKey") or "clearFocusKey"
    local key = rest:upper():gsub("%s+", "")
    if key == "NONE" or key == "OFF" then key = "" end
    db[field] = key
    if ns.ApplyToolBindings then ns.ApplyToolBindings() end
    p(cmd .. " = |cFFFFFF00" .. (key == "" and "(unbound)" or key) .. "|r")

  elseif cmd == "shoulder" or cmd == "camera" then
    local order = { "off", "always", "cursor", "target" }
    local want = rest:lower()
    if want == "" then   -- cycle
      local idx = 1
      for k, v in ipairs(order) do if v == db.camera.mode then idx = k end end
      want = order[idx % #order + 1]
    end
    local valid = false
    for _, v in ipairs(order) do if v == want then valid = true end end
    if not valid then p("usage: /ctpi shoulder [off|always|cursor|target]"); return end
    db.camera.mode = want
    if ns.UpdateShoulder then ns.UpdateShoulder() end
    p("shoulder camera = |cFFFFFF00" .. want .. "|r")

  elseif cmd == "dialogkeys" or cmd == "questkeys" then
    db.dialog.keys = not db.dialog.keys
    if ns.RefreshDialogKeys then ns.RefreshDialogKeys() end
    p("quest / gossip keys " .. (db.dialog.keys and "on" or "off"))

  elseif cmd == "debug" then
    ns.debug = not ns.debug
    ns.lastWhy = false   -- force the next state to print
    p("debug " .. (ns.debug and "on (prints every cursor lock/free change)" or "off"))

  elseif cmd == "why" then
    -- deferred: while the slash runs, the chat box is still active, which
    -- would always read as "typing"
    C_Timer.After(0.6, function()
      local free, why = shouldFreeCursor()
      p("enabled=" .. tostring(db.enabled) .. "  mouselooking=" .. tostring(IsMouselooking()))
      p("cursor should be free? " .. (free and ("|cFFFF8800yes|r -> " .. why)
        or "|cFF00FF00no|r (should be mouselooking)"))
      local kf = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
      if kf then p("keyboard focus: " .. tostring(kf.GetName and kf:GetName() or "unnamed frame")) end
      p(string.format("fps %.0f, focus-loss threshold %.0f, cursor info: %s",
        GetFramerate() or 0, ns.FocusThreshold() or 0, tostring((GetCursorInfo and GetCursorInfo()) or "none")))
      if not free and not IsMouselooking() then
        MouselookStart()
        C_Timer.After(0.2, function()
          p("after a manual MouselookStart(): mouselooking=" .. tostring(IsMouselooking()))
        end)
      end
    end)

  elseif cmd == "block" and rest ~= "" then
    db.extraBlock[rest] = true
    p("will free cursor while |cFFFFFF00" .. rest .. "|r is open")

  elseif cmd == "unblock" and rest ~= "" then
    db.extraBlock[rest] = nil
    p("removed |cFFFFFF00" .. rest .. "|r from block list")

  elseif cmd == "reset" then
    if InCombatLockdown() then p("cant reset in combat"); return end
    wipe(db)
    copyDefaults(db, defaults)
    applySoftTarget()
    refreshReticle()
    ns.RefreshBindings()
    ns.ForceReconcile()
    if ns.UpdateShoulder then ns.UpdateShoulder() end
    p("reset to defaults")

  else
    p("|cFFFFFF00/ctpi|r opens settings. also: toggle, left/right <interact|run|autorun|none>, "
      .. "softenemy, softfriend, softinteract, focusunlock, "
      .. "lockkey/focuskey/clearfocuskey <BIND|none>, shoulder [off|always|cursor|target], "
      .. "block/unblock <Frame>, why, debug, reset")
  end
end

-- ---------------------------------------------------------------------
-- Globals for Bindings.xml (it runs in global scope, no access to ns)
-- ---------------------------------------------------------------------
function CTPI_ToggleMaster()
  SlashCmdList["CTPI"]("toggle")
end

function CTPI_ToggleFreeCursor()
  ns.freeCursorHeld = not ns.freeCursorHeld
  ns.ForceReconcile()
  if ns.UpdateShoulder then ns.UpdateShoulder() end   -- "cursor" shoulder mode follows this
end
