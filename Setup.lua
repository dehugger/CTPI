local addonName, ns = ...

-- =====================================================================
-- CTPI / Setup.lua
-- Guided setup. Opens once on first login (and once after the 3.0
-- update), and any time with /ctpi setup or from the quick menu.
-- Six short steps; everything is applied as you go, and every choice is
-- also in the regular settings afterwards.
--   1 welcome + recommended game settings
--   2 play style (melee / ranged + caster / healer / simple)
--   3 mouse buttons
--   4 camera + HUD
--   5 keys (real keybinds, captured by pressing them)
--   6 done
-- =====================================================================

local SETUP_VERSION = 3
local GOLD = "|cFFc8a25e"
local frame, steps, stepIdx = nil, {}, 1
local reloaders = {}

local function K() return ns.UIKit end

local function rebuildAll()
  if ns.UpdateEnemyMacro then ns.UpdateEnemyMacro() end
  if ns.RefreshBindings then ns.RefreshBindings() end
  if ns.RebuildRadial then ns.RebuildRadial() end
  if ns.LayoutHUD then ns.LayoutHUD() end
  if ns.LayoutLook then ns.LayoutLook() end
  if ns.UpdateShoulder then ns.UpdateShoulder() end
  if ns.ApplySoftTarget then ns.ApplySoftTarget() end
  if ns.ReloadConfigControls then ns.ReloadConfigControls() end
end

local function para(parent, text, anchor, dy, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, dy or -10)
  else fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0) end
  fs:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
  fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
  fs:SetText(text)
  return fs
end

local function header(parent, text, anchor, dy)
  local fs = para(parent, text, anchor, dy, "GameFontNormal")
  fs:SetTextColor(0.85, 0.70, 0.42)
  return fs
end

-- ---------------------------------------------------------------------
-- step 1: welcome + game settings
-- ---------------------------------------------------------------------
local GAME_SETTINGS = {
  { cvar = "autoInteract", value = "0", label = "Turn off Click-to-Move",
    why = "so a stray click doesn't walk you somewhere" },
  { cvar = "deselectOnClick", value = "0", label = "Turn on Sticky Targeting",
    why = "your target stays until you pick another" },
}
local wantGame = { true, true }

local function stepWelcome(p)
  local h = header(p, "Welcome to Coffee's Touchpad Improvements")
  local t = para(p, "CTPI keeps the camera in always-on mouselook so you steer by moving your fingers, "
    .. "aim with screen center, and click what you're looking at. This takes about a minute. "
    .. "Every choice here is also in the settings later (" .. GOLD .. "/ctpi|r), and you can run this "
    .. "again with " .. GOLD .. "/ctpi setup|r.", h, -8)
  local g = header(p, "Recommended game settings", t, -16)
  local prev = g
  for i, s in ipairs(GAME_SETTINGS) do
    local c = K().makeCheck(p, s.label .. "  |cFF888888(" .. s.why .. ")|r",
      function() return wantGame[i] end, function(v) wantGame[i] = v end)
    c:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", (i == 1) and -4 or 0, -4)
    prev = c
  end
  local mac = para(p, "|cFF888888On a Mac trackpad, also set System Settings > Trackpad > Secondary click "
    .. "to two fingers, so right-click works.|r", prev, -10, "GameFontHighlightSmall")
  mac:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 4, -10)
end

local function applyGameSettings()
  for i, s in ipairs(GAME_SETTINGS) do
    if wantGame[i] then pcall(ns.SetCVar, s.cvar, s.value) end
  end
end

-- ---------------------------------------------------------------------
-- step 2: play style
-- ---------------------------------------------------------------------
local STYLES = {
  { key = "melee",  label = "Melee",
    desc = "Click an enemy to lock it and start auto attack. In combat your target sticks; right-click unlocks." },
  { key = "ranged", label = "Ranged / caster",
    desc = "Click an enemy to lock it and fire your main attack (Auto Shot, or the spell below). Target sticks in combat." },
  { key = "healer", label = "Healer",
    desc = "Click enemies to lock them (no attack). In combat, clicking a friendly casts the heal below." },
  { key = "simple", label = "Keep it simple",
    desc = "Left-click just interacts, like the game normally does. Nothing locks or switches." },
}

local function defaultStyle()
  local c = ns.PlayerClass()
  if c == "HUNTER" or c == "MAGE" or c == "WARLOCK" or c == "EVOKER" then return "ranged" end
  if c == "PRIEST" then return "healer" end
  return "melee"
end
local chosenStyle

local function applyStyle(key)
  local db, cfg = ns.db, ns.ClassConfig()
  local def = ns.CLASS_DEFAULTS[ns.PlayerClass()] or {}
  chosenStyle = key
  db.leftAction = "INTERACTMOUSEOVER"
  if key == "simple" then
    db.leftEnemy, db.hardLock, cfg.friendClick = "interact", false, false
  elseif key == "healer" then
    db.leftEnemy, db.hardLock, cfg.friendClick = "lock", false, true
    db.softTargetFriend = true
    if (cfg.friendSpell or "") == "" then cfg.friendSpell = def.friendSpell or "" end
  else
    db.leftEnemy, db.hardLock, cfg.friendClick = "lockattack", true, false
    if key == "melee" then
      cfg.enemyAction = (def.enemyAction == "druid") and "druid" or "melee"
    else
      local a = def.enemyAction
      cfg.enemyAction = (a == "autoshot" or a == "druid") and a or "spell"
      if (cfg.enemySpell or "") == "" then cfg.enemySpell = def.enemySpell or "" end
    end
  end
  rebuildAll()
end

local function stepStyle(p)
  local h = header(p, "How do you play this character?")
  local btns = {}
  local descFS
  local function repaint()
    for _, b in ipairs(btns) do
      if b.key == chosenStyle then b:LockHighlight() else b:UnlockHighlight() end
    end
    for _, s in ipairs(STYLES) do
      if s.key == chosenStyle then descFS:SetText(s.desc) end
    end
    for _, fn in ipairs(reloaders) do fn() end
  end
  local prev
  for _, s in ipairs(STYLES) do
    local b = K().makeButton(p, s.label, (s.key == "ranged" or s.key == "simple") and 116 or 84,
      function() applyStyle(s.key); repaint() end)
    b.key = s.key
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    else b:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -8) end
    btns[#btns + 1] = b; prev = b
  end
  descFS = para(p, "", btns[1], -10)
  descFS:SetHeight(32)
  local cfgf = function() return ns.ClassConfig() end
  local spell = K().makeEditRow(p, "Main spell", 200,
    function() return cfgf().enemySpell end,
    function(v) cfgf().enemySpell = v; rebuildAll() end, 80)
  spell:SetPoint("TOPLEFT", descFS, "BOTTOMLEFT", 0, -8)
  local heal = K().makeEditRow(p, "Heal", 200,
    function() return cfgf().friendSpell end,
    function(v) cfgf().friendSpell = v; rebuildAll() end, 80)
  heal:SetPoint("TOPLEFT", spell, "BOTTOMLEFT", 0, -4)
  reloaders[#reloaders + 1] = function() spell.Reload(); heal.Reload() end
  local note = para(p, "|cFF888888Spell names are what you'd type after /cast. Leave the main spell empty "
    .. "for auto attack. Hunters use Auto Shot automatically.|r", heal, -10, "GameFontHighlightSmall")
  p.OnEnter = function()
    if not chosenStyle then chosenStyle = defaultStyle(); applyStyle(chosenStyle) end
    repaint()
  end
end

-- ---------------------------------------------------------------------
-- step 3: mouse buttons
-- ---------------------------------------------------------------------
local function stepMouse(p)
  local db = ns.db
  local h = header(p, "Mouse buttons (while the camera is locked)")
  local l = para(p, "Left-click", h, -10, "GameFontHighlightSmall")
  local lb, lr = K().makeChoiceRow(p,
    { { label = "Interact", value = "INTERACTMOUSEOVER", w = 80 },
      { label = "Hold to run", value = "MOVEFORWARD", w = 96 } },
    function() return db.leftAction end,
    function(v) db.leftAction = v; rebuildAll() end)
  lb[1]:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -4)
  local r = para(p, "Right-click", lb[1], -12, "GameFontHighlightSmall")
  local rb, rr = K().makeChoiceRow(p,
    { { label = "Autorun (tap)", value = "TOGGLEAUTORUN", w = 104 },
      { label = "Hold to run", value = "MOVEFORWARD", w = 96 },
      { label = "Interact", value = "INTERACTMOUSEOVER", w = 80 } },
    function() return db.rightAction end,
    function(v) db.rightAction = v; rebuildAll() end)
  rb[1]:SetPoint("TOPLEFT", r, "BOTTOMLEFT", 0, -4)
  local c = K().makeCheck(p, "Left-click stops autorun",
    function() return db.leftStopsAutorun end,
    function(v) db.leftStopsAutorun = v; if ns.SyncAutorunSwap then ns.SyncAutorunSwap() end end)
  c:SetPoint("TOPLEFT", rb[1], "BOTTOMLEFT", -4, -10)
  local n = para(p, "|cFF888888One action per button: the game doesn't let addons tell a tap from a hold. "
    .. "While locked onto a target in combat, right-click unlocks it.|r", c, -8, "GameFontHighlightSmall")
  n:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 4, -8)
  p.OnEnter = function() lr(); rr(); c:Reload() end
end

-- ---------------------------------------------------------------------
-- step 4: camera + HUD
-- ---------------------------------------------------------------------
local function stepLook(p)
  local db = ns.db
  local h = header(p, "Camera and what's around the aim point")
  local s = para(p, "Over-the-shoulder camera", h, -10, "GameFontHighlightSmall")
  local sb, sr = K().makeChoiceRow(p,
    { { label = "Off", value = "off", w = 50 }, { label = "Always", value = "always", w = 66 },
      { label = "Cursor key", value = "cursor", w = 88 }, { label = "Target lock", value = "target", w = 92 } },
    function() return db.camera.mode end,
    function(v) db.camera.mode = v; rebuildAll() end)
  sb[1]:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -4)
  local checks = {
    { "Reticle (dot at the aim point)", "reticle", "show" },
    { "Look-at label (name + what clicking does)", "tooltip", nil },
    { "GCD + cast arc", "gcd", "show" },
    { "Resource arc (energy / rage / mana)", "power", "show" },
    { "Combo points", "combo", "show" },
    { "Radial menu while holding Shift", "radial", "enabled" },
  }
  local prev, made = sb[1], {}
  for i, c in ipairs(checks) do
    local get, set
    if c[2] == "tooltip" then
      get = function() return db.tooltip.mode ~= "off" end
      set = function(v) db.tooltip.mode = v and "compact" or "off"; rebuildAll() end
    else
      get = function() return db[c[2]][c[3]] end
      set = function(v)
        db[c[2]][c[3]] = v
        if c[2] == "radial" and ns.ApplyFreelookCentering then ns.ApplyFreelookCentering() end
        if c[2] == "reticle" and ns.RefreshReticle then ns.RefreshReticle() end
        if c[2] == "combo" and ns.UpdateCombo then ns.UpdateCombo() end
        rebuildAll()
      end
    end
    local cb = K().makeCheck(p, c[1], get, set)
    cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", (i == 1) and -4 or 0, (i == 1) and -10 or -2)
    prev = cb; made[#made + 1] = cb
  end
  p.OnEnter = function() sr(); for _, cb in ipairs(made) do cb:Reload() end end
end

-- ---------------------------------------------------------------------
-- step 5: keys (press to bind)
-- ---------------------------------------------------------------------
local MODIFIER_KEYS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1 }

local function keyCombo(key)
  local mods = ""
  if IsAltKeyDown() then mods = mods .. "ALT-" end
  if IsControlKeyDown() then mods = mods .. "CTRL-" end
  if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
  return mods .. key
end

local KEYS = {
  { label = "Quick toggles menu", why = "opens the quick menu and frees the cursor",
    get = function() return GetBindingKey("CTPI_QUICKMENU") end,
    set = function(k)
      SetBinding(k, "CTPI_QUICKMENU")
      SaveBindings(GetCurrentBindingSet())
    end },
  { label = "Free cursor", why = "unlock the camera to click on UI",
    get = function() return GetBindingKey("CTPI_FREECURSOR") end,
    set = function(k)
      SetBinding(k, "CTPI_FREECURSOR")
      SaveBindings(GetCurrentBindingSet())
    end },
  { label = "Interact", why = "loot / talk from the keyboard, also in combat",
    get = function() return ns.db.interactKey ~= "" and ns.db.interactKey or nil end,
    set = function(k) ns.db.interactKey = k; if ns.ApplyToolBindings then ns.ApplyToolBindings() end end },
  { label = "Target lock", why = "lock what you're looking at",
    get = function() return ns.db.lockKey ~= "" and ns.db.lockKey or nil end,
    set = function(k) ns.db.lockKey = k; if ns.ApplyToolBindings then ns.ApplyToolBindings() end end },
}

local function stepKeys(p)
  local h = header(p, "Keys")
  local t = para(p, "Click a button, then press the key you want (with Shift / Ctrl / Alt if you like). "
    .. "Esc cancels. A key you pick replaces whatever it did before.", h, -8, "GameFontHighlightSmall")
  local prev = t
  local buttons = {}
  for i, k in ipairs(KEYS) do
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(400, 26)
    row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, (i == 1) and -12 or -6)
    local l = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l:SetPoint("LEFT", row, "LEFT", 0, 0)
    l:SetWidth(140); l:SetJustifyH("LEFT")
    l:SetText(k.label)
    local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    b:SetSize(120, 22)
    b:SetPoint("LEFT", l, "RIGHT", 4, 0)
    local w = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    w:SetPoint("LEFT", b, "RIGHT", 8, 0)
    w:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    w:SetJustifyH("LEFT")
    w:SetText(k.why)
    local function show() b:SetText(k.get() or "|cFF888888(none)|r") end
    b:SetScript("OnClick", function(self)
      if InCombatLockdown() then return end
      self:SetText(GOLD .. "press a key|r")
      self:EnableKeyboard(true)
      self:SetScript("OnKeyDown", function(me, key)
        if MODIFIER_KEYS[key] then return end
        me:EnableKeyboard(false)
        me:SetScript("OnKeyDown", nil)
        if key ~= "ESCAPE" and not InCombatLockdown() then k.set(keyCombo(key)) end
        show()
      end)
    end)
    show()
    buttons[#buttons + 1] = show
    prev = row
  end
  p.OnEnter = function() for _, fn in ipairs(buttons) do fn() end end
end

-- ---------------------------------------------------------------------
-- step 6: done
-- ---------------------------------------------------------------------
local function stepDone(p)
  local h = header(p, "You're set")
  local t = para(p, "Things to know:\n\n"
    .. "  " .. GOLD .. "Hold Shift|r for the radial menu: slide toward a spell and click it.\n"
    .. "  " .. GOLD .. "Right-click|r unlocks your target while locked in combat.\n"
    .. "  The " .. GOLD .. "quick menu|r (minimap button or your key) flips the common settings.\n"
    .. "  " .. GOLD .. "/ctpi|r has everything else; the Class tab edits your radial rings.\n"
    .. "  " .. GOLD .. "/ctpi why|r explains what the cursor is doing if something feels off.", h, -10)
end

-- ---------------------------------------------------------------------
-- frame
-- ---------------------------------------------------------------------
local STEPS = {
  { title = "Welcome", build = stepWelcome, leave = applyGameSettings },
  { title = "Play style", build = stepStyle },
  { title = "Mouse", build = stepMouse },
  { title = "Camera + HUD", build = stepLook },
  { title = "Keys", build = stepKeys },
  { title = "Done", build = stepDone },
}

local nextB, backB, counter

local function showStep(i)
  stepIdx = i
  for j, pg in ipairs(steps) do
    if j == i then pg:Show(); if pg.OnEnter then pg.OnEnter() end else pg:Hide() end
  end
  counter:SetText(GOLD .. i .. "|r / " .. #STEPS .. "   " .. STEPS[i].title)
  backB:SetEnabled(i > 1)
  nextB:SetText(i == #STEPS and "Finish" or "Next")
end

local function build()
  if frame then return end
  frame = CreateFrame("Frame", "CTPISetupFrame", UIParent, "BackdropTemplate")
  frame:SetSize(520, 400)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true); frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0.05, 0.04, 0.03, 0.96)
  frame:SetBackdropBorderColor(0.78, 0.64, 0.37, 1)
  tinsert(UISpecialFrames, "CTPISetupFrame")

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("CTPI setup")
  title:SetTextColor(0.85, 0.70, 0.42)
  counter = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  counter:SetPoint("TOPRIGHT", -40, -18)
  CreateFrame("Button", nil, frame, "UIPanelCloseButton"):SetPoint("TOPRIGHT", 0, 0)

  for i, st in ipairs(STEPS) do
    local pg = CreateFrame("Frame", nil, frame)
    pg:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -46)
    pg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 46)
    st.build(pg)
    pg:Hide()
    steps[i] = pg
  end

  backB = K().makeButton(frame, "Back", 80, function()
    if stepIdx > 1 then showStep(stepIdx - 1) end
  end)
  backB:SetPoint("BOTTOMLEFT", 16, 14)
  nextB = K().makeButton(frame, "Next", 90, function()
    local st = STEPS[stepIdx]
    if st.leave then st.leave() end
    if stepIdx < #STEPS then
      showStep(stepIdx + 1)
    else
      ns.db.setupVersion = SETUP_VERSION
      frame:Hide()
    end
  end)
  nextB:SetPoint("BOTTOMRIGHT", -16, 14)
  local skip = K().makeButton(frame, "Skip setup", 90, function()
    ns.db.setupVersion = SETUP_VERSION
    frame:Hide()
  end)
  skip:SetPoint("RIGHT", nextB, "LEFT", -6, 0)

  frame:SetScript("OnHide", function() ns.ForceReconcile() end)
  frame:Hide()
end

function ns.OpenSetup()
  if InCombatLockdown() then
    print("|cFFc8a25eCTPI|r: setup opens after combat")
    return
  end
  build()
  showStep(1)
  frame:Show()
  ns.ForceReconcile()   -- free the cursor for it
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  local db = ns.db
  if db and (db.setupVersion or 0) < SETUP_VERSION then
    C_Timer.After(2, function() if not InCombatLockdown() then ns.OpenSetup() end end)
  end
end)
