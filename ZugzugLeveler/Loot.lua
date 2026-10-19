-- Loot.lua -- what dropped for you, per creature: the companion page's "your
-- drop rates", the way Wowhead gets its numbers (AllTheThings has no rates).
--
-- At LOOT_OPENED, each slot: GetNumLootItems, GetLootSlotInfo, GetLootSlotLink,
-- read as Blizzard's LootFrame.lua (1.60.1 export) reads them. Where it came
-- from: GetLootSourceInfo(slot) -> guid, quantity[, guid, quantity ...] when the
-- client has it (a global the UI export does not call: confirm in game),
-- otherwise the dead creature you have targeted. Each corpse counts once (its
-- GUID), so opening the same loot window again adds nothing.
--   ZugzugLevelerDB.loot[npcID] = { name, n = corpses looted,
--     items = { [itemID] = { c = corpses it dropped from, q = total quantity, name } } }

local _, ns = ...
local C = ns.C

local L = {}
ns.Loot = L

local KEEP_NPCS = 500
local seen, seenList = {}, {} -- corpse GUIDs already counted (the last 200)

local function ok(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

function L.npcOf(guid)
  if not (ok(guid) and type(guid) == "string" and guid:find("^Creature%-")) then return nil end
  return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

local function itemOf(link)
  if not (ok(link) and type(link) == "string") then return nil end
  return tonumber(link:match("|Hitem:(%d+)") or link:match("^item:(%d+)"))
end

-- the slot's sources: { {guid, quantity}, ... }
local function sources(slot, fallback)
  local out = {}
  if GetLootSourceInfo then
    local r = { C.try(GetLootSourceInfo, slot) }
    for k = 1, #r, 2 do
      if ok(r[k]) and type(r[k]) == "string" then out[#out + 1] = { r[k], tonumber(r[k + 1]) or 1 } end
    end
  end
  if #out == 0 and fallback then out[1] = { fallback, nil } end
  return out
end

function L.read()
  local db = ns.db
  db.loot = db.loot or {}
  local tgt = C.try(UnitGUID, "target")
  local fallback = (C.try(UnitIsDead, "target") and L.npcOf(tgt)) and tgt or nil
  local tgtName = C.try(UnitName, "target")
  local fresh = {} -- corpses first seen in this window
  local drops = {} -- guid -> { [itemID] = quantity }
  local names = {} -- itemID -> name (GetLootSlotInfo's second value)
  for slot = 1, (C.try(GetNumLootItems) or 0) do
    local _, itemName, quantity, currencyID, _, _, _, _, _, isCoin = C.try(GetLootSlotInfo, slot)
    local id = not isCoin and not currencyID and itemOf(C.try(GetLootSlotLink, slot))
    if id then
      if ok(itemName) and type(itemName) == "string" then names[id] = itemName end
      local src = sources(slot, fallback)
      for _, s in ipairs(src) do
        local guid = s[1]
        if L.npcOf(guid) and not seen[guid] then
          fresh[guid] = true
          drops[guid] = drops[guid] or {}
          drops[guid][id] = (drops[guid][id] or 0) + (s[2] or (ok(quantity) and quantity) or 1)
        end
      end
    end
  end
  -- a corpse with nothing but coin still counts as looted: the target, if it is one
  if fallback and not seen[fallback] then fresh[fallback] = true end
  for guid in pairs(fresh) do
    local npc = L.npcOf(guid)
    local rec = db.loot[npc]
    if not rec then
      local n = 0
      for _ in pairs(db.loot) do n = n + 1 end
      if n >= KEEP_NPCS then rec = nil else rec = { n = 0, items = {} }; db.loot[npc] = rec end
    end
    if rec then
      rec.n = rec.n + 1
      if guid == tgt and ok(tgtName) and type(tgtName) == "string" then rec.name = tgtName end
      for id, q in pairs(drops[guid] or {}) do
        local e = rec.items[id] or { c = 0, q = 0 }
        rec.items[id] = e
        e.c, e.q = e.c + 1, e.q + q
        e.name = e.name or names[id]
      end
    end
    seen[guid] = true
    seenList[#seenList + 1] = guid
    if #seenList > 200 then seen[table.remove(seenList, 1)] = nil end
  end
end

ns.On("LOOT_OPENED", function() L.read() end)
