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
  local steps, unplaced, skip = {}, {}, skipped()
  for _, q in ipairs(C.questLogIDs()) do
    if not skip[q] then
      local done = C.isComplete(q)
      local wmap, wx, wy = C_QuestLog and C.try(C_QuestLog.GetNextWaypoint, q)
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
  -- quest givers on these maps
  if ns.db.qlAccept ~= false and C_QuestLine and C_QuestLine.GetAvailableQuestLines then
    local seen = {}
    for _, map in ipairs(maps()) do
      C.try(C_QuestLine.RequestQuestLinesForMap, map)
      for _, ln in ipairs(C.try(C_QuestLine.GetAvailableQuestLines, map) or {}) do
        local q = ln.questID
        if q and not seen[q] and not ln.isHidden and not ln.isDaily and not skip[q]
          and not C.isOnQuest(q) and not C.isTurnedIn(q) and ln.x and (ln.x > 0 or ln.y > 0) then
          seen[q] = true
          steps[#steps + 1] = { act = "accept", q = q, title = ln.questName, map = map, x = ln.x, y = ln.y }
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

function QL.start()
  ns.Engine.setRoute(QL.NAME)
  lastSig = nil
  QL.rebuild(true)
end

-- What /lev ql debug prints: where the positions came from.
function QL.debug()
  local placed = QL.collect()
  local acc = 0
  for _, s in ipairs(placed) do if s.act == "accept" then acc = acc + 1 end end
  C.print("quest log mode: %d placed (%d quest givers), %d with no position from the game; maps asked: %s",
    #placed, acc, #QL.unplaced, table.concat(maps(), ","))
  for _, s in ipairs(QL.unplaced) do C.print("  no position: %s", s.title or s.q) end
end

local function onChange()
  if QL.active() and C.now() - lastBuild > 0.5 then QL.rebuild() end
end

ns.On("QUEST_LOG_UPDATE", onChange)
ns.On("QUEST_ACCEPTED", function() if QL.active() then QL.rebuild(true) end end)
ns.On("QUEST_TURNED_IN", function() if QL.active() then QL.rebuild(true) end end)
ns.On("QUEST_REMOVED", function() if QL.active() then QL.rebuild(true) end end)
ns.On("ZONE_CHANGED_NEW_AREA", function() if QL.active() then QL.rebuild(true) end end)
ns.On("PLAYER_ENTERING_WORLD", function() if QL.active() then QL.rebuild(true) end end)
ns.On("SL_TICK", function()
  if QL.active() and C.now() - lastBuild > REBUILD_EVERY then QL.rebuild() end
end)
ns.On("PLAYER_LEVEL_UP", function()
  if QL.active() and next(skipped()) then QL.unswap() end
end)
