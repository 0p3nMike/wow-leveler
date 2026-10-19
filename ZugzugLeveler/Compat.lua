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

-- Forever (1.60.1) asks C_QuestLog. Mists of Pandaria Classic (5.5.4) still has
-- the older quest log globals and lacks most of C_QuestLog: GetNumQuestLogEntries,
-- GetQuestLogTitle(i) -> title, level, questTag, isHeader, isCollapsed,
-- isComplete (1 done, -1 failed), frequency, questID (Cata QuestLogFrame.lua:232),
-- IsQuestComplete(questID) (QuestDataProvider.lua:139), GetQuestLogIndexByID,
-- GetQuestsCompleted. Every quest call below tries the new one, then the old.
function C.isOnQuest(q) return (C_QuestLog and try(C_QuestLog.IsOnQuest, q)) and true or false end
function C.isComplete(q)
  if C_QuestLog and C_QuestLog.IsComplete then return try(C_QuestLog.IsComplete, q) and true or false end
  return try(IsQuestComplete, q) and true or false
end
function C.isTurnedIn(q) return (C_QuestLog and try(C_QuestLog.IsQuestFlaggedCompleted, q)) and true or false end

-- Every questID ever turned in, as a set { [questID] = true }, or nil.
-- C_QuestLog.GetAllCompletedQuestIDs is a list; the old GetQuestsCompleted a set.
function C.completedSet()
  local all = C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs and try(C_QuestLog.GetAllCompletedQuestIDs)
  if type(all) == "table" then
    local set = {}
    for _, q in ipairs(all) do set[q] = true end
    return set
  end
  all = try(GetQuestsCompleted)
  if type(all) ~= "table" then return nil end
  local set = {}
  for k, v in pairs(all) do
    if type(k) == "number" and v then set[k] = true elseif type(v) == "number" then set[v] = true end
  end
  return set
end

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

-- The quest log, row by row: { i, title, level, isHeader, questID, isComplete }.
-- C_QuestLog.GetInfo where the game has it, else GetQuestLogTitle.
function C.questLog()
  local out = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, (try(C_QuestLog.GetNumQuestLogEntries) or 0) do
      local info = try(C_QuestLog.GetInfo, i)
      if info then
        out[#out + 1] = { i = i, title = info.title, level = info.level, isHeader = info.isHeader and true or false, questID = info.questID }
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, (try(GetNumQuestLogEntries) or 0) do
      local title, level, _, isHeader, _, isComplete, _, questID = try(GetQuestLogTitle, i)
      if title then
        out[#out + 1] = { i = i, title = title, level = level, isHeader = isHeader and true or false, questID = questID,
          isComplete = type(isComplete) == "number" and isComplete > 0 }
      end
    end
  end
  return out
end

function C.questTitle(q)
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then return try(C_QuestLog.GetTitleForQuestID, q) or nil end
  local i = q and GetQuestLogIndexByID and try(GetQuestLogIndexByID, q)
  if i and i > 0 then return (try(GetQuestLogTitle, i)) or nil end
  -- any quest, in the log or not (Mists QuestLogDocumentation: GetQuestInfo
  -- -> title, MayReturnNothing until the client has the quest cached)
  return (C_QuestLog and try(C_QuestLog.GetQuestInfo, q)) or nil
end

-- A quest log row's own words: description, objectives text. Forever takes
-- the row; the older GetQuestLogQuestText() reads the selected row (TBC
-- QuestLogFrame.lua:371), so select it and put the selection back.
function C.questText(i)
  if not (GetQuestLogSelection and SelectQuestLogEntry) or (C_QuestLog and C_QuestLog.GetInfo) then
    return try(GetQuestLogQuestText, i)
  end
  local was = try(GetQuestLogSelection)
  try(SelectQuestLogEntry, i)
  local desc, ask = try(GetQuestLogQuestText)
  if was then try(SelectQuestLogEntry, was) end
  return desc, ask
end

-- questIDs currently in the log (headers skipped).
function C.questLogIDs()
  local out = {}
  for _, e in ipairs(C.questLog()) do
    if not e.isHeader and e.questID and e.questID > 0 then out[#out + 1] = e.questID end
  end
  return out
end

-- ------------------------------------------------------------- tooltips

-- An item's tooltip as { lines = { { leftText, rightText, leftColor, rightColor } } },
-- the shape C_TooltipInfo.GetHyperlink returns on Forever. Mists of Pandaria
-- has no C_TooltipInfo, so there a hidden GameTooltip is filled with the link
-- and its rows (<name>TextLeftN / TextRightN, GameTooltipTemplate) read back.
local scanTip
local function color(fs)
  local r, g, b = try(fs.GetTextColor, fs)
  if type(r) ~= "number" then return nil end
  return { GetRGB = function() return r, g, b end }
end
function C.tooltip(link)
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then return try(C_TooltipInfo.GetHyperlink, link) end
  if type(link) ~= "string" or not CreateFrame then return nil end
  if not scanTip then
    scanTip = try(CreateFrame, "GameTooltip", "ZugzugScanTip", nil, "GameTooltipTemplate")
    if not scanTip then return nil end
  end
  try(scanTip.SetOwner, scanTip, WorldFrame, "ANCHOR_NONE")
  try(scanTip.ClearLines, scanTip)
  if not try(function() scanTip:SetHyperlink(link) return true end) then return nil end
  local out = {}
  for i = 1, (try(scanTip.NumLines, scanTip) or 0) do
    local l, r = _G["ZugzugScanTipTextLeft" .. i], _G["ZugzugScanTipTextRight" .. i]
    out[#out + 1] = {
      leftText = l and try(l.GetText, l), rightText = r and r:IsShown() and try(r.GetText, r) or nil,
      leftColor = l and color(l), rightColor = r and color(r),
    }
  end
  try(scanTip.Hide, scanTip)
  return { lines = out }
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

-- Running on WoW: Forever? Its C_GameRules.GetForeverExperiencePreset is in
-- the 1.60.1 export and not in Mists of Pandaria Classic's (Ketho's lists for
-- both). Forever-only data (RestedXP routes, talents, the danger list, the 1-300
-- profession plan) is used only when this is true: the TOC's
-- [AllowLoadGameType camelot] tags did not keep the routes out on Mists (a Mists
-- character was offered "RXP Undead Mage", 2026-10-18).
function C.isForever() return (C_GameRules and C_GameRules.GetForeverExperiencePreset) and true or false end

function C.now() return try(GetTime) or 0 end
function C.epoch() return try(GetServerTime) or try(time) or 0 end

function C.charKey()
  return (try(UnitName, "player") or "?") .. "-" .. (try(GetRealmName) or "?")
end

function C.print(fmt, ...)
  local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  print("|cff8fd14fzugzug_leveler|r " .. msg)
end
