-- Engine.lua -- which step are we on, and is it done.
--
-- Per character (ZugzugLevelerCharDB): route = name, step = index,
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
-- Play styles: RestedXP has steps only for hardcore or softcore characters, and
-- only for self-found or auction-house ones; rxp2route keeps them, marked
-- (mode = "hc", "sc", "ssf", "ah", or two joined by a comma). The game says which
-- this character is (C_GameRules.IsHardcoreActive, C_PlayerInfo.IsSelfFoundActive,
-- 1.60.1 export); ZugzugLevelerCharDB.hardcore / .ssf (true/false) override it.
function E.hardcore()
  local v = cdb().hardcore
  if v ~= nil then return v end
  return (C_GameRules and C.try(C_GameRules.IsHardcoreActive)) and true or false
end
function E.ssf()
  local v = cdb().ssf
  if v ~= nil then return v end
  return (C_PlayerInfo and C.try(C_PlayerInfo.IsSelfFoundActive)) and true or false
end
local MODE_OK = {
  hc = function() return E.hardcore() end, sc = function() return not E.hardcore() end,
  ssf = function() return E.ssf() end, ah = function() return not E.ssf() end,
}
function E.modeOk(s)
  if not s.mode then return true end
  for m in s.mode:gmatch("[^,]+") do
    local f = MODE_OK[m]
    if f and not f() then return false end
  end
  return true
end

function E.applies(s)
  if not E.modeOk(s) then return false end -- a hardcore / self-found step, and this character is not
  if Route.leftOut(s) then return false end -- the player left this kind of step out (the page's route options)
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
  -- hearth / flight: done once you are on the map the route continues on (you
  -- got there), else it walls off everything after it from the optimizer
  if s.act == "hearth" or s.act == "fly" then
    local m = C.mapPos()
    for j = i + 1, #steps do
      local n = steps[j]
      if E.applies(n) then
        Route.Resolve(n)
        if n.map then
          if m and m == n.map then return true end
          break
        end
      end
    end
  end
  for j = i + 1, #steps do
    if Route.QUEST_STEP[steps[j].act] and E.applies(steps[j]) then return questDone(steps[j]) and true or false end
  end
  return false
end

-- A do / turn-in step for a quest you do not have, whose accept step the route
-- has already passed (skipped, or the quest was abandoned): it cannot be done
-- where the route stands. Returns the passed accept step's index. A quest with
-- no accept step in the route (picked up elsewhere) is never "missing".
-- Quest q, needed at step i, is one you do not have and the route will not
-- give you: not in the log, not turned in, and every accept step for it
-- before i already passed. Returns that accept step's index.
local function gone(q, i, steps)
  if C.isOnQuest(q) or C.isTurnedIn(q) then return nil end
  local db = cdb()
  local from, sticky, deferred = db.step or 1, db.sticky or {}, db.deferred or {}
  local passed
  for j = i - 1, 1, -1 do
    local a = steps[j]
    if a.act == "accept" and a.q == q then
      if j >= from and not sticky[j] and not deferred[j] and E.applies(a) then return nil end -- still to come
      passed = passed or j
    end
  end
  return passed
end

-- A step that cannot be done where the route stands. Returns the reason
-- ("accept" or "after") and the step index it hangs on.
--   do / turn-in  its quest is gone (accept skipped, or the quest abandoned).
--                 A quest with no accept step in the route (picked up
--                 elsewhere) is never gone.
--   accept        a follow-up (s.after: the turn-ins listed before it in the
--                 same RXP step) whose every lead-in quest is gone, so the NPC
--                 will not offer it.
--   accept        the quest data (QuestInfo.lua, from AllTheThings) says you
--                 cannot take it: "blocked" (a missing quest the route will not
--                 do first, or not for your faction / race / class) or "level"
--                 (too low: back on level-up). The second value is the reason.
--                 Quests the data does not know fall back to s.after.
local function upcoming(q, steps)
  local db = cdb()
  local from, sticky, deferred = db.step or 1, db.sticky or {}, db.deferred or {}
  for j = from, #steps do
    if steps[j].q == q and not sticky[j] and not deferred[j] then return true end
  end
end

function E.missing(i, steps)
  local s = steps[i]
  if not s.q then return nil end
  local QI = ns.QInfo
  if s.act == "complete" or s.act == "turnin" then
    local a = gone(s.q, i, steps)
    if a then return "accept", a end
  elseif s.act == "accept" and QI and QI.get(s.q) and not (C.isOnQuest(s.q) or C.isTurnedIn(s.q)) then
    local b = QI.blocked(s.q)
    if not b then return nil end
    if b.kind == "prereq" then
      for _, p in ipairs(b.need) do if upcoming(p, steps) then return nil end end -- the route does it first
    end
    return b.kind == "level" and "level" or "blocked", b
  elseif s.act == "accept" and s.after and not (C.isOnQuest(s.q) or C.isTurnedIn(s.q)) then
    local a
    for _, q in ipairs(s.after) do
      a = gone(q, i, steps)
      if not a then return nil end
    end
    return "after", a
  end
end

-- Set a missing step aside, saying why, so it does not block the route.
-- Marked "missing" (not true, as /swap marks): level-ups leave it alone and
-- accepting the quest brings it back.
local function setAsideMissing(i, steps)
  local why, a = E.missing(i, steps)
  if not why then return false end
  local db = cdb()
  db.deferred = db.deferred or {}
  db.deferred[i] = why == "level" and "level" or "missing"
  local s = steps[i]
  if why == "blocked" or why == "level" then
    C.print("%s: passed, because %s.%s", E.describe(s), ns.QInfo.say(a, steps),
      why == "level" and " It comes back when you level up." or (a.kind == "prereq" and " Do that and it comes back." or ""))
    return true
  end
  local from = steps[a]
  if why == "after" then
    C.print("%s: passed. It comes after %s, which you do not have (its accept, step %d, was skipped).",
      E.describe(s), C.questTitle(from.q) or from.title or ("quest " .. from.q), a)
  else
    C.print("%s: not in your quest log, so passed. Its accept (step %d%s) was skipped; pick the quest up and it comes back.",
      E.describe(s), a, from.npc and (", from " .. from.npc) or "")
  end
  return true
end

-- A step left behind: you are on another map, and the hearth / flight the
-- route takes after it is already done (you went on without it). Returns the
-- hearth / flight step's index.
function E.leftBehind(i, steps)
  local s = steps[i]
  if s.act == "hearth" or s.act == "fly" then return nil end
  if (cdb().kept or {})[i] then return nil end -- you brought it back: it stays
  Route.Resolve(s)
  local m = C.mapPos()
  if not (s.map and m) or m == s.map then return nil end
  for h = i + 1, #steps do
    local b = steps[h]
    if b.act == "hearth" or b.act == "fly" then
      if E.isDone(h, steps) then return h end
      return nil
    end
  end
end

-- Set left-behind steps aside ("left": a level-up leaves them alone, /swap
-- back or accepting the quest brings them back); one chat line per batch.
local leftNames = {}
local function setAsideLeft(i, steps)
  if not E.leftBehind(i, steps) then return false end
  local db = cdb()
  db.deferred = db.deferred or {}
  db.deferred[i] = "left"
  local s = steps[i]
  leftNames[#leftNames + 1] = s.q and (C.questTitle(s.q) or s.title) or s.text or ("step " .. i)
  leftNames.map = leftNames.map or (s.map and C.mapName(s.map))
  return true
end
local function sayLeft()
  if #leftNames == 0 then return end
  local seen, names = {}, {}
  for _, n in ipairs(leftNames) do if not seen[n] then seen[n] = true; names[#names + 1] = n end end
  C.print("you moved on from %s, so %d step%s there %s set aside: %s. /swap back brings them back.",
    leftNames.map or "that zone", #leftNames, #leftNames == 1 and "" or "s", #leftNames == 1 and "is" or "are",
    table.concat(names, ", "))
  leftNames = {}
end

-- a pause does not count against the step it happened on
ns.On("SL_PAUSE", function(paused, secs)
  local st = ns.cdb and ns.cdb.stepStart
  if not paused and st and secs and secs > 0 then st.t = math.min(st.t + secs, C.epoch()) end
end)

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
    while p.list[1] do
      local j = p.list[1]
      if E.isDone(j, r.steps) then
        table.remove(p.list, 1)
        finish(j, j == head)
      elseif setAsideMissing(j, r.steps) or setAsideLeft(j, r.steps) then
        table.remove(p.list, 1)
      else
        break
      end
    end
    sayLeft()
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
    elseif setAsideMissing(i, r.steps) or setAsideLeft(i, r.steps) then
      i = i + 1
    else
      break
    end
  end
  sayLeft()
  if i ~= start then
    db.step = i
    stamp(i)
    ns.Fire("SL_STEP", i, E.step(i))
  end
end

function E.setRoute(name)
  local db = cdb()
  db.route, db.step, db.sticky, db.stats, db.deferred, db.plan, db.kept = name, 1, {}, {}, {}, nil, nil
  local r = E.route()
  db.routeSteps = r and #r.steps
  stamp(1)
  ns.Fire("SL_ROUTE", name)
  E.evaluate()
  ns.Fire("SL_STEP", E.index(), E.step())
end

-- Leave a guide for a while (quest log mode) without losing your place in
-- it; E.resume() takes you back where you were.
function E.park()
  local db = cdb()
  if not db.route or (ns.QuestLog and db.route == ns.QuestLog.NAME) then return false end
  db.parked = { route = db.route, step = db.step, sticky = db.sticky, stats = db.stats, deferred = db.deferred,
    kept = db.kept, routeSteps = db.routeSteps }
  return true
end

local rebase -- (db, r): set below, with SL_READY
function E.resume()
  local db, p = cdb(), cdb().parked
  if not (p and Route.Get(p.route)) then return false end
  db.route, db.step, db.sticky, db.stats, db.deferred, db.kept, db.routeSteps, db.plan =
    p.route, p.step or 1, p.sticky or {}, p.stats or {}, p.deferred or {}, p.kept, p.routeSteps, nil
  db.parked = nil
  rebase(db, E.route())
  stamp(db.step)
  ns.Fire("SL_ROUTE", db.route)
  E.evaluate()
  ns.Fire("SL_STEP", E.index(), E.step())
  return true
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
  if r.dynamic and ns.QuestLog then return ns.QuestLog.swap(s) end -- quest log mode: by quest
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
-- keepMissing: leave steps set aside for a missing quest (a level-up does not
-- put a quest in your log).
function E.unswap(q, keepMissing)
  local r, db = E.route(), cdb()
  if r and r.dynamic and ns.QuestLog then return ns.QuestLog.unswap(q) end
  if not (r and db.deferred and next(db.deferred)) then return 0 end
  local first, n = nil, 0
  local function about(s)
    if s.q == q then return true end
    for _, k in ipairs(s.after or {}) do if k == q then return true end end -- its follow-up
  end
  for i, why in pairs(db.deferred) do
    if (not q or about(r.steps[i])) and not (keepMissing and (why == "missing" or why == "left")) then
      db.deferred[i] = nil
      if why == "left" then db.kept = db.kept or {}; db.kept[i] = true end
      n = n + 1
      first = (not first or i < first) and i or first
    end
  end
  if n > 0 then db.plan = nil end
  if first and first < E.index() then
    db.step = first
    stamp(first)
    E.evaluate()
    ns.Fire("SL_STEP", E.index(), E.step())
  end
  return n
end

ns.On("PLAYER_LEVEL_UP", function()
  local n = E.unswap(nil, true)
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
  if not s then return "Route finished. |cff999999/zug questlog|r keeps going on your own quests." end
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

-- A regenerated route file renumbers its steps, so finished and set-aside
-- marks, step timings and an optimizer plan point at the wrong steps: keep
-- only "everything before your place is done" (as /zug step does).
-- What a step is, to find it again in a regenerated route (db.stepKey).
function E.stepKey(s)
  if not s then return nil end
  return table.concat({ s.act or "", tostring(s.q or ""), s.text or s.title or "", tostring(s.obj or "") }, "|")
end

rebase = function(db, r)
  if not r or r.dynamic or db.routeSteps == #r.steps then return end
  -- the route file changed (new data): find the step you were on by what it is,
  -- nearest to where it was; otherwise keep the number
  if db.stepKey and db.step then
    for d = 0, 60 do
      local hit
      for _, j in ipairs({ db.step + d, db.step - d }) do
        if not hit and r.steps[j] and E.stepKey(r.steps[j]) == db.stepKey then hit = j end
      end
      if hit then db.step = hit; break end
    end
  end
  if db.routeSteps then
    C.print("route %q changed (%d -> %d steps): you are at step %d; /zug step <n> moves you", db.route, db.routeSteps, #r.steps, db.step or 1)
  end
  local i = math.min(db.step or 1, #r.steps + 1)
  db.sticky, db.stats, db.deferred, db.plan, db.kept, db.routeSteps = {}, {}, {}, nil, nil, #r.steps
  for j = 1, i - 1 do db.sticky[j] = true end
end

E.rebase = rebase -- for tests
ns.On("SL_STEP", function(_, s) if s then cdb().stepKey = E.stepKey(s) end end)

ns.On("SL_READY", function()
  local db, r = cdb(), E.route()
  if db.route and not r then
    C.print("route %q is no longer installed; /zug route list", db.route)
  end
  rebase(db, r)
end)

ns.On("PLAYER_ENTERING_WORLD", function()
  if E.route() then
    E.evaluate()
    ns.Fire("SL_STEP", E.index(), E.step())
  end
end)

ns.On("QUEST_ACCEPTED", function(q) E.unswap(q); markQuest("accept", q); E.evaluate() end)
-- Turning in q may open quests that were set aside for needing it.
local function opened(q)
  local r, db = E.route(), cdb()
  if not (r and db.deferred and ns.QInfo) then return end
  local back = {}
  for i, why in pairs(db.deferred) do
    local s = r.steps[i]
    local e = s and s.act == "accept" and why == "missing" and ns.QInfo.get(s.q)
    if e and e.sq then
      for _, p in ipairs(e.sq) do if p == q then back[#back + 1] = s.q end end
    end
  end
  for _, bq in ipairs(back) do E.unswap(bq) end
end
ns.On("QUEST_TURNED_IN", function(q) markQuest("turnin", q); opened(q); E.evaluate() end)
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
