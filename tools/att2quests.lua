-- att2quests.lua -- AllTheThings' Forever quest data -> ZugzugLeveler/data/Quests.lua
--
--   luajit tools/att2quests.lua <ATT db/Camelot/Categories folder> <ATT commit> [out]
--
-- AllTheThings (github.com/ATTWoWAddon/AllTheThings, MIT License) ships a built
-- database per game; db/Camelot is Forever's (its TOC lists Interface 16001).
-- Each category file registers a handler for "OnBuildDataCache" that builds a
-- tree of h()/m()/q()/n()/qo()... constructors. This runs those files with
-- stand-in constructors that only record what they are given, then keeps each
-- quest's facts. What the fields mean, as ATT's own code reads them:
--   sourceQuests  quests to turn in first; sqreq of them when set, else all
--                 (src/Classes/Quests.lua missingReqs); a breadcrumb among
--                 them does not block (missingSourceQuests)
--   altQuests     any of these done locks this one (altcollected)
--   isBreadcrumb  a lead-in, optional
--   lvl           minimum level, or {min, max} (src/Modules/Filter.lua Level)
--   r             faction: 1 Horde, 2 Alliance (Enum.FlightPathFaction; Filter.lua
--                 Race_CurrentFaction compares it with app.FactionID)
--   races / c     race IDs / class IDs that can take it
--   qgs           quest giver NPC IDs; coords = { [uiMapID] = { {x, y}, ... } } (0-100)
--   qo(n, {coords, crs, providers})  objective n: where, which creatures, which item
--   lc            lock criteria { needed, key, value, ... }
-- Output: ns.QuestDB[questID] = { sq, sqreq, alt, bc, lvl, r, races, c, qg, at, zone, obj, lc, rep }
--   at  = { map, x, y } (the giver's first point, 0-1), zone = the map it is listed under,
--   obj = { [n] = { map, x, y, crs = {...} } }

local dir, commit, out = arg[1], arg[2] or "unknown", arg[3] or "ZugzugLeveler/data/Quests.lua"
assert(dir, "usage: luajit tools/att2quests.lua <db/Camelot/Categories> <commit> [out]")

local handlers = {}
local NS = { AddEventHandler = function(ev, fn) if ev == "OnBuildDataCache" then handlers[#handlers + 1] = fn end end }
local function mk(kind)
  return function(id, ...)
    local a = { ... }
    local t = type(a[#a]) == "table" and a[#a] or {}
    t._kind, t._id = kind, id
    return t
  end
end
local proxy
proxy = setmetatable({}, { __index = function() return proxy end, __call = function() return proxy end })
setmetatable(NS, { __index = function(t, k)
  if type(k) == "string" and k:find("^Create") then
    local f = mk((k:gsub("^Create", "")))
    rawset(t, k, f)
    return f
  end
  return proxy
end })

local FILES = { "Zones", "Instances", "Holidays", "WorldDrops", "Craftables", "PVP", "Professions", "Character",
  "ExpansionFeatures", "HiddenQuestTriggers", "NeverImplemented" }
for _, name in ipairs(FILES) do
  local f = loadfile(dir .. "/" .. name .. ".lua")
  if f then f("AllTheThings", NS) end
end
local cats = {}
for _, h in ipairs(handlers) do h(cats) end

local Q = {}
local function first(coords)
  if type(coords) ~= "table" then return nil end
  local best
  for map, pts in pairs(coords) do
    if type(map) == "number" and type(pts) == "table" and type(pts[1]) == "table" then
      if not best or map < best[1] then best = { map, pts[1][1] / 100, pts[1][2] / 100 } end
    end
  end
  return best
end
local function ids(v)
  if type(v) ~= "table" then return nil end
  local o = {}
  for _, x in ipairs(v) do if type(x) == "number" then o[#o + 1] = x end end
  return #o > 0 and o or nil
end
local function union(a, b)
  if not a then return b end
  if not b then return a end
  local seen, o = {}, {}
  for _, x in ipairs(a) do if not seen[x] then seen[x] = true; o[#o + 1] = x end end
  for _, x in ipairs(b) do if not seen[x] then seen[x] = true; o[#o + 1] = x end end
  table.sort(o)
  return o
end

-- loot by creature: ATT files an item's droppers on the item (crs = { npc ids }),
-- so turning that round gives each creature's loot (no drop rates: ATT has none)
local LOOT = {}
local function walk(node, zone)
  if type(node) ~= "table" then return end
  local z = zone
  if node._kind == "Map" and type(node._id) == "number" then z = node._id end
  if node._kind == "Item" and type(node._id) == "number" and type(node.crs) == "table" then
    for _, npc in ipairs(node.crs) do
      if type(npc) == "number" then
        local l = LOOT[npc] or {}
        LOOT[npc] = l
        local seen = false
        for _, x in ipairs(l) do if x == node._id then seen = true end end
        if not seen and #l < 16 then l[#l + 1] = node._id end
      end
    end
  end
  if node._kind == "Quest" and type(node._id) == "number" then
    local id = node._id
    local e = Q[id] or {}
    Q[id] = e
    e.sq = union(e.sq, ids(node.sourceQuests))
    e.alt = union(e.alt, ids(node.altQuests))
    e.qg = union(e.qg, ids(node.qgs))
    e.races = e.races or ids(node.races)
    e.c = e.c or ids(node.c)
    e.sqreq = e.sqreq or node.sqreq
    e.bc = e.bc or (node.isBreadcrumb and 1 or nil)
    e.lvl = e.lvl or node.lvl
    e.r = e.r or node.r
    e.rep = e.rep or (node.repeatable and 1 or nil)
    e.at = e.at or first(node.coords)
    e.zone = e.zone or z
    if type(node.lc) == "table" then e.lc = e.lc or node.lc end
    for _, c in ipairs(node.g or {}) do
      if type(c) == "table" and c._kind == "QuestObjective" and type(c._id) == "number" then
        e.obj = e.obj or {}
        local o = e.obj[c._id] or {}
        e.obj[c._id] = o
        local p = first(c.coords)
        if p and not o[1] then o[1], o[2], o[3] = p[1], p[2], p[3] end
        o.crs = union(o.crs, ids(c.crs))
      end
    end
  end
  for _, c in ipairs(node.g or {}) do walk(c, z) end
  for _, c in ipairs(node) do walk(c, z) end
end
for _, v in pairs(cats) do walk(v, nil) end
-- objectives with neither a place nor a creature say nothing
for _, e in pairs(Q) do
  if e.obj then
    local any
    for n, o in pairs(e.obj) do
      if o[1] or o.crs then any = true else e.obj[n] = nil end
    end
    if not any then e.obj = nil end
  end
end

-- -------------------------------------------------------------- write
local function lit(v)
  local t = type(v)
  if t == "number" then
    if v == math.floor(v) then return tostring(v) end
    return (string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", ""))
  elseif t == "string" then return string.format("%q", v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "table" then
    local parts, n = {}, #v
    for k = 1, n do parts[#parts + 1] = lit(v[k]) end
    local keys = {}
    for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = (type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. lit(k) .. "]")) .. "=" .. lit(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end

local idsSorted = {}
for id in pairs(Q) do idsSorted[#idsSorted + 1] = id end
table.sort(idsSorted)
local f = assert(io.open(out, "wb"))
f:write("-- Quests.lua -- generated by tools/att2quests.lua; do not edit by hand, re-run the tool.\n")
f:write("--\n-- Quest facts for WoW Forever from AllTheThings (https://github.com/ATTWoWAddon/AllTheThings,\n")
f:write("-- commit " .. commit .. ", db/Camelot), used under its MIT License:\n--\n")
for l in io.lines(dir .. "/../../../LICENSE") do f:write("--   " .. l .. "\n") end
f:write("--\n-- Fields: see tools/att2quests.lua. " .. #idsSorted .. " quests.\n\nlocal _, ns = ...\n\nns.QuestDB = {\n")
for _, id in ipairs(idsSorted) do f:write("[" .. id .. "]=" .. lit(Q[id]) .. ",\n") end
f:write("}\n")
f:close()
print(("wrote %s: %d quests"):format(out, #idsSorted))

-- the loot index, for the companion page (JSON: the page reads it, the addon does not need it)
local lootOut = arg[4] or "companion/web/data/npcloot.json"
local npcs = {}
for id in pairs(LOOT) do npcs[#npcs + 1] = id end
table.sort(npcs)
local lf = assert(io.open(lootOut, "wb"))
lf:write('{"_source":"AllTheThings (MIT, https://github.com/ATTWoWAddon/AllTheThings) commit ' .. commit ..
  ', db/Camelot: items by the creatures that drop them (crs), turned round. No drop rates: ATT has none.","loot":{')
for k, id in ipairs(npcs) do
  table.sort(LOOT[id]) -- the files are read in no fixed order: sorted, the output is the same every run
  lf:write((k > 1 and "," or "") .. '"' .. id .. '":[' .. table.concat(LOOT[id], ",") .. "]")
end
lf:write("}}\n")
lf:close()
print(("wrote %s: loot for %d creatures"):format(lootOut, #npcs))
