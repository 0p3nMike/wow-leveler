-- Farm.lua -- /zug farm <what>: a route through the gathering nodes you have
-- recorded on this map (Loot.lua L.node: where you stood when you looted an
-- herb, an ore vein, a chest), nearest first, that starts again when you reach
-- the end. <what> matches the items the nodes gave (part of a name, or an item
-- ID); empty = every node here. The arrow walks it; the optimizer orders the
-- next few as for any route. Nodes respawn on Blizzard's timers, so some will
-- be empty or taken: walk on.
-- Your place is kept: /zug farm off goes back to quest log mode or the guide
-- you were on (Engine.park / resume).

local _, ns = ...
local C, Route = ns.C, ns.Route

local F = {}
ns.Farm = F

F.NAME = "Farm"
local route = { name = F.NAME, dynamic = true, steps = {} }
Route.Register(route)

function F.active() return ns.cdb and ns.cdb.route == F.NAME end

local function gives(p, what)
  if what == "" then return true end
  for id, e in pairs(p.items or {}) do
    if tostring(id) == what or (type(e.name) == "string" and e.name:lower():find(what, 1, true)) then return true end
  end
  return false
end

-- recorded nodes on your map that gave <what>
function F.nodes(what)
  local map = C.mapPos()
  local out = {}
  for _, p in ipairs(map and ns.db.nodes and ns.db.nodes[map] or {}) do
    if gives(p, what) then out[#out + 1] = { map = map, x = p.x, y = p.y } end
  end
  return out, map
end

-- the loop: from where you stand, each time the nearest node not yet in it
function F.build()
  local what = ns.cdb.farm or ""
  local left = F.nodes(what)
  local _, cx, cy = C.mapPos()
  cx, cy = cx or 0.5, cy or 0.5
  local steps = {}
  while #left > 0 do
    local bi, bd
    for i, q in ipairs(left) do
      local d = (q.x - cx) ^ 2 + (q.y - cy) ^ 2
      if not bd or d < bd then bi, bd = i, d end
    end
    local q = table.remove(left, bi)
    steps[#steps + 1] = { act = "goto", map = q.map, x = q.x, y = q.y, r = 15, text = what ~= "" and ("Gather " .. what) or "Gather here" }
    cx, cy = q.x, q.y
  end
  route.steps = steps
  Route.saveLive(F.NAME, steps)
  return #steps
end

local function restart()
  if ns.Optimizer then ns.Optimizer.held = nil end
  local db = ns.cdb
  db.step, db.sticky, db.deferred, db.plan = 1, {}, {}, nil
  ns.Engine.evaluate()
  ns.Fire("SL_STEP", ns.Engine.index(), ns.Engine.step())
end

function F.start(what)
  what = (what or ""):lower()
  local found = F.nodes(what)
  if #found == 0 then
    C.print("no recorded %snodes on this map yet: gather a few (the addon records each one you loot), then /zug farm again", what ~= "" and (what .. " ") or "")
    return false
  end
  if not F.active() then
    ns.cdb.farmFrom = ns.cdb.route
    if ns.cdb.route ~= (ns.QuestLog and ns.QuestLog.NAME) then ns.Engine.park() end
  end
  ns.cdb.farm = what
  F.build()
  ns.Engine.setRoute(F.NAME)
  C.print("farming %s: %d nodes on this map, nearest first, round and round. /zug farm off goes back", what ~= "" and what or "everything", #route.steps)
  return true
end

function F.stop()
  if not F.active() then return C.print("not farming") end
  local from = ns.cdb.farmFrom
  ns.cdb.farm, ns.cdb.farmFrom, ns.cdb.route = nil, nil, nil
  if from == (ns.QuestLog and ns.QuestLog.NAME) then ns.QuestLog.start()
  elseif not ns.Engine.resume() and from then ns.Engine.setRoute(from) end
  C.print("stopped farming")
end

-- what you can farm on this map: { { name, nodes } } by item, most nodes first
function F.list()
  local map = C.mapPos()
  local by = {}
  for _, p in ipairs(map and ns.db.nodes and ns.db.nodes[map] or {}) do
    for id, e in pairs(p.items or {}) do
      local k = e.name or ("item " .. id)
      by[k] = (by[k] or 0) + 1
    end
  end
  local out = {}
  for k, n in pairs(by) do out[#out + 1] = { name = k, nodes = n } end
  table.sort(out, function(a, b) return a.nodes > b.nodes end)
  return out
end

function F.command(args)
  if args == "off" or args == "stop" then return F.stop() end
  if args == "list" then
    local l = F.list()
    if #l == 0 then return C.print("no gathering nodes recorded on this map yet") end
    for k = 1, math.min(#l, 10) do C.print("  %s: %d node%s", l[k].name, l[k].nodes, l[k].nodes > 1 and "s" or "") end
    return C.print("/zug farm <name> walks them")
  end
  F.start(args)
end

-- round and round: past the last node, a new loop from where you are
ns.On("SL_TICK", function()
  if F.active() and #route.steps > 0 and ns.Engine.index() > #route.steps then F.build(); restart() end
end)
ns.On("PLAYER_ENTERING_WORLD", function() if F.active() then F.build(); restart() end end)
ns.On("ZONE_CHANGED_NEW_AREA", function() if F.active() then F.build(); restart() end end)
