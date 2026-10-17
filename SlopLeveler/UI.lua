-- UI.lua -- the step window and the export window.
--
-- Step window: route and step count, the current step, the next two, then
-- XP/hour, time to level and what the last step cost. Drag to move; the
-- position is saved. Templates used (BackdropTemplate, UIPanelCloseButton,
-- UIPanelScrollFrameTemplate) are all loaded on Forever: checked in the
-- 1.60.1 export's Blizzard_SharedXML.toc.

local _, ns = ...
local C, XP = ns.C, ns.XP

local UI = {}
ns.UI = UI

local WIDTH = 340
local f, lines

local function backdrop(frame)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.82)
    frame:SetBackdropBorderColor(0.56, 0.82, 0.31, 0.6)
  end
end

local function build()
  f = CreateFrame("Frame", "SlopLevelerFrame", UIParent, "BackdropTemplate")
  f:SetSize(WIDTH, 112)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    ns.db.ui = { point = point, rel = rel, x = x, y = y, shown = true }
  end)
  backdrop(f)
  local pos = ns.db.ui
  f:SetPoint(pos and pos.point or "TOPRIGHT", UIParent, pos and pos.rel or "TOPRIGHT", pos and pos.x or -240, pos and pos.y or -220)

  lines = {} -- a pool; refresh() fills as many as it needs and sizes the frame
  if ns.db.ui and ns.db.ui.shown == false then f:Hide() end
end

local function row(i)
  local fs = lines[i]
  if not fs then
    fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(WIDTH - 16)
    fs:SetJustifyH("LEFT")
    lines[i] = fs
  end
  return fs
end

-- The sub-objective block for a quest step: the game's live objective list
-- (this step's one highlighted), the guide's instruction, who to kill / see.
local function details(s, mode, out)
  local E = ns.Engine
  if s.q and (s.act == "complete" or s.act == "turnin") then
    for n, o in ipairs(C.objectives(s.q)) do
      if o.text and o.text ~= "" then
        local color = o.finished and "ff808080" or (s.obj == n and "ffffd100" or "ffffffff")
        out[#out + 1] = { ("  |c%s· %s|r"):format(color, o.text), "GameFontHighlightSmall" }
      end
    end
  end
  if s.act == "accept" and s.q and ns.Assist.notOffered[s.q] then
    out[#out + 1] = { "  |cffff6060not offered yet: missing a level or a lead-in quest|r", "GameFontHighlightSmall", wrap = true }
  end
  if s.hint then out[#out + 1] = { "  |cffb0b0b0" .. s.hint .. "|r", "GameFontHighlightSmall", wrap = true } end
  if s.mobs and mode == "work" then
    out[#out + 1] = { "  |cffff6060kill:|r " .. table.concat(s.mobs, ", "), "GameFontHighlightSmall", wrap = true }
  end
  if s.npc then out[#out + 1] = { "  |cff80ff80talk to:|r " .. s.npc, "GameFontHighlightSmall" } end
end

function UI.refresh()
  if not f then return end
  local E = ns.Engine
  local r = E.route()
  local rec = ns.Rec.active() and "  |cffff4040● REC|r" or ""
  local out = {}
  if r then
    local i = E.index()
    local s = E.step()
    local mode = ns.Way.mode and ns.Way.mode() or "travel"
    out[#out + 1] = { ("%s  |cff999999%d/%d|r%s"):format(r.name, math.min(i, #r.steps), #r.steps, rec), "GameFontNormalSmall" }
    if s and s.act == "complete" and mode == "work" then
      -- in the area: the objective IS the step
      local text, done = E.objective(s)
      out[#out + 1] = { ("|cffff8040%s|r %s"):format(done and "Done:" or "Do:", text or s.hint or E.describe(s)), "GameFontHighlight", wrap = true }
    else
      out[#out + 1] = { E.describe(s), "GameFontHighlight", wrap = true }
    end
    if s then details(s, mode, out) end
    for _, row in ipairs(ns.Danger and ns.Danger.rows() or {}) do out[#out + 1] = { row, "GameFontHighlightSmall", wrap = true } end
    local up = E.upcoming(3)
    for k = 2, #up do out[#out + 1] = { E.describe(r.steps[up[k]]), "GameFontDisableSmall" } end
    local plan, pend = ns.cdb.plan, ns.Optimizer and ns.Optimizer.pending
    if plan then
      out[#out + 1] = { ("|cff60ff60optimized order|r |cff999999(~%d yd shorter, %d left · /lev optimize clear)|r"):format(plan.save or 0, #plan.list), "GameFontDisableSmall" }
    elseif pend then
      out[#out + 1] = { ("|cffffd100a shorter order saves ~%d yd|r |cff999999/lev optimize|r"):format(math.floor(pend.save + 0.5)), "GameFontDisableSmall" }
    end
    local waiting = #E.deferred()
    if waiting > 0 then
      out[#out + 1] = { ("|cffc080ff%d set aside|r |cff999999(back on level-up · /swap back)|r"):format(waiting), "GameFontDisableSmall" }
    end
  else
    out[#out + 1] = { "sl0p.leveler" .. rec, "GameFontNormalSmall" }
    out[#out + 1] = { "No route. |cff999999/lev route list|r", "GameFontHighlight" }
    out[#out + 1] = { ns.Rec.active() and "Recording this run." or "|cff999999/lev rec start|r to record one.", "GameFontDisableSmall" }
  end
  local cur, max, lvl, rested = C.xp()
  local pctTxt = cur and max > 0 and string.format("%d%%", math.floor(cur / max * 100)) or "--"
  out[#out + 1] = { ("XP/h |cffffffff%s|r  ·  level in |cffffffff%s|r  ·  lvl %s %s%s"):format(
    XP.fmtNum(XP.rate()), XP.fmtTime(XP.ttl()), lvl or "?", pctTxt,
    (rested and rested > 0) and string.format("  |cff4fa3ffrested %s|r", XP.fmtNum(rested)) or ""), "GameFontHighlightSmall" }
  local st = ns.cdb.stats and r and ns.cdb.stats[E.index() - 1]
  local s = XP.session()
  out[#out + 1] = { ("%ssession %s, %s XP (%s quest)"):format(
    st and string.format("last step %s, %s XP  ·  ", XP.fmtTime(st.secs), XP.fmtNum(st.xp)) or "",
    XP.fmtTime(s and C.epoch() - s.start), XP.fmtNum(s and s.total), XP.fmtNum(s and s.quest)), "GameFontDisableSmall" }
  local split = r and ns.Splits and ns.Splits.line()
  if split then out[#out + 1] = { split, "GameFontHighlightSmall" } end
  if ns.Prof then
    local wl = ns.Prof.windowLine()
    if wl then out[#out + 1] = { wl, "GameFontHighlightSmall", wrap = true } end
    for _, row in ipairs(ns.Prof.lines()) do out[#out + 1] = { row, "GameFontHighlightSmall", wrap = true } end
  end
  local dt = ns.Downtime and ns.Downtime.line()
  if dt then out[#out + 1] = { dt, "GameFontHighlightSmall", wrap = true } end

  local y = -6
  for n, item in ipairs(out) do
    local fs = row(n)
    fs:SetFontObject(item[2])
    fs:SetWordWrap(item.wrap and true or false)
    fs:SetText(item[1])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 8, y)
    fs:Show()
    local h = (fs.GetStringHeight and fs:GetStringHeight()) or 0
    y = y - math.max(h, 12) - 3
  end
  for n = #out + 1, #lines do lines[n]:Hide() end
  f:SetHeight(-y + 4)
end

-- The window's visible rows as text (for tests and /lev why).
function UI.lines()
  local t = {}
  for _, fs in ipairs(lines or {}) do
    if fs:IsShown() then t[#t + 1] = fs:GetText() or fs.text end
  end
  return t
end

function UI.toggle()
  if not f then return end
  f:SetShown(not f:IsShown())
  ns.db.ui = ns.db.ui or {}
  ns.db.ui.shown = f:IsShown()
end

-- ------------------------------------------------------------ export window

local ex
function UI.showText(title, text)
  if not ex then
    ex = CreateFrame("Frame", "SlopLevelerExport", UIParent, "BackdropTemplate")
    ex:SetSize(560, 420)
    ex:SetPoint("CENTER")
    ex:SetFrameStrata("DIALOG")
    ex:EnableMouse(true)
    ex:SetMovable(true)
    ex:RegisterForDrag("LeftButton")
    ex:SetScript("OnDragStart", ex.StartMoving)
    ex:SetScript("OnDragStop", ex.StopMovingOrSizing)
    backdrop(ex)
    ex.title = ex:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ex.title:SetPoint("TOPLEFT", 10, -8)
    local close = CreateFrame("Button", nil, ex, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local scroll = CreateFrame("ScrollFrame", nil, ex, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(510)
    edit:SetScript("OnEscapePressed", function() ex:Hide() end)
    scroll:SetScrollChild(edit)
    ex.edit = edit
  end
  ex.title:SetText(title .. "  |cff999999(Ctrl+A, Ctrl+C)|r")
  ex.edit:SetText(text)
  ex:Show()
  ex.edit:SetFocus()
  ex.edit:HighlightText()
end

-- ----------------------------------------------------------------- events

local ticks = 0
ns.On("SL_READY", function() build(); UI.refresh() end)
ns.On("SL_STEP", UI.refresh)
ns.On("SL_ROUTE", UI.refresh)
ns.On("SL_XP", UI.refresh)
ns.On("SL_MODE", UI.refresh)
ns.On("QUEST_LOG_UPDATE", UI.refresh)
ns.On("PLAYER_ENTERING_WORLD", UI.refresh)
ns.On("SL_TICK", function()
  ticks = ticks + 1
  if ticks % 4 == 0 then UI.refresh() end -- every 2 s is plenty for the clock
end)
