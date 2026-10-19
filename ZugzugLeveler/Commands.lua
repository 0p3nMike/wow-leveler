-- Commands.lua -- /zug (also /zugzug).

local _, ns = ...
local C = ns.C

local HELP = {
  "/zug                       show or hide the window · /zug options: every toggle in one panel",
  "/zug rec start [name]      start recording a run   · /zug rec stop · /zug rec mark <note>",
  "/zug runs                  list recorded runs",
  "/zug route list            routes you can follow",
  "/zug route use <name>      follow a route (starts at step 1)",
  "/zug route fromrun <n> [name]   turn recorded run n into a route and follow it",
  "/zug route delete <name>   delete a saved route   · /zug route off · /zug route resume (back where you left a guide)",
  "/zug why                   what the step wants and why: the zone, the guide, your level, quests it skips · why debug",
  "/zug coach on|off          heads-ups when the route changes zone, and a question when you seem stuck or lost",
  "/zug goal speed|complete   fastest leveling, or completion (reputation, professions, every quest)",
  "/zug prices                at the auction house: read prices for the page (once every 15 min; also a button there)",
  "/zug model                 your character in 3D, wearing what you wear (drag to turn)",
  "/zug sync                  save now for the companion page (reloads the UI; also the window's Sync button and a key)",
  "/zug live on|off|check     XP, level and quests on the companion page as you play (the game's chat log)",
  "/zug pause · /zug resume   a detour of your own: nothing timed, coach quiet, arrow rests (also the window's button and a key)",
  "/zug errors [clear]        a report of the addon's errors to copy (no character name in it; nothing is sent)",
  "/zug tmog                  what the game says about your transmog, slot by slot (it is saved at the transmogrifier)",
  "/zug talents [list|<name>|auto|off]  the talent to take next (RestedXP's talent guides)",
  "/zug party on|off         share your step and quest progress with party members who use the addon",
  "/zug peon on|off          the talking peon beside the window, off by default (says what the coach says; click him)",
  "/zug skip · /zug back · /zug step <n>",
  "/zug questlog (/zug ql)    no guide: your quest log + nearby quest givers, shortest order · ql debug · ql accept on|off",
  "/zug farm <herb or ore>     walk the gathering nodes you have looted on this map, round and round · farm list · farm off",
  "/zug optimize              do the next steps in the shortest order (from where you stand) · optimize auto|suggest|off|clear",
  "/swap                      set this step (and its quest) aside for now; back on level-up · /swap back · /swap list",
  "/zug export [route]        the route as Lua, for a routes/*.lua file",
  "/zug assist route|all|off  auto accept/turn-in (Shift skips)   · /zug greys on|off",
  "/zug release on|off        auto-release and retrieve corpse (default off)",
  "/zug arrow on|off          the on-screen arrow (our TomTom)   · /zug pin on|off  the game's map pin + marker",
  "/way x y [text] · /way <uiMapID> x y [text] · /way clear   a manual target; right-click the arrow to drop it",
  "/zug xp reset              start a new XP session",
  "/zug danger on|off · /zug flight (known flight points, speeds)",
  "/zug prof                  profession plan: what to craft/gather, materials, trainers · prof way · prof on|off",
  "/zug map on|off · /zug targetbutton on|off · /zug downtime [reset] · /zug splits reset",
  "Key Bindings > AddOns > zugzug_leveler: keys for the quest-item and target buttons (shift-drag to move them)",
}

local function onoff(v) return v == "on" end

-- The report /zug errors shows: version, client, class and level, each error.
-- No character or realm name, so it can be pasted in public.
function ns.errorReport()
  local out = { "zugzug_leveler error report" }
  local v, build = C.try(GetBuildInfo)
  local _, cls = C.try(UnitClass, "player")
  local last = ns.db.errors[#ns.db.errors]
  out[#out + 1] = ("addon %s · client %s (%s) · %s level %s"):format(last.version or "?", tostring(v or "?"), tostring(build or "?"),
    tostring(cls or "?"), tostring(C.try(UnitLevel, "player") or "?"))
  for _, e in ipairs(ns.db.errors) do
    out[#out + 1] = ("%s  in %s: %s"):format(date and date("%Y-%m-%d %H:%M", e.at) or tostring(e.at), e.event, e.err)
  end
  out[#out + 1] = ""
  out[#out + 1] = "Paste this in a new issue at https://github.com/michael-slop/wow-leveler/issues, or send it to whoever gave you the addon."
  return table.concat(out, "\n")
end

local function runLabel(i, r)
  local secs = (r.stopped or C.epoch()) - r.started
  return string.format("#%d %s%s · %s · lvl %s-%s · %d events · %s%s", i, r.name and (r.name .. " · ") or "",
    r.char or "?", date("%Y-%m-%d %H:%M", r.started), r.startLevel or "?", r.endLevel or "now",
    #r.ev, ns.XP.fmtTime(secs), r.stopped and "" or " |cffff4040(recording)|r")
end

local function route(args)
  local sub, rest = args:match("^(%S*)%s*(.-)$")
  local E, Route = ns.Engine, ns.Route
  if sub == "list" or sub == "" then
    local list = Route.List()
    if #list == 0 then C.print("no routes yet: record one with /zug rec start") end
    for _, r in ipairs(list) do C.print("%s  |cff999999%d steps, %s|r", r.name, r.steps, r.from) end
  elseif sub == "use" then
    if not Route.Get(rest) then return C.print("no route %q", rest) end
    E.setRoute(rest)
    C.print("following %q", rest)
  elseif sub == "fromrun" then
    local n, name = rest:match("^(%d+)%s*(.-)$")
    local run = n and ns.db.runs and ns.db.runs[tonumber(n)]
    if not run then return C.print("no run #%s (/zug runs)", tostring(n)) end
    name = (name ~= "" and name) or run.name or ("run " .. n)
    local def = Route.FromRun(run, name)
    Route.Save(def)
    E.setRoute(name)
    C.print("route %q: %d steps from run #%s, now following it", name, #def.steps, n)
  elseif sub == "delete" then
    Route.Delete(rest)
    C.print("deleted %q", rest)
  elseif sub == "resume" then
    if E.resume() then C.print("back on %q at step %d", ns.cdb.route, E.index())
    else C.print("no guide to go back to") end
  elseif sub == "off" then
    E.park()
    ns.cdb.route = nil
    ns.Way.clear()
    ns.Fire("SL_ROUTE", nil)
  else
    C.print("unknown: /zug route %s", sub)
  end
end

-- /swap: set the current step aside for now (see Engine.swap)
function ns.swapCommand(args)
  local E = ns.Engine
  args = (args or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if args == "back" then
    local n = E.unswap()
    C.print(n > 0 and ("%d set-aside step%s back in the route"):format(n, n == 1 and "" or "s") or "nothing set aside")
  elseif args == "list" then
    local list = E.deferred()
    if #list == 0 then return C.print("nothing set aside") end
    local r = E.route()
    for _, i in ipairs(list) do C.print("  %d: %s", i, E.describe(r.steps[i])) end
  else
    local s, n = E.swap()
    if not s then return C.print("no step to swap") end
    C.print("set aside: %s%s  ·  back on level-up, or /swap back", E.describe(s),
      n > 1 and (" (+%d more for that quest)"):format(n - 1) or "")
  end
  if ns.UI then ns.UI.refresh() end
end

SLASH_ZUGZUGLEVELERSWAP1 = "/swap"
SlashCmdList.ZUGZUGLEVELERSWAP = function(msg) ns.swapCommand(msg) end

-- /zug, and /zugzug: the peon's own words (/lev and /leveler were retired 2026-10-18)
SLASH_ZUGZUGLEVELER1 = "/zug"
SLASH_ZUGZUGLEVELER2 = "/zugzug"
SlashCmdList.ZUGZUGLEVELER = function(msg)
  local cmd, args = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then ns.UI.toggle()
  elseif cmd == "help" then for _, l in ipairs(HELP) do C.print(l) end
  elseif cmd == "rec" then
    local sub, rest = args:match("^(%S*)%s*(.-)$")
    if sub == "start" then
      if ns.Rec.active() then return C.print("already recording; /zug rec stop first") end
      C.print("recording run #%d", ns.Rec.start(rest))
    elseif sub == "stop" then
      local n = ns.Rec.stop()
      C.print(n and ("stopped run #" .. n .. " · /zug route fromrun " .. n .. " to follow it") or "not recording")
    elseif sub == "mark" then
      if ns.Rec.mark(rest) then C.print("marked: %s", rest) else C.print("not recording") end
    else
      C.print(ns.Rec.active() and "recording" or "not recording")
    end
  elseif cmd == "runs" then
    local runs = ns.db.runs or {}
    if #runs == 0 then C.print("no runs yet") end
    for i, r in ipairs(runs) do C.print(runLabel(i, r)) end
  elseif cmd == "route" then route(args)
  elseif cmd == "why" and args ~= "debug" then
    for _, l in ipairs(ns.Coach.why()) do C.print(l) end
  elseif cmd == "sync" then ns.Live.sync()
  elseif cmd == "model" then ns.Model.toggle()
  elseif cmd == "tmog" then ns.Export.tmogDebug()
  elseif cmd == "prices" then ns.Auction.scan()
  elseif cmd == "pause" then if args == "" then ns.Pause.toggle() else ns.Pause.set(onoff(args)) end
  elseif cmd == "resume" then ns.Pause.set(false)
  elseif cmd == "errors" then
    if args == "clear" then ns.db.errors = nil; C.print("error list cleared")
    elseif not (ns.db.errors and #ns.db.errors > 0) then C.print("no errors kept. Good.")
    else ns.UI.showText("Error report", ns.errorReport()) end
  elseif cmd == "talents" or cmd == "talent" then ns.Talents.command(args)
  elseif cmd == "party" then ns.Party.toggle(args ~= "off"); C.print("sharing your route place with your party: %s", args ~= "off" and "on" or "off")
  elseif cmd == "peon" then
    local v = args == "" and not (ns.db.peon == true) or (args ~= "" and args ~= "off")
    ns.Peon.toggle(v); C.print("the peon: %s", v and "on" or "off")
  elseif cmd == "goal" then
    if args == "speed" or args == "complete" then
      ns.db.goal, ns.db.goalAt = args, C.epoch()
      if ns.Engine.evaluate then ns.Engine.evaluate() end
    end
    local g = ns.Route.goal()
    C.print("goal: %s  |cff999999(/zug goal speed | /zug goal complete)|r", g == "speed" and "fastest leveling" or g == "complete" and "completion" or "not chosen")
  elseif cmd == "live" then
    if args == "on" or args == "off" then ns.Live.set(args == "on")
    elseif args == "check" then ns.Live.check()
    else C.print("live updates: %s  |cff999999(/zug live on|off|check)|r", ns.Live.logging() and "on" or "off") end
  elseif cmd == "coach" then
    ns.db.coach = args ~= "off"
    C.print("coach (heads-ups and questions): %s", ns.db.coach and "on" or "off")
  elseif cmd == "why" then
    -- /zug why debug: what the engine sees for the current step, to find a step that will not pass
    local E, i = ns.Engine, ns.Engine.index()
    local s = E.step()
    if not s then return C.print("no current step") end
    C.print("step %d: %s", i, E.describe(s))
    if s.q then
      C.print("quest %d %q  onQuest=%s  complete=%s  turnedIn=%s%s", s.q, C.questTitle(s.q) or s.title or "?",
        tostring(C.isOnQuest(s.q)), tostring(C.isComplete(s.q)), tostring(C.isTurnedIn(s.q)),
        s.obj and ("  obj" .. s.obj .. "=" .. tostring(C.objectiveDone(s.q, s.obj))) or "")
    end
    if s.need then
      for k, v in pairs(s.need) do
        C.print("needs %s = %s", k, type(v) == "table" and table.concat(v, ",") or tostring(v))
      end
      C.print("applies now: %s", tostring(E.applies(s)))
    end
    if s.opt then C.print("optional step") end
  elseif cmd == "swap" then ns.swapCommand(args)
  elseif cmd == "flight" then ns.Flight.report()
  elseif cmd == "prof" then
    if args == "way" then ns.Prof.wayToTrainer()
    elseif args == "on" or args == "off" then ns.Prof.toggle(onoff(args)); C.print("profession help: %s", args)
    else
      local rows = ns.Prof.lines()
      if #rows == 0 then C.print("no professions (or /zug prof on)") end
      for _, r in ipairs(rows) do C.print(r) end
    end
  elseif cmd == "options" or cmd == "config" or cmd == "settings" then ns.Options.open()
  elseif cmd == "danger" then ns.Danger.toggle(onoff(args)); C.print("danger warnings: %s", args)
  elseif cmd == "farm" then
    ns.Farm.command(args)
  elseif cmd == "questlog" or cmd == "ql" then
    if args == "debug" then ns.QuestLog.debug()
    elseif args == "accept off" or args == "accept on" then
      ns.db.qlAccept = args == "accept on"
      ns.QuestLog.rebuild(true)
      C.print("quest log mode picks up new quests: %s", args:sub(8))
    else
      ns.QuestLog.start()
      C.print("quest log mode: your quests, shortest order from here (%d placed, %d without a position)",
        #ns.Engine.route().steps, #ns.QuestLog.unplaced)
    end
  elseif cmd == "optimize" or cmd == "opt" then
    local O = ns.Optimizer
    if args == "auto" or args == "off" or args == "suggest" then
      ns.db.optimize = args
      C.print("optimizer: %s", args)
    elseif args == "clear" then
      -- the guide's order for the steps in view; the setting is NOT changed,
      -- auto picks up again once the route has moved past them
      ns.cdb.plan, O.pending = nil, nil
      local upto = O.hold()
      ns.Engine.evaluate()
      ns.Fire("SL_STEP", ns.Engine.index(), ns.Engine.step())
      C.print("guide's order for now%s · optimizer stays %s", upto and (" (until step " .. upto .. ")") or "", O.mode())
    else
      local p = O.pending or O.plan()
      if not p then
        C.print("nothing to reorder here (a level gate, hearth or flight is next, or too few steps)")
      elseif p.save < 1 then
        C.print("the route's order is already the shortest for the next %d steps", #p.idx)
      else
        O.apply(p)
        O.pending = nil
        C.print("reordered the next %d steps: ~%d yd shorter", #p.idx, p.save)
      end
    end
  elseif cmd == "map" then ns.MapPath.toggle(onoff(args)); C.print("map + minimap route: %s", args)
  elseif cmd == "targetbutton" then ns.db.targetButton = onoff(args); ns.Buttons.update(); C.print("target button: %s", args)
  elseif cmd == "downtime" then
    if args == "reset" then ns.Downtime.reset(); C.print("downtime reset")
    else
      local lines = ns.Downtime.report()
      if #lines == 0 then C.print("no downtime data yet") end
      for _, l in ipairs(lines) do C.print(l) end
    end
  elseif cmd == "splits" and args == "reset" then ns.Splits.reset(); C.print("best splits for this route cleared")
  elseif cmd == "skip" then ns.Engine.skip()
  elseif cmd == "back" then ns.Engine.jump(ns.Engine.index() - 1)
  elseif cmd == "step" and tonumber(args) then ns.Engine.jump(tonumber(args))
  elseif cmd == "export" then
    local def = ns.Route.Get(args ~= "" and args or ns.cdb.route)
    if not def then return C.print("no route to export") end
    ns.UI.showText(def.name, ns.Route.ToLua(def))
  elseif cmd == "assist" and (args == "route" or args == "all" or args == "off") then
    ns.db.assist = args
    C.print("assist: %s", args)
  elseif cmd == "greys" then ns.db.sellGreys = onoff(args); C.print("sell greys: %s", args)
  elseif cmd == "release" then ns.db.autoRelease = onoff(args); C.print("auto-release: %s", args)
  elseif cmd == "pin" or cmd == "waypoint" then
    ns.db.waypoint = onoff(args)
    ns.Way.refresh()
    C.print("map pin: %s", args)
  elseif cmd == "arrow" then
    ns.Arrow.toggle(onoff(args))
    C.print("arrow: %s", args)
  elseif cmd == "xp" and args == "reset" then ns.XP.reset(); ns.UI.refresh(); C.print("new XP session")
  else
    C.print("unknown command; /zug help")
  end
  ns.UI.refresh()
end

ns.On("SL_READY", function()
  if ns.Rec.active() then C.print("still recording run #%d", ns.db.recording) end
end)

-- First login with no route: name the generated routes for this race + class.
local hinted
ns.On("PLAYER_ENTERING_WORLD", function()
  if hinted or ns.cdb.route then return end
  hinted = true
  local _, race = C.try(UnitRace, "player")
  local _, class = C.try(UnitClass, "player")
  if not (race and class) then return end
  race = race == "Scourge" and "Undead" or race
  local prefix = ("RXP %s %s"):format(race, class:sub(1, 1) .. class:sub(2):lower())
  local mine = {}
  for _, r in ipairs(ns.Route.List()) do
    if r.name:sub(1, #prefix) == prefix then mine[#mine + 1] = r.name end
  end
  if #mine > 0 then
    C.print("routes for you: %s  ·  /zug route use <name>", table.concat(mine, ", "))
  end
end)
