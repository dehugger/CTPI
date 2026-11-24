-- CTPI debug window: a live readout of what CTPI thinks is going on, plus a
-- scrolling log of every change (cursor lock / free, what left-click is bound
-- to, target swaps, combat, combo points, focus loss, the radial).
--
-- /ctpi debug (or the quick menu) opens it. While it's open, ns.debug is on
-- and the rest of the addon reports into it with ns.Log. It never frees the
-- cursor by being open, so you can watch it while playing.
--
-- Nothing here hooks secure frames' attribute handlers (that can taint the
-- game's own state-driver loop); everything is polled from addon code.
local ADDON, ns = ...

local MAX_LINES = 400
local lines = {}          -- plain-text copy of the log, for the Copy box
local frame, logFrame, stateFS, copyFrame
local paused = false

local COLORS = {
  cursor = "88ccff", click = "c8a25e", bind = "b48cff", target = "ff8866",
  combat = "ff4444", focus = "66dd88", radial = "ffd24d", combo = "ffaa33", look = "dddddd",
  info = "aaaaaa",
}

local function plain(v)
  if ns.IsSecret(v) then return "<secret>" end
  return v
end

local function stamp()
  local t = GetTime()
  return string.format("%s.%02d", date("%H:%M:%S"), math.floor((t % 1) * 100))
end

-- the one entry point: ns.Log("cursor", "free: radial menu open")
function ns.Log(cat, msg)
  if not ns.debug then return end
  local line = stamp() .. " [" .. cat .. "] " .. tostring(msg)
  lines[#lines + 1] = line
  if #lines > MAX_LINES then table.remove(lines, 1) end
  if logFrame and not paused then
    logFrame:AddMessage("|cFF666666" .. stamp() .. "|r |cFF" .. (COLORS[cat] or "ffffff")
      .. cat .. "|r " .. tostring(msg))
  end
end

-- ---------------------------------------------------------------------
-- readable names for what a mouse button is bound to right now
-- ---------------------------------------------------------------------
local CLICK_NAMES = {
  CTPIEnemyClickButton  = "enemy click (target + act)",
  CTPIEnemyLockedButton = "LOCKED (act on target)",
  CTPIFriendClickButton = "friend click (heal)",
  CTPIUnlockButton      = "unlock (clear target)",
  CTPITabLockButton     = "tab: target what you look at",
  CTPITabUnlockButton   = "tab: unlock (clear target)",
}
local function bindingName(key)
  local a = GetBindingAction and GetBindingAction(key, true)
  if not a or a == "" then return "nothing" end
  local btn = a:match("^CLICK ([^:]+)")
  if btn then
    if btn:match("^CTPIRadial") then return "radial" end
    return CLICK_NAMES[btn] or btn
  end
  return a:lower()
end

local function unitDesc(u)
  local e = UnitExists(u)
  if ns.IsSecret(e) then return "<secret>" end
  if not e then return "-" end
  local n = plain(UnitName(u)) or "?"
  local tags = {}
  local d = UnitIsDead(u)
  if not ns.IsSecret(d) and d then tags[#tags + 1] = "dead" end
  local h = UnitCanAttack("player", u)
  if not ns.IsSecret(h) then tags[#tags + 1] = h and "hostile" or "not hostile" end
  return n .. (#tags > 0 and (" (" .. table.concat(tags, ", ") .. ")") or "")
end

local function yn(v, yes, no)
  if v then return "|cFF66dd88" .. (yes or "yes") .. "|r" end
  return "|cFF888888" .. (no or "no") .. "|r"
end

local function stateText()
  local db = ns.db
  if not db then return "not loaded yet" end
  local out = {}
  local function add(k, v) out[#out + 1] = "|cFFc8a25e" .. k .. "|r  " .. v end

  local free, why = ns.ShouldFreeCursor()
  add("CTPI", yn(db.enabled, "on", "OFF") .. "   mouselook " .. yn(IsMouselooking())
    .. "   cursor " .. (free and ("|cFFff8800free|r: " .. why) or "|cFF66dd88locked|r"))
  if ns.FocusDebug then
    local fps, thr, slow, lost, by = ns.FocusDebug()
    add("focus", string.format("%s   fps %d (bg below %d)   slow for %.2fs   Cmd %s",
      lost and ("|cFFff8800AWAY|r (" .. tostring(by) .. ")") or "|cFF66dd88here|r", fps, thr, slow,
      (IsMetaKeyDown and IsMetaKeyDown()) and "down" or "up"))
  end
  add("combat", yn(InCombatLockdown()) .. "   stealth " .. yn((ns.PlayerStealthed())) .. "   form "
    .. tostring(plain(GetShapeshiftForm and GetShapeshiftForm())))

  add("target", unitDesc("target"))
  local cp = ns.GetComboPoints and ns.GetComboPoints()
  if cp ~= nil then add("combo pts", tostring(plain(cp))) end
  add("mouseover", unitDesc("mouseover"))
  add("soft", "enemy " .. unitDesc("softenemy") .. "   interact " .. unitDesc("softinteract"))

  add("left-click", bindingName("BUTTON1"))
  add("right-click", bindingName("BUTTON2"))
  local tk = ns.TabKeys and ns.TabKeys()
  if tk then add(tk, bindingName(tk)) end
  local aim = CTPIAimHeader and CTPIAimHeader:GetAttribute("state-aim")
  add("aim driver", (ns.AimHeaderActive and ns.AimHeaderActive()) and tostring(aim)
    or ("|cFF888888off|r" .. (ns.secureAimOK and "" or " (secure path unavailable)")))
  if ns.ComboLockSpec then
    local on, form = ns.ComboLockSpec()
    add("combo lock", (on and ("|cFF66dd88armed for this class|r" .. (form and (" (form " .. form .. ")") or ""))
      or "|cFF888888off|r") .. "   active now " .. yn(ns.ComboLocked and ns.ComboLocked())
      .. "   unlock primed " .. yn(ns.UnlockArmed and ns.UnlockArmed()))
  end
  add("hard lock", yn(db.hardLock, "on", "off") .. "   locked now " .. yn(ns.HardLocked and ns.HardLocked())
    .. "   left on enemies: " .. tostring(db.leftEnemy))
  add("other", "autorun swap " .. yn(ns.autorunSwap) .. "   free-cursor key " .. yn(ns.freeCursorHeld)
    .. "   radial " .. yn(ns.RadialOpen and ns.RadialOpen(), "open", "closed"))
  return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------
-- change watcher: polls the things that have no event of their own and
-- logs the transitions
-- ---------------------------------------------------------------------
local last = {}
local function watch(key, value, cat, fmt)
  if last[key] ~= value then
    if last[key] ~= nil or key == "why" then ns.Log(cat, fmt(value, last[key])) end
    last[key] = value
  end
end

local function poll()
  if not ns.db then return end
  local free, why = ns.ShouldFreeCursor()
  watch("why", free and why or "locked", "cursor", function(v)
    return v == "locked" and "locked (mouselook)" or ("free: " .. v)
  end)
  watch("b1", bindingName("BUTTON1"), "bind", function(v) return "left-click -> " .. v end)
  watch("b2", bindingName("BUTTON2"), "bind", function(v) return "right-click -> " .. v end)
  local tk = ns.TabKeys and ns.TabKeys()
  if tk then watch("tab", bindingName(tk), "bind", function(v) return tk .. " -> " .. v end) end
  local aim = CTPIAimHeader and CTPIAimHeader:GetAttribute("state-aim") or "-"
  watch("aim", tostring(aim), "bind", function(v) return "aim driver state: " .. v end)
  watch("armed", (ns.UnlockArmed and ns.UnlockArmed()) and "yes" or "no", "click", function(v)
    return v == "yes" and "unlock primed (right-click again to unlock)" or "unlock disarmed"
  end)
  watch("combo", (ns.ComboLocked and ns.ComboLocked()) and "on" or "off", "combo", function(v)
    return "combo lock " .. (v == "on" and "holding your target" or "released")
  end)
  local cp = ns.GetComboPoints and ns.GetComboPoints()
  if cp ~= nil and not ns.IsSecret(cp) then
    watch("cp", cp, "combo", function(v, old) return "combo points " .. tostring(old) .. " -> " .. tostring(v) end)
  end
  watch("radial", (ns.RadialOpen and ns.RadialOpen()) and "open" or "closed", "radial",
    function(v) return "radial " .. v end)
end

-- ---------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------
local function savePos()
  local db = ns.db
  if not (db and frame) then return end
  local p, _, rp, x, y = frame:GetPoint(1)
  db.debugPos = { p, rp, x, y }
end

local function makeButton(parent, text, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 20)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function showCopy()
  if not copyFrame then
    copyFrame = CreateFrame("Frame", "CTPIDebugCopyFrame", frame, "BackdropTemplate")
    copyFrame:SetAllPoints(logFrame:GetParent())
    copyFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
    copyFrame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    copyFrame:SetBackdropColor(0, 0, 0, 0.95)
    local sf = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6); sf:SetPoint("BOTTOMRIGHT", -26, 6)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(GameFontHighlightSmall)
    eb:SetWidth(sf:GetWidth() > 0 and sf:GetWidth() or 380)
    eb:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    sf:SetScrollChild(eb)
    copyFrame.eb = eb
    copyFrame:SetScript("OnHide", function() eb:ClearFocus() end)
  end
  local eb = copyFrame.eb
  eb:SetText(stateText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "\n\n" .. table.concat(lines, "\n"))
  copyFrame:Show()
  eb:SetFocus()
  eb:HighlightText()
end

local function build()
  if frame then return end
  frame = CreateFrame("Frame", "CTPIDebugFrame", UIParent, "BackdropTemplate")
  frame:SetSize(440, 560)
  frame:SetFrameStrata("HIGH")
  frame:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0.05, 0.05, 0.07, 0.88)
  local pos = ns.db and ns.db.debugPos
  if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0) end
  frame:SetMovable(true); frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("CTPI debug")
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", title, "RIGHT", 8, 0)
  hint:SetText("drag to move (with the cursor free)")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() ns.ToggleDebugWindow(false) end)

  stateFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  stateFS:SetPoint("TOPLEFT", 12, -32)
  stateFS:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
  stateFS:SetJustifyH("LEFT"); stateFS:SetJustifyV("TOP")
  stateFS:SetSpacing(2)
  stateFS:SetWordWrap(true)

  -- log area
  local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  box:SetPoint("TOPLEFT", stateFS, "BOTTOMLEFT", -4, -8)
  box:SetPoint("BOTTOMRIGHT", -8, 34)
  box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
  box:SetBackdropColor(0, 0, 0, 0.5)
  logFrame = CreateFrame("ScrollingMessageFrame", nil, box)
  logFrame:SetPoint("TOPLEFT", 6, -4); logFrame:SetPoint("BOTTOMRIGHT", -6, 4)
  logFrame:SetFontObject(GameFontHighlightSmall)
  logFrame:SetJustifyH("LEFT")
  logFrame:SetFading(false)
  logFrame:SetMaxLines(MAX_LINES)
  logFrame:SetInsertMode("BOTTOM")
  logFrame:EnableMouseWheel(true)
  logFrame:SetScript("OnMouseWheel", function(self, d)
    if d > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  for _, l in ipairs(lines) do logFrame:AddMessage(l) end

  local clear = makeButton(frame, "Clear", 60, function()
    wipe(lines); logFrame:Clear()
  end)
  clear:SetPoint("BOTTOMLEFT", 10, 8)
  local pause
  pause = makeButton(frame, "Pause", 60, function()
    paused = not paused
    pause:SetText(paused and "Resume" or "Pause")
    if not paused then
      logFrame:Clear()
      for _, l in ipairs(lines) do logFrame:AddMessage(l) end
    end
  end)
  pause:SetPoint("LEFT", clear, "RIGHT", 6, 0)
  local copy = makeButton(frame, "Copy", 60, showCopy)
  copy:SetPoint("LEFT", pause, "RIGHT", 6, 0)
  local copyHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  copyHint:SetPoint("LEFT", copy, "RIGHT", 8, 0)
  copyHint:SetText("Copy: state + log, then Cmd-C")

  -- live state, 5x a second; transitions every tick
  local acc, pacc = 0, 0
  frame:SetScript("OnUpdate", function(_, el)
    pacc = pacc + el
    if pacc >= 0.05 then pacc = 0; poll() end
    acc = acc + el
    if acc >= 0.2 then acc = 0; stateFS:SetText(stateText()) end
  end)

  -- events with names of their own
  frame:RegisterEvent("PLAYER_TARGET_CHANGED")
  frame:RegisterEvent("PLAYER_REGEN_DISABLED")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:RegisterEvent("UPDATE_BINDINGS")
  frame:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_TARGET_CHANGED" then
      ns.Log("target", "target -> " .. unitDesc("target"))
    elseif ev == "PLAYER_REGEN_DISABLED" then
      ns.Log("combat", "entered combat")
    elseif ev == "PLAYER_REGEN_ENABLED" then
      ns.Log("combat", "left combat")
    elseif ev == "UPDATE_BINDINGS" then
      ns.Log("info", "UPDATE_BINDINGS (binding redraw)")
    end
  end)

  frame:Hide()
end

-- which CTPI button a click landed on (post-hooks: they run after the secure
-- click is done, so they can't get in its way)
local hooked = false
local function hookClicks()
  if hooked then return end
  hooked = true
  for name, desc in pairs(CLICK_NAMES) do
    local b = _G[name]
    if b then
      b:HookScript("OnClick", function(_, button, down)
        if not down then return end
        ns.Log("click", desc .. " fired, target " .. unitDesc("target"))
      end)
    end
  end
end

function ns.ToggleDebugWindow(on)
  build()
  if on == nil then on = not frame:IsShown() end
  ns.debug = on and true or false
  if ns.db then ns.db.debugOpen = ns.debug end
  if on then
    hookClicks()
    wipe(last)
    frame:Show()
    stateFS:SetText(stateText())
    ns.Log("info", "debug window opened")
  else
    frame:Hide()
  end
end

-- reopen after a /reload if it was open
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  if ns.db and ns.db.debugOpen then
    C_Timer.After(1, function() ns.ToggleDebugWindow(true) end)
  end
end)
