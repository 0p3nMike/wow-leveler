-- Waypoint.lua -- where are we headed: the current step, or a /way you typed.
--
-- One target at a time, given to two displays:
--   * the game's own pin and in-world marker (C_Map user waypoint +
--     C_SuperTrack), checked in the 1.60.1 export;
--   * our arrow (Arrow.lua), the TomTom replacement.
-- A manual /way wins over the route until you reach it or /way clear.
-- Fires SL_TARGET(target or nil); target = { cont, wx, wy, map, x, y, text, r, manual, dim }.
--
-- Two modes for a "do" (complete) step, re-decided every tick (Engine.mode):
--   travel  outside the area: the arrow heads for the nearest edge of it
--   work    inside it: the arrow walks the step's hunting loop (RXP #loop +
--           radius gotos, the same chain RXP's own arrow walks) or, with no
--           loop, dims; its title shows the live objective instead. SL_MODE fires on change.
-- Accept/turn-in steps with a chain of gotos walk the chain, then the NPC.
-- The game's pin always stays on the step itself; only our arrow walks.
--
-- TomTom itself is not used: it is not installed, and I could not read its
-- source to check its API. /way takes TomTom's everyday form (x y [text]).

local _, ns = ...
local C, Route = ns.C, ns.Route

local W = {}
ns.Way = W

local pinned       -- the user waypoint we set: { map }
local routeTarget  -- from the current step
local manual       -- from /way

local function pinOn() return ns.db.waypoint ~= false end

local function clearPin()
  if pinned and C_Map and C_Map.ClearUserWaypoint then
    local cur = C.try(C_Map.GetUserWaypoint)
    if cur and cur.uiMapID == pinned.map then C.try(C_Map.ClearUserWaypoint) end
  end
  pinned = nil
end

local function setPin(t)
  if not (pinOn() and t and t.map and t.x) then clearPin(); return end
  if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return end
  if not C.try(C_Map.CanSetUserWaypointOnMap, t.map) then clearPin(); return end
  if not C.try(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(t.map, t.x, t.y)) then return end
  pinned = { map = t.map }
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
    C.try(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
  end
end

-- World position of a target: RXP steps carry it; others are converted.
local function withWorld(t)
  if t and not t.wx and t.map and t.x then
    t.cont, t.wx, t.wy = C.worldPos(t.map, t.x, t.y)
  end
  return t
end

local pinTarget            -- what the game's pin shows (the step, or the /way)
local lastPinKey, lastKey  -- publish only on change: SetUserWaypoint is not free
local cur, walk, wi, mode  -- current step, its radius points, index, travel/work

local function key(t)
  if not t then return "-" end
  return table.concat({ tostring(t.map), tostring(t.wx or t.x), tostring(t.wy or t.y),
    t.dim and "d" or "", t.text or "" }, "|")
end

local function publish(force)
  local t = manual or routeTarget
  -- paused: no pin for the route's step (a /way of your own keeps its pin)
  local pt = manual or (not ns.Pause.on() and pinTarget) or nil
  local pk = key(pt)
  if force or pk ~= lastPinKey then setPin(pt); lastPinKey = pk end
  local k = key(t)
  if force or k ~= lastKey then lastKey = k; ns.Fire("SL_TARGET", t) end
end

function W.current() return manual or routeTarget end
function W.mode() return mode end

local function at(p, text, dim)
  Route.Resolve(p)
  return withWorld({ cont = p.cont, wx = p.wx, wy = p.wy, map = p.map, x = p.x, y = p.y,
    r = p.r, text = text, dim = dim })
end

-- Work out the route's arrow target for the current step and position.
function W.tick(force)
  local E = ns.Engine
  local s = cur
  if not (s and (s.wx or s.x or s.map)) then
    routeTarget, pinTarget = nil, nil
    return publish(force)
  end
  Route.Resolve(s)
  local desc = E.describe(s)
  pinTarget = (s.wx or s.x) and at(s, desc) or nil
  local m = E.mode(s)
  if s.act == "complete" and m == "work" then
    local obj = E.objective(s) or s.hint or desc
    if #walk > 0 and s.loop then
      local d = E.yardsTo(walk[wi])
      if d and d <= walk[wi].r then wi = wi % #walk + 1 end
      routeTarget = at(walk[wi], obj)
    else
      routeTarget = pinTarget and at(s, obj, true) or nil
    end
  elseif s.act == "complete" then
    -- travelling to a hunting area: head for the nearest point of it
    local best, bd = s, E.yardsTo(s)
    for _, p in ipairs(walk) do
      local d = E.yardsTo(p)
      if d and (not bd or d < bd) then best, bd = p, d end
    end
    routeTarget = (best.wx or best.x) and at(best, desc) or nil
  else
    while wi <= #walk do
      local d = E.yardsTo(walk[wi])
      if d and d <= walk[wi].r then wi = wi + 1 else break end
    end
    routeTarget = wi <= #walk and at(walk[wi], desc) or pinTarget
  end
  -- a flight is quicker (Flight.lua): point at the flight master first
  if routeTarget and routeTarget.wx and m ~= "work" and ns.Flight and not C.try(UnitOnTaxi, "player") then
    local pm, px, py = C.mapPos()
    local pc, pwx, pwy = C.worldPos(pm, px, py)
    if pc then
      local _, leg = ns.Flight.travel({ pc, pwx, pwy }, { routeTarget.cont, routeTarget.wx, routeTarget.wy })
      if leg then
        routeTarget = { cont = leg.from.cont, wx = leg.from.wx, wy = leg.from.wy, r = 10,
          text = ("|cff80c0ffFly|r %s -> %s"):format(leg.from.name, leg.to.name) }
      end
    end
  end
  if m ~= mode then
    mode = m
    ns.Fire("SL_MODE", m, s)
  end
  publish(force)
end

-- From a route step (nil clears).
function W.set(s)
  cur, walk, wi, mode = s, {}, 1, nil
  for _, p in ipairs(s and s.path or {}) do
    if p.r then walk[#walk + 1] = p end -- radius-0 points are pins only (RXP: no arrow)
  end
  W.tick(true)
end

ns.On("SL_TICK", function() if cur then W.tick() end end)
ns.On("QUEST_LOG_UPDATE", function() if cur and mode == "work" then W.tick() end end)

-- /way: x, y in 0..1 on `map` (default: the map you are on).
function W.way(map, x, y, text)
  manual = withWorld({ map = map, x = x, y = y, text = text or string.format("%.1f, %.1f", x * 100, y * 100),
    manual = true, r = 8 })
  publish()
  return manual
end

function W.clearManual()
  if not manual then return end
  manual = nil
  publish()
end

function W.clear()
  routeTarget, manual, pinTarget, cur, lastKey, lastPinKey = nil, nil, nil, nil, nil, nil
  clearPin()
  ns.Fire("SL_TARGET", nil)
end

function W.refresh() publish(true) end
ns.On("SL_PAUSE", function() publish(true) end)

ns.On("SL_STEP", function(_, s) W.set(s) end)

-- ------------------------------------------------------------------ /way

-- /way x y [text]   /way <uiMapID> x y [text]   /way clear
local function slashWay(msg)
  msg = (msg or ""):gsub(",", " ")
  if msg:match("^%s*clear%s*$") or msg:match("^%s*reset%s*$") then
    W.clearManual()
    return C.print("/way cleared")
  end
  local words = {}
  for w in msg:gmatch("%S+") do words[#words + 1] = w end
  local n1, n2, n3 = tonumber(words[1]), tonumber(words[2]), tonumber(words[3])
  local map, x, y, first
  if n1 and n2 and n3 then
    map, x, y, first = n1, n2, n3, 4          -- /way <uiMapID> x y [text]
  elseif n1 and n2 then
    map, x, y, first = (C.mapPos()), n1, n2, 3 -- /way x y [text]
  end
  local rest = first and table.concat(words, " ", first) or ""
  if not (map and x and y) or x > 100 or y > 100 then
    return C.print("usage: /way x y [text]  ·  /way <uiMapID> x y [text]  ·  /way clear")
  end
  W.way(map, x / 100, y / 100, rest ~= "" and rest or nil)
  C.print("/way %s %.1f, %.1f%s", C.mapName(map) or map, x, y, rest ~= "" and (" - " .. rest) or "")
end

SLASH_ZUGZUGLEVELERWAY1 = "/way"
SLASH_ZUGZUGLEVELERWAY2 = "/slway"
SlashCmdList.ZUGZUGLEVELERWAY = slashWay
