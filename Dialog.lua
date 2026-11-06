local addonName, ns = ...

-- =====================================================================
-- CTPI / Dialog.lua
-- Quest + gossip by keyboard, without freeing the cursor.
--
-- While an NPC dialog is open (gossip, quest greeting, quest text, turn-in,
-- reward), CTPI keeps mouselook on and shows a small numbered list under the
-- reticle with everything you can do there:
--   UP / DOWN       move the selection
--   RIGHT / SPACE / ENTER   pick the selected line
--   LEFT            back out: goodbye / decline / close
--   1 - 9           pick a line directly
--   ESC             close (the game's own)
-- The keys are override bindings that only exist while the dialog is open,
-- so space / enter / 1-9 / arrows go back to normal the moment it closes.
--
-- Combat: bindings can only change out of combat, so dialogs opened in
-- combat just free the cursor like before, and the keys are dropped the
-- moment combat starts (PLAYER_REGEN_DISABLED still allows it).
--
-- Everything is done through the quest / gossip API (C_GossipInfo,
-- AcceptQuest, GetQuestReward...), in our own order: turn-ins first, then
-- new quests, then quests in progress, then gossip options, then goodbye.
-- =====================================================================

local KEYS = {
  UP = "Up", DOWN = "Down", RIGHT = "Go", LEFT = "Back", SPACE = "Go", ENTER = "Go",
  ["1"] = "1", ["2"] = "2", ["3"] = "3", ["4"] = "4", ["5"] = "5",
  ["6"] = "6", ["7"] = "7", ["8"] = "8", ["9"] = "9",
}
local SKIP = { GossipFrame = true, QuestFrame = true }
local MAX_LINES = 14

local items, sel, kind, header = {}, 1, nil, nil
local lastQuestKind
local bound = false

local owner = CreateFrame("Frame", "CTPIDialogBindingOwner", UIParent)
local keyBtn = CreateFrame("Button", "CTPIDialogKeyButton", UIParent)
keyBtn:SetSize(1, 1)
keyBtn:RegisterForClicks("AnyDown")

-- Core.lua asks this while deciding whether a window should free the cursor
function ns.DialogSkipFrames()
  if bound then return SKIP end
end

local function enabled()
  local db = ns.db
  return db and db.enabled and db.dialog and db.dialog.keys
end

-- ---------------------------------------------------------------------
-- the list overlay
-- ---------------------------------------------------------------------
local list, headFS, hintFS
local lines = {}

local function buildList()
  if list then return end
  list = CreateFrame("Frame", "CTPIDialogList", UIParent, "BackdropTemplate")
  list:SetFrameStrata("TOOLTIP")
  list:SetWidth(320)
  list:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  list:SetBackdropColor(0.04, 0.03, 0.02, 0.82)
  list:SetBackdropBorderColor(0.78, 0.64, 0.37, 0.8)
  headFS = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  headFS:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -8)
  headFS:SetPoint("RIGHT", list, "RIGHT", -10, 0)
  headFS:SetJustifyH("LEFT"); headFS:SetWordWrap(false)
  for i = 1, MAX_LINES do
    local fs = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", (i == 1) and headFS or lines[i - 1], "BOTTOMLEFT", 0, (i == 1) and -6 or -3)
    fs:SetPoint("RIGHT", list, "RIGHT", -10, 0)
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    lines[i] = fs
  end
  hintFS = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hintFS:SetJustifyH("LEFT")
  hintFS:SetText("up/down: select    right/space: choose    left: back    1-9")
  list:Hide()
end

local function render()
  if not list then return end
  if not bound or #items == 0 then list:Hide(); return end
  local T = ns.db.tooltip
  list:ClearAllPoints()
  list:SetPoint("TOP", UIParent, "CENTER", T.x or 0, (T.y or -24) - 44)
  headFS:SetText(header or "")
  local n = math.min(#items, MAX_LINES)
  for i = 1, MAX_LINES do
    local fs = lines[i]
    if i <= n then
      local num = (i <= 9) and (i .. ". ") or "    "
      if i == sel then
        fs:SetText("|cFFc8a25e> " .. num .. "|r" .. items[i].label)
      else
        fs:SetText("|cFF777777  " .. num .. "|r" .. items[i].label)
      end
      fs:Show()
    else
      fs:Hide()
    end
  end
  hintFS:ClearAllPoints()
  hintFS:SetPoint("TOPLEFT", lines[n], "BOTTOMLEFT", 0, -6)
  list:SetHeight(8 + 16 + 6 + n * 17 + 6 + 12 + 10)
  list:Show()
end

-- ---------------------------------------------------------------------
-- building the choices
-- ---------------------------------------------------------------------
local function add(label, fn) items[#items + 1] = { label = label or "?", fn = fn } end

local function npcName()
  local n = UnitName("npc")
  if ns.IsSecret(n) then return nil end
  return n
end

local function buildGossip()
  local G = C_GossipInfo
  if not G then return end
  header = npcName()
  local active = (G.GetActiveQuests and G.GetActiveQuests()) or {}
  local avail  = (G.GetAvailableQuests and G.GetAvailableQuests()) or {}
  for _, q in ipairs(active) do
    if q.isComplete then
      add("|cFFFFD100?|r " .. (q.title or "?"), function() G.SelectActiveQuest(q.questID) end)
    end
  end
  for _, q in ipairs(avail) do
    add("|cFFFFD100!|r " .. (q.title or "?"), function() G.SelectAvailableQuest(q.questID) end)
  end
  for _, q in ipairs(active) do
    if not q.isComplete then
      add("|cFF888888?|r " .. (q.title or "?"), function() G.SelectActiveQuest(q.questID) end)
    end
  end
  local opts = (G.GetOptions and G.GetOptions()) or {}
  table.sort(opts, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
  for i, o in ipairs(opts) do
    add(o.name, function()
      local ok = o.gossipOptionID and pcall(G.SelectOption, o.gossipOptionID)
      if not ok and G.SelectOptionByIndex then pcall(G.SelectOptionByIndex, o.orderIndex or i) end
    end)
  end
  add("|cFF888888Goodbye|r", function() if G.CloseGossip then G.CloseGossip() end end)
end

local function buildGreeting()
  header = npcName()
  local nActive = (GetNumActiveQuests and GetNumActiveQuests()) or 0
  local nAvail  = (GetNumAvailableQuests and GetNumAvailableQuests()) or 0
  for i = 1, nActive do
    local title, done = GetActiveTitle(i)
    if done then add("|cFFFFD100?|r " .. (title or "?"), function() SelectActiveQuest(i) end) end
  end
  for i = 1, nAvail do
    add("|cFFFFD100!|r " .. (GetAvailableTitle(i) or "?"), function() SelectAvailableQuest(i) end)
  end
  for i = 1, nActive do
    local title, done = GetActiveTitle(i)
    if not done then add("|cFF888888?|r " .. (title or "?"), function() SelectActiveQuest(i) end) end
  end
  add("|cFF888888Goodbye|r", function() CloseQuest() end)
end

local function buildDetail()
  header = GetTitleText and GetTitleText() or npcName()
  if QuestGetAutoAccept and QuestGetAutoAccept() then
    add("OK", function()
      if AcknowledgeAutoAcceptQuest then pcall(AcknowledgeAutoAcceptQuest) end
      CloseQuest()
    end)
  else
    add("|cFF66FF66Accept|r", function() AcceptQuest() end)
    add("Decline", function() DeclineQuest() end)
  end
end

local function buildProgress()
  header = GetTitleText and GetTitleText() or npcName()
  if IsQuestCompletable and IsQuestCompletable() then
    add("|cFF66FF66Continue|r", function() CompleteQuest() end)
  else
    add("|cFF888888Not done yet (close)|r", function() CloseQuest() end)
  end
end

local function buildComplete()
  header = GetTitleText and GetTitleText() or npcName()
  local n = (GetNumQuestChoices and GetNumQuestChoices()) or 0
  if n > 1 then
    for i = 1, n do
      local name, tex = GetQuestItemInfo("choice", i)
      local icon = tex and ("|T" .. tex .. ":16:16|t ") or ""
      add(icon .. (name or ("Reward " .. i)), function() GetQuestReward(i) end)
    end
  else
    add("|cFF66FF66Complete quest|r", function() GetQuestReward(n == 1 and 1 or 0) end)
  end
end

local BUILDERS = {
  gossip = buildGossip, greeting = buildGreeting, detail = buildDetail,
  progress = buildProgress, complete = buildComplete,
}

local function rebuild()
  wipe(items); header = nil
  local fn = kind and BUILDERS[kind]
  if fn then pcall(fn) end
  if sel > #items or sel < 1 then sel = 1 end
end

-- ---------------------------------------------------------------------
-- bindings
-- ---------------------------------------------------------------------
local function bind()
  if bound or InCombatLockdown() or not enabled() then return end
  for key, b in pairs(KEYS) do
    SetOverrideBindingClick(owner, true, key, "CTPIDialogKeyButton", b)
  end
  bound = true
  ns.ForceReconcile()
end

local function unbind()
  if not bound or InCombatLockdown() then return end
  ClearOverrideBindings(owner)
  bound = false
  ns.ForceReconcile()
end

local function open(k)
  kind = k
  sel = 1
  rebuild()
  buildList()
  bind()
  render()
end

local function close()
  kind = nil
  wipe(items)
  unbind()
  render()
end

-- after any close event, look at what is actually still on screen (gossip
-- -> quest hand-offs fire their events in an inconvenient order)
local function recheck()
  local q, g = _G.QuestFrame, _G.GossipFrame
  if q and q:IsVisible() and lastQuestKind then
    if kind ~= lastQuestKind then open(lastQuestKind) end
  elseif g and g:IsVisible() then
    if kind ~= "gossip" then open("gossip") end
  else
    close()
  end
end

-- LEFT: back out of whatever screen this is
local function back()
  if kind == "gossip" then
    if C_GossipInfo and C_GossipInfo.CloseGossip then C_GossipInfo.CloseGossip() end
  elseif kind == "detail" and not (QuestGetAutoAccept and QuestGetAutoAccept()) then
    DeclineQuest()
  else
    CloseQuest()
  end
end

keyBtn:SetScript("OnClick", function(self, b)
  if not bound or #items == 0 then return end
  if b == "Up" then
    sel = (sel > 1) and (sel - 1) or #items
  elseif b == "Down" then
    sel = (sel < #items) and (sel + 1) or 1
  elseif b == "Go" then
    local it = items[sel]; if it then it.fn() end
  elseif b == "Back" then
    back()
  else
    local n = tonumber(b)
    if n and items[n] then sel = n; items[n].fn() end
  end
  render()
end)

-- ---------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------
local QUEST_KIND = {
  QUEST_GREETING = "greeting", QUEST_DETAIL = "detail",
  QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete",
}

local ev = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL",
                     "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED",
                     "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(self, event)
  if event == "GOSSIP_SHOW" then
    open("gossip")
  elseif QUEST_KIND[event] then
    lastQuestKind = QUEST_KIND[event]
    open(lastQuestKind)
  elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
    if event == "QUEST_FINISHED" then lastQuestKind = nil end
    C_Timer.After(0.05, recheck)
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- last moment bindings can still change: give the keys back for combat
    if bound then ClearOverrideBindings(owner); bound = false; render(); ns.ForceReconcile() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if kind then bind(); render() end
  end
end)

-- for the settings toggle / slash command
function ns.RefreshDialogKeys()
  if enabled() then
    if kind then bind(); render() end
  else
    unbind(); render()
  end
end
