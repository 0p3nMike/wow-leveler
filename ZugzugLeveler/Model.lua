-- Model.lua -- your character in 3D, inside the game (/zug model).
--
-- The game draws it: a PlayerModel from Blizzard's own "ModelTemplate"
-- (Blizzard_SharedXML ModelFrameTemplates.xml: ModelFrameMixin, drag to turn),
-- set to your unit, so it wears exactly what you wear, face and hair included.
-- The companion page shows a 3D character only if the player turns on
-- Wowhead pictures there; this one needs nothing outside the game.

local _, ns = ...
local C = ns.C

local Model = {}
ns.Model = Model

local f
local function build()
  f = CreateFrame("Frame", "ZugzugLevelerModel", UIParent, "BackdropTemplate")
  f:SetSize(260, 360)
  f:SetPoint("CENTER", 300, 0)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("DIALOG")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetBackdropBorderColor(0.56, 0.82, 0.31, 0.6)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -8)
  title:SetText(C.try(UnitName, "player") or "You")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  local ok, m = pcall(CreateFrame, "PlayerModel", nil, f, "ModelTemplate")
  if not ok then m = CreateFrame("PlayerModel", nil, f) end
  m:SetPoint("TOPLEFT", 6, -28)
  m:SetPoint("BOTTOMRIGHT", -6, 22)
  f.model = m
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOM", 0, 6)
  hint:SetText("drag the character to turn it")
  f:Hide()
end

function Model.toggle()
  if not f then build() end
  if f:IsShown() then f:Hide() return end
  C.try(f.model.SetUnit, f.model, "player")
  f:Show()
end

-- what you wear changes: redress the model while it is open
ns.On("PLAYER_EQUIPMENT_CHANGED", function()
  if f and f:IsShown() then C.try(f.model.SetUnit, f.model, "player") end
end)
