-- Engine.lua -- which step are we on, and is it done.
--
-- Per character (SlopLevelerCharDB): route = name, step = index,
-- sticky = { [index] = true } for steps already finished, stats = { [index] =
-- { secs, xp } } for how long each step took and what it paid.
--
-- A step is done when the game says so, never because time passed:
--   accept    on the quest (or it is already turned in)
--   complete  objectives complete (or turned in)
--   turnin    flagged completed -- and QUEST_TURNED_IN marks it at once,
--             since the flag can lag the event
--   others    within r yards of (map, x, y); or the step's level is reached;
--             or the next quest step is already done (you got there anyway)
-- Once done, a step stays done (sticky): walking away does not undo it.

local _, ns = ...
local C, Route = ns.C, ns.Route

local E = {}
ns.Engine = E

local DEFAULT_R = 15

local function cdb() return ns.cdb end

function E.route() return Route.Get(cdb().route) end
-- The step on screen: the head of an optimizer plan when one is active
-- (Optimizer.lua), else the route pointer.
function E.index()
  local p = cdb().plan
  if p and p.list[1] then return p.list[1] end
  return cdb().step or 1
end

-- Upcoming step indices in the order they will be shown: the plan first,
-- then the route from after it. Set-aside and finished steps are left out.
function E.upcoming(n)
  local r, db = E.route(), cdb()
  local out = {}
  if not r then return out end
  local deferred, sticky = db.deferred or {}, db.sticky or {}
  local from = db.step or 1
  if db.plan then
    for _, j in ipairs(db.plan.list) do out[#out + 1] = j end
    from = db.plan.after
  end
  for j = from, #r.steps do
    if #out >= n then break end
    if not deferred[j] and not sticky[j] then out[#out + 1] = j end
  end
  while #out > n do table.remove(out) end
  return out
end

function E.step(i)
  local r = E.route()
  return r and Route.Resolve(r.steps[i or E.index()])
end

local function near(s)
  Route.Resolve(s)
  if not (s.map and s.x) then return false end
  local m, x, y = C.mapPos()
  if not x then return false end
  local d = C.yards(m, x, y, s.map, s.x, s.y)
  if not d and m == s.map then
    -- No world position (some maps): fall back to raw map units.
    d = math.sqrt((x - s.x) ^ 2 + (y - s.y) ^ 2) * 1000
  end
  return d ~= nil and d <= (s.r or DEFAULT_R)
end

-- RXP's .xp rule, ported from its functions.lua (addon.functions.xp, the
-- completion test): level L plus xp, where xp >= 1 is that much XP into L,
-- 0 < xp < 1 is that fraction of L's bar, xp < 0 is that much short of L.
function E.levelReached(L, xp)
  local cur, max, level = C.xp()
  level = level or C.try(UnitLevel, "player") or 0
  xp = xp or 0
  if not cur then return level >= L end
  if xp < 0 then return level >= L or (level == L - 1 and cur >= max + xp) end
  if xp >= 1 then return level > L or (level == L and cur >= xp) end
  return level > L or (level == L and cur >= max * xp)
end

local function questDone(s)
  if s.act == "accept" then return C.isOnQuest(s.q) or C.isTurnedIn(s.q) end
  if s.act == "complete" then
    if C.isComplete(s.q) or C.isTurnedIn(s.q) then return true end
    return s.obj ~= nil and C.objectiveDone(s.q, s.obj)
  end
  if s.act == "turnin" then return C.isTurnedIn(s.q) end
end

local function all(list, test)
  for _, q in ipairs(list or {}) do if not test(q) then return false end end
  return true
end

-- A step's `need` conditions (imported from RXP's .isOnQuest and friends)
-- say when it applies at all; a step that does not apply is passed over.
function E.applies(s)
  local n = s.need
  if not n then return true end
  if not all(n.on, C.isOnQuest) then return false end
  if not all(n.done, C.isComplete) then return false end
  if not all(n.notdone, function(q) return not C.isComplete(q) end) then return false end
  if not all(n.turned, C.isTurnedIn) then return false end
  if not all(n.avail, function(q) return not C.isOnQuest(q) and not C.isTurnedIn(q) end) then return false end
  if n.below and (C.try(UnitLevel, "player") or 0) >= n.below then return false end
  return true
end

function E.isDone(i, steps)
  local db = cdb()
  if db.sticky and db.sticky[i] then return true end
  local s = steps[i]
  if not E.applies(s) then return true end
  if Route.QUEST_STEP[s.act] then
    -- optional: a quest you never picked up does not block the route
    if s.opt and s.act ~= "accept" and not C.isOnQuest(s.q) and not C.isTurnedIn(s.q) then return true end
    return questDone(s) and true or false
  end
  if s.lvl then return E.levelReached(s.lvl, s.xp) end
  if near(s) then return true end
  for j = i + 1, #steps do
    if Route.QUEST_STEP[steps[j].act] and E.applies(steps[j]) then return questDone(steps[j]) and true or false end
  end
  return false
end

local function stamp(i)
  local s = ns.XP.session()
  cdb().stepStart = { i = i, t = C.epoch(), xp = s and s.total or 0 }
end

-- wasCurrent: the step was on screen when it finished (not fast-forwarded
-- past, not skipped). SL_FINISH(i, wasCurrent) feeds the speedrun splits.
local function finish(i, wasCurrent)
  local db, st = cdb(), cdb().stepStart
  db.sticky = db.sticky or {}
  db.sticky[i] = true
  if st and st.i == i then
    local s = ns.XP.session()
    db.stats = db.stats or {}
    db.stats[i] = { secs = C.epoch() - st.t, xp = (s and s.total or 0) - st.xp }
  end
  ns.Fire("SL_FINISH", i, wasCurrent and true or false)
end

-- Move forward past every finished step. Fires SL_STEP when the index moves.
-- Steps set aside with /swap are passed over without being finished.
function E.evaluate()
  local r = E.route()
  if not r then return end
  local db = cdb()
  -- an optimizer plan: finish from its head; when it runs out, the route
  -- pointer jumps past the window (every step in it was in the plan)
  local p = db.plan
  if p then
    local head = p.list[1]
    while p.list[1] and E.isDone(p.list[1], r.steps) do
      local j = table.remove(p.list, 1)
      finish(j, j == head)
    end
    if p.list[1] then
      if p.list[1] ~= head then
        stamp(p.list[1])
        ns.Fire("SL_STEP", p.list[1], E.step(p.list[1]))
      end
      return
    end
    db.plan = nil
    if p.after > (db.step or 1) then db.step = p.after end
    stamp(db.step)
    ns.Fire("SL_STEP", db.step, E.step(db.step))
  end
  local deferred = db.deferred or {}
  local i, start = E.index(), E.index()
  while i <= #r.steps do
    if deferred[i] then
      i = i + 1
    elseif E.isDone(i, r.steps) then
      finish(i, i == start)
      i = i + 1
    else
      break
    end
  end
  if i ~= start then
    db.step = i
    stamp(i)
    ns.Fire("SL_STEP", i, E.step(i))
  end
end

function E.setRoute(name)
  local db = cdb()
  db.route, db.step, db.sticky, db.stats, db.deferred, db.plan = name, 1, {}, {}, {}, nil
  stamp(1)
  ns.Fire("SL_ROUTE", name)
  E.evaluate()
  ns.Fire("SL_STEP", E.index(), E.step())
end

function E.jump(i)
  local r = E.route()
  if not r then return end
  local db = cdb()
  db.plan = nil
  i = math.max(1, math.min(i, #r.steps + 1))
  db.sticky = db.sticky or {}
  for j = i, #r.steps do db.sticky[j] = nil end
  for j = 1, i - 1 do db.sticky[j] = true end
  db.step = i
  stamp(i)
  ns.Fire("SL_STEP", i, E.step(i))
end

function E.skip()
  local i = E.index()
  local p = cdb().plan
  if p and p.list[1] == i then -- skipping inside a plan: drop just that step
    finish(i, false)
    table.remove(p.list, 1)
    stamp(E.index())
    E.evaluate()
    ns.Fire("SL_STEP", E.index(), E.step())
    return
  end
  finish(i, false)
  E.jump(i + 1)
end

-- ----------------------------------------------------------- /swap
-- "Not now": set the current step aside, with every later unfinished step of
-- the same quest (its do/turn-in would be blocked too), and move on. Set-aside
-- steps come back on level-up (usually what was missing), when you accept that
-- quest anyway, or with /swap back.

function E.deferred()
  local out = {}
  for i in pairs(cdb().deferred or {}) do out[#out + 1] = i end
  table.sort(out)
  return out
end

function E.swap()
  local r, i = E.route(), E.index()
  local s = r and r.steps[i]
  if not s then return nil end
  local db = cdb()
  db.plan = nil
  db.deferred = db.deferred or {}
  db.deferred[i] = true
  local n = 1
  if s.q then
    for j = i + 1, #r.steps do
      if r.steps[j].q == s.q and not (db.sticky or {})[j] then db.deferred[j] = true; n = n + 1 end
    end
  end
  local before = E.index()
  E.evaluate()
  if E.index() == before then -- evaluate only moves when something changed; force the move
    local j = i + 1
    while j <= #r.steps and db.deferred[j] do j = j + 1 end
    db.step = j
    stamp(j)
    ns.Fire("SL_STEP", j, E.step(j))
    E.evaluate()
  end
  return s, n
end

-- Bring set-aside steps back (all, or only those for quest q). The route
-- returns to the earliest one; finished steps in between pass straight away.
function E.unswap(q)
  local r, db = E.route(), cdb()
  if not (r and db.deferred and next(db.deferred)) then return 0 end
  local first, n = nil, 0
  db.plan = nil
  for i in pairs(db.deferred) do
    if not q or r.steps[i].q == q then
      db.deferred[i] = nil
      n = n + 1
      first = (not first or i < first) and i or first
    end
  end
  if first and first < E.index() then
    db.step = first
    stamp(first)
    E.evaluate()
    ns.Fire("SL_STEP", E.index(), E.step())
  end
  return n
end

ns.On("PLAYER_LEVEL_UP", function()
  local n = E.unswap()
  if n > 0 then C.print("level up: %d set-aside step%s back in the route", n, n == 1 and "" or "s") end
end)

-- Mark the first unfinished step matching (act, q) at or after the current one.
local function markQuest(act, q)
  local r = E.route()
  if not r then return end
  for i = (cdb().step or 1), #r.steps do
    local s = r.steps[i]
    if s.act == act and s.q == q and not (cdb().sticky or {})[i] then
      cdb().sticky = cdb().sticky or {}
      cdb().sticky[i] = true
      return
    end
  end
end

-- ------------------------------------------------------ the "do" area

local AREA = 50 -- yards: inside this of the step or any of its path points = working

-- Yards from the player to a point carrying step-style position fields.
function E.yardsTo(p)
  Route.Resolve(p)
  local m, x, y = C.mapPos()
  if not x then return nil end
  if p.wx then
    local pc, px, py = C.worldPos(m, x, y)
    if not pc or pc ~= p.cont then return nil end
    return math.sqrt((p.wx - px) ^ 2 + (p.wy - py) ^ 2)
  end
  if p.map and p.x then return C.yards(m, x, y, p.map, p.x, p.y) end
end

-- "work" when the player is in the area of a complete step, else "travel".
function E.mode(s)
  if not (s and s.act == "complete") then return "travel" end
  local best = E.yardsTo(s)
  for _, p in ipairs(s.path or {}) do
    local d = E.yardsTo(p)
    if d and (not best or d < best) then best = d end
    if d and p.r and d <= p.r + 15 then return "work" end
  end
  return (best and best <= AREA) and "work" or "travel"
end

-- The objective this step is about (or the first unfinished one): text, finished.
function E.objective(s)
  local list = C.objectives(s and s.q)
  local o = s and s.obj and list[s.obj]
  if not o then
    for _, it in ipairs(list) do if not it.finished then o = it; break end end
  end
  if o then return o.text, o.finished end
end

-- -------------------------------------------------------------- text

local COLOR = {
  accept = "ffffd100", complete = "ffff8040", turnin = "ff40ff40",
  ["goto"] = "ff80c0ff", fly = "ff80c0ff", hearth = "ff80c0ff",
  sethearth = "ffc080ff", train = "ffc080ff", note = "ffcccccc",
}
local VERB = {
  accept = "Accept", complete = "Do", turnin = "Turn in", ["goto"] = "Go to",
  fly = "Fly", hearth = "Hearth", sethearth = "Set hearth", train = "Train", note = "",
}

function E.describe(s)
  if not s then return "Route finished." end
  Route.Resolve(s)
  local what
  if Route.QUEST_STEP[s.act] then
    what = C.questTitle(s.q) or s.title or ("quest " .. tostring(s.q))
    if s.text then what = what .. " - " .. s.text end
  else
    what = s.text or (s.map and C.mapName(s.map)) or ""
    if s.act == "note" and s.lvl then
      local cur, max, level = C.xp()
      local goal = s.xp and s.xp >= 1 and (" +" .. s.xp .. " xp") or ""
      what = s.text or ("Grind to level " .. s.lvl .. goal)
      if cur then what = what .. string.format(" |cff999999(you: %d, %d/%d)|r", level, cur, max) end
    end
  end
  local where = s.x and string.format(" |cff999999(%.1f, %.1f)|r", s.x * 100, s.y * 100) or ""
  local verb = VERB[s.act] or s.act
  return string.format("|c%s%s|r %s%s", COLOR[s.act] or "ffffffff", verb, what, where)
end

-- -------------------------------------------------------------- events

ns.On("SL_READY", function()
  if cdb().route and not E.route() then
    C.print("route %q is no longer installed; /lev route list", cdb().route)
  end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
  if E.route() then
    E.evaluate()
    ns.Fire("SL_STEP", E.index(), E.step())
  end
end)

ns.On("QUEST_ACCEPTED", function(q) E.unswap(q); markQuest("accept", q); E.evaluate() end)
ns.On("QUEST_TURNED_IN", function(q) markQuest("turnin", q); E.evaluate() end)
ns.On("QUEST_LOG_UPDATE", E.evaluate)
ns.On("PLAYER_LEVEL_UP", E.evaluate)
ns.On("ZONE_CHANGED_NEW_AREA", E.evaluate)
ns.On("SL_TICK", E.evaluate)

ns.On("HEARTHSTONE_BOUND", function()
  local s = E.step()
  if s and s.act == "sethearth" then finish(E.index()); E.evaluate() end
end)
ns.On("TRAINER_CLOSED", function()
  local s = E.step()
  if s and s.act == "train" then finish(E.index()); E.evaluate() end
end)
