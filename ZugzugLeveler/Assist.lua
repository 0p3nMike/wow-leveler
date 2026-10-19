-- Assist.lua -- the clicking between steps: accept, turn in, sell greys.
--
-- Adapted from ghoul's GhoulBridge assist() / gossipPick() / greetingPick() /
-- sellGreys(), which are Michael's own. Changed for a real account:
--   * By default it only acts on quests in the active route (/zug assist
--     route|all|off). Hold Shift while talking to an NPC to do it yourself.
--   * It never picks between rewards. With a choice it prints the one that
--     sells best and leaves the window open for you.
--   * It follows Blizzard's own QuestFrame rules (Mainline QuestFrame.lua in
--     the 1.60.1 export): no PvP-flagged quests, nothing that costs gold.
--   * Auto-release on death is off unless you turn it on (/zug release on).
-- All of these are unprotected calls the default UI makes from its own
-- buttons. None of ghoul's bot (keys, screen reading) is part of this addon.

local _, ns = ...
local C = ns.C
local try = C.try

local A = {}
ns.Assist = A

local recent = {} -- questID -> epoch of our last pick, so a refused pick cannot loop

local function mode() return ns.db.assist or "route" end

function A.wanted(q, act)
  local m = mode()
  if m == "off" or not q then return false end
  if try(IsShiftKeyDown) then return false end
  if m == "all" then return true end
  local r = ns.Engine.route()
  if not r then return false end
  for _, s in ipairs(r.steps) do
    if s.q == q and (s.act == act or (act == "turnin" and s.act == "complete")) then return true end
  end
  return false
end

local function fresh(q)
  local now = C.epoch()
  if recent[q] and now - recent[q] < 3 then return false end
  recent[q] = now
  return true
end

-- ------------------------------------------------------------ quest frame

local function onDetail()
  local q = try(GetQuestID)
  if try(QuestFlagsPVP) then return end
  if QuestFrame and QuestFrame.autoQuest then return end -- auto-accept quests are already taken
  if A.wanted(q, "accept") then try(AcceptQuest) end
end

local function onProgress()
  local q = try(GetQuestID)
  if try(IsQuestCompletable) and A.wanted(q, "turnin") then try(CompleteQuest) end
end

local function bestSellChoice(n)
  local best, bestPrice
  for i = 1, n do
    local link = try(GetQuestItemLink, "choice", i)
    local price = link and select(11, try(C_Item and C_Item.GetItemInfo or GetItemInfo, link))
    if type(price) == "number" and (not bestPrice or price > bestPrice) then best, bestPrice = link, price end
  end
  return best, bestPrice
end

local function onComplete()
  local q = try(GetQuestID)
  if not A.wanted(q, "turnin") then return end
  local money = try(GetQuestMoneyToGet)
  if money and money > 0 then return end
  local n = try(GetNumQuestChoices) or 0
  if n > 1 then
    local link, price = bestSellChoice(n)
    if link then C.print("reward choice: best vendor price is %s (%s)", link, try(GetCoinTextureString, price) or price) end
    return
  end
  try(GetQuestReward, n == 1 and 1 or 0)
end

-- --------------------------------------------------- gossip and greetings

local function onGossip()
  if not (C_GossipInfo and C_GossipInfo.GetActiveQuests) then return end
  for _, info in ipairs(try(C_GossipInfo.GetActiveQuests) or {}) do
    if info.isComplete and A.wanted(info.questID, "turnin") and fresh(info.questID) then
      try(C_GossipInfo.SelectActiveQuest, info.questID)
      return
    end
  end
  for _, info in ipairs(try(C_GossipInfo.GetAvailableQuests) or {}) do
    if A.wanted(info.questID, "accept") and fresh(info.questID) then
      try(C_GossipInfo.SelectAvailableQuest, info.questID)
      return
    end
  end
end

-- ----------------------------------------------------- "not offered yet"
-- The game says nothing about whether an NPC WILL offer a quest until you
-- open their quest list. So when you talk to the current accept step's NPC
-- (matched by name, or by standing within 25 yd of the step) and the quest is
-- not in what they offer, mark it: you are missing a level or a lead-in quest.

A.notOffered = {} -- questID -> true, this session

local function atStepNpc(s)
  local who = try(UnitName, "npc")
  if s.npc and who then return who == s.npc end
  local d = ns.Engine.yardsTo(s)
  return d ~= nil and d <= 25
end

function A.checkOffered(offered)
  local s = ns.Engine.step()
  if not (s and s.act == "accept" and s.q) then return end
  if C.isOnQuest(s.q) or C.isTurnedIn(s.q) or not atStepNpc(s) then return end
  if offered[s.q] then
    A.notOffered[s.q] = nil
  elseif not A.notOffered[s.q] then
    A.notOffered[s.q] = true
    C.print("|cffff6060%s isn't offering %s yet|r: you're missing a level or a lead-in quest. /zug why · /zug skip",
      try(UnitName, "npc") or s.npc or "this NPC", s.title or ("quest " .. s.q))
    if ns.UI then ns.UI.refresh() end
  end
end

ns.On("QUEST_ACCEPTED", function(q) A.notOffered[q] = nil end)

local function gossipOffered()
  local offered = {}
  for _, info in ipairs(try(C_GossipInfo.GetAvailableQuests) or {}) do offered[info.questID] = true end
  for _, info in ipairs(try(C_GossipInfo.GetActiveQuests) or {}) do offered[info.questID] = true end
  return offered
end

local function greetingOffered()
  local offered = {}
  for i = 1, (try(GetNumAvailableQuests) or 0) do
    local q = select(5, try(GetAvailableQuestInfo, i))
    if q then offered[q] = true end
  end
  for i = 1, (try(GetNumActiveQuests) or 0) do
    local q = try(GetActiveQuestID, i)
    if q then offered[q] = true end
  end
  return offered
end

local function onGreeting()
  for i = 1, (try(GetNumActiveQuests) or 0) do
    local _, isComplete = try(GetActiveTitle, i)
    local q = try(GetActiveQuestID, i)
    if isComplete and A.wanted(q, "turnin") and fresh(q) then try(SelectActiveQuest, i) return end
  end
  for i = 1, (try(GetNumAvailableQuests) or 0) do
    local q = select(5, try(GetAvailableQuestInfo, i))
    if A.wanted(q, "accept") and fresh(q) then try(SelectAvailableQuest, i) return end
  end
end

-- ------------------------------------------------------------- merchant

function A.sellGreys()
  if ns.db.sellGreys == false then return 0 end
  local numSlots, itemInfo, use = C.bagFn("GetContainerNumSlots"), C.bagFn("GetContainerItemInfo"), C.bagFn("UseContainerItem")
  local sold = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (try(numSlots, bag) or 0) do
      local info = try(itemInfo, bag, slot)
      if type(info) == "table" and info.quality == 0 and not info.hasNoValue and not info.isLocked then
        try(use, bag, slot)
        sold = sold + 1
      end
    end
  end
  return sold
end

-- ----------------------------------------------------------------- death

local function after(secs, fn)
  if C_Timer and C_Timer.After then C_Timer.After(secs, fn) else fn() end
end

ns.On("PLAYER_DEAD", function()
  if ns.db.autoRelease ~= true then return end
  after(1.5, function()
    if try(UnitIsDead, "player") and not try(UnitIsGhost, "player") then try(RepopMe) end
  end)
end)

ns.On("CORPSE_IN_RANGE", function()
  if ns.db.autoRelease ~= true then return end
  after(0.5, function() try(RetrieveCorpse) end)
end)

ns.On("QUEST_DETAIL", onDetail)
ns.On("QUEST_PROGRESS", onProgress)
ns.On("QUEST_COMPLETE", onComplete)
ns.On("GOSSIP_SHOW", function() A.checkOffered(gossipOffered()) end)   -- even with assist off
ns.On("QUEST_GREETING", function() A.checkOffered(greetingOffered()) end)
ns.On("GOSSIP_SHOW", onGossip)
ns.On("QUEST_GREETING", onGreeting)
ns.On("MERCHANT_SHOW", function() if mode() ~= "off" then A.sellGreys() end end)
