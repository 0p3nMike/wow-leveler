-- Downtime.lua -- where the time goes, per zone: fighting, drinking/eating,
-- dead, flying, moving, standing still.
--
-- Every tick (0.5 s) the player is in exactly one state, chosen in this order:
--   dead     UnitIsDeadOrGhost
--   combat   UnitAffectingCombat
--   drink    a helpful aura named Drink / Food / Refreshment (enUS client names)
--   flight   UnitOnTaxi
--   move     position changed since the last tick
--   afk      UnitIsAFK, or standing still for 3 minutes (kept out of "idle")
--   idle     none of the above (vendors, quest text, standing)
-- Aura names can be SECRET on Forever (C_UnitAuras.GetAuraDataByIndex is
-- SecretWhenUnitAuraRestricted in the 1.60.1 export). Each one is checked with
-- issecretvalue before it is compared, and drinking is only looked for out of
-- combat. GetUnitSpeed is not used (SecretWhenUnitStatsRestricted); movement
-- is measured from position instead.
-- Totals: ZugzugLevelerCharDB.downtime[zone][state] (this session) and, while
-- recording, run.time[zone][state].

local _, ns = ...
local C, XP = ns.C, ns.XP

local D = {}
ns.Downtime = D

D.STATES = { "combat", "drink", "move", "flight", "idle", "afk", "dead" }
-- afk: the game's own AFK flag (UnitIsAFK), or standing still this long
local AFK_AFTER = 180
local stillSince
local DRINK = { Drink = true, Food = true, Refreshment = true, ["Food & Drink"] = true }

local last, lastPos

local function secret(v) return issecretvalue and issecretvalue(v) end

function D.drinking()
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
  for i = 1, 40 do
    local aura = C.try(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not aura then return false end
    local name = aura.name
    if name and not secret(name) and DRINK[name] then return true end
  end
  return false
end

function D.state()
  if C.try(UnitIsDeadOrGhost, "player") then return "dead" end
  if C.try(UnitAffectingCombat, "player") then return "combat" end
  if D.drinking() then return "drink" end
  if C.try(UnitOnTaxi, "player") then return "flight" end
  local m, x, y = C.mapPos()
  local moved = x and lastPos and (m ~= lastPos[1] or math.abs(x - lastPos[2]) + math.abs(y - lastPos[3]) > 0.0002)
  lastPos = x and { m, x, y } or lastPos
  if moved then stillSince = nil; return "move" end
  stillSince = stillSince or C.now()
  if C.try(UnitIsAFK, "player") or C.now() - stillSince >= AFK_AFTER then return "afk" end
  return "idle"
end

local function add(tbl, zone, state, dt)
  tbl[zone] = tbl[zone] or {}
  tbl[zone][state] = (tbl[zone][state] or 0) + dt
end

ns.On("SL_TICK", function()
  local now = C.now()
  local dt = last and math.min(now - last, 2) or 0
  last = now
  if dt <= 0 then return end
  if ns.Pause.on() then D.now = "paused"; return end
  local st = D.state()
  local zone = C.mapName((C.mapPos())) or "?"
  ns.cdb.downtime = ns.cdb.downtime or {}
  add(ns.cdb.downtime, zone, st, dt)
  local run = ns.Rec.active()
  if run then
    run.time = run.time or {}
    add(run.time, zone, st, dt)
  end
  D.now = st
end)

-- shares of each state, for one zone or all of them
function D.shares(zone)
  local t, total = {}, 0
  for z, states in pairs(ns.cdb.downtime or {}) do
    if not zone or z == zone then
      for st, secs in pairs(states) do t[st] = (t[st] or 0) + secs; total = total + secs end
    end
  end
  return t, total
end

local COLOR = { combat = "ffff6060", drink = "ff4fa3ff", move = "ffffffff", flight = "ffc080ff", idle = "ff999999", afk = "ff666666", dead = "ff808080" }

-- One line for the window: this zone's split, biggest first.
function D.line()
  local zone = C.mapName((C.mapPos()))
  local t, total = D.shares(zone)
  if total < 30 then return nil end
  local parts = {}
  for _, st in ipairs(D.STATES) do
    if t[st] and t[st] / total >= 0.02 then
      parts[#parts + 1] = { st, t[st] / total }
    end
  end
  table.sort(parts, function(a, b) return a[2] > b[2] end)
  local out = {}
  for _, p in ipairs(parts) do
    out[#out + 1] = ("|c%s%s %d%%|r"):format(COLOR[p[1]], p[1], math.floor(p[2] * 100 + 0.5))
  end
  return (zone or "here") .. ": " .. table.concat(out, " · ")
end

function D.reset() ns.cdb.downtime = {} end

-- full table for /zug downtime
function D.report()
  local lines = {}
  for zone, states in pairs(ns.cdb.downtime or {}) do
    local total = 0
    for _, s in pairs(states) do total = total + s end
    local bits = {}
    for _, st in ipairs(D.STATES) do
      if states[st] then bits[#bits + 1] = ("%s %s"):format(st, XP.fmtTime(states[st])) end
    end
    lines[#lines + 1] = ("%s (%s): %s"):format(zone, XP.fmtTime(total), table.concat(bits, ", "))
  end
  table.sort(lines)
  return lines
end
