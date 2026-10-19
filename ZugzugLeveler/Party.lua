-- Party.lua -- levelling together: share where you are on the route with your
-- party, so two people stay in step.
--
-- C_ChatInfo.RegisterAddonMessagePrefix / SendAddonMessage and the
-- CHAT_MSG_ADDON event (ChatInfoDocumentation, 1.60.1 export); IsInGroup /
-- IsInRaid as Blizzard_CombatLog.lua uses them. Only party members running this
-- addon see it, and only while you are grouped. What is sent, one short line:
--   "1|route|step|steps|level|paused|quest|have|need"
-- (version 1; the quest is the current step's, with its first objective).
-- Kept in memory only: a party member's name is never written to the saves.

local _, ns = ...
local C = ns.C

local P = {}
ns.Party = P

local PREFIX = "ZUGZUG"
local EVERY = 30 -- seconds between updates while nothing changes
P.mates = {} -- sender -> { route, step, steps, level, paused, q, have, need, at }

local function on() return ns.db.party ~= false end
local function grouped() return IsInGroup and C.try(IsInGroup) end
local function channel() return (IsInRaid and C.try(IsInRaid)) and "RAID" or "PARTY" end

local function clean(s) return (tostring(s or ""):gsub("|", "/")):sub(1, 60) end

-- this character's line
function P.line()
  local E = ns.Engine
  local r, s = E.route(), E.step()
  local q, have, need = s and s.q, nil, nil
  if q then
    local o = C.objectives(q)[1]
    if o and not (issecretvalue and (issecretvalue(o.numFulfilled) or issecretvalue(o.numRequired))) then
      have, need = o.numFulfilled, o.numRequired
    end
  end
  return table.concat({ "1", clean(r and r.name), r and E.index() or 0, r and #r.steps or 0, C.try(UnitLevel, "player") or 0,
    ns.Pause.on() and 1 or 0, q or 0, have or "", need or "" }, "|")
end

local lastSent, lastLine = -100, nil
function P.send(force)
  if not (on() and grouped() and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  local line = P.line()
  if not force and line == lastLine and C.now() - lastSent < EVERY then return end
  lastSent, lastLine = C.now(), line
  C.try(C_ChatInfo.SendAddonMessage, PREFIX, line, channel())
end

function P.receive(prefix, text, _, sender)
  if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
  if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
  local me = C.try(UnitName, "player")
  local short = sender:match("^([^%-]+)") or sender
  if short == me then return end
  local f = {}
  for part in (text .. "|"):gmatch("([^|]*)|") do f[#f + 1] = part end
  if f[1] ~= "1" then return end -- a newer version's line: not understood
  P.mates[short] = { route = f[2], step = tonumber(f[3]) or 0, steps = tonumber(f[4]) or 0, level = tonumber(f[5]) or 0,
    paused = f[6] == "1", q = tonumber(f[7]), have = tonumber(f[8]), need = tonumber(f[9]), at = C.now() }
  if ns.UI then ns.UI.refresh() end
end

-- one line per party member for the window (Route tab), freshest first
function P.rows()
  if not on() then return {} end
  local E = ns.Engine
  local r = E.route()
  local out, now = {}, C.now()
  for name, m in pairs(P.mates) do
    if now - m.at > EVERY * 4 then
      P.mates[name] = nil -- gone quiet: left the group or logged off
    else
      local where
      if r and m.route == r.name then
        local d = m.step - E.index()
        where = d == 0 and "on your step" or (d > 0 and ("%d step%s ahead"):format(d, d == 1 and "" or "s") or ("%d step%s behind"):format(-d, d == -1 and "" or "s"))
      else
        where = m.route ~= "" and ("on %s, step %d"):format(m.route, m.step) or "no route"
      end
      local prog = m.need and m.need > 0 and (" · %d/%d"):format(m.have or 0, m.need) or ""
      out[#out + 1] = ("|cff80ff80%s|r |cff999999lvl %d|r %s%s%s"):format(name, m.level, where, prog, m.paused and " |cff8fb8f0(paused)|r" or "")
    end
  end
  table.sort(out)
  return out
end

function P.toggle(v) ns.db.party = v; if v then P.send(true) end end

ns.On("SL_READY", function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C.try(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end)
ns.On("CHAT_MSG_ADDON", function(...) P.receive(...) end)
ns.On("GROUP_ROSTER_UPDATE", function() P.send(true) end)
ns.On("SL_STEP", function() P.send(true) end)
ns.On("SL_PAUSE", function() P.send(true) end)
local ticks = 0
ns.On("SL_TICK", function()
  ticks = ticks + 1
  if ticks % 10 == 0 then P.send() end -- every 5 s: sends only when the line changed, or every 30 s
end)
