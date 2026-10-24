-- Bags.lua -- sort your bags: /zug sort, the Sort button on the backpack, a
-- key, or after looting (off by default).
--
-- Forever has Blizzard's own C_Container.SortBags (its 1.60.1 export). Mists of
-- Pandaria Classic and Classic Era do not (not in their ContainerDocumentation;
-- Era's bag frame even has Blizzard's sort button commented out,
-- Blizzard_UIPanels_Game/Classic/ContainerFrame.xml). There the items are moved
-- one swap at a time with C_Container.PickupContainerItem, the way bag addons
-- do it: pick up one slot, put it down on another, wait until the server has
-- unlocked both (ContainerItemInfo.isLocked, ITEM_LOCK_CHANGED), then the next.
--
-- Only the backpack and plain bags are sorted (GetContainerNumFreeSlots' bagFamily
-- 0): a quiver, ammo pouch, soul or herb bag keeps what it holds. Never in
-- combat, never with something already on the cursor.
--
-- Order: hearthstone, keys, quest items, consumables, weapons and armor,
-- trade goods and reagents, recipes, bags, the rest, junk (grey) last; within a
-- kind best quality first, then item level, name, bigger stack first.
-- GetItemInfo's 12th value is the item class (Enum.ItemClass, Era 1.15.9:
-- Consumable 0, Container 1, Weapon 2, Gem 3, Armor 4, Reagent 5, Projectile 6,
-- Tradegoods 7, ItemEnhancement 8, Recipe 9, Quiver 11, Questitem 12, Key 13,
-- Miscellaneous 15).

local _, ns = ...
local C = ns.C

local B = {}
ns.Bags = B

local HEARTHSTONE = 6948
local GROUP = { [13] = 1, [12] = 2, [0] = 3, [8] = 3, [6] = 3, [2] = 4, [4] = 4, [3] = 5, [7] = 5, [5] = 5, [9] = 6, [1] = 7, [11] = 7, [15] = 8 }
local JUNK, OTHER = 10, 9
local STEP, TIMEOUT = 0.05, 30 -- seconds between checks; give up after this long

local function numBags() return NUM_BAG_SLOTS or 4 end

-- the slots that are sorted: { { bag, slot } } in bag order
local function slots()
  local out = {}
  for bag = 0, numBags() do
    local _, family = C.try(C.bagFn("GetContainerNumFreeSlots"), bag)
    if bag == 0 or family == 0 then
      for slot = 1, (C.try(C.bagFn("GetContainerNumSlots"), bag) or 0) do out[#out + 1] = { bag, slot } end
    end
  end
  return out
end

-- what is in a slot: { id, count, locked } or nil when empty
local function read(s)
  local info = C.try(C.bagFn("GetContainerItemInfo"), s[1], s[2])
  if type(info) ~= "table" or not info.itemID then return nil end
  return { id = info.itemID, count = info.stackCount or 1, locked = info.isLocked, quality = info.quality, name = info.itemName }
end

local function itemInfo(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return C.try(f, id)
end

-- the sort key of an item: group, quality, item level, name
function B.key(it)
  local name, _, quality, ilvl, _, _, _, _, _, _, _, classID = itemInfo(it.id)
  quality = quality or it.quality or 1
  local group = (it.id == HEARTHSTONE and 0) or (quality == 0 and JUNK) or GROUP[classID or -1] or OTHER
  return { group, -quality, -(ilvl or 0), name or it.name or "", it.id, -it.count }
end

local function less(a, b)
  for k = 1, #a.key do
    if a.key[k] ~= b.key[k] then return a.key[k] < b.key[k] end
  end
  return false
end

-- the order the bags should end in: the item ID for each slot (nil = empty)
function B.plan(list)
  local items = {}
  for _, s in ipairs(list) do
    local it = read(s)
    if it then it.key = B.key(it); items[#items + 1] = it end
  end
  table.sort(items, less)
  local want = {}
  for k = 1, #list do want[k] = items[k] and items[k].id or false end
  return want
end

local job -- the sort in progress: { list, want, moves, started, quiet }

local function finish(msg)
  local j = job
  job = nil
  if msg and j and not (j.quiet and msg:find("^bags sorted")) then C.print(msg) end
end

local function blocked()
  if C.try(InCombatLockdown) or C.try(UnitAffectingCombat, "player") then return "not in combat: sort stopped" end
  if GetCursorInfo and C.try(GetCursorInfo) then return "something is on the cursor: sort stopped" end
end

-- one move, or wait for the last one to land
function B.step()
  local j = job
  if not j then return end
  local why = blocked()
  if why then return finish(why) end
  if C.now() - j.started > TIMEOUT then return finish("sorting took too long: stopped (sort again to finish)") end
  local cur = {}
  for k, s in ipairs(j.list) do
    local it = read(s)
    if it and it.locked then return B.later() end -- a move still landing
    cur[k] = it and it.id or false
  end
  for i = 1, #j.list do
    if cur[i] ~= j.want[i] then
      if not j.want[i] then break end -- everything wanted is placed
      local from
      for k = i + 1, #j.list do if cur[k] == j.want[i] then from = k; break end end
      if not from then return finish("your bags changed while sorting: sort again") end
      -- different items (cur[i] ~= want[i]), so the two never merge into one stack
      local pick = C.bagFn("PickupContainerItem")
      C.try(pick, j.list[from][1], j.list[from][2])
      C.try(pick, j.list[i][1], j.list[i][2])
      if GetCursorInfo and C.try(GetCursorInfo) then
        if ClearCursor then C.try(ClearCursor) end
        return finish("the game refused a move: sort stopped")
      end
      j.moves = j.moves + 1
      if j.moves > 2 * #j.list then return finish("sort stopped: too many moves") end
      return B.later()
    end
  end
  finish(("bags sorted (%d %s)"):format(j.moves, j.moves == 1 and "move" or "moves"))
end

function B.later()
  if C_Timer and C_Timer.After then C_Timer.After(STEP, B.step) end
end

function B.busy() return job ~= nil end

-- quiet: say nothing when it worked (the after-looting sort)
function B.sort(quiet)
  if job then return end
  local why = blocked()
  if why then if not quiet then C.print((why:gsub(": sort stopped", ": bags not sorted"))) end return end
  if C.game() == "forever" and C_Container and C_Container.SortBags then
    C.try(C_Container.SortBags) -- Blizzard's own sort
    if not quiet then C.print("bags sorted") end
    return
  end
  local list = slots()
  job = { list = list, want = B.plan(list), moves = 0, started = C.now(), quiet = quiet }
  B.step()
end

function B.auto() return ns.db.autoSort == true end
function B.setAuto(v) ns.db.autoSort = v and true or false end

ns.On("ITEM_LOCK_CHANGED", function() if job then B.step() end end)
ns.On("LOOT_CLOSED", function()
  if not B.auto() then return end
  if C_Timer and C_Timer.After then C_Timer.After(1.5, function() B.sort(true) end) else B.sort(true) end
end)

-- A Sort button on the backpack (Blizzard's ContainerFrame1), beside its search
-- box when it has one (Mists/ContainerFrame.lua puts BagItemSearchBox at the
-- backpack's top right). A bag addon that replaces the backpack hides it:
-- /zug sort and the key still work. Forever sorts with Blizzard's own button.
local button
local function makeButton()
  local bag = _G.ContainerFrame1
  if button or not bag or C.game() == "forever" then return end
  button = CreateFrame("Button", "ZugzugLevelerSortButton", bag, "UIPanelButtonTemplate")
  button:SetSize(40, 18)
  local search = _G.BagItemSearchBox
  if search and search.GetParent and search:GetParent() == bag then
    button:SetPoint("RIGHT", search, "LEFT", -6, 0)
  else
    button:SetPoint("TOPRIGHT", bag, "TOPRIGHT", -10, -26)
  end
  button:SetText("Sort")
  button:SetScript("OnClick", function() B.sort() end)
  button:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText("Sort your bags")
      GameTooltip:AddLine("zugzug_leveler. Quest items and consumables first, junk last. /zug sort auto on sorts after you loot.", 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
ns.On("PLAYER_ENTERING_WORLD", makeButton)

function ZugzugLeveler_Sort() B.sort() end
BINDING_NAME_ZUGZUGLEVELER_SORT = "Sort your bags"
