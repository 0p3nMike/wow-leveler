-- Talents.lua -- which talent to take: RestedXP's talent guides for your class
-- (data/Talents.lua, CC BY-NC-SA 4.0), against what you have learned.
--
-- A guide is a build from level 10, one pick per level ({ level, tab, row,
-- column, rank, note }). What you have: C_SpecializationInfo.GetTalentInfo with
-- { specializationIndex = tab, tier = row, column = column } (its query takes the
-- grid position directly; SpecializationInfoDocumentation, 1.60.1 export) -> rank.
-- Pending = picks for your level or below that you do not have yet.
-- The guide: the one you chose (/zug talents <name>), or the first by RestedXP's
-- #order that covers your level, a "Survival" (hardcore) one for a hardcore
-- character, an AoE one if you follow an AoE route.

local _, ns = ...
local C = ns.C

local T = {}
ns.Talents = T

-- ------------------------------------------------ Mists of Pandaria Classic
-- Six tiers of three talents, one pick each, opening at Blizzard's
-- CLASS_TALENT_LEVELS. The build: wowsims' preset for your active spec
-- (data/Talents_Mists.lua, MIT; level-90 PvE builds), or the one you chose
-- (/zug talents <spec> <name>). What you have: GetTalentTierInfo(tier, group,
-- inspect, unit) -> available, selected column (0 = none), unlock level, as
-- Blizzard_TalentUI/Mists does; glyphs: GetGlyphSocketInfo(i, group) -> its spell.
local function mistsData()
  local _, cls = C.try(UnitClass, "player")
  return not C.isForever() and ns.TalentDataMists and cls and ns.TalentDataMists[cls] or nil
end
T.mists = function() return mistsData() ~= nil end

local function group() return (C_SpecializationInfo and C.try(C_SpecializationInfo.GetActiveSpecGroup)) or 1 end

-- the active spec's name (GetSpecializationInfo, else the class's spec list)
function T.specName()
  local S = C_SpecializationInfo
  local i = S and C.try(S.GetSpecialization)
  if not i or i == 0 then return nil end
  local _, name = C.try(S.GetSpecializationInfo, i)
  if not name then
    local _, _, classID = C.try(UnitClass, "player")
    _, name = C.try(GetSpecializationInfoForClassID, classID, i)
  end
  return name
end

local function label(b) return b.spec .. " " .. b.name end

function T.mistsBuild()
  local d = mistsData()
  if not d then return nil end
  local want, spec, pick = ns.cdb.talentGuide, T.specName(), nil
  for _, b in ipairs(d.builds) do
    if want and label(b):lower() == want:lower() then return b, d end
    if spec and b.spec:lower() == spec:lower() and (not pick or b.name == "Default") then pick = b end
  end
  return pick, d
end

-- tiers open at your level with nothing picked, and the build's pick for each
function T.mistsPending()
  local b, d = T.mistsBuild()
  if not b then return {}, nil end
  local lvl, out = C.try(UnitLevel, "player") or 1, {}
  for tier = 1, 6 do
    local col = tonumber(b.talents:sub(tier, tier)) or 0
    local _, selected, unlock = C.try(GetTalentTierInfo, tier, group(), false, "player")
    unlock = unlock or d.levels[tier]
    if col > 0 and lvl >= unlock and (selected or 0) == 0 then
      out[#out + 1] = { name = d.tiers[tier][col].name, lvl = unlock, tier = tier }
    end
  end
  return out, b
end

-- the build's glyphs you do not have: { { name, kind = "major"|"minor" } }
function T.mistsGlyphs(b)
  local have, out = {}, {}
  for i = 1, (C.try(GetNumGlyphSockets) or 0) do
    local _, _, _, spell = C.try(GetGlyphSocketInfo, i, group())
    if spell then have[spell] = true end
  end
  for _, kind in ipairs({ "major", "minor" }) do
    for _, g in ipairs(b and b[kind] or {}) do
      if not (g.spell and have[g.spell]) then out[#out + 1] = { name = g.name, kind = kind } end
    end
  end
  return out
end

function T.guides()
  local _, cls = C.try(UnitClass, "player")
  return C.isForever() and ns.TalentData and cls and ns.TalentData[cls] or {} -- RestedXP's Forever talents
end

function T.guide()
  local list = T.guides()
  local want = ns.cdb.talentGuide
  if want then
    for _, g in ipairs(list) do if g.name == want then return g end end
  end
  local lvl = C.try(UnitLevel, "player") or 1
  local hc = ns.Engine.hardcore()
  local r = ns.Engine.route()
  local aoe = r and r.name and r.name:find("AoE") ~= nil
  local best, bestScore
  for _, g in ipairs(list) do
    if lvl <= g.max then
      -- lower is better: the right play style first, then AoE to match the route, then RestedXP's order
      local score = (g.hc == hc and 0 or 1000) + ((g.name:find("AoE") ~= nil) == aoe and 0 or 100) + (g.order or 99)
      if not bestScore or score < bestScore then best, bestScore = g, score end
    end
  end
  return best
end

-- current rank and name of the talent at tab / row / column
function T.rank(tab, row, col)
  if not (C_SpecializationInfo and C_SpecializationInfo.GetTalentInfo) then return nil end
  local info = C.try(C_SpecializationInfo.GetTalentInfo, { specializationIndex = tab, tier = row, column = col })
  if type(info) ~= "table" then return nil end
  return info.rank or 0, info.name
end

-- the picks due at your level that you do not have: { { name, rank, lvl } }
-- (Mists: { { name, lvl, tier } })
function T.pending()
  if mistsData() then return T.mistsPending() end
  local g = T.guide()
  if not g then return {}, nil end
  local lvl = C.try(UnitLevel, "player") or 1
  local out = {}
  for _, p in ipairs(g.picks) do
    local plvl, tab, row, col, rank, note = p[1], p[2], p[3], p[4], p[5], p[6]
    if plvl > lvl then break end
    local have, name = T.rank(tab, row, col)
    if have and have < rank then
      out[#out + 1] = { name = name or (note or ""):gsub(" %(Rank %d+%)", ""), rank = rank, lvl = plvl, note = note }
    end
  end
  return out, g
end

-- one line for the window, or nil
function T.line()
  if ns.db.talents == false then return nil end
  local list = T.pending()
  if #list == 0 then return nil end
  local first = list[1]
  return ("|cffffd100Talent:|r %s%s%s |cff999999/zug talents|r"):format(first.name,
    first.rank and (" " .. first.rank) or (" |cff999999(level %d tier)|r"):format(first.lvl),
    #list > 1 and ("  |cff999999+%d more|r"):format(#list - 1) or "")
end

function T.report()
  if mistsData() then
    local list, b = T.mistsPending()
    if not b then return C.print("no talent build for your spec yet (pick a specialization; /zug talents list)") end
    local d = mistsData()
    C.print("talents: %s (wowsims, a level-90 PvE build)%s", label(b), ns.cdb.talentGuide and "" or "  |cff999999for your spec; /zug talents list|r")
    for tier = 1, 6 do
      local col = tonumber(b.talents:sub(tier, tier)) or 0
      local _, selected = C.try(GetTalentTierInfo, tier, group(), false, "player")
      local mine = (selected or 0) > 0 and d.tiers[tier][selected] and d.tiers[tier][selected].name
      C.print("  %d: %s%s", d.levels[tier], col > 0 and d.tiers[tier][col].name or "?",
        mine and (mine ~= (col > 0 and d.tiers[tier][col].name) and ("  |cff999999(you: %s)|r"):format(mine) or "  |cff60ff60(you have it)|r") or "")
    end
    local miss = T.mistsGlyphs(b)
    if #miss > 0 then
      local names = {}
      for _, g in ipairs(miss) do names[#names + 1] = g.name end
      C.print("  glyphs to get: %s", table.concat(names, ", "))
    end
    return
  end
  local list, g = T.pending()
  if not g then return C.print("no talent guide for your class") end
  C.print("talents: %s (RestedXP)%s", g.name, ns.cdb.talentGuide and "" or "  |cff999999chosen for you; /zug talents list|r")
  if #list == 0 then return C.print("  nothing to spend: you are on plan") end
  for k = 1, math.min(#list, 8) do C.print("  level %d: %s rank %d", list[k].lvl, list[k].name, list[k].rank) end
end

function T.command(args)
  if args == "list" and mistsData() then
    for _, b in ipairs(mistsData().builds) do C.print("  %s  |cff999999%s|r", label(b), b.talents) end
    C.print("/zug talents <spec> <name> picks one (e.g. /zug talents frost default); /zug talents auto follows your spec")
  elseif args == "list" then
    for _, g in ipairs(T.guides()) do C.print("  %s  |cff999999levels to %d%s|r", g.name, g.max, g.hc and ", hardcore" or "") end
    C.print("/zug talents <name> picks one; /zug talents auto goes back to the automatic choice")
  elseif args == "auto" then
    ns.cdb.talentGuide = nil; T.report()
  elseif args == "off" or args == "on" then
    ns.db.talents = args == "on"; C.print("talent advice: %s", args)
  elseif args ~= "" and mistsData() then
    for _, b in ipairs(mistsData().builds) do
      if label(b):lower() == args:lower() then ns.cdb.talentGuide = label(b); return T.report() end
    end
    C.print("no build named %q; /zug talents list", args)
  elseif args ~= "" then
    for _, g in ipairs(T.guides()) do
      if g.name:lower() == args:lower() then ns.cdb.talentGuide = g.name; return T.report() end
    end
    C.print("no talent guide named %q; /zug talents list", args)
  else
    T.report()
  end
  if ns.UI then ns.UI.refresh() end
end

-- a level-up with a point to spend: the peon says which
ns.On("PLAYER_LEVEL_UP", function(level)
  if ns.db.talents == false or (tonumber(level) or 0) < 10 then return end
  local function tell()
    local list = T.pending()
    if #list > 0 and ns.Peon then
      ns.Peon.say(list[1].rank and ("New talent: %s, rank %d."):format(list[1].name, list[1].rank) or ("New talent: %s."):format(list[1].name), nil, ns.Peon.LINES.talent)
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(4, tell) else tell() end -- after the "Zug zug! Level" line, and once the game has the new level
end)
