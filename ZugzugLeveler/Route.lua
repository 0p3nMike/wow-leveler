-- Route.lua -- our route format, the registry, and run -> route conversion.
--
-- A route is { name = "...", steps = { step, ... } } and a step is
--   { act = "accept"|"complete"|"turnin"|"goto"|"fly"|"hearth"|"sethearth"|"train"|"note",
--     q = questID, title = "fallback text", map = uiMapID, x = 0..1, y = 0..1,
--     r = arrive radius in yards (default 15), text = "note", lvl = level gate,
--     obj = objective index (complete: done when that one objective is),
--     opt = true (complete/turnin: skipped if you never took the quest),
--     need = { on = {q..}, done = {q..}, notdone = {q..}, turned = {q..},
--              avail = {q..}, below = level } -- the step only applies when all hold,
--     cont = continentID, wx = , wy = world position: RXP's Forever guides give
--            this instead of x/y; Route.Resolve turns it into x/y in game }
-- Quest steps (accept/complete/turnin) are judged from the quest log; the rest
-- by arriving at (map, x, y), by an event, or by the next quest step finishing.
--
-- Routes come from two places: files in routes/ (ns.Route.Register), and
-- recorded runs converted in game (/zug route fromrun N), saved in
-- ZugzugLevelerDB.routes so every character can use them.

local _, ns = ...
local C = ns.C

local Route = {}
ns.Route = Route

local fileRoutes, order = {}, {}

Route.QUEST_STEP = { accept = true, complete = true, turnin = true }

-- Fill in map/x/y from a world position the first time a step is looked at.
-- Left alone when the game cannot convert it.
function Route.Resolve(s)
  if s and s.wx and not s.x then
    local map, x, y = C.fromWorld(s.cont, s.wx, s.wy, s.map)
    if map then s.map, s.x, s.y = map, x, y end
  end
  return s
end

-- Kinds of step a player may leave out (the companion page's "What your
-- route includes"; its choice is routes/custom/Prefs.lua: ns.RoutePrefs.skip).
-- Matched on a train / goto / note step's text and hint, lowercase, by
-- these words, taken from what RestedXP's Forever guides say ("Train
-- Cooking", "Create Linen Bandages until...", "Train Staves"). The companion
-- reads this same table, so the page counts what the addon skips.
Route.CATEGORIES = {
  cooking = { label = "Cooking (training it, and the cooking it has you do)", words = { "cooking", "apprentice cook", "herb baked egg", " cook " } },
  firstaid = { label = "First aid (training, and making bandages)", words = { "first aid", "bandage" } },
  professions = { label = "Gathering and crafting trainers (mining, skinning, herbalism, smithing, enchanting...)", words = { "train mining", "train skinning", "train herbalism", "train blacksmithing", "train enchanting", "train tailoring", "train alchemy", "train engineering", "train leatherworking" } },
  weapons = { label = "Weapon skill training (staves, swords, bows...)", words = { "train staves", "train 1h", "train 2h", "train two-handed", "train one-handed", "train bows", "train guns", "train crossbows", "train thrown", "train daggers", "train fist", "train polearms", "train wands" } },
  food = { label = "Buying food and water (a mage conjures them)", words = { "buy food", "buy water", "buy drink", "restock food", "restock water" } },
  classtrain = { label = "Class trainer visits (new spell ranks)", words = { "train your class spells" } },
  pettrain = { label = "Pet trainer visits", words = { "train your pet spells" } },
  optional = { label = "Optional quests RestedXP marks as skippable", opt = true },
}

-- The category a step falls in, or nil.
function Route.category(s)
  if not s then return nil end
  if s.opt and not s.act:find("accept") then return "optional" end
  if s.act ~= "train" and s.act ~= "goto" and s.act ~= "note" then return nil end
  local t = " " .. ((s.text or "") .. " " .. (s.hint or "")):lower() .. " "
  for key, c in pairs(Route.CATEGORIES) do
    for _, w in ipairs(c.words or {}) do
      if t:find(w, 1, true) then return key end
    end
  end
end

-- Left out by the player's choice (the page's Prefs.lua)?
-- The player's goal: "speed" (fastest leveling) or "complete" (reputation,
-- professions, every quest). Kept in ZugzugLevelerDB.goal; the page's
-- Prefs.lua (goal + at) wins when it was chosen later than the game's.
Route.GOALS = { speed = true, complete = true }
function Route.goal()
  local p, db = ns.RoutePrefs, ns.db
  if not db then return nil end
  if p and Route.GOALS[p.goal] and (p.at or 0) > (db.goalAt or 0) then db.goal, db.goalAt = p.goal, p.at end
  return db.goal
end
-- What each goal leaves out when the player has not picked step kinds on the page.
Route.GOAL_SKIP = { speed = { cooking = true, firstaid = true, professions = true }, complete = {} }

-- The step kinds left out: picked on the page (routes/custom/Prefs.lua) or in
-- the game's options panel (ZugzugLevelerDB.skip, skipAt), whichever was picked
-- later; with neither, the goal's.
function Route.skips()
  local prefs, db = ns.RoutePrefs, ns.db
  local page = prefs and prefs.skip
  local pageSet = (page and next(page)) or (prefs and prefs.custom)
  if db and db.skip and (db.skipAt or 0) >= ((pageSet and prefs.at) or 0) then return db.skip end
  if pageSet then return page or {} end
  return Route.GOAL_SKIP[Route.goal() or ""]
end

function Route.setSkip(kind, left)
  local db = ns.db
  local cur = Route.skips() or {}
  local t = {}
  for k, v in pairs(cur) do t[k] = v end
  t[kind] = left and true or nil
  db.skip, db.skipAt = t, C.epoch()
end

function Route.leftOut(s)
  local p = Route.skips()
  if not p then return false end
  local k = Route.category(s)
  return k ~= nil and p[k] == true
end

-- A route file for another race or class need not load (its steps would only
-- take memory): true when the character is known and is not that race/class.
-- UnitRace's second value ("Scourge") and UnitClass's second ("MAGE"), read
-- while the addon's files load; unknown then -> load everything.
function Route.Skip(race, class)
  local _, r = C.try(UnitRace, "player")
  local _, c = C.try(UnitClass, "player")
  if type(r) ~= "string" or type(c) ~= "string" then return false end
  return r ~= race or c ~= class
end

function Route.Register(def)
  assert(type(def) == "table" and def.name and def.steps, "route needs name and steps")
  -- A route for the other faction is not kept: ten generated routes are ~850 KB of Lua.
  local mine = C.try(UnitFactionGroup, "player")
  if def.faction and mine and def.faction ~= mine then return end
  if not fileRoutes[def.name] then order[#order + 1] = def.name end
  fileRoutes[def.name] = def
end

function Route.Get(name)
  if not name then return nil end
  local saved = ns.db and ns.db.routes and ns.db.routes[name]
  return saved or fileRoutes[name]
end

function Route.List()
  local out = {}
  for _, n in ipairs(order) do out[#out + 1] = { name = n, steps = #fileRoutes[n].steps, from = "file" } end
  for n, r in pairs(ns.db and ns.db.routes or {}) do
    out[#out + 1] = { name = n, steps = #r.steps, from = "saved" }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function Route.Save(def)
  ns.db.routes = ns.db.routes or {}
  ns.db.routes[def.name] = def
end

function Route.Delete(name)
  if ns.db.routes then ns.db.routes[name] = nil end
end

-- ----------------------------------------------------------- run -> route

local function at(ev) return ev.map, ev.x, ev.y end

local function firstCrumbAfter(run, t)
  for _, s in ipairs(run.path or {}) do
    local ct, m, x, y = s:match("^(%d+)|(%d+)|(%d+)|(%d+)$")
    if ct and tonumber(ct) >= t then return tonumber(m), tonumber(x) / 10000, tonumber(y) / 10000 end
  end
end

function Route.FromRun(run, name)
  local steps, titles, abandoned = {}, {}, {}
  for _, ev in ipairs(run.ev) do
    if ev.e == "abandon" and ev.q then abandoned[ev.q] = true end
    if ev.e == "accept" and ev.q and ev.title then titles[ev.q] = ev.title end
  end
  local pendingFly
  for _, ev in ipairs(run.ev) do
    local e, map, x, y = ev.e, at(ev)
    local function add(s)
      s.map, s.x, s.y = s.map or map, s.x or x, s.y or y
      steps[#steps + 1] = s
    end
    if e == "accept" and not abandoned[ev.q] then
      add({ act = "accept", q = ev.q, title = titles[ev.q] })
    elseif e == "done" and not abandoned[ev.q] then
      add({ act = "complete", q = ev.q, title = titles[ev.q] or ev.title })
    elseif e == "turnin" then
      add({ act = "turnin", q = ev.q, title = titles[ev.q] })
    elseif e == "fly" then
      add({ act = "goto", text = "Flight master" })
      pendingFly = true
    elseif e == "land" and pendingFly then
      pendingFly = nil
      add({ act = "fly", text = C.mapName(map) and ("Fly to " .. C.mapName(map)) or "Fly", r = 60 })
    elseif e == "hearth" then
      local m2, x2, y2 = firstCrumbAfter(run, ev.t + 10)
      steps[#steps + 1] = { act = "hearth", text = ev.note and ("Hearth to " .. ev.note) or "Hearth",
        map = m2, x = x2, y = y2, r = 60 }
    elseif e == "sethearth" then
      add({ act = "sethearth", text = ev.note and ("Set hearth: " .. ev.note) or "Set hearth" })
    elseif e == "mark" then
      add({ act = "note", text = ev.note })
    end
  end
  return { name = name, steps = steps, fromRun = run.started, char = run.char, preset = run.preset }
end

-- --------------------------------------------------------------- export

local KEYS = { "act", "q", "obj", "title", "text", "hint", "npc", "mobs", "use", "map", "x", "y", "cont", "wx", "wy", "r", "lvl", "xp", "opt", "need", "loop", "path" }

local function lit(v)
  if type(v) == "table" then
    local parts = {}
    for _, x in ipairs(v) do parts[#parts + 1] = lit(x) end
    local keys = {}
    for k in pairs(v) do if type(k) == "string" then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. " = " .. lit(v[k]) end
    return "{ " .. table.concat(parts, ", ") .. " }"
  end
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "number" then
    if v == math.floor(v) then return tostring(v) end
    return string.format("%.4f", v)
  end
  return tostring(v)
end

-- Lua source for a routes/*.lua file.
function Route.ToLua(def)
  local out = { "local _, ns = ...", "", "ns.Route.Register({", "  name = " .. lit(def.name) .. ",", "  steps = {" }
  for _, s in ipairs(def.steps) do
    local parts = {}
    for _, k in ipairs(KEYS) do
      if s[k] ~= nil then
        local key = k
        parts[#parts + 1] = key .. " = " .. lit(s[k])
      end
    end
    out[#out + 1] = "    { " .. table.concat(parts, ", ") .. " },"
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "})"
  return table.concat(out, "\n") .. "\n"
end
