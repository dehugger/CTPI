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

-- ground spells (Distract, Blizzard...) cast at the crosshair: /cast [@cursor].
-- while the camera is locked CTPI keeps the game's cursor centering on, so
-- the hidden cursor sits on the crosshair and "@cursor" means "where I'm
-- looking". (only once you've put ground macros on your bars.)
ns.GROUND_DEFAULTS = {
  ROGUE   = "Distract",
  MAGE    = "Blizzard, Flamestrike",
  WARLOCK = "Rain of Fire",
  DRUID   = "Hurricane",
  HUNTER  = "Volley, Flare",
  PRIEST  = "Mass Dispel",
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

function ns.GroundList()
  local cfg = ns.ClassConfig and ns.ClassConfig()
  if not cfg then return "" end
  if cfg.ground == nil then cfg.ground = ns.GROUND_DEFAULTS[ns.PlayerClass()] or "" end
  return cfg.ground
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
  local function add(list, ground)
    for raw in (list .. ","):gmatch("([^,]*),") do
      local s = raw:gsub("^%s+", ""):gsub("%s+$", "")
      if s ~= "" then
        local n = knownSpellName(s)
        if n then out[#out + 1] = { spell = n, macro = (PREFIX .. n):sub(1, 16), ground = ground }
        else unknown[#unknown + 1] = s end
      end
    end
  end
  add(ns.ReticleList(), false)
  add(ns.GroundList(), true)
  return out, unknown
end

local function body(spell, ground)
  if ground then return "#showtooltip " .. spell .. "\n/cast [@cursor] " .. spell end
  return "#showtooltip " .. spell .. "\n/cast [@mouseover,harm,nodead][] " .. spell
end

-- create / update the macros. returns made, unknown, failed (lists)
local function makeMacros()
  local list, unknown = entries()
  local made, failed = {}, {}
  for _, e in ipairs(list) do
    local idx = GetMacroIndexByName(e.macro)
    if idx and idx > 0 then
      EditMacro(idx, e.macro, ICON, body(e.spell, e.ground))
      made[#made + 1] = e
    else
      local _, chars = GetNumMacros()
      local maxChar = MAX_CHARACTER_MACROS or 18
      local ok = chars < maxChar and pcall(CreateMacro, e.macro, ICON, body(e.spell, e.ground), true)
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
  local names, anyGround = {}, false
  for _, e in ipairs(made) do
    names[#names + 1] = e.spell .. (e.ground and " (at crosshair)" or "")
    if e.ground then anyGround = true end
  end
  -- ground macros only aim right with the cursor held on the crosshair
  ns.db.groundAim = anyGround or nil
  ns.ForceReconcile()
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
  ns.db.groundAim = nil
  if ns.SetAimCentering then ns.SetAimCentering(false) end
  p("reticle casts: put " .. back .. " plain spell(s) back on your bars.")
end
