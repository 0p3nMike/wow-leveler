-- XP.lua -- how fast are we leveling, and where does it come from.
--
-- Everything is in server epoch seconds (GetServerTime) so a session survives
-- /reload and relog: a gap of more than SESSION_GAP starts a new session.
-- Each gain is split into quest XP (QUEST_TURNED_IN carries xpReward) and
-- everything else (kills, exploration), which is what tells you whether a
-- route is quest-bound or grind-bound.

local _, ns = ...
local C = ns.C

local XP = {}
ns.XP = XP

local WINDOW = 600        -- rolling rate window, seconds
local SESSION_GAP = 1800  -- offline longer than this = new session

local last           -- { xp, max, lvl }
local pendingQuest = 0

local function session() return ns.cdb.session end

local function newSession(now)
  ns.cdb.session = { start = now, seen = now, total = 0, quest = 0, samples = {} }
end

local function prune(s, now)
  local keep = {}
  for _, smp in ipairs(s.samples) do
    if now - smp[1] <= WINDOW then keep[#keep + 1] = smp end
  end
  s.samples = keep
end

local function resync()
  local cur, max, lvl = C.xp()
  if cur then last = { xp = cur, max = max, lvl = lvl } end
end

ns.On("SL_READY", function()
  local now = C.epoch()
  local s = session()
  if not s or now - (s.seen or 0) > SESSION_GAP then newSession(now) end
  resync()
end)

ns.On("PLAYER_ENTERING_WORLD", resync)

ns.On("QUEST_TURNED_IN", function(_, xpReward)
  if type(xpReward) == "number" and xpReward > 0 then pendingQuest = pendingQuest + xpReward end
end)

-- The gain since the last reading. A level-up means the rest of the old bar
-- plus what is on the new one (one level per event; two at once would need a
-- 60-level quest, and then the number is merely low, never negative).
function XP.delta(prev, cur, max, lvl)
  if not prev then return 0 end
  if lvl > prev.lvl then return math.max(prev.max - prev.xp, 0) + cur end
  if cur >= prev.xp then return cur - prev.xp end
  return 0
end

ns.On("PLAYER_XP_UPDATE", function(unit)
  if unit and unit ~= "player" then return end
  local cur, max, lvl = C.xp()
  if not cur then return end
  local gain = XP.delta(last, cur, max, lvl)
  last = { xp = cur, max = max, lvl = lvl }
  if gain <= 0 then return end
  if ns.Pause.on() then pendingQuest = 0; return end -- a detour's XP is not the route's rate
  local quest = math.min(gain, pendingQuest)
  pendingQuest = pendingQuest - quest
  local now, s = C.epoch(), session()
  s.total, s.quest, s.seen = s.total + gain, s.quest + quest, now
  s.samples[#s.samples + 1] = { now, gain }
  prune(s, now)
  ns.Fire("SL_XP", gain, quest)
end)

-- after a pause: the session and its samples move on by the paused time, so
-- XP/hour counts only the time you were on the route
ns.On("SL_PAUSE", function(paused, secs)
  local s = session()
  if paused or not s or not secs or secs <= 0 then return end
  local now = C.epoch()
  s.start = math.min(s.start + secs, now)
  for _, smp in ipairs(s.samples) do smp[1] = math.min(smp[1] + secs, now) end
end)

ns.On("SL_TICK", function()
  local s = session()
  if s then s.seen = C.epoch() end
end)

-- XP per hour over the rolling window (or the whole session when it is
-- shorter). nil until there is a minute of data.
function XP.rate()
  local s = session()
  if not s then return nil end
  local now = C.epoch()
  prune(s, now)
  local span = math.min(WINDOW, now - s.start)
  if span < 60 then return nil end
  local sum = 0
  for _, smp in ipairs(s.samples) do sum = sum + smp[2] end
  return sum / span * 3600
end

function XP.sessionRate()
  local s = session()
  if not s then return nil end
  local span = C.epoch() - s.start
  if span < 60 then return nil end
  return s.total / span * 3600
end

-- Seconds to the next level at the current rate.
function XP.ttl()
  local r = XP.rate()
  local cur, max = C.xp()
  if not r or r <= 0 or not cur then return nil end
  return (max - cur) / r * 3600
end

function XP.session() return session() end

function XP.reset()
  newSession(C.epoch())
  pendingQuest = 0
  resync()
end

-- "1h 05m" / "12m" / "40s"
function XP.fmtTime(s)
  if not s then return "--" end
  s = math.floor(s + 0.5)
  if s >= 3600 then return string.format("%dh %02dm", math.floor(s / 3600), math.floor((s % 3600) / 60)) end
  if s >= 60 then return string.format("%dm", math.floor(s / 60)) end
  return string.format("%ds", s)
end

function XP.fmtNum(n)
  if not n then return "--" end
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n + 0.5))
end
