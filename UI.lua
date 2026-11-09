local addonName, ns = ...

-- =====================================================================
-- CTPI / UI.lua
-- In-game settings panel, tabbed (Reticle / HUD / Camera / Behavior).
-- Every numeric control is a slider PLUS a type-in box (two-way synced).
-- The panel sits off to the side and keeps the reticle + HUD visible while
-- open, so edits preview live.
-- Hand-rolled BackdropTemplate window (the retail Settings API differs
-- across client builds; a custom frame is the portable choice).
-- =====================================================================

local panel
local controls = {}   -- widgets with :Reload(), refreshed each open

local idn = 0
local function uid(p) idn = idn + 1; return p .. idn end

-- ---- slider factory ---------------------------------------------------------
-- OptionsSliderTemplate is a deprecated template on modern clients (Forever)
-- and can disappear any patch. try it, then the modern ones, then hand-roll.
local SLIDER_TEMPLATES = { "OptionsSliderTemplate", "UISliderTemplateWithLabels", "UISliderTemplate" }

local function styleBareSlider(s)
  s:SetOrientation("HORIZONTAL")
  if (s:GetHeight() or 0) < 4 then s:SetHeight(17) end
  s:EnableMouse(true)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", s, "LEFT", 4, 0)
  track:SetPoint("RIGHT", s, "RIGHT", -4, 0)
  track:SetHeight(4)
  track:SetColorTexture(0.25, 0.22, 0.18, 0.9)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
end

local function makeSlider(parent)
  for _, tmpl in ipairs(SLIDER_TEMPLATES) do
    local name = uid("CTPISlider")
    local ok, s = pcall(CreateFrame, "Slider", name, parent, tmpl)
    if ok and s then
      if not s:GetThumbTexture() then styleBareSlider(s) end
      return name, s
    end
  end
  local name = uid("CTPISlider")
  local s = CreateFrame("Slider", name, parent)
  styleBareSlider(s)
  return name, s
end

-- ---- slider + editbox row ---------------------------------------------------
-- label (left) | slider (mid) | type-in box (right), all kept in sync.
local function makeSliderRow(parent, label, lo, hi, step, decimals, getVal, setVal)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(308, 26)

  local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
  lbl:SetWidth(74); lbl:SetJustifyH("LEFT")
  lbl:SetText(label)

  local name, s = makeSlider(row)
  s:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
  s:SetWidth(150)
  s:SetMinMaxValues(lo, hi)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  -- OptionsSliderTemplate has Low/High/Text children; blank them (we label ourselves)
  if _G[name .. "Low"]  then _G[name .. "Low"]:SetText("")  end
  if _G[name .. "High"] then _G[name .. "High"]:SetText("") end
  if _G[name .. "Text"] then _G[name .. "Text"]:SetText("") end

  local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
  box:SetSize(46, 18)
  box:SetPoint("LEFT", s, "RIGHT", 14, 0)
  box:SetAutoFocus(false)
  box:SetJustifyH("CENTER")
  box:SetMaxLetters(7)

  local function disp(v)
    if decimals then return string.format("%." .. decimals .. "f", v) end
    return tostring(math.floor(v + 0.5))
  end

  local guard = false
  local function setSliderQuiet(v) guard = true; s:SetValue(v); guard = false end

  local function commit(v)
    if v < lo then v = lo elseif v > hi then v = hi end
    if not decimals then v = math.floor(v + 0.5) end
    setSliderQuiet(v)
    box:SetText(disp(v))
    setVal(v)
  end

  s:SetScript("OnValueChanged", function(self, v)
    if guard then return end
    if not decimals then v = math.floor(v + 0.5) end
    box:SetText(disp(v))
    setVal(v)
  end)
  box:SetScript("OnEnterPressed", function(self)
    local v = tonumber(self:GetText())
    if v then commit(v) else self:SetText(disp(getVal())) end
    self:ClearFocus()
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:SetText(disp(getVal())); self:ClearFocus()
  end)

  setSliderQuiet(getVal()); box:SetText(disp(getVal()))
  row.Reload = function() setSliderQuiet(getVal()); box:SetText(disp(getVal())) end
  return row
end

local function makeCheck(parent, label, getVal, setVal)
  local c = CreateFrame("CheckButton", uid("CTPICheck"), parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:SetPoint("LEFT", c, "RIGHT", 2, 0)
  t:SetText(label)
  c:SetChecked(getVal())
  c:SetScript("OnClick", function(self) setVal(self:GetChecked() and true or false) end)
  c.Reload = function() c:SetChecked(getVal()) end
  return c
end

local function makeButton(parent, label, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 90, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function makeChoiceRow(parent, choices, getVal, setVal)
  local btns = {}
  local function repaint()
    local cur = getVal()
    for _, b in ipairs(btns) do
      if b.value == cur then b:LockHighlight() else b:UnlockHighlight() end
    end
  end
  local prev
  for _, choice in ipairs(choices) do
    local b = makeButton(parent, choice.label, choice.w or 64, function()
      setVal(choice.value); repaint()
    end)
    b.value = choice.value
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) end
    btns[#btns + 1] = b; prev = b
  end
  repaint()
  return btns, repaint
end

-- dual-API RGB color picker (opacity has its own slider, so picker is RGB-only)
local function openColorPicker(r, g, b, onChange)
  local function apply()
    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
    onChange(nr, ng, nb)
  end
  if ColorPickerFrame.SetupColorPickerAndShow then            -- 10.x+
    ColorPickerFrame:SetupColorPickerAndShow({
      r = r, g = g, b = b, hasOpacity = false,
      swatchFunc = apply, cancelFunc = function() onChange(r, g, b) end,
    })
  else                                                         -- 9.x / classic
    ColorPickerFrame.func           = apply
    ColorPickerFrame.cancelFunc     = function() onChange(r, g, b) end
    ColorPickerFrame.hasOpacity     = false
    ColorPickerFrame.previousValues = { r, g, b }
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Hide(); ColorPickerFrame:Show()
  end
end

-- ---- layout helpers ---------------------------------------------------------
local function sectionHeader(parent, text, anchor, gap)
  local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap or -12)
  h:SetText(text); h:SetTextColor(0.82, 0.67, 0.40)
  return h
end
local function smallLabel(parent, text, anchor, dx, dy)
  local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx or 0, dy or -10)
  l:SetText(text)
  return l
end

-- ---- panel ------------------------------------------------------------------
-- Tabbed: Reticle / HUD / Camera / Behavior. Each tab is a page frame; the
-- widgets inside chain their anchors from an invisible anchor at the page top.
local repaints = {}
local pages, tabBtns = {}, {}

local function pageTop(page)
  local a = CreateFrame("Frame", nil, page)
  a:SetSize(1, 1)
  a:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  return a
end

local function selectTab(key)
  for k, pg in pairs(pages) do
    if k == key then pg:Show() else pg:Hide() end
  end
  for _, b in ipairs(tabBtns) do
    if b.key == key then b:LockHighlight() else b:UnlockHighlight() end
  end
  if ns.db then ns.db.uiTab = key end
end

-- ===== RETICLE ===============================================================
local function buildReticlePage(page)
  local db = ns.db
  local R  = db.reticle
  local function refresh() ns.RefreshReticle() end

  local hRet = sectionHeader(page, "Reticle", pageTop(page), 0)

  local cShow = makeCheck(page, "Show reticle",
    function() return R.show end,
    function(v) R.show = v; ns.PreviewReticle(panel:IsShown()) end)
  cShow:SetPoint("TOPLEFT", hRet, "BOTTOMLEFT", 0, -6)
  controls[#controls+1] = cShow

  local shapeLbl = smallLabel(page, "Shape", cShow, 4, -10)
  local shapeBtns, shapeRepaint = makeChoiceRow(page,
    { { label = "Dot", value = "dot" }, { label = "Cross", value = "cross" },
      { label = "Ticks", value = "ticks" } },
    function() return R.shape end,
    function(v) R.shape = v; refresh() end)
  shapeBtns[1]:SetPoint("TOPLEFT", shapeLbl, "BOTTOMLEFT", 0, -6)
  repaints[#repaints+1] = shapeRepaint

  local rSize = makeSliderRow(page, "Size", 2, 20, 1, nil,
    function() return R.size end, function(v) R.size = v; refresh() end)
  rSize:SetPoint("TOPLEFT", shapeBtns[1], "BOTTOMLEFT", 4, -16)
  controls[#controls+1] = rSize

  local rOpac = makeSliderRow(page, "Opacity", 0, 1, 0.05, 2,
    function() return R.alpha end, function(v) R.alpha = v; refresh() end)
  rOpac:SetPoint("TOPLEFT", rSize, "BOTTOMLEFT", 0, -8)
  controls[#controls+1] = rOpac

  -- color row
  local colorRow = CreateFrame("Frame", nil, page)
  colorRow:SetSize(308, 22)
  colorRow:SetPoint("TOPLEFT", rOpac, "BOTTOMLEFT", 0, -10)
  local colorLbl = colorRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  colorLbl:SetPoint("LEFT", colorRow, "LEFT", 0, 0)
  colorLbl:SetWidth(74); colorLbl:SetJustifyH("LEFT"); colorLbl:SetText("Color")
  local swatch = CreateFrame("Button", nil, colorRow)
  swatch:SetSize(48, 18)
  swatch:SetPoint("LEFT", colorLbl, "RIGHT", 4, 0)
  local swBorder = swatch:CreateTexture(nil, "BACKGROUND")
  swBorder:SetPoint("TOPLEFT", -1, 1); swBorder:SetPoint("BOTTOMRIGHT", 1, -1)
  swBorder:SetColorTexture(0.6, 0.6, 0.6, 1)
  local swTex = swatch:CreateTexture(nil, "ARTWORK")
  swTex:SetAllPoints()
  local function paintSwatch() swTex:SetColorTexture(R.r, R.g, R.b, 1) end
  paintSwatch()
  swatch:SetScript("OnClick", function()
    openColorPicker(R.r, R.g, R.b, function(nr, ng, nb)
      R.r, R.g, R.b = nr, ng, nb; paintSwatch(); refresh()
    end)
  end)
  swatch.Reload = paintSwatch
  controls[#controls+1] = swatch

  local rPosX = makeSliderRow(page, "Position X", -500, 500, 1, nil,
    function() return R.x end, function(v) R.x = v; refresh() end)
  rPosX:SetPoint("TOPLEFT", colorRow, "BOTTOMLEFT", 0, -10)
  controls[#controls+1] = rPosX

  local rPosY = makeSliderRow(page, "Position Y", -500, 500, 1, nil,
    function() return R.y end, function(v) R.y = v; refresh() end)
  rPosY:SetPoint("TOPLEFT", rPosX, "BOTTOMLEFT", 0, -8)
  controls[#controls+1] = rPosY

  local centerBtn = makeButton(page, "Center (true aim point)", 165, function()
    R.x, R.y = 0, 0; refresh(); rPosX:Reload(); rPosY:Reload()
  end)
  centerBtn:SetPoint("TOPLEFT", rPosY, "BOTTOMLEFT", -4, -12)

  local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", centerBtn, "BOTTOMLEFT", 4, -12)
  note:SetPoint("RIGHT", page, "RIGHT", 0, 0)
  note:SetJustifyH("LEFT"); note:SetWordWrap(true)
  note:SetText("Screen center is where interact and soft-target actually aim. "
    .. "Moving the reticle only moves the marker. To get your character out of "
    .. "the way, use the shoulder camera on the Camera tab instead.")
end

-- ===== LABEL =================================================================
local function buildLabelPage(page)
  local db = ns.db
  local T = db.tooltip
  local function look() ns.LayoutLook(); ns.UpdateLook(IsMouselooking()) end

  -- look-at label
  local hLook = sectionHeader(page, "Look-at label", pageTop(page), 0)
  local modeLbl = smallLabel(page, "Shows what the reticle is on and what clicking does.", hLook, 0, -6)
  local modeBtns, modeRepaint = makeChoiceRow(page,
    { { label = "Compact", value = "compact", w = 76 },
      { label = "Full tooltip", value = "full", w = 92 },
      { label = "Off", value = "off", w = 52 } },
    function() return T.mode end,
    function(v) T.mode = v; look() end)
  modeBtns[1]:SetPoint("TOPLEFT", modeLbl, "BOTTOMLEFT", 0, -6)
  repaints[#repaints+1] = modeRepaint

  local tX = makeSliderRow(page, "Position X", -600, 600, 1, nil,
    function() return T.x end, function(v) T.x = v; look() end)
  tX:SetPoint("TOPLEFT", modeBtns[1], "BOTTOMLEFT", 4, -12)
  controls[#controls+1] = tX
  local tY = makeSliderRow(page, "Position Y", -600, 600, 1, nil,
    function() return T.y end, function(v) T.y = v; look() end)
  tY:SetPoint("TOPLEFT", tX, "BOTTOMLEFT", 0, -6)
  controls[#controls+1] = tY

  local hRead = sectionHeader(page, "Readability", tY, -16)
  local tSize = makeSliderRow(page, "Text size", 10, 28, 1, nil,
    function() return T.fontSize end, function(v) T.fontSize = v; look() end)
  tSize:SetPoint("TOPLEFT", hRead, "BOTTOMLEFT", 0, -8)
  controls[#controls+1] = tSize

  local styleLbl = smallLabel(page, "Click hint", tSize, -4, -12)
  local styleBtns, styleRepaint = makeChoiceRow(page,
    { { label = "Icons + words", value = "icons", w = 110 },
      { label = "Icons", value = "iconsonly", w = 60 },
      { label = "Text", value = "text", w = 56 } },
    function() return T.hintStyle or "icons" end,
    function(v) T.hintStyle = v; look() end)
  styleBtns[1]:SetPoint("TOPLEFT", styleLbl, "BOTTOMLEFT", 0, -6)
  repaints[#repaints+1] = styleRepaint

  local cPlate = makeCheck(page, "Dark backdrop behind the label",
    function() return T.backdrop end, function(v) T.backdrop = v; look() end)
  cPlate:SetPoint("TOPLEFT", styleBtns[1], "BOTTOMLEFT", -4, -8)
  controls[#controls+1] = cPlate
end

-- ===== HUD ===================================================================
local function buildHUDPage(page)
  local db = ns.db
  local G, P = db.gcd, db.power
  local function hud() ns.LayoutHUD(); ns.UpdateHUD(IsMouselooking()) end

  -- GCD
  local hGcd = sectionHeader(page, "Global cooldown", pageTop(page), 0)
  local cGcd = makeCheck(page, "Show GCD",
    function() return G.show end, function(v) G.show = v; hud() end)
  cGcd:SetPoint("TOPLEFT", hGcd, "BOTTOMLEFT", -4, -4)
  controls[#controls+1] = cGcd
  local gStyleLbl = smallLabel(page, "Style", cGcd, 4, -8)
  local gStyleBtns, gStyleRepaint = makeChoiceRow(page,
    { { label = "Arc", value = "arc", w = 52 },
      { label = "Swipe on reticle", value = "swipe", w = 124 } },
    function() return G.style or "arc" end, function(v) G.style = v; hud() end)
  gStyleBtns[1]:SetPoint("TOPLEFT", gStyleLbl, "BOTTOMLEFT", 0, -6)
  repaints[#repaints+1] = gStyleRepaint
  local gSideLbl = smallLabel(page, "Arc side (matches the resource arc's size)", gStyleBtns[1], 0, -10)
  local gSideBtns, gSideRepaint = makeChoiceRow(page,
    { { label = "Opposite", value = "opposite", w = 68 },
      { label = "Left", value = "left", w = 46 }, { label = "Right", value = "right", w = 50 },
      { label = "Below", value = "below", w = 52 }, { label = "Above", value = "above", w = 52 } },
    function() return G.side or "opposite" end, function(v) G.side = v; hud() end)
  gSideBtns[1]:SetPoint("TOPLEFT", gSideLbl, "BOTTOMLEFT", 0, -6)
  repaints[#repaints+1] = gSideRepaint
  local cTrack = makeCheck(page, "Arc: keep the empty track visible in combat",
    function() return G.track end, function(v) G.track = v; hud() end)
  cTrack:SetPoint("TOPLEFT", gSideBtns[1], "BOTTOMLEFT", -4, -8)
  controls[#controls+1] = cTrack
  local gSize = makeSliderRow(page, "Swipe size", 12, 64, 1, nil,
    function() return G.size end, function(v) G.size = v; hud() end)
  gSize:SetPoint("TOPLEFT", cTrack, "BOTTOMLEFT", 4, -4)
  controls[#controls+1] = gSize
  local gAlpha = makeSliderRow(page, "Swipe alpha", 0.05, 1, 0.05, 2,
    function() return G.alpha end, function(v) G.alpha = v; hud() end)
  gAlpha:SetPoint("TOPLEFT", gSize, "BOTTOMLEFT", 0, -6)
  controls[#controls+1] = gAlpha

  -- resource arc
  local hPow = sectionHeader(page, "Resource arc (energy / rage / mana)", gAlpha, -14)
  local cPow = makeCheck(page, "Show resource arc",
    function() return P.show end, function(v) P.show = v; hud() end)
  cPow:SetPoint("TOPLEFT", hPow, "BOTTOMLEFT", -4, -4)
  controls[#controls+1] = cPow
  local cIdle = makeCheck(page, "Hide when idle (out of combat and full)",
    function() return P.hideIdle end, function(v) P.hideIdle = v; hud() end)
  cIdle:SetPoint("TOPLEFT", cPow, "BOTTOMLEFT", 0, -2)
  controls[#controls+1] = cIdle
  local sideLbl = smallLabel(page, "Side", cIdle, 4, -8)
  local sideBtns, sideRepaint = makeChoiceRow(page,
    { { label = "Left", value = "left" }, { label = "Right", value = "right" },
      { label = "Below", value = "below" }, { label = "Above", value = "above" } },
    function() return P.side end, function(v) P.side = v; hud() end)
  sideBtns[1]:SetPoint("TOPLEFT", sideLbl, "BOTTOMLEFT", 0, -6)
  repaints[#repaints+1] = sideRepaint
  local pRad = makeSliderRow(page, "Radius", 16, 90, 1, nil,
    function() return P.radius end, function(v) P.radius = v; hud() end)
  pRad:SetPoint("TOPLEFT", sideBtns[1], "BOTTOMLEFT", 4, -12)
  controls[#controls+1] = pRad

  -- combo
  local comboLbl = smallLabel(page, "Combo points", pRad, -4, -12)
  local comboBtns, comboRepaint = makeChoiceRow(page,
    { { label = "Inner ring", value = "ring", w = 84 },
      { label = "Row above",  value = "row",  w = 84 },
      { label = "Off",        value = "off",  w = 52 } },
    function() return db.combo.show and (db.combo.layout or "ring") or "off" end,
    function(v)
      if v == "off" then
        db.combo.show = false
      else
        db.combo.show = true; db.combo.layout = v
      end
      ns.LayoutCombo(); ns.UpdateCombo()
    end)
  comboBtns[1]:SetPoint("TOPLEFT", comboLbl, "BOTTOMLEFT", 0, -6)
  repaints[#repaints+1] = comboRepaint

  -- position of the whole arc group
  local hPos = sectionHeader(page, "Arc position + spacing", comboBtns[1], -16)
  local hX = makeSliderRow(page, "Offset X", -400, 400, 1, nil,
    function() return db.hud.x end, function(v) db.hud.x = v; hud() end)
  hX:SetPoint("TOPLEFT", hPos, "BOTTOMLEFT", 0, -8)
  controls[#controls+1] = hX
  local hY = makeSliderRow(page, "Offset Y", -400, 400, 1, nil,
    function() return db.hud.y end, function(v) db.hud.y = v; hud() end)
  hY:SetPoint("TOPLEFT", hX, "BOTTOMLEFT", 0, -6)
  controls[#controls+1] = hY
  local hGap = makeSliderRow(page, "Ring gap", 4, 30, 1, nil,
    function() return db.hud.gap end, function(v) db.hud.gap = v; hud() end)
  hGap:SetPoint("TOPLEFT", hY, "BOTTOMLEFT", 0, -6)
  controls[#controls+1] = hGap
end

-- ===== CAMERA ================================================================
local MODE_TEXT = {
  off    = "Camera stays centered behind your character.",
  always = "Shoulder view whenever CTPI is on.",
  cursor = "Shoulder view while the camera is locked. Freeing the cursor with "
        .. "the CTPI free-cursor key (Key Bindings > AddOns) or the master toggle "
        .. "centers it again. Windows that free the cursor on their own (bags, "
        .. "vendors, chat) leave the camera alone.",
  target = "Shoulder view after you lock a target with the target-lock key. "
        .. "Clearing the target (Esc) centers it again.",
}

local function buildCameraPage(page)
  local C = ns.db.camera

  local hCam = sectionHeader(page, "Over-the-shoulder camera", pageTop(page), 0)
  local sub = smallLabel(page, "Moves your character off the reticle. Aim stays at screen center.", hCam, 0, -6)

  local desc = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local function paintDesc() desc:SetText(MODE_TEXT[C.mode] or "") end

  local modeBtns, modeRepaint = makeChoiceRow(page,
    { { label = "Off", value = "off", w = 48 },
      { label = "Always", value = "always", w = 62 },
      { label = "Cursor key", value = "cursor", w = 86 },
      { label = "Target lock", value = "target", w = 90 } },
    function() return C.mode end,
    function(v) C.mode = v; paintDesc(); ns.UpdateShoulder() end)
  modeBtns[1]:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
  repaints[#repaints+1] = function() modeRepaint(); paintDesc() end

  desc:SetPoint("TOPLEFT", modeBtns[1], "BOTTOMLEFT", 0, -10)
  desc:SetPoint("RIGHT", page, "RIGHT", 0, 0)
  desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
  desc:SetTextColor(0.85, 0.85, 0.85)
  desc:SetHeight(56)
  paintDesc()

  local off = makeSliderRow(page, "Offset", -3, 3, 0.1, 1,
    function() return C.offset end,
    function(v) C.offset = v; ns.UpdateShoulder() end)
  off:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 4, -8)
  controls[#controls+1] = off

  local flip = makeButton(page, "Switch shoulder", 120, function()
    C.offset = -(C.offset or 1.2); off:Reload(); ns.UpdateShoulder()
  end)
  flip:SetPoint("TOPLEFT", off, "BOTTOMLEFT", -4, -10)

  local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", flip, "BOTTOMLEFT", 4, -14)
  note:SetPoint("RIGHT", page, "RIGHT", 0, 0)
  note:SetJustifyH("LEFT"); note:SetWordWrap(true)
  note:SetText("Uses the game's hidden over-shoulder camera setting. The game may "
    .. "show a warning about experimental camera features the first time it turns on. "
    .. "Also: /ctpi shoulder cycles modes.")
end

-- ===== BEHAVIOR ==============================================================
local function buildBehaviorPage(page)
  local db = ns.db

  local hBeh = sectionHeader(page, "Clicking (while the camera is locked)", pageTop(page), 0)
  local CLICK_CHOICES = {
    { label = "Interact", value = "INTERACTMOUSEOVER", w = 62 },
    { label = "Hold run", value = "MOVEFORWARD",       w = 66 },
    { label = "Autorun",  value = "TOGGLEAUTORUN",     w = 64 },
    { label = "Nothing",  value = "",                  w = 60 },
  }

  local leftLbl = smallLabel(page, "Left-click", hBeh, 0, -8)
  local leftBtns, leftRepaint = makeChoiceRow(page, CLICK_CHOICES,
    function() return db.leftAction end,
    function(v)
      db.leftAction = v; ns.RefreshBindings()
      if not InCombatLockdown() and ns.ApplyNativeClick then ns.ApplyNativeClick() end
    end)
  leftBtns[1]:SetPoint("TOPLEFT", leftLbl, "BOTTOMLEFT", 0, -6)
  repaints[#repaints+1] = leftRepaint

  local enemyLbl = smallLabel(page, "Left-click on enemies (when left is Interact)", leftBtns[1], 0, -10)
  local enemyBtns, enemyRepaint = makeChoiceRow(page,
    { { label = "Interact",      value = "interact",   w = 70 },
      { label = "Lock target",   value = "lock",       w = 92 },
      { label = "Lock + attack", value = "lockattack", w = 108 } },
    function() return db.leftEnemy or "interact" end,
    function(v)
      if InCombatLockdown() then return end
      db.leftEnemy = v
      if ns.UpdateEnemyMacro then ns.UpdateEnemyMacro() end
      ns.RefreshBindings()
    end)
  enemyBtns[1]:SetPoint("TOPLEFT", enemyLbl, "BOTTOMLEFT", 0, -6)
  repaints[#repaints+1] = enemyRepaint

  local rightLbl = smallLabel(page, "Right-click", enemyBtns[1], 0, -10)
  local rightBtns, rightRepaint = makeChoiceRow(page, CLICK_CHOICES,
    function() return db.rightAction end,
    function(v) db.rightAction = v; ns.RefreshBindings() end)
  rightBtns[1]:SetPoint("TOPLEFT", rightLbl, "BOTTOMLEFT", 0, -6)
  repaints[#repaints+1] = rightRepaint

  local clickNote = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  clickNote:SetPoint("TOPLEFT", rightBtns[1], "BOTTOMLEFT", 0, -8)
  clickNote:SetPoint("RIGHT", page, "RIGHT", 0, 0)
  clickNote:SetJustifyH("LEFT"); clickNote:SetWordWrap(true)
  clickNote:SetText("Interact attacks enemies and talks / loots / gathers everything else. "
    .. "One action per button: tap-to-interact + hold-to-run on the same button isn't "
    .. "possible while the camera is locked, so put them on different buttons.")

  local cStopAuto = makeCheck(page, "Left-click stops autorun (when left is Interact, out of combat)",
    function() return db.leftStopsAutorun end,
    function(v) db.leftStopsAutorun = v; if ns.SyncAutorunSwap then ns.SyncAutorunSwap() end end)
  cStopAuto:SetPoint("TOPLEFT", clickNote, "BOTTOMLEFT", -4, -6)
  controls[#controls+1] = cStopAuto

  local hSoft = sectionHeader(page, "Look to target", cStopAuto, -12)
  local cSoftE = makeCheck(page, "Enemies (look at a mob to target it)",
    function() return db.softTargetEnemy end,
    function(v) db.softTargetEnemy = v; ns.ApplySoftTarget() end)
  cSoftE:SetPoint("TOPLEFT", hSoft, "BOTTOMLEFT", -4, -4)
  controls[#controls+1] = cSoftE
  local cSoftF = makeCheck(page, "Friendlies (look to heal)",
    function() return db.softTargetFriend end,
    function(v) db.softTargetFriend = v; ns.ApplySoftTarget() end)
  cSoftF:SetPoint("TOPLEFT", cSoftE, "BOTTOMLEFT", 0, -2)
  controls[#controls+1] = cSoftF
  local cSoftI = makeCheck(page, "Interactables (npcs, nodes, mailboxes, corpses)",
    function() return db.softTargetInteract end,
    function(v) db.softTargetInteract = v; ns.ApplySoftTarget() end)
  cSoftI:SetPoint("TOPLEFT", cSoftF, "BOTTOMLEFT", 0, -2)
  controls[#controls+1] = cSoftI

  local hCur = sectionHeader(page, "Cursor", cSoftI, -12)
  local cFocus = makeCheck(page, "Unlock cursor when the window loses focus",
    function() return db.unlockOnFocusLoss end,
    function(v) db.unlockOnFocusLoss = v; ns.ApplyBackgroundCap(); ns.ForceReconcile() end)
  cFocus:SetPoint("TOPLEFT", hCur, "BOTTOMLEFT", -4, -4)
  controls[#controls+1] = cFocus
  local cBk = makeCheck(page, "   Set background FPS to 8 so this is reliable (restored on logout)",
    function() return db.manageBackgroundFps end,
    function(v) db.manageBackgroundFps = v; ns.ApplyBackgroundCap(); ns.ForceReconcile() end)
  cBk:SetPoint("TOPLEFT", cFocus, "BOTTOMLEFT", 0, -2)
  controls[#controls+1] = cBk
  local cDbg = makeCheck(page, "Debug messages in chat (why the cursor frees)",
    function() return ns.debug and true or false end,
    function(v) ns.debug = v; ns.lastWhy = false end)
  cDbg:SetPoint("TOPLEFT", cBk, "BOTTOMLEFT", 0, -2)
  controls[#controls+1] = cDbg

  -- target-tools readout (binds are set via slash; this just reflects them)
  local cDlg = makeCheck(page, "Quest / gossip keys: arrows, space, 1-9 (camera stays locked)",
    function() return db.dialog.keys end,
    function(v) db.dialog.keys = v; if ns.RefreshDialogKeys then ns.RefreshDialogKeys() end end)
  cDlg:SetPoint("TOPLEFT", cDbg, "BOTTOMLEFT", 0, -2)
  controls[#controls+1] = cDlg

  local hKeys = sectionHeader(page, "Keys", cDlg, -12)
  local toolsLbl = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  toolsLbl:SetPoint("TOPLEFT", hKeys, "BOTTOMLEFT", 0, -6)
  toolsLbl:SetPoint("RIGHT", page, "RIGHT", 0, 0)
  toolsLbl:SetJustifyH("LEFT"); toolsLbl:SetWordWrap(true)
  toolsLbl.Reload = function(self)
    local function k(v) return (v and v ~= "") and v or "unbound" end
    self:SetText("Target lock |cFFc8a25e" .. k(db.lockKey) .. "|r   "
      .. "Set focus |cFFc8a25e" .. k(db.focusKey) .. "|r   "
      .. "Clear focus |cFFc8a25e" .. k(db.clearFocusKey) .. "|r   "
      .. "Interact |cFFc8a25e" .. k(db.interactKey) .. "|r\n"
      .. "|cFF888888change with /ctpi lockkey|focuskey|clearfocuskey|interactkey <BIND|none>.\n"
      .. "Master toggle and free cursor are in Key Bindings > AddOns.|r")
  end
  toolsLbl:Reload()
  controls[#controls+1] = toolsLbl
end

local function buildPanel()
  panel = CreateFrame("Frame", "CTPIConfigFrame", UIParent, "BackdropTemplate")
  panel:SetSize(360, 740)
  -- default off to the left so the centered reticle stays visible
  panel:SetPoint("LEFT", UIParent, "LEFT", 40, 0)
  panel:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  panel:SetBackdropColor(0.05, 0.04, 0.03, 0.94)
  panel:SetBackdropBorderColor(0.78, 0.64, 0.37, 1)
  panel:SetFrameStrata("DIALOG")
  panel:SetClampedToScreen(true)
  panel:SetMovable(true); panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    ns.db.uiPos = { point = point, x = x, y = y }
  end)
  panel:SetScript("OnShow", function() ns.PreviewReticle(true) end)
  panel:SetScript("OnHide", function() ns.PreviewReticle(false); ns.ForceReconcile() end)
  tinsert(UISpecialFrames, "CTPIConfigFrame")   -- ESC closes

  if ns.db.uiPos then
    local pz = ns.db.uiPos
    panel:ClearAllPoints()
    panel:SetPoint(pz.point, UIParent, pz.point, pz.x, pz.y)
  end

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
  title:SetText("Coffee's Touchpad Improvements")
  title:SetTextColor(0.85, 0.70, 0.42)

  CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    :SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)

  -- tabs
  local TABS = {
    { key = "reticle",  label = "Reticle",  w = 66, build = buildReticlePage },
    { key = "label",    label = "Label",    w = 56, build = buildLabelPage },
    { key = "hud",      label = "HUD",      w = 50, build = buildHUDPage },
    { key = "camera",   label = "Camera",   w = 66, build = buildCameraPage },
    { key = "behavior", label = "Behavior", w = 76, build = buildBehaviorPage },
  }
  local prev
  for _, t in ipairs(TABS) do
    local b = makeButton(panel, t.label, t.w, function() selectTab(t.key) end)
    b.key = t.key
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    else b:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -12) end
    tabBtns[#tabBtns + 1] = b
    prev = b

    local page = CreateFrame("Frame", nil, panel)
    page:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -86)
    page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 16)
    t.build(page)
    page:Hide()
    pages[t.key] = page
  end

  -- divider under the tabs
  local line = panel:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(0.78, 0.64, 0.37, 0.35)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -78)
  line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -78)

  selectTab(pages[ns.db.uiTab or ""] and ns.db.uiTab or "reticle")
  panel.repaints = repaints
end

local function ensurePanel()
  -- frames are created shown by default; build then hide so the very first
  -- ToggleConfig/OpenConfig actually shows it (was: build-shown -> toggle hid it)
  if not panel then buildPanel(); panel:Hide() end
end

local function showPanel()
  ensurePanel()
  for _, c in ipairs(controls) do if c.Reload then c:Reload() end end
  for _, fn in ipairs(panel.repaints) do fn() end
  panel:Show()
end

function ns.ToggleConfig()
  ensurePanel()
  if panel:IsShown() then panel:Hide() else showPanel() end
end

-- always-open (used by the Blizzard options button). closes the options /
-- game-menu frames first so the floating panel isn't hidden behind them.
function ns.OpenConfig()
  if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
    HideUIPanel(InterfaceOptionsFrame)
  end
  if GameMenuFrame and GameMenuFrame:IsShown() then
    HideUIPanel(GameMenuFrame)
  end
  -- modern Settings window (Forever). out of combat only, to stay clear of taint
  if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then
    HideUIPanel(SettingsPanel)
  end
  showPanel()
end

-- ---- Blizzard options category (Interface > AddOns) --------------------------
-- Two paths:
--   * 2.5.5 uses the OLD InterfaceOptions_AddCategory API. The Settings.* API
--     corrupts the addon list there, so when the old API exists we use it.
--   * Forever (modern Mainline UI) has no InterfaceOptions_AddCategory, so we
--     register a canvas category with Settings.* instead.
-- Registered once; guarded against the duplicate-registration corruption that
-- bites on /reload.
local optPanel
function ns.BuildOptionsCategory()
  if optPanel then return end
  local legacy = InterfaceOptions_AddCategory
  local modern = Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
  if not (legacy or modern) then return end

  optPanel = CreateFrame("Frame", "CTPIOptionsPanel", UIParent)
  optPanel.name = "coffee-tan"

  local title = optPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("coffee-tan  |cFF888888(CTPI)|r")

  local desc = optPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  desc:SetPoint("RIGHT", optPanel, "RIGHT", -32, 0)
  desc:SetJustifyH("LEFT")
  desc:SetText("Always-on mouselook and reticle targeting for trackpad play. "
    .. "All settings live in a movable window, opened below or with /ctpi.")

  local btn = CreateFrame("Button", nil, optPanel, "UIPanelButtonTemplate")
  btn:SetSize(190, 26)
  btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
  btn:SetText("Open CTPI settings")
  btn:SetScript("OnClick", function() ns.OpenConfig() end)

  if legacy then
    -- guard: don't add twice (prevents addon-list corruption on /reload)
    local cats = INTERFACEOPTIONS_ADDONCATEGORIES
    if type(cats) == "table" then
      for _, c in ipairs(cats) do
        if c == optPanel or (type(c) == "table" and c.name == optPanel.name) then return end
      end
    end
    InterfaceOptions_AddCategory(optPanel)
  else
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, optPanel, optPanel.name)
    if ok and cat then
      pcall(Settings.RegisterAddOnCategory, cat)
      ns.settingsCategory = cat
    end
  end
end
