-- Export.lua -- what the companion site (companion/) needs that nothing else saves.
--
-- Addons cannot talk to anything outside the game; the site reads the
-- SavedVariables files the game writes on /reload and logout. This adds:
--   SlopLevelerDB.maps[uiMapID]   = { name, cont, x0, y0, x1, y1 }
--       where a map sits in the world: C_Map.GetWorldPosFromMapPos at the
--       map's corners (0,0) and (1,1). With it the site can put recorded paths
--       (map x/y) and route stops (world x/y) on one canvas. Your map and the
--       ones above it, recorded as you travel.
--   SlopLevelerCharDB.char        = name, realm, class, race, faction, level, xp, xpMax, at
--   SlopLevelerCharDB.profSnap    = your professions and skill (Professions.lua's P.mine())
-- The site writes back only one file: routes/custom/Planner.lua (its Planner
-- tab), which this addon loads on /reload like any other route.

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
  local cur, max, lvl = C.xp()
  local _, class = C.try(UnitClass, "player")
  local _, race = C.try(UnitRace, "player")
  ns.cdb.char = {
    name = C.try(UnitName, "player"), realm = C.try(GetRealmName), class = class, race = race,
    faction = C.try(UnitFactionGroup, "player"), level = lvl, xp = cur, xpMax = max, at = C.epoch(),
  }
  if ns.Prof then ns.cdb.profSnap = ns.Prof.mine() end
end

ns.On("PLAYER_ENTERING_WORLD", function() E.recordMaps(); E.snapshot() end)
ns.On("ZONE_CHANGED_NEW_AREA", E.recordMaps)
ns.On("PLAYER_LEVEL_UP", E.snapshot)
ns.On("SKILL_LINES_CHANGED", E.snapshot)
ns.On("PLAYER_LOGOUT", E.snapshot)
ns.On("PLAYER_LEAVING_WORLD", E.snapshot)
