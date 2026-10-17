-- Commands.lua -- /lev (also /leveler).

local _, ns = ...
local C = ns.C

local HELP = {
  "/lev                       show or hide the window",
  "/lev rec start [name]      start recording a run   · /lev rec stop · /lev rec mark <note>",
  "/lev runs                  list recorded runs",
  "/lev route list            routes you can follow",
  "/lev route use <name>      follow a route (starts at step 1)",
  "/lev route fromrun <n> [name]   turn recorded run n into a route and follow it",
  "/lev route delete <name>   delete a saved route   · /lev route off",
  "/lev skip · /lev back · /lev step <n>",
  "/lev questlog (/lev ql)    no guide: your quest log + nearby quest givers, shortest order · ql debug · ql accept on|off",
  "/lev optimize              do the next steps in the shortest order (from where you stand) · optimize auto|suggest|off|clear",
  "/swap                      set this step (and its quest) aside for now; back on level-up · /swap back · /swap list",
  "/lev export [route]        the route as Lua, for a routes/*.lua file",
  "/lev assist route|all|off  auto accept/turn-in (Shift skips)   · /lev greys on|off",
  "/lev release on|off        auto-release and retrieve corpse (default off)",
  "/lev arrow on|off          the on-screen arrow (our TomTom)   · /lev pin on|off  the game's map pin + marker",
  "/way x y [text] · /way <uiMapID> x y [text] · /way clear   a manual target; right-click the arrow to drop it",
  "/lev xp reset              start a new XP session",
  "/lev danger on|off · /lev flight (known flight points, speeds)",
  "/lev map on|off · /lev targetbutton on|off · /lev downtime [reset] · /lev splits reset",
  "Key Bindings > AddOns > sl0p.leveler: keys for the quest-item and target buttons (shift-drag to move them)",
}

local function onoff(v) return v == "on" end

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
    if #list == 0 then C.print("no routes yet: record one with /lev rec start") end
    for _, r in ipairs(list) do C.print("%s  |cff999999%d steps, %s|r", r.name, r.steps, r.from) end
  elseif sub == "use" then
    if not Route.Get(rest) then return C.print("no route %q", rest) end
    E.setRoute(rest)
    C.print("following %q", rest)
  elseif sub == "fromrun" then
    local n, name = rest:match("^(%d+)%s*(.-)$")
    local run = n and ns.db.runs and ns.db.runs[tonumber(n)]
    if not run then return C.print("no run #%s (/lev runs)", tostring(n)) end
    name = (name ~= "" and name) or run.name or ("run " .. n)
    local def = Route.FromRun(run, name)
    Route.Save(def)
    E.setRoute(name)
    C.print("route %q: %d steps from run #%s, now following it", name, #def.steps, n)
  elseif sub == "delete" then
    Route.Delete(rest)
    C.print("deleted %q", rest)
  elseif sub == "off" then
    ns.cdb.route = nil
    ns.Way.clear()
    ns.Fire("SL_ROUTE", nil)
  else
    C.print("unknown: /lev route %s", sub)
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

SLASH_SLOPLEVELERSWAP1 = "/swap"
SlashCmdList.SLOPLEVELERSWAP = function(msg) ns.swapCommand(msg) end

SLASH_SLOPLEVELER1 = "/lev"
SLASH_SLOPLEVELER2 = "/leveler"
SlashCmdList.SLOPLEVELER = function(msg)
  local cmd, args = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then ns.UI.toggle()
  elseif cmd == "help" then for _, l in ipairs(HELP) do C.print(l) end
  elseif cmd == "rec" then
    local sub, rest = args:match("^(%S*)%s*(.-)$")
    if sub == "start" then
      if ns.Rec.active() then return C.print("already recording; /lev rec stop first") end
      C.print("recording run #%d", ns.Rec.start(rest))
    elseif sub == "stop" then
      local n = ns.Rec.stop()
      C.print(n and ("stopped run #" .. n .. " · /lev route fromrun " .. n .. " to follow it") or "not recording")
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
  elseif cmd == "why" then
    -- what the engine sees for the current step, to find a step that will not pass
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
  elseif cmd == "danger" then ns.Danger.toggle(onoff(args)); C.print("danger warnings: %s", args)
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
      -- in auto mode the next re-plan would undo this, so clearing also stops auto
      if O.mode() == "auto" then ns.db.optimize = "suggest" end
      ns.cdb.plan, O.pending = nil, nil
      ns.Engine.evaluate()
      ns.Fire("SL_STEP", ns.Engine.index(), ns.Engine.step())
      C.print("back to the route's order (optimizer now: %s · /lev optimize auto to turn it back on)", O.mode())
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
    C.print("unknown command; /lev help")
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
    C.print("routes for you: %s  ·  /lev route use <name>", table.concat(mine, ", "))
  end
end)
