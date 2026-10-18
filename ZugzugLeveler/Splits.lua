-- Splits.lua -- speedrun splits: each step's time against your best.
--
-- Time is PLAYED time on the route (it only runs while you are logged in), so
-- logging off for the night does not count against a step.
-- A step's segment = time from it becoming current to it finishing. Only steps
-- you actually played count: steps fast-forwarded past (already done) or
-- /lev skip'ped are not timed, so they can never set a fake "best".
--   ZugzugLevelerDB.best[route].seg[i]  your best segment for step i (any character)
--   ZugzugLevelerCharDB.split           this character's current attempt
-- Shown: the running step clock against its best, and the sum of
-- (segment - best) over this attempt = time lost or gained vs your best.

local _, ns = ...
local C, XP = ns.C, ns.XP

local S = {}
ns.Splits = S

local last -- GetTime() of the previous tick

local function attempt()
  local cdb = ns.cdb
  local route = cdb.route
  if not route then return nil end
  local r = ns.Engine.route()
  if r and r.dynamic then return nil end -- quest log mode rebuilds its steps: nothing to compare
  if not cdb.split or cdb.split.route ~= route then
    -- segStep is set by SL_STEP: a step is only timed once it has been on screen
    cdb.split = { route = route, played = 0, segStart = 0, segStep = nil, delta = 0, timed = 0, golds = 0 }
  end
  return cdb.split
end

local function best(route)
  ns.db.best = ns.db.best or {}
  ns.db.best[route] = ns.db.best[route] or { seg = {} }
  return ns.db.best[route]
end

ns.On("SL_TICK", function()
  local now = C.now()
  local a = attempt()
  if a and last then a.played = a.played + math.min(now - last, 2) end -- a hitch is not play time
  last = now
end)

ns.On("SL_ROUTE", function() if ns.cdb.split then ns.cdb.split = nil end; attempt() end)

ns.On("SL_STEP", function(i)
  local a = attempt()
  if a and a.segStep ~= i then a.segStep, a.segStart = i, a.played end
end)

-- The step clock: (seconds on this step, best for it or nil).
function S.current()
  local a = attempt()
  if not a then return nil end
  local b = best(a.route).seg[ns.Engine.index()]
  return a.played - a.segStart, b
end

ns.On("SL_FINISH", function(i, wasCurrent)
  local a = attempt()
  if not (a and wasCurrent and a.segStep == i) then return end
  local seg = a.played - a.segStart
  local bs = best(a.route).seg
  if bs[i] then
    a.delta = a.delta + (seg - bs[i])
    a.timed = a.timed + 1
  end
  if not bs[i] or seg < bs[i] then
    if bs[i] then a.golds = a.golds + 1 end
    bs[i] = seg
  end
  a.segStep, a.segStart = nil, a.played
end)

-- "+1:05" / "-0:12"
function S.fmtDelta(d)
  local sign = d < 0 and "-" or "+"
  d = math.floor(math.abs(d) + 0.5)
  return ("%s%d:%02d"):format(sign, math.floor(d / 60), d % 60)
end

-- One line for the window, or nil before there is anything to compare.
function S.line()
  local a = attempt()
  if not a then return nil end
  local cur, b = S.current()
  local parts = {}
  if cur then
    if b then
      local d = cur - b
      parts[#parts + 1] = ("step %s |c%s%s|r"):format(XP.fmtTime(cur), d > 0 and "ffff6060" or "ff60ff60", S.fmtDelta(d))
    else
      parts[#parts + 1] = "step " .. XP.fmtTime(cur)
    end
  end
  if a.timed > 0 then
    parts[#parts + 1] = ("vs best |c%s%s|r over %d steps"):format(a.delta > 0 and "ffff6060" or "ff60ff60", S.fmtDelta(a.delta), a.timed)
  end
  if a.golds > 0 then parts[#parts + 1] = ("|cffffd100%d gold|r"):format(a.golds) end
  return #parts > 0 and table.concat(parts, "  ·  ") or nil
end

function S.reset(route)
  if ns.db.best then ns.db.best[route or ns.cdb.route or ""] = nil end
  ns.cdb.split = nil
end
