-- Flight.lua -- let the optimizer and the arrow use the flight paths you know.
--
-- Known flight points are learned the way Blizzard's own flight map reads
-- them (Blizzard_FlightMap, 1.60.1 export): at a flight master,
-- GetTaxiMapID() then C_TaxiMap.GetAllTaxiNodes(mapID); state Current (0) or
-- Reachable (1) = known, Unreachable (2) = not. Positions are on that map and
-- are turned into world positions. Stored per character: ZugzugLevelerCharDB.flights.
--
-- Travel cost, in "walking yards" so the optimizer's numbers stay comparable:
--   walk   straight-line yards
--   fly    walk to the known flight point nearest the start, fly to the one
--          nearest the destination, walk from there; the flight counts as
--          (distance / flight speed + OVERHEAD seconds) * run speed
--   cost   the cheaper of the two
-- Not a Dijkstra over the flight network: Forever's taxis route themselves
-- through intermediate points, so one hop between two known points is the
-- whole trip; the measured flight speed below absorbs the detour.
-- Speeds are MEASURED, not assumed, once there is data:
--   run    your actual moving speed (median-ish of recent samples)
--   fly    straight-line distance / time of each real flight you take
-- Until the first flight, fly speed is ASSUMED (DEFAULT_FLY) and /zug flight
-- says so.

local _, ns = ...
local C = ns.C

local F = {}
ns.Flight = F

local DEFAULT_RUN, DEFAULT_FLY, OVERHEAD = 7, 20, 15

local function cdb() return ns.cdb end
local function speeds()
  cdb().speed = cdb().speed or {}
  return cdb().speed
end

function F.run() return speeds().run or DEFAULT_RUN end
function F.fly() return speeds().fly or DEFAULT_FLY end
function F.measured() return speeds().fly ~= nil end

-- ------------------------------------------------------------- learning nodes

function F.learn()
  if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return 0 end
  local map = C.try(GetTaxiMapID)
  if not map then return 0 end
  cdb().flights = cdb().flights or {}
  local n = 0
  for _, node in ipairs(C.try(C_TaxiMap.GetAllTaxiNodes, map) or {}) do
    if node.nodeID and node.position and (node.state == 0 or node.state == 1) then
      local x, y = node.position:GetXY()
      local cont, wx, wy = C.worldPos(map, x, y)
      if cont then
        cdb().flights[node.nodeID] = { name = node.name, cont = cont, wx = wx, wy = wy }
        n = n + 1
      end
    end
  end
  return n
end

ns.On("TAXIMAP_OPENED", F.learn)

function F.known()
  local out = {}
  for id, n in pairs(cdb().flights or {}) do out[#out + 1] = n end
  return out
end

-- ------------------------------------------------------------ measuring speed

local lastPos, flightStart

local function playerWorld()
  local m, x, y = C.mapPos()
  if not x then return nil end
  local c, wx, wy = C.worldPos(m, x, y)
  if c then return { c, wx, wy, C.now() } end
end

ns.On("SL_TICK", function()
  local p = playerWorld()
  local onTaxi = C.try(UnitOnTaxi, "player")
  if onTaxi then
    -- take-off: where you stood just before (a stale sample is no start point)
    if not flightStart and lastPos and C.now() - lastPos[4] < 2 then flightStart = lastPos end
  elseif flightStart and p then
    -- landed: effective speed = straight line / time
    local d = math.sqrt((p[2] - flightStart[2]) ^ 2 + (p[3] - flightStart[3]) ^ 2)
    local t = p[4] - flightStart[4]
    if p[1] == flightStart[1] and t > 10 and d > 200 then
      local v = d / t
      speeds().fly = speeds().fly and (speeds().fly * 0.7 + v * 0.3) or v
    end
    flightStart = nil
  elseif p and lastPos and p[1] == lastPos[1] then
    local dt = p[4] - lastPos[4]
    if dt > 0.2 and dt < 2 then
      local v = math.sqrt((p[2] - lastPos[2]) ^ 2 + (p[3] - lastPos[3]) ^ 2) / dt
      if v > 3 and v < 40 then -- moving on foot or mounted; not standing, not a teleport
        speeds().run = speeds().run and (speeds().run * 0.95 + v * 0.05) or v
      end
    end
  end
  if not onTaxi then lastPos = p end
end)

-- ------------------------------------------------------------------- costs

local function yd(a, b)
  if a[1] ~= b[1] then return nil end
  return math.sqrt((a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

local function nearest(p, nodes)
  local best, bd
  for _, n in ipairs(nodes) do
    local d = yd(p, { n.cont, n.wx, n.wy })
    if d and (not bd or d < bd) then best, bd = n, d end
  end
  return best, bd
end

-- Cost from a to b (each {cont, wx, wy}) in walking yards, and the flight
-- leg if flying is cheaper: { from = node, to = node }.
function F.travel(a, b)
  local walk = yd(a, b)
  local nodes = F.known()
  if #nodes < 2 then return walk or 1e7 end
  local na, da = nearest(a, nodes)
  local nb, db = nearest(b, nodes)
  if not (na and nb) or na == nb or na.cont ~= nb.cont then return walk or 1e7 end
  local hop = yd({ na.cont, na.wx, na.wy }, { nb.cont, nb.wx, nb.wy })
  local flyYards = da + db + (hop / F.fly() + OVERHEAD) * F.run()
  if not walk or flyYards < walk then return flyYards, { from = na, to = nb } end
  return walk
end

function F.report()
  local nodes = F.known()
  C.print("known flight points: %d · run %.1f yd/s · flight %.1f yd/s%s", #nodes, F.run(), F.fly(),
    F.measured() and "" or " (assumed until your first flight)")
  table.sort(nodes, function(a, b) return a.name < b.name end)
  for _, n in ipairs(nodes) do C.print("  %s", n.name) end
end
