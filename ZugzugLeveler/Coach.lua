-- Coach.lua -- what the route wants, why, and a question when there is a real
-- choice. For the player who is lost: a step list says WHAT, this says WHY.
--
--   /zug why   the step in plain words: what to do and who to see, which of
--              RestedXP's guides it belongs to, why it is in another zone and
--              what is there, whether you are on level, and which of your own
--              quests the route will not take you to (and what to do then).
--   heads-up   when the route's next step is in another zone, one chat line
--              saying where and why, once per zone.
--   asks       a yes/no popup only when there is a real choice:
--                stuck  the same quest step for 12 minutes, no progress on it,
--                       while you are at it -> set it aside and go on?
--                away   4 minutes in a zone where the route has nothing ->
--                       follow your own quests here? (your place is kept)
--                back   in quest log mode, in the zone of the guide you left ->
--                       back to the guide, where you left it?
--              Never in combat. "No" (or Escape) waits 15 minutes before
--              asking that again.
-- The state and the "why" lines go to ZugzugLevelerCharDB.coach, so the
-- companion page shows the same explanation (it reads them on /reload).

local _, ns = ...
local C, Route = ns.C, ns.Route

local Coach = {}
ns.Coach = Coach

local STUCK_SECS, AWAY_SECS, SNOOZE = 12 * 60, 4 * 60, 15 * 60
local AT_STEP_YD = 200 -- "at it": this close to the step (or its hunting path)
local LOOKAHEAD = 40   -- "the route has nothing here": none of the next 40 steps

Coach.STUCK_SECS, Coach.AWAY_SECS = STUCK_SECS, AWAY_SECS

local function Eng() return ns.Engine end
local function on() return not ns.db or ns.db.coach ~= false end

local function mapOf(s)
  if not s then return nil end
  Route.Resolve(s)
  return s.map
end
local function zone(m) return m and C.mapName(m) or "somewhere else" end
local function plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function list(t, n)
  n = n or 3
  local shown = {}
  for k = 1, math.min(n, #t) do shown[k] = t[k] end
  return table.concat(shown, ", ") .. (#t > n and (" and %d more"):format(#t - n) or "")
end

-- The RestedXP guide (route section) step i is in, and the one before it.
-- Route files from tools/rxp2route.py carry sections = { {from, name} }.
function Coach.section(r, i)
  local secs = r and r.sections
  if not secs then return nil end
  local k
  for n, s in ipairs(secs) do
    if s.from <= i then k = n else break end
  end
  if not k then return nil end
  return secs[k], secs[k - 1], secs[k + 1]
end

-- a sentence's full stop, unless it has one
local function stop(t) return t:find("[%.!?]$") and t or (t .. ".") end

-- "12-17 The Barrens AoE" -> 12, 17
local function levels(sec)
  if not sec then return nil end
  local a, b = sec.name:match("^(%d+)%-(%d+)")
  return tonumber(a), tonumber(b)
end

-- From step i on, while the route stays on map m: how many steps, and up to
-- three quest titles.
local function whatThere(r, i, m)
  local n, titles, seen = 0, {}, {}
  for j = i, math.min(#r.steps, i + 80) do
    local s = r.steps[j]
    local sm = mapOf(s)
    if sm and sm ~= m then break end
    n = n + 1
    local t = s.q and (C.questTitle(s.q) or s.title)
    if t and not seen[t] then seen[t] = true; titles[#titles + 1] = t end
  end
  return n, titles
end

-- Titles of the quests in your log that no step from i on covers.
function Coach.offRoute(r, i)
  local covered, deferred = {}, ns.cdb.deferred or {}
  for j = i, #r.steps do
    local s = r.steps[j]
    if s.q and not deferred[j] then covered[s.q] = true end
  end
  local out = {}
  for _, q in ipairs(C.questLogIDs()) do
    if not covered[q] then out[#out + 1] = C.questTitle(q) or ("quest " .. q) end
  end
  return out
end

-- The last step before i that has a map.
local function prevMapped(r, i)
  for j = i - 1, 1, -1 do
    if mapOf(r.steps[j]) then return j end
  end
end

-- Why the route is in another zone at step i: one sentence, or nil.
function Coach.moveReason(r, i)
  local s = r.steps[i]
  local m = mapOf(s)
  if not m then return nil end
  local sec, _, nxt = Coach.section(r, i)
  local j = prevMapped(r, i)
  local from = j and mapOf(r.steps[j])
  local n, titles = whatThere(r, i, m)
  local what = #titles > 0 and (": " .. list(titles)) or ""
  local why
  if j and from ~= m then
    local before = Coach.section(r, j)
    if sec and before and before ~= sec then
      return ("RestedXP's %q is done there, and its next part, %q, starts in %s%s."):format(before.name, sec.name, zone(m), what)
    end
    why = ("the guide moves on to %s for %d step%s%s."):format(zone(m), n, n == 1 and "" or "s", what)
  else
    why = ("the route is in %s for %d more step%s%s."):format(zone(m), n, n == 1 and "" or "s", what)
  end
  -- the trip that ends a guide: say where it is heading
  if sec and nxt and nxt.from - i <= 20 then
    local ns_ = r.steps[nxt.from]
    why = why .. (" It is the end of RestedXP's %q: its next part, %q, starts at step %d in %s."):format(
      sec.name, nxt.name, nxt.from, zone(mapOf(ns_)))
  elseif sec and i - sec.from < 8 then
    local _, before = Coach.section(r, i)
    if before then why = why .. (" A new part of the guide begins here: %q (after %q)."):format(sec.name, before.name) end
  end
  return why
end

-- The explanation, as chat lines.
function Coach.why()
  local E = Eng()
  local r, i = E.route(), E.index()
  if not r then return { "No route. /zug route list shows the guides; /zug questlog follows your own quests." } end
  local s = r.steps[i]
  local out = {}
  if r.dynamic then
    out[#out + 1] = "Quest log mode: the arrow takes your own quests, nearest first."
    local p = ns.cdb.parked
    if p then out[#out + 1] = ("Your place in %s is kept at step %d: /zug route resume goes back."):format(p.route, p.step or 1) end
    if s then out[#out + 1] = "Now: " .. E.describe(s) end
    return out
  end
  if not s then return { "You have finished this route. /zug questlog keeps going on your own quests." } end

  out[#out + 1] = ("Step %d of %d: %s"):format(i, #r.steps, E.describe(s))
  -- the step itself
  if s.lvl then
    local _, _, level = C.xp()
    out[#out + 1] = ("A level stop: the guide has you reach level %d%s before going on, so what comes next is not too hard and still gives good XP. You are level %s."):format(
      s.lvl, s.xp and s.xp >= 1 and (" plus " .. s.xp .. " XP") or "", tostring(level or "?"))
  elseif s.act == "accept" then
    local b = s.q and ns.QInfo and ns.QInfo.blocked(s.q)
    if b then
      out[#out + 1] = ("You cannot take it yet: %s."):format(ns.QInfo.say(b, r.steps))
    elseif s.q and ns.Assist and ns.Assist.notOffered[s.q] then
      out[#out + 1] = ("%s did not offer it: you are missing a level or the quest before it. /swap sets it aside."):format(s.npc or "The quest giver")
    elseif s.npc then
      out[#out + 1] = ("Pick it up from %s."):format(s.npc)
    end
  elseif s.act == "complete" and s.q then
    local objs = {}
    for _, o in ipairs(C.objectives(s.q)) do if o.text and o.text ~= "" and not o.finished then objs[#objs + 1] = o.text end end
    if #objs > 0 then out[#out + 1] = "Still to do: " .. list(objs, 4) .. "." end
    if s.hint then out[#out + 1] = stop(s.hint) end
    if s.mobs then out[#out + 1] = "Kill: " .. list(s.mobs, 4) .. "." end
  elseif s.act == "turnin" then
    if s.q and not C.isOnQuest(s.q) and not C.isTurnedIn(s.q) then
      out[#out + 1] = "That quest is not in your log. /swap sets the step aside."
    elseif s.npc then
      out[#out + 1] = ("Hand it in to %s."):format(s.npc)
    end
  elseif s.hint then
    out[#out + 1] = stop(s.hint)
  end
  -- where, and why there
  local here, there = C.mapPos(), mapOf(s)
  if there and here and there ~= here then
    out[#out + 1] = ("It is in %s; you are in %s. Why: %s"):format(zone(there), zone(here), Coach.moveReason(r, i) or "that is where the guide goes next.")
  elseif there then
    local yd = E.yardsTo and E.yardsTo(s)
    if yd then out[#out + 1] = ("It is here in %s, about %d yards away (the arrow points at it)."):format(zone(there), math.floor(yd + 0.5)) end
  end
  -- on level?
  local sec = Coach.section(r, i)
  local a, b = levels(sec)
  local _, _, level = C.xp()
  if sec and a and level then
    local pace = level < a and ("you are %d level%s under it: expect harder fights; quests in your log and the level stops catch you up."):format(a - level, a - level == 1 and "" or "s")
      or level > b and "you are past it: the guide's quests will give less XP, so do not linger." or "you are on pace."
    out[#out + 1] = ("This part is RestedXP's %q, for levels %d-%d; %s"):format(sec.name, a, b, pace)
    -- behind, or going for completion: quests here the route skips (the quest data's givers)
    if (level < a or Route.goal() == "complete") and here and ns.QInfo then
      local covered = {}
      for j = i, #r.steps do if r.steps[j].q then covered[r.steps[j].q] = true end end
      local extra = {}
      for _, q in ipairs(ns.QInfo.availableOn(here)) do
        if not covered[q] then extra[#extra + 1] = ns.QInfo.title(q, r.steps) end
      end
      if #extra > 0 then
        out[#out + 1] = ("%d quest%s you can take here %s not on the route: %s. %s"):format(
          #extra, #extra == 1 and "" or "s", #extra == 1 and "is" or "are", list(extra),
          Route.goal() == "complete" and "You are going for completion: worth doing while you are here." or "Extra XP while you are under level.")
      end
    end
  end
  -- your own quests
  local off = Coach.offRoute(r, i)
  if #off > 0 then
    out[#out + 1] = ("%d of your quests are not on the route from here (%s). The route will not take you to them; abandon them, do them on the way, or /zug questlog to follow your own quests (your place here is kept)."):format(#off, list(off))
  end
  local aside = #E.deferred()
  if aside > 0 then out[#out + 1] = ("%d step%s set aside: /swap list, /swap back."):format(aside, aside == 1 and " is" or "s are") end
  return out
end

-- ------------------------------------------------------------- the state

local st = { step = nil, sig = nil, progressAt = 0, awayMap = nil, awaySince = 0, snooze = {}, announced = nil, saveAt = -100 }

local function inCombat()
  return (InCombatLockdown and C.try(InCombatLockdown)) or (UnitAffectingCombat and C.try(UnitAffectingCombat, "player"))
end
local function onTaxi() return UnitOnTaxi and C.try(UnitOnTaxi, "player") end

-- questing / travelling / flying / grinding / questlog / done / none
function Coach.state()
  local E = Eng()
  local r = E.route()
  if not r then return "none" end
  if r.dynamic then return "questlog" end
  local s = E.step()
  if not s then return "done" end
  if s.lvl and not E.levelReached(s.lvl, s.xp) then return "grinding" end
  if onTaxi() then return "flying" end
  local here, there = C.mapPos(), mapOf(s)
  if here and there and here ~= there then return "travelling" end
  return "questing"
end

local function snoozed(key) return st.snooze[key] and C.now() < st.snooze[key] end

-- What you are doing right now, read from the game (no model needed, works for
-- everyone, live): dead / afk / flying from Downtime.lua's state; vendor or
-- talking from the game's own frames being open; resting (eating, drinking);
-- grinding at a level stop; hunting in the current "do" step's area; fighting
-- off it; travelling; idle.
local function shown(name)
  local f = _G[name]
  return f and f.IsShown and C.try(f.IsShown, f) and true or false
end
function Coach.activity()
  if ns.Pause.on() then return "paused" end
  local d = ns.Downtime and ns.Downtime.now
  if d == "dead" then return "dead" end
  if d == "afk" then return "afk" end
  if d == "flight" then return "flying" end
  if shown("MerchantFrame") or shown("AuctionHouseFrame") or shown("BankFrame") then return "vendor" end
  if shown("QuestFrame") or shown("GossipFrame") then return "talking" end
  if d == "drink" then return "resting" end
  local state = Coach.state()
  if state == "grinding" then return "grinding" end
  local s = Eng().step()
  if s and s.act == "complete" and ns.Way and ns.Way.mode and ns.Way.mode() == "work" then return "hunting" end
  if d == "combat" then return "fighting" end
  if state == "travelling" or d == "move" then return "travelling" end
  return "idle"
end
Coach.PAUSE = { paused = true, afk = true, dead = true, talking = true, vendor = true, flying = true } -- not "stuck" while these

-- A yes/no question: the game's own popup (StaticPopup_Show, with OnAccept /
-- OnCancel as Blizzard_StaticPopup/StaticPopup.lua calls them), plus the
-- same question in chat with the command that answers it.
-- One question at a time: asked while another of ours is on screen, a question
-- waits its turn (once per key) and comes up when that one closes. That queue
-- is also the first-run wizard: goal, route and live updates, one after another.
local waiting = {}
local function nextQuestion()
  local q = table.remove(waiting, 1)
  if q then Coach.ask(unpack(q, 1, 7)) elseif Coach.onIdle then local f = Coach.onIdle; Coach.onIdle = nil; f() end
end
Coach.waiting = waiting -- for tests

function Coach.ask(key, text, yes, no, onYes, chatHint, onNo)
  if StaticPopup_Visible and C.try(StaticPopup_Visible, "ZUGZUGLEVELER_ASK") then
    for _, q in ipairs(waiting) do if q[1] == key then return false end end
    waiting[#waiting + 1] = { key, text, yes, no, onYes, chatHint, onNo }
    return false
  end
  st.snooze[key] = C.now() + SNOOZE -- asked: not again for a while, whatever the answer
  C.print("%s  |cff999999(%s)|r", text, chatHint)
  if ns.Peon then ns.Peon.say(text, "ask", ns.Peon.LINES.ask) end
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  StaticPopupDialogs.ZUGZUGLEVELER_ASK = {
    text = "zugzug_leveler\n\n%s", button1 = yes, button2 = no,
    OnAccept = function() onYes() end,
    -- the second button only (StaticPopup.lua passes reason "clicked"; Escape is not an answer)
    OnCancel = function(_, _, reason) if onNo and reason == "clicked" then onNo() end end,
    -- closed, however: the next question that waited (after the popup is gone)
    OnHide = function() if C_Timer and C_Timer.After then C_Timer.After(0.5, nextQuestion) else nextQuestion() end end,
    timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
  }
  C.try(StaticPopup_Show, "ZUGZUGLEVELER_ASK", text)
end
Coach.asking = st -- for tests

-- Objective progress as one string. On Forever, quest progress can be a
-- Midnight "secret" in combat, and comparing a secret is an error (Questie's
-- docs/forever-tooltip-secrets.md): a secret part reads as "?".
local function objSig(s)
  if not (s and s.q) then return "" end
  local t = {}
  for _, o in ipairs(C.objectives(s.q)) do
    local text = o.text
    if issecretvalue and (issecretvalue(text) or issecretvalue(o.finished)) then text = "?" end
    t[#t + 1] = (text or "") .. ((not (issecretvalue and issecretvalue(o.finished)) and o.finished) and "+" or "")
  end
  return table.concat(t, ";")
end

-- Is the route anywhere on map m in the next LOOKAHEAD steps?
local function routeHas(m)
  local E = Eng()
  local r = E.route()
  for _, j in ipairs(E.upcoming(LOOKAHEAD)) do
    if mapOf(r.steps[j]) == m then return true end
  end
  return false
end

local function near(s)
  local E = Eng()
  local best = E.yardsTo and E.yardsTo(s)
  for _, p in ipairs(s.path or {}) do
    local d = E.yardsTo(p)
    if d and (not best or d < best) then best = d end
  end
  return best and best <= AT_STEP_YD
end

function Coach.tick()
  if not on() or inCombat() then return end -- nothing to ask in combat, and progress may be secret then
  local E = Eng()
  local r, i, s = E.route(), E.index(), E.step()
  local now = C.now()
  if i ~= st.step then st.step, st.progressAt, st.sig = i, now, objSig(s) end
  local sig = objSig(s)
  if sig ~= st.sig then st.sig, st.progressAt = sig, now end
  local state = Coach.state()
  local act = Coach.activity()
  -- time spent per activity this session, for the page
  ns.cdb.activity = ns.cdb.activity or {}
  if st.lastTick then ns.cdb.activity[act] = (ns.cdb.activity[act] or 0) + math.min(now - st.lastTick, 4) end
  -- away, dead, talking, at a vendor, flying: the "stuck" and "away" clocks wait
  if Coach.PAUSE[act] and st.lastTick then
    local dt = math.min(now - st.lastTick, 4)
    st.progressAt, st.awaySince = st.progressAt + dt, st.awaySince + dt
  end
  st.lastTick = now
  local here = C.mapPos()
  if here ~= st.awayMap then st.awayMap, st.awaySince = here, now end

  if not inCombat() and not Coach.PAUSE[act] then
    -- stuck: a quest step that has not moved while you are at it
    if state == "questing" and s and s.q and (s.act == "accept" or s.act == "complete" or s.act == "turnin")
      and now - st.progressAt >= STUCK_SECS and near(s) and not snoozed("stuck" .. i) then
      Coach.ask("stuck" .. i, ("%s has not moved for %d minutes. Set it aside and go on with the route? It comes back when you level up."):format(
        plain(E.describe(s)), math.floor((now - st.progressAt) / 60)), "Set it aside", "Keep trying",
        function() ns.swapCommand("") end, "/swap does the same; /zug why explains the step")
    -- away: a zone the route has nothing in
    elseif state == "travelling" and here and now - st.awaySince >= AWAY_SECS and not routeHas(here) and not snoozed("away" .. here) then
      Coach.ask("away" .. here, ("The route has nothing in %s: its next step is in %s. Follow your own quests here instead? Your place in the guide is kept."):format(
        zone(here), zone(mapOf(s))), "My quests", "Stay on the route",
        function() ns.QuestLog.start(); C.print("following your quests; /zug route resume goes back to the guide") end,
        "/zug questlog does the same; /zug route resume goes back")
    -- back: in quest log mode, where the guide you left continues
    elseif state == "questlog" and ns.cdb.parked and here and not snoozed("back" .. here) then
      local pr = Route.Get(ns.cdb.parked.route)
      local ps = pr and pr.steps[ns.cdb.parked.step or 1]
      if ps and mapOf(ps) == here then
        Coach.ask("back" .. here, ("You are where %s goes on (step %d: %s). Back to the guide?"):format(
          ns.cdb.parked.route, ns.cdb.parked.step or 1, plain(E.describe(ps))), "Back to the guide", "Not yet",
          function() E.resume() end, "/zug route resume does the same")
      end
    end
  end

  -- for the companion page
  if now - st.saveAt >= 10 then
    st.saveAt = now
    local lines = {}
    for k, l in ipairs(Coach.why()) do lines[k] = plain(l) end
    local doing = act == "hunting" and s and E.objective(s) or nil
    ns.cdb.coach = { state = state, activity = act, doing = doing and plain(doing) or nil, why = lines, at = C.epoch() }
  end
end

-- The heads-up: the route's step is in another zone. Once per zone.
function Coach.announce()
  if not on() or ns.Pause.on() then return end
  local E = Eng()
  local r, i, s = E.route(), E.index(), E.step()
  if not (r and s) or r.dynamic then return end
  local there, here = mapOf(s), C.mapPos()
  if not there or there == here or there == st.announced then return end
  st.announced = there
  local why = Coach.moveReason(r, i) or "that is where the guide goes next."
  C.print("|cff80c0ffnext stop is in %s|r: %s  Why: %s  |cff999999/zug why|r", zone(there), E.describe(s), why)
  if ns.Peon then ns.Peon.say(("New zone: %s. Me lead."):format(zone(there)), nil, ns.Peon.LINES.zone) end
end

-- The window's one line about it (UI.lua shows it under the step).
function Coach.line()
  if not on() then return nil end
  local E = Eng()
  local r, i, s = E.route(), E.index(), E.step()
  if not (r and s) or r.dynamic then return nil end
  local there, here = mapOf(s), C.mapPos()
  if there and here and there ~= here then
    return ("|cff80c0ffin %s|r |cff999999- %s|r"):format(zone(there), Coach.moveReason(r, i) or "where the guide goes next")
  end
end

-- A new player has no route: offer RestedXP's for their race and class
-- (tools/rxp2route.py names them "RXP <Race> <Class>", Skyborne with the faction).
-- Classic Era has two (tools/routes.json): "RXP Survival <Race> <Class>",
-- RestedXP's hardcore Survival Guide, and "RXP Era <Race> <Class>", its speedrun.
-- Returns the one to offer first and the other: Survival first on a Hardcore
-- realm (or when the player turned hardcore steps on), the speedrun elsewhere.
local RACE_NAME = { Scourge = "Undead" }
function Coach.routeFor()
  if C.game() == "era" then
    local _, race = C.try(UnitRace, "player")
    local _, class = C.try(UnitClass, "player")
    if type(race) ~= "string" or type(class) ~= "string" then return nil end
    local who = ("%s %s"):format(RACE_NAME[race] or race, class:sub(1, 1) .. class:sub(2):lower())
    local hc, sr = "RXP Survival " .. who, "RXP Era " .. who
    hc, sr = Route.Get(hc) and hc or nil, Route.Get(sr) and sr or nil
    if Eng().hardcore() then return hc or sr, hc and sr end
    return sr or hc, sr and hc
  end
  local _, race = C.try(UnitRace, "player")
  local _, class = C.try(UnitClass, "player")
  local faction = C.try(UnitFactionGroup, "player")
  if type(race) ~= "string" or type(class) ~= "string" then return nil end
  local cls = class:sub(1, 1) .. class:sub(2):lower()
  local name = ("RXP %s %s"):format(RACE_NAME[race] or race, cls)
  if race == "Skyborne" and faction then name = name .. " " .. faction end
  return Route.Get(name) and name or nil
end

-- How do you want to play? Asked once (the page can change it: Plan & Runs).
-- Any guide besides the routes that build themselves (quest log mode, farming)?
-- (Mists of Pandaria Classic has none: Forever's routes stay off there.)
local function haveGuides()
  for _, r in ipairs(Route.List()) do
    local def = Route.Get(r.name)
    if not (def and def.dynamic) then return true end
  end
  return false
end

ns.On("PLAYER_ENTERING_WORLD", function()
  -- the goal picks which guide steps to skip: nothing to ask without a guide
  if not on() or Route.goal() or ns.db.goalAsked or not haveGuides() then return end
  local function askGoal()
    if Route.goal() then return end
    ns.db.goalAsked = true
    local function set(g) ns.db.goal, ns.db.goalAt = g, C.epoch(); C.print("goal: %s (the companion page's Plan & Runs changes it)", g == "speed" and "fastest leveling" or "completion") end
    Coach.ask("goal", "How do you want to play? Fastest leveling skips cooking, first aid and crafting trainers. Completion keeps everything and points out other quests, reputation and professions.",
      "Fastest leveling", "Completion", function() set("speed") end, "/zug goal speed | /zug goal complete", function() set("complete") end)
  end
  if C_Timer and C_Timer.After then C_Timer.After(4, askGoal) else askGoal() end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
  -- a route that is not here any more (a Forever route a Mists character was
  -- put on before C.isForever): ask again
  if ns.cdb.route and ns.cdb.route ~= ns.QuestLog.NAME and not Route.Get(ns.cdb.route) and not haveGuides() then
    ns.cdb.route, ns.cdb.offeredRoute = nil, nil
  end
  if not on() or ns.cdb.route or ns.cdb.offeredRoute then return end
  local name, other = Coach.routeFor()
  if not name and not haveGuides() then
    -- no guide for this game: offer quest log mode
    local function offerLog()
      if ns.cdb.route then return end
      ns.cdb.offeredRoute = true
      Coach.ask("route", "No guide for this game yet. Follow your quests instead? The arrow takes the shortest way through your quest log and the quest givers near you.",
        "My quests", "Not now", function() ns.QuestLog.start(); C.print("following your quests; /zug why explains any step") end, "/zug questlog does the same")
    end
    if C_Timer and C_Timer.After then C_Timer.After(5, offerLog) else offerLog() end
    return
  end
  if not name then return end
  local function follow(n) Eng().setRoute(n); C.print("following %q; /zug why explains any step", n) end
  local function offer()
    if ns.cdb.route then return end
    ns.cdb.offeredRoute = true
    local aoe = Route.Get(name .. " AoE") and name .. " AoE"
    if other then
      -- Classic Era: RestedXP's hardcore Survival Guide, or its speedrun
      local def = Route.Get(name)
      local safe, fast = name, other
      if not (def and def.hardcore) then safe, fast = other, name end
      local why = Eng().hardcore() and "This is a Hardcore realm: one death ends the character. "
        or ""
      Coach.ask("route", ("No route yet. %sRestedXP has two for you: Survival (%s: built for hardcore, safer quests and pulls) or speedrun (%s: faster, riskier). Which one? Escape: neither for now."):format(why, safe, fast),
        "Survival", "Speedrun", function() follow(safe) end, "/zug route use " .. safe .. " | /zug route use " .. fast, function() follow(fast) end)
    elseif aoe then
      -- RestedXP has an AoE variant for this race and class (pulling packs, for mages)
      Coach.ask("route", ("No route yet. RestedXP has two for you: questing (%s), or AoE (%s: big pulls, faster but riskier). Which one? Escape: neither for now."):format(name, aoe),
        "Questing", "AoE", function() follow(name) end, "/zug route use " .. name .. " | /zug route use " .. aoe, function() follow(aoe) end)
    else
      Coach.ask("route", ("No route yet. Follow %s? It is RestedXP's leveling guide for your race and class, step by step with an arrow."):format(name),
        "Follow it", "Not now", function() follow(name) end, "/zug route use " .. name)
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(5, offer) else offer() end
end)

-- First run: the peon says hello, the questions above come one at a time (the
-- queue in Coach.ask), and when they are done he says where things are.
ns.On("PLAYER_ENTERING_WORLD", function()
  if not on() or ns.db.wizardDone then return end
  ns.db.wizardDone = true
  local function hello()
    if ns.Peon then ns.Peon.say(ns.Peon.LINES.hello or "Zug zug!", "yell") end
    Coach.onIdle = function()
      if ns.Peon then ns.Peon.say(ns.Peon.LINES.goodbye or "Ready to work.") end
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(2, hello) else hello() end
end)

local ticks = 0
ns.On("SL_TICK", function()
  ticks = ticks + 1
  if ticks % 4 == 0 then Coach.tick() end -- every 2 s
end)
ns.On("SL_STEP", function() st.saveAt = -100; Coach.announce() end)
ns.On("ZONE_CHANGED_NEW_AREA", function() Coach.announce() end)
