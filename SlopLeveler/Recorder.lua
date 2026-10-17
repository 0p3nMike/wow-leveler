-- Recorder.lua -- write down the route as it is actually played.
--
-- A run lives in SlopLevelerDB.runs (account-wide, so a route recorded on one
-- character can be replayed on the next). Two streams:
--   run.ev    quest/level/travel events, one table each:
--             { t, e, q, title, map, x, y, lvl, xp, gain, note }
--   run.path  position breadcrumbs as compact strings "t|map|x|y"
--             (x, y as 0..10000) -- a 1-60 run is tens of thousands of these,
--             and strings keep the SavedVariables file small.
-- Event names (e): accept, done (objectives complete), turnin, abandon,
-- level, xp (kill/explore XP merged per MERGE s), fly, land, hearth,
-- sethearth, death, zone, mark.

local _, ns = ...
local C = ns.C

local R = {}
ns.Rec = R

local CRUMB_EVERY = 5      -- seconds between breadcrumbs
local CRUMB_MOVE = 0.002   -- ...and only if moved this far (map units) or changed map
local MERGE = 10           -- kill XP within this many seconds folds into one entry
local HEARTH_SPELL = 8690  -- Hearthstone

local run              -- the run being recorded, or nil
local lastCrumb = { t = 0 }
local complete = {}    -- questID -> true once its objectives were seen complete
local flying = false

function R.active() return run end

local function stamp(e, fields)
  if not run then return end
  local mapID, x, y = C.mapPos()
  local cur, _, lvl = C.xp()
  local entry = { t = C.epoch(), e = e, map = mapID, x = x, y = y, lvl = lvl, xp = cur }
  for k, v in pairs(fields or {}) do entry[k] = v end
  run.ev[#run.ev + 1] = entry
  return entry
end
R.stamp = stamp

local function seedComplete()
  complete = {}
  for _, q in ipairs(C.questLogIDs()) do
    if C.isComplete(q) then complete[q] = true end
  end
end

function R.start(name)
  local db = ns.db
  db.runs = db.runs or {}
  run = {
    name = name ~= "" and name or nil,
    char = C.charKey(),
    class = select(2, C.try(UnitClass, "player")),
    race = select(2, C.try(UnitRace, "player")),
    preset = C.xpPreset(),
    started = C.epoch(),
    startLevel = C.try(UnitLevel, "player"),
    ev = {}, path = {},
  }
  db.runs[#db.runs + 1] = run
  db.recording = #db.runs
  seedComplete()
  lastCrumb = { t = 0 }
  stamp("zone", { note = C.mapName((C.mapPos())) })
  return #db.runs
end

function R.stop()
  if not run then return nil end
  run.stopped = C.epoch()
  run.endLevel = C.try(UnitLevel, "player")
  local n = ns.db.recording
  run, ns.db.recording = nil, nil
  return n
end

function R.mark(note) return stamp("mark", { note = note }) end

-- Resume the run that was recording when the UI was last unloaded.
ns.On("SL_READY", function()
  local n = ns.db.recording
  local r = n and ns.db.runs and ns.db.runs[n]
  if r and not r.stopped then
    run = r
    seedComplete()
  else
    ns.db.recording = nil
  end
end)

-- ------------------------------------------------------------- quest events

ns.On("QUEST_ACCEPTED", function(q)
  if not run or type(q) ~= "number" then return end
  stamp("accept", { q = q, title = C.questTitle(q) })
end)

ns.On("QUEST_TURNED_IN", function(q, xpReward, money)
  if not run then return end
  complete[q] = nil
  stamp("turnin", { q = q, gain = xpReward, money = money })
end)

ns.On("QUEST_REMOVED", function(q)
  if not run or type(q) ~= "number" then return end
  -- QUEST_REMOVED also fires on a turn-in; only a quest that was not turned
  -- in was abandoned. Checked a moment later, once the flag is set.
  local function check()
    if not C.isTurnedIn(q) and not C.isOnQuest(q) then
      complete[q] = nil
      stamp("abandon", { q = q })
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(1, check) else check() end
end)

-- Objectives finishing has no event of its own; QUEST_LOG_UPDATE is the
-- signal, and the flip from incomplete to complete is what gets recorded.
ns.On("QUEST_LOG_UPDATE", function()
  if not run then return end
  for _, q in ipairs(C.questLogIDs()) do
    if not complete[q] and C.isComplete(q) then
      complete[q] = true
      stamp("done", { q = q, title = C.questTitle(q) })
    end
  end
end)

-- ------------------------------------------------------- level, xp, travel

ns.On("PLAYER_LEVEL_UP", function(lvl) if run then stamp("level", { lvl = lvl }) end end)

ns.On("SL_XP", function(gain, quest)
  if not run then return end
  local other = gain - quest
  if other <= 0 then return end
  local prev = run.ev[#run.ev]
  if prev and prev.e == "xp" and C.epoch() - prev.t <= MERGE then
    prev.gain, prev.n = prev.gain + other, (prev.n or 1) + 1
  else
    stamp("xp", { gain = other, n = 1 })
  end
end)

ns.On("TAXIMAP_CLOSED", function()
  if run and C.try(UnitOnTaxi, "player") then flying = true; stamp("fly") end
end)

ns.On("PLAYER_CONTROL_GAINED", function()
  if run and flying then flying = false; stamp("land") end
end)

ns.On("HEARTHSTONE_BOUND", function()
  if run then stamp("sethearth", { note = C.try(GetBindLocation) }) end
end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  -- spellID can be a secret value on Forever; comparing one errors, so pcall.
  if not run or unit ~= "player" then return end
  local ok, isHearth = pcall(function() return spellID == HEARTH_SPELL end)
  if ok and isHearth then stamp("hearth", { note = C.try(GetBindLocation) }) end
end)

ns.On("PLAYER_DEAD", function() if run then stamp("death") end end)

ns.On("ZONE_CHANGED_NEW_AREA", function()
  if run then stamp("zone", { note = C.mapName((C.mapPos())) }) end
end)

-- -------------------------------------------------------------- breadcrumbs

ns.On("SL_TICK", function()
  if not run then return end
  local now = C.epoch()
  if now - lastCrumb.t < CRUMB_EVERY then return end
  local mapID, x, y = C.mapPos()
  if not x then return end
  local moved = mapID ~= lastCrumb.map
    or math.abs(x - lastCrumb.x) + math.abs(y - lastCrumb.y) > CRUMB_MOVE
  if not moved then return end
  lastCrumb = { t = now, map = mapID, x = x, y = y }
  run.path[#run.path + 1] = string.format("%d|%d|%d|%d", now, mapID,
    math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5))
end)
