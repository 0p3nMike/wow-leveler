-- Buttons.lua -- two keybindable buttons for the current step. YOU press them.
--
--   ZugzugLevelerItemButton    uses the step's quest item (RXP .use)
--   ZugzugLevelerTargetButton  /targetexact the step's mobs (RXP .mob), or its NPC
--
-- Both are SecureActionButtonTemplate buttons (type=item / type=macro), the
-- same mechanism as an action bar slot: the game runs them only from your click
-- or key press. Checked in the 1.60.1 export: SECURE_ACTIONS.item ("item"
-- attribute) and .macro ("macrotext") in Blizzard_FrameXML/SecureTemplates.lua;
-- /targetexact is SLASH_COMMAND.TARGET_EXACT. Registered for AnyUp+AnyDown:
-- SecureActionButton_OnClick then fires once, on whichever the
-- ActionButtonUseKeyDown setting picks. Bindings: Bindings.xml (Key Bindings >
-- AddOns > zugzugleveler).
--
-- Secure frames cannot be changed in combat, so updates wait for
-- PLAYER_REGEN_ENABLED.

local _, ns = ...
local C = ns.C

local B = {}
ns.Buttons = B

BINDING_HEADER_ZUGZUGLEVELER = "zugzug_leveler"
_G["BINDING_NAME_CLICK ZugzugLevelerItemButton:LeftButton"] = "Use the step's quest item"
_G["BINDING_NAME_CLICK ZugzugLevelerTargetButton:LeftButton"] = "Target the step's mob / NPC"

local item, target, pending

local function make(name, icon)
  local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
  b:SetSize(36, 36)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetMovable(true)
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self) if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end end)
  b:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rel, x, y = self:GetPoint()
    ns.db.buttons = ns.db.buttons or {}
    ns.db.buttons[name] = { point = p, rel = rel, x = x, y = y }
  end)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexture(icon)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:Hide()
  return b
end

local function place(b, name, dx)
  local pos = ns.db.buttons and ns.db.buttons[name]
  b:ClearAllPoints()
  if pos then
    b:SetPoint(pos.point, UIParent, pos.rel, pos.x, pos.y)
  else
    b:SetPoint("TOP", ZugzugLevelerArrow or UIParent, "BOTTOM", dx, -40)
  end
end

-- The macro for a step: its mobs, else the NPC to talk to.
function B.targetMacro(s)
  local names = (s and s.mobs) or (s and s.npc and { s.npc }) or nil
  if not names or #names == 0 then return nil end
  local lines = {}
  for i = #names, 1, -1 do lines[#lines + 1] = "/targetexact " .. names[i] end -- first name wins: it runs last
  return table.concat(lines, "\n")
end

function B.update()
  if not item then return end
  if InCombatLockdown() then pending = true; return end
  pending = false
  local s = ns.Engine.step()
  -- quest item: only if it is actually in the bags
  local id = s and s.use
  local count = id and C_Item and C.try(C_Item.GetItemCount, id) or 0
  if id and count > 0 then
    item:SetAttribute("type", "item")
    item:SetAttribute("item", "item:" .. id)
    item.icon:SetTexture(C.try(C_Item.GetItemIconByID, id) or 134400)
    item.tip = (C.try(C_Item.GetItemNameByID, id) or ("item " .. id))
    item:Show()
  else
    item:Hide()
  end
  local macro = ns.db.targetButton ~= false and B.targetMacro(s)
  if macro then
    target:SetAttribute("type", "macro")
    target:SetAttribute("macrotext", macro)
    target.tip = macro:gsub("/targetexact ", ""):gsub("\n", ", ")
    target:Show()
  else
    target:Hide()
  end
end

local function tooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(self.tip or "")
  GameTooltip:AddLine("Shift-drag to move. Bind a key: Key Bindings > AddOns.", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

ns.On("SL_READY", function()
  item = make("ZugzugLevelerItemButton", 134400)
  target = make("ZugzugLevelerTargetButton", "Interface\\Icons\\Ability_Hunter_SniperShot")
  place(item, "ZugzugLevelerItemButton", -22)
  place(target, "ZugzugLevelerTargetButton", 22)
  for _, b in ipairs({ item, target }) do
    b:SetScript("OnEnter", tooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
end)

ns.On("SL_STEP", B.update)
ns.On("SL_ROUTE", B.update)
ns.On("BAG_UPDATE_DELAYED", B.update)
ns.On("PLAYER_REGEN_ENABLED", function() if pending then B.update() end end)
