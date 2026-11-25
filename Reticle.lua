-- Reticle casts: chosen spells (interrupts, CC) cast on whatever is under
-- the reticle, without changing your target. Under mouselook the game's
-- "mouseover" unit is exactly the thing at screen center, so a
--   /cast [@mouseover,harm,nodead][] Kick
-- macro kicks what you're looking at and falls back to your target when
-- you're looking at nothing. Your target (and its combo points) stays put.
--
-- The game has its own "mouseover cast" option, but it applies to every
-- spell, so builders would land on whatever crossed the reticle. This only
-- touches the spells you list.
--
-- CTPI writes one character macro per spell (named "CT:<spell>") and can
-- swap them onto your bars wherever the plain spell sits, and back again.
-- Macros and bars can only be changed out of combat.
local ADDON, ns = ...

ns.RETICLE_DEFAULTS = {
  ROGUE   = "Kick, Gouge, Blind, Sap",
  WARRIOR = "Pummel, Shield Bash",
  MAGE    = "Counterspell, Polymorph",
  WARLOCK = "Fear, Banish, Death Coil",
  PRIEST  = "Shackle Undead",
  SHAMAN  = "Earth Shock, Purge",
  PALADIN = "Hammer of Justice, Turn Undead",
  DRUID   = "Bash, Feral Charge, Entangling Roots, Hibernate",
  HUNTER  = "Scatter Shot, Wyvern Sting, Scare Beast",
}

local PREFIX = "CT:"
local ICON = 134400          -- question mark: #showtooltip swaps in the spell's own icon
local MAX_SLOTS = 180

local function p(msg) print("|cFFc8a25eCTPI|r: " .. msg) end

-- the saved list for this class (filled from the defaults the first time)
function ns.ReticleList()
  local cfg = ns.ClassConfig and ns.ClassConfig()
  if not cfg then return "" end
  if cfg.reticle == nil then cfg.reticle = ns.RETICLE_DEFAULTS[ns.PlayerClass()] or "" end
  return cfg.reticle
end

local function knownSpellName(name)
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
  if type(info) == "table" and info.name and not ns.IsSecret(info.name) then return info.name end
  if GetSpellInfo then
    local n = GetSpellInfo(name)
    if n and not ns.IsSecret(n) then return n end
  end
end

-- parsed list: { {spell=, macro=}, ... }, plus names that arent known
local function entries()
  local out, unknown = {}, {}
  for raw in (ns.ReticleList() .. ","):gmatch("([^,]*),") do
    local s = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if s ~= "" then
      local n = knownSpellName(s)
      if n then out[#out + 1] = { spell = n, macro = (PREFIX .. n):sub(1, 16) }
      else unknown[#unknown + 1] = s end
    end
  end
  return out, unknown
end

local function body(spell)
  return "#showtooltip " .. spell .. "\n/cast [@mouseover,harm,nodead][] " .. spell
end

-- create / update the macros. returns made, unknown, failed (lists)
local function makeMacros()
  local list, unknown = entries()
  local made, failed = {}, {}
  for _, e in ipairs(list) do
    local idx = GetMacroIndexByName(e.macro)
    if idx and idx > 0 then
      EditMacro(idx, e.macro, ICON, body(e.spell))
      made[#made + 1] = e
    else
      local _, chars = GetNumMacros()
      local maxChar = MAX_CHARACTER_MACROS or 18
      local ok = chars < maxChar and pcall(CreateMacro, e.macro, ICON, body(e.spell), true)
      if ok then made[#made + 1] = e else failed[#failed + 1] = e.spell end
    end
  end
  return made, unknown, failed
end

local function slotSpellName(slot)
  local t, id = GetActionInfo(slot)
  if t ~= "spell" or not id then return nil end
  local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
  if not n and GetSpellInfo then n = GetSpellInfo(id) end
  if ns.IsSecret(n) then return nil end
  return n
end

-- make the macros and put them on your bars in place of the plain spells
function ns.PlaceReticleMacros()
  if InCombatLockdown() then p("reticle casts: can't change macros or bars in combat"); return end
  local made, unknown, failed = makeMacros()
  local byName = {}
  for _, e in ipairs(made) do byName[e.spell] = e.macro end
  local swapped = 0
  ClearCursor()
  for slot = 1, MAX_SLOTS do
    local n = slotSpellName(slot)
    local m = n and byName[n]
    if m then
      PickupMacro(m)
      PlaceAction(slot)
      ClearCursor()
      swapped = swapped + 1
    end
  end
  local names = {}
  for _, e in ipairs(made) do names[#names + 1] = e.spell end
  p("reticle casts: " .. (#names > 0 and table.concat(names, ", ") or "none") .. " ready, "
    .. swapped .. " bar slot(s) swapped."
    .. (#unknown > 0 and (" Not in your spellbook: " .. table.concat(unknown, ", ") .. ".") or "")
    .. (#failed > 0 and (" No free character macro slot for: " .. table.concat(failed, ", ") .. ".") or ""))
  if swapped == 0 and #names > 0 then
    p("none of those spells were on your bars. Drag the CT: macros from /macro (character tab) onto them.")
  end
end

-- put the plain spells back where CT: macros sit (the macros themselves stay)
function ns.RestoreReticleSpells()
  if InCombatLockdown() then p("reticle casts: can't change bars in combat"); return end
  local back = 0
  ClearCursor()
  for slot = 1, MAX_SLOTS do
    local t = GetActionInfo(slot)
    local name = t == "macro" and GetActionText(slot)
    if name and not ns.IsSecret(name) and name:sub(1, #PREFIX) == PREFIX then
      local idx = GetMacroIndexByName(name)
      local _, _, mbody = GetMacroInfo(idx)
      local spell = mbody and mbody:match("#showtooltip ([^\n]+)")
      if spell then
        if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(spell) elseif PickupSpell then PickupSpell(spell) end
        if GetCursorInfo() then
          PlaceAction(slot)
          ClearCursor()
          back = back + 1
        end
      end
    end
  end
  p("reticle casts: put " .. back .. " plain spell(s) back on your bars.")
end

-- 3.1.0 dev builds wrote "/cast [@cursor]" ground macros (Distract at the
-- crosshair). without working cursor centering they land wherever the
-- hidden cursor happens to be, so turn any of those back into a plain cast
-- (the game's normal placement: the cursor frees and you click the spot).
local fix = CreateFrame("Frame")
fix:RegisterEvent("PLAYER_LOGIN")
fix:SetScript("OnEvent", function()
  C_Timer.After(2, function()
    if InCombatLockdown() or not GetNumMacros then return end
    local global, chars = GetNumMacros()
    local first = (MAX_ACCOUNT_MACROS or 120) + 1
    for idx = first, first + (chars or 0) - 1 do
      local name, _, mbody = GetMacroInfo(idx)
      if name and mbody and name:sub(1, #PREFIX) == PREFIX and mbody:find("@cursor", 1, true) then
        local spell = mbody:match("#showtooltip ([^\n]+)")
        if spell then EditMacro(idx, name, ICON, "#showtooltip " .. spell .. "\n/cast " .. spell) end
      end
    end
  end)
end)
