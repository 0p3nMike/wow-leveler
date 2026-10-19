-- MapPath.lua -- the route drawn on the world map and the minimap.
--
-- World map: a data provider (WorldMapFrame:AddDataProvider, the way
-- Blizzard_WorldMap.lua adds its own; MapCanvasDataProviderMixin in
-- Blizzard_MapCanvas, 1.60.1 export). On every map change it draws, on the
-- map's canvas: a line from you through the next steps in route order (the
-- route RXP worked out; it is not re-optimised here), numbered markers, and
-- the current step's hunting loop. Lines are Line objects (CreateLine /
-- SetStartPoint / SetThickness, SimpleLineAPIDocumentation).
-- Minimap: markers for the next steps and the loop, placed from world
-- position: radius from C_Minimap.GetViewRadius, turned with GetPlayerFacing
-- when the rotateMinimap CVar is on. Points past the edge sit on the rim.
-- Objectives: for each unfinished quest in your log, the places AllTheThings
-- gives for its objectives (obj in data/Quests.lua: { map, x, y, crs }), as
-- orange diamonds on the world map and small dots on the minimap.

local _, ns = ...
local C, Route = ns.C, ns.Route

local M = {}
ns.MapPath = M

local AHEAD = 12 -- steps drawn ahead on the world map
local COLOR = {
  accept = { 1, 0.82, 0 }, complete = { 1, 0.5, 0.25 }, turnin = { 0.25, 1, 0.25 },
  ["goto"] = { 0.5, 0.75, 1 }, fly = { 0.5, 0.75, 1 }, hearth = { 0.5, 0.75, 1 },
  sethearth = { 0.75, 0.5, 1 }, train = { 0.75, 0.5, 1 }, note = { 0.8, 0.8, 0.8 },
}

local function on() return ns.db.mapPath ~= false end

-- World position of a step or path point: (cont, wx, wy).
local function world(p)
  Route.Resolve(p)
  if p.wx then return p.cont, p.wx, p.wy end
  if p.map and p.x then return C.worldPos(p.map, p.x, p.y) end
end

-- The points to draw: upcoming steps (skipping set-aside ones) and the
-- current step's loop. Each: { cont, wx, wy, n = step number, act, loop }.
function M.points()
  local E = ns.Engine
  local r = E.route()
  if not r then return {}, {} end
  local steps, loop = {}, {}
  local i = E.index()
  -- in the order they will be done: an optimizer plan first, then the route
  for _, j in ipairs(E.upcoming(AHEAD * 2)) do
    if #steps >= AHEAD then break end
    local s = r.steps[j]
    local cont, wx, wy = world(s)
    if cont then steps[#steps + 1] = { cont = cont, wx = wx, wy = wy, n = j, act = s.act } end
  end
  local cur = r.steps[i]
  for _, p in ipairs(cur and cur.loop and cur.path or {}) do
    if p.r then
      local cont, wx, wy = world(p)
      if cont then loop[#loop + 1] = { cont = cont, wx = wx, wy = wy } end
    end
  end
  return steps, loop
end

-- Objective places of the unfinished quests in your log: { cont, wx, wy, q }.
local OBJ_MAX = 40
function M.objectives()
  local out = {}
  local db = ns.QuestDB or {}
  for _, e in ipairs(ns.cdb and ns.cdb.questLog or {}) do
    local rec = e.q and not e.done and db[e.q]
    for _, o in ipairs(rec and rec.obj or {}) do
      if o[1] and o[2] and #out < OBJ_MAX then
        local cont, wx, wy = C.worldPos(o[1], o[2], o[3])
        if cont then out[#out + 1] = { cont = cont, wx = wx, wy = wy, q = e.q } end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- world map

local provider = {}
local overlay, lines, marks = nil, {}, {}

local function canvasXY(mapID, p)
  if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
  local _, pos = C.try(C_Map.GetMapPosFromWorldPos, p.cont, CreateVector2D(p.wx, p.wy), mapID)
  if not pos then return nil end
  local x, y = pos:GetXY()
  if x < -0.05 or x > 1.05 or y < -0.05 or y > 1.05 then return nil end -- off this map
  return x, y
end

local function line(n)
  if not lines[n] then lines[n] = overlay:CreateLine(nil, "OVERLAY") end
  return lines[n]
end

local function mark(n)
  if not marks[n] then
    local t = overlay:CreateTexture(nil, "OVERLAY")
    local fs = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", t, "CENTER", 0, 0)
    marks[n] = { t = t, fs = fs }
  end
  return marks[n]
end

function provider:RemoveAllData()
  for _, l in ipairs(lines) do l:Hide() end
  for _, m in ipairs(marks) do m.t:Hide(); m.fs:Hide() end
end

function provider:RefreshAllData()
  self:RemoveAllData()
  if not on() then return end
  local map = self:GetMap()
  local canvas = map:GetCanvas()
  if not overlay then
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel((canvas:GetFrameLevel() or 0) + 2000)
  end
  local mapID = map:GetMapID()
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  local scale = (map.GetCanvasScale and map:GetCanvasScale()) or 1
  local steps, loop = M.points()
  -- you are the start of the line
  local pm, px, py = C.mapPos()
  local pc, pwx, pwy = C.worldPos(pm, px, py)
  local chain = {}
  if pc then chain[1] = { cont = pc, wx = pwx, wy = pwy, me = true } end
  for _, p in ipairs(steps) do chain[#chain + 1] = p end
  local nl, prev = 0, nil
  for k, p in ipairs(chain) do
    local x, y = canvasXY(mapID, p)
    if x then
      local here = { x * w, -y * h }
      if prev then
        nl = nl + 1
        local l = line(nl)
        l:SetThickness(3 / scale)
        local c = COLOR[p.act] or COLOR.note
        l:SetColorTexture(c[1], c[2], c[3], k == 2 and 0.95 or 0.55)
        l:SetStartPoint("TOPLEFT", overlay, prev[1], prev[2])
        l:SetEndPoint("TOPLEFT", overlay, here[1], here[2])
        l:Show()
      end
      if not p.me then
        local m = mark(k)
        local c = COLOR[p.act] or COLOR.note
        local size = 10 / scale
        m.t:SetSize(size, size)
        m.t:SetColorTexture(c[1], c[2], c[3], 1)
        m.t:SetRotation(0)
        m.t:ClearAllPoints()
        m.t:SetPoint("CENTER", overlay, "TOPLEFT", here[1], here[2])
        m.t:Show()
        m.fs:SetText(p.n)
        m.fs:SetScale(1 / scale)
        m.fs:Show()
      end
      prev = here
    else
      prev = nil -- a gap where the route leaves this map
    end
  end
  -- objective places of the quests in your log: orange diamonds
  local nm = #chain
  for _, p in ipairs(M.objectives()) do
    local x, y = canvasXY(mapID, p)
    if x then
      nm = nm + 1
      local m = mark(nm)
      local size = 9 / scale
      m.t:SetSize(size, size)
      m.t:SetColorTexture(1, 0.55, 0.1, 0.9)
      m.t:SetRotation(math.pi / 4)
      m.t:ClearAllPoints()
      m.t:SetPoint("CENTER", overlay, "TOPLEFT", x * w, -y * h)
      m.t:Show()
      m.fs:Hide()
    end
  end
  -- the hunting loop, closed
  for k = 1, #loop do
    local a, b = loop[k], loop[k % #loop + 1]
    local ax, ay = canvasXY(mapID, a)
    local bx, by = canvasXY(mapID, b)
    if ax and bx and #loop > 1 then
      nl = nl + 1
      local l = line(nl)
      l:SetThickness(2 / scale)
      l:SetColorTexture(1, 0.5, 0.25, 0.5)
      l:SetStartPoint("TOPLEFT", overlay, ax * w, -ay * h)
      l:SetEndPoint("TOPLEFT", overlay, bx * w, -by * h)
      l:Show()
    end
  end
end

function provider:OnCanvasScaleChanged() self:RefreshAllData() end

function M.refreshWorld()
  if WorldMapFrame and WorldMapFrame:IsShown() and provider.GetMap and provider:GetMap() then provider:RefreshAllData() end
end

-- ------------------------------------------------------------------ minimap

local mini, dots = nil, {}
local MINI_DOTS = 8

local function dot(n)
  if not dots[n] then
    local t = mini:CreateTexture(nil, "OVERLAY")
    t:SetSize(7, 7)
    dots[n] = t
  end
  return dots[n]
end

-- Minimap offset in pixels for a world point, clamped to the rim.
function M.miniOffset(p, pc, pwx, pwy, facing, rotate, yardsRadius, pxRadius)
  if p.cont ~= pc then return nil end
  local dN, dW = p.wx - pwx, p.wy - pwy
  local east, north = -dW, dN
  if rotate and facing then
    -- the minimap turns so your facing is up: turn the world the other way
    local cs, sn = math.cos(facing), math.sin(facing)
    east, north = east * cs + north * sn, -east * sn + north * cs
  end
  local k = pxRadius / yardsRadius
  local x, y = east * k, north * k
  local d = math.sqrt(x * x + y * y)
  local edge = d > pxRadius - 4
  if edge then x, y = x / d * (pxRadius - 4), y / d * (pxRadius - 4) end
  return x, y, edge
end

local function miniUpdate()
  if not (mini and on()) then return end
  for _, t in ipairs(dots) do t:Hide() end
  local steps, loop = M.points()
  local pm, px, py = C.mapPos()
  local pc, pwx, pwy = C.worldPos(pm, px, py)
  if not pc then return end
  local yards = C_Minimap and C.try(C_Minimap.GetViewRadius)
  if not yards or yards <= 0 then return end
  local rotate = C.try(GetCVarBool, "rotateMinimap")
  local facing = rotate and C.try(GetPlayerFacing) or nil
  local radius = Minimap:GetWidth() / 2
  local n = 0
  local function put(p, r, g, b, size)
    local x, y, edge = M.miniOffset(p, pc, pwx, pwy, facing, rotate, yards, radius)
    if not x or n >= MINI_DOTS + #loop + 16 then return end
    n = n + 1
    local t = dot(n)
    t:SetSize(size, size)
    t:SetColorTexture(r, g, b, edge and 0.5 or 1)
    t:ClearAllPoints()
    t:SetPoint("CENTER", Minimap, "CENTER", x, y)
    t:Show()
  end
  for _, p in ipairs(loop) do put(p, 1, 0.5, 0.25, 5) end
  local objs = M.objectives()
  for k = 1, math.min(#objs, 10) do put(objs[k], 1, 0.55, 0.1, 5) end
  for _, hit in ipairs(ns.Danger and ns.Danger.near or {}) do -- threats near you, red
    put({ cont = hit.at[1], wx = hit.at[2], wy = hit.at[3] }, 1, 0.1, 0.1, 7)
  end
  for k = math.min(#steps, MINI_DOTS), 1, -1 do -- next step drawn last, on top
    local c = COLOR[steps[k].act] or COLOR.note
    put(steps[k], c[1], c[2], c[3], k == 1 and 9 or 6)
  end
end

-- ----------------------------------------------------------------- wiring

ns.On("SL_READY", function()
  if WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin then
    provider = Mixin(CreateFromMixins(MapCanvasDataProviderMixin), provider)
    WorldMapFrame:AddDataProvider(provider)
  end
  if Minimap then
    mini = CreateFrame("Frame", nil, Minimap)
    mini:SetAllPoints(Minimap)
    mini:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 5)
    local acc = 0
    mini:SetScript("OnUpdate", function(_, dt)
      acc = acc + dt
      if acc < 0.1 then return end
      acc = 0
      miniUpdate()
    end)
  end
end)

ns.On("SL_STEP", M.refreshWorld)
ns.On("SL_ROUTE", M.refreshWorld)
ns.On("QUEST_LOG_UPDATE", M.refreshWorld)

function M.toggle(v)
  ns.db.mapPath = v
  if not v and provider.RemoveAllData then provider:RemoveAllData() end
  M.refreshWorld()
  if not v then for _, t in ipairs(dots) do t:Hide() end end
end
