-- Options.lua -- every toggle in one place: Esc > Options > AddOns > zugzugleveler
-- (or /zug options).
--
-- Built the way Blizzard's own guide says to (Blizzard_Settings_Shared/
-- Blizzard_ImplementationReadme.lua, 1.60.1 export): a vertical-layout
-- category, proxy settings that read and write our SavedVariables, checkboxes
-- and dropdowns, then Settings.RegisterAddOnCategory. Section headings are
-- CreateSettingsListSectionHeaderInitializer on the category's layout, as
-- Blizzard's AdvancedOptions.lua does. The slash commands keep working; both
-- change the same values.

local _, ns = ...
local C = ns.C

local O = {}
ns.Options = O

-- dropdown: { key, label, tooltip, values, names, get, set }
local DROPS = {
  { "ZUGZUG_GOAL", "How you play",
    "Fastest leveling leaves cooking, first aid and crafting trainers out of the route. Completion keeps everything in. The companion page's Planner tab changes the same choice.",
    { "none", "speed", "complete" }, { "Not chosen yet", "Fastest leveling", "Completion" },
    function() return ns.Route.goal() or "none" end,
    function(v)
      if v == "none" then ns.db.goal, ns.db.goalAt = nil, C.epoch() else ns.db.goal, ns.db.goalAt = v, C.epoch() end
      ns.db.goalAsked = true
    end },
  { "SLOPLEV_OPTIMIZE", "Shortest-order optimizer",
    "Auto: the arrow follows the shortest order from where you stand. Suggest: tells you, /zug optimize applies. Off: the guide's order.",
    { "auto", "suggest", "off" }, { "Auto", "Suggest", "Off" },
    function() return ns.Optimizer.mode() end,
    function(v) ns.db.optimize = v end },
  { "SLOPLEV_ASSIST", "Auto accept / turn in",
    "Route: only quests on the route. All: every quest. Off: you click. Hold Shift to skip it once.",
    { "route", "all", "off" }, { "Route quests", "All quests", "Off" },
    function() return ns.db.assist or "route" end,
    function(v) ns.db.assist = v end },
}

-- checkbox: { key, label, tooltip, get, set } -- get/set read our db (nil = the default)
local PLAY = {
  { "ZUGZUG_PAUSE", "Paused (a detour of your own)",
    "Nothing is timed, the coach is quiet and the arrow rests; a /way still guides you. Also the window's pause button and /zug pause.",
    function() return ns.Pause.on() end, function(v) ns.Pause.set(v) end },
}

local SCREEN = {
  { "SLOPLEV_WINDOW", "Step window", "The window with the step, objectives, XP/hour and splits.",
    function() return not (ns.db.ui and ns.db.ui.shown == false) end,
    function(v) if (not (ns.db.ui and ns.db.ui.shown == false)) ~= v then ns.UI.toggle() end end },
  { "ZUGZUG_PEON", "The talking peon", "Beside the window: says what the coach says. Click him. Off by default.",
    function() return ns.db.peon == true end, function(v) ns.Peon.toggle(v) end },
  { "SLOPLEV_ARROW", "Arrow", "The on-screen arrow to the next stop (our TomTom).",
    function() return ns.db.arrow ~= false end, function(v) ns.Arrow.toggle(v) end },
  { "SLOPLEV_PIN", "Map pin and in-world marker", "The game's own waypoint pin and floating marker for each step.",
    function() return ns.db.waypoint ~= false end, function(v) ns.db.waypoint = v; ns.Way.refresh() end },
  { "SLOPLEV_MAP", "Route lines on the map and minimap", "Line through the next steps, hunting loops, minimap dots.",
    function() return ns.db.mapPath ~= false end, function(v) ns.MapPath.toggle(v) end },
  { "SLOPLEV_DANGER", "Danger warnings", "Elites, rares and patrols near you and your next stop (RestedXP's Forever data).",
    function() return ns.db.danger ~= false end, function(v) ns.Danger.toggle(v) end },
  { "ZUGZUG_AUTOSORT", "Sort bags after looting", "Sorts your bags a moment after a loot window closes. /zug sort (or the backpack's Sort button) sorts any time.",
    function() return ns.Bags.auto() end, function(v) ns.Bags.setAuto(v) end },
  { "SLOPLEV_TARGET", "Target button", "Keybindable button that targets the step's mobs or NPC.",
    function() return ns.db.targetButton ~= false end, function(v) ns.db.targetButton = v; ns.Buttons.update() end },
}

-- hardcore and self-found: the game says, these override it (per character)
local STYLE = {
  { "ZUGZUG_HARDCORE", "Hardcore steps", "RestedXP's hardcore-only steps (and not its softcore-only ones). Follows the game's hardcore setting unless you change it here.",
    function() return ns.Engine.hardcore() end, function(v) ns.cdb.hardcore = v; ns.Engine.evaluate() end },
  { "ZUGZUG_SSF", "Self-found steps", "RestedXP's self-found steps (no auction house). Follows the game's self-found setting unless you change it here.",
    function() return ns.Engine.ssf() end, function(v) ns.cdb.ssf = v; ns.Engine.evaluate() end },
}

local HELP = {
  { "ZUGZUG_COACH", "Coach", "A heads-up when the route changes zone, and a question when you seem stuck or lost.",
    function() return ns.db.coach ~= false end, function(v) ns.db.coach = v end },
  { "ZUGZUG_LIVE", "Live updates for the companion page",
    "Turns on the game's chat log (what /chatlog does), so the page shows XP, levels and quests as you play. It is a file on this PC; nothing is sent anywhere.",
    function() return ns.Live.logging() end, function(v) ns.Live.set(v) end },
  { "ZUGZUG_TALENTS", "Talent advice", "Which talent to take next, from RestedXP's talent guides (/zug talents).",
    function() return ns.db.talents ~= false end, function(v) ns.db.talents = v end },
  { "ZUGZUG_PARTY", "Share your route place with your party",
    "Party members with this addon see your step, level and quest progress in their window, and you see theirs. Nothing is saved or sent outside the group.",
    function() return ns.db.party ~= false end, function(v) ns.Party.toggle(v) end },
  { "SLOPLEV_PROF", "Profession help", "What to craft or gather next, materials vs your bags, trainer reminders.",
    function() return ns.db.prof ~= false end, function(v) ns.Prof.toggle(v) end },
  { "SLOPLEV_QLACCEPT", "Quest log mode picks up new quests", "Add quest givers on your map as accept steps.",
    function() return ns.db.qlAccept ~= false end,
    function(v) ns.db.qlAccept = v; if ns.QuestLog.active() then ns.QuestLog.rebuild(true) end end },
  { "SLOPLEV_GREYS", "Sell grey items at vendors", nil,
    function() return ns.db.sellGreys ~= false end, function(v) ns.db.sellGreys = v end },
  { "SLOPLEV_RELEASE", "Auto-release on death", "Release and retrieve the corpse automatically. Off by default.",
    function() return ns.db.autoRelease == true end, function(v) ns.db.autoRelease = v end },
}

-- what the route includes: one box per step kind (Route.CATEGORIES), ticked = kept in
local KINDS = { "classtrain", "pettrain", "weapons", "food", "cooking", "firstaid", "professions", "optional" }
local function routeBoxes()
  local t = {}
  for _, k in ipairs(KINDS) do
    local cat = ns.Route.CATEGORIES[k]
    if cat then
      t[#t + 1] = { "ZUGZUG_KIND_" .. k:upper(), cat.label,
        "Untick to leave these steps out of the route. The companion page's Plan & Runs changes the same list (whichever you changed last wins).",
        function() local s = ns.Route.skips(); return not (s and s[k]) end,
        function(v) ns.Route.setSkip(k, not v); if ns.Engine.route() then ns.Engine.evaluate() end end }
    end
  end
  return t
end

function O.build()
  if O.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local category, layout = Settings.RegisterVerticalLayoutCategory("zugzug_leveler")
  local function header(text)
    if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
      layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
  end
  local function check(c)
    local key, label, tip, get, set = unpack(c)
    local setting = Settings.RegisterProxySetting(category, key, Settings.VarType.Boolean, label, true, get,
      function(v) set(v); if ns.UI then ns.UI.refresh() end end)
    Settings.CreateCheckbox(category, setting, tip)
  end
  local function drop(d)
    local key, label, tip, values, names, get, set = unpack(d)
    local function getNum()
      local v = get()
      for k, val in ipairs(values) do if val == v then return k end end
      return 1
    end
    local setting = Settings.RegisterProxySetting(category, key, Settings.VarType.Number, label, 1, getNum,
      function(n) set(values[n] or values[1]); if ns.UI then ns.UI.refresh() end end)
    local function options()
      local box = Settings.CreateControlTextContainer()
      for k, nm in ipairs(names) do box:Add(k, nm) end
      return box:GetData()
    end
    Settings.CreateDropdown(category, setting, options, tip)
  end
  header("How you play")
  for _, d in ipairs(DROPS) do drop(d) end
  for _, c in ipairs(PLAY) do check(c) end
  for _, c in ipairs(STYLE) do check(c) end
  header("On screen")
  for _, c in ipairs(SCREEN) do if c[1] ~= "ZUGZUG_PEON" or ns.Peon.ENABLED then check(c) end end
  header("Help")
  for _, c in ipairs(HELP) do check(c) end
  header("What your route includes")
  for _, c in ipairs(routeBoxes()) do check(c) end
  Settings.RegisterAddOnCategory(category)
  O.category = category
end

function O.open()
  O.build()
  if O.category and Settings.OpenToCategory then Settings.OpenToCategory(O.category:GetID()) end
end

ns.On("SL_READY", function() C.try(O.build) end)

O.DROPS, O.KINDS = DROPS, KINDS -- for the tests
