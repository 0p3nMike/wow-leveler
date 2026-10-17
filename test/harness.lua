-- harness.lua -- run the REAL addon files under Lua 5.1 / luajit against a
-- fake Forever API, drive game events, and check what the addon does.
--
--   luajit test/harness.lua <path to SlopLeveler/>
--
-- Same idea as ghoul's addon/test/harness.lua: in game every handler runs
-- inside pcall (Events.lua), so a typo never errors there -- it just quietly
-- does nothing. Here the bus's error print is turned into a failure.

local dir = assert(arg[1], "usage: harness.lua <addon dir>")

-- ------------------------------------------------------------ fake world
local W = {
  t = 1000000, gt = 100, level = 5, xp = 100, xpMax = 1000, rested = 0,
  map = 1429, x = 0.40, y = 0.50, shift = false, taxi = false,
  log = {},        -- questID -> { complete = bool, title = "" }
  turnedIn = {},   -- questID -> true
  calls = {},      -- protected-ish calls made, in order
  printed = {},
}
local function called(name, ...) W.calls[#W.calls + 1] = { name, ... } end

-- --------------------------------------------------------- fake frames
local frames = {}
local function stub()
  local o = { scripts = {}, events = {}, shown = true, text = "" }
  return setmetatable(o, { __index = function(t, k)
    if k == "SetScript" then return function(self, s, f) self.scripts[s] = f end end
    if k == "RegisterEvent" then return function(self, e) self.events[e] = true end end
    if k == "Show" then return function(self) self.shown = true end end
    if k == "Hide" then return function(self) self.shown = false end end
    if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
    if k == "IsShown" then return function(self) return self.shown end end
    if k == "SetText" then return function(self, s) self.text = s end end
    if k == "SetFormattedText" then return function(self, fmt, ...) self.text = string.format(fmt, ...) end end
    if k == "CreateFontString" or k == "CreateTexture" or k == "CreateLine" then
      return function(self)
        local c = stub()
        if k == "CreateLine" then rawset(c, "isLine", true) end
        if not rawget(self, "kids") then rawset(self, "kids", {}) end
        table.insert(rawget(self, "kids"), c)
        return c
      end
    end
    if k == "GetWidth" or k == "GetHeight" then return function(self) return rawget(self, "size") or 1000 end end
    if k == "kids" or k == "size" or k == "attrs" then return nil end
    if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
    return function() end -- every other widget method is a no-op
  end })
end
function CreateFrame(_, name)
  local f = stub()
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent = stub()
Minimap = stub(); Minimap.size = 140
SlashCmdList = {}
NUM_BAG_SLOTS = 4
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  W.printed[#W.printed + 1] = table.concat(parts, " ")
end
date = os.date

-- ------------------------------------------------------------ fake API
function GetServerTime() return W.t end
function GetTime() return W.gt end
function UnitXP() return W.xp end
function UnitXPMax() return W.xpMax end
function UnitLevel() return W.level end
function GetXPExhaustion() return W.rested end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitRace() return "Human", "Human", 1 end
function UnitOnTaxi() return W.taxi end
function GetBindLocation() return "Goldshire" end
function UnitFactionGroup() return W.faction or "Alliance" end
function IsShiftKeyDown() return W.shift end
function UnitIsDead() return true end
function UnitIsGhost() return false end
function RepopMe() called("RepopMe") end
function RetrieveCorpse() called("RetrieveCorpse") end
function GetCoinTextureString(n) return tostring(n) .. "c" end
function GetPlayerFacing() return W.facing or 0 end
function InCombatLockdown() return W.combat == true end
function UnitAffectingCombat() return W.combat == true end
function UnitIsDeadOrGhost() return false end
function issecretvalue(v) return W.secret == true end
function GetCVarBool(name) return name == "rotateMinimap" and W.rotate == true end
C_UnitAuras = { GetAuraDataByIndex = function(_, i) if W.drinking and i == 1 then return { name = "Drink" } end end }
C_Minimap = { GetViewRadius = function() return 200 end }
function Mixin(obj, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do obj[k] = v end end return obj end
function CreateFromMixins(...) return Mixin({}, ...) end
MapCanvasDataProviderMixin = { GetMap = function(self) return self.owningMap end }
W.providers = {}
WorldMapFrame = setmetatable({}, { __index = function() return function() end end })
WorldMapFrame.canvas = nil
function WorldMapFrame:AddDataProvider(p) table.insert(W.providers, p) end
function IsShiftKeyDown() return W.shift end
GameTooltip = setmetatable({}, { __index = function() return function() end end })
W.bagItems = {}
C_Texture = { GetAtlasInfo = function(name) return name == "Navigation-Tracked-Arrow" and { width = 32 } or nil end }

function CreateVector2D(x, y)
  return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = CreateVector2D(x, y) } end }

-- Every test map is 1000 x 1000 yards on continent 0, so 0.01 = 10 yards.
C_Map = {
  GetBestMapForUnit = function() return W.map end,
  GetPlayerMapPosition = function() return CreateVector2D(W.x, W.y) end,
  GetMapInfo = function(id) return { name = "Map" .. id } end,
  GetWorldPosFromMapPos = function(_, p) return 0, CreateVector2D(p.x * 1000, p.y * 1000) end,
  GetMapPosFromWorldPos = function(_, v, map) return map or W.map, CreateVector2D(v.x / 1000, v.y / 1000) end,
  CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(p) W.pin = p; called("SetUserWaypoint", p.uiMapID); return true end,
  GetUserWaypoint = function() return W.pin end,
  ClearUserWaypoint = function() W.pin = nil; called("ClearUserWaypoint") end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) called("SuperTrack", v) end }
C_Timer = { After = function(_, fn) fn() end }
C_GameRules = { GetForeverExperiencePreset = function() return 1 end }

local function logList()
  local ids = {}
  for q in pairs(W.log) do ids[#ids + 1] = q end
  table.sort(ids)
  return ids
end
C_QuestLog = {
  IsOnQuest = function(q) return W.log[q] ~= nil end,
  IsComplete = function(q) return W.log[q] ~= nil and W.log[q].complete end,
  IsQuestFlaggedCompleted = function(q) return W.turnedIn[q] == true end,
  GetTitleForQuestID = function(q) return W.log[q] and W.log[q].title or nil end,
  GetNumQuestLogEntries = function() return #logList() end,
  GetInfo = function(i) local q = logList()[i]; return q and { questID = q, isHeader = false } end,
  GetQuestObjectives = function(q) return W.log[q] and W.log[q].objs or {} end,
}

-- quest frame / gossip state for Assist
W.qf = { id = nil, choices = 0, money = 0, completable = true }
function GetQuestID() return W.qf.id end
function QuestFlagsPVP() return false end
function AcceptQuest() called("AcceptQuest", W.qf.id) end
function IsQuestCompletable() return W.qf.completable end
function CompleteQuest() called("CompleteQuest", W.qf.id) end
function GetNumQuestChoices() return W.qf.choices end
function GetQuestMoneyToGet() return W.qf.money end
function GetQuestReward(i) called("GetQuestReward", i) end
function GetQuestItemLink(_, i) return "item" .. i end
C_Item = { GetItemInfo = function(link) local n = tonumber(link:match("%d+")); return link, nil, nil, nil, nil, nil, nil, nil, nil, nil, n * 10 end }
C_Item.GetItemCount = function(id) return W.bagItems[id] or 0 end
C_Item.GetItemIconByID = function() return 134400 end
C_Item.GetItemNameByID = function(id) return "Item " .. id end
W.gossip = { active = {}, available = {} }
C_GossipInfo = {
  GetActiveQuests = function() return W.gossip.active end,
  GetAvailableQuests = function() return W.gossip.available end,
  SelectActiveQuest = function(q) called("SelectActiveQuest", q) end,
  SelectAvailableQuest = function(q) called("SelectAvailableQuest", q) end,
}
W.bags = { [0] = { { quality = 0, hasNoValue = false }, { quality = 1 }, { quality = 0, hasNoValue = true } } }
C_Container = {
  GetContainerNumSlots = function(b) return W.bags[b] and #W.bags[b] or 0 end,
  GetContainerItemInfo = function(b, s) return W.bags[b] and W.bags[b][s] end,
  UseContainerItem = function(b, s) called("UseContainerItem", b, s) end,
}

-- ------------------------------------------------------------ load addon
local ns = {}
local toc = assert(io.open(dir .. "/SlopLeveler.toc"))
local function load(rel)
  rel = rel:gsub("\\", "/")
  local path = dir .. "/" .. rel
  if path:match("%.xml$") then
    -- <Script file="x.lua"/> entries, relative to the xml's folder
    local base = rel:match("^(.*/)") or ""
    local f = assert(io.open(path))
    for file in f:read("*a"):gmatch('<Script%s+file="([^"]+)"') do load(base .. file) end
    f:close()
    return
  end
  local chunk = assert(loadfile(path))
  chunk("SlopLeveler", ns)
end
for line in toc:lines() do
  line = line:gsub("\r", "")
  if line ~= "" and not line:match("^##") then load(line) end
end
toc:close()

local events = frames[1] -- Events.lua makes the first frame
local function fire(e, ...) events.scripts.OnEvent(events, e, ...) end
local function tick(n) for _ = 1, (n or 1) do events.scripts.OnUpdate(events, 0.5) end end

-- ------------------------------------------------------------ test kit
local failures, passed = 0, 0
local function check(cond, what)
  if cond then passed = passed + 1 else failures = failures + 1; io.write("FAIL ", what, "\n") end
end
local function errorsPrinted()
  for _, p in ipairs(W.printed) do if p:find("error in") then return p end end
end
local function hasCall(name, a)
  for _, c in ipairs(W.calls) do if c[1] == name and (a == nil or c[2] == a) then return true end end
  return false
end
local function resetCalls() W.calls = {} end
local function accept(q, title) W.log[q] = { complete = false, title = title or ("Q" .. q) }; fire("QUEST_ACCEPTED", q); fire("QUEST_LOG_UPDATE") end
local function finishObj(q) W.log[q].complete = true; fire("QUEST_LOG_UPDATE") end
local function turnin(q, xp)
  W.log[q] = nil; W.turnedIn[q] = true
  fire("QUEST_TURNED_IN", q, xp, 50); fire("QUEST_REMOVED", q)
  W.xp = W.xp + xp; fire("PLAYER_XP_UPDATE", "player"); fire("QUEST_LOG_UPDATE")
end

-- ================================================================ tests

-- load
fire("ADDON_LOADED", "SlopLeveler")
fire("PLAYER_ENTERING_WORLD")
check(SlopLevelerDB and SlopLevelerCharDB, "SavedVariables tables created")
check(SlashCmdList.SLOPLEVELER, "slash command registered")
local lev = SlashCmdList.SLOPLEVELER

-- XP math
check(ns.XP.delta({ xp = 900, max = 1000, lvl = 5 }, 50, 1200, 6) == 150, "level-up delta = rest of old bar + new")
check(ns.XP.delta({ xp = 100, max = 1000, lvl = 5 }, 160, 1000, 5) == 60, "plain delta")
check(ns.XP.fmtTime(3725) == "1h 02m", "fmtTime hours: " .. ns.XP.fmtTime(3725))

-- recorder: a short played run
lev("rec start test run")
check(ns.Rec.active(), "recording started")
W.t = W.t + 30; W.x = 0.41; tick(1)
accept(101, "Wolves")
W.t = W.t + 60; W.x = 0.45; tick(1)
W.xp = W.xp + 40; fire("PLAYER_XP_UPDATE", "player")
W.t = W.t + 2; W.xp = W.xp + 40; fire("PLAYER_XP_UPDATE", "player") -- merges with the one before
finishObj(101)
W.t = W.t + 60; W.x = 0.40; tick(1)
turnin(101, 300)
accept(102, "Boars")
accept(103, "Abandon me")
W.log[103] = nil; fire("QUEST_REMOVED", 103)
W.t = W.t + 60; W.map = 1430; W.x, W.y = 0.20, 0.30; fire("ZONE_CHANGED_NEW_AREA")
finishObj(102)
turnin(102, 200)
lev("rec mark grind here")
lev("rec stop")
check(not ns.Rec.active(), "recording stopped")

local run = SlopLevelerDB.runs[1]
local kinds = {}
for _, e in ipairs(run.ev) do kinds[#kinds + 1] = e.e end
local seq = table.concat(kinds, ",")
check(seq == "zone,accept,xp,done,turnin,accept,accept,abandon,zone,done,turnin,mark", "event sequence: " .. seq)
check(run.ev[3].gain == 80 and run.ev[3].n == 2, "kill XP merged into one entry")
check(run.ev[5].gain == 300, "turn-in XP recorded")
check(#run.path >= 3, "breadcrumbs recorded: " .. #run.path)
check(run.preset == "modern", "XP preset tagged")
local s = ns.XP.session()
check(s.total == 580 and s.quest == 500, ("session split total=%d quest=%d"):format(s.total, s.quest))

-- run -> route
lev("route fromrun 1 Elwynn v1")
local r = ns.Route.Get("Elwynn v1")
check(r ~= nil, "route saved from run")
local acts = {}
for _, st in ipairs(r.steps) do acts[#acts + 1] = st.act .. (st.q and st.q or "") end
local aseq = table.concat(acts, ",")
check(aseq == "accept101,complete101,turnin101,accept102,complete102,turnin102,note", "route steps: " .. aseq)

-- export round-trips
local src = ns.Route.ToLua(r)
local reg
local fakeNs = { Route = { Register = function(def) reg = def end } }
local chunk = assert(loadstring(src))
chunk("SlopLeveler", fakeNs)
check(reg and #reg.steps == #r.steps and reg.steps[1].q == 101 and reg.steps[1].title == "Wolves", "exported Lua re-registers the same route")

-- engine: follow the route on a fresh character state
SlopLevelerCharDB.route = nil
W.log, W.turnedIn = {}, {}
W.map, W.x, W.y = 1429, 0.40, 0.50
resetCalls()
lev("route use Elwynn v1")
check(ns.Engine.index() == 1, "starts at step 1")
check(hasCall("SetUserWaypoint", 1429) and hasCall("SuperTrack", true), "waypoint + arrow set for step 1")
accept(101, "Wolves")
check(ns.Engine.index() == 2, "accept advances to complete step, now " .. ns.Engine.index())
finishObj(101)
check(ns.Engine.index() == 3, "objectives complete advances to turn-in")
turnin(101, 300)
check(ns.Engine.index() == 4, "turn-in advances")
check(SlopLevelerCharDB.stats[1] ~= nil, "per-step stats recorded")
-- out of order: 102 already done before we reach its steps
W.turnedIn[102] = true; fire("QUEST_LOG_UPDATE")
check(ns.Engine.index() == 7, "already-turned-in quest skips its steps, now " .. ns.Engine.index())
lev("skip")
check(ns.Engine.index() == 8 and ns.Engine.step() == nil, "skip past last step finishes the route")
lev("back")
check(ns.Engine.index() == 7, "back goes one step back")

-- goto step by distance
ns.Route.Register({ name = "goto test", steps = {
  { act = "goto", map = 1429, x = 0.60, y = 0.50, r = 15 },
  { act = "note", text = "end" },
} })
lev("route use goto test")
W.map, W.x, W.y = 1429, 0.50, 0.50; tick(1)
check(ns.Engine.index() == 1, "100 yards away: goto not done")
W.x = 0.59; tick(1)
check(ns.Engine.index() == 2, "10 yards away: goto done")
W.x = 0.40; tick(1)
check(ns.Engine.index() == 2, "walking away does not undo a finished step")

-- assist, route mode
lev("route use Elwynn v1")
W.log, W.turnedIn = {}, {}
resetCalls()
W.qf.id = 101; fire("QUEST_DETAIL")
check(hasCall("AcceptQuest", 101), "assist accepts a route quest")
resetCalls()
W.qf.id = 999; fire("QUEST_DETAIL")
check(not hasCall("AcceptQuest"), "assist ignores a quest not on the route")
resetCalls()
W.shift = true; W.qf.id = 101; fire("QUEST_DETAIL"); W.shift = false
check(not hasCall("AcceptQuest"), "Shift suppresses assist")
resetCalls()
W.qf.id = 101; W.qf.choices = 0; fire("QUEST_PROGRESS"); fire("QUEST_COMPLETE")
check(hasCall("CompleteQuest", 101) and hasCall("GetQuestReward", 0), "assist turns in with no reward choice")
resetCalls()
W.qf.choices = 3; fire("QUEST_COMPLETE")
check(not hasCall("GetQuestReward"), "assist never picks between rewards")
check(W.printed[#W.printed]:find("item3"), "prints the best-selling choice")
resetCalls()
W.qf.choices = 1; W.qf.money = 500; fire("QUEST_COMPLETE")
check(not hasCall("GetQuestReward"), "assist never pays gold to complete")
W.qf.money = 0
resetCalls()
W.gossip.active = { { questID = 999, isComplete = true }, { questID = 102, isComplete = true } }
fire("GOSSIP_SHOW")
check(hasCall("SelectActiveQuest", 102) and not hasCall("SelectActiveQuest", 999), "gossip picks only route turn-ins")
resetCalls(); fire("GOSSIP_SHOW")
check(not hasCall("SelectActiveQuest"), "gossip does not re-pick the same quest within 3 s")
resetCalls(); fire("MERCHANT_SHOW")
check(hasCall("UseContainerItem", 0, 1) and #W.calls == 1, "sells only the grey with a value")
resetCalls(); fire("PLAYER_DEAD")
check(not hasCall("RepopMe"), "no auto-release by default")
lev("release on"); fire("PLAYER_DEAD")
check(hasCall("RepopMe"), "auto-release when turned on")
lev("assist off"); resetCalls(); W.qf.id = 101; fire("QUEST_DETAIL")
check(not hasCall("AcceptQuest"), "assist off does nothing")

-- RXP-style steps: objectives, conditions, optional, world positions
lev("assist route")
ns.Route.Register({ name = "rxp test", steps = {
  { act = "complete", q = 201, obj = 2 },
  { act = "turnin", q = 202, opt = true },
  { act = "accept", q = 203, need = { turned = { 999 } } },
  { act = "note", text = "too high", need = { below = 3 } },
  { act = "goto", map = 1429, cont = 0, wx = 600, wy = 500 },
  { act = "note", text = "end" },
} })
W.log = { [201] = { complete = false, objs = { { finished = true }, { finished = false } } } }
W.turnedIn = {}
lev("route use rxp test")
check(ns.Engine.index() == 1, "objective 2 not finished: complete step waits")
resetCalls()
W.log[201].objs[2].finished = true
W.map, W.x, W.y = 1429, 0.1, 0.1
fire("QUEST_LOG_UPDATE")
check(ns.Engine.index() == 5, "obj done, optional turn-in, conditional accept, level-gated note all passed: now " .. ns.Engine.index())
local s5 = ns.Engine.step()
check(s5.x and math.abs(s5.x - 0.6) < 1e-9 and math.abs(s5.y - 0.5) < 1e-9, "world position resolved to map x/y")
check(hasCall("SetUserWaypoint", 1429), "waypoint set from a world-position step")
W.x, W.y = 0.595, 0.5; tick(1)
check(ns.Engine.index() == 6, "arrived at a world-position goto")

-- generated RXP routes load, and only this faction's
local names = {}
for _, r in ipairs(ns.Route.List()) do names[r.name] = r.steps end
check(names["RXP Human Warrior"] and names["RXP Human Warrior"] > 700, "generated Human route loaded")
check(names["RXP Orc Warrior"] == nil, "other faction's route not loaded")
local hr = ns.Route.Get("RXP Human Warrior")
check(hr.steps[1].q == 783 and hr.steps[1].wx == -8933.47, "first Human step is A Threat Within at Deputy Willem")
local bad = 0
local OTHER = { ["goto"] = true, fly = true, hearth = true, sethearth = true, train = true, note = true }
for _, st in ipairs(hr.steps) do
  if ns.Route.QUEST_STEP[st.act] then
    if type(st.q) ~= "number" then bad = bad + 1 end
  elseif not OTHER[st.act] then
    bad = bad + 1
  end
end
check(bad == 0, "every generated step has a known act and quest id")

-- the arrow (TomTom replacement): world vector +x north, +y west; facing CCW from north
local A = ns.Arrow
local function near(a, b) return math.abs(a - b) < 1e-6 end
local d, rel = A.solve({ cont = 0, wx = 100, wy = 0 }, 0, 0, 0, 0)
check(near(d, 100) and near(rel, 0), "target due north, facing north: straight ahead")
d, rel = A.solve({ cont = 0, wx = 0, wy = 50 }, 0, 0, 0, 0)
check(near(rel, math.pi / 2), "target west, facing north: arrow turns left (CCW 90)")
d, rel = A.solve({ cont = 0, wx = 100, wy = 0 }, 0, 0, 0, math.pi / 2)
check(near(rel, 3 * math.pi / 2), "facing west, target north: arrow turns right (CW 90)")
check(A.solve({ cont = 1, wx = 1, wy = 1 }, 0, 0, 0, 0) == nil, "other continent: no bearing")
local r0, g0 = A.color(0)
local r1, g1 = A.color(math.pi)
check(r0 == 0 and g0 == 1 and r1 == 1 and g1 == 0, "green ahead, red behind")

-- /way: a manual target beats the route, and arriving drops it
lev("route use goto test")
W.map, W.x, W.y, W.facing = 1429, 0.10, 0.10, 0
resetCalls()
SlashCmdList.SLOPLEVELERWAY("50 40 the tree")
local t = ns.Way.current()
check(t and t.manual and t.map == 1429 and near(t.x, 0.5) and t.text == "the tree", "/way x y text sets a manual target on this map")
check(hasCall("SetUserWaypoint", 1429), "/way also sets the game's pin")
SlashCmdList.SLOPLEVELERWAY("1430 20 30")
check(ns.Way.current().map == 1430, "/way <mapID> x y")
SlashCmdList.SLOPLEVELERWAY("50 40")
W.x, W.y = 0.499, 0.40; A.update()
check(not ns.Way.current() or not ns.Way.current().manual, "arriving at a /way drops it, back to the route")
SlashCmdList.SLOPLEVELERWAY("50 40"); SlashCmdList.SLOPLEVELERWAY("clear")
check(not (ns.Way.current() or {}).manual, "/way clear")
lev("arrow off"); lev("arrow on"); lev("pin off"); lev("pin on")

-- sub-objectives: travel mode outside the area, work mode inside it
ns.Route.Register({ name = "obj test", steps = {
  { act = "complete", q = 301, obj = 2, hint = "Kill Gnolls", mobs = { "Gnoll" }, npc = nil,
    map = 1429, cont = 0, wx = 500, wy = 500, loop = true, path = {
      { map = 1429, cont = 0, wx = 500, wy = 500 },            -- radius 0: a pin only, never walked
      { map = 1429, cont = 0, wx = 500, wy = 500, r = 20 },
      { map = 1429, cont = 0, wx = 600, wy = 500, r = 20 },
  } },
  { act = "complete", q = 302, obj = 1, map = 1429, cont = 0, wx = 800, wy = 800 },
  { act = "note", text = "end" },
} })
W.log = {
  [301] = { complete = false, objs = { { text = "Banner: 1/1", finished = true }, { text = "Gnoll slain: 2/5", finished = false } } },
  [302] = { complete = false, objs = { { text = "Rat slain: 0/3", finished = false } } },
}
W.turnedIn = {}
W.map, W.x, W.y = 1429, 0.10, 0.10            -- world (100, 100): far away
lev("route use obj test")
local function ui() return table.concat(ns.UI.lines(), "\n") end
check(ns.Way.mode() == "travel", "far from the area: travel mode")
check(ns.Way.current().wx == 500 and not ns.Way.current().dim, "travel: arrow heads for the area")
check(ui():find("Gnoll slain: 2/5", 1, true) and ui():find("Kill Gnolls", 1, true), "window lists objectives and the guide's instruction")
check(not ui():find("kill:", 1, true), "mob list only shown once you are there")
W.x, W.y = 0.5, 0.5; tick(1)                   -- world (500, 500): in the area
check(ns.Way.mode() == "work", "in the area: work mode")
check(ui():find("Do:|r Gnoll slain: 2/5", 1, true), "work: the main line IS the objective")
check(ui():find("kill:", 1, true) and ui():find("Gnoll", 1, true), "work: who to kill")
check(ns.Way.current().wx == 600, "loop: reached point 1, arrow moves on to point 2")
check(ns.Way.current().text == "Gnoll slain: 2/5", "loop: arrow title is the objective")
W.x = 0.6; tick(1)
check(ns.Way.current().wx == 500, "loop: reached the last point, back to the first")
W.log[301].objs[2] = { text = "Gnoll slain: 5/5", finished = true }; fire("QUEST_LOG_UPDATE")
check(ns.Engine.index() == 2, "objective done: next step")
W.x, W.y = 0.8, 0.8; tick(1)
check(ns.Way.mode() == "work" and ns.Way.current().dim, "work with no loop: arrow dims on the spot")
check(ns.Way.current().text == "Rat slain: 0/3", "dimmed arrow shows the objective")

-- RXP's .xp gates: level plus XP into it (the bug that sent Michael ahead too early)
local E = ns.Engine
W.level, W.xp, W.xpMax = 5, 1200, 2800
check(not E.levelReached(5, 1940), "level 5 with 1200 xp: 5+1940 not reached")
W.xp = 1940
check(E.levelReached(5, 1940), "level 5 with 1940 xp: reached")
W.level, W.xp, W.xpMax = 6, 10, 3500
check(E.levelReached(5, 1940), "level 6: past it")
W.level, W.xp, W.xpMax = 5, 1300, 2800
check(not E.levelReached(5, 0.5) and E.levelReached(5, 0.4), "fraction of the bar")
W.level, W.xp, W.xpMax = 5, 2600, 2800
check(E.levelReached(6, -300) and not E.levelReached(6, -100), "N xp short of the next level")
W.level = 4
check(not E.levelReached(5) and E.levelReached(4), "plain level gate")
ns.Route.Register({ name = "xp gate", steps = {
  { act = "note", text = "Grind to 1940+/2800xp", lvl = 5, xp = 1940 },
  { act = "accept", q = 401 },
} })
W.level, W.xp, W.xpMax, W.log, W.turnedIn = 5, 100, 2800, {}, {}
lev("route use xp gate")
check(ns.Engine.index() == 1, "at level 5 + 100 xp the grind step holds")
W.xp = 1950; fire("PLAYER_XP_UPDATE", "player"); tick(1)
check(ns.Engine.index() == 2, "at 1950 xp it passes")
W.level, W.xp, W.xpMax = 5, 100, 1000

-- "not offered yet": at the step's NPC, and the quest is not in their list
function UnitName(u) if u == "npc" then return W.npc end return "Tester" end
ns.Route.Register({ name = "offer test", steps = {
  { act = "accept", q = 501, title = "Locked Quest", npc = "Executor Arren", map = 1429, cont = 0, wx = 500, wy = 500 },
  { act = "note", text = "end" },
} })
W.log, W.turnedIn, W.map, W.x, W.y = {}, {}, 1429, 0.1, 0.1
lev("route use offer test")
W.npc = "Someone Else"; W.gossip = { active = {}, available = { { questID = 777 } } }
fire("GOSSIP_SHOW")
check(not ns.Assist.notOffered[501], "a different NPC proves nothing")
W.npc = "Executor Arren"; fire("GOSSIP_SHOW")
check(ns.Assist.notOffered[501], "the step's NPC without the quest: marked not offered")
check(table.concat(ns.UI.lines(), "\n"):find("not offered yet", 1, true), "window says so")
W.gossip.available = { { questID = 501 } }; fire("GOSSIP_SHOW")
check(not ns.Assist.notOffered[501], "offered later (level up): mark cleared")
W.npc = nil

-- /swap: set a quest aside, rotate on, come back on level-up or accept
ns.Route.Register({ name = "swap test", steps = {
  { act = "accept", q = 601, title = "Locked" },
  { act = "accept", q = 602, title = "Open" },
  { act = "complete", q = 601, obj = 1 },
  { act = "complete", q = 602, obj = 1 },
  { act = "turnin", q = 601 },
  { act = "turnin", q = 602 },
} })
W.log, W.turnedIn, W.level = {}, {}, 5
lev("route use swap test")
check(ns.Engine.index() == 1, "starts on the locked quest")
SlashCmdList.SLOPLEVELERSWAP("")
check(ns.Engine.index() == 2, "/swap moves on to the next quest")
check(#ns.Engine.deferred() == 3, "its do + turn-in steps are set aside too")
accept(602, "Open")
W.log[602].complete = true; W.log[602].objs = { { finished = true } }; fire("QUEST_LOG_UPDATE")
check(ns.Engine.index() == 6, "route runs past the set-aside steps: now " .. ns.Engine.index())
check(table.concat(ns.UI.lines(), "\n"):find("3 set aside", 1, true), "window shows what is set aside")
W.level = 6; fire("PLAYER_LEVEL_UP", 6)
check(ns.Engine.index() == 1 and #ns.Engine.deferred() == 0, "level-up brings them back, from the first")
SlashCmdList.SLOPLEVELERSWAP("")
accept(601, "Locked")
check(#ns.Engine.deferred() == 0, "accepting it anyway brings it back")
check(ns.Engine.index() == 3, "and the route continues at its do step: " .. ns.Engine.index())
SlashCmdList.SLOPLEVELERSWAP(""); lev("swap back")
check(#ns.Engine.deferred() == 0, "/lev swap back")
W.level = 5

-- buttons: quest item + target macro, never touched in combat
local item, tgt = _G.SlopLevelerItemButton, _G.SlopLevelerTargetButton
local function attr(b, k) return b.attrs and b.attrs[k] end
for _, b in ipairs({ item, tgt }) do
  b.attrs = {}
  b.SetAttribute = function(self, k, v) self.attrs[k] = v end
end
ns.Route.Register({ name = "button test", steps = {
  { act = "complete", q = 701, obj = 1, use = 5185, mobs = { "Gnoll", "Gnoll Brute" } },
  { act = "turnin", q = 701, npc = "Executor Arren" },
} })
W.log = { [701] = { complete = false, objs = { { finished = false } } } }
W.turnedIn, W.bagItems = {}, { [5185] = 1 }
lev("route use button test")
check(item.shown and attr(item, "type") == "item" and attr(item, "item") == "item:5185", "item button set to the step's quest item")
check(tgt.shown and attr(tgt, "type") == "macro", "target button is a macro")
check(attr(tgt, "macrotext") == "/targetexact Gnoll Brute\n/targetexact Gnoll", "macro targets the mobs, first name last so it wins")
W.bagItems = {}; fire("BAG_UPDATE_DELAYED")
check(not item.shown, "item not in bags: button hidden")
W.combat = true
W.log[701].objs[1].finished = true; W.log[701].complete = true; fire("QUEST_LOG_UPDATE")
check(attr(tgt, "macrotext"):find("Gnoll", 1, true), "in combat: secure button left alone")
W.combat = false; fire("PLAYER_REGEN_ENABLED")
check(attr(tgt, "macrotext") == "/targetexact Executor Arren", "after combat: turn-in step targets the NPC")

-- speedrun splits: played steps timed, fast-forwarded ones never
local S = ns.Splits
local function play(secs) for _ = 1, math.floor(secs / 1.5) do W.gt = W.gt + 1.5; tick(1) end end
ns.Route.Register({ name = "split test", steps = {
  { act = "accept", q = 801 }, { act = "accept", q = 802 }, { act = "note", text = "end" },
} })
W.log, W.turnedIn = {}, {}
lev("route use split test")
play(30); accept(801)
local bs = SlopLevelerDB.best["split test"].seg
check(bs[1] and math.abs(bs[1] - 30) < 2, "step 1 timed ~30s: " .. tostring(bs[1]))
lev("route use split test")                      -- 801 already accepted: fast-forward
check(math.abs(bs[1] - 30) < 2, "fast-forwarded step does not set a fake best")
W.log = {}; lev("route use split test")
play(10); accept(801)
check(bs[1] < 12, "faster run sets a new best")
check(S.line():find("-0:2", 1, true) and S.line():find("1 gold", 1, true), "line shows time gained and the gold: " .. tostring(S.line()))

-- downtime: one state per tick, secret aura names ignored
lev("downtime reset")
W.map, W.x, W.y = 1429, 0.2, 0.2
W.combat = true; play(15)
W.combat, W.drinking = false, true; play(9)
W.drinking = false
for _ = 1, 4 do W.x = W.x + 0.01; W.gt = W.gt + 1.5; tick(1) end
local t, total = ns.Downtime.shares()
check(t.combat and t.drink and t.move and t.combat > t.drink, "combat, drink and move all counted")
check(ns.Downtime.line():find("combat", 1, true), "window line: " .. tostring(ns.Downtime.line()))
W.drinking, W.secret = true, true
check(not ns.Downtime.drinking(), "a secret aura name is never compared")
W.drinking, W.secret = false, false

-- the route on the world map: you -> next steps, plus the loop
local P = W.providers[1]
check(P, "data provider added to the world map")
local canvas = stub(); canvas.size = 1000
P.owningMap = { GetMapID = function() return 1429 end, GetCanvas = function() return canvas end, GetCanvasScale = function() return 1 end }
lev("route use obj test")
W.log = { [301] = { complete = false, objs = { { finished = true }, { finished = false } } } }
W.map, W.x, W.y = 1429, 0.1, 0.1
P:RefreshAllData()
local function shownLines()
  local n = 0
  for _, f in ipairs(frames) do
    for _, c in ipairs(rawget(f, "kids") or {}) do
      if rawget(c, "isLine") and c.shown then n = n + 1 end
    end
  end
  return n
end
local steps, loop = ns.MapPath.points()
check(#steps == 2 and #loop == 2, "points: the 2 upcoming steps with a place, and the 2-point loop")
check(shownLines() == 4, "world map: you->step1->step2 (2 lines) + closed loop (2 lines) = " .. shownLines())
lev("map off")
check(shownLines() == 0, "/lev map off clears the lines")
lev("map on")

-- minimap placement math
local MP = ns.MapPath
local x, y = MP.miniOffset({ cont = 0, wx = 100, wy = 0 }, 0, 0, 0, nil, false, 200, 70)
check(math.abs(x) < 1e-9 and math.abs(y - 35) < 1e-9, "north-up: a point 100 yd north is straight up")
x, y = MP.miniOffset({ cont = 0, wx = 0, wy = -100 }, 0, 0, 0, nil, false, 200, 70)
check(math.abs(x - 35) < 1e-9 and math.abs(y) < 1e-9, "north-up: a point east is to the right (wy is west)")
x, y = MP.miniOffset({ cont = 0, wx = 100, wy = 0 }, 0, 0, 0, math.pi / 2, true, 200, 70)
check(math.abs(x - 35) < 1e-9 and math.abs(y) < 1e-9, "rotating minimap facing west: north is to your right")
local _, _, edge = MP.miniOffset({ cont = 0, wx = 1000, wy = 0 }, 0, 0, 0, nil, false, 200, 70)
check(edge, "far point pinned to the rim")

-- optimizer: Michael's case. In the field, the route says "walk to town and
-- train", then come back to the field for the next quest, then town again.
local O = ns.Optimizer
lev("optimize suggest")
ns.Route.Register({ name = "opt test", steps = {
  { act = "complete", q = 901, obj = 1, map = 1429, cont = 0, wx = 900, wy = 0 },   -- 1 field
  { act = "train", text = "Train Fireball", map = 1429, cont = 0, wx = 0, wy = 0 },  -- 2 town
  { act = "complete", q = 902, obj = 1, map = 1429, cont = 0, wx = 910, wy = 0 },   -- 3 field
  { act = "turnin", q = 901, map = 1429, cont = 0, wx = 0, wy = 0 },                 -- 4 town
  { act = "turnin", q = 902, map = 1429, cont = 0, wx = 5, wy = 0 },                 -- 5 town
  { act = "note", text = "Grind", lvl = 99 },                                         -- 6 barrier
  { act = "accept", q = 903, map = 1429, cont = 0, wx = 0, wy = 0 },                 -- 7
} })
W.log = { [901] = { complete = false, objs = { { finished = false } } }, [902] = { complete = false, objs = { { finished = false } } } }
W.turnedIn, W.level = {}, 5
W.map, W.x, W.y = 1429, 0.9, 0.0                 -- standing in the field
lev("route use opt test")
local p = O.plan()
check(p and #p.idx == 5 and p.after == 6, "window: the 5 steps up to the level gate")
-- route: 900->0 (train) ->910 ->0 ->5 = 0+900+910+910+5 = 2725; best: 1,3,5,4,2 = 0+10+905+5+0 = 920
check(p and math.abs(p.routeCost - 2725) < 1 and math.abs(p.bestCost - 920) < 1, ("route order %d yd, best %d yd"):format(p.routeCost, p.bestCost))
check(p.idx[1] == 1 and p.idx[2] == 3, "best: finish both field quests first: " .. table.concat(p.idx, ","))
local pos = {}
for k, j in ipairs(p.idx) do pos[j] = k end
check(pos[1] < pos[4] and pos[3] < pos[5], "never turns in before the quest is done")
check(O.pending and table.concat(ns.UI.lines(), "\n"):find("shorter order saves", 1, true), "suggested, not forced")
check(ns.Engine.index() == 1, "the route is unchanged until you say so")
lev("optimize")
W.log[901].objs[1].finished = true; W.log[901].complete = true; fire("QUEST_LOG_UPDATE")
check(ns.Engine.index() == 3, "after the first field quest: the other field quest, not the trainer")
check(table.concat(ns.UI.lines(), "\n"):find("optimized order", 1, true), "window says the order is optimized")
W.log[902].objs[1].finished = true; W.log[902].complete = true; W.x = 0.0; fire("QUEST_LOG_UPDATE")
local left = {}
for _, j in ipairs(ns.cdb.plan.list) do left[#left + 1] = j end
check(#left == 3 and ns.Engine.index() == left[1], "then the town stops: " .. table.concat(left, ","))
fire("TRAINER_CLOSED")
W.log[901], W.turnedIn[901] = nil, true; fire("QUEST_TURNED_IN", 901, 100, 0)
W.log[902], W.turnedIn[902] = nil, true; fire("QUEST_TURNED_IN", 902, 100, 0)
check(ns.cdb.plan == nil and ns.Engine.index() == 6, "plan done: back on the route after the window (" .. ns.Engine.index() .. ")")

-- auto mode: re-plans from where you are as you move, keeps the arrow on the
-- shortest order, never yanks you out of the area you are working in
lev("optimize auto")
ns.Route.Register({ name = "auto test", steps = {
  { act = "complete", q = 911, obj = 1, map = 1429, cont = 0, wx = 800, wy = 0 },   -- 1 east
  { act = "complete", q = 912, obj = 1, map = 1429, cont = 0, wx = 0, wy = 800 },   -- 2 north
  { act = "complete", q = 913, obj = 1, map = 1429, cont = 0, wx = 120, wy = 0 },   -- 3 near
  { act = "note", text = "end", lvl = 99 },
} })
W.log = {}
for _, q in ipairs({ 911, 912, 913 }) do W.log[q] = { complete = false, objs = { { finished = false } } } end
W.turnedIn = {}
-- (exactly 0,0 is "no position" to Compat.mapPos, as the game reports in instances)
W.map, W.x, W.y = 1429, 0.005, 0.005
lev("route use auto test")
check(ns.Engine.index() == 3, "auto: from (0,0) the near quest comes first, without asking: " .. ns.Engine.index())
local steps0 = 0
ns.On("SL_STEP", function() steps0 = steps0 + 1 end)
for _ = 1, 8 do W.gt = W.gt + 0.5; tick(1) end
check(ns.Engine.index() == 3 and steps0 == 0, "standing still: no re-plan churn, the arrow stays put")
W.x, W.y = 0.005, 0.7                                 -- walked most of the way north
for _ = 1, 4 do W.gt = W.gt + 0.5; tick(1) end
check(ns.Engine.index() == 2, "walked north: the arrow swaps to the north quest: " .. ns.Engine.index())
W.x, W.y = 0.79, 0.0                                  -- now standing in the east quest's area
local realMode = ns.Way.mode
ns.Way.mode = function() return "work" end
for _ = 1, 4 do W.gt = W.gt + 0.5; tick(1) end
check(ns.Engine.index() == 2, "in a work area: no switching mid-objective")
ns.Way.mode = realMode
for _ = 1, 4 do W.gt = W.gt + 0.5; tick(1) end
check(ns.Engine.index() == 1, "out of it: the east quest you are standing next to: " .. ns.Engine.index())
lev("optimize clear")
check(ns.db.optimize == "suggest" and ns.cdb.plan == nil, "clear stops auto so it is not re-applied")
lev("optimize suggest")

-- the solver is exact: compare with trying every order
math.randomseed(7)
for trial = 1, 5 do
  local n, P = 7, {}
  for k = 1, n do P[k] = { 0, math.random(0, 1000), math.random(0, 1000) } end
  local must = {}
  for k = 1, n do must[k] = {} end
  must[3] = { 1 }; must[6] = { 2, 3 }; must[7] = { 5 }
  local from = { 0, 500, 500 }
  local _, best = O.solve(from, P, must)
  local brute = math.huge
  local function perm(order, used)
    if #order == n then brute = math.min(brute, O.cost(from, P, order)); return end
    for k = 1, n do
      if not used[k] then
        local ok = true
        for _, a in ipairs(must[k]) do if not used[a] then ok = false end end
        if ok then used[k] = true; order[#order + 1] = k; perm(order, used); order[#order] = nil; used[k] = nil end
      end
    end
  end
  perm({}, {})
  check(math.abs(best - brute) < 1e-6, ("trial %d: solver %.1f == brute force %.1f"):format(trial, best, brute))
end
lev("optimize clear")

-- UI renders without errors
ns.UI.refresh()
lev("export")
local before = #W.printed
lev("route use rxp test"); lev("why")
local said = table.concat(W.printed, "\n", before + 1)
check(said:find("step %d+:"), "/lev why reports the step")
lev("runs")
lev("help")

-- optional: write SlopLevelerDB the way WoW writes SavedVariables
-- (["key"] = value, array items followed by "-- [n]"), for tools/routes.py
if arg[2] then
  local out = {}
  local function ser(v, ind)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    local lines, pad = { "{" }, string.rep("\t", ind + 1)
    local n = #v
    for i = 1, n do lines[#lines + 1] = pad .. ser(v[i], ind + 1) .. ", -- [" .. i .. "]" end
    local keys = {}
    for k in pairs(v) do if type(k) ~= "number" or k > n or k < 1 then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local key = type(k) == "string" and string.format("[%q]", k) or "[" .. k .. "]"
      lines[#lines + 1] = pad .. key .. " = " .. ser(v[k], ind + 1) .. ","
    end
    lines[#lines + 1] = string.rep("\t", ind) .. "}"
    return table.concat(lines, "\n")
  end
  local f = assert(io.open(arg[2], "w"))
  f:write("\nSlopLevelerDB = " .. ser(SlopLevelerDB, 0) .. "\n")
  f:close()
end

local err = errorsPrinted()
check(not err, "no handler errors (" .. tostring(err) .. ")")

io.write(string.format("%d passed, %d failed\n", passed, failures))
os.exit(failures == 0 and 0 or 1)
