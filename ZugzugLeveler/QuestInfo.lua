-- QuestInfo.lua -- can this character take quest q, and if not, why.
--
-- From data/Quests.lua (AllTheThings' Forever data, MIT; see tools/att2quests.lua),
-- read the way ATT's own code reads it (src/Classes/Quests.lua missingReqs and
-- altcollected, src/Modules/Filter.lua):
--   faction   r: 1 Horde, 2 Alliance (Enum.FlightPathFaction)
--   race      races: race IDs (UnitRace's third value)
--   class     c: class IDs (UnitClass's third value)
--   locked    any altQuests turned in
--   past      a breadcrumb whose nextQuests (nx) you took or did (ATT's
--             LockedAsBreadcrumb: done, or itself locked; taking one counts
--             too, as ATT warns when you accept it, Quests.lua:1185)
--   prereqs   sourceQuests: sqreq of them (else all) done; one you are on, a
--             breadcrumb, or one that is not for you does not count as missing
--   level     lvl: minimum, or {min, max}
-- A quest the data does not know is never blocked (the game decides).

local _, ns = ...
local C = ns.C

local QI = {}
ns.QInfo = QI

-- data/Quests.lua sets ns.QuestDB (Forever), data/Quests_Mists.lua ns.QuestDBMists,
-- data/Quests_Era.lua ns.QuestDBEra: each game reads its own, even if all were loaded
local function DB()
  local g = C.game()
  if g == "mists" then return ns.QuestDBMists or {} end
  if g == "era" then return ns.QuestDBEra or {} end
  return ns.QuestDB or {}
end
QI.db = DB
function QI.get(q) return q and DB()[q] end

local FACTION = { Horde = 1, Alliance = 2 }
function QI.me()
  local faction = FACTION[C.try(UnitFactionGroup, "player") or ""]
  local _, _, race = C.try(UnitRace, "player")
  local _, _, class = C.try(UnitClass, "player")
  local level = C.try(UnitLevel, "player")
  return faction, race, class, level
end

-- Done quests: one C.completedSet call for a whole pass (as Questie and ATT
-- do) instead of thousands of single lookups.
local doneSet
local function turned(q)
  if doneSet then return doneSet[q] == true end
  return C.isTurnedIn(q)
end
local function withDone(fn)
  doneSet = C.completedSet()
  local ok, out = pcall(fn)
  doneSet = nil
  if not ok then error(out) end
  return out
end

local function has(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

-- Not for this character at all (faction, race, class)?
local function notForMe(e, faction, race, class)
  if e.r and faction and e.r ~= faction then return "faction" end
  if e.races and race and not has(e.races, race) then return "race" end
  if e.c and class and not has(e.c, class) then return "class" end
end

-- nil when q can be taken now (or is in the log / done); else
--   { kind = "never", why = "faction"|"race"|"class"|"alt"|"toohigh", q = alt quest, max = level }
--   { kind = "prereq", need = { quest ids still to do } }
--   { kind = "level", lvl = level needed }
function QI.blocked(q)
  local e = QI.get(q)
  if not e then return nil end
  if turned(q) or C.isOnQuest(q) then return nil end
  local faction, race, class, level = QI.me()
  local nf = notForMe(e, faction, race, class)
  if nf then return { kind = "never", why = nf } end
  for _, a in ipairs(e.alt or {}) do
    if turned(a) then return { kind = "never", why = "alt", q = a } end
  end
  if e.bc then
    for _, n in ipairs(e.nx or {}) do
      local ne = QI.get(n)
      local locked = turned(n) or C.isOnQuest(n)
      for _, a in ipairs(not locked and ne and ne.alt or {}) do if turned(a) then locked = true end end
      if locked then return { kind = "never", why = "past", q = n } end
    end
  end
  local lvl, max = e.lvl, nil
  if type(lvl) == "table" then lvl, max = lvl[1], lvl[2] end
  if max and level and level > max then return { kind = "never", why = "toohigh", max = max } end
  if e.sq and #e.sq > 0 then
    local need, have, missing = e.sqreq or #e.sq, 0, {}
    for _, s in ipairs(e.sq) do
      local se = QI.get(s)
      if turned(s) or C.isOnQuest(s) or (se and (se.bc or notForMe(se, faction, race, class))) then
        have = have + 1
      else
        missing[#missing + 1] = s
      end
    end
    if have < need then return { kind = "prereq", need = missing } end
  end
  if lvl and level and level < lvl then return { kind = "level", lvl = lvl } end
  return nil
end

-- A quest's name: the game's, else the route's, else its number.
function QI.title(q, steps)
  local t = C.questTitle(q)
  if t then return t end
  for _, s in ipairs(steps or {}) do
    if s.q == q and s.title then return s.title end
  end
  return "quest " .. tostring(q)
end

-- The reason as words, for chat and the window.
function QI.say(b, steps)
  if not b then return nil end
  if b.kind == "prereq" then
    local names = {}
    for k, s in ipairs(b.need) do if k <= 3 then names[#names + 1] = QI.title(s, steps) end end
    return ("it needs %s first"):format(table.concat(names, " and "))
  elseif b.kind == "level" then
    local _, _, _, level = QI.me()
    return ("it needs level %d (you are %s)"):format(b.lvl, tostring(level or "?"))
  elseif b.why == "alt" then
    return ("you did %s, which rules this one out"):format(QI.title(b.q, steps))
  elseif b.why == "past" then
    return ("it only leads to %s, which you already have or did"):format(QI.title(b.q, steps))
  elseif b.why == "toohigh" then
    return ("it is only offered up to level %d"):format(b.max)
  end
  return ("it is not offered to your %s"):format(b.why)
end

-- Every quest this character can take now, anywhere (for the companion page's
-- map: the game knows what you have done, the page does not).
function QI.availableAll(cap)
  return withDone(function()
    local out = {}
    for q, e in pairs(DB()) do
      if e.at and not e.rep and not C.isOnQuest(q) and not turned(q) and not QI.blocked(q) then
        out[#out + 1] = q
      end
    end
    table.sort(out)
    while cap and #out > cap do table.remove(out) end
    return out
  end)
end

-- Quests this character can take now that start on map m (from the data's
-- quest-giver points), nearest-first is the caller's business.
function QI.availableOn(m)
  return withDone(function()
    local out = {}
    for q, e in pairs(DB()) do
      if e.at and e.at[1] == m and not e.rep and not C.isOnQuest(q) and not turned(q) and not QI.blocked(q) then
        out[#out + 1] = q
      end
    end
    table.sort(out)
    return out
  end)
end
