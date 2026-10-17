-- Options.lua -- every toggle in one place: Esc > Options > AddOns > sl0p.leveler
-- (or /lev options).
--
-- Built the way Blizzard's own guide says to (Blizzard_Settings_Shared/
-- Blizzard_ImplementationReadme.lua, 1.60.1 export): a vertical-layout
-- category, proxy settings that read and write our SavedVariables, checkboxes
-- and dropdowns, then Settings.RegisterAddOnCategory. The slash commands keep
-- working; both change the same values.

local _, ns = ...
local C = ns.C

local O = {}
ns.Options = O

-- { key, label, tooltip, get, set } -- get/set read our db (nil = the default)
local CHECKS = {
  { "SLOPLEV_WINDOW", "Step window", "The window with the step, objectives, XP/hour and splits.",
    function() return not (ns.db.ui and ns.db.ui.shown == false) end,
    function(v) if (not (ns.db.ui and ns.db.ui.shown == false)) ~= v then ns.UI.toggle() end end },
  { "SLOPLEV_ARROW", "Arrow", "The on-screen arrow to the next stop (our TomTom).",
    function() return ns.db.arrow ~= false end, function(v) ns.Arrow.toggle(v) end },
  { "SLOPLEV_PIN", "Map pin and in-world marker", "The game's own waypoint pin and floating marker for each step.",
    function() return ns.db.waypoint ~= false end, function(v) ns.db.waypoint = v; ns.Way.refresh() end },
  { "SLOPLEV_MAP", "Route lines on the map and minimap", "Line through the next steps, hunting loops, minimap dots.",
    function() return ns.db.mapPath ~= false end, function(v) ns.MapPath.toggle(v) end },
  { "SLOPLEV_DANGER", "Danger warnings", "Elites, rares and patrols near you and your next stop (RestedXP's Forever data).",
    function() return ns.db.danger ~= false end, function(v) ns.Danger.toggle(v) end },
  { "SLOPLEV_TARGET", "Target button", "Keybindable button that targets the step's mobs or NPC.",
    function() return ns.db.targetButton ~= false end, function(v) ns.db.targetButton = v; ns.Buttons.update() end },
  { "SLOPLEV_GREYS", "Sell grey items at vendors", nil,
    function() return ns.db.sellGreys ~= false end, function(v) ns.db.sellGreys = v end },
  { "SLOPLEV_RELEASE", "Auto-release on death", "Release and retrieve the corpse automatically. Off by default.",
    function() return ns.db.autoRelease == true end, function(v) ns.db.autoRelease = v end },
  { "SLOPLEV_PROF", "Profession help", "What to craft or gather next, materials vs your bags, trainer reminders.",
    function() return ns.db.prof ~= false end, function(v) ns.Prof.toggle(v) end },
  { "SLOPLEV_QLACCEPT", "Quest log mode picks up new quests", "Add quest givers on your map as accept steps.",
    function() return ns.db.qlAccept ~= false end,
    function(v) ns.db.qlAccept = v; if ns.QuestLog.active() then ns.QuestLog.rebuild(true) end end },
}

local DROPS = {
  { "SLOPLEV_OPTIMIZE", "Shortest-order optimizer",
    "Auto: the arrow follows the shortest order from where you stand. Suggest: tells you, /lev optimize applies. Off: the guide's order.",
    { "auto", "suggest", "off" }, { "Auto", "Suggest", "Off" },
    function() return ns.Optimizer.mode() end,
    function(v) ns.db.optimize = v end },
  { "SLOPLEV_ASSIST", "Auto accept / turn in",
    "Route: only quests on the route. All: every quest. Off: you click. Hold Shift to skip it once.",
    { "route", "all", "off" }, { "Route quests", "All quests", "Off" },
    function() return ns.db.assist or "route" end,
    function(v) ns.db.assist = v end },
}

function O.build()
  if O.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local category = Settings.RegisterVerticalLayoutCategory("sl0p.leveler")
  for _, d in ipairs(DROPS) do
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
  for _, c in ipairs(CHECKS) do
    local key, label, tip, get, set = unpack(c)
    local setting = Settings.RegisterProxySetting(category, key, Settings.VarType.Boolean, label, true, get,
      function(v) set(v); if ns.UI then ns.UI.refresh() end end)
    Settings.CreateCheckbox(category, setting, tip)
  end
  Settings.RegisterAddOnCategory(category)
  O.category = category
end

function O.open()
  O.build()
  if O.category and Settings.OpenToCategory then Settings.OpenToCategory(O.category:GetID()) end
end

ns.On("SL_READY", function() C.try(O.build) end)

O.CHECKS, O.DROPS = CHECKS, DROPS -- for the tests
