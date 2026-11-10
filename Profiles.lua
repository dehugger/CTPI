local addonName, ns = ...

-- =====================================================================
-- CTPI / Profiles.lua
-- Per-class setup: what a left-click on an enemy does in "lock + attack"
-- mode, the optional in-combat friendly click (healers), and the Shift
-- radial rings. Everything here is a starting point; it's copied into
-- the saved settings per class (db.classes[CLASS]) and edited from the
-- Class tab / setup wizard.
--
-- Spell names are English (this is what /cast and the radial use). On a
-- non-English client they need editing; the icons and casts follow
-- whatever names are saved.
--
-- Condition tokens: macro conditions can only name druid forms by index
-- ([form:2]), and the index depends on which forms you've learned. So
-- profiles write "{cat}", "{bear}", "{moonkin}"... and ns.ExpandTokens
-- swaps in the right index from your actual form bar.
-- =====================================================================

-- enemy click actions (lock + attack mode)
--   melee     auto attack
--   autoshot  Auto Shot (hunters)
--   spell     cast enemySpell at your target
--   druid     caster / moonkin: enemySpell, any other form: auto attack
ns.ENEMY_ACTIONS = {
  { "melee",    "Auto attack" },
  { "autoshot", "Auto Shot" },
  { "spell",    "Cast a spell" },
  { "druid",    "Druid (by form)" },
}

local function ring(name, cond, slots) return { name = name, cond = cond, slots = slots } end

ns.CLASS_DEFAULTS = {
  WARRIOR = { enemyAction = "melee", rings = {
    ring("Combat", "", { "Charge", "Hamstring", "Pummel", "Shield Bash", "Thunder Clap",
      "Intimidating Shout", "Rend", "Execute" }) } },
  ROGUE = { enemyAction = "melee", rings = {
    ring("Stealth", "[stealth][stance:1]", { "Sap", "Cheap Shot", "Garrote", "Ambush",
      "Pick Pocket", "Distract", "Sprint", "Blind" }),
    ring("Combat", "", { "Kick", "Gouge", "Kidney Shot", "Blind", "Evasion", "Sprint",
      "Vanish", "Feint" }) } },
  HUNTER = { enemyAction = "autoshot", rings = {
    ring("Combat", "", { "Hunter's Mark", "Concussive Shot", "Wing Clip", "Scatter Shot",
      "Freezing Trap", "Feign Death", "Mend Pet", "Aspect of the Cheetah" }) } },
  MAGE = { enemyAction = "spell", enemySpell = "Frostbolt", rings = {
    ring("Combat", "", { "Frost Nova", "Counterspell", "Polymorph", "Blink", "Fire Blast",
      "Cone of Cold", "Arcane Explosion", "Ice Block" }) } },
  WARLOCK = { enemyAction = "spell", enemySpell = "Shadow Bolt", rings = {
    ring("Combat", "", { "Corruption", "Curse of Agony", "Immolate", "Fear", "Death Coil",
      "Drain Life", "Life Tap", "Howl of Terror" }) } },
  PRIEST = { enemyAction = "spell", enemySpell = "Smite", friendSpell = "Flash Heal", rings = {
    ring("Combat", "", { "Power Word: Shield", "Renew", "Flash Heal", "Shadow Word: Pain",
      "Mind Blast", "Psychic Scream", "Fade", "Dispel Magic" }) } },
  SHAMAN = { enemyAction = "spell", enemySpell = "Lightning Bolt", friendSpell = "Healing Wave", rings = {
    ring("Combat", "", { "Earth Shock", "Flame Shock", "Frost Shock", "Purge",
      "Healing Wave", "Ghost Wolf", "Grounding Totem", "Tremor Totem" }) } },
  PALADIN = { enemyAction = "melee", friendSpell = "Flash of Light", rings = {
    ring("Combat", "", { "Judgement", "Hammer of Justice", "Holy Light", "Flash of Light",
      "Divine Protection", "Blessing of Protection", "Lay on Hands", "Cleanse" }) } },
  DRUID = { enemyAction = "druid", enemySpell = "Wrath", friendSpell = "Regrowth", rings = {
    ring("Prowl", "[stealth]", { "Pounce", "Ravage", "Shred", "Rake", "Dash", "Cower",
      "Faerie Fire (Feral)", "Tiger's Fury" }),
    ring("Cat", "[{cat}]", { "Rake", "Shred", "Rip", "Ferocious Bite", "Claw",
      "Tiger's Fury", "Dash", "Faerie Fire (Feral)" }),
    ring("Bear", "[{bear}]", { "Growl", "Bash", "Maul", "Swipe", "Demoralizing Roar",
      "Enrage", "Frenzied Regeneration", "Feral Charge" }),
    ring("Caster", "", { "Moonfire", "Entangling Roots", "Regrowth", "Rejuvenation",
      "Healing Touch", "Hibernate", "Innervate", "Faerie Fire" }) } },
  DEATHKNIGHT = { enemyAction = "melee", rings = { ring("Combat", "", {}) } },
  MONK        = { enemyAction = "melee", rings = { ring("Combat", "", {}) } },
  DEMONHUNTER = { enemyAction = "melee", rings = { ring("Combat", "", {}) } },
  EVOKER      = { enemyAction = "spell", enemySpell = "Living Flame", rings = { ring("Combat", "", {}) } },
}

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepcopy(v) end
  return c
end
ns.DeepCopy = deepcopy

function ns.PlayerClass()
  local _, class = UnitClass("player")
  return class or "WARRIOR"
end

-- this class's saved setup, created from the defaults the first time
function ns.ClassConfig()
  local db = ns.db
  if not db then return nil end
  db.classes = db.classes or {}
  local class = ns.PlayerClass()
  local cfg = db.classes[class]
  if not cfg then
    cfg = deepcopy(ns.CLASS_DEFAULTS[class] or { enemyAction = "melee", rings = { ring("Combat", "", {}) } })
    cfg.enemySpell = cfg.enemySpell or ""
    cfg.friendSpell = cfg.friendSpell or ""
    cfg.friendClick = false   -- opt-in: in combat, left-click a friendly to cast friendSpell
    db.classes[class] = cfg
  end
  return cfg
end

function ns.ResetClassConfig()
  if ns.db and ns.db.classes then ns.db.classes[ns.PlayerClass()] = nil end
  return ns.ClassConfig()
end

-- ---------------------------------------------------------------------
-- form tokens -> [form:N]
-- ---------------------------------------------------------------------
local FORM_SPELLS = {
  cat = { 768 }, bear = { 5487, 9634 }, moonkin = { 24858, 197625 }, travel = { 783 },
  aquatic = { 1066 }, tree = { 33891, 114282 }, flight = { 33943, 40120 }, shadow = { 15473 },
}
local FORM_NAMES = {
  cat = { "Cat Form" }, bear = { "Bear Form", "Dire Bear Form" }, moonkin = { "Moonkin Form" },
  travel = { "Travel Form" }, aquatic = { "Aquatic Form" }, tree = { "Tree of Life" },
  flight = { "Flight Form", "Swift Flight Form" }, shadow = { "Shadowform" },
}

-- GetShapeshiftFormInfo differs between clients (retail: icon, active,
-- castable, spellID; classic: icon, name, active, castable[, spellID]),
-- so look at every value it returns
function ns.FormIndex(key)
  if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then return nil end
  for i = 1, (GetNumShapeshiftForms() or 0) do
    local r = { GetShapeshiftFormInfo(i) }
    for _, v in ipairs(r) do
      if type(v) == "number" and not ns.IsSecret(v) then
        for _, id in ipairs(FORM_SPELLS[key] or {}) do if v == id then return i end end
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(v)
        if n and not ns.IsSecret(n) then
          for _, want in ipairs(FORM_NAMES[key] or {}) do if n == want then return i end end
        end
      elseif type(v) == "string" and not ns.IsSecret(v) then
        for _, want in ipairs(FORM_NAMES[key] or {}) do if v == want then return i end end
      end
    end
  end
end

-- "{cat}" -> "form:3" (or a never-true "form:99" if you don't have it)
function ns.ExpandTokens(text)
  return (text:gsub("{(%a+)}", function(k)
    k = k:lower()
    if k == "stealth" then return "stealth" end
    local i = ns.FormIndex(k)
    return "form:" .. (i or 99)
  end))
end

-- the attack part of a click: never while stealthed (rogues: Classic-style
-- clients report stealth as stance 1, so guard that too)
function ns.AttackLine()
  if ns.PlayerClass() == "ROGUE" then
    return "/startattack [nostealth,nostance:1,@target,harm,nodead]"
  end
  return "/startattack [nostealth,@target,harm,nodead]"
end

-- the action lines of a lock + attack click for this class (no /target line)
function ns.EnemyActionLines()
  local cfg = ns.ClassConfig()
  if not cfg then return ns.AttackLine(), nil end
  local action, spell = cfg.enemyAction or "melee", cfg.enemySpell or ""
  if action == "autoshot" then
    local n = ns.SpellName and ns.SpellName(75) or "Auto Shot"
    return "/cast [@target,harm,nodead] !" .. n, { main = n }
  elseif action == "spell" and spell ~= "" then
    return "/cast [@target,harm,nodead] " .. spell, { main = spell }
  elseif action == "druid" and spell ~= "" then
    return ns.ExpandTokens("/cast [noform,@target,harm,nodead][{moonkin},@target,harm,nodead] " .. spell)
      .. "\n/startattack [form,nostealth,@target,harm,nodead]", nil
  end
  return ns.AttackLine(), nil
end
