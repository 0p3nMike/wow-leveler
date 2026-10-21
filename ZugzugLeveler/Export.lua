-- Export.lua -- what the companion site (companion/) needs that nothing else saves.
--
-- Addons cannot talk to anything outside the game; the site reads the
-- SavedVariables files the game writes on /reload and logout. This adds:
--   ZugzugLevelerDB.maps[uiMapID]   = { name, cont, x0, y0, x1, y1 }
--       where a map sits in the world: C_Map.GetWorldPosFromMapPos at the
--       map's corners (0,0) and (1,1). With it the site can put recorded paths
--       (map x/y) and route stops (world x/y) on one canvas. Your map and the
--       ones above it, recorded as you travel.
--   ZugzugLevelerCharDB.char        = name, realm, class, race, faction, level, xp, xpMax,
--                                   rested, map/x/y (where you were), at
--   ZugzugLevelerCharDB.profSnap    = your professions and skill (Professions.lua's P.mine())
--   ZugzugLevelerCharDB.gear        = what you wear and carry, for the site's Gear tab:
--       slots[slot name: "Head", "Finger0", "MainHand" ...] / bags[n] =
--         { id, name, q, ilvl, req, type, sub, loc, icon, sell, cid, sc, bind, stats, tip, dur, durMax }
--       spec = { cur, trees = { { name, role, points } } }, stats = { str, agi, sta, int, spi, spell },
--       skills = { { name, rank, max, head } } (armor and weapon skills say what you can wear),
--       money, ilvl
--   ZugzugLevelerCharDB.money       = { { t, copper } ... }: gold over time (one sample per change, 2 min apart)
--   ZugzugLevelerCharDB.turnedIn    = { [questID] = time }: quests this character turned in
--   ZugzugLevelerCharDB.questLog    = the quest log with objectives (E.questLog)
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
  -- While the game is closing (PLAYER_LOGOUT on quitting just after a load)
  -- it reports XP 0 of 0, no gear and no professions: saving that would
  -- replace the last good snapshot with an empty one (seen 2026-10-18: level
  -- 14, XP 0/0, all slots empty). No XP bar to read: keep what is saved.
  if not max or max <= 0 or not lvl or lvl <= 0 then return end
  local _, class = C.try(UnitClass, "player")
  -- raceID and sex (2 male, 3 female) pick the 3D model on the companion page
  local _, race, raceID = C.try(UnitRace, "player")
  local map, x, y = C.mapPos()
  -- Forever names have a surname: UnitName gives (first, surname), which
  -- Blizzard's Camelot NameUtil.FormatUnitNameForDisplay joins with a space
  local first, surname = C.try(UnitName, "player")
  ns.cdb.char = {
    name = first, surname = type(surname) == "string" and surname ~= "" and surname or nil,
    realm = C.try(GetRealmName), class = class, race = race,
    raceID = raceID, sex = C.try(UnitSex, "player"),
    faction = C.try(UnitFactionGroup, "player"), level = lvl, xp = cur, xpMax = max, rested = rested,
    map = map, x = x, y = y, at = C.epoch(),
    -- the game, and whether this character plays hardcore (a Hardcore realm,
    -- a RestedXP hardcore route, or the option): the page then defaults the
    -- Gear tab to RestedXP's Hardcore weights and says so
    game = C.game(), hcRealm = C.hardcoreRealm() or nil,
    hardcore = (ns.Engine and ns.Engine.hardcore()) or nil,
  }
  if ns.Prof then ns.cdb.profSnap = ns.Prof.mine() end
  E.avail()
  E.gear()
end

-- Quests you could pick up right now (QuestInfo.lua): the page pins their
-- givers and weighs their rewards. Their names when the game has them
-- (C.questTitle), and their reward items looked up (E.lookupRewards).
--   ZugzugLevelerCharDB.avail = { questID ... }, availNames = { [questID] = title }
function E.avail()
  if not ns.QInfo then return end
  ns.cdb.avail = ns.QInfo.availableAll(600)
  local names = {}
  for _, q in ipairs(ns.cdb.avail) do names[q] = C.questTitle(q) end
  ns.cdb.availNames = names
  E.lookupRewards()
end

-- The reward items (AllTheThings' rw, data/Quests*.lua) of the quests you can
-- take or have, asked of the game itself: C_Item.GetItemInfo(id) answers from
-- the client's cache or asks the server, which answers with
-- GET_ITEM_INFO_RECEIVED(itemID, success) (5.5.4 and 1.60.1 event lists).
-- Equippable ones are remembered (E.remember) with the game's own stats and
-- required level, so the page can say which quest gives an upgrade before you
-- ever see its reward window. Up to 80 asks per pass; each item once a session.
local asked = {}
function E.lookupRewards()
  if not (ns.QInfo and C_Item) then return end
  local items, n = ns.db.items or {}, 0
  local qs = {}
  for _, q in ipairs(ns.cdb.avail or {}) do qs[#qs + 1] = q end
  for _, q in ipairs(C.questLogIDs()) do qs[#qs + 1] = q end
  for _, q in ipairs(qs) do
    local e = ns.QInfo.get(q)
    for _, id in ipairs(e and e.rw or {}) do
      if n >= 80 then return end
      if not items[id] and asked[id] == nil then
        n = n + 1
        local _, link = C.try(C_Item.GetItemInfo, id)
        if link then asked[id] = true; E.remember(link) else asked[id] = false end -- false: the server answers later
      end
    end
  end
end
ns.On("GET_ITEM_INFO_RECEIVED", function(id, ok)
  if asked[id] ~= false then return end
  asked[id] = true
  if not ok then return end
  local _, link = C.try(C_Item.GetItemInfo, id)
  if link then E.remember(link) end
end)

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
  for k, v in pairs(C.try(C_Item.GetItemStats, link) or C.try(GetItemStats, link) or {}) do
    if type(k) == "string" and type(plain(v)) == "number" then stats[k] = v end
  end
  return { id = id, name = plain(name), q = plain(q), ilvl = plain(ilvl), req = plain(req), type = plain(typ),
    sub = plain(sub), loc = plain(loc), icon = plain(icon), sell = plain(sell), stats = stats, tip = E.tipLines(link), tt = E.tipFull(link),
    cid = plain(cid), sc = plain(sc), bind = plain(bind) } -- classID 2 weapon / 4 armor, subclassID (Enum.ItemWeaponSubclass / ItemArmorSubclass)
end

-- The tooltip's lines that carry numbers ("left|right"). GetItemStats has no
-- weapon speed and lumps every spell school together, so the site reads those
-- from here, as RestedXP's ItemUpgrades.lua does. C_TooltipInfo.GetHyperlink
-- returns { lines = { { leftText, rightText } } } (Blizzard_SharedXMLGame
-- TooltipDataHandler.lua iterates tooltipData.lines the same way).
function E.tipLines(link)
  local data = C.tooltip(link)
  local out = {}
  for _, l in ipairs(type(data) == "table" and data.lines or {}) do
    local left, right = plain(l.leftText), plain(l.rightText)
    local s = (type(left) == "string" and left or "") .. (type(right) == "string" and right ~= "" and "|" .. right or "")
    if s:find("%d") and #out < 16 then out[#out + 1] = s end
  end
  return out
end

-- The whole tooltip as the game draws it, for the site's item tooltips:
-- "leftHex\tleft\trightHex\tright" per line. Colours as TooltipDataHandler.lua
-- (Blizzard_SharedXMLGame) reads them: lineData.leftColor / rightColor, a
-- colour with GetRGB, NORMAL_FONT_COLOR (ffd100) when absent.
local function hex(c)
  if type(c) ~= "table" or not c.GetRGB then return "ffd100" end
  local r, g, b = C.try(c.GetRGB, c)
  if type(plain(r)) ~= "number" then return "ffd100" end
  return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
function E.tipFull(link)
  local data = C.tooltip(link)
  local out = {}
  for _, l in ipairs(type(data) == "table" and data.lines or {}) do
    local left, right = plain(l.leftText), plain(l.rightText)
    left = type(left) == "string" and left or ""
    right = type(right) == "string" and right or ""
    if (left ~= "" or right ~= "") and #out < 30 then
      out[#out + 1] = table.concat({ hex(l.leftColor), (left:gsub("\t", " ")), hex(l.rightColor), (right:gsub("\t", " ")) }, "\t")
    end
  end
  return out
end

local function spec()
  local S = C_SpecializationInfo
  if not S then return nil end
  local _, _, classID = C.try(UnitClass, "player")
  local out = { cur = plain(C.try(S.GetSpecialization)), trees = {} }
  local n = classID and C.try(S.GetNumSpecializationsForClassID, classID) or 0
  local sex = C.try(UnitSex, "player")
  for i = 1, n do
    -- the arguments Camelot's PaperDollFrame_SetLevel passes; before a spec can
    -- be chosen the name comes back empty
    local id, name, _, _, role, _, points = C.try(S.GetSpecializationInfo, i, false, false, nil, sex)
    if not plain(name) then
      -- Mists saved an empty spec at login (talent data loads later): the
      -- class's specs by number, GetSpecializationInfoForClassID(classID, i)
      -- -> id, name, description, icon, role (in both 1.60.1 and 5.5.4 lists)
      local id2, name2, _, _, role2 = C.try(GetSpecializationInfoForClassID, classID, i)
      id, name, role = id or id2, name2, role or role2
    end
    out.trees[i] = { name = plain(name), role = plain(role), points = plain(points) or 0, id = plain(id) }
  end
  -- Mists: the column picked in each of the six talent tiers (0 = none) and the
  -- glyphs' spells (GetTalentTierInfo / GetGlyphSocketInfo, as Talents.lua reads them)
  if C.game() == "mists" and GetTalentTierInfo then
    local grp = C.try(S.GetActiveSpecGroup) or 1
    out.tiers, out.glyphs = {}, {}
    for tier = 1, 6 do
      local _, sel = C.try(GetTalentTierInfo, tier, grp, false, "player")
      out.tiers[tier] = plain(sel) or 0
    end
    for i = 1, (C.try(GetNumGlyphSockets) or 0) do
      local _, _, _, spell = C.try(GetGlyphSocketInfo, i, grp)
      if plain(spell) then out.glyphs[#out.glyphs + 1] = spell end
    end
  end
  return out
end

-- Armor and weapon skills (and the rest of the skill list), with the header
-- each sits under, so the site knows what this character can wear.
local function skills()
  local S, out, head = C_SkillInfo, {}, nil
  if not (S and S.GetNumSkillLines) and GetNumSkillLines then
    -- Mists: skillName, isHeader, isExpanded, skillRank, numTempPoints,
    -- skillModifier, skillMaxRank (Classic SkillFrame.lua:26)
    for i = 1, (C.try(GetNumSkillLines) or 0) do
      local name, isHeader, _, rank, _, _, max = C.try(GetSkillLineInfo, i)
      if isHeader then head = plain(name)
      elseif plain(name) then out[#out + 1] = { name = name, rank = plain(rank), max = plain(max), head = head } end
    end
    return out
  end
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
-- looked up by name with C_PaperDollInfo.GetInventorySlotInfo, as the frame does
-- (GetInventorySlotInfo on Mists, Cata PaperDollFrame.lua:2476).
local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
  "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1",
  "MainHand", "SecondaryHand", "Ranged" }

-- The look a slot shows when it is transmogged, for the page's 3D character:
-- C_Transmog.GetSlotVisualInfo({ slotID, type = 0 Appearance, modification =
-- 0 Main }) (the table TransmogLocationMixin:GetData builds, Blizzard_TransmogShared
-- .lua:604) -> appliedSourceID, 0 when not transmogged (Constants.Transmog.NoTransmogID);
-- C_TransmogCollection.GetSourceInfo(source) -> itemID. The Collections window
-- reads it away from the transmogrifier too. nil: the item's own look.
local function appearance(slot)
  if not (C_Transmog and C_Transmog.GetSlotVisualInfo) then return nil end
  local v = C.try(C_Transmog.GetSlotVisualInfo, { slotID = slot, type = 0, modification = 0 })
  if type(v) ~= "table" then return nil end
  if plain(v.isHideVisual) then return { hidden = true } end
  local src = plain(v.appliedSourceID)
  if not src or src == 0 or src == plain(v.baseSourceID) then return nil end
  local info = C_TransmogCollection and C.try(C_TransmogCollection.GetSourceInfo, src)
  local id = type(info) == "table" and plain(info.itemID)
  if not id then return nil end
  return { id = id, name = plain(info.name), src = src }
end

-- Mists of Pandaria Classic keeps transmog in outfits (C_TransmogOutfitInfo,
-- the 5.5.4 export), and GetSlotVisualInfo above can say "none" while you wear
-- one. The outfit slots are read the way Blizzard's transmog window does
-- (Blizzard_TransmogTemplates.lua:280-285): GetViewedOutfitSlotInfo(outfit slot,
-- 0 Appearance, weapon option) -> displayType (0 unassigned, 1 assigned, 2 your
-- gear's own look, 3 hidden, 4 disabled), transmogID = a source;
-- GetSourceItemID(source) -> itemID. Outfit slot from the inventory slot with
-- GetTransmogOutfitSlotFromInventorySlot(slot - 1), as TransmogUtil.CreateTransmogLocation.
-- "Viewed" is the outfit the transmog window shows, which it sets to the one you
-- wear when it opens (Blizzard_Transmog.lua:516): read at the window only.
local function outfitLook(slot)
  local O = C_TransmogOutfitInfo
  if not (O and O.GetViewedOutfitSlotInfo and O.GetTransmogOutfitSlotFromInventorySlot) then return nil end
  local ts = plain(C.try(O.GetTransmogOutfitSlotFromInventorySlot, slot - 1))
  if not ts then return nil end
  local opt = plain(C.try(O.GetEquippedSlotOptionFromTransmogSlot, ts)) or 0
  local v = C.try(O.GetViewedOutfitSlotInfo, ts, 0, opt)
  if type(v) ~= "table" then return nil end
  local shown = plain(v.displayType)
  if shown == 3 then return { hidden = true } end
  if shown ~= 1 then return false end -- your gear's own look
  local src = plain(v.transmogID)
  local id = src and src ~= 0 and plain(C.try(C_TransmogCollection.GetSourceItemID, src))
  if not id then return false end
  return { id = id, name = plain(C.try(C_Item.GetItemNameByID, id)), src = src }
end

-- Your transmog, read at the transmogrifier:
--   ZugzugLevelerCharDB.tmog = { at, slots = { Head = { id, name, src } | { hidden = true } | false } }
-- false = that slot shows the item you wear. The page draws these looks.
function E.tmog(quiet)
  local info = (C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo) or GetInventorySlotInfo
  local out, n = {}, 0
  for _, name in ipairs(SLOTS) do
    local slot = C.try(info, name .. "Slot")
    -- whichever way reports a transmog (outfit window or the older wardrobe);
    -- false when one says "your own look"; nil when neither answers
    local o = slot and outfitLook(slot)
    local a = slot and appearance(slot)
    local look = (type(o) == "table" and o) or a or o
    if look ~= nil then
      out[name] = look
      if look then n = n + 1 end
    end
  end
  if not next(out) then return end
  ns.cdb.tmog = { at = C.epoch(), slots = out }
  if not quiet then C.print("your transmog is saved for the companion page (%d slots). Sync or /reload to show it.", n) end
end
local function atTransmog() return C_Transmog and C.try(C_Transmog.IsAtTransmogNPC) end
-- Mists opens transmog two ways (Mists UIParent.lua:1152: TRANSMOGRIFY_OPEN shows
-- the older wardrobe; PlayerInteractionFrameManager.lua:117: interaction type 24,
-- Transmogrifier, shows the outfit window). Read after the window has picked the
-- outfit you wear, and again a moment later in case it was still loading.
local function readSoon()
  if not (C_Timer and C_Timer.After) then E.tmog(); return end
  C_Timer.After(0.5, function() E.tmog(true) end)
  C_Timer.After(2, function() E.tmog() end)
end
ns.On("TRANSMOGRIFY_OPEN", readSoon)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
  local want = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Transmogrifier or 24
  if kind == want then readSoon() end
end)
ns.On("TRANSMOGRIFY_SUCCESS", function() if atTransmog() then E.tmog(true) end end)
ns.On("TRANSMOG_DISPLAYED_OUTFIT_CHANGED", function() if atTransmog() then E.tmog(true) end end)

-- /zug tmog: what the game says about each slot's look, both ways, to check the above
function E.tmogDebug()
  local info = (C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo) or GetInventorySlotInfo
  local O = C_TransmogOutfitInfo
  C.print("transmog: at the transmogrifier %s, active outfit %s, viewed outfit %s", tostring(atTransmog()),
    tostring(O and C.try(O.GetActiveOutfitID)), tostring(O and C.try(O.GetCurrentlyViewedOutfitID)))
  for _, name in ipairs(SLOTS) do
    local slot = C.try(info, name .. "Slot")
    if slot then
      local v = C_Transmog and C.try(C_Transmog.GetSlotVisualInfo, { slotID = slot, type = 0, modification = 0 })
      local ts = O and plain(C.try(O.GetTransmogOutfitSlotFromInventorySlot, slot - 1))
      local w = ts and C.try(O.GetViewedOutfitSlotInfo, ts, 0, plain(C.try(O.GetEquippedSlotOptionFromTransmogSlot, ts)) or 0)
      C.print("  %s: visual base %s applied %s hidden %s | outfit slot %s shown %s transmog %s", name,
        tostring(type(v) == "table" and plain(v.baseSourceID)), tostring(type(v) == "table" and plain(v.appliedSourceID)),
        tostring(type(v) == "table" and plain(v.isHideVisual)), tostring(ts),
        tostring(type(w) == "table" and plain(w.displayType)), tostring(type(w) == "table" and plain(w.transmogID)))
    end
  end
end

-- Mists: your ratings and what they give, as the character frame works them
-- out (Cata/PaperDollFrame.lua: GetCombatRatingBonus(CR_HIT_SPELL) +
-- GetSpellHitModifier() for spell hit, and so on). CR_* are the client's own
-- globals (CR_HIT_SPELL = 8, CR_HASTE_SPELL = 20, CR_MASTERY = 26 ...).
--   { hit = { rating, pct }, crit, haste, mastery, expertise, meleeHit, meleeCrit, meleeHaste }
function E.ratings()
  local function rated(cr) return cr and plain(C.try(GetCombatRating, cr)) or nil end
  local function bonus(cr) return cr and plain(C.try(GetCombatRatingBonus, cr)) or nil end
  local crit = 0
  for school = 2, 7 do crit = math.max(crit, plain(C.try(GetSpellCritChance, school)) or 0) end
  local out = {
    hit = { rated(CR_HIT_SPELL), (bonus(CR_HIT_SPELL) or 0) + (plain(C.try(GetSpellHitModifier)) or 0) },
    crit = { rated(CR_CRIT_SPELL), crit },
    haste = { rated(CR_HASTE_SPELL), plain(C.try(UnitSpellHaste, "player")) },
    mastery = { rated(CR_MASTERY), plain(C.try(GetMasteryEffect)) },
    expertise = { rated(CR_EXPERTISE), plain(C.try(GetExpertise)) },
    meleeHit = { rated(CR_HIT_MELEE), (bonus(CR_HIT_MELEE) or 0) + (plain(C.try(GetHitModifier)) or 0) },
    meleeCrit = { rated(CR_CRIT_MELEE), plain(C.try(GetCritChance)) },
    meleeHaste = { rated(CR_HASTE_MELEE), plain(C.try(GetMeleeHaste)) },
  }
  return out
end

function E.gear()
  local g = { slots = {}, bags = {}, at = C.epoch() }
  local info = (C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo) or GetInventorySlotInfo
  for _, name in ipairs(SLOTS) do
    local slot = C.try(info, name .. "Slot")
    local it = slot and E.item(C.try(GetInventoryItemLink, "player", slot))
    if it then
      local cur, max = C.try(GetInventoryItemDurability, slot)
      it.dur, it.durMax = plain(cur), plain(max)
      it.tmog = appearance(slot)
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
  if C.game() == "mists" then g.stats.r = E.ratings() end
  g.ilvl = plain(select(2, C.try(GetAverageItemLevel)))
  g.money = plain(C.try(GetMoney))
  g.spec, g.skills = spec(), skills()
  -- nothing worn at all, where something was: the game not answering (it is
  -- loading or closing), not you undressing: keep the last good record
  local old = ns.cdb.gear
  if not next(g.slots) and old and old.slots and next(old.slots) then return end
  ns.cdb.gear = g
end

-- ------------------------------------------------- items the game has shown you
-- No public item database has Forever's stats (Forever reworked items under
-- their Classic IDs), so the site's "best in slot" works from what the game
-- itself shows: quest rewards at the quest NPC and items at merchants. Account
-- wide, so every character's travels fill it:
--   ZugzugLevelerDB.items[itemID]   = E.item() record
--   ZugzugLevelerDB.quests[questID] = { title, choice = { itemIDs }, reward = { itemIDs }, at }
--   ZugzugLevelerDB.vendors[itemID] = { { npc, map, x, y, price } ... }
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

-- Your look (skin, face, hair, ...), for the companion page's 3D character.
-- The game tells it at a barber: C_BarberShop.GetAvailableCustomizations()
-- (BarberShopDocumentation, 1.60.1 export) lists every option with the choice
-- you wear now (currentChoiceIndex), which is what Blizzard's barber window
-- reads to show you (Blizzard_BarberShopUI.lua). Sitting down is enough;
-- nothing is changed. Read again when a new look is bought. The option and
-- choice numbers are the game's ChrCustomization ones, the same the page's
-- model viewer takes. A druid's forms are categories of their own: skipped.
--   ZugzugLevelerCharDB.look = { at, options = { { o = optionID, c = choiceID, name, choice } } }
function E.look()
  local cats = C_BarberShop and C.try(C_BarberShop.GetAvailableCustomizations)
  if type(cats) ~= "table" or #cats == 0 then return end
  local out = {}
  for _, cat in ipairs(cats) do
    if not plain(cat.spellShapeshiftFormID) then
      for _, o in ipairs(cat.options or {}) do
        local k = plain(o.currentChoiceIndex)
        local ch = k and o.choices and o.choices[k]
        if ch and plain(ch.id) and plain(o.id) then
          out[#out + 1] = { o = o.id, c = ch.id, name = plain(o.name), choice = plain(ch.name) }
        end
      end
    end
  end
  if #out == 0 then return end
  ns.cdb.look = { at = C.epoch(), options = out }
  C.print("your look is saved for the companion page's 3D character (%d features). Sync or /reload to show it.", #out)
end
ns.On("BARBER_SHOP_OPEN", function()
  -- after the barber window has built the character (its own code warns that an
  -- early call returns nothing)
  if C_Timer and C_Timer.After then C_Timer.After(0.5, E.look) else E.look() end
end)
ns.On("BARBER_SHOP_APPEARANCE_APPLIED", function() E.look() end)

-- A quest's own words when a quest giver offers it, before it is in your log
-- (GetQuestText / GetObjectiveText at QUEST_DETAIL, as Blizzard's QuestInfo.lua
-- reads them), with who offered it and where: the companion page shows them
-- for quests you have not picked up yet, with or without Wowhead.
--   ZugzugLevelerDB.questText[questID] = { title, desc, ask, npc, map, x, y, at }
local QUEST_TEXT_KEEP = 400
function E.questText()
  local q = plain(C.try(GetQuestID))
  if not q or q == 0 then return end
  local desc, ask = plain(C.try(GetQuestText)), plain(C.try(GetObjectiveText))
  if type(desc) ~= "string" and type(ask) ~= "string" then return end
  local map, x, y = C.mapPos()
  ns.db.questText = ns.db.questText or {}
  local t = ns.db.questText
  t[q] = { title = C.questTitle(q) or plain(C.try(GetTitleText)), at = C.epoch(),
    desc = type(desc) == "string" and desc ~= "" and desc:sub(1, 600) or nil,
    ask = type(ask) == "string" and ask ~= "" and ask:sub(1, 400) or nil,
    npc = plain(C.try(UnitName, "npc")), map = map, x = x, y = y }
  -- keep the newest QUEST_TEXT_KEEP
  local n, oldest, oldestAt = 0, nil, math.huge
  for id, rec in pairs(t) do
    n = n + 1
    if (rec.at or 0) < oldestAt then oldest, oldestAt = id, rec.at or 0 end
  end
  if n > QUEST_TEXT_KEEP and oldest then t[oldest] = nil end
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
      if not info and GetMerchantItemInfo then -- Mists: name, texture, price, ... (TBC MerchantFrame.lua:203)
        local _, _, price = C.try(GetMerchantItemInfo, i)
        info = { price = price }
      end
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
--   ZugzugLevelerCharDB.questLog = { { q, title, level, zone, done, objs = { { text, have, need, done } } } }
-- C.questLog rows (title, questID, level, isHeader; a header's title is the
-- zone) and GetQuestObjectives (QuestObjectiveInfo), 1.60.1 export.
function E.questLog()
  local out, zone = {}, nil
  for _, info in ipairs(C.questLog()) do
    local i = info.i
    if info.isHeader then zone = plain(info.title)
    elseif info and plain(info.questID) and info.questID > 0 then
      local objs = {}
      for _, o in ipairs(C.objectives(info.questID)) do
        objs[#objs + 1] = { text = plain(o.text), have = plain(o.numFulfilled), need = plain(o.numRequired), done = plain(o.finished) and true or false }
      end
      -- the quest's own words, as the game's quest log shows them
      -- (GetQuestLogQuestText(questLogIndex): description, objectives text;
      -- Blizzard_UIPanels_Game QuestMapFrame.lua reads it the same way)
      local desc, ask = C.questText(i)
      desc, ask = plain(desc), plain(ask)
      out[#out + 1] = { q = info.questID, title = plain(info.title), level = plain(info.level), zone = zone,
        done = C.isComplete(info.questID), objs = objs,
        ask = type(ask) == "string" and ask ~= "" and ask:sub(1, 400) or nil,
        desc = type(desc) == "string" and desc ~= "" and desc:sub(1, 600) or nil }
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
ns.On("PLAYER_SPECIALIZATION_CHANGED", soon)
-- turning in or picking up a quest changes what you can take next
local availSoon = settle(function() E.avail() end)
ns.On("QUEST_ACCEPTED", availSoon)
ns.On("PLAYER_MONEY", E.money)
-- Quests this character has turned in, so the site never suggests a reward
-- from one that is done: ZugzugLevelerCharDB.turnedIn[questID] = time.
ns.On("QUEST_TURNED_IN", function(q)
  q = plain(q)
  if not q then return end
  ns.cdb.turnedIn = ns.cdb.turnedIn or {}
  ns.cdb.turnedIn[q] = C.epoch()
  availSoon()
end)
ns.On("QUEST_DETAIL", E.questFrame, true) -- before Assist accepts and the frame closes
ns.On("QUEST_DETAIL", E.questText, true)
ns.On("QUEST_COMPLETE", E.questFrame, true)
ns.On("MERCHANT_SHOW", E.merchant)
ns.On("PLAYER_LOGOUT", function() E.snapshot(); E.money(); E.questLog() end)
ns.On("PLAYER_LEAVING_WORLD", E.snapshot)
