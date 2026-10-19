-- Peon.lua -- the helper, in game: a talking peon beside the step window, the
-- way Warcraft III's unit portrait talks to you (and WoW's own talking heads).
--
-- Built from what Blizzard's TalkingHeadUI uses in the 1.60.1 export
-- (Blizzard_FrameXML/TalkingHeadUI.xml/.lua): a PlayerModel inside the
-- "TalkingHeads-*" portrait atlases. The model is the Lazy Peon, creature 10556
-- (AllTheThings: quest 5441's objective), set with SetCreature
-- (FrameAPICharacterModelBase), close up with SetPortraitZoom. He talks with
-- animation 60 (EmoteTalk), shouts with 64 (EmoteTalkExclamation), asks with 65
-- (EmoteTalkQuestion) and rests on 0 (Stand): the numbers are wowdev.wiki's
-- M2/AnimationList (the UI export only names the type, AnimationDataEnum).
-- A creature the client has not cached may draw nothing: then the portrait
-- shows the addon's icon (media/icon.tga, the same peon) instead.
--
-- He says what the coach says (heads-ups, its questions), "Break" on a pause,
-- "Work complete" on a turn-in, a level-up; and, clicked, the Warcraft III
-- peon's lines, until you click him too often. Off by default: /zug peon on.
--
-- His voice: the lines in data/Voice.lua (generated from the companion's
-- peon/lines.json by tools/peon_voice.py --ship; impressions by a friend of the
-- project) are .ogg files in media/voice/, played with PlaySoundFile on the
-- Dialog channel (a global in Ketho's BlizzardInterfaceResources list for this
-- client; Blizzard's own docs only cover C_Sound.PlaySound: confirm in game).
-- A line with words that change ("Level 17") shows those words and plays the
-- fixed line it matches ("Zug zug! Level up!"). He speaks in caveman
-- efficiency: few words, the facts exact.

local _, ns = ...
local C = ns.C

local P = {}
ns.Peon = P

local CREATURE = 10556 -- Lazy Peon
local ANIM = { talk = 60, yell = 64, ask = 65, stand = 0 }
local ICON = "Interface\\AddOns\\ZugzugLeveler\\media\\icon"
local VOICE = "Interface\\AddOns\\ZugzugLeveler\\media\\voice\\"
local L = ns.PeonLines or { ready = { "Zug zug." }, annoyed = { "Me not that kind of orc!" }, easter = {}, game = {} }
P.READY, P.ANNOYED, P.EASTER, P.LINES = L.ready, L.annoyed, L.easter or {}, L.game
local playing -- the sound handle of the line he is saying

local f, model, icon, bubble, text
local talkUntil, hideAt = 0, 0
local pokes, lastPoke = 0, 0

local function on() return ns.db.peon == true end -- off unless the player turns him on

local function atlas(tex, names)
  for _, n in ipairs(names) do
    if C_Texture and C.try(C_Texture.GetAtlasInfo, n) then tex:SetAtlas(n); return true end
  end
  return false
end

local function build()
  local win = _G.ZugzugLevelerFrame
  f = CreateFrame("Button", "ZugzugLevelerPeon", UIParent, "BackdropTemplate")
  f:SetSize(84, 84)
  if win then f:SetPoint("TOPRIGHT", win, "TOPLEFT", -6, 0) else f:SetPoint("CENTER") end
  f:SetFrameStrata("MEDIUM")

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 6, -6)
  bg:SetPoint("BOTTOMRIGHT", -6, 6)
  if not atlas(bg, { "TalkingHeads-PortraitBg" }) then
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.05, 0.12, 0.35, 1)
  end

  model = CreateFrame("PlayerModel", "ZugzugLevelerPeonModel", f)
  model:SetPoint("TOPLEFT", 6, -6)
  model:SetPoint("BOTTOMRIGHT", -6, 6)
  C.try(model.SetCreature, model, CREATURE)
  C.try(model.SetPortraitZoom, model, 1)
  model:SetScript("OnModelLoaded", function(self) C.try(self.SetPortraitZoom, self, 1); P.idle() end)

  icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 8, -8)
  icon:SetPoint("BOTTOMRIGHT", -8, 8)
  icon:SetTexture(ICON)
  icon:Hide()

  local border = f:CreateTexture(nil, "OVERLAY")
  border:SetAllPoints()
  if not atlas(border, { "TalkingHeads-Horde-PortraitFrame", "TalkingHeads-Alliance-PortraitFrame" }) and f.SetBackdrop then
    -- no portrait atlas in this client: a plain gold edge
    f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    f:SetBackdropBorderColor(0.85, 0.69, 0.29, 1)
  end

  -- what he says: a panel to the left of the portrait
  bubble = CreateFrame("Frame", "ZugzugLevelerPeonSays", f, "BackdropTemplate")
  bubble:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, -4)
  bubble:SetWidth(220)
  if bubble.SetBackdrop then
    bubble:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    bubble:SetBackdropColor(0.07, 0.06, 0.04, 0.92)
    bubble:SetBackdropBorderColor(0.85, 0.69, 0.29, 0.9)
  end
  local name = bubble:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  name:SetPoint("TOPLEFT", 8, -6)
  name:SetText("Peon")
  text = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
  text:SetWidth(204)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(true)
  bubble:Hide()

  f:RegisterForClicks("LeftButtonUp")
  f:SetScript("OnClick", function() P.poke() end)
  f:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText("Peon")
      GameTooltip:AddLine("Your helper. He says what the coach says. /zug peon off hides him.", 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  local acc = 0
  f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.25 then return end
    acc = 0
    local now = C.now()
    if talkUntil > 0 and now >= talkUntil then talkUntil = 0; P.idle() end
    if hideAt > 0 and now >= hideAt then hideAt = 0; bubble:Hide() end
  end)

  -- no model after a few seconds (the creature is not in this client's cache): the icon
  if C_Timer and C_Timer.After then
    C_Timer.After(3, function()
      local id = C.try(model.GetModelFileID, model)
      if not id or id == 0 then model:Hide(); icon:Show() end
    end)
  end
  P.show()
end

function P.idle()
  if model then C.try(model.SetAnimation, model, ANIM.stand) end
end

-- his voice for a fixed line (data/Voice.lua); nothing for any other words
function P.voice(line)
  local file = ns.PeonVoice and line and ns.PeonVoice[line]
  if not (file and PlaySoundFile) or ns.db.peonVoice == false then return false end
  if playing and StopSound then C.try(StopSound, playing) end
  local ok, handle = C.try(PlaySoundFile, VOICE .. file .. ".ogg", "Dialog")
  playing = ok and handle or nil
  return ok and true or false
end

-- say(text[, kind[, line]]): kind "yell" or "ask" picks the animation; line is
-- the fixed line he says aloud when text has words of its own (default: text)
function P.say(msg, kind, line)
  if not (f and on() and msg and msg ~= "") then return end
  P.voice(line or msg)
  text:SetText(msg)
  bubble:SetHeight(math.max(text:GetStringHeight() or 14, 14) + 30)
  bubble:Show()
  local secs = math.min(math.max(#msg * 0.06, 2.5), 8)
  C.try(model.SetAnimation, model, ANIM[kind or "talk"] or ANIM.talk)
  talkUntil = C.now() + secs
  hideAt = C.now() + secs + 5
  P.last = msg
end

-- clicked: a ready line, then, clicked too often, the annoyed ones, and past
-- those an easter egg (never the same one twice running)
local lastEgg = 0
function P.poke()
  local now = C.now()
  pokes = (now - lastPoke < 2.5) and pokes + 1 or 1
  lastPoke = now
  if pokes >= 4 + #P.ANNOYED and #P.EASTER > 0 then
    local k = math.random(#P.EASTER)
    if #P.EASTER > 1 and k == lastEgg then k = k % #P.EASTER + 1 end
    lastEgg = k
    P.say(P.EASTER[k], "yell")
  elseif pokes >= 4 then
    P.say(P.ANNOYED[math.min(pokes - 3, #P.ANNOYED)], "yell")
  else
    P.say(P.READY[math.random(#P.READY)])
  end
end

-- shown with the step window, when he is on
function P.show()
  if not f then return end
  local win = _G.ZugzugLevelerFrame
  f:SetShown(on() and (not win or win:IsShown()))
end

function P.toggle(v)
  ns.db.peon = v
  P.show()
end

ns.On("SL_READY", function() build() end)
ns.On("SL_PAUSE", function(paused)
  if paused then P.say(P.LINES.pause or "Break. Me wait.") else P.say(P.LINES.resume or "Back to work!", "yell") end
end)
ns.On("PLAYER_LEVEL_UP", function(level)
  P.say(("Zug zug! Level %s!"):format(tostring(level or "")), "yell", P.LINES.levelup)
end)
local lastDone = -100
ns.On("QUEST_TURNED_IN", function()
  if C.now() - lastDone > 20 then lastDone = C.now(); P.say(P.LINES.turnin or "Work complete.") end
end)
