-- Events.lua -- one event frame, one bus. Every module subscribes here
-- instead of making its own frame, so the order handlers run in is the order
-- the files load in (TOC order), and a handler error is caught and reported
-- once instead of breaking every handler after it.
--
-- Internal events are plain strings that are not WoW events, fired with
-- ns.Fire: "SL_READY" (SavedVariables loaded), "SL_STEP" (current step changed),
-- "SL_ROUTE" (route changed), "SL_TICK" (0.5 s).

local ADDON, ns = ...
local C = ns.C

local handlers = {}
local frame = CreateFrame("Frame")
local reported = {}

local function dispatch(event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok and not reported[err] then
      reported[err] = true
      C.print("|cffff6060error in %s:|r %s  |cff999999/zug errors makes a report to copy|r", event, tostring(err))
      ns.noteError(event, err)
    end
  end
end

-- first: run before the handlers already there (Export reads a quest's
-- rewards before Assist accepts it and the frame closes).
function ns.On(event, fn, first)
  if not handlers[event] then
    handlers[event] = {}
    if not event:match("^SL_") then
      pcall(frame.RegisterEvent, frame, event) -- an event this client lacks is skipped, not fatal
    end
  end
  if first then table.insert(handlers[event], 1, fn) else table.insert(handlers[event], fn) end
end

ns.Fire = dispatch

-- Errors are kept (the last 20, in ZugzugLevelerDB.errors) so /zug errors can
-- show a report to copy and paste where the project takes bug reports, and the
-- companion page can say there were some. Nothing is sent anywhere.
function ns.noteError(event, err)
  if not ns.db then return end
  local list = ns.db.errors or {}
  ns.db.errors = list
  local version = C_AddOns and C_AddOns.GetAddOnMetadata and C.try(C_AddOns.GetAddOnMetadata, ADDON, "Version") or "?"
  list[#list + 1] = { at = C.epoch(), event = event, err = tostring(err), version = version }
  while #list > 20 do table.remove(list, 1) end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    ZugzugLevelerDB = ZugzugLevelerDB or {}
    ZugzugLevelerCharDB = ZugzugLevelerCharDB or {}
    ns.db, ns.cdb = ZugzugLevelerDB, ZugzugLevelerCharDB
    ns.db.version = 1
    dispatch("SL_READY")
    return
  end
  dispatch(event, ...)
end)
frame:RegisterEvent("ADDON_LOADED")

local TICK, acc = 0.5, 0
frame:SetScript("OnUpdate", function(_, dt)
  acc = acc + dt
  if acc < TICK then return end
  acc = 0
  if ns.db then dispatch("SL_TICK") end
end)
