-- Arrow.lua -- our TomTom replacement: a fixed on-screen arrow to the target.
--
-- The game's own marker (Waypoint.lua) floats over the destination, and only
-- shows an edge arrow while the target is off screen. This is the always-there
-- "crazy arrow": turn until it points straight up, then run.
--
-- Math, all in the world vector Blizzard's C_Map.GetWorldPosFromMapPos returns:
--   +x is north, +y is west (HereBeDragons-2.0.lua processMap reads a map's
--   top from vector x and its left from vector y). GetPlayerFacing is radians
--   counter-clockwise from north. So the bearing to the target is
--   atan2(dWest, dNorth) in the same frame, and the arrow turns by
--   (bearing - facing): Texture:SetRotation is counter-clockwise too.
-- Not used: GetUnitSpeed, which Forever marks SecretWhenUnitStatsRestricted.
-- ETA comes from how fast the distance is actually shrinking.
--
-- Art: Blizzard's own "Navigation-Tracked-Arrow" atlas, the one their
-- SuperTrackedFrame.xml uses in the 1.60.1 export. Nothing copied from TomTom.

local _, ns = ...
local C, XP = ns.C, ns.XP

local A = {}
ns.Arrow = A

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local PI, TICK = math.pi, 0.05

local f, tex, title, dist
local target
local lastD, lastT, speed -- yards, seconds, yards/second (smoothed)

local function on() return ns.db.arrow ~= false end

-- Player's world position, the same way targets are converted (Compat.worldPos).
local function playerWorld()
  local m, x, y = C.mapPos()
  if not x then return nil end
  return C.worldPos(m, x, y)
end

-- (yards, relative angle) to the target, or nil.
function A.solve(t, pc, px, py, facing)
  if not (t and t.wx and pc and facing) or t.cont ~= pc then return nil end
  local dN, dW = t.wx - px, t.wy - py
  local d = math.sqrt(dN * dN + dW * dW)
  local rel = (atan2(dW, dN) - facing) % (2 * PI)
  return d, rel
end

-- green straight ahead, yellow to the side, red behind
function A.color(rel)
  local off = rel > PI and 2 * PI - rel or rel -- 0..pi
  local k = off / PI
  if k < 0.5 then return k * 2, 1, 0 end
  return 1, 1 - (k - 0.5) * 2, 0
end

local function build()
  f = CreateFrame("Button", "ZugzugLevelerArrow", UIParent)
  f:SetSize(64, 64)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("RightButtonUp")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    ns.db.arrowPos = { point = point, rel = rel, x = x, y = y }
  end)
  -- right-click: drop a /way, or skip past a step you do not want to walk to
  f:SetScript("OnClick", function()
    if target and target.manual then ns.Way.clearManual() else C.print("right-click clears a /way; /lev skip skips a step") end
  end)
  local pos = ns.db.arrowPos
  f:SetPoint(pos and pos.point or "TOP", UIParent, pos and pos.rel or "TOP", pos and pos.x or 0, pos and pos.y or -140)

  tex = f:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  -- The art points up at rotation 0: SuperTrackedFrame turns it with
  -- SetRotation(-angle) where angle is measured from UP_VECTOR (0, 1).
  if C_Texture and C.try(C_Texture.GetAtlasInfo, "Navigation-Tracked-Arrow") then
    tex:SetAtlas("Navigation-Tracked-Arrow")
  else
    tex:SetTexture("Interface\\Minimap\\MinimapArrow") -- fallback if the atlas ever goes away
  end

  title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "BOTTOM", 0, -2)
  title:SetWidth(260)
  title:SetWordWrap(false)
  dist = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dist:SetPoint("TOP", title, "BOTTOM", 0, -2)
  f:Hide()
  if target and on() then title:SetText(target.text or ""); f:Show() end

  local acc = 0
  f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < TICK then return end
    acc = 0
    A.update()
  end)
end

function A.update()
  if not f then return end
  local pc, px, py = playerWorld()
  local facing = C.try(GetPlayerFacing)
  local d, rel = A.solve(target, pc, px, py, facing)
  if not d then
    -- no facing (instances), other continent, or no world position
    tex:SetRotation(0)
    tex:SetVertexColor(0.5, 0.5, 0.5)
    dist:SetText(target and target.cont and pc and target.cont ~= pc and "other continent" or "")
    return
  end
  tex:SetRotation(rel)
  tex:SetVertexColor(A.color(rel))
  local now = C.now()
  if lastD and now > lastT then
    local v = (lastD - d) / (now - lastT)
    speed = speed and (speed * 0.9 + v * 0.1) or v
  end
  lastD, lastT = d, now
  local eta = speed and speed > 0.5 and d / speed or nil
  dist:SetFormattedText("%d yd%s", math.floor(d + 0.5), eta and ("  ·  " .. XP.fmtTime(eta)) or "")
  if target.manual and d <= (target.r or 8) then
    C.print("arrived: %s", target.text or "/way")
    ns.Way.clearManual()
  end
end

ns.On("SL_TARGET", function(t)
  -- a new place resets the ETA; a new objective count on the same place does not
  local moved = not (t and target and t.wx == target.wx and t.wy == target.wy)
  target = t
  if moved then lastD, lastT, speed = nil, nil, nil end
  if not f then return end
  if t and on() then
    title:SetText(t.text or "")
    -- work mode with no hunting loop: you are there, the objective matters, not the arrow
    f:SetAlpha(t.dim and 0.35 or 1)
    f:Show()
    A.update()
  else
    f:Hide()
  end
end)

ns.On("SL_READY", build)

function A.toggle(v)
  ns.db.arrow = v
  if f then
    if v and target then f:Show() else f:Hide() end
  end
end
