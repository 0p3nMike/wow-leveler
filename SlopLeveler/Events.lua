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
      C.print("|cffff6060error in %s:|r %s", event, tostring(err))
    end
  end
end

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    if not event:match("^SL_") then
      pcall(frame.RegisterEvent, frame, event) -- an event this client lacks is skipped, not fatal
    end
  end
  table.insert(handlers[event], fn)
end

ns.Fire = dispatch

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    SlopLevelerDB = SlopLevelerDB or {}
    SlopLevelerCharDB = SlopLevelerCharDB or {}
    ns.db, ns.cdb = SlopLevelerDB, SlopLevelerCharDB
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
