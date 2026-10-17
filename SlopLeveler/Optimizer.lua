-- Optimizer.lua -- a shorter order for the next few steps.
--
-- Ordering stops is the travelling-salesman problem with precedence rules
-- (not a shortest-path / Dijkstra problem: that finds the best path between
-- TWO points). It is exact here because the window is small:
--   window   the next unfinished steps from the route pointer, up to MAXN with
--            a position. It stops at anything that must stay where the route
--            put it: a level gate, hearth / set hearth / flight, a step with no
--            position, a set-aside step.
--   rules    the same quest keeps its route order (accept -> do -> turn in);
--            a step whose `need` names a quest comes after that quest's steps
--            in the window; train steps keep their order among themselves.
--   cost     straight-line yards from you through the stops. Only walking:
--            addons get no pathing, so cliffs and rivers are not seen.
--   solver   Held-Karp dynamic programming over subsets (2^n * n^2; n <= 10
--            is ~100k steps of Lua, a few ms), with a step only allowed once
--            everything it must follow is done.
-- It SUGGESTS: when the best order beats the route's by MIN_SAVE yards and
-- MIN_PCT, it says so; /lev optimize applies it (an Engine plan), and
-- /lev optimize auto applies it by itself each time a new window opens.
-- The route's order is not wrong when it is longer: a trainer visit can be
-- worth the walk (a new Fireball rank speeds up every kill after it), and
-- only you can judge that, which is why it asks.

local _, ns = ...
local C, Route = ns.C, ns.Route

local O = {}
ns.Optimizer = O

local MAXN, MIN_SAVE, MIN_PCT = 10, 150, 0.15
local BARRIER = { hearth = true, sethearth = true, fly = true }

local function world(s)
  Route.Resolve(s)
  if s.wx then return s.cont, s.wx, s.wy end
  if s.map and s.x then return C.worldPos(s.map, s.x, s.y) end
end

-- The window: { idx = {route indices}, pos = {{cont,wx,wy}}, after = index }.
function O.window()
  local E = ns.Engine
  local r, db = E.route(), ns.cdb
  if not r then return nil end
  -- from the route pointer, active plan or not: a re-plan sees the same steps
  -- (finished ones are sticky and drop out)
  local sticky, deferred = db.sticky or {}, db.deferred or {}
  local idx, pos = {}, {}
  local j = db.step or 1
  while j <= #r.steps and #idx < MAXN do
    local s = r.steps[j]
    if sticky[j] or (E.applies and not E.applies(s)) then
      -- finished or not for this character: not part of the plan
    elseif deferred[j] then
      break
    elseif E.isDone(j, r.steps) then
      -- already satisfied: the engine passes it on its own
    else
      if s.lvl or BARRIER[s.act] then break end
      local c, x, y = world(s)
      if not c then break end
      idx[#idx + 1], pos[#pos + 1] = j, { c, x, y }
    end
    j = j + 1
  end
  if #idx < 3 then return nil end -- nothing to reorder
  return { idx = idx, pos = pos, after = j }
end

-- must[b] = list of a that have to come before b (positions in the window).
function O.rules(steps, idx)
  local must = {}
  for b = 1, #idx do
    must[b] = {}
    local sb = steps[idx[b]]
    for a = 1, b - 1 do
      local sa = steps[idx[a]]
      local before = (sa.q and sa.q == sb.q)
        or (sa.act == "train" and sb.act == "train")
      if not before and sb.need and sa.q then
        for _, k in ipairs({ "on", "done", "turned", "notdone", "avail" }) do
          for _, q in ipairs(sb.need[k] or {}) do if q == sa.q then before = true end end
        end
      end
      if before then must[b][#must[b] + 1] = a end
    end
  end
  return must
end

local function straight(p, q)
  if p[1] ~= q[1] then return 1e7 end
  local dx, dy = p[2] - q[2], p[3] - q[3]
  return math.sqrt(dx * dx + dy * dy)
end

-- Travel cost between two {cont, wx, wy}: flight-aware when Flight.lua knows
-- your flight points (in walking yards), else straight-line yards.
local function dist(p, q)
  if ns.Flight and ns.Flight.travel then return (ns.Flight.travel(p, q)) end
  return straight(p, q)
end
O.dist = dist

-- Cost of visiting pos in `order` (window positions), starting at `from`.
function O.cost(from, pos, order)
  local total, at = 0, from
  for _, k in ipairs(order) do total = total + dist(at, pos[k]); at = pos[k] end
  return total
end

-- Held-Karp with precedence. Returns the best order (window positions) and cost.
function O.solve(from, pos, must)
  local n = #pos
  local pow = {}
  for k = 1, n do pow[k] = 2 ^ (k - 1) end
  local function has(mask, k) return math.floor(mask / pow[k]) % 2 == 1 end
  local need = {}
  for k = 1, n do
    local m = 0
    for _, a in ipairs(must[k]) do m = m + pow[a] end
    need[k] = m
  end
  local function allowed(mask, k)
    local m = need[k]
    if m == 0 then return true end
    for _, a in ipairs(must[k]) do if not has(mask, a) then return false end end
    return true
  end
  local full = 2 ^ n - 1
  -- tie-break: among equally short orders keep the route's own order (a later
  -- step taken early costs a hair more). A thousandth of a yard: it never
  -- outweighs real distance, and the cost returned is the true one.
  local EPS = 1e-3
  local count = { [0] = 0 }
  for mask = 1, full do count[mask] = count[math.floor(mask / 2)] + mask % 2 end
  -- travel costs once per solve (the loops below would otherwise call it ~100k times)
  local D0, D = {}, {}
  for a = 1, n do
    D0[a] = dist(from, pos[a])
    D[a] = {}
    for b = 1, n do D[a][b] = a == b and 0 or dist(pos[a], pos[b]) end
  end
  local dp, par = {}, {}
  for k = 1, n do
    if need[k] == 0 then
      dp[pow[k] * n + k] = D0[k] + EPS * k * n
    end
  end
  for mask = 1, full do
    for last = 1, n do
      local here = dp[mask * n + last]
      if here and has(mask, last) then
        for k = 1, n do
          if not has(mask, k) and allowed(mask, k) then
            local nm = mask + pow[k]
            local c = here + D[last][k] + EPS * k * (n - count[mask])
            local key = nm * n + k
            if not dp[key] or c < dp[key] then dp[key], par[key] = c, last end
          end
        end
      end
    end
  end
  local best, bl
  for last = 1, n do
    local c = dp[full * n + last]
    if c and (not best or c < best) then best, bl = c, last end
  end
  if not best then return nil end
  local order, mask, last = {}, full, bl
  while last do
    table.insert(order, 1, last)
    local p = par[mask * n + last]
    mask = mask - pow[last]
    last = p
  end
  return order, O.cost(from, pos, order)
end

-- Work out the best order for the current window from where you stand.
-- Returns { idx = route indices in best order, save = yards, routeCost, bestCost, after }.
function O.plan()
  local w = O.window()
  if not w then return nil end
  local m, x, y = C.mapPos()
  local pc, px, py = C.worldPos(m, x, y)
  if not pc then return nil end
  local from = { pc, px, py }
  local r = ns.Engine.route()
  local must = O.rules(r.steps, w.idx)
  local order, best = O.solve(from, w.pos, must)
  if not order then return nil end
  local natural = {}
  for k = 1, #w.idx do natural[k] = k end
  local routeCost = O.cost(from, w.pos, natural)
  local idx = {}
  for k, o in ipairs(order) do idx[k] = w.idx[o] end
  return { idx = idx, save = routeCost - best, routeCost = routeCost, bestCost = best,
    after = w.after, window = w, from = from }
end

function O.worthIt(p)
  return p and p.save >= MIN_SAVE and p.save >= p.routeCost * MIN_PCT
end

-- Make it the order the engine follows. SL_STEP (the arrow moving) only when
-- the step to do next actually changes, so a hunting loop is not restarted.
function O.apply(p)
  if not p then return false end
  local before = ns.Engine.index()
  ns.cdb.plan = { list = p.idx, after = p.after, save = math.floor(p.save + 0.5) }
  ns.Engine.evaluate()
  if ns.Engine.index() ~= before then ns.Fire("SL_STEP", ns.Engine.index(), ns.Engine.step()) end
  return true
end

-- ------------------------------------------------------------ auto mode
-- "auto" (the default): re-solve from where you are every EVERY seconds and
-- whenever the step changes; switch the arrow when another order is clearly
-- shorter than the one being followed (HYST_YD and HYST_PCT, so two equal
-- choices do not flip back and forth). Never while you are in the area of the
-- current "do" step: finish what you are standing in first.

local HYST_YD, HYST_PCT, EVERY = 40, 0.08, 2

function O.mode() return ns.db.optimize or "auto" end

-- Cost, from where you are, of the order being followed now: the plan's
-- remaining steps, then any window steps it does not have, in route order.
function O.currentCost(p)
  local w = p.window
  local at = {}
  for k, j in ipairs(w.idx) do at[j] = k end
  local order, seen = {}, {}
  for _, j in ipairs(ns.cdb.plan and ns.cdb.plan.list or {}) do
    if at[j] and not seen[j] then order[#order + 1] = at[j]; seen[j] = true end
  end
  for k, j in ipairs(w.idx) do
    if not seen[j] then order[#order + 1] = k end
  end
  return O.cost(p.from, w.pos, order)
end

local lastSay = 0
local busy
function O.replan()
  if busy or O.mode() ~= "auto" then return end
  if ns.Way.mode and ns.Way.mode() == "work" then return end
  local p = O.plan()
  if not p then return end
  local gain = O.currentCost(p) - p.bestCost
  if gain < HYST_YD or gain < O.currentCost(p) * HYST_PCT then return end
  local E = ns.Engine
  local before = E.index()
  busy = true
  O.apply(p)
  busy = false
  if E.index() ~= before and C.now() - lastSay > 15 then
    lastSay = C.now()
    C.print("shorter from here (~%d yd): %s", gain, E.describe(E.step()))
  end
  if ns.UI then ns.UI.refresh() end
end

-- "suggest": say it once per window, apply on /lev optimize.
local lastKey
function O.suggest()
  if ns.cdb.plan or O.mode() ~= "suggest" then return end
  local p = O.plan()
  if not O.worthIt(p) then return end
  local key = table.concat(p.idx, ",")
  if key == lastKey then return end
  lastKey = key
  O.pending = p
  C.print("a shorter order saves ~%d yd: next would be %s  ·  /lev optimize", p.save,
    ns.Engine.describe(ns.Engine.route().steps[p.idx[1]]))
  if ns.UI then ns.UI.refresh() end
end

function O.check()
  if O.mode() == "auto" then O.replan() else O.suggest() end
end

ns.On("SL_STEP", function()
  if O.mode() == "off" then return end
  O.pending = nil
  -- after the engine settles on the new step
  if C_Timer and C_Timer.After then C_Timer.After(0, O.check) else O.check() end
end)

local ticks = 0
ns.On("SL_TICK", function()
  ticks = ticks + 1
  if ticks % (EVERY * 2) == 0 and O.mode() == "auto" and ns.Engine.route() then O.replan() end
end)
