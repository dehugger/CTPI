local addonName, ns = ...

-- =====================================================================
-- CTPI / QuickMenu.lua
-- Rapid toggles: a compact click-to-flip list of the flags you change
-- mid-play, opened from
--   * the minimap button   (left-click: quick menu, right-click: full
--                           settings, drag: move it around the minimap)
--   * the minimap addon dropdown (TOC AddonCompartmentFunc)
--   * a keybind (Key Bindings > AddOns > "Toggle CTPI quick menu"), which
--     is the handy one since mouselook hides the cursor; the menu frees the
--     cursor while it's open (it's in Core's block list).
-- Rows either flip a boolean or step through a list of options.
-- Settings that change bindings take effect right away out of combat, or
-- as soon as combat ends.
-- =====================================================================

local GOLD = "|cFFc8a25e"

-- db path helpers: "camera.mode" -> db.camera.mode
local function getPath(path)
  local t = ns.db
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end
local function setPath(path, v)
  local t = ns.db
  local parts = {}
  for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
  for i = 1, #parts - 1 do t = t[parts[i]] end
  t[parts[#parts]] = v
end

local function rebind()
  if ns.UpdateEnemyMacro then ns.UpdateEnemyMacro() end
  if ns.RefreshBindings then ns.RefreshBindings() end
end
local function hud()
  if ns.LayoutHUD then ns.LayoutHUD() end
  if ns.UpdateHUD then ns.UpdateHUD(IsMouselooking()) end
end
local function look()
  if ns.LayoutLook then ns.LayoutLook() end
  if ns.UpdateLook then ns.UpdateLook(IsMouselooking()) end
end

-- ---------------------------------------------------------------------
-- rows. { section = "..." } or
--   { label, path, after }                      boolean flag
--   { label, path, after, cycle = { {value, name}, ... } }
--   { label, get, set }                         custom
-- ---------------------------------------------------------------------
local ROWS = {
  { section = "General" },
  { label = "CTPI enabled",
    get = function() return ns.db.enabled end,
    set = function() SlashCmdList["CTPI"]("toggle") end },
  { label = "Cursor reappears", path = "cursorReturn",
    after = function() if ns.ApplyCursorReturn then ns.ApplyCursorReturn() end end,
    cycle = { { "game", "Game default" }, { "stay", "Where it was" }, { "center", "Centered" } } },
  { label = "Free cursor (stay unlocked)",
    get = function() return ns.freeCursorHeld end,
    set = function() CTPI_ToggleFreeCursor() end },

  { section = "Clicking" },
  { label = "Left-click on enemies", path = "leftEnemy", after = rebind, combat = true,
    cycle = { { "interact", "Interact" }, { "lock", "Lock" }, { "lockattack", "Lock + attack" } } },
  { label = "Hard lock in combat", path = "hardLock", after = rebind, combat = true },
  { label = "Rogue stealth openers", path = "rogueOpeners", after = rebind },
  { label = "Left-click stops autorun", path = "leftStopsAutorun",
    after = function() if ns.SyncAutorunSwap then ns.SyncAutorunSwap() end end },
  { label = "Shift radial menu", path = "radial.enabled", combat = true,
    after = function()
      if ns.ApplyFreelookCentering then ns.ApplyFreelookCentering() end
      if ns.RebuildRadial then ns.RebuildRadial() end
    end },
  { label = "Quest / gossip keys", path = "dialog.keys",
    after = function() if ns.RefreshDialogKeys then ns.RefreshDialogKeys() end end },

  { section = "Camera + HUD" },
  { label = "Shoulder camera", path = "camera.mode",
    after = function() if ns.UpdateShoulder then ns.UpdateShoulder() end end,
    cycle = { { "off", "Off" }, { "always", "Always" }, { "cursor", "Cursor key" }, { "target", "Target lock" } } },
  { label = "Look-at label", path = "tooltip.mode", after = look,
    cycle = { { "compact", "Compact" }, { "full", "Full tooltip" }, { "off", "Off" } } },
  { label = "Reticle", path = "reticle.show",
    after = function() if ns.RefreshReticle then ns.RefreshReticle() end; ns.ForceReconcile() end },
  { label = "GCD", path = "gcd.show", after = hud },
  { label = "Casts on the GCD arc", path = "gcd.cast", after = hud },
  { label = "Resource arc", path = "power.show", after = hud },
  { label = "Combo points", path = "combo.show",
    after = function() if ns.UpdateCombo then ns.UpdateCombo() end end },

  { section = "Look to target" },
  { label = "Enemies", path = "softTargetEnemy",
    after = function() if ns.ApplySoftTarget then ns.ApplySoftTarget() end end },
  { label = "Friendlies (heal)", path = "softTargetFriend",
    after = function() if ns.ApplySoftTarget then ns.ApplySoftTarget() end end },
  { label = "Interactables", path = "softTargetInteract",
    after = function() if ns.ApplySoftTarget then ns.ApplySoftTarget() end end },

  { section = "Cursor" },
  { label = "Unlock when window loses focus", path = "unlockOnFocusLoss",
    after = function() if ns.ApplyBackgroundCap then ns.ApplyBackgroundCap() end; ns.ForceReconcile() end },
  { label = "Debug messages",
    get = function() return ns.debug end,
    set = function() ns.debug = not ns.debug; ns.lastWhy = false end },
  { label = "Minimap button", path = "minimap.show",
    after = function() if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end end },
}

-- ---------------------------------------------------------------------
-- menu frame
-- ---------------------------------------------------------------------
local menu
local rowFrames = {}
local ROW_H, WIDTH = 18, 250

local function valueText(row)
  if row.cycle then
    local cur = getPath(row.path)
    for _, c in ipairs(row.cycle) do
      if c[1] == cur then return GOLD .. c[2] .. "|r" end
    end
    return GOLD .. tostring(cur) .. "|r"
  end
  local v
  if row.get then v = row.get() else v = getPath(row.path) end
  return v and "|cFF55DD55On|r" or "|cFF777777Off|r"
end

local function refreshAll()
  for _, f in ipairs(rowFrames) do
    if f.row and not f.row.section then f.value:SetText(valueText(f.row)) end
  end
end
ns.RefreshQuickMenu = refreshAll

local function activate(row)
  if row.set then
    row.set()
  elseif row.cycle then
    local cur, idx = getPath(row.path), 0
    for i, c in ipairs(row.cycle) do if c[1] == cur then idx = i end end
    setPath(row.path, row.cycle[idx % #row.cycle + 1][1])
  else
    setPath(row.path, not getPath(row.path))
  end
  if row.after then row.after() end
  if row.combat and InCombatLockdown() then
    print("|cFFc8a25eCTPI|r: " .. row.label .. " takes effect when combat ends")
  end
  refreshAll()
  if ns.ReloadConfigControls then ns.ReloadConfigControls() end
end

local function build()
  if menu then return end
  menu = CreateFrame("Frame", "CTPIQuickMenu", UIParent, "BackdropTemplate")
  menu:SetFrameStrata("DIALOG")
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  menu:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  menu:SetBackdropColor(0.05, 0.04, 0.03, 0.95)
  menu:SetBackdropBorderColor(0.78, 0.64, 0.37, 1)
  tinsert(UISpecialFrames, "CTPIQuickMenu")   -- Esc closes

  local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, -10)
  title:SetText("CTPI quick toggles")
  title:SetTextColor(0.85, 0.70, 0.42)

  CreateFrame("Button", nil, menu, "UIPanelCloseButton"):SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, 0)

  local y = -30
  for _, row in ipairs(ROWS) do
    local f
    if row.section then
      f = CreateFrame("Frame", nil, menu)
      f:SetSize(WIDTH - 20, ROW_H)
      f:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, y - 4)
      local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      t:SetPoint("LEFT", f, "LEFT", 2, 0)
      t:SetText(row.section)
      t:SetTextColor(0.82, 0.67, 0.40)
      y = y - ROW_H - 4
    else
      f = CreateFrame("Button", nil, menu)
      f:SetSize(WIDTH - 20, ROW_H)
      f:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, y)
      f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      local l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      l:SetPoint("LEFT", f, "LEFT", 8, 0)
      l:SetText(row.label)
      local v = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      v:SetPoint("RIGHT", f, "RIGHT", -6, 0)
      f.value = v
      f:SetScript("OnClick", function() activate(row) end)
      y = y - ROW_H
    end
    f.row = row
    rowFrames[#rowFrames + 1] = f
  end

  local all = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
  all:SetSize((WIDTH - 30) / 2, 22)
  all:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, y - 8)
  all:SetText("All settings")
  all:SetScript("OnClick", function()
    menu:Hide()
    if ns.OpenConfig then ns.OpenConfig() end
  end)
  local setup = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
  setup:SetSize((WIDTH - 30) / 2, 22)
  setup:SetPoint("LEFT", all, "RIGHT", 6, 0)
  setup:SetText("Run setup")
  setup:SetScript("OnClick", function()
    menu:Hide()
    if ns.OpenSetup then ns.OpenSetup() end
  end)
  y = y - 8 - 22

  menu:SetSize(WIDTH, -y + 12)
  menu:SetScript("OnShow", refreshAll)
  menu:SetScript("OnHide", function() ns.ForceReconcile() end)
  menu:Hide()
end

local function place()
  menu:ClearAllPoints()
  local b = ns.minimapButton
  if b and b:IsVisible() then
    menu:SetPoint("TOPRIGHT", b, "BOTTOMLEFT", 0, 4)
  else
    menu:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
  end
end

function ns.ToggleQuickMenu()
  build()
  if menu:IsShown() then menu:Hide() else place(); menu:Show() end
  ns.ForceReconcile()   -- free / re-lock the cursor right away
end

-- globals for Bindings.xml and the TOC's addon compartment entry
function CTPI_ToggleQuickMenu() ns.ToggleQuickMenu() end
function CTPI_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then
    if ns.OpenConfig then ns.OpenConfig() end
  else
    ns.ToggleQuickMenu()
  end
end
function CTPI_OnAddonCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
  GameTooltip:SetText("Coffee's Touchpad Improvements")
  GameTooltip:AddLine("Left-click: quick toggles", 1, 1, 1)
  GameTooltip:AddLine("Right-click: all settings", 1, 1, 1)
  GameTooltip:Show()
end
function CTPI_OnAddonCompartmentLeave() GameTooltip:Hide() end

-- ---------------------------------------------------------------------
-- minimap button (hand-rolled, no library). sits on the minimap's edge at
-- db.minimap.angle degrees; drag to move it around.
-- ---------------------------------------------------------------------
local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"

local function positionButton(b)
  local a = math.rad((ns.db.minimap and ns.db.minimap.angle) or 215)
  local r = (Minimap:GetWidth() / 2) + 8
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function buildButton()
  if ns.minimapButton or not Minimap then return end
  local b = CreateFrame("Button", "CTPIMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      if ns.OpenConfig then ns.OpenConfig() end
    else
      ns.ToggleQuickMenu()
    end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Coffee's Touchpad Improvements")
    GameTooltip:AddLine("Left-click: quick toggles", 1, 1, 1)
    GameTooltip:AddLine("Right-click: all settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function(me)
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local sc = Minimap:GetEffectiveScale()
      ns.db.minimap.angle = math.deg(math.atan2(py / sc - my, px / sc - mx))
      positionButton(me)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  ns.minimapButton = b
  positionButton(b)
end

function ns.UpdateMinimapButton()
  if not ns.db then return end
  if ns.db.minimap.show then
    buildButton()
    if ns.minimapButton then positionButton(ns.minimapButton); ns.minimapButton:Show() end
  elseif ns.minimapButton then
    ns.minimapButton:Hide()
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() ns.UpdateMinimapButton() end)
