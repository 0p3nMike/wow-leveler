-- harness.lua -- run the REAL addon files under Lua 5.1 / luajit against a
-- fake Forever API, drive game events, and check what the addon does.
--
--   luajit test/harness.lua <path to ZugzugLeveler/> [SavedVariables dump | -] [camelot | mists | era]
--
-- The 3rd argument is the game type the TOC's [AllowLoadGameType ...] tags are
-- read for: camelot (Forever, the default, every test) or mists (Mists of
-- Pandaria Classic: the fake API is reshaped to 5.5.4's and only the Mists
-- tests run; they stop before the Forever ones), or era (Classic Era 1.15.9 on
-- a Hardcore realm, TOC tag vanilla: the API reshaped to wow-ui-source
-- classic_era's, only the Era tests run).
--
-- Same idea as ghoul's addon/test/harness.lua: in game every handler runs
-- inside pcall (Events.lua), so a typo never errors there -- it just quietly
-- does nothing. Here the bus's error print is turned into a failure.

local dir = assert(arg[1], "usage: harness.lua <addon dir> [dump | -] [camelot | mists | era]")
local GAME = arg[3] or "camelot"
local TAG = GAME == "era" and "vanilla" or GAME -- the TOC's name for the game
if arg[2] == "-" then arg[2] = nil end

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
function GetLocale() return "deDE" end
ERR_QUEST_ACCEPTED_S = "Quest accepted: %s"
function GetTime() return W.gt end
function UnitXP() return W.xp end
function UnitXPMax() return W.xpMax end
function UnitLevel() return W.level end
function GetXPExhaustion() return W.rested end
function UnitName(u) if u == nil or u == "player" then return "Tester", "Testsson" end return "Tester" end
function GetRealmName() return "Realm" end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitRace() return "Human", "Human", 1 end
function UnitSex() return 3 end
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
W.settings = {}
Settings = {
  VarType = { Boolean = "boolean", Number = "number", String = "string" },
  RegisterVerticalLayoutCategory = function(name) return { name = name, GetID = function() return 77 end } end,
  RegisterProxySetting = function(_, key, _, label, _, get, set)
    local s = { key = key, label = label, get = get, set = set }
    W.settings[key] = s
    return s
  end,
  CreateCheckbox = function() end,
  CreateDropdown = function(_, setting, options) setting.options = options end,
  CreateControlTextContainer = function()
    local d = {}
    return { Add = function(_, v, l) d[#d + 1] = { value = v, label = l } end, GetData = function() return d end }
  end,
  RegisterAddOnCategory = function(c) W.addonCategory = c end,
  OpenToCategory = function(id) W.openedCategory = id end,
}
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
  GetInfo = function(i) local q = logList()[i]; return q and { questID = q, isHeader = false, title = W.log[q].title, level = 5 } end,
  GetQuestObjectives = function(q) return W.log[q] and W.log[q].objs or {} end,
  GetQuestsOnMap = function(map) return (W.poi or {})[map] or {} end,
  GetNextWaypoint = function(q) local w = (W.wp or {})[q]; if w then return w[1], w[2], w[3] end end,
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

-- ------------------------------------------- Mists of Pandaria Classic API
-- The same fake world through 5.5.4's API (Ketho's classic GlobalAPI.lua and
-- Gethe/wow-ui-source branch classic): the old quest log globals instead of
-- most of C_QuestLog, no C_QuestLine / C_TooltipInfo / C_PaperDollInfo /
-- C_TradeSkillUI / C_SkillInfo / C_Minimap, no user waypoints.
if GAME == "mists" or GAME == "era" then
  local HEADER = "Twilight Highlands"
  local function row(i) if i == 1 then return nil end return logList()[i - 1] end -- row 1 is a zone header
  C_QuestLog = {
    IsOnQuest = C_QuestLog.IsOnQuest, IsQuestFlaggedCompleted = C_QuestLog.IsQuestFlaggedCompleted,
    GetQuestObjectives = C_QuestLog.GetQuestObjectives, GetQuestsOnMap = C_QuestLog.GetQuestsOnMap,
    GetQuestInfo = function(q) return (W.log[q] and W.log[q].title) or (W.names or {})[q] end,
  }
  function GetNumQuestLogEntries() return #logList() + 1 end
  -- title, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID (Cata QuestLogFrame.lua:232)
  function GetQuestLogTitle(i)
    if i == 1 then return HEADER, 0, nil, true, false, nil, 0, 0 end
    local q = row(i)
    if q then return W.log[q].title, 84, nil, false, false, W.log[q].complete and 1 or nil, 0, q end
  end
  function IsQuestComplete(q) return W.log[q] ~= nil and W.log[q].complete end
  function GetQuestLogIndexByID(q) for i, x in ipairs(logList()) do if x == q then return i + 1 end end return 0 end
  function GetQuestsCompleted() local t = {} for q in pairs(W.turnedIn) do t[q] = true end return t end
  W.sel = 0
  function GetQuestLogSelection() return W.sel end
  function SelectQuestLogEntry(i) W.sel = i end
  function GetQuestLogQuestText(i) assert(i == nil, "Mists' GetQuestLogQuestText takes no index"); local q = row(W.sel); return q and ("about " .. q), q and ("do " .. q) end
  C_QuestLine, C_TooltipInfo, C_PaperDollInfo, C_TradeSkillUI, C_SkillInfo, C_Minimap = nil, nil, nil, nil, nil, nil
  C_GameRules = { IsHardcoreActive = function() return false end }
  C_SuperTrack = {}
  C_Map.CanSetUserWaypointOnMap, C_Map.SetUserWaypoint, C_Map.GetUserWaypoint, C_Map.ClearUserWaypoint = nil, nil, nil, nil
end

-- ------------------------------------------------------- Classic Era API
-- 1.15.9 (wow-ui-source classic_era, Blizzard_APIDocumentationGenerated): the
-- same old quest log globals as Mists, but no IsQuestComplete /
-- GetQuestsCompleted proven, no GetTaxiMapID; QUEST_ACCEPTED is (questIndex,
-- questId); Era's project constants; a Hardcore realm (W.hc).
if GAME == "era" then
  IsQuestComplete, GetQuestsCompleted = nil, nil
  WOW_PROJECT_CLASSIC, WOW_PROJECT_ID = 2, 2
  W.hc = true
  C_GameRules = { IsHardcoreActive = function() return W.hc end }
  C_PlayerInfo = { IsSelfFoundActive = function() return false end }
  W.prof = 0
  function debugprofilestop() return W.prof end
end

-- ------------------------------------------------------------ load addon
local ns = {}
local toc = assert(io.open(dir .. "/ZugzugLeveler.toc"))
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
  chunk("ZugzugLeveler", ns)
end
for line in toc:lines() do
  line = line:gsub("\r", "")
  local file, games = line:match("^(.-)%s*%[AllowLoadGameType%s+([^%]]*)%]%s*$")
  local wanted = not games
  for g in (games or ""):gmatch("[^,%s]+") do if g == TAG then wanted = true end end
  if line ~= "" and not line:match("^#") and wanted then load(file or line) end
end
toc:close()
-- The real quest data (AllTheThings') knows quest numbers these tests make up
-- (401, 601 ...) as real Forever quests: the tests run with none, and the
-- quest data tests bring their own (and check a few real facts).
local REAL_QUESTDB = ns.QuestDB
ns.QuestDB = {}

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
local function accept(q, title)
  W.log[q] = { complete = false, title = title or ("Q" .. q) }
  -- Era's QUEST_ACCEPTED is (questIndex, questId); Forever's (questId)
  if GAME == "era" then fire("QUEST_ACCEPTED", 7, q) else fire("QUEST_ACCEPTED", q) end
  fire("QUEST_LOG_UPDATE")
end
local function finishObj(q) W.log[q].complete = true; fire("QUEST_LOG_UPDATE") end
local function turnin(q, xp)
  W.log[q] = nil; W.turnedIn[q] = true
  fire("QUEST_TURNED_IN", q, xp, 50); fire("QUEST_REMOVED", q)
  W.xp = W.xp + xp; fire("PLAYER_XP_UPDATE", "player"); fire("QUEST_LOG_UPDATE")
end

-- ================================================================ tests

-- load
fire("ADDON_LOADED", "ZugzugLeveler")
fire("PLAYER_ENTERING_WORLD")
check(ZugzugLevelerDB and ZugzugLevelerCharDB, "SavedVariables tables created")
check(SlashCmdList.ZUGZUGLEVELER, "slash command registered")
check(ZugzugLevelerCharDB.char and ZugzugLevelerCharDB.char.name == "Tester" and ZugzugLevelerCharDB.char.surname == "Testsson", "first name and surname saved")
check(ZugzugLevelerDB.chatStrings and ZugzugLevelerDB.chatStrings.s.ERR_QUEST_ACCEPTED_S == "Quest accepted: %s" and ZugzugLevelerDB.chatStrings.locale == "deDE",
  "the client's own chat strings are saved for the companion")
local zug = SlashCmdList.ZUGZUGLEVELER

local function finish()
  local err = errorsPrinted()
  check(not err, "no handler errors (" .. tostring(err) .. ")")
  io.write(string.format("%d passed, %d failed\n", passed, failures))
  os.exit(failures == 0 and 0 or 1)
end

-- ======================================== Mists of Pandaria Classic (mists)
if GAME == "mists" then
  local C = ns.C
  local n = 0
  for _ in pairs(ns.QuestDBMists or {}) do n = n + 1 end
  check(n > 10000, "Mists quest data loaded (" .. n .. " quests), not Forever's")
  local names = {}
  for _, r in ipairs(ns.Route.List()) do if not ns.Route.Get(r.name).dynamic then names[#names + 1] = r.name end end
  check(#names == 0, "no Forever routes on Mists, only the self-building ones (quest log, farm): " .. table.concat(names, ","))
  check(ns.TalentData == nil and ns.ProfData == nil, "Forever's talent and profession plans are not loaded")
  check(ZugzugLevelerCharDB.offeredRoute and not ZugzugLevelerDB.goalAsked, "first run: quest log mode offered, no guide goal asked")

  -- What happened in the real Mists client (2026-10-18): the TOC's
  -- [AllowLoadGameType camelot] lines loaded anyway. With every Forever file
  -- loaded, the addon must still use none of it.
  for _, f in ipairs({ "data/Quests.lua", "data/Talents.lua", "data/Danger.lua", "data/Professions.lua", "routes/rxp/routes.xml" }) do load(f) end
  names = {}
  for _, r in ipairs(ns.Route.List()) do if not ns.Route.Get(r.name).dynamic then names[#names + 1] = r.name end end
  check(#names == 0, "Forever's route files loaded on Mists register nothing (" .. #names .. " routes)")
  check(ns.QInfo.db() == ns.QuestDBMists and ns.QuestDB ~= ns.QuestDBMists, "Mists reads its own quest data with Forever's loaded too")
  check(next(ns.Talents.guides()) == nil, "no Forever talent guide on Mists")
  -- a character a Forever route was given before this: offered quest log mode again
  ZugzugLevelerCharDB.route, ZugzugLevelerCharDB.offeredRoute = "RXP Undead Mage", true
  fire("PLAYER_ENTERING_WORLD")
  check(ZugzugLevelerCharDB.route == nil or ZugzugLevelerCharDB.route == ns.QuestLog.NAME, "a route that is not here is dropped")
  check(ZugzugLevelerCharDB.offeredRoute == true, "and quest log mode is offered again")

  -- the quest log through the old globals
  W.level, W.faction, W.map, W.x, W.y = 84, "Horde", 241, 0.5, 0.5
  accept(201, "Fire in the Skies"); accept(202, "Bird Down"); finishObj(202)
  check(table.concat(C.questLogIDs(), ",") == "201,202", "log quest IDs from GetQuestLogTitle, the header skipped")
  check(C.isComplete(202) and not C.isComplete(201), "complete from IsQuestComplete")
  check(C.questTitle(201) == "Fire in the Skies", "title from the log row (GetQuestLogIndexByID)")
  W.names = { [999] = "Not In Log" }
  check(C.questTitle(999) == "Not In Log", "title of a quest not in the log from C_QuestLog.GetQuestInfo")
  W.turnedIn[300] = true
  local set = C.completedSet()
  check(set and set[300] and not set[201], "turned-in quests from GetQuestsCompleted")
  W.sel = 1
  fire("QUEST_LOG_UPDATE")
  local log = ZugzugLevelerCharDB.questLog
  check(log and #log == 2 and log[1].zone == "Twilight Highlands" and log[1].level == 84 and log[2].done == true,
    "the page's quest log: zone from the header row, level, done")
  check(log and log[1].desc == "about 201" and log[2].ask == "do 202", "each quest's own words, read by selecting its row")
  check(W.sel == 1, "the quest log's selection is put back")

  -- quest log mode: quest givers from the data (no C_QuestLine)
  zug("questlog")
  local acc, ok = 0, true
  for _, s in ipairs(ns.QuestLog.collect()) do
    if s.act == "accept" then
      acc = acc + 1
      if s.map ~= 241 or ns.QInfo.blocked(s.q) or not s.title then ok = false end
    end
  end
  check(acc > 0 and ok, "quest givers on Twilight Highlands from the quest data, all takeable now (" .. acc .. ")")
  local levels = { [1] = { 1, 10 }, [461] = { 1, 5 }, [201] = { 80, 81 } } -- Durotar, Valley of Trials, Kelp'thar Forest
  C_Map.GetMapLevels = function(m) local l = levels[m]; if l then return l[1], l[2] end end
  -- Hellfire Peninsula (map 100), Michael's case, 2026-10-18, with the real Mists data:
  -- "Report to Nazgrel" (10875) is a breadcrumb to 10876 (nextQuests); "Weaken the
  -- Ramparts" (9572) is a Hellfire Ramparts dungeon quest (ATT: Instances only)
  do
    local oldMap, oldLvl, oldTurned = W.map, W.level, W.turnedIn
    W.map, W.level = 100, 60
    W.turnedIn = { [10838] = true, [10124] = true }
    local function offered()
      local t = {}
      for _, s in ipairs(ns.QuestLog.collect()) do if s.act == "accept" then t[s.q] = true end end
      return t
    end
    local before = offered()
    check(before[10875], "the breadcrumb is offered while its follow-up is not done")
    W.turnedIn[10876] = true
    local after = offered()
    check(not after[10875] and ns.QInfo.blocked(10875) and ns.QInfo.blocked(10875).why == "past",
      "a breadcrumb whose follow-up you did is not offered (" .. tostring(ns.QInfo.say(ns.QInfo.blocked(10875))) .. ")")
    check(not after[9572], "a dungeon quest is not offered on your own")
    IsInGroup = function() return true end
    check(offered()[9572], "in a group it is")
    IsInGroup = nil
    W.log[9572] = { complete = false, title = "Weaken the Ramparts", objs = {} }
    W.poi = { [100] = { { questID = 9572, x = 0.47, y = 0.52 } } }
    local into = false
    for _, s in ipairs(ns.QuestLog.collect()) do if s.q == 9572 then into = true end end
    check(not into and ns.QuestLog.dungeon[1] == 9572, "a dungeon quest in your log: not routed into the dungeon on your own, listed instead")
    W.log[9572], W.poi = nil, nil
    W.map, W.level, W.turnedIn = oldMap, oldLvl, oldTurned
  end
  W.map = 1
  local grey = 0
  for _, s in ipairs(ns.QuestLog.collect()) do if s.act == "accept" then grey = grey + 1 end end
  check(grey == 0, "no quest givers in a zone you have outlevelled (" .. grey .. ")")
  W.map = 241

  -- gear: GetInventorySlotInfo, GetItemStats, a hidden tooltip read back
  local slotIDs = { HeadSlot = 1, MainHandSlot = 16 }
  function GetInventorySlotInfo(name) return slotIDs[name] or 99, "", false end
  function GetInventoryItemLink(_, slot) if slot == 16 then return "|Hitem:2::|h" end end
  function GetInventoryItemDurability() return 30, 35 end
  function GetItemStats() return { ITEM_MOD_INTELLECT_SHORT = 40 } end
  C_Item.GetItemInfoInstant = function(link) return tonumber(tostring(link):match("item:(%d+)")) end
  local make = CreateFrame
  function CreateFrame(kind, name, ...)
    local f = make(kind, name, ...)
    if kind == "GameTooltip" then
      local rows = {}
      local function fs(t) return { GetText = function() return t end, GetTextColor = function() return 1, 1, 1 end, IsShown = function() return t ~= nil end } end
      rawset(f, "SetHyperlink", function() rows = { { "Frostfire Staff" }, { "Two-Hand", "Staff" } } end)
      rawset(f, "NumLines", function() for i, r in ipairs(rows) do _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i] = fs(r[1]), fs(r[2]) end return #rows end)
    end
    return f
  end
  -- transmog: the main hand wears another staff's look
  C_Transmog = { GetSlotVisualInfo = function(loc)
    assert(loc.type == 0 and loc.modification == 0, "appearance, main")
    if loc.slotID == 16 then return { baseSourceID = 11, appliedSourceID = 77, isHideVisual = false } end
    return { baseSourceID = 12, appliedSourceID = 0, isHideVisual = false }
  end }
  C_TransmogCollection = { GetSourceInfo = function(src) if src == 77 then return { itemID = 5000, name = "Staff of Looks" } end end }
  fire("PLAYER_EQUIPMENT_CHANGED")
  local mh = ZugzugLevelerCharDB.gear and ZugzugLevelerCharDB.gear.slots.MainHand
  check(mh and mh.tmog and mh.tmog.id == 5000 and mh.tmog.name == "Staff of Looks", "a transmogged slot saves the look it wears")
  -- outfits (C_TransmogOutfitInfo), read when the transmog window opens
  C_Transmog.IsAtTransmogNPC = function() return true end
  C_TransmogOutfitInfo = {
    GetTransmogOutfitSlotFromInventorySlot = function(inv) return ({ [0] = 0, [15] = 12 })[inv] end, -- head, main hand
    GetEquippedSlotOptionFromTransmogSlot = function(ts) return ts == 12 and 2 or 0 end,
    GetViewedOutfitSlotInfo = function(ts, kind, opt)
      assert(kind == 0, "appearance")
      if ts == 0 then return { displayType = 1, transmogID = 88 } end
      if ts == 12 and opt == 2 then return { displayType = 3, transmogID = 0 } end
    end,
    GetActiveOutfitID = function() return 1 end, GetCurrentlyViewedOutfitID = function() return 1 end,
  }
  C_TransmogCollection.GetSourceItemID = function(src) return src == 88 and 6000 or nil end
  fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5) -- a merchant: not read
  check(ZugzugLevelerCharDB.tmog == nil, "another interaction window does not read the transmog")
  fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 24) -- the Transmogrifier, Mists' outfit window
  local tm = ZugzugLevelerCharDB.tmog
  check(tm and tm.slots.Head and tm.slots.Head.id == 6000 and tm.slots.MainHand and tm.slots.MainHand.hidden,
    "at the transmogrifier: each slot's outfit look saved (an item, or hidden)")
  zug("tmog")
  check(W.printed[#W.printed]:find("MainHand", 1, true) or W.printed[#W.printed]:find("Ranged", 1, true), "/zug tmog reports each slot")
  C_TransmogOutfitInfo = nil
  check(mh and mh.stats.ITEM_MOD_INTELLECT_SHORT == 40 and mh.dur == 30, "equipped item by slot name, stats from GetItemStats")
  check(mh and #mh.tt == 2 and mh.tt[2] == "ffffff\tTwo-Hand\tffffff\tStaff", "tooltip read from a hidden GameTooltip")

  -- spec names when the spec call answers without them (Mists at login)
  C_SpecializationInfo = {
    GetSpecialization = function() return 3 end,
    GetNumSpecializationsForClassID = function() return 3 end,
    GetSpecializationInfo = function(i) return 61 + i end, -- no name yet
  }
  function GetSpecializationInfoForClassID(_, i) return 61 + i, ({ "Arcane", "Fire", "Frost" })[i], "", 0, "DAMAGER" end
  fire("PLAYER_EQUIPMENT_CHANGED")
  local sp = ZugzugLevelerCharDB.gear and ZugzugLevelerCharDB.gear.spec
  check(sp and sp.cur == 3 and sp.trees[3].name == "Frost" and sp.trees[3].id == 64, "spec names from GetSpecializationInfoForClassID when the spec call has none")
  C_SpecializationInfo, GetSpecializationInfoForClassID = nil, nil

  -- talents: wowsims' Frost build (311122) against the tiers picked; level 62, the 60 tier open
  do
    W.level = 62
    C_SpecializationInfo = { GetSpecialization = function() return 3 end, GetActiveSpecGroup = function() return 1 end,
      GetNumSpecializationsForClassID = function() return 3 end,
      GetSpecializationInfo = function(i) return 61 + i, ({ "Arcane", "Fire", "Frost" })[i] end }
    local picked = { 3, 1, 1, 0, 0, 0 }
    function GetTalentTierInfo(tier) local lv = ({ 15, 30, 45, 60, 75, 90 })[tier]; return W.level >= lv, picked[tier], lv end
    function GetNumGlyphSockets() return 6 end
    function GetGlyphSocketInfo(i) if i == 1 then return true, 1, 1, 56377 end return true, 1, 1, nil end -- Splitting Ice slotted
    UnitClass = function() return "Mage", "MAGE", 8 end
    local list, b = ns.Talents.pending()
    check(b and b.spec == "Frost" and b.name == "Default" and #list == 1 and list[1].name == "Greater Invisibility" and list[1].lvl == 60,
      "Mists talents: the Frost build's pick for the open level-60 tier (" .. tostring(list[1] and list[1].name) .. ")")
    check((ns.Talents.line() or ""):find("Greater Invisibility", 1, true), "the window says which talent to pick")
    local miss = ns.Talents.mistsGlyphs(b)
    local names = {}
    for _, g in ipairs(miss) do names[g.name] = true end
    check(not names["Glyph of Splitting Ice"] and names["Glyph of Icy Veins"], "glyphs you lack from the build (Splitting Ice slotted, Icy Veins not)")
    zug("talents"); zug("talents list")
    fire("PLAYER_EQUIPMENT_CHANGED")
    local sp = ZugzugLevelerCharDB.gear.spec
    check(sp.tiers and sp.tiers[1] == 3 and sp.tiers[4] == 0 and sp.glyphs[1] == 56377, "the page gets your tier picks and glyphs")
    -- ratings: the client's CR_* numbers, rating and percent as the character frame works them out
    CR_HIT_SPELL, CR_CRIT_SPELL, CR_HASTE_SPELL, CR_MASTERY = 8, 11, 20, 26
    function GetCombatRating(cr) return ({ [8] = 43, [11] = 180, [20] = 86, [26] = 120 })[cr] or 0 end
    function GetCombatRatingBonus(cr) return ({ [8] = 4.98 })[cr] or 0 end
    function GetSpellHitModifier() return 1 end
    function GetSpellCritChance(school) return school == 5 and 14.2 or 12 end
    function UnitSpellHaste() return 7.97 end
    function GetMasteryEffect() return 19.6 end
    fire("PLAYER_EQUIPMENT_CHANGED")
    local r = ZugzugLevelerCharDB.gear.stats.r
    check(r and r.hit[1] == 43 and math.abs(r.hit[2] - 5.98) < 1e-9 and r.crit[2] == 14.2 and r.haste[2] == 7.97 and r.mastery[1] == 120,
      "ratings and percentages saved (spell hit = rating bonus + modifier, best school's crit)")
    CR_HIT_SPELL, CR_CRIT_SPELL, CR_HASTE_SPELL, CR_MASTERY = nil, nil, nil, nil
    GetCombatRating, GetCombatRatingBonus, GetSpellHitModifier, GetSpellCritChance, UnitSpellHaste, GetMasteryEffect = nil, nil, nil, nil, nil, nil
    C_SpecializationInfo, GetTalentTierInfo, GetNumGlyphSockets, GetGlyphSocketInfo = nil, nil, nil, nil
    UnitClass = function() return "Warrior", "WARRIOR", 1 end
  end

  -- reward items of quests you can take, looked up in the game (one answers later)
  do
    ns.QuestDBMists[777001] = { at = { 100, 0.5, 0.5 }, rw = { 31717, 99999 } }
    ZugzugLevelerCharDB.avail = { 777001 }
    local cachedNow, oldInfo, oldEquip = {}, C_Item.GetItemInfo, C_Item.IsEquippableItem
    C_Item.GetItemInfo = function(x)
      local id = tonumber(x) or tonumber(tostring(x):match("item:(%d+)"))
      if not cachedNow[id] then return nil end
      return id == 31717 and "Fel-Tooth Robe" or "Bandage", "|Hitem:" .. id .. "::|h", 2, 115, 60, "Armor", "Cloth", 1, "INVTYPE_ROBE", 0, 500, 4, 1, 1
    end
    C_Item.IsEquippableItem = function(link) return tostring(link):find("31717") ~= nil end
    ns.Export.lookupRewards()
    check(not (ZugzugLevelerDB.items or {})[31717], "a reward the client does not have yet waits for the server")
    cachedNow[31717], cachedNow[99999] = true, true
    fire("GET_ITEM_INFO_RECEIVED", 31717, true)
    fire("GET_ITEM_INFO_RECEIVED", 99999, true)
    local got = (ZugzugLevelerDB.items or {})[31717]
    check(got and got.name == "Fel-Tooth Robe" and got.req == 60 and not ZugzugLevelerDB.items[99999],
      "the server's answer is remembered with the game's stats and required level; non-gear is not")
    C_Item.GetItemInfo, C_Item.IsEquippableItem = oldInfo, oldEquip
    ns.QuestDBMists[777001], ZugzugLevelerCharDB.avail = nil, nil
  end

  -- skills and the trade skill window, old style
  local lines = { { "Weapon Skills", true }, { "Staves", false, false, 400, 0, 0, 450 } }
  function GetNumSkillLines() return #lines end
  function GetSkillLineInfo(i) return unpack(lines[i]) end
  fire("PLAYER_EQUIPMENT_CHANGED")
  local sk = ZugzugLevelerCharDB.gear and ZugzugLevelerCharDB.gear.skills
  check(sk and #sk == 1 and sk[1].name == "Staves" and sk[1].rank == 400 and sk[1].max == 450 and sk[1].head == "Weapon Skills", "skills from GetSkillLineInfo")
  local recipes = { { "Tailoring", "header" }, { "Bolt of Embersilk", "optimal", 3 }, { "Spare", "trivial", 9 }, { "Cloak", "medium", 1 } }
  function GetNumTradeSkills() return #recipes end
  function GetTradeSkillInfo(i) return unpack(recipes[i]) end
  function GetTradeSkillLine() return "Tailoring", 437, 450 end
  function GetTradeSkillNumReagents(i) return i == 2 and 1 or 0 end
  function GetTradeSkillReagentInfo(_, r) if r == 1 then return "Embersilk Cloth", 0, 5, 12 end end
  function GetTradeSkillReagentItemLink() return "|Hitem:53010::|h" end
  function GetTradeSkillItemLink(i) return "|Hitem:" .. (53640 + i) .. "::|h" end
  ns.Prof.scanWindow()
  check(#ns.Prof.canSkill == 2 and ns.Prof.canSkill[1].name == "Bolt of Embersilk" and ns.Prof.canSkill[1].orange, "skill-up recipes from GetTradeSkillInfo")
  local pr = ZugzugLevelerCharDB.profRecipes and ZugzugLevelerCharDB.profRecipes.Tailoring
  check(pr and pr.rank == 437 and #pr.recipes == 2 and pr.recipes[1].mats[1].id == 53010 and pr.recipes[1].mats[1].need == 5 and pr.recipes[1].mats[1].have == 12,
    "the planner's recipes saved with materials, need and have (trivial ones left out)")
  ZugzugLevelerCharDB.profRecipes = nil
  fire("TRADE_SKILL_UPDATE") -- Mists fills the list on this event, after TRADE_SKILL_SHOW
  check(ZugzugLevelerCharDB.profRecipes and ZugzugLevelerCharDB.profRecipes.Tailoring, "recipes read on Mists' TRADE_SKILL_UPDATE")

  -- gathering: a node looted (its GUID a GameObject) is recorded where you stand; the same spot again counts up
  do
    W.map, W.x, W.y = 241, 0.40, 0.50
    local loot = { { "|Hitem:72092::|h", "Ghost Iron Ore", 3, "GameObject-0-1-0-0-209311-0000AAAA01" } }
    function GetNumLootItems() return #loot end
    function GetLootSlotInfo(s) return 0, loot[s][2], loot[s][3] end
    function GetLootSlotLink(s) return loot[s][1] end
    function GetLootSourceInfo(s) return loot[s][4], loot[s][3] end
    fire("LOOT_OPENED")
    loot[1][4] = "GameObject-0-1-0-0-209311-0000AAAA02"; W.x = 0.401
    fire("LOOT_OPENED")
    loot[1] = { "|Hitem:72234::|h", "Green Tea Leaf", 2, "GameObject-0-1-0-0-209349-0000BBBB01" }; W.x, W.y = 0.60, 0.20
    fire("LOOT_OPENED")
    local nodes = ZugzugLevelerDB.nodes and ZugzugLevelerDB.nodes[241]
    check(nodes and #nodes == 2 and nodes[1].n == 2 and nodes[1].items[72092].q == 6 and nodes[1].items[72092].name == "Ghost Iron Ore",
      "gathering nodes recorded per map, the same spot counted again")
    local before = ZugzugLevelerCharDB.route
    zug("farm ore")
    check(ZugzugLevelerCharDB.route == "Farm" and #ns.Engine.route().steps == 1 and ns.Engine.route().steps[1].text == "Gather ore", "/zug farm ore: a route through the ore nodes")
    zug("farm")
    check(#ns.Engine.route().steps == 2, "/zug farm: every node on the map")
    zug("farm off")
    check(ZugzugLevelerCharDB.route == before, "/zug farm off: back to " .. tostring(before))
    GetNumLootItems, GetLootSlotInfo, GetLootSlotLink, GetLootSourceInfo = nil, nil, nil, nil
  end

  zug("why"); zug("way 50 50"); tick(4)
  finish()
end

-- ============================================ Classic Era / Hardcore (era)
if GAME == "era" then
  local C, E = ns.C, ns.Engine
  check(C.game() == "era" and C.hardcoreRealm(), "Classic Era, a Hardcore realm")
  local n = 0
  for _ in pairs(ns.QuestDBEra or {}) do n = n + 1 end
  check(n > 3000, "Era quest data loaded (" .. n .. " quests)")
  check(ns.QInfo.db() == ns.QuestDBEra, "Era reads its own quest data")
  -- with Forever's and Mists' files loaded as well (a client ignoring a tag), none of them is used
  for _, f in ipairs({ "data/Quests.lua", "data/Quests_Mists.lua", "routes/rxp/routes.xml" }) do load(f) end
  check(ns.QInfo.db() == ns.QuestDBEra, "Era's quest data even with the others loaded")
  local names = {}
  for _, r in ipairs(ns.Route.List()) do names[r.name] = true end
  check(names["RXP Survival Human Warrior"] and names["RXP Era Human Warrior"], "both Era routes for a Human Warrior")
  check(not names["RXP Human Warrior"] and not names["RXP Survival Undead Mage"], "no Forever route, no other race's or class's")
  check(ns.Route.Get("RXP Survival Human Warrior").hardcore == true and not ns.Route.Get("RXP Era Human Warrior").hardcore,
    "the Survival route is marked hardcore, the speedrun not")
  local first, other = ns.Coach.routeFor()
  check(first == "RXP Survival Human Warrior" and other == "RXP Era Human Warrior", "Hardcore realm: Survival offered first")
  W.hc = false
  first, other = ns.Coach.routeFor()
  check(first == "RXP Era Human Warrior" and other == "RXP Survival Human Warrior", "a normal Era realm: the speedrun first")
  check(not E.hardcore(), "not hardcore off a Hardcore realm, on no route")
  zug("route use RXP Survival Human Warrior")
  check(E.hardcore(), "following RestedXP's hardcore guide counts as hardcore (RXP GuideWindow.lua)")
  W.hc = true

  -- shared classic data: talents (Survival builds), danger list, profession plan
  W.level = 12
  local g = ns.Talents.guide()
  check(g and g.hc == true, "a Survival talent build on Hardcore (" .. tostring(g and g.name) .. ")")
  check(next(ns.Talents.guides()) ~= nil, "RestedXP's classic talent guides on Era")
  check(ns.DangerData and ns.DangerData.Alliance and #ns.DangerData.Alliance > 0, "the danger list loads on Era")

  -- QUEST_ACCEPTED (questIndex, questId): the route's first quest is taken by its ID
  local r = E.route()
  local s1 = r.steps[E.index()]
  check(s1 and s1.act == "accept", "the Survival route starts with an accept (" .. tostring(s1 and s1.act) .. ")")
  local i0 = E.index()
  ns.Rec.start("era")
  accept(s1.q, s1.title)
  check(E.index() > i0, "accepting it moves the route on, though Era sends the log row first")
  local got = {}
  for _, ev in ipairs(ns.Rec.active().ev or {}) do if ev.e == "accept" then got[#got + 1] = ev.q end end
  check(#got == 1 and got[1] == s1.q, "the run records the quest's ID, not its log row (" .. table.concat(got, ",") .. ")")
  ns.Rec.stop()

  -- the quest log through the old globals, complete from GetQuestLogTitle's 6th value
  check(not C.isComplete(s1.q), "not complete yet")
  finishObj(s1.q)
  check(C.isComplete(s1.q), "complete from GetQuestLogTitle (Era has no IsQuestComplete)")
  check(C.completedSet() == nil and not C.isTurnedIn(99999), "no completed-quest list on Era: asked one by one")

  -- a slow event on a Hardcore realm is noted once in /zug errors
  ns.On("SL_SLOWTEST", function() W.prof = W.prof + 150 end)
  ns.Fire("SL_SLOWTEST"); ns.Fire("SL_SLOWTEST")
  local slowNotes = 0
  for _, e in ipairs(ZugzugLevelerDB.errors or {}) do if e.err:find("slow: SL_SLOWTEST", 1, true) then slowNotes = slowNotes + 1 end end
  check(slowNotes == 1, "a handler over 100 ms on Hardcore is noted once (" .. slowNotes .. ")")
  ns.On("SL_FASTTEST", function() W.prof = W.prof + 5 end)
  ns.Fire("SL_FASTTEST")
  check(not ns.slowEvents().SL_FASTTEST, "a quick one is not")

  -- the snapshot tells the page the game and that this character plays hardcore
  ns.Export.snapshot()
  local ch = ZugzugLevelerCharDB.char
  check(ch and ch.game == "era" and ch.hcRealm == true and ch.hardcore == true, "char.game / hcRealm / hardcore saved for the page")


  -- bag sorting (Bags.lua): Era has no SortBags, so items are swapped one at a time
  do
    local CC, CI, gi = C_Container, C_Item.GetItemInfo, GetCursorInfo
    local B = {}   -- bag -> { family, slots = { [slot] = { id, count } or false } }
    local ITEMS = {
      [6948] = { "Hearthstone", 1, 1, 15 }, [100] = { "Broken Fang", 0, 1, 15 }, [2589] = { "Linen Cloth", 1, 5, 7 },
      [118] = { "Minor Healing Potion", 1, 5, 0 }, [200] = { "Gnoll Paw", 1, 1, 12 }, [300] = { "Rusty Sword", 2, 8, 2 },
      [2512] = { "Rough Arrow", 1, 5, 6 },
    }
    local cursor, locks, picks = nil, {}, 0
    local function put(bag, family, list) B[bag] = { family = family, slots = list } end
    put(0, 0, { { 100, 1 }, { 2589, 5 }, false, { 6948, 1 } })
    put(1, 0, { { 300, 1 }, { 118, 3 }, { 2589, 20 }, { 200, 1 } })
    put(2, 1, { { 2512, 200 }, false }) -- a quiver: never sorted
    C_Container = {
      GetContainerNumSlots = function(b) return B[b] and #B[b].slots or 0 end,
      GetContainerNumFreeSlots = function(b) return 0, B[b] and B[b].family or 0 end,
      GetContainerItemInfo = function(b, sl)
        local it = B[b] and B[b].slots[sl]
        if not it then return nil end
        local k = b .. ":" .. sl
        local locked = (locks[k] or 0) > 0
        if locked then locks[k] = locks[k] - 1 end
        return { itemID = it[1], stackCount = it[2], isLocked = locked, quality = ITEMS[it[1]][2], itemName = ITEMS[it[1]][1] }
      end,
      PickupContainerItem = function(b, sl)
        picks = picks + 1
        if not cursor then cursor = { b, sl }; return end
        local a, z = B[cursor[1]].slots, B[b].slots
        local from, to = a[cursor[2]], z[sl]
        if to and from and to[1] == from[1] then to[2] = to[2] + from[2]; a[cursor[2]] = false -- the same item: merged
        else a[cursor[2]], z[sl] = to or false, from end
        locks[cursor[1] .. ":" .. cursor[2]], locks[b .. ":" .. sl] = 1, 1
        cursor = nil
      end,
    }
    C_Item.GetItemInfo = function(id)
      local t = ITEMS[tonumber(id)]
      if t then return t[1], nil, t[2], t[3], nil, nil, nil, nil, nil, nil, 0, t[4] end
    end
    GetCursorInfo = function() return cursor and "item" or nil end
    local function ids(bag) local o = {} for _, it in ipairs(B[bag].slots) do o[#o + 1] = it and it[1] or "-" end return table.concat(o, " ") end
    local function total(id) local n = 0 for _, bg in pairs(B) do for _, it in ipairs(bg.slots) do if it and it[1] == id then n = n + it[2] end end end return n end
    W.printed = {}
    zug("sort")
    check(ids(0) .. " | " .. ids(1) == "6948 200 118 300 | 2589 2589 100 -",
      "sorted: hearthstone, quest item, potion, sword, cloth, junk last (" .. ids(0) .. " | " .. ids(1) .. ")")
    check(total(2589) == 25 and total(118) == 3, "no stack lost or merged")
    check(ids(2) == "2512 -", "the quiver keeps its arrows")
    check(not cursor and not ns.Bags.busy(), "nothing left on the cursor, the sort finished")
    local said = W.printed[#W.printed] or ""
    check(said:find("bags sorted %(%d+ moves%)"), "it says so: " .. said)
    local p0 = picks
    zug("sort")
    check(picks == p0 and (W.printed[#W.printed] or ""):find("0 moves"), "sorted bags: nothing moved")
    -- out of order again, then combat and a full cursor stop it before any move
    B[0].slots[1], B[1].slots[3] = B[1].slots[3], B[0].slots[1]
    W.combat = true; p0 = picks
    zug("sort")
    check(picks == p0 and (W.printed[#W.printed] or ""):find("not in combat"), "never in combat")
    W.combat = false
    cursor = { 0, 4 }; p0 = picks
    zug("sort")
    check(picks == p0 + 0 and (W.printed[#W.printed] or ""):find("cursor"), "never with something on the cursor")
    cursor = nil
    -- after looting, when turned on (quietly)
    zug("sort auto on")
    check(ns.Bags.auto() and ZugzugLevelerDB.autoSort == true, "/zug sort auto on")
    local n0 = #W.printed
    fire("LOOT_CLOSED")
    check(ids(0) == "6948 200 118 300" and #W.printed == n0, "sorted after looting, without a chat line")
    zug("sort auto off")
    check(W.settings.ZUGZUG_AUTOSORT ~= nil, "the option is in the panel")
    C_Container, C_Item.GetItemInfo, GetCursorInfo = CC, CI, gi
  end
  zug("why"); tick(4)
  finish()
end

-- XP math
check(ns.XP.delta({ xp = 900, max = 1000, lvl = 5 }, 50, 1200, 6) == 150, "level-up delta = rest of old bar + new")
check(ns.XP.delta({ xp = 100, max = 1000, lvl = 5 }, 160, 1000, 5) == 60, "plain delta")
check(ns.XP.fmtTime(3725) == "1h 02m", "fmtTime hours: " .. ns.XP.fmtTime(3725))

-- recorder: a short played run
zug("rec start test run")
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
zug("rec mark grind here")
zug("rec stop")
check(not ns.Rec.active(), "recording stopped")

local run = ZugzugLevelerDB.runs[1]
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
zug("route fromrun 1 Elwynn v1")
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
chunk("ZugzugLeveler", fakeNs)
check(reg and #reg.steps == #r.steps and reg.steps[1].q == 101 and reg.steps[1].title == "Wolves", "exported Lua re-registers the same route")

-- engine: follow the route on a fresh character state
ZugzugLevelerCharDB.route = nil
W.log, W.turnedIn = {}, {}
W.map, W.x, W.y = 1429, 0.40, 0.50
resetCalls()
zug("route use Elwynn v1")
check(ns.Engine.index() == 1, "starts at step 1")
check(hasCall("SetUserWaypoint", 1429) and hasCall("SuperTrack", true), "waypoint + arrow set for step 1")
accept(101, "Wolves")
check(ns.Engine.index() == 2, "accept advances to complete step, now " .. ns.Engine.index())
finishObj(101)
check(ns.Engine.index() == 3, "objectives complete advances to turn-in")
turnin(101, 300)
check(ns.Engine.index() == 4, "turn-in advances")
check(ZugzugLevelerCharDB.stats[1] ~= nil, "per-step stats recorded")
-- out of order: 102 already done before we reach its steps
W.turnedIn[102] = true; fire("QUEST_LOG_UPDATE")
check(ns.Engine.index() == 7, "already-turned-in quest skips its steps, now " .. ns.Engine.index())
zug("skip")
check(ns.Engine.index() == 8 and ns.Engine.step() == nil, "skip past last step finishes the route")
zug("back")
check(ns.Engine.index() == 7, "back goes one step back")

-- goto step by distance
ns.Route.Register({ name = "goto test", steps = {
  { act = "goto", map = 1429, x = 0.60, y = 0.50, r = 15 },
  { act = "note", text = "end" },
} })
zug("route use goto test")
W.map, W.x, W.y = 1429, 0.50, 0.50; tick(1)
check(ns.Engine.index() == 1, "100 yards away: goto not done")
W.x = 0.59; tick(1)
check(ns.Engine.index() == 2, "10 yards away: goto done")
W.x = 0.40; tick(1)
check(ns.Engine.index() == 2, "walking away does not undo a finished step")

-- assist, route mode
zug("route use Elwynn v1")
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
zug("release on"); fire("PLAYER_DEAD")
check(hasCall("RepopMe"), "auto-release when turned on")
zug("assist off"); resetCalls(); W.qf.id = 101; fire("QUEST_DETAIL")
check(not hasCall("AcceptQuest"), "assist off does nothing")

-- RXP-style steps: objectives, conditions, optional, world positions
zug("assist route")
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
zug("route use rxp test")
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
zug("route use goto test")
W.map, W.x, W.y, W.facing = 1429, 0.10, 0.10, 0
resetCalls()
SlashCmdList.ZUGZUGLEVELERWAY("50 40 the tree")
local t = ns.Way.current()
check(t and t.manual and t.map == 1429 and near(t.x, 0.5) and t.text == "the tree", "/way x y text sets a manual target on this map")
check(hasCall("SetUserWaypoint", 1429), "/way also sets the game's pin")
SlashCmdList.ZUGZUGLEVELERWAY("1430 20 30")
check(ns.Way.current().map == 1430, "/way <mapID> x y")
SlashCmdList.ZUGZUGLEVELERWAY("50 40")
W.x, W.y = 0.499, 0.40; A.update()
check(not ns.Way.current() or not ns.Way.current().manual, "arriving at a /way drops it, back to the route")
SlashCmdList.ZUGZUGLEVELERWAY("50 40"); SlashCmdList.ZUGZUGLEVELERWAY("clear")
check(not (ns.Way.current() or {}).manual, "/way clear")
zug("arrow off"); zug("arrow on"); zug("pin off"); zug("pin on")

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
zug("route use obj test")
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
zug("route use xp gate")
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
zug("route use offer test")
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
zug("route use swap test")
check(ns.Engine.index() == 1, "starts on the locked quest")
SlashCmdList.ZUGZUGLEVELERSWAP("")
check(ns.Engine.index() == 2, "/swap moves on to the next quest")
check(#ns.Engine.deferred() == 3, "its do + turn-in steps are set aside too")
accept(602, "Open")
W.log[602].complete = true; W.log[602].objs = { { finished = true } }; fire("QUEST_LOG_UPDATE")
check(ns.Engine.index() == 6, "route runs past the set-aside steps: now " .. ns.Engine.index())
check(table.concat(ns.UI.lines(), "\n"):find("3 set aside", 1, true), "window shows what is set aside")
W.level = 6; fire("PLAYER_LEVEL_UP", 6)
check(ns.Engine.index() == 1 and #ns.Engine.deferred() == 0, "level-up brings them back, from the first")
SlashCmdList.ZUGZUGLEVELERSWAP("")
accept(601, "Locked")
check(#ns.Engine.deferred() == 0, "accepting it anyway brings it back")
check(ns.Engine.index() == 3, "and the route continues at its do step: " .. ns.Engine.index())
SlashCmdList.ZUGZUGLEVELERSWAP(""); zug("swap back")
check(#ns.Engine.deferred() == 0, "/zug swap back")
-- a regenerated route file renumbers its steps: set-aside marks are dropped on load
check(ZugzugLevelerCharDB.routeSteps == 6, "route use records the step count")
SlashCmdList.ZUGZUGLEVELERSWAP("")
check(#ns.Engine.deferred() > 0, "something set aside before the reload")
ns.Fire("SL_READY")
check(#ns.Engine.deferred() > 0, "same route file: set-aside steps kept over a reload")
local swapSteps = ns.Route.Get("swap test").steps
table.insert(swapSteps, 1, { act = "note", text = "new first step" })
resetCalls(); ns.Fire("SL_READY")
check(#ns.Engine.deferred() == 0 and ZugzugLevelerCharDB.routeSteps == 7, "changed route file: set-aside steps cleared")
table.remove(swapSteps, 1); ZugzugLevelerCharDB.routeSteps = 6
-- ...and finished marks ahead of your place belonged to the old numbering
ZugzugLevelerCharDB.step, ZugzugLevelerCharDB.sticky, ZugzugLevelerCharDB.stepKey = 3, { [1] = true, [5] = true }, nil -- an older save: no step key
ZugzugLevelerCharDB.routeSteps = 99; ns.Fire("SL_READY")
local sk = ZugzugLevelerCharDB.sticky
check(sk[1] and sk[2] and not sk[5] and ZugzugLevelerCharDB.step == 3, "changed route file: done = everything before your place, nothing after")

-- a turn-in for a quest you do not have, its accept already passed: set aside, said why
ns.Route.Register({ name = "missing test", steps = {
  { act = "accept", q = 651, title = "Skipped", npc = "Quinn" },
  { act = "accept", q = 652, title = "Held" },
  { act = "turnin", q = 651, title = "Skipped" },
  { act = "accept", q = 653, title = "Follow-up", after = { 651 } },
  { act = "turnin", q = 652, title = "Held" },
  { act = "turnin", q = 653, title = "Follow-up" },
} })
W.log, W.turnedIn = {}, {}
local function printed(s, from)
  for k = from or 1, #W.printed do if W.printed[k]:find(s, 1, true) then return true end end
end
zug("route use missing test")
zug("step 2")
local mark = #W.printed
accept(652, "Held")
check(ns.Engine.index() == 5, "turn-in of a quest not in the log, and its follow-up's accept, are passed: now " .. ns.Engine.index())
check(ZugzugLevelerCharDB.deferred[3] == "missing", "and set aside as missing")
check(ZugzugLevelerCharDB.deferred[4] == "missing", "the follow-up the NPC will not offer is set aside too")
check(printed("not in your quest log", mark) and printed("from Quinn", mark), "chat says why, and who gives it")
check(printed("comes after Skipped", mark), "chat says what the follow-up waits on")
W.log[652].complete = true; turnin(652, 0)
check(ns.Engine.index() == 7 and ZugzugLevelerCharDB.deferred[6] == "missing", "the follow-up's turn-in is passed as well: " .. ns.Engine.index())
W.level = 6; fire("PLAYER_LEVEL_UP", 6)
check(ZugzugLevelerCharDB.deferred[3] == "missing" and ns.Engine.index() == 7, "a level-up does not bring a missing quest back")
accept(651, "Skipped")
check(ns.Engine.index() == 3 and not ZugzugLevelerCharDB.deferred[3] and not ZugzugLevelerCharDB.deferred[4],
  "picking the quest up brings its turn-in and follow-up back: " .. ns.Engine.index())
-- a follow-up whose lead-in you still have is offered as normal
check(not ns.Engine.missing(4, ns.Route.Get("missing test").steps), "follow-up of a quest in your log: not missing")
W.level = 5

-- a hearth is done once you are where the route goes next, so the optimizer
-- sees past it (in the city, the city's steps can be the closest)
ns.Route.Register({ name = "hearth test", steps = {
  { act = "accept", q = 711, map = 1429, cont = 0, wx = 100, wy = 100 },
  { act = "hearth", text = "Hearth to the city" },
  { act = "accept", q = 712, map = 1430, cont = 0, wx = 900, wy = 900 },
  { act = "accept", q = 713, map = 1430, cont = 0, wx = 910, wy = 900 },
  { act = "accept", q = 714, map = 1430, cont = 0, wx = 920, wy = 900 },
} })
W.log, W.turnedIn, W.map, W.x, W.y = {}, {}, 1429, 0.1, 0.1
zug("route use hearth test")
local hs = ns.Route.Get("hearth test").steps
check(not ns.Engine.isDone(2, hs), "hearth not done while still in the old zone")
local w = ns.Optimizer.window()
check(not w, "old zone: the optimizer stops at the hearth")
W.map = 1430
check(ns.Engine.isDone(2, hs), "in the zone the route continues in: hearth done")
w = ns.Optimizer.window()
check(w and #w.idx == 3 and w.idx[1] == 3, "and the optimizer sees the city's steps past it, not the one left behind")
mark = #W.printed
fire("QUEST_LOG_UPDATE")
check(ns.Engine.index() == 3 and ZugzugLevelerCharDB.deferred[1] == "left", "the step left in the old zone is set aside: " .. ns.Engine.index())
check(printed("you moved on from", mark), "chat names what was left behind")
W.level = 6; fire("PLAYER_LEVEL_UP", 6); W.level = 5
check(ZugzugLevelerCharDB.deferred[1] == "left", "a level-up does not bring it back")
zug("swap back")
check(not ZugzugLevelerCharDB.deferred[1], "/zug swap back does")
W.map = 1429

-- the coach: why the route wants this, a heads-up on a zone change, and a
-- question only when stuck or lost
local asked = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which, text) asked[#asked + 1] = { text = text, dlg = StaticPopupDialogs[which] } end
ns.Route.Register({ name = "coach test", sections = { { from = 1, name = "1-6 Startzone" }, { from = 4, name = "6-10 Nextzone" } }, steps = {
  { act = "accept", q = 801, title = "Near Quest", npc = "Ana", map = 1429, x = 0.5, y = 0.5 },
  { act = "complete", q = 801, obj = 1, map = 1429, x = 0.6, y = 0.5, hint = "Kill boars" },
  { act = "turnin", q = 801, title = "Near Quest", npc = "Ana", map = 1429, x = 0.5, y = 0.5 },
  { act = "accept", q = 802, title = "Far Quest", npc = "Bo", map = 1430, x = 0.3, y = 0.3 },
  { act = "complete", q = 802, obj = 1, map = 1430, x = 0.4, y = 0.3 },
} })
W.log, W.turnedIn, W.map, W.x, W.y, W.level, W.combat = {}, {}, 1429, 0.5, 0.5, 5, false
zug("route use coach test")
accept(801, "Near Quest"); accept(999, "Stray Quest")
W.log[801].objs = { { text = "Boar slain: 0/5", finished = false } }; fire("QUEST_LOG_UPDATE")
check(ns.Engine.index() == 2 and ns.Coach.state() == "questing", "coach: questing at the step")
local why = table.concat(ns.Coach.why(), "\n")
check(why:find("Still to do: Boar slain: 0/5", 1, true) and why:find("Kill boars", 1, true), "why: what is left, and the guide's hint")
check(why:find("Stray Quest", 1, true) and why:find("/zug questlog", 1, true), "why: names your quests the route skips, and what to do")
check(why:find('"1-6 Startzone", for levels 1-6; you are on pace', 1, true), "why: the guide part and your pace")
-- stuck: 12 minutes at the step with nothing moving
W.x = 0.6; ns.Coach.tick()
W.combat = true; W.gt = W.gt + ns.Coach.STUCK_SECS + 1; ns.Coach.tick()
check(#asked == 0, "never asks in combat")
W.combat = false; mark = #W.printed; ns.Coach.tick()
check(#asked == 1 and asked[1].text:find("has not moved for 12 minutes", 1, true), "stuck: asks whether to set the step aside")
check(printed("/swap does the same", mark), "the question is in chat too, with the command")
ns.Coach.tick()
check(#asked == 1, "asked once, not every tick")
mark = #W.printed
asked[1].dlg.OnAccept()
check(ZugzugLevelerCharDB.deferred[2] and ns.Engine.index() == 4, "yes: set aside, the route goes on: " .. ns.Engine.index())
check(printed("next stop is in Map1430", mark) and printed('RestedXP\'s "1-6 Startzone" is done there, and its next part, "6-10 Nextzone", starts in Map1430: Far Quest', mark),
  "heads-up: the next step is in another zone, and why")
check(ns.Coach.state() == "travelling" and table.concat(ns.UI.lines(), "\n"):find("in Map1430", 1, true), "window: where the step is")
why = table.concat(ns.Coach.why(), "\n")
check(why:find("It is in Map1430; you are in Map1429", 1, true) and why:find("1 level under it", 1, true), "why: the other zone, and you are under its levels")
-- away: minutes in a zone the route has nothing in
ns.Coach.tick()
check(#asked == 2 and asked[2].text:find("The route has nothing in Map1429", 1, true), "away: offers your own quests")
asked[2].dlg.OnAccept()
check(ZugzugLevelerCharDB.route == "Quest log" and ZugzugLevelerCharDB.parked and ZugzugLevelerCharDB.parked.step == 4, "quest log mode, your place in the guide kept")
-- back: where the guide goes on
W.map = 1430; ns.Coach.tick()
check(#asked == 3 and asked[3].text:find("Back to the guide?", 1, true), "back: offers the guide when you reach its zone")
asked[3].dlg.OnAccept()
check(ZugzugLevelerCharDB.route == "coach test" and ns.Engine.index() == 4 and ZugzugLevelerCharDB.deferred[2] and not ZugzugLevelerCharDB.parked,
  "resumed where you left it, set-aside steps and all")
W.gt = W.gt + 11; ns.Coach.tick()
check(ZugzugLevelerCharDB.coach and ZugzugLevelerCharDB.coach.state == "questing" and ZugzugLevelerCharDB.coach.why[1]:find("^Step 4 of 5"), "the why is saved for the companion page")
zug("route off"); zug("route resume")
check(ZugzugLevelerCharDB.route == "coach test" and ns.Engine.index() == 4, "/zug route off, then resume")
-- one question at a time: the next waits its turn, and comes when the first closes
local visible = true
StaticPopup_Visible = function() return visible end
local n0 = #asked
ns.Coach.ask("qa", "First?", "Yes", "No", function() end, "hint")
ns.Coach.ask("qa", "First again?", "Yes", "No", function() end, "hint")
ns.Coach.ask("qb", "Second?", "Yes", "No", function() end, "hint")
check(#asked == n0 and #ns.Coach.waiting == 2, "asked while another is up: they wait, once per key")
local done = false
ns.Coach.onIdle = function() done = true end
visible = false
asked[#asked].dlg.OnHide()
check(#asked == n0 + 1 and asked[#asked].text == "First?" and #ns.Coach.waiting == 1, "the popup closed: the first that waited comes up")
asked[#asked].dlg.OnHide(); asked[#asked].dlg.OnHide()
check(asked[#asked].text == "Second?" and done, "then the next, then the first-run wizard's last word")
check(ZugzugLevelerDB.wizardDone == true, "the first-run wizard ran once")
StaticPopup_Visible = nil
StaticPopupDialogs, StaticPopup_Show = nil, nil
W.map, W.combat = 1429, nil

-- the quest data: what AllTheThings records, read as its code reads it
check(REAL_QUESTDB[91921].sq[1] == 91920 and REAL_QUESTDB[91920].sq[1] == 430 and REAL_QUESTDB[430].sq[1] == 429,
  "real data: Return to Quinn (Again) needs Wild Eyes, which needs Return to Quinn, which needs Wild Hearts")
check(REAL_QUESTDB[6323].races[1] == 5 and REAL_QUESTDB[840].bc == 1 and REAL_QUESTDB[91920].r == 1,
  "real data: Ride to the Undercity is Undead only, Conscript of the Horde a breadcrumb, Wild Eyes Horde")
ns.QuestDB = {
  [900] = { lvl = 1, at = { 1429, 0.5, 0.5 } },
  [901] = { sq = { 900 }, lvl = 1, r = 2, at = { 1429, 0.5, 0.5 } },
  [902] = { r = 1 },
  [903] = { lvl = 8 },
  [904] = { sq = { 905 } }, [905] = { bc = 1 },
  [906] = { alt = { 907 } },
  [908] = { lvl = { 1, 4 } },
}
W.log, W.turnedIn, W.level, W.faction = {}, {}, 5, "Alliance"
local QI = ns.QInfo
local b = QI.blocked(901)
check(b and b.kind == "prereq" and b.need[1] == 900, "a quest whose lead-in you have not done: blocked, naming it")
check(QI.blocked(902).why == "faction" and QI.blocked(903).kind == "level" and QI.blocked(903).lvl == 8, "the other faction's quest; one above your level")
check(not QI.blocked(904), "a breadcrumb lead-in does not block")
W.turnedIn[907] = true
check(QI.blocked(906).why == "alt" and QI.blocked(908).why == "toohigh", "locked by the quest you did instead; too high a level for it")
check(not QI.blocked(4242), "a quest the data does not know is never blocked")
W.turnedIn[900] = true
check(not QI.blocked(901), "lead-in done: open")
W.turnedIn[900] = nil
-- in the route: set aside with the real reason, back when it opens
ns.Route.Register({ name = "qdb test", steps = {
  { act = "accept", q = 901, title = "Second", map = 1429, x = 0.5, y = 0.5 },
  { act = "accept", q = 903, title = "Higher", map = 1429, x = 0.5, y = 0.5 },
  { act = "turnin", q = 901, title = "Second", map = 1429, x = 0.5, y = 0.5 },
  { act = "note", text = "end" },
} })
mark = #W.printed
zug("route use qdb test")
check(ZugzugLevelerCharDB.deferred[1] == "missing" and ZugzugLevelerCharDB.deferred[2] == "level", "set aside: one needs a lead-in, one a level")
check(printed("because it needs quest 900 first", mark) and printed("it needs level 8 (you are 5). It comes back when you level up", mark), "chat says exactly why")
W.turnedIn[900] = true; fire("QUEST_TURNED_IN", 900)
check(not ZugzugLevelerCharDB.deferred[1] and ns.Engine.index() == 1, "turning in the lead-in brings it back: " .. ns.Engine.index())
W.level = 8; fire("PLAYER_LEVEL_UP", 8)
check(not ZugzugLevelerCharDB.deferred[2], "the level one comes back on level-up")
-- the route doing the lead-in first: not missing
W.turnedIn, W.level = {}, 5
ns.Route.Register({ name = "qdb order", steps = {
  { act = "accept", q = 900, title = "First" }, { act = "turnin", q = 900, title = "First" },
  { act = "accept", q = 901, title = "Second" },
} })
zug("route use qdb order")
check(not ns.Engine.missing(3, ns.Route.Get("qdb order").steps), "a lead-in the route does first does not block")
check(#QI.availableOn(1429) >= 1, "quests you can take on a map, from the data's quest givers")
ns.QuestDB, W.faction, W.level = {}, nil, 5

-- every race/class has a route; a route file for another one does not load
check(ns.Coach.routeFor() == "RXP Human Warrior", "the route offered to a Human Warrior: " .. tostring(ns.Coach.routeFor()))
check(ns.Route.Get("RXP Human Warrior") and not ns.Route.Get("RXP Undead Mage") and not ns.Route.Get("RXP Orc Warlock"),
  "only this character's route files are kept in memory")
check(ns.Route.Skip("Scourge", "MAGE") and not ns.Route.Skip("Human", "WARRIOR"), "Route.Skip by race file name and class")

-- route options from the page: a mage leaves cooking out
local R = ns.Route
check(R.category({ act = "train", text = "Train Cooking" }) == "cooking" and R.category({ act = "goto", text = "Create Linen Bandages until your skill is 40 or higher" }) == "firstaid"
  and R.category({ act = "train", text = "Train Staves" }) == "weapons" and R.category({ act = "train", text = "Train your class spells" }) == "classtrain"
  and R.category({ act = "accept", q = 1, title = "Cooking quest" }) == nil, "step kinds, from RestedXP's own wording; quests are not touched")
ns.RoutePrefs = { skip = { cooking = true } }
check(not ns.Engine.applies({ act = "train", text = "Train Cooking" }) and ns.Engine.applies({ act = "train", text = "Train First Aid" }),
  "a kind you left out is passed over, the rest stays")
ns.RoutePrefs = nil
-- the goal: fastest leveling leaves out cooking, first aid and crafting trainers
local cook, cls = { act = "train", text = "Train Cooking" }, { act = "train", text = "Train your class spells" }
ZugzugLevelerDB.goal, ZugzugLevelerDB.goalAt = nil, nil
check(not R.leftOut(cook), "no goal chosen: nothing left out")
zug("goal speed")
check(R.goal() == "speed" and R.leftOut(cook) and not R.leftOut(cls), "speed: cooking out, class training in")
ns.RoutePrefs = { goal = "complete", at = ZugzugLevelerDB.goalAt + 10 }
check(R.goal() == "complete" and not R.leftOut(cook), "a later choice on the page wins: completion keeps cooking")
ns.RoutePrefs = { goal = "complete", at = 1 }
check(R.goal() == "complete", "an older page choice does not undo a newer one")
ZugzugLevelerDB.goal = "speed"; ns.RoutePrefs = { skip = {}, custom = true }
check(not R.leftOut(cook), "step kinds picked on the page win over the goal's defaults")
ns.RoutePrefs, ZugzugLevelerDB.goal, ZugzugLevelerDB.goalAt = nil, nil, nil
-- what you are doing, read from the game
local oldNow = ns.Downtime.now
ns.Downtime.now = "afk"
check(ns.Coach.activity() == "afk" and ns.Coach.PAUSE.afk, "afk: seen, and the stuck clock waits")
ns.Downtime.now = "idle"; _G.MerchantFrame = { IsShown = function() return true end }
check(ns.Coach.activity() == "vendor", "at a vendor")
_G.MerchantFrame, ns.Downtime.now = nil, oldNow

-- a listed mob's NPC number, learned when you target it (for the page's loot list)
local oldGUID, oldName = UnitGUID, UnitName
UnitGUID = function(u) if u == "target" then return "Creature-0-4170-0-12-448-000012ABCD" end end
UnitName = function(u) if u == "target" then return "Hogger" end return oldName(u) end
fire("PLAYER_TARGET_CHANGED")
check(ZugzugLevelerDB.npcIds and ZugzugLevelerDB.npcIds.Hogger == 448, "targeting Hogger learns NPC 448")
UnitGUID = function(u) if u == "target" then return "Player-4170-0ABC" end end
UnitName = function(u) if u == "target" then return "Somebody" end return oldName(u) end
fire("PLAYER_TARGET_CHANGED")
check(not ZugzugLevelerDB.npcIds.Somebody, "players and unlisted creatures are not kept")
UnitGUID, UnitName = oldGUID, oldName

-- auction house prices: the whole house read in one go (C_AuctionHouse.ReplicateItems)
do
  local list = { -- index 0 first, as the replicate list counts
    [0] = { "Linen Cloth", 1, 20, 1, true, 5, nil, 0, 0, 400, 0, nil, nil, nil, nil, 0, 2589, true },
    [1] = { "Linen Cloth", 1, 10, 1, true, 5, nil, 0, 0, 150, 0, nil, nil, nil, nil, 0, 2589, true },
    [2] = { "Heavy Linen Bandage", 1, 5, 1, true, 5, nil, 0, 0, 500, 0, nil, nil, nil, nil, 0, 2581, true },
  }
  local asked = 0
  C_AuctionHouse = {
    ReplicateItems = function() asked = asked + 1 end,
    GetNumReplicateItems = function() return 3 end,
    GetReplicateItemInfo = function(i) local e = list[i]; if e then return unpack(e, 1, 18) end end,
  }
  _G.AuctionHouseFrame = { IsShown = function() return true end }
  mark = #W.printed
  zug("prices")
  fire("REPLICATE_ITEM_LIST_UPDATE")
  local pr = ns.Auction.prices()
  local linen = pr and pr.items[2589]
  check(asked == 1 and linen and linen.p == 15 and linen.n == 2 and linen.q == 30 and linen.name == "Linen Cloth",
    "lowest unit price, listings and quantity per item")
  check(pr.items[2581].p == 100 and pr.listings == 3, "every listing read, from index 0")
  zug("prices")
  check(asked == 1 and printed("one full auction house read every 15 minutes", mark), "a second read within 15 minutes waits")
  C_AuctionHouse, _G.AuctionHouseFrame = nil, nil
end

-- the 3D character in game, and the new name's commands
zug("model")
check(_G.ZugzugLevelerModel and _G.ZugzugLevelerModel:IsShown(), "/zug model shows your character in a model frame")
zug("model")
check(not _G.ZugzugLevelerModel:IsShown(), "and /zug model again hides it")
check(SLASH_ZUGZUGLEVELER1 == "/zug" and SLASH_ZUGZUGLEVELER2 == "/zugzug" and not SLASH_ZUGZUGLEVELER3, "/zug and /zugzug, and nothing else (no /lev)")

-- pause / resume: a detour of your own (walking to a flight path, waiting for a friend)
do
  ZugzugLevelerCharDB.paused = nil
  local sx = ns.XP.session()
  local start0, total0 = sx.start, sx.total
  local stepT0 = ZugzugLevelerCharDB.stepStart and ZugzugLevelerCharDB.stepStart.t
  local played0 = ZugzugLevelerCharDB.split and ZugzugLevelerCharDB.split.played
  local pb = _G.ZugzugLevelerPauseButton
  check(pb and pb.scripts.OnClick and pb.play and not pb.play.shown, "a pause button beside Sync, showing the bars")
  mark = #W.printed
  pb.scripts.OnClick(pb)
  check(ns.Pause.on() and printed("paused", mark) and pb.play.shown and not pb.bars[1].shown, "the button pauses, and turns into a play arrow")
  check(ns.Coach.activity() == "paused" and ns.Coach.PAUSE.paused, "the coach sees it and waits")
  W.xp = W.xp + 50; fire("PLAYER_XP_UPDATE", "player")
  check(sx.total == total0, "XP on a detour is not the route's rate")
  for _ = 1, 10 do W.gt = W.gt + 0.5; tick(1) end
  W.t = W.t + 5
  check(math.abs(ns.Pause.secs() - 5) < 0.01, "paused time counted: " .. ns.Pause.secs())
  check(not ZugzugLevelerCharDB.split or ZugzugLevelerCharDB.split.played == played0, "the splits clock stands still")
  check(ns.Downtime.now == "paused", "where-the-time-goes skips it")
  local first = ns.UI.lines()[1] or ""
  check(first:find("paused"), "the window says so: " .. first)
  local cur = ns.Way.current()
  check(not cur or cur.manual or ns.Arrow.resting(), "the arrow rests while following the route")
  local r1, a1, s1 = ns.Arrow.idlePose(0.3)
  local r2, a2, s2 = ns.Arrow.idlePose(2.0)
  local r3 = ns.Arrow.idlePose(7.8) -- in the sweep
  check(r1 ~= r2 and a1 ~= a2 and s1 ~= s2 and r3 >= 0 and r3 < 2 * math.pi and a1 > 0.4 and a1 <= 0.8, "the resting arrow drifts, breathes and sweeps")
  ns.Pause.set(true) -- already paused: nothing changes
  check(math.abs(ns.Pause.secs() - 5) < 0.01, "pausing twice keeps the clock")
  mark = #W.printed
  zug("resume")
  check(not ns.Pause.on() and printed("resumed after", mark), "/zug resume")
  check(sx.start == math.min(start0 + 5, W.t), "XP/hour does not count the pause")
  check(not stepT0 or ZugzugLevelerCharDB.stepStart.t == math.min(stepT0 + 5, W.t), "nor does the step's time")
  check(not ns.Arrow.resting(), "the arrow points again")
  zug("pause"); check(ns.Pause.on(), "/zug pause toggles on"); zug("pause"); check(not ns.Pause.on(), "and off")
  check(ZugzugLeveler_Pause and BINDING_NAME_ZUGZUGLEVELER_PAUSE, "a key binding for it")
end

-- error reports: a handler error is kept, /zug errors shows a report to copy
do
  ns.On("SL_TEST_BOOM", function() error("boom") end)
  ns.Fire("SL_TEST_BOOM")
  local e = ZugzugLevelerDB.errors and ZugzugLevelerDB.errors[#ZugzugLevelerDB.errors]
  check(e and e.event == "SL_TEST_BOOM" and e.err:find("boom"), "a handler error is kept")
  local shown
  local old = ns.UI.showText
  ns.UI.showText = function(title, text) shown = text end
  zug("errors")
  ns.UI.showText = old
  check(shown and shown:find("zugzug_leveler error report", 1, true) and shown:find("SL_TEST_BOOM", 1, true) and not shown:find("Tester", 1, true),
    "the report: version, client, the error, and no character name")
  zug("errors clear")
  check(not ZugzugLevelerDB.errors, "/zug errors clear")
  for k, p in ipairs(W.printed) do if p:find("error in SL_TEST_BOOM", 1, true) then W.printed[k] = "(expected test error)" end end
end

-- your look, read at a barber (C_BarberShop)
do
  C_BarberShop = { GetAvailableCustomizations = function() return {
    { id = 1, options = {
      { id = 10, name = "Skin Color", currentChoiceIndex = 2, choices = { { id = 100, name = "1" }, { id = 101, name = "2" } } },
      { id = 11, name = "Face", currentChoiceIndex = 1, choices = { { id = 110, name = "1" } } },
    } },
    { id = 2, spellShapeshiftFormID = 768, options = { { id = 20, currentChoiceIndex = 1, choices = { { id = 200 } } } } },
  } end }
  fire("BARBER_SHOP_OPEN")
  local look = ZugzugLevelerCharDB.look
  check(look and #look.options == 2 and look.options[1].o == 10 and look.options[1].c == 101 and look.options[2].c == 110,
    "a barber's chair: every feature's current choice saved (forms left out)")
  C_BarberShop = nil
end

-- loot you saw: per creature, each corpse once
do
  local slots = {
    { link = "|cff9d9d9d|Hitem:2589::|h[Linen Cloth]|h|r", q = 2, src = { "Creature-0-1-2-3-299-0000AAAA", 2 } },
    { link = nil, coin = true },
    { link = "|Hitem:4865::|h[Ruined Pelt]|h", q = 1, src = { "Creature-0-1-2-3-299-0000AAAA", 1 } },
  }
  GetNumLootItems = function() return #slots end
  GetLootSlotInfo = function(i) local s = slots[i]; return nil, s.link and s.link:match("%[(.-)%]"), s.q, nil, nil, nil, nil, nil, nil, s.coin end
  GetLootSlotLink = function(i) return slots[i].link end
  GetLootSourceInfo = function(i) local s = slots[i].src; if s then return s[1], s[2] end end
  local oldGUID, oldDead = UnitGUID, UnitIsDead
  UnitGUID = function(u) if u == "target" then return "Creature-0-1-2-3-299-0000AAAA" end end
  UnitIsDead = function() return true end
  fire("LOOT_OPENED")
  local wolf = ZugzugLevelerDB.loot and ZugzugLevelerDB.loot[299]
  check(wolf and wolf.n == 1 and wolf.items[2589].c == 1 and wolf.items[2589].q == 2 and wolf.items[4865].c == 1 and wolf.items[2589].name == "Linen Cloth", "a looted wolf: one corpse, what it dropped")
  fire("LOOT_OPENED")
  check(wolf.n == 1 and wolf.items[2589].q == 2, "the same corpse opened again adds nothing")
  slots[1].src[1] = "Creature-0-1-2-3-299-0000BBBB"; slots[3].src = nil
  UnitGUID = function() return nil end
  fire("LOOT_OPENED")
  check(wolf.n == 2 and wolf.items[2589].c == 2 and wolf.items[4865].c == 1, "a second wolf: two corpses, linen from both")
  GetNumLootItems, GetLootSlotInfo, GetLootSlotLink, GetLootSourceInfo, UnitGUID, UnitIsDead = nil, nil, nil, nil, oldGUID, oldDead
end

-- talents: RestedXP's guide for your class against what you have
do
  local have = { ["1:1:2"] = 2 }
  C_SpecializationInfo = { GetTalentInfo = function(q) return { rank = have[q.specializationIndex .. ":" .. q.tier .. ":" .. q.column] or 0, name = "Talent " .. q.tier .. q.column } end }
  local oldData = ns.TalentData
  ns.TalentData = { WARRIOR = {
    { name = "Arms (Survival) 10-30", min = 10, max = 30, hc = true, order = 1, picks = { { 10, 1, 1, 2, 1, "Deflection (Rank 1)" } } },
    { name = "Arms 10-30", min = 10, max = 30, hc = false, order = 4, picks = {
      { 10, 1, 1, 2, 1, "Deflection (Rank 1)" }, { 11, 1, 1, 2, 2, "Deflection (Rank 2)" }, { 12, 1, 1, 2, 3, "Deflection (Rank 3)" },
      { 13, 1, 2, 1, 1, "Improved Rend (Rank 1)" }, { 30, 1, 3, 1, 1, "Late (Rank 1)" } } },
  } }
  W.level = 13
  local list, g = ns.Talents.pending()
  check(g and g.name == "Arms 10-30", "not hardcore: the plain guide: " .. tostring(g and g.name))
  check(#list == 2 and list[1].rank == 3 and list[2].name == "Talent 21", "pending: what you lack up to your level, not later picks")
  check(ns.Talents.line():find("Talent 12 3", 1, true) and ns.Talents.line():find("+1 more", 1, true), "the window line")
  C_GameRules = { IsHardcoreActive = function() return true end, GetForeverExperiencePreset = function() return 1 end }
  check(select(2, ns.Talents.pending()).name == "Arms (Survival) 10-30", "a hardcore character gets the Survival guide")
  C_GameRules = { GetForeverExperiencePreset = function() return 1 end } -- Forever, not hardcore
  zug("talents Arms (Survival) 10-30")
  check(ZugzugLevelerCharDB.talentGuide == "Arms (Survival) 10-30" and select(2, ns.Talents.pending()).hc, "/zug talents <name> picks one")
  zug("talents auto"); check(not ZugzugLevelerCharDB.talentGuide, "/zug talents auto")
  have["1:1:2"], have["1:2:1"] = 3, 1
  check(#ns.Talents.pending() == 0 and not ns.Talents.line(), "on plan: nothing shown")
  ns.TalentData, C_SpecializationInfo, W.level = oldData, nil, 5
end

-- party play: your place on the route, shared with the group
do
  local sent = {}
  C_ChatInfo = { SendAddonMessage = function(p, m, ch) sent[#sent + 1] = { p, m, ch } end, RegisterAddonMessagePrefix = function() end }
  IsInGroup = function() return true end
  zug("route use coach test")
  ns.Party.send(true)
  local last = sent[#sent]
  check(last and last[1] == "ZUGZUG" and last[3] == "PARTY" and last[2]:find("^1|coach test|%d+|5|"), "your line goes to the party: " .. tostring(last and last[2]))
  local i = ns.Engine.index()
  fire("CHAT_MSG_ADDON", "ZUGZUG", ("1|coach test|%d|5|6|0|802|2|6"):format(i + 2), "PARTY", "Buddy-Realm")
  fire("CHAT_MSG_ADDON", "ZUGZUG", "1|coach test|1|5|6|0|0||", "PARTY", "Tester-Realm") -- yourself: ignored
  fire("CHAT_MSG_ADDON", "OTHER", "1|x|1|1|1|0|0||", "PARTY", "Stranger")
  local rows = table.concat(ns.Party.rows(), "\n")
  check(rows:find("Buddy", 1, true) and rows:find("2 steps ahead", 1, true) and rows:find("2/6", 1, true), "a party member: how far ahead, and their progress: " .. rows)
  check(not rows:find("Tester", 1, true) and not rows:find("Stranger", 1, true), "not yourself, not other addons")
  check(table.concat(ns.UI.lines(), "\n"):find("Buddy", 1, true), "they show in the window")
  check(not (ZugzugLevelerCharDB.party or ZugzugLevelerDB.mates), "names are not saved")
  zug("party off"); check(#ns.Party.rows() == 0, "/zug party off")
  zug("party on")
  W.gt = W.gt + 200
  check(#ns.Party.rows() == 0, "a party member gone quiet drops off")
  C_ChatInfo, IsInGroup = nil, nil
  zug("route off")
end

-- objective places for the quests in your log (AllTheThings' obj)
do
  local oldDB, oldLog = ns.QuestDB, ZugzugLevelerCharDB.questLog
  ns.QuestDB = { [901] = { obj = { { 1429, 0.30, 0.40, crs = { 299 } }, { crs = { 300 } } } }, [902] = { obj = { { 1429, 0.6, 0.6 } } } }
  ZugzugLevelerCharDB.questLog = { { q = 901, done = false }, { q = 902, done = true } }
  local objs = ns.MapPath.objectives()
  check(#objs == 1 and objs[1].q == 901 and math.abs(objs[1].wx - 300) < 1e-6, "objective places: unfinished quests, the ones with coordinates")
  ns.QuestDB, ZugzugLevelerCharDB.questLog = oldDB, oldLog
end

-- a regenerated route: your step is found again by what it is
do
  ns.Route.Register({ name = "rebase test", steps = { { act = "goto", text = "A", map = 1429, x = 0.1, y = 0.1 },
    { act = "goto", text = "B", map = 1429, x = 0.2, y = 0.2 }, { act = "goto", text = "C", map = 1429, x = 0.3, y = 0.3 } } })
  zug("route use rebase test"); zug("step 3")
  check(ZugzugLevelerCharDB.stepKey == "goto||C|", "the step you are on is remembered: " .. tostring(ZugzugLevelerCharDB.stepKey))
  ns.Route.Register({ name = "rebase test", steps = { { act = "goto", text = "A", map = 1429, x = 0.1, y = 0.1 },
    { act = "goto", text = "new", mode = "hc", map = 1429, x = 0.15, y = 0.15 },
    { act = "goto", text = "B", map = 1429, x = 0.2, y = 0.2 }, { act = "goto", text = "C", map = 1429, x = 0.3, y = 0.3 } } })
  ns.Engine.rebase(ZugzugLevelerCharDB, ns.Route.Get("rebase test"))
  check(ZugzugLevelerCharDB.step == 4 and ZugzugLevelerCharDB.sticky[3] and not ZugzugLevelerCharDB.sticky[4], "a step added before yours: still on C, now step 4")
  zug("route off")
end

-- the talking peon beside the window (Peon.lua)
do
  local pf = _G.ZugzugLevelerPeon
  check(pf and _G.ZugzugLevelerPeonModel and _G.ZugzugLevelerPeonSays, "the peon's portrait, model and speech panel")
  check(not pf:IsShown() and ns.Peon.last == nil, "off by default: hidden, and he said nothing")
  -- out of this version (Peon.ENABLED false, 2026-10-23): /zug peon cannot bring him
  check(ns.Peon.ENABLED == false, "the peon is out of the released addon")
  zug("peon on")
  check(not pf:IsShown() and ZugzugLevelerDB.peon ~= true, "/zug peon on does nothing while he is out")
  -- the rest tests him as he will be when he comes back
  ns.Peon.ENABLED = true
  zug("peon")
  check(pf:IsShown(), "/zug peon turns him on")
  local played = {}
  PlaySoundFile = function(path, channel) played[#played + 1] = { path, channel }; return true, #played end
  StopSound = function() end
  zug("pause"); zug("resume")
  check(ns.Peon.last == "Back to work!", "he says so when a pause ends: " .. tostring(ns.Peon.last))
  local last = played[#played]
  check(last and last[2] == "Dialog" and last[1] == "Interface\\AddOns\\ZugzugLeveler\\media\\voice\\" .. ns.PeonVoice["Back to work!"] .. ".ogg", "and out loud, his own clip on the Dialog channel")
  zug("pause"); check(ns.Peon.last == "Break. Me wait.", "and when it began"); zug("resume")
  local n = #played
  fire("PLAYER_LEVEL_UP", 17)
  check(ns.Peon.last == "Zug zug! Level 17!" and played[n + 1] and played[n + 1][1]:find(ns.PeonVoice["Zug zug! Level up!"], 1, true), "words of its own on screen, the fixed line out loud")
  ns.Peon.say("words with no clip")
  check(#played == n + 1, "no clip for other words: quiet")
  for _ = 1, 4 do pf.scripts.OnClick(pf) end
  check(ns.Peon.last == ns.Peon.ANNOYED[1], "poked four times: " .. tostring(ns.Peon.last))
  pf.scripts.OnClick(pf); pf.scripts.OnClick(pf)
  check(ns.Peon.last == "Me not that kind of orc!", "and then the line everyone remembers")
  pf.scripts.OnClick(pf)
  local egg1 = ns.Peon.last
  local isEgg = function(l) for _, e in ipairs(ns.Peon.EASTER) do if e == l then return true end end end
  check(#ns.Peon.EASTER >= 2 and isEgg(egg1), "poked past the annoyed lines: an easter egg: " .. tostring(egg1))
  pf.scripts.OnClick(pf)
  check(isEgg(ns.Peon.last) and ns.Peon.last ~= egg1, "and never the same one twice running")
  W.gt = W.gt + 10; pf.scripts.OnClick(pf)
  local ready = false
  for _, l in ipairs(ns.Peon.READY) do if l == ns.Peon.last then ready = true end end
  check(ready, "after a rest, a ready line again: " .. tostring(ns.Peon.last))
  W.gt = W.gt + 30; fire("QUEST_TURNED_IN", 999, 0, 0) -- one "work complete" per 20 s
  check(ns.Peon.last == "Work complete.", "a turn-in: work complete")
  PlaySoundFile, StopSound = nil, nil
  zug("peon off")
  check(not pf:IsShown(), "/zug peon off hides him")
  ns.Peon.say("unheard")
  check(ns.Peon.last ~= "unheard", "and he stays quiet")
  zug("peon on")
  check(pf:IsShown(), "/zug peon on brings him back")
  zug("peon off")
  ns.Peon.ENABLED = false
end

-- a new character with both a questing and an AoE route is asked which
do
  local asked2 = {}
  StaticPopupDialogs = {}
  StaticPopup_Show = function(which, text) asked2[#asked2 + 1] = { text = text, dlg = StaticPopupDialogs[which] } end
  local cls = select(1, UnitClass("player"))
  local base = "RXP Human " .. cls
  ns.Route.Register({ name = base, steps = { { act = "goto", text = "Q", map = 1429, x = 0.1, y = 0.1 } } })
  ns.Route.Register({ name = base .. " AoE", steps = { { act = "goto", text = "A", map = 1429, x = 0.1, y = 0.1 } } })
  ZugzugLevelerCharDB.route, ZugzugLevelerCharDB.offeredRoute = nil, nil
  fire("PLAYER_ENTERING_WORLD")
  local q
  for _, a in ipairs(asked2) do if a.text:find("two for you", 1, true) then q = a end end
  check(q and q.dlg.button1 == "Questing" and q.dlg.button2 == "AoE", "questing or AoE: asked which")
  if q then q.dlg.OnCancel(nil, nil, "clicked") end
  check(ZugzugLevelerCharDB.route == base .. " AoE", "the second button follows the AoE route")
  StaticPopupDialogs, StaticPopup_Show = nil, nil
  zug("route off")
end

-- live updates: the game's chat log, asked for, never silent
local logging = false
LoggingChat = function(on) if on ~= nil then logging = on end return logging end
mark = #W.printed
zug("live on")
check(logging and ZugzugLevelerDB.live == true and printed("WoWChatLog.txt", mark), "/zug live on turns the game's chat log on and says where it goes")
zug("live check")
check(printed("live check " .. W.t, mark), "/zug live check prints the marker the companion looks for")
zug("live off")
check(not logging and ZugzugLevelerDB.live == false, "/zug live off")
local reloaded = false
ReloadUI = function() reloaded = true end
zug("sync")
check(reloaded and ZugzugLevelerCharDB.syncAt == W.t, "/zug sync saves now (a UI reload)")
LoggingChat, ReloadUI = nil, nil

-- buttons: quest item + target macro, never touched in combat
local item, tgt = _G.ZugzugLevelerItemButton, _G.ZugzugLevelerTargetButton
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
zug("route use button test")
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
zug("route use split test")
play(30); accept(801)
local bs = ZugzugLevelerDB.best["split test"].seg
check(bs[1] and math.abs(bs[1] - 30) < 2, "step 1 timed ~30s: " .. tostring(bs[1]))
zug("route use split test")                      -- 801 already accepted: fast-forward
check(math.abs(bs[1] - 30) < 2, "fast-forwarded step does not set a fake best")
W.log = {}; zug("route use split test")
play(10); accept(801)
check(bs[1] < 12, "faster run sets a new best")
check(S.line():find("-0:2", 1, true) and S.line():find("1 gold", 1, true), "line shows time gained and the gold: " .. tostring(S.line()))

-- downtime: one state per tick, secret aura names ignored
zug("downtime reset")
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
zug("route use obj test")
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
zug("map off")
check(shownLines() == 0, "/zug map off clears the lines")
zug("map on")

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
zug("optimize suggest")
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
zug("route use opt test")
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
zug("optimize")
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
zug("optimize auto")
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
zug("route use auto test")
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
zug("optimize clear")
check(ns.db.optimize == "auto" and ns.cdb.plan == nil, "clear does NOT change the setting (that was the bug)")
check(ns.Engine.index() == 1, "clear: the guide's order")
W.x, W.y = 0.005, 0.7                                 -- walk north again: auto would switch...
for _ = 1, 6 do W.gt = W.gt + 0.5; tick(1) end
check(ns.Engine.index() == 1, "...but not for the stretch you cleared")
check(ns.Optimizer.held == 4, "held until the route passes step 4")
for _, q in ipairs({ 911, 912, 913 }) do W.log[q].objs[1].finished = true; W.log[q].complete = true end
fire("QUEST_LOG_UPDATE")
for _ = 1, 4 do W.gt = W.gt + 0.5; tick(1) end
check(ns.Optimizer.held == nil, "past the stretch: auto is back by itself")
zug("optimize suggest")

-- quest log mode: no guide, the game's own quest positions + quest givers
C_QuestLine = {
  RequestQuestLinesForMap = function() end,
  GetAvailableQuestLines = function(map) return (W.lines or {})[map] or {} end,
}
zug("optimize auto")
W.log = {
  [1001] = { complete = false, title = "Bat Wings", objs = { { text = "Bat wing: 2/6", finished = false } } },
  [1002] = { complete = true, title = "Done Thing", objs = { { text = "x: 1/1", finished = true } } },
  [1003] = { complete = false, title = "Somewhere Else", objs = { { text = "y: 0/1", finished = false } } },
}
W.turnedIn = {}
W.poi = { [1429] = { { questID = 1001, x = 0.10, y = 0.0 }, { questID = 1002, x = 0.90, y = 0.0 } } }
W.wp = {}
W.lines = { [1429] = {
  { questID = 1004, questName = "Nearby Pickup", x = 0.12, y = 0.0, isHidden = false },
  { questID = 1005, questName = "Grey Quest", x = 0.13, y = 0.0, isHidden = true },
} }
W.map, W.x, W.y = 1429, 0.05, 0.01
zug("questlog")
local QLr = ns.Engine.route()
local acts = {}
for _, s in ipairs(QLr.steps) do acts[#acts + 1] = s.act .. s.q end
table.sort(acts)
check(table.concat(acts, ",") == "accept1004,complete1001,turnin1002", "quest log steps: " .. table.concat(acts, ","))
check(#ns.QuestLog.unplaced == 1 and ns.QuestLog.unplaced[1].q == 1003, "a quest with no position is listed, not routed")
check(ZugzugLevelerCharDB.liveSteps and ZugzugLevelerCharDB.liveSteps.route == "Quest log" and #ZugzugLevelerCharDB.liveSteps.steps == #QLr.steps
  and ZugzugLevelerCharDB.liveSteps.steps[1].map, "quest log mode saves its steps for the page's map")
check(ns.Engine.step().q == 1001 or ns.Engine.step().q == 1004, "starts with what is nearest")
W.log[1001].objs[1] = { text = "Bat wing: 6/6", finished = true }; W.log[1001].complete = true
W.gt = W.gt + 1; fire("QUEST_LOG_UPDATE")
local has = {}
for _, s in ipairs(ns.Engine.route().steps) do has[s.act .. s.q] = true end
check(has.turnin1001 and not has.complete1001, "objectives done: it becomes a turn-in step")
local cur = ns.Engine.step()
SlashCmdList.ZUGZUGLEVELERSWAP("")
local gone = true
for _, s in ipairs(ns.Engine.route().steps) do if s.q == cur.q then gone = false end end
check(gone, "/swap sets that quest aside in quest log mode")
W.level = 6; fire("PLAYER_LEVEL_UP", 6); W.level = 5
local back = false
for _, s in ipairs(ns.Engine.route().steps) do if s.q == cur.q then back = true end end
check(back, "level-up brings it back")
-- a /reload in quest log mode: the saved optimizer plan names steps, but the
-- mode's steps are rebuilt only after login (Engine.lua:122 / MapPath.lua:35, Mists)
do
  local qr = ns.Route.Get(ns.QuestLog.NAME)
  local keep = qr.steps
  ZugzugLevelerCharDB.plan = { list = { 3, 1 }, after = 4 }
  qr.steps = {}
  local ok1 = pcall(ns.Engine.evaluate)
  local ok2 = pcall(ns.MapPath.points)
  check(ok1 and ok2 and ZugzugLevelerCharDB.plan == nil, "a saved plan naming steps the route does not have yet is dropped, not followed")
  qr.steps = keep
end
W.wp = { [1003] = { 1430, 0.25, 0.75 } }
local placed
for _, s in ipairs(ns.QuestLog.collect()) do if s.q == 1003 then placed = s end end
check(placed and placed.map == 1430 and placed.x == 0.25 and placed.y == 0.75, "GetNextWaypoint's map AND x, y place a quest")
W.wp = {}
zug("ql debug")
check(W.printed[#W.printed - 1]:find("placed", 1, true) or W.printed[#W.printed]:find("no position", 1, true), "ql debug reports")
zug("optimize suggest")

-- flights: learned at the flight master, measured, used when quicker
function GetTaxiMapID() return 1429 end
C_TaxiMap = { GetAllTaxiNodes = function() return {
  { nodeID = 1, name = "Brill", state = 0, position = CreateVector2D(0.02, 0.02) },
  { nodeID = 2, name = "Far Camp", state = 1, position = CreateVector2D(0.98, 0.98) },
  { nodeID = 3, name = "Unknown Spot", state = 2, position = CreateVector2D(0.5, 0.5) },
} end }
ZugzugLevelerCharDB.flights, ZugzugLevelerCharDB.speed = nil, nil
fire("TAXIMAP_OPENED")
check(#ns.Flight.known() == 2, "learns the 2 known flight points, not the unknown one")
local walk = ns.Flight.travel({ 0, 20, 20 }, { 0, 980, 980 })
local direct = math.sqrt(2) * 960
check(walk < direct * 0.6, ("far trip: flying (%d) beats walking (%d)"):format(walk, direct))
local short = ns.Flight.travel({ 0, 20, 20 }, { 0, 120, 20 })
check(math.abs(short - 100) < 1e-6, "short trip: still walks")
-- the arrow sends you to the flight master first
ns.Route.Register({ name = "fly test", steps = { { act = "complete", q = 1201, obj = 1, map = 1429, cont = 0, wx = 980, wy = 980 } } })
W.log = { [1201] = { complete = false, objs = { { finished = false } } } }
W.map, W.x, W.y = 1429, 0.03, 0.03
zug("route use fly test")
check((ns.Way.current().text or ""):find("Fly", 1, true) and ns.Way.current().wx == 20, "arrow: to the Brill flight master, 'Fly Brill -> Far Camp'")
-- a real flight measures the speed
W.gt = W.gt + 0.5; tick(1)                               -- standing at the flight master
W.taxi = true; W.gt = W.gt + 0.5; tick(1)                -- take off
W.gt = W.gt + 40; W.x, W.y = 0.97, 0.97; tick(1)         -- flying
W.taxi = false; W.gt = W.gt + 0.5; tick(1)               -- landed, 41 s after the last ground sample
check(ns.Flight.measured() and math.abs(ns.Flight.fly() - math.sqrt(2) * 940 / 41) < 0.5, ("flight speed measured: %.1f yd/s"):format(ns.Flight.fly()))
zug("flight")
ZugzugLevelerCharDB.flights = nil

-- danger warnings (RXP's data, here a small stand-in)
check(ns.DangerData and #ns.DangerData.Alliance > 200, "generated danger data loaded")
local realData = ns.DangerData
ns.DangerData = { Alliance = {
  { n = "Hogger", lo = 11, hi = 11, c = "Elite", mv = "Idle", note = "Charge / Stun", pins = { { 1429, 0.50, 0.50 } } },
  { n = "Patrol Gnoll", lo = 9, hi = 10, c = "Normal", mv = "Slow Patrol", lines = { { 1429, { 0.40, 0.60, 0.60, 0.60 } } } },
  { n = "Weak Wolf", lo = 2, hi = 3, c = "Normal", mv = "Idle", pins = { { 1429, 0.52, 0.50 } } },
} }
ns.Danger.reset()
W.level, W.map, W.x, W.y = 10, 1429, 0.53, 0.50          -- 30 yd from Hogger, 10 from the weak wolf
zug("danger on")
ns.Danger.update()
check(ns.Danger.near[1] and ns.Danger.near[1].e.n == "Hogger", "Hogger is the closest threat")
local names = {}
for _, h in ipairs(ns.Danger.near) do names[h.e.n] = true end
check(not names["Weak Wolf"], "a normal mob well under your level is not a threat")
check(table.concat(W.printed, "\n"):find("danger:|r Hogger (elite 11), 30 yd", 1, true), "chat warns once")
local before = #W.printed; ns.Danger.update()
check(#W.printed == before, "...and only once")
W.x, W.y = 0.50, 0.62                                     -- 20 yd beside the middle of the patrol path
ns.Danger.update()
check(ns.Danger.near[1] and ns.Danger.near[1].e.n == "Patrol Gnoll" and math.abs(ns.Danger.near[1].d - 20) < 1e-6, "patrol path: distance to the nearest point on it")
check(table.concat(ns.Danger.rows(), "\n"):find("Patrol Gnoll", 1, true), "window row")
zug("danger off"); ns.Danger.update()
check(#ns.Danger.near == 0, "/zug danger off")
zug("danger on")
ns.DangerData = realData; ns.Danger.reset()

-- options panel: Blizzard's Settings, proxy settings over our own db
check(W.addonCategory and W.addonCategory.name == "zugzug_leveler", "registered under Options > AddOns")
local nCheck, nDrop = 0, 0
for _, s in pairs(W.settings) do if s.options then nDrop = nDrop + 1 else nCheck = nCheck + 1 end end
-- the peon's is left out while Peon.ENABLED is false; sort-after-looting is one
check(nCheck == 26 and nDrop == 3 and not W.settings.ZUGZUG_PEON and W.settings.ZUGZUG_AUTOSORT,
  ("26 toggles (no peon, auto-sort) and 3 dropdowns (%d, %d)"):format(nCheck, nDrop))
-- bag sorting on Forever: Blizzard's own C_Container.SortBags, nothing moved by hand
do
  local sorted, picked = 0, 0
  C_Container.SortBags = function() sorted = sorted + 1 end
  local pick = C_Container.PickupContainerItem
  C_Container.PickupContainerItem = function() picked = picked + 1 end
  zug("sort")
  check(sorted == 1 and picked == 0 and not ns.Bags.busy(), "Forever: /zug sort calls Blizzard's SortBags")
  C_Container.SortBags, C_Container.PickupContainerItem = nil, pick
end
-- play styles: hardcore / self-found steps, from the game or the panel
check(ns.Engine.applies({ act = "goto", mode = "sc" }) and not ns.Engine.applies({ act = "goto", mode = "hc" }), "not hardcore: softcore steps in, hardcore ones out")
C_GameRules = { IsHardcoreActive = function() return true end, GetForeverExperiencePreset = function() return 1 end }
check(ns.Engine.applies({ act = "goto", mode = "hc" }) and not ns.Engine.applies({ act = "goto", mode = "sc" }), "the game says hardcore: hardcore steps in")
W.settings.ZUGZUG_HARDCORE.set(false)
check(not ns.Engine.applies({ act = "goto", mode = "hc" }), "the panel overrides it")
check(not ns.Engine.applies({ act = "goto", mode = "ssf" }) and ns.Engine.applies({ act = "goto", mode = "ah" }), "not self-found: auction-house steps in")
W.settings.ZUGZUG_SSF.set(true)
check(ns.Engine.applies({ act = "goto", mode = "ssf" }) and not ns.Engine.applies({ act = "goto", mode = "ah" }) and not ns.Engine.applies({ act = "goto", mode = "hc,ssf" }), "self-found: its steps in; both marks need both")
ZugzugLevelerCharDB.hardcore, ZugzugLevelerCharDB.ssf, C_GameRules = nil, nil, { GetForeverExperiencePreset = function() return 1 end }
-- the goal, the pause and the route's step kinds, from the panel
local goalSet = W.settings.ZUGZUG_GOAL
goalSet.set(3); check(ns.db.goal == "complete" and goalSet.get() == 3, "goal dropdown: Completion")
goalSet.set(2); check(ns.Route.goal() == "speed", "goal dropdown: Fastest")
local cook = W.settings.ZUGZUG_KIND_COOKING
check(cook and cook.get() == false, "fastest leaves cooking out, and the box shows it")
cook.set(true)
check(not ns.Route.leftOut({ act = "train", text = "Train Cooking" }) and ns.Route.leftOut({ act = "train", text = "Train First Aid" }),
  "ticking cooking keeps it, the goal's other kinds stay out")
ns.RoutePrefs = { skip = { cooking = true }, at = ZugzugLevelerDB.skipAt + 5 }
check(ns.Route.leftOut({ act = "train", text = "Train Cooking" }), "a later choice on the page wins")
ns.RoutePrefs, ZugzugLevelerDB.skip, ZugzugLevelerDB.skipAt, ZugzugLevelerDB.goal, ZugzugLevelerDB.goalAt = nil, nil, nil, nil, nil
W.settings.ZUGZUG_PAUSE.set(true); check(ns.Pause.on(), "pause from the panel")
W.settings.ZUGZUG_PAUSE.set(false); check(not ns.Pause.on(), "and resume")
W.settings.ZUGZUG_COACH.set(false); check(ZugzugLevelerDB.coach == false, "coach off from the panel")
W.settings.ZUGZUG_COACH.set(true)
local arrowSet = W.settings.SLOPLEV_ARROW
arrowSet.set(false)
check(ns.db.arrow == false and arrowSet.get() == false, "unticking Arrow turns it off")
arrowSet.set(true)
check(ns.db.arrow == true, "and back on")
local opt = W.settings.SLOPLEV_OPTIMIZE
check(#opt.options() == 3 and opt.options()[2].label == "Suggest", "optimizer dropdown: Auto / Suggest / Off")
opt.set(3); check(ns.db.optimize == "off" and opt.get() == 3, "dropdown Off sets the optimizer off")
opt.set(2); check(ns.db.optimize == "suggest", "dropdown Suggest")
W.settings.SLOPLEV_RELEASE.set(true); check(ns.db.autoRelease == true, "auto-release toggle")
W.settings.SLOPLEV_RELEASE.set(false)
zug("options")
check(W.openedCategory == 77, "/zug options opens the panel")

-- professions: plan step, materials vs bags, trainer, the profession window
W.profs = { { "Tailoring", 87, 150, 197 }, { "Mining", 40, 75, 186 } }
function GetProfessions() return 1, 2 end
function GetProfessionInfo(i)
  local p = W.profs[i]
  if p then return p[1], 0, p[2], p[3], 0, 0, p[4] end
end
check(ns.ProfData and ns.ProfData.guides.Tailoring and #ns.ProfData.guides.Tailoring > 10, "profession data loaded")
W.bagItems = { [2592] = 12 }                                 -- 12 Wool Cloth in the bags
local rows = table.concat(ns.Prof.lines(), "\n")
check(rows:find("Tailoring|r 87/150  craft ~13 Bolt of Woolen Cloth (to 100)", 1, true), "tailoring: the step and how many crafts")
check(rows:find("39 Wool Cloth/12", 1, true), "materials for the rest of the step vs bags: 39 needed, 12 have")
check(rows:find("Mining|r 40/75  gather Copper Ore", 1, true) and rows:find("Elwynn Forest", 1, true), "mining: what and where for your faction")
W.profs[1] = { "Tailoring", 150, 150, 197 }
rows = table.concat(ns.Prof.lines(), "\n")
check(rows:find("train the next rank", 1, true), "capped: train reminder")
zug("prof way")
local tw = ns.Way.current()
check(tw and tw.manual and tw.map == 1453, "/zug prof way: the arrow to the Expert tailoring trainer in Stormwind")
SlashCmdList.ZUGZUGLEVELERWAY("clear")
C_TradeSkillUI = {
  GetFilteredRecipeIDs = function() return { 1, 2, 3, 4 } end,
  GetRecipeInfo = function(id) return ({
    { recipeID = 1, name = "Woolen Cape", learned = true, relativeDifficulty = 0 },
    { recipeID = 2, name = "Green Woolen Vest", learned = true, relativeDifficulty = 1 },
    { recipeID = 3, name = "Linen Belt", learned = true, relativeDifficulty = 3 },
    { recipeID = 4, name = "Unlearned", learned = false, relativeDifficulty = 0 },
  })[id] end,
  GetCraftableCount = function(id) return ({ 2, 0, 9, 5 })[id] end,
}
fire("TRADE_SKILL_SHOW")
check(#ns.Prof.canSkill == 1 and ns.Prof.canSkill[1].name == "Woolen Cape", "window: only learned, skill-giving, makeable recipes")
ns.UI.refresh()
check(not table.concat(ns.UI.lines(), "\n"):find("skill-ups you can make now", 1, true), "professions are not on the Route tab")
ZugzugLevelerDB.uiTab = "prof"; ns.UI.refresh()
check(table.concat(ns.UI.lines(), "\n"):find("skill-ups you can make now", 1, true), "they are on the Prof tab")
ZugzugLevelerDB.uiTab = "stats"; ns.UI.refresh()
check(table.concat(ns.UI.lines(), "\n"):find("session", 1, true), "the session numbers are on the Stats tab")
ZugzugLevelerDB.uiTab = nil; ns.UI.refresh()
fire("TRADE_SKILL_CLOSE")
check(#ns.Prof.canSkill == 0, "cleared when the profession window closes")
W.profs = {}

-- export for the companion site: map bounds + character snapshot
W.map, W.x, W.y = 1429, 0.3, 0.3
fire("PLAYER_ENTERING_WORLD")
local mb = ZugzugLevelerDB.maps and ZugzugLevelerDB.maps[1429]
check(mb and mb.cont == 0 and mb.x0 == 0 and mb.x1 == 1000 and mb.y1 == 1000 and mb.name == "Map1429", "map bounds recorded for the site")
check(ZugzugLevelerCharDB.char and ZugzugLevelerCharDB.char.level == W.level and ZugzugLevelerCharDB.char.class == "WARRIOR", "character snapshot")
check(ZugzugLevelerCharDB.char.raceID == 1 and ZugzugLevelerCharDB.char.sex == 3, "snapshot keeps race ID and sex (the site's 3D model)")
-- the game closing reports XP 0 of 0: the last good snapshot stays
local good = ZugzugLevelerCharDB.char
local xpMax0 = W.xpMax; W.xpMax = 0
fire("PLAYER_LOGOUT")
check(ZugzugLevelerCharDB.char == good, "a closing game's empty numbers do not replace the snapshot")
W.xpMax = xpMax0

-- gear for the site's Gear tab: equipped, equippable bag items, spec, skills, stats, gold
do
  local items = {
    [2] = { "Worn Shortsword", 1, 2, 1, "Weapon", "One-Handed Swords", "INVTYPE_WEAPONMAINHAND", { ITEM_MOD_STRENGTH_SHORT = 1 } },
    [6] = { "Recruit's Pants", 1, 1, 1, "Armor", "Cloth", "INVTYPE_LEGS", {} },
    [8] = { "Brittle Bow", 0, 1, 1, "Weapon", "Bows", "INVTYPE_RANGED", {} },
    [9] = { "Ring of Secrets", 2, 10, 5, "Armor", "Miscellaneous", "INVTYPE_FINGER", { ITEM_MOD_STAMINA_SHORT = W.secretStat } },
  }
  local function id(link) return tonumber(tostring(link):match("item:(%d+)")) end
  C_Item.GetItemInfo = function(link)
    local n = id(link)
    local it = n and items[n]
    if not it then local k = tonumber(tostring(link):match("%d+")); return link, nil, nil, nil, nil, nil, nil, nil, nil, nil, (k or 0) * 10 end
    return it[1], link, it[2], it[3], it[4], it[5], it[6], 1, it[7], 1000 + n, n * 7, it[5] == "Weapon" and 2 or 4, n == 2 and 7 or 1, 2
  end
  C_Item.GetItemInfoInstant = function(link) return id(link) end
  C_Item.GetItemStats = function(link) local it = items[id(link)]; return it and it[8] end
  C_Item.IsEquippableItem = function(link) return items[id(link)] ~= nil end
  C_TooltipInfo = { GetHyperlink = function(link)
    if id(link) ~= 2 then return { lines = {} } end
    local white = { GetRGB = function() return 1, 1, 1 end }
    return { lines = { { leftText = "Worn Shortsword", leftColor = white }, { leftText = "1 - 3 Damage", rightText = "Speed 1.90" }, { leftText = "(1.1 damage per second)" } } }
  end }
  local worn = { [16] = "|Hitem:2::|h", [7] = "|Hitem:6::|h" }
  local slotIDs = { HeadSlot = 1, LegsSlot = 7, MainHandSlot = 16 }
  C_PaperDollInfo = { GetInventorySlotInfo = function(name) return slotIDs[name] or 99, 0, false end }
  function GetInventoryItemLink(_, slot) return worn[slot] end
  function GetInventoryItemDurability(slot) if worn[slot] then return 30, 35 end end
  W.bags[1] = { { hyperlink = "|Hitem:8::|h" }, { hyperlink = "|Hitem:77::|h" }, { hyperlink = "|Hitem:9::|h" } }
  function UnitStat(_, i) return 20 + i, 20 + i end
  function GetSpellBonusDamage(school) return school == 3 and 12 or 0 end
  function GetAverageItemLevel() return 3, 2.5 end
  W.money = 1234
  function GetMoney() return W.money end
  C_SpecializationInfo = {
    GetSpecialization = function() return 2 end,
    GetNumSpecializationsForClassID = function() return 3 end,
    GetSpecializationInfo = function(i) return 70 + i, ({ "Arms", "Fury", "Protection" })[i], "", 1, "DAMAGER", 1, i == 2 and 5 or 0 end,
  }
  local lines = { { isHeader = true, name = "Weapon Skills" }, { name = "Swords", rank = 5, maxRank = 25 }, { isHeader = true, name = "Armor Proficiencies" }, { name = "Cloth", rank = 1, maxRank = 1 } }
  C_SkillInfo = { GetNumSkillLines = function() return #lines end, GetSkillLineInfo = function(i) return lines[i] end }
  fire("PLAYER_EQUIPMENT_CHANGED")
  local g = ZugzugLevelerCharDB.gear
  local mh = g and g.slots.MainHand
  check(mh and mh.name == "Worn Shortsword" and mh.stats.ITEM_MOD_STRENGTH_SHORT == 1 and mh.dur == 30, "equipped item with stats and durability, by slot name")
  check(mh and mh.cid == 2 and mh.sc == 7 and mh.bind == 2, "item class, subclass and binding saved")
  check(mh and #mh.tip == 2 and mh.tip[1] == "1 - 3 Damage|Speed 1.90", "tooltip lines with numbers kept, left|right")
  check(mh and #mh.tt == 3 and mh.tt[1] == "ffffff\tWorn Shortsword\tffd100\t" and mh.tt[2] == "ffd100\t1 - 3 Damage\tffd100\tSpeed 1.90",
    "whole tooltip kept with the game's line colours (yellow when none)")
  check(g and g.slots.Legs and g.slots.Legs.sub == "Cloth" and g.slots.Legs.loc == "INVTYPE_LEGS" and not g.slots.Head, "legs saved, empty slots left out")
  check(g and #g.bags == 2 and g.bags[1].id == 8, "only equippable bag items saved")
  W.secretStat = nil
  check(g and g.spec.cur == 2 and g.spec.trees[2].name == "Fury" and g.spec.trees[2].points == 5, "spec and points per tree")
  check(g and g.skills[1].name == "Swords" and g.skills[1].head == "Weapon Skills" and g.skills[2].head == "Armor Proficiencies", "skills keep their header")
  check(g and g.stats.sta == 23 and g.stats.spell == 12 and g.ilvl == 2.5 and g.money == 1234, "stats, spell power, item level, gold")
  W.secret = true
  fire("PLAYER_EQUIPMENT_CHANGED")
  W.secret = false
  check(ZugzugLevelerCharDB.gear.stats.sta == nil and ZugzugLevelerCharDB.gear.money == nil, "secret values are never saved")
  fire("PLAYER_EQUIPMENT_CHANGED")
  fire("PLAYER_MONEY")
  local t0 = W.t
  W.money = 2000; fire("PLAYER_MONEY")
  check(#ZugzugLevelerCharDB.money == 1 and ZugzugLevelerCharDB.money[1][2] == 2000, "gold changes within 2 min update one sample")
  W.t = W.t + 300; W.money = 2500; fire("PLAYER_MONEY")
  check(#ZugzugLevelerCharDB.money == 2 and ZugzugLevelerCharDB.money[2][1] == t0 + 300, "a later change adds a sample")

  -- the item catalogue: quest rewards at the NPC, read before Assist accepts
  local oldLink = GetQuestItemLink
  local seenAtAccept
  GetQuestItemLink = function(kind, i)
    if W.qf.closed then return nil end
    if kind == "choice" then return ({ "|Hitem:8::|h", "|Hitem:9::|h", "|Hitem:77::|h" })[i] end
    if kind == "reward" then return "|Hitem:6::|h" end
  end
  function GetNumQuestRewards() return 1 end
  function GetTitleText() return "Wanted: Bones" end
  function GetQuestText() return "Bones everywhere. Bring me some." end
  function GetObjectiveText() return "Bring 8 Bones to Ana." end
  local oldAccept = AcceptQuest
  AcceptQuest = function() seenAtAccept = ZugzugLevelerDB.quests and ZugzugLevelerDB.quests[555]; W.qf.closed = true; called("AcceptQuest", W.qf.id) end
  W.qf.id, W.qf.choices = 555, 3
  ns.Route.Register({ name = "reward test", steps = { { act = "accept", q = 555 } } })
  zug("route use reward test")
  fire("QUEST_DETAIL")
  local qr = ZugzugLevelerDB.quests and ZugzugLevelerDB.quests[555]
  check(qr and #qr.choice == 2 and qr.choice[1] == 8 and qr.choice[2] == 9 and qr.reward[1] == 6, "quest rewards recorded, equippable only")
  check(seenAtAccept ~= nil, "rewards are read before Assist accepts the quest")
  local qt = ZugzugLevelerDB.questText and ZugzugLevelerDB.questText[555]
  check(qt and qt.ask == "Bring 8 Bones to Ana." and qt.desc:find("Bones everywhere", 1, true) and qt.map == W.map,
    "the quest's own words, kept when it is offered, with where")
  GetQuestText, GetObjectiveText = nil, nil
  check(ZugzugLevelerDB.items[9] and ZugzugLevelerDB.items[9].name == "Ring of Secrets" and ZugzugLevelerDB.items[9].req == 5, "reward items kept in the catalogue")
  GetQuestItemLink, AcceptQuest, W.qf.closed, W.qf.choices, W.qf.id = oldLink, oldAccept, nil, 0, nil
  -- the quest log, with objectives
  W.log[701] = { title = "Wolves", complete = false, objs = { { text = "Wolf killed: 3/8", numFulfilled = 3, numRequired = 8, finished = false } } }
  W.log[702] = { title = "Mail", complete = true, objs = {} }
  fire("QUEST_LOG_UPDATE")
  local ql = ZugzugLevelerCharDB.questLog or {}
  local byQ = {}
  for _, e in ipairs(ql) do byQ[e.q] = e end
  check(byQ[701] and byQ[701].title == "Wolves" and byQ[701].objs[1].have == 3 and byQ[701].objs[1].need == 8 and not byQ[701].done, "quest log saved with objective progress")
  check(byQ[702] and byQ[702].done == true, "finished quests marked done")
  W.log[701], W.log[702] = nil, nil
  fire("QUEST_TURNED_IN", 555, 100, 0)
  check(ZugzugLevelerCharDB.turnedIn and ZugzugLevelerCharDB.turnedIn[555] == W.t, "turned-in quests remembered per character")

  -- merchants
  function GetMerchantNumItems() return 2 end
  function GetMerchantItemLink(i) return ({ "|Hitem:6::|h", "|Hitem:77::|h" })[i] end
  C_MerchantFrame = { GetItemInfo = function(i) return { price = 100 * i } end }
  function UnitName(u) return u == "npc" and "Vendor Vic" or "Tester" end
  fire("MERCHANT_SHOW"); fire("MERCHANT_SHOW")
  local v = ZugzugLevelerDB.vendors and ZugzugLevelerDB.vendors[6]
  check(v and #v == 1 and v[1].npc == "Vendor Vic" and v[1].price == 100 and v[1].map == W.map, "merchant items with seller, place and price, once per seller")
  check(ZugzugLevelerDB.vendors[77] == nil, "items you cannot equip are not kept")
  function UnitName() return "Tester" end
end

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
zug("optimize clear")

-- UI renders without errors
ns.UI.refresh()
zug("export")
local before = #W.printed
zug("route use rxp test"); zug("why")
local said = table.concat(W.printed, "\n", before + 1)
check(said:find("Step %d+ of %d+:"), "/zug why explains the step")
before = #W.printed; zug("why debug")
said = table.concat(W.printed, "\n", before + 1)
check(said:find("step %d+:"), "/zug why debug reports what the engine sees")
zug("runs")
zug("help")

-- optional: write ZugzugLevelerDB the way WoW writes SavedVariables
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
  f:write("\nZugzugLevelerDB = " .. ser(ZugzugLevelerDB, 0) .. "\n")
  f:write("ZugzugLevelerCharDB = " .. ser(ZugzugLevelerCharDB, 0) .. "\n")
  f:close()
end

local err = errorsPrinted()
check(not err, "no handler errors (" .. tostring(err) .. ")")

io.write(string.format("%d passed, %d failed\n", passed, failures))
os.exit(failures == 0 and 0 or 1)
