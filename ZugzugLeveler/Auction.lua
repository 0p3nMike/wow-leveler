-- Auction.lua -- auction house prices, read by the game while you are at the
-- auction house, for the companion page's "what to craft for money".
--
-- C_AuctionHouse.ReplicateItems() asks for the whole auction house at once
-- (Blizzard_APIDocumentationGenerated AuctionHouseDocumentation.lua: "should be
-- used in place of an 'allItem' QueryAuctionItems call"); REPLICATE_ITEM_LIST_UPDATE
-- says it arrived; GetNumReplicateItems / GetReplicateItemInfo(index) read it:
-- name, texture, count, qualityID, usable, level, levelType, minBid,
-- minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner,
-- ownerFullName, saleStatus, itemID, hasAllInfo. It is started from a click
-- (the Read prices button on the auction house, or /zug prices), and the game
-- allows one such scan every 15 minutes. Read in slices over several frames.
-- Kept per realm and faction: ZugzugLevelerDB.prices["Realm-Faction"] =
--   { at, listings, items = { [itemID] = { p = lowest unit buyout (copper), n = listings, q = quantity, name } } }

local _, ns = ...
local C = ns.C

local A = {}
ns.Auction = A

local SCAN_EVERY = 15 * 60
local SLICE = 1500
local scanning = false

local function key() return (C.try(GetRealmName) or "?") .. "-" .. (C.try(UnitFactionGroup, "player") or "?") end
function A.prices() local p = ns.db.prices; return p and p[key()] end

local function open()
  local f = _G.AuctionHouseFrame
  return f and f.IsShown and C.try(f.IsShown, f)
end

function A.scan()
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then return C.print("this client has no auction house scan") end
  if not open() then return C.print("open the auction house first, then /zug prices (or the Read prices button)") end
  local wait = (ns.db.lastScan or 0) + SCAN_EVERY - C.epoch()
  if wait > 0 then return C.print("the game allows one full auction house read every 15 minutes: next in %d min", math.ceil(wait / 60)) end
  ns.db.lastScan, scanning = C.epoch(), true
  C.try(C_AuctionHouse.ReplicateItems)
  C.print("reading the auction house (a few seconds)...")
end

local function finish(items, listings)
  ns.db.prices = ns.db.prices or {}
  ns.db.prices[key()] = { at = C.epoch(), listings = listings, items = items }
  local n = 0
  for _ in pairs(items) do n = n + 1 end
  C.print("auction house read: %d listings, %d different items. The companion page (Character > Professions) shows what pays (after /reload or Sync).", listings, n)
end

function A.read()
  local total = C.try(C_AuctionHouse.GetNumReplicateItems) or 0
  local items, listings, i = {}, 0, 0
  local function slice()
    -- the docs do not say whether the index starts at 0 or 1: read 0..total and skip what is empty
    local stop = math.min(total, i + SLICE - 1)
    for k = i, stop do
      local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C.try(C_AuctionHouse.GetReplicateItemInfo, k)
      if type(itemID) == "number" and type(buyout) == "number" and buyout > 0 and type(count) == "number" and count > 0 then
        listings = listings + 1
        local unit = math.floor(buyout / count + 0.5)
        local e = items[itemID]
        if not e then e = { p = unit, n = 0, q = 0 }; items[itemID] = e end
        if unit < e.p then e.p = unit end
        e.n, e.q = e.n + 1, e.q + count
        if not e.name and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then e.name = name end
      end
    end
    i = stop + 1
    if i <= total and C_Timer and C_Timer.After then C_Timer.After(0, slice) elseif i <= total then slice() else finish(items, listings) end
  end
  slice()
end

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
  if scanning then scanning = false; A.read() end
end)

-- A Read prices button on the auction house window (a click is always allowed).
local button
ns.On("AUCTION_HOUSE_SHOW", function()
  local f = _G.AuctionHouseFrame
  if button or not f then return end
  button = CreateFrame("Button", "ZugzugLevelerPricesButton", f, "UIPanelButtonTemplate")
  button:SetSize(110, 20)
  button:SetPoint("TOPRIGHT", f, "TOPRIGHT", -60, -2)
  button:SetText("Read prices")
  button:SetScript("OnClick", A.scan)
  button:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText("zugzug_leveler: read prices")
      GameTooltip:AddLine("Reads the whole auction house (once every 15 minutes) so the companion page can show what is worth crafting.", 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end)
