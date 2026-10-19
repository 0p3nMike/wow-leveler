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

function T.guides()
  local _, cls = C.try(UnitClass, "player")
  return ns.TalentData and cls and ns.TalentData[cls] or {}
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
function T.pending()
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
  return ("|cffffd100Talent:|r %s %d%s |cff999999/zug talents|r"):format(first.name, first.rank,
    #list > 1 and ("  |cff999999+%d more|r"):format(#list - 1) or "")
end

function T.report()
  local list, g = T.pending()
  if not g then return C.print("no talent guide for your class") end
  C.print("talents: %s (RestedXP)%s", g.name, ns.cdb.talentGuide and "" or "  |cff999999chosen for you; /zug talents list|r")
  if #list == 0 then return C.print("  nothing to spend: you are on plan") end
  for k = 1, math.min(#list, 8) do C.print("  level %d: %s rank %d", list[k].lvl, list[k].name, list[k].rank) end
end

function T.command(args)
  if args == "list" then
    for _, g in ipairs(T.guides()) do C.print("  %s  |cff999999levels to %d%s|r", g.name, g.max, g.hc and ", hardcore" or "") end
    C.print("/zug talents <name> picks one; /zug talents auto goes back to the automatic choice")
  elseif args == "auto" then
    ns.cdb.talentGuide = nil; T.report()
  elseif args == "off" or args == "on" then
    ns.db.talents = args == "on"; C.print("talent advice: %s", args)
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
    if #list > 0 and ns.Peon then ns.Peon.say(("New talent: %s, rank %d."):format(list[1].name, list[1].rank), nil, ns.Peon.LINES.talent) end
  end
  if C_Timer and C_Timer.After then C_Timer.After(4, tell) else tell() end -- after the "Zug zug! Level" line, and once the game has the new level
end)
