-- Pause.lua -- "I am doing my own thing for a while": pause the optimizer.
--
-- Walking to Thunder Bluff for a flight path, waiting for a friend, a detour
-- the route knows nothing about. While paused:
--   * XP/hour, the session, step times and speedrun splits do not count the time
--     (XP.lua, Engine.lua stepStart, Splits.lua): the detour is not the route's;
--   * where the time goes (Downtime.lua) and recorded runs (Recorder.lua) skip it;
--   * the coach asks nothing (Coach.PAUSE) and the optimizer does not reorder;
--   * the arrow idles (Arrow.lua) and the game's map pin for the step is cleared.
--     A /way you set yourself still works: that is often the point of pausing.
-- The quest log is still followed, so the step list is right when you resume.
-- Kept per character, so a /reload or a Sync on the way stays paused:
--   ZugzugLevelerCharDB.paused = { at = epoch, secs = online seconds paused so far }

local _, ns = ...
local C = ns.C

local P = {}
ns.Pause = P

local last -- GetTime() of the previous tick, to count online paused time only

function P.on() return ns.cdb ~= nil and ns.cdb.paused ~= nil end

-- online seconds this pause has lasted
function P.secs() return P.on() and ns.cdb.paused.secs or 0 end

function P.set(v)
  if not ns.cdb or v == P.on() then return end
  if v then
    ns.cdb.paused, last = { at = C.epoch(), secs = 0 }, C.now()
    C.print("paused: the route waits, nothing is timed, the arrow rests. A /way still guides you. Resume: the button again, or /zug resume.")
    ns.Fire("SL_PAUSE", true, 0)
  else
    local secs = ns.cdb.paused.secs or 0
    ns.cdb.paused = nil
    C.print("resumed after %s: back to %s", ns.XP.fmtTime(secs), ns.Engine.route() and ns.Engine.describe(ns.Engine.step()) or "no route")
    ns.Fire("SL_PAUSE", false, secs)
  end
  if ns.UI then ns.UI.refresh() end
end

function P.toggle() P.set(not P.on()) end

ns.On("SL_TICK", function()
  local now = C.now()
  if P.on() and last then
    local p = ns.cdb.paused
    p.secs = (p.secs or 0) + math.min(now - last, 2) -- a hitch or a loading screen is not paused time
  end
  last = now
end)

function ZugzugLeveler_Pause() P.toggle() end
BINDING_NAME_ZUGZUGLEVELER_PAUSE = "Pause / resume the route and its timing"
