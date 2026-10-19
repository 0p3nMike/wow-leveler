-- Live.lua -- fresher data for the companion page.
--
-- An addon's saved data reaches the disk only on /reload or logout, and an
-- addon cannot write files or open connections. Two things help:
--
--   sync   /zug sync, the Sync button on the window, or a key (Key Bindings >
--          AddOns): saves now by reloading the UI (C_UI.Reload, via ReloadUI
--          in Blizzard_SharedXML InterfaceUtil.lua). A few seconds of loading
--          screen, and the page has everything.
--   live   the game's own chat log. LoggingChat(true) (what /chatlog does,
--          Blizzard_ChatFrameBase SlashCommands.lua) makes the client write
--          chat to Logs\WoWChatLog.txt, its system lines included: "Quest
--          accepted: %s", "%s completed.", "%s dies, you gain %d experience.",
--          the level-up line, loot (GlobalStrings enUS, Ketho's
--          BlizzardInterfaceResources forever branch). The companion follows
--          that file, so XP, level and quest events show between saves.
--          It is a log of ALL your chat on this PC, so it is asked once, never
--          switched on silently. /zug live on|off.
--   check  /zug live check prints one marker line; the companion page shows
--          whether it reached the log, and how late, which tells whether the
--          client writes the log as you play or only now and then.

local _, ns = ...
local C = ns.C

local Live = {}
ns.Live = Live

function Live.logging() return LoggingChat and C.try(LoggingChat) and true or false end

function Live.set(on)
  ns.db.live = on and true or false
  if LoggingChat then C.try(LoggingChat, on and true or false) end
  C.print("live updates for the companion page: %s%s", on and "on" or "off",
    on and " |cff999999(the game now writes chat to Logs\\WoWChatLog.txt on this PC; /zug live off stops it)|r" or "")
end

function Live.check()
  if not Live.logging() then return C.print("live updates are off: /zug live on first") end
  -- the companion looks for this exact shape: "zugzugleveler live check <epoch>"
  C.print("live check %d (the companion page shows whether this line reached the chat log)", C.epoch())
  ns.cdb.liveCheck = C.epoch()
end

function Live.sync()
  ns.cdb.syncAt = C.epoch()
  if ReloadUI then ReloadUI() elseif C_UI and C_UI.Reload then C_UI.Reload() end
end
-- for the key binding (Bindings.xml)
function ZugzugLeveler_Sync() Live.sync() end
BINDING_NAME_ZUGZUGLEVELER_SYNC = "Save now for the companion page (reloads the UI)"

local asked
ns.On("PLAYER_ENTERING_WORLD", function()
  if ns.db.live == true then
    if not Live.logging() and LoggingChat then C.try(LoggingChat, true) end
  elseif ns.db.live == nil and not asked and ns.Coach then
    asked = true
    local function ask()
      ns.Coach.ask("live", "Show XP, level and quests on the companion page as you play, between saves? This turns on the game's chat log (Logs\\WoWChatLog.txt on this PC).",
        "Turn it on", "Not now", function() Live.set(true) end, "/zug live on | /zug live off")
    end
    if C_Timer and C_Timer.After then C_Timer.After(6, ask) else ask() end
  end
end)

-- The chat log in the player's language: the client's own format strings for
-- the lines the companion reads (chatlog.go, chatlocale.go), so a German or
-- French client is read in German or French. English clients save them too
-- (the companion keeps its built-in patterns for those).
--   ZugzugLevelerDB.chatStrings = { locale, at, s = { KEY = format } }
Live.CHAT_KEYS = { "ERR_QUEST_ACCEPTED_S", "ERR_QUEST_COMPLETE_S", "COMBATLOG_XPGAIN_FIRSTPERSON",
  "COMBATLOG_XPGAIN_EXHAUSTION1", "COMBATLOG_XPGAIN_EXHAUSTION2", "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED",
  "ERR_QUEST_REWARD_EXP_I", "ERR_ZONE_EXPLORED_XP", "LEVEL_UP", "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
  "LOOT_ITEM_PUSHED_SELF", "YOU_LOOT_MONEY", "ERR_QUEST_REWARD_MONEY_S" }
ns.On("SL_READY", function()
  local s = {}
  for _, k in ipairs(Live.CHAT_KEYS) do
    local v = _G[k]
    if type(v) == "string" then s[k] = v end
  end
  ns.db.chatStrings = { locale = C.try(GetLocale) or "enUS", at = C.epoch(), s = s }
end)
