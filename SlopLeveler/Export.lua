-- Export.lua -- what the companion site (companion/) needs that nothing else saves.
--
-- Addons cannot talk to anything outside the game; the site reads the
-- SavedVariables files the game writes on /reload and logout. This adds:
--   SlopLevelerDB.maps[uiMapID]   = { name, cont, x0, y0, x1, y1 }
--       where a map sits in the world: C_Map.GetWorldPosFromMapPos at the
--       map's corners (0,0) and (1,1). With it the site can put recorded paths
--       (map x/y) and route stops (world x/y) on one canvas. Your map and the
--       ones above it, recorded as you travel.
--   SlopLevelerCharDB.char        = name, realm, class, race, faction, level, xp, xpMax,
--                                   rested, map/x/y (where you were), at
--   SlopLevelerCharDB.profSnap    = your professions and skill (Professions.lua's P.mine())
--   SlopLevelerCharDB.gear        = what you wear and carry, for the site's Gear tab:
--       slots[slot name: "Head", "Finger0", "MainHand" ...] / bags[n] =
--         { id, name, q, ilvl, req, type, sub, loc, icon, sell, cid, sc, bind, stats, tip, dur, durMax }
--       spec = { cur, trees = { { name, role, points } } }, stats = { str, agi, sta, int, spi, spell },
--       skills = { { name, rank, max, head } } (armor and weapon skills say what you can wear),
--       money, ilvl
--   SlopLevelerCharDB.money       = { { t, copper } ... }: gold over time (one sample per change, 2 min apart)
--   SlopLevelerCharDB.turnedIn    = { [questID] = time }: quests this character turned in
--   SlopLevelerCharDB.questLog    = the quest log with objectives (E.questLog)
-- The site writes back only one file: routes/custom/Planner.lua (its Planner
-- tab), which this addon loads on /reload like any other route.
--
-- Gear APIs (1.60.1 export, Gethe/wow-ui-source `forever`): C_Item.GetItemInfo /
-- GetItemStats / IsEquippableItem, GetInventoryItemLink / GetInventoryItemDurability
-- (Camelot PaperDollFrame.lua), C_SpecializationInfo.GetSpecialization /
-- GetSpecializationInfo (returns pointsSpent) / GetNumSpecializationsForClassID,
-- C_SkillInfo.GetNumSkillLines / GetSkillLineInfo (Camelot SkillsFrame.lua),
-- UnitStat, GetSpellBonusDamage, GetAverageItemLevel, GetMoney.

local _, ns = ...
local C = ns.C

local E = {}
ns.Export = E

function E.mapBounds(id)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local c0, p0 = C.try(C_Map.GetWorldPosFromMapPos, id, CreateVector2D(0, 0))
  local c1, p1 = C.try(C_Map.GetWorldPosFromMapPos, id, CreateVector2D(1, 1))
  if not (c0 and p0 and p1) or c0 ~= c1 then return nil end
  local x0, y0 = p0:GetXY()
  local x1, y1 = p1:GetXY()
  if x0 == x1 or y0 == y1 then return nil end
  return { name = C.mapName(id), cont = c0, x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

function E.recordMaps()
  ns.db.maps = ns.db.maps or {}
  local id, guard = C.mapPos(), 0
  while id and id > 0 and guard < 4 do
    if not ns.db.maps[id] then ns.db.maps[id] = E.mapBounds(id) end
    local info = C_Map and C.try(C_Map.GetMapInfo, id)
    id = info and info.parentMapID
    guard = guard + 1
  end
end

function E.snapshot()
  local cur, max, lvl, rested = C.xp()
  local _, class = C.try(UnitClass, "player")
  local _, race = C.try(UnitRace, "player")
  local map, x, y = C.mapPos()
  ns.cdb.char = {
    name = C.try(UnitName, "player"), realm = C.try(GetRealmName), class = class, race = race,
    faction = C.try(UnitFactionGroup, "player"), level = lvl, xp = cur, xpMax = max, rested = rested,
    map = map, x = x, y = y, at = C.epoch(),
  }
  if ns.Prof then ns.cdb.profSnap = ns.Prof.mine() end
  E.gear()
end

-- ------------------------------------------------------------------ gear

-- A value the addon may keep: nil for Midnight "secrets" (Forever runs them).
local function plain(v)
  if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

function E.item(link)
  if type(link) ~= "string" or not C_Item then return nil end
  local name, _, q, ilvl, req, typ, sub, _, loc, icon, sell, cid, sc, bind = C.try(C_Item.GetItemInfo, link)
  local id = C.try(C_Item.GetItemInfoInstant, link) or tonumber(link:match("item:(%d+)"))
  if not id then return nil end
  local stats = {}
  for k, v in pairs(C.try(C_Item.GetItemStats, link) or {}) do
    if type(k) == "string" and type(plain(v)) == "number" then stats[k] = v end
  end
  return { id = id, name = plain(name), q = plain(q), ilvl = plain(ilvl), req = plain(req), type = plain(typ),
    sub = plain(sub), loc = plain(loc), icon = plain(icon), sell = plain(sell), stats = stats, tip = E.tipLines(link),
    cid = plain(cid), sc = plain(sc), bind = plain(bind) } -- classID 2 weapon / 4 armor, subclassID (Enum.ItemWeaponSubclass / ItemArmorSubclass)
end

-- The tooltip's lines that carry numbers ("left|right"). GetItemStats has no
-- weapon speed and lumps every spell school together, so the site reads those
-- from here, as RestedXP's ItemUpgrades.lua does. C_TooltipInfo.GetHyperlink
-- returns { lines = { { leftText, rightText } } } (Blizzard_SharedXMLGame
-- TooltipDataHandler.lua iterates tooltipData.lines the same way).
function E.tipLines(link)
  local data = C_TooltipInfo and C.try(C_TooltipInfo.GetHyperlink, link)
  local out = {}
  for _, l in ipairs(type(data) == "table" and data.lines or {}) do
    local left, right = plain(l.leftText), plain(l.rightText)
    local s = (type(left) == "string" and left or "") .. (type(right) == "string" and right ~= "" and "|" .. right or "")
    if s:find("%d") and #out < 16 then out[#out + 1] = s end
  end
  return out
end

local function spec()
  local S = C_SpecializationInfo
  if not S then return nil end
  local _, _, classID = C.try(UnitClass, "player")
  local out = { cur = plain(C.try(S.GetSpecialization)), trees = {} }
  local n = classID and C.try(S.GetNumSpecializationsForClassID, classID) or 0
  for i = 1, n do
    local _, name, _, _, role, _, points = C.try(S.GetSpecializationInfo, i)
    out.trees[i] = { name = plain(name), role = plain(role), points = plain(points) or 0 }
  end
  return out
end

-- Armor and weapon skills (and the rest of the skill list), with the header
-- each sits under, so the site knows what this character can wear.
local function skills()
  local S, out, head = C_SkillInfo, {}, nil
  if not (S and S.GetNumSkillLines) then return out end
  for i = 1, (C.try(S.GetNumSkillLines) or 0) do
    local s = C.try(S.GetSkillLineInfo, i)
    if s and s.isHeader then head = plain(s.name)
    elseif s and plain(s.name) then out[#out + 1] = { name = s.name, rank = plain(s.rank), max = plain(s.maxRank), head = head } end
  end
  return out
end

local STAT = { "str", "agi", "sta", "int", "spi" } -- UnitStat's index order
-- The character frame's slot buttons (Camelot PaperDollFrame.xml: Character<Name>Slot),
-- looked up by name with C_PaperDollInfo.GetInventorySlotInfo, as the frame does.
local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
  "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1",
  "MainHand", "SecondaryHand", "Ranged" }

function E.gear()
  local g = { slots = {}, bags = {}, at = C.epoch() }
  local info = C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo
  for _, name in ipairs(SLOTS) do
    local slot = C.try(info, name .. "Slot")
    local it = slot and E.item(C.try(GetInventoryItemLink, "player", slot))
    if it then
      local cur, max = C.try(GetInventoryItemDurability, slot)
      it.dur, it.durMax = plain(cur), plain(max)
      g.slots[name] = it
    end
  end
  local nslots, binfo = C.bagFn("GetContainerNumSlots"), C.bagFn("GetContainerItemInfo")
  for bag = 0, NUM_BAG_SLOTS or 4 do
    for s = 1, (C.try(nslots, bag) or 0) do
      local b = C.try(binfo, bag, s)
      local link = b and plain(b.hyperlink)
      if link and #g.bags < 60 and C.try(C_Item.IsEquippableItem, link) then g.bags[#g.bags + 1] = E.item(link) end
    end
  end
  g.stats = {}
  for i, k in ipairs(STAT) do
    local _, eff = C.try(UnitStat, "player", i)
    g.stats[k] = plain(eff)
  end
  local sp = 0
  for school = 2, 7 do sp = math.max(sp, plain(C.try(GetSpellBonusDamage, school)) or 0) end
  g.stats.spell = sp
  g.ilvl = plain(select(2, C.try(GetAverageItemLevel)))
  g.money = plain(C.try(GetMoney))
  g.spec, g.skills = spec(), skills()
  ns.cdb.gear = g
end

-- ------------------------------------------------- items the game has shown you
-- No public item database has Forever's stats (Forever reworked items under
-- their Classic IDs), so the site's "best in slot" works from what the game
-- itself shows: quest rewards at the quest NPC and items at merchants. Account
-- wide, so every character's travels fill it:
--   SlopLevelerDB.items[itemID]   = E.item() record
--   SlopLevelerDB.quests[questID] = { title, choice = { itemIDs }, reward = { itemIDs }, at }
--   SlopLevelerDB.vendors[itemID] = { { npc, map, x, y, price } ... }
-- Quest frame: GetNumQuestChoices / GetNumQuestRewards / GetQuestItemLink, as
-- Mainline QuestInfo.lua reads them; merchants: GetMerchantNumItems,
-- GetMerchantItemLink, C_MerchantFrame.GetItemInfo (price), as MerchantFrame.lua.

local MAXITEMS = 4000

function E.remember(link)
  if not (link and C_Item and C.try(C_Item.IsEquippableItem, link)) then return nil end
  local it = E.item(link)
  if not it then return nil end
  local items = ns.db.items or {}
  ns.db.items = items
  if not items[it.id] then
    local n = 0
    for _ in pairs(items) do n = n + 1 end
    if n >= MAXITEMS then return it.id end
  end
  -- not cached yet: keep what we have, fill in once the client has it
  if not it.name and not (items[it.id] and items[it.id].name) and C_Timer and C_Timer.After then
    C_Timer.After(1.5, function() local again = E.item(link); if again and again.name then items[it.id] = again end end)
  end
  if it.name or not items[it.id] then items[it.id] = it end
  return it.id
end

function E.questFrame()
  local q = plain(C.try(GetQuestID))
  if not q or q == 0 then return end
  local rec = { title = C.questTitle(q) or plain(C.try(GetTitleText)), choice = {}, reward = {}, at = C.epoch() }
  for kind, count in pairs({ choice = GetNumQuestChoices, reward = GetNumQuestRewards }) do
    for i = 1, (plain(C.try(count)) or 0) do
      local id = E.remember(C.try(GetQuestItemLink, kind, i))
      if id then rec[kind][#rec[kind] + 1] = id end
    end
  end
  if #rec.choice + #rec.reward == 0 then return end
  ns.db.quests = ns.db.quests or {}
  ns.db.quests[q] = rec
end

function E.merchant()
  local n = plain(C.try(GetMerchantNumItems)) or 0
  local npc = plain(C.try(UnitName, "npc"))
  local map, x, y = C.mapPos()
  ns.db.vendors = ns.db.vendors or {}
  for i = 1, math.min(n, 200) do
    local id = E.remember(C.try(GetMerchantItemLink, i))
    if id then
      local info = C_MerchantFrame and C.try(C_MerchantFrame.GetItemInfo, i)
      local list = ns.db.vendors[id] or {}
      ns.db.vendors[id] = list
      local known = false
      for _, v in ipairs(list) do if v.npc == npc then known = true; v.map, v.x, v.y = map, x, y end end
      if not known and #list < 4 then
        list[#list + 1] = { npc = npc, map = map, x = x, y = y, price = info and plain(info.price) }
      end
    end
  end
end

-- Gold over time, for gold per hour: one sample per change, at most every 2 min.
function E.money()
  local m = plain(C.try(GetMoney))
  if not m then return end
  local list = ns.cdb.money or {}
  ns.cdb.money = list
  local last = list[#list]
  local t = C.epoch()
  if last and last[2] == m then return end
  if last and t - last[1] < 120 then last[2] = m; return end
  list[#list + 1] = { t, m }
  while #list > 2000 do table.remove(list, 1) end
end

-- The quest log as the site's Quests tab shows it:
--   SlopLevelerCharDB.questLog = { { q, title, level, zone, done, objs = { { text, have, need, done } } } }
-- C_QuestLog.GetInfo (QuestInfo: title, questID, level, isHeader; a header's
-- title is the zone) and GetQuestObjectives (QuestObjectiveInfo), 1.60.1 export.
function E.questLog()
  local out, zone = {}, nil
  if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
  for i = 1, (C.try(C_QuestLog.GetNumQuestLogEntries) or 0) do
    local info = C.try(C_QuestLog.GetInfo, i)
    if info and info.isHeader then zone = plain(info.title)
    elseif info and plain(info.questID) and info.questID > 0 then
      local objs = {}
      for _, o in ipairs(C.objectives(info.questID)) do
        objs[#objs + 1] = { text = plain(o.text), have = plain(o.numFulfilled), need = plain(o.numRequired), done = plain(o.finished) and true or false }
      end
      out[#out + 1] = { q = info.questID, title = plain(info.title), level = plain(info.level), zone = zone,
        done = C.isComplete(info.questID), objs = objs }
    end
  end
  ns.cdb.questLog = out
end

-- Equipment, bags and the quest log change in bursts (looting, vendoring,
-- kills); save each once it settles.
local function settle(fn)
  local pending = false
  return function()
    if pending then return end
    pending = true
    local run = function() pending = false; fn() end
    if C_Timer and C_Timer.After then C_Timer.After(2, run) else run() end
  end
end
local soon = settle(function() E.gear() end)
ns.On("QUEST_LOG_UPDATE", settle(E.questLog))

ns.On("PLAYER_ENTERING_WORLD", function() E.recordMaps(); E.snapshot(); E.money() end)
ns.On("ZONE_CHANGED_NEW_AREA", E.recordMaps)
ns.On("PLAYER_LEVEL_UP", E.snapshot)
ns.On("SKILL_LINES_CHANGED", E.snapshot)
ns.On("PLAYER_EQUIPMENT_CHANGED", soon)
ns.On("BAG_UPDATE_DELAYED", soon)
ns.On("ACTIVE_TALENT_GROUP_CHANGED", soon)
ns.On("PLAYER_TALENT_UPDATE", soon)
ns.On("PLAYER_MONEY", E.money)
-- Quests this character has turned in, so the site never suggests a reward
-- from one that is done: SlopLevelerCharDB.turnedIn[questID] = time.
ns.On("QUEST_TURNED_IN", function(q)
  q = plain(q)
  if not q then return end
  ns.cdb.turnedIn = ns.cdb.turnedIn or {}
  ns.cdb.turnedIn[q] = C.epoch()
end)
ns.On("QUEST_DETAIL", E.questFrame, true) -- before Assist accepts and the frame closes
ns.On("QUEST_COMPLETE", E.questFrame, true)
ns.On("MERCHANT_SHOW", E.merchant)
ns.On("PLAYER_LOGOUT", function() E.snapshot(); E.money(); E.questLog() end)
ns.On("PLAYER_LEAVING_WORLD", E.snapshot)
