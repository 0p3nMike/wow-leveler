-- Professions.lua -- what to craft or gather next, what it costs, when to train.
--
-- Your professions and skill come from the game anywhere (GetProfessions +
-- GetProfessionInfo: name, rank, maxRank, ..., skillLine -- the same calls
-- Forever's spellbook makes, Blizzard_ProfessionsBook/Camelot).
-- The plan comes from data/Professions.lua (ProfessionLevelingGuide, MIT):
-- classic 1-300 steps per profession, trainers, item IDs. For each profession:
--   crafting   the step you are in: "craft ~13 Bolt of Woolen Cloth (to 100)",
--              and the materials for the rest of it vs what is in your bags.
--              "~" because it assumes one skill-up per craft (true while the
--              recipe is orange; yellow and green give fewer).
--   gathering  what to gather and where, for your faction.
--   capped     skill at the rank's maximum: which trainer, and /lev prof way
--              puts the arrow on them.
-- In the profession window the game itself says which recipes still give
-- skill-ups (C_TradeSkillUI.GetRecipeInfo -> relativeDifficulty: 0 orange,
-- 1 yellow; GetCraftableCount): the ones you can make right now are listed.
-- Forever's NEW recipes are not in the 1-300 plan; the in-window list covers
-- them because it reads the game.

local _, ns = ...
local C = ns.C

local P = {}
ns.Prof = P

local function data() return ns.ProfData or { guides = {}, trainers = {}, items = {} } end
local function on() return ns.db.prof ~= false end

-- { name, rank, max, skillLine } for each profession you have.
function P.mine()
  local out = {}
  if not GetProfessions then return out end
  local idx = { C.try(GetProfessions) }
  for k = 1, 5 do
    local i = idx[k]
    if i then
      local name, _, rank, max, _, _, skillLine = C.try(GetProfessionInfo, i)
      if name then out[#out + 1] = { name = name, rank = rank or 0, max = max or 0, skillLine = skillLine } end
    end
  end
  return out
end

function P.step(name, rank)
  for _, s in ipairs(data().guides[name] or {}) do
    if rank >= s[1] and rank < s[2] then return s end
  end
end

function P.have(itemName)
  local id = data().items[itemName:lower()]
  if not id or not (C_Item and C_Item.GetItemCount) then return nil end
  return C.try(C_Item.GetItemCount, id) or 0
end

-- Materials for the rest of a crafting step: { {need, name, have}, ... }
function P.needs(s, rank)
  local crafts = math.max(s[2] - rank, 0)
  local out = {}
  for _, m in ipairs(s.mats or {}) do
    out[#out + 1] = { m[1] * crafts, m[2], P.have(m[2]) }
  end
  return out, crafts
end

-- The trainer tier for a skill cap: the one whose "(lo-hi)" range holds it.
function P.trainer(name, max)
  local best
  for _, t in ipairs(data().trainers[name] or {}) do
    local lo, hi = t.rank:match("%((%d+)%-(%d+)%)")
    lo, hi = tonumber(lo), tonumber(hi)
    if not lo then best = best or t
    elseif max >= lo and max < hi then return t end
  end
  return best
end

local function faction() return C.try(UnitFactionGroup, "player") end

-- One or two lines per profession for the window.
function P.lines()
  if not on() then return {} end
  local rows = {}
  for _, p in ipairs(P.mine()) do
    local head = ("|cffc080ff%s|r %d/%d"):format(p.name, p.rank, p.max)
    local s = P.step(p.name, p.rank)
    if p.max > 0 and p.rank >= p.max and p.max < 300 then
      local t = P.trainer(p.name, p.max)
      rows[#rows + 1] = head .. "  |cffffd100train the next rank|r" .. (t and " |cff999999/lev prof way|r" or "")
    elseif s and s.gather then
      local f = faction()
      local zones = (f == "Alliance" and s.a) or (f == "Horde" and s.h) or s.both or s.a or s.h or ""
      rows[#rows + 1] = ("%s  gather %s |cff999999(%s)|r"):format(head, s.gather, zones)
    elseif s then
      local needs, crafts = P.needs(s, p.rank)
      local parts = {}
      for _, n in ipairs(needs) do
        local col = (n[3] and n[3] >= n[1]) and "ff60ff60" or "ffff8080"
        parts[#parts + 1] = ("|c%s%d %s%s|r"):format(col, n[1], n[2], n[3] and ("/" .. n[3]) or "")
      end
      rows[#rows + 1] = ("%s  craft ~%d %s (to %d)"):format(head, crafts, s.item, s[2])
      if #parts > 0 then rows[#rows + 1] = "    |cff999999need|r " .. table.concat(parts, ", ") end
    end
  end
  return rows
end

-- /lev prof way: the arrow to the trainer you need (first capped profession)
function P.wayToTrainer()
  local f = faction()
  for _, p in ipairs(P.mine()) do
    if p.max > 0 and p.rank >= p.max and p.max < 300 then
      local t = P.trainer(p.name, p.max)
      local at = t and ((f == "Alliance" and t.a) or (f == "Horde" and t.h))
      if at then
        ns.Way.way(at[1], at[2], at[3], p.name .. " trainer")
        C.print("%s trainer: %s", p.name, t.where)
        return true
      end
    end
  end
  C.print("no profession is at its skill cap")
  return false
end

-- ------------------------------------------------------- profession window

P.canSkill = {} -- recipes in the open profession window that give skill-ups now

function P.scanWindow()
  P.canSkill = {}
  if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo) then return end
  local ids = C.try(C_TradeSkillUI.GetAllRecipeIDs) or C.try(C_TradeSkillUI.GetFilteredRecipeIDs) or {}
  for _, id in ipairs(ids) do
    local info = C.try(C_TradeSkillUI.GetRecipeInfo, id)
    if info and info.learned and info.relativeDifficulty and info.relativeDifficulty <= 1 then
      local n = C.try(C_TradeSkillUI.GetCraftableCount, id) or 0
      if n > 0 then
        P.canSkill[#P.canSkill + 1] = { name = info.name, orange = info.relativeDifficulty == 0, n = n }
      end
    end
  end
  table.sort(P.canSkill, function(a, b)
    if a.orange ~= b.orange then return a.orange end
    return a.n > b.n
  end)
end

function P.windowLine()
  if not on() or #P.canSkill == 0 then return nil end
  local parts = {}
  for k = 1, math.min(3, #P.canSkill) do
    local r = P.canSkill[k]
    parts[#parts + 1] = ("|c%s%s|r x%d"):format(r.orange and "ffff8040" or "ffffd100", r.name, r.n)
  end
  return "skill-ups you can make now: " .. table.concat(parts, ", ")
end

ns.On("TRADE_SKILL_SHOW", function() P.scanWindow(); if ns.UI then ns.UI.refresh() end end)
ns.On("TRADE_SKILL_LIST_UPDATE", function() P.scanWindow(); if ns.UI then ns.UI.refresh() end end)
ns.On("TRADE_SKILL_CLOSE", function() P.canSkill = {}; if ns.UI then ns.UI.refresh() end end)
ns.On("SKILL_LINES_CHANGED", function() if ns.UI then ns.UI.refresh() end end)
ns.On("BAG_UPDATE_DELAYED", function() if ns.UI then ns.UI.refresh() end end)

function P.toggle(v) ns.db.prof = v; if ns.UI then ns.UI.refresh() end end
