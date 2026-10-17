-- Compat.lua -- every game call the addon makes, behind one table.
--
-- try()/passOk() and the feature-detect rule come from ghoul's GhoulBridge.lua:
-- detect each API, never a version number, and wrap every call so a function
-- missing (or refused) on some client reads as nil instead of erroring every
-- frame. That matters more on Forever than anywhere: it runs Midnight's
-- "secrets", so a call can start refusing an addon in a later build.
--
-- Signatures checked against Blizzard's own export for 1.60.1 (70450),
-- Gethe/wow-ui-source branch `forever`, Blizzard_APIDocumentationGenerated.

local _, ns = ...

local C = {}
ns.C = C

-- ALL of f's results, or nil if it errors. (GhoulBridge: a fixed-arity
-- version once dropped GetQuestLogTitle's 8th value and every quest vanished.)
local function passOk(ok, ...)
  if ok then return ... end
  return nil
end

function C.try(f, ...)
  if not f then return nil end
  return passOk(pcall(f, ...))
end
local try = C.try

-- C_Container.X on modern clients, the old global otherwise.
function C.bagFn(name) return (C_Container and C_Container[name]) or _G[name] end

-- (uiMapID, x, y) with x, y in 0..1; (uiMapID) alone inside instances.
function C.mapPos()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local id = try(C_Map.GetBestMapForUnit, "player")
  local pos = id and try(C_Map.GetPlayerMapPosition, id, "player")
  if pos then
    local x, y = pos:GetXY()
    if x and (x > 0 or y > 0) then return id, x, y end
  end
  return id
end

-- (continentID, worldX, worldY) in yards, so points on a zone map and on one
-- of its sub-zone maps can be compared.
function C.worldPos(mapID, x, y)
  if not (mapID and x and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local cont, pos = try(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if not (cont and pos) then return nil end
  local wx, wy = pos:GetXY()
  return cont, wx, wy
end

-- Yards between two map points, or nil when they are not comparable
-- (different continents, or a map with no world position, like an instance).
function C.yards(m1, x1, y1, m2, x2, y2)
  local c1, a1, b1 = C.worldPos(m1, x1, y1)
  local c2, a2, b2 = C.worldPos(m2, x2, y2)
  if not (c1 and c2) or c1 ~= c2 then return nil end
  return math.sqrt((a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

-- World position (continent, vector x, vector y) -> (uiMapID, x, y) on
-- `map` (or the best map there). The inverse of C.worldPos.
function C.fromWorld(cont, wx, wy, map)
  if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
  local id, pos = try(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy), map)
  if not (id and pos) then return nil end
  local x, y = pos:GetXY()
  return id, x, y
end

function C.mapName(id)
  local info = id and C_Map and try(C_Map.GetMapInfo, id)
  return info and info.name or nil
end

-- --------------------------------------------------------------- quests

function C.isOnQuest(q) return (C_QuestLog and try(C_QuestLog.IsOnQuest, q)) and true or false end
function C.isComplete(q) return (C_QuestLog and try(C_QuestLog.IsComplete, q)) and true or false end
function C.isTurnedIn(q) return (C_QuestLog and try(C_QuestLog.IsQuestFlaggedCompleted, q)) and true or false end

-- The quest's objectives as the game reports them: { text, finished,
-- numFulfilled, numRequired } each (QuestObjectiveInfo in the 1.60.1 export).
-- Empty when the quest is not in the log.
function C.objectives(q)
  local list = q and C_QuestLog and try(C_QuestLog.GetQuestObjectives, q)
  return type(list) == "table" and list or {}
end

-- One objective (1-based) of a quest in the log is finished.
function C.objectiveDone(q, obj)
  local o = C.objectives(q)[obj]
  return (o and o.finished) and true or false
end

function C.questTitle(q)
  return (C_QuestLog and try(C_QuestLog.GetTitleForQuestID, q)) or nil
end

-- questIDs currently in the log (headers skipped).
function C.questLogIDs()
  local out = {}
  if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return out end
  for i = 1, (try(C_QuestLog.GetNumQuestLogEntries) or 0) do
    local info = try(C_QuestLog.GetInfo, i)
    if info and not info.isHeader and info.questID and info.questID > 0 then
      out[#out + 1] = info.questID
    end
  end
  return out
end

-- ------------------------------------------------------------------ XP

-- (xp, xpMax, level, rested) or nil when the values are not readable.
function C.xp()
  local cur, max = try(UnitXP, "player"), try(UnitXPMax, "player")
  if type(cur) ~= "number" or type(max) ~= "number" then return nil end
  return cur, max, try(UnitLevel, "player") or 0, try(GetXPExhaustion) or 0
end

-- "classic" / "modern" / nil: Forever's XP-rate preset
-- (Enum.ForeverExperiencePreset: Classic = 0, Modern = 1).
function C.xpPreset()
  local p = C_GameRules and try(C_GameRules.GetForeverExperiencePreset)
  if p == 0 then return "classic" elseif p == 1 then return "modern" end
  return nil
end

function C.now() return try(GetTime) or 0 end
function C.epoch() return try(GetServerTime) or try(time) or 0 end

function C.charKey()
  return (try(UnitName, "player") or "?") .. "-" .. (try(GetRealmName) or "?")
end

function C.print(fmt, ...)
  local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  print("|cff8fd14fsl0p.leveler|r " .. msg)
end
