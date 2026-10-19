-- QuestLog.lua -- "Quest log" mode: no guide, just your quests.
--
-- A route that builds itself from the game: every quest in your log becomes a
-- "do" step at its objective area, or a "turn in" step once it is complete,
-- and nearby quest givers ("!") become "accept" steps. The optimizer (auto by
-- default) then orders the nearest of them from where you stand, so the
-- arrow always points at the shortest way through what you have.
-- Covers any level and any zone, including Forever's new quests that no guide
-- has yet. Where the positions come from (1.60.1 export):
--   C_QuestLog.GetQuestsOnMap(uiMapID)  -> QuestPOIMapInfo {questID, x, y, ...}
--     the same quest areas the world map draws, asked on your map and the
--     maps above it (zone, continent)
--   C_QuestLog.GetNextWaypoint(questID) -> mapID, x, y
--     when a quest wants you somewhere else first (another zone)
--   C_QuestLine.RequestQuestLinesForMap / GetAvailableQuestLines(uiMapID)
--     quest givers the map shows; isHidden (trivial, too low) are left out
-- Mists of Pandaria Classic has neither GetNextWaypoint nor C_QuestLine: there
-- quest givers come from the quest data (data/Quests_Mists.lua, AllTheThings),
-- the ones QuestInfo says you can take now. That data rarely knows a quest's
-- level, so grey ones are left out by a rule of thumb (QL.outlevelled).
-- A quest the game gives no position for is listed in the window, not routed.
-- /swap here sets that QUEST aside until you level up (/swap back).

local _, ns = ...
local C, Route = ns.C, ns.Route

local QL = {}
ns.QuestLog = QL

QL.NAME = "Quest log"
local route = { name = QL.NAME, dynamic = true, steps = {} }
Route.Register(route)

QL.unplaced = {}   -- quests in the log the game gives no position for
local lastSig, lastBuild = nil, -100
local REBUILD_EVERY = 10

function QL.active() return ns.cdb and ns.cdb.route == QL.NAME end

-- Your map and the ones above it (zone, continent): where to ask for quests.
local function maps()
  local out, id, guard = {}, C.mapPos(), 0
  while id and id > 0 and guard < 4 do
    out[#out + 1] = id
    local info = C_Map and C.try(C_Map.GetMapInfo, id)
    id = info and info.parentMapID
    guard = guard + 1
  end
  return out
end

local function skipped() ns.cdb.qlSkip = ns.cdb.qlSkip or {}; return ns.cdb.qlSkip end

-- A quest from the data that is grey for you, by a rule of thumb (the data
-- has no quest levels, only a minimum level now and then): its minimum level
-- 10+ under yours, or its zone's top level (C_Map.GetMapLevels, what the
-- map's area labels show, AreaLabelDataProvider.lua:76) 3+ under yours.
function QL.outlevelled(q)
  local e, level = ns.QInfo.get(q), C.try(UnitLevel, "player")
  if not (e and level) then return false end
  local lvl = type(e.lvl) == "table" and e.lvl[1] or e.lvl
  if lvl and lvl + 10 <= level then return true end
  local top
  if C_Map then _, top = C.try(C_Map.GetMapLevels, e.zone or (e.at and e.at[1])) end
  return (top and top > 0 and top + 3 <= level) and true or false
end

-- Dungeon quests need a group. The quest data marks them (inst: AllTheThings
-- lists them only under its Instances category, tools/att2quests.lua). On your
-- own, quest log mode does not send you to pick one up or into the dungeon for
-- its objectives (a finished one still gets turned in); in a party or raid it does.
local function grouped() return (C.try(IsInGroup) or C.try(IsInRaid)) and true or false end
local function isDungeon(q)
  local e = ns.QInfo and ns.QInfo.get(q)
  return (e and e.inst) and true or false
end
QL.dungeon = {} -- dungeon quests in your log that are left out while you are on your own

-- The steps, nearest first. Returns placed steps; fills QL.unplaced.
function QL.collect()
  local where = {}
  for _, map in ipairs(maps()) do
    for _, poi in ipairs((C_QuestLog and C.try(C_QuestLog.GetQuestsOnMap, map)) or {}) do
      if poi.questID and not where[poi.questID] and poi.x and (poi.x > 0 or poi.y > 0) then
        where[poi.questID] = { map = map, x = poi.x, y = poi.y }
      end
    end
  end
  local steps, unplaced, skip, dungeon = {}, {}, skipped(), {}
  local solo = not grouped()
  for _, q in ipairs(C.questLogIDs()) do
    local done = C.isComplete(q)
    if skip[q] then
      -- set aside (/swap)
    elseif solo and not done and isDungeon(q) then
      dungeon[#dungeon + 1] = q -- its objectives are inside a dungeon: not on your own
    else
      -- (not "C_QuestLog and C.try(...)": an and/or keeps only the first result)
      local wmap, wx, wy
      if C_QuestLog then wmap, wx, wy = C.try(C_QuestLog.GetNextWaypoint, q) end
      local pos = (wmap and wx and { map = wmap, x = wx, y = wy }) or where[q]
      local s = { act = done and "turnin" or "complete", q = q, title = C.questTitle(q) }
      if not done then
        for _, o in ipairs(C.objectives(q)) do
          if not o.finished and o.text and o.text ~= "" then s.hint = o.text; break end
        end
      end
      if pos then
        s.map, s.x, s.y = pos.map, pos.x, pos.y
        steps[#steps + 1] = s
      else
        unplaced[#unplaced + 1] = s
      end
    end
  end
  QL.dungeon = dungeon
  -- quest givers on these maps
  if ns.db.qlAccept ~= false and C_QuestLine and C_QuestLine.GetAvailableQuestLines then
    local seen = {}
    for _, map in ipairs(maps()) do
      C.try(C_QuestLine.RequestQuestLinesForMap, map)
      for _, ln in ipairs(C.try(C_QuestLine.GetAvailableQuestLines, map) or {}) do
        local q = ln.questID
        if q and not seen[q] and not ln.isHidden and not ln.isDaily and not skip[q] and not (solo and isDungeon(q))
          and not C.isOnQuest(q) and not C.isTurnedIn(q) and ln.x and (ln.x > 0 or ln.y > 0) then
          seen[q] = true
          steps[#steps + 1] = { act = "accept", q = q, title = ln.questName, map = map, x = ln.x, y = ln.y }
        end
      end
    end
  elseif ns.db.qlAccept ~= false and ns.QInfo then
    -- no C_QuestLine: the quest data's giver points on these maps, for quests
    -- this character can take now and has not outlevelled
    local seen = {}
    for _, map in ipairs(maps()) do
      for _, q in ipairs(ns.QInfo.availableOn(map)) do
        local at = ns.QInfo.get(q).at
        if not seen[q] and not skip[q] and not QL.outlevelled(q) and not (solo and isDungeon(q)) then
          seen[q] = true
          steps[#steps + 1] = { act = "accept", q = q, title = ns.QInfo.title(q), map = at[1], x = at[2], y = at[3] }
        end
      end
    end
  end
  -- nearest first: the optimizer's window is the next few, so it plans the closest
  local m, px, py = C.mapPos()
  local pc, pwx, pwy = C.worldPos(m, px, py)
  for _, s in ipairs(steps) do
    local c, wx, wy = C.worldPos(s.map, s.x, s.y)
    s.cont, s.wx, s.wy = c, wx, wy
    s._d = (pc and c == pc and wx) and math.sqrt((wx - pwx) ^ 2 + (wy - pwy) ^ 2) or 1e9
  end
  table.sort(steps, function(a, b) return a._d < b._d end)
  for _, s in ipairs(steps) do s._d = nil end
  QL.unplaced = unplaced
  return steps
end

local function signature(steps)
  local t = {}
  for _, s in ipairs(steps) do
    t[#t + 1] = ("%s%d@%d:%.3f,%.3f"):format(s.act, s.q, s.map or 0, s.x or 0, s.y or 0)
  end
  table.sort(t) -- order (by distance) changing alone is not a new set
  return table.concat(t, ";")
end

-- Rebuild the route when the SET of steps changed. force: rebuild regardless.
function QL.rebuild(force)
  if not QL.active() then return false end
  lastBuild = C.now()
  local steps = QL.collect()
  local sig = signature(steps)
  if not force and sig == lastSig then return false end
  lastSig = sig
  route.steps = steps
  Route.saveLive(QL.NAME, steps)
  if ns.Optimizer then ns.Optimizer.held = nil end -- step numbers start over: a held stretch no longer exists
  local db = ns.cdb
  db.step, db.sticky, db.deferred, db.plan = 1, {}, {}, nil
  ns.Engine.evaluate()
  ns.Fire("SL_STEP", ns.Engine.index(), ns.Engine.step())
  return true
end

-- /swap in this mode: set the quest aside until level-up.
function QL.swap(s)
  if not (s and s.q) then return nil end
  skipped()[s.q] = true
  QL.rebuild(true)
  return s, 1
end

function QL.unswap(q)
  local skip, n = skipped(), 0
  for k in pairs(skip) do
    if not q or k == q then skip[k] = nil; n = n + 1 end
  end
  if n > 0 then QL.rebuild(true) end
  return n
end

-- Your place in the guide you leave is kept: /zug route resume goes back.
function QL.start()
  ns.Engine.park()
  ns.Engine.setRoute(QL.NAME)
  lastSig = nil
  QL.rebuild(true)
end

-- What /zug ql debug prints: where the positions came from.
function QL.debug()
  local placed = QL.collect()
  local acc = 0
  for _, s in ipairs(placed) do if s.act == "accept" then acc = acc + 1 end end
  C.print("quest log mode: %d placed (%d quest givers), %d with no position from the game; maps asked: %s",
    #placed, acc, #QL.unplaced, table.concat(maps(), ","))
  for _, s in ipairs(QL.unplaced) do C.print("  no position: %s", s.title or s.q) end
  for _, q in ipairs(QL.dungeon) do C.print("  dungeon, left out while you are on your own: %s", ns.QInfo.title(q)) end
end

local function onChange()
  if QL.active() and C.now() - lastBuild > 0.5 then QL.rebuild() end
end

ns.On("QUEST_LOG_UPDATE", onChange)
ns.On("QUEST_ACCEPTED", function() if QL.active() then QL.rebuild(true) end end)
ns.On("QUEST_TURNED_IN", function() if QL.active() then QL.rebuild(true) end end)
ns.On("QUEST_REMOVED", function() if QL.active() then QL.rebuild(true) end end)
ns.On("ZONE_CHANGED_NEW_AREA", function() if QL.active() then QL.rebuild(true) end end)
ns.On("GROUP_ROSTER_UPDATE", function() if QL.active() then QL.rebuild() end end) -- dungeon quests come and go with a group
ns.On("PLAYER_ENTERING_WORLD", function() if QL.active() then QL.rebuild(true) end end)
ns.On("SL_TICK", function()
  if QL.active() and C.now() - lastBuild > REBUILD_EVERY then QL.rebuild() end
end)
ns.On("PLAYER_LEVEL_UP", function()
  if QL.active() and next(skipped()) then QL.unswap() end
end)
