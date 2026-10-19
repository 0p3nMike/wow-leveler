-- Danger.lua -- warn about elites, rares and nasty patrols near you and your next stop.
--
-- Data: data/Danger.lua, converted by tools/rxp_danger.py from RestedXP's
-- Forever dangerous-mob list (CC BY-NC-SA 4.0). Each entry: name, level
-- range, classification (Normal / Elite / Rare / Boss), movement, a note
-- ("Charge / Stun"), and where: pins (spots) and/or lines (patrol paths).
--
-- A mob matters when it is an Elite / Rare / Boss, or a Normal mob not more
-- than 2 levels under you. Distance is to the nearest pin, or to the nearest
-- point of a patrol path (point-to-segment), in yards.
--   near you      within WARN yards: chat line once per mob per session, and
--                 a row in the window
--   near the step within STEP yards of the arrow's target: "route passes X"
-- Minimap: MapPath.lua draws the nearby ones as red dots.

local _, ns = ...
local C = ns.C

local D = {}
ns.Danger = D

local WARN, STEP = 70, 60
local list       -- this faction's entries, with world positions filled in
local warned = {}
D.near, D.atStep = {}, {}

local function on() return ns.db.danger ~= false end

local function prepare()
  if list then return list end
  local faction = C.try(UnitFactionGroup, "player")
  local src = C.isForever() and ns.DangerData and faction and ns.DangerData[faction] or {} -- Forever's mobs
  list = {}
  for _, e in ipairs(src) do
    local w = { pins = {}, segs = {} }
    for _, p in ipairs(e.pins or {}) do
      local c, x, y = C.worldPos(p[1], p[2], p[3])
      if c then w.pins[#w.pins + 1] = { c, x, y } end
    end
    for _, ln in ipairs(e.lines or {}) do
      local pts, prev = ln[2], nil
      for k = 1, #pts - 1, 2 do
        local c, x, y = C.worldPos(ln[1], pts[k], pts[k + 1])
        if c then
          local here = { c, x, y }
          if prev and prev[1] == c then w.segs[#w.segs + 1] = { prev, here } end
          prev = here
        end
      end
    end
    if #w.pins > 0 or #w.segs > 0 then
      e.w = w
      list[#list + 1] = e
    end
  end
  return list
end

local function segDist(p, a, b)
  local dx, dy = b[2] - a[2], b[3] - a[3]
  local len2 = dx * dx + dy * dy
  local t = len2 > 0 and (((p[2] - a[2]) * dx + (p[3] - a[3]) * dy) / len2) or 0
  t = math.max(0, math.min(1, t))
  local x, y = a[2] + t * dx, a[3] + t * dy
  return math.sqrt((p[2] - x) ^ 2 + (p[3] - y) ^ 2), { a[1], x, y }
end

-- Yards from a world point {cont, wx, wy} to the mob, and the closest spot.
function D.distance(e, p)
  local best, at
  for _, q in ipairs(e.w.pins) do
    if q[1] == p[1] then
      local d = math.sqrt((q[2] - p[2]) ^ 2 + (q[3] - p[3]) ^ 2)
      if not best or d < best then best, at = d, q end
    end
  end
  for _, s in ipairs(e.w.segs) do
    if s[1][1] == p[1] then
      local d, q = segDist(p, s[1], s[2])
      if not best or d < best then best, at = d, q end
    end
  end
  return best, at
end

function D.matters(e, level)
  if e.c ~= "Normal" then return true end
  return (e.hi or 0) >= (level or 0) - 2
end

local function scan(p, radius)
  local out = {}
  local level = C.try(UnitLevel, "player") or 0
  for _, e in ipairs(prepare()) do
    if D.matters(e, level) then
      local d, at = D.distance(e, p)
      if d and d <= radius then out[#out + 1] = { e = e, d = d, at = at } end
    end
  end
  table.sort(out, function(a, b) return a.d < b.d end)
  return out
end

function D.label(e)
  local tag = e.c ~= "Normal" and (e.c:lower() .. " ") or ""
  local lvl = e.lo == e.hi and tostring(e.lo) or (e.lo .. "-" .. e.hi)
  return ("%s (%s%s)"):format(e.n, tag, lvl)
end

function D.update()
  if not on() then D.near, D.atStep = {}, {}; return end
  local m, x, y = C.mapPos()
  local pc, px, py = C.worldPos(m, x, y)
  if not pc then return end
  D.near = scan({ pc, px, py }, WARN)
  for _, hit in ipairs(D.near) do
    if not warned[hit.e] then
      warned[hit.e] = true
      C.print("|cffff4040danger:|r %s, %d yd%s", D.label(hit.e), hit.d, hit.e.note and (" · " .. hit.e.note) or "")
    end
  end
  local t = ns.Way and ns.Way.current()
  D.atStep = (t and t.wx) and scan({ t.cont, t.wx, t.wy }, STEP) or {}
end

-- Rows for the window: the closest threat near you, then one near the step.
function D.rows()
  local rows = {}
  local n = D.near[1]
  if n then
    rows[#rows + 1] = ("|cffff4040! %s|r %d yd%s"):format(D.label(n.e), n.d, n.e.note and (" |cffb0b0b0" .. n.e.note .. "|r") or "")
  end
  local s = D.atStep[1]
  if s and (not n or s.e ~= n.e) then
    rows[#rows + 1] = ("|cffff8040next stop is near %s|r%s"):format(D.label(s.e), s.e.mv ~= "" and (" |cffb0b0b0(" .. s.e.mv:lower() .. ")|r") or "")
  end
  return rows
end

local ticks = 0
ns.On("SL_TICK", function()
  ticks = ticks + 1
  if ticks % 2 == 0 then D.update() end -- once a second
end)
ns.On("PLAYER_LEVEL_UP", function() warned = {} end)

-- Learn a listed mob's NPC number when you target or mouse over it (UnitGUID
-- "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>"), for the companion
-- page's loot list and Wowhead link: ns.db.npcIds[name] = id. RestedXP's list
-- has names only, and the game holds creature names only for ones you meet.
local names
local function learn(unit)
  local guid = C.try(UnitGUID, unit)
  if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) or not guid:find("^Creature%-") then return end
  local name = C.try(UnitName, unit)
  if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return end
  if not names then
    names = {}
    for _, side in pairs(C.isForever() and ns.DangerData or {}) do for _, e in ipairs(side) do names[e.n] = true end end
  end
  if not names[name] then return end
  local id = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
  if id then
    ns.db.npcIds = ns.db.npcIds or {}
    ns.db.npcIds[name] = id
  end
end
D.learn = learn
ns.On("PLAYER_TARGET_CHANGED", function() learn("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() learn("mouseover") end)

function D.reset() list, warned = nil, {} end

function D.toggle(v)
  ns.db.danger = v
  D.update()
end
