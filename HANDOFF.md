# HANDOFF: zugzugleveler (started 2026-10-17)

## Where things are

- Source: this repo.
- Deployed: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\ZugzugLeveler`
  is a **junction** to `ZugzugLeveler\` here. Client: Forever beta 1.60.1.70450
  (`.build.info`, product `wow_classic_beta`).
- Forever launches **2026-11-04**; the beta ends about 2026-10-22. At launch the
  live client gets its own folder. Find its name, then run
  `.\deploy.ps1 -Client <folder>`.

## Renamed to zugzugleveler (2026-10-18)

Folder `ZugzugLeveler`, TOC `ZugzugLeveler.toc`, saves `ZugzugLeveler.lua` with
`ZugzugLevelerDB` / `ZugzugLevelerCharDB`, slash `/zug` `/zugzug` (`/lev` and `/leveler` retired 2026-10-18), companion
`zugzugleveler-companion.exe`, `%LOCALAPPDATA%\zugzugleveler`, write header `X-Zugzug`. Old saves
(`SlopLeveler.lua`) are moved by the companion (migrate.go) only while the game is closed (a running
game rewrites the old file on exit); until then it reads them as they are. deploy.ps1 drops the old
`SlopLeveler` junction. The GitHub repo name (wow-leveler) is unchanged: renaming it is Michael's call.

## Beta / launch checklist (Forever launches 2026-11-04)

1. **Interface number.** If the live client's `GetBuildInfo()` 4th value is not 16001, change
   `## Interface:` in ZugzugLeveler.toc (keep 16001 too: `16001, 160xx`). Otherwise the game
   marks it "out of date" and does not load it.
2. **Client folder.** Find the live folder (`_forever_`?), then `.\deploy.ps1 -Client <folder>`.
   The companion and the installer find any `_*_` folder that holds the addon or a Wow*.exe.
3. **Data refresh.** RestedXP and AllTheThings update often:
   `python -I tools\rxp2route.py <RXPGuides> --race .. --class ..` (all 52 + the AoE route: see
   "Regenerating routes"), and `luajit tools\att2quests.lua <ATT>\db\Camelot\Categories <commit>`.
   Then both test suites, and compare the step counts.
4. **Release.** `.\tools\release.ps1` -> `dist\zugzugleveler-setup.exe` + the addon zip.
5. **In game, once:** full restart; the coach offers your route; `/zug why`; `/zug model`;
   `/zug sync`; `/zug live on` + `/zug live check` (does the chat log fill as you play?).
6. **Wowhead pictures stay off by default** (settings.go): ZAM's terms forbid non-browser
   downloads. Never switch the default on for others.

## Added 2026-10-18 (0.3.0-alpha)

- **Goal** (Route.goal/GOAL_SKIP, prefs.go): fastest leveling or completion; the page's Planner and
  the game (first-run question, `/zug goal`, options panel) both set it; the newer choice wins
  (Prefs.lua `at` vs ZugzugLevelerDB.goalAt). Route kinds left out work the same way
  (Prefs.lua skip vs ZugzugLevelerDB.skip/skipAt, Route.skips).
- **Pause** (Pause.lua): window button left of Sync, `/zug pause|resume`, key, options. While paused
  XP/hour, session, step times, splits, downtime, recorder crumbs, coach prompts and the optimizer
  stop; the arrow idles (Arrow.lua idlePose: drift + breathe + a sweep every 7 s); the step's map pin
  is cleared; a manual `/way` still works; the quest log is still followed. Per character, survives
  /reload. On resume the XP session and step clock move on by the paused online time.
- **Activity** (Coach.activity, Downtime afk): afk, vendor, talking, flying, hunting, fighting,
  travelling, paused, dead; saved in cdb.coach for the page and the peon.
- **The peon**. In game (Peon.lua): PlayerModel `SetCreature(10556)` (Lazy Peon; ATT quest 5441),
  `SetPortraitZoom(1)`, TalkingHeads atlases (Horde portrait frame, PortraitBg), talk animations 60/64/65
  and stand 0 (wowdev.wiki M2/AnimationList: the UI export does not define AnimationDataEnum). Falls
  back to media/icon.tga if no model loads in 3 s. Says coach heads-ups/questions, pause/resume,
  level-ups, turn-ins (one per 20 s), talent points; clicks: ready lines, then annoyed ones.
  On the page (web/peon.js): three.js 0.170.0 (vendored; npm sha512 + jsDelivr byte match checked),
  the Sketchfab model (web/peon/, textures shrunk), a WC3 portrait with jaw (Teeth_011 +x) moving as
  text types; only Stand1 and StandLumber are used because every other clip leaves the head-and-
  shoulders frame (checked by rendering all 16 clips). The page's AI helper (ask.go) answers through
  him. `node tools/peon-icon.mjs` re-renders peon/icon.png, peon/logo.png; media/icon.tga is
  icon.png at 64x64 (TOC IconTexture: Forever's AddonList.lua draws it at 20x20).
- **First run** (Coach.lua): questions queue (one popup at a time, the next on OnHide); first login:
  goal (4 s), route (5 s; Questing/AoE when "<route> AoE" exists), live updates (6 s); peon hello and
  closing line (Coach.onIdle).
- **Options panel** (Options.lua): sections (CreateSettingsListSectionHeaderInitializer, as Blizzard's
  AdvancedOptions.lua): How you play (goal, optimizer, assist, pause, hardcore, self-found), On screen,
  Help (coach, live, talents, party ...), What your route includes.
- **Errors** (Events.lua ns.noteError): last 20 in ZugzugLevelerDB.errors; `/zug errors` report (no
  character name); the page's Overview says when there are some.
- **Auction house** (Auction.lua): ReplicateItems scan from a click, read in slices; prices per
  realm-faction; /api/prices; Professions tab money card.
- **Quest text before pickup** (Export.lua E.questText at QUEST_DETAIL): ZugzugLevelerDB.questText,
  /api/questtext, under "Next stop".
- **Loot you saw** (Loot.lua): per creature, each corpse GUID once; GetLootSourceInfo when the client
  has it, else the dead target; /api/loot; the map's mob card shows your rates.
- **Party** (Party.lua): addon messages "ZUGZUG" to PARTY/RAID: route, step, level, paused, quest
  progress; rows in the window; names never saved.
- **Objective areas** (MapPath.lua): ATT `obj` coordinates of unfinished log quests as diamonds on
  the world map and dots on the minimap.
- **Talents** (Talents.lua, data/Talents.lua from tools/rxptalents.py): RestedXP classic talent
  guides (loaded on camelot by RXPGuides.toc); rank via C_SpecializationInfo.GetTalentInfo
  { specializationIndex, tier, column }.
- **Hardcore / self-found** (Engine.applies/modeOk): rxp2route now keeps RXP's #hardcore #softcore
  #ssf #ah steps marked (`mode`), shown by C_GameRules.IsHardcoreActive /
  C_PlayerInfo.IsSelfFoundActive or the options. Routes were regenerated (step counts up 0-32).
  Engine remembers the current step (cdb.stepKey) and finds it again when a route file changes.
  **Saves from before this have no key**: Michael's Undead Mage AoE place (step 315) is step 320 in
  the new file: `/zug step 320` once.
- **Data refresh** (tools/refresh.py, pins.json, routes.json): rebuilds all 53 routes, talents,
  Quests.lua and npcloot.json from the pinned commits; `--check` compares. Verified 2026-10-18: at the
  pins every file reproduces byte for byte (att2quests now sorts loot lists so it is repeatable).
- **Languages** (Live.lua chatStrings, chatlocale.go): the client's own GlobalStrings for the chat
  lines the page reads; a non-English client's lines become patterns (numbered %1$s handled).
  The addon's own text is still English.
- **Updates** (update.go): opt-in (Settings), GitHub releases/latest every 6 h; the Overview links a
  newer release. Releases need `zugzugleveler-setup.exe` attached.
- **Mac**: `tools\release.ps1` also builds `zugzugleveler-companion-mac-{arm64,amd64}`; default
  game folder /Applications/World of Warcraft. Installer and watcher stay Windows-only.

- **Page redesign** (web/app.js, style.css): 4 screens instead of 7 tabs. Character
  (characterTab: notices, left tabbedPanel Now/Notes, centre gearScreen with the compact
  sheet and the full name from snap.surname, right tabbedPanel Gear/Professions/Details),
  Map & Quests (worldTab: mapTab + questLog; clicking a quest calls mapShow -> rings from
  questPlaces), Plan & Runs (planTab: charAnalytics, runsTab, plannerTab), About (aboutTab:
  help, commands, privacy, credits; the footer is one line). Old hashes map via OLD_TABS.
  Display name **zugzug_leveler** (TOC Title, chat, options, page); internal names
  (ZugzugLeveler folder, saves, exe names, %LOCALAPPDATA%\zugzugleveler) unchanged.
  The in-game peon is **off by default** (`ns.db.peon == true`). The page peon breathes
  (slow loop: body lift + jaw ease) and talks with one smooth jaw cycle about twice a second.

- **The peon's voice and personality** (voice.go, web/peon.js, Peon.lua, data/Voice.lua,
  tools/peon_voice.py, web/peon/lines.json). The voice is **`peon`**: a friend of the
  project's impressions (Downloads\Peon Quotes.mp3, used with permission), 24 kHz mono 19.6 s,
  in Chatterbox-TTS-Server\reference_audio and \voices (its UI dropdown), blendable.
  `peondrac` (blendd: peon 70 + dracflow15 30) is Michael's own, local only: it is part
  Dracula Flow, someone else's voice, so it is not shipped. Neither is on the homelab yet
  (asleep): `stream\sync-voices.ps1 -Push` when it is awake.
  Personality: caveman efficiency (few words, no filler, facts exact). lines.json holds every
  fixed line; `tools\peon_voice.py --ship` (with Chatterbox's python_embedded) renders them and
  packs .ogg into web/peon/voice/peon/ (page, 25 lines) and ZugzugLeveler/media/voice/ (addon,
  18 lines) and writes data/Voice.lua. In game: PlaySoundFile(path, "Dialog"), a global in
  Ketho's Forever GlobalAPI list (not in Blizzard's docs): **confirm in game**. The page turns
  coach lines into peon speech (peonSpeak); ask.go's system prompt makes the helper model
  answer as the peon (max_tokens 300). New lines on the page: Settings, "Chatterbox for new
  lines". File name = sha1("<voice>\n<text>")[:20] in Go, Python and data/Voice.lua.

## Mists of Pandaria Classic (added 2026-10-18)

- **One TOC for both games**, as RXPGuides.toc does: `## Interface: 16001, 50504`, Forever-only files
  tagged `[AllowLoadGameType camelot]` (routes, talents, professions plan, danger, data/Quests.lua),
  `data/Quests_Mists.lua [AllowLoadGameType mists]`. Linked into `_classic_` (`.\deploy.ps1 -Client _classic_`).
- **Compat.lua** tries the C_QuestLog call, then 5.5.4's old globals (GetQuestLogTitle, IsQuestComplete,
  GetQuestsCompleted, GetQuestLogIndexByID, C_QuestLog.GetQuestInfo, GetQuestLogQuestText with
  SelectQuestLogEntry). Also C.tooltip (hidden GameTooltip when there is no C_TooltipInfo), and old
  GetInventorySlotInfo / GetItemStats / GetMerchantItemInfo / GetSkillLineInfo / GetTradeSkillInfo.
  Signatures read from Gethe/wow-ui-source branch `classic` (5.5.4.70449) and Ketho's classic GlobalAPI.
- **No guide on Mists**: the coach offers quest log mode; quest givers come from data/Quests_Mists.lua
  (QuestInfo.availableOn) because Mists has no C_QuestLine; QL.outlevelled drops grey ones by a rule
  of thumb (min level 10+ under you, or the zone's C_Map.GetMapLevels top 3+ under you).
- **Data**: `lua tools/att2quests.lua <ATT>/db/Mists/Categories <commit> ZugzugLeveler/data/Quests_Mists.lua -`
  (lua 5.4+: Mists' Zones.lua has more constants than luajit allows; Holidays.lua's handler fails and is
  skipped, named on stderr). 14,371 quests. Forever's data still builds byte-identical with luajit.
- **Transmog** (Export.lua appearance): C_Transmog.GetSlotVisualInfo + C_TransmogCollection.GetSourceInfo
  -> `slots[x].tmog = { id, name, src }` or `{ hidden = true }`; the page draws that look. **Confirm in
  game** that it reads away from the transmogrifier. Barber look works unchanged on Mists.
- **Tests**: `luajit test\harness.lua ZugzugLeveler - mists` (Mists-shaped API, Mists-only tests).
- **Companion game gate** (games.go, app.js gameGate): every client folder, named from .build.info;
  with two or more that have the addon the page asks "Which game?" first; Settings > Change game;
  `?game=_classic_` skips the question. /api/questdb follows the game; /api/prof and /api/danger
  are {} on later expansions. Wowhead (3D, icons, maps) is still Forever's data set: Mists items
  will be missing from the 3D character.
- Fixed on Forever too: `local a, b, c = X and C.try(...)` kept only the first result, so
  GetNextWaypoint's x, y were always nil in quest log mode.

## Mists: gear, talents, ratings, professions (added 2026-10-19)

Sources checked (licenses read from each project's own files, 2026-10-19): usable are
AllTheThings (MIT), wowsims/mop (MIT, asks for a visible link: About has it) and RestedXP
(CC BY-NC-SA). GPL (AtlasLoot MoP, SimulationCraft, every 5.4.8 emulator DB, Azeroth Pilot
Reloaded) and All Rights Reserved / unlicensed (Questie, QuestieDB, MoP profession guides,
HandyNotes, ReforgeLite, SpecBisTooltip, Pawn = CC BY-NC-ND) are ideas only. No open MoP 80-90
leveling route and no open node-spawn data exist.

- **Quest rewards**: att2quests.lua writes `rw` (a quest's i()/s() children) for both games;
  Mists data is `ns.QuestDBMists` (QuestInfo reads the one for the game). Export.lua
  E.lookupRewards asks the game for the rewards of `avail` + log quests (GetItemInfo /
  GET_ITEM_INFO_RECEIVED) and remembers equippable ones with real stats + required level;
  `availNames` saves their titles.
- **Page Gear tab on Mists** (games.go expansion -> gear.js setGame): weights from
  `data/mists/weights.json` (RestedXP MoP leveling 1-84 for 6 classes + wowsims level-90 EP for
  every spec; the active spec is found in either), items from `data/mists/items.json` (wowsims
  stats for ATT's reward items; the game's own items win), stat names unified (gear.js canon),
  no ranged slot (Cata/PaperDollFrame IsRangedSlotShown), armor specialization from 50, Monk and
  Death Knight, Wowhead links under /mop-classic/. Map: reward quests at their givers.
- **Talents** (Talents.lua on Mists, data/Talents_Mists.lua): wowsims' preset for the active spec;
  GetTalentTierInfo for picks (tiers 15-90, DK 56-90: Blizzard's CLASS_TALENT_LEVELS);
  GetGlyphSocketInfo for glyphs. `/zug talents`, `/zug talents list`, `/zug talents frost default`.
  Page: Details > Talents. These are level-90 raid builds, not PvP.
- **Ratings**: Export.lua E.ratings (GetCombatRating / Bonus with the client's CR_* globals, as
  PaperDollFrame does); page shows them and "1% costs" from `data/mists/ratings.json`
  (combatratings.txt, columns by CR id; level 90 = hit 340, crit 600, haste 425, mastery 600).
- **Professions**: Professions.lua saves every orange/yellow/green recipe with materials
  (`cdb.profRecipes`); the page ranks the cheapest skill-ups at AH prices. Loot.lua records
  gathering nodes (`db.nodes[map]`, from GameObject loot GUIDs). Farm.lua: `/zug farm <name>`,
  `farm list`, `farm off` (a looping route through your recorded nodes; keeps your place).
  Map & Quests has a "gathering" layer.
- **Data refresh**: `python -I tools/refresh.py --rxp .. --att .. --wowsims <wowsims/mop clone>`
  (pins.json has wowsims). RestedXP's MoP weights were read from RXP at 8a8dd1ce (not the
  routes' pin).
- **Confirm in game**: transmog reading at the transmogrifier (`/zug tmog`), GetTalentTierInfo
  picks, glyph spells, reward lookups filling `db.items`, node GUIDs (gather once, `/zug farm list`).

## Classic Era & Hardcore (added 2026-10-20)

Hardcore is a realm type inside the Classic Era client (`_classic_era_`, 1.15.9.70003,
product wow_classic_era), not a client of its own. Michael's Era characters are on Skull Rock.
Sources read for this, all at the commits in pins.json (`rxp_era`, `att_era`):
RXPGuides.toc / GuideList-classic.xml / GuideLoader.lua `applies` / RXPGuides.lua
`SeasonCheck` + `HardcoreCheck` + `GetSeason`, Gethe/wow-ui-source branch `classic_era`
(8165d4cd, 1.15.9.70003), ATT `db/Vanilla`.

- **Game identity** (Compat.lua `C.game()` = forever / era / mists): Forever by its own API,
  Era by `WOW_PROJECT_ID == WOW_PROJECT_CLASSIC` (Era's Blizzard_FrameXMLBase/Vanilla/Constants.lua:97).
  Every old "not Forever = Mists" gate now asks C.game(). `C.hardcoreRealm()` /
  `C.selfFound()` (C_GameRules.IsHardcoreActive, C_PlayerInfo.IsSelfFoundActive: both in
  Era's API docs). TOC: `## Interface: 16001, 50504, 11509`, Era files tagged
  `[AllowLoadGameType vanilla]` (RXP's tag for Era). **11509 is RXP's number and the
  version pattern, not read from the game: confirm with `/dump GetBuildInfo()`.**
- **Routes** (routes/era, 80 files, tools/routes.json `"game": "era"`): for all 40 Era
  race/class pairs, `RXP Survival <Race> <Class>` = RestedXP's **Survival Guide** (its
  hardcore guide, #hardcore on every guide; 1 to 21-23) and `RXP Era <Race> <Class>` = its
  speedrun guides (1 to 21-22). Free RXP Era guides stop there; their 23-60 guides are not in
  the repo. Route files carry `game = "era"` (Route.Skip's 3rd argument) and Survival ones
  `hardcore = true`. The coach offers Survival first on a Hardcore realm, speedrun first
  elsewhere, the other as the second button.
- **rxp2route.py `--game era [--group Survival]`**: guides from GuideList-classic.xml (SoD
  left out), zone coordinates via DB/classic/db.lua, `CLASSIC` as the game word, RXP's
  season rule (`#season` must list 0; `#som` hidden), `#hardcoreserver`/`#softcoreserver`
  kept as marks `hcs`/`scs` (Engine: the realm decides). Two converter fixes that Forever
  shares: the guide header now ends at the first `step` line even when that step is filtered
  out (step tags leaked into the header before), and `git_commit` follows a worktree's .git
  file. **Forever's 53 routes still reproduce byte for byte at their pin.**
- **Shared with Forever**, checked file against file: RestedXP's classic dangerous mobs = its
  Forever list (whitespace only), classic stat weights = Forever's, the talent guides are the
  classic ones on both. So data/Danger.lua, Talents.lua, Professions.lua load on Era too.
  New: data/Quests_Era.lua (`ns.QuestDBEra`, 3,930 quests, att2quests.lua on db/Vanilla).
- **Hardcore behaviour, as RXP does it**: following a hardcore route counts as hardcore
  (Engine.hardcore: override, else Hardcore realm, else route.hardcore) so its hardcore-only
  steps and Survival talent builds apply; the snapshot saves `char.game`, `char.hcRealm`,
  `char.hardcore`, and the page's Gear tab then starts on RestedXP's **Hardcore** weights.
  The addon never abandons quests (RXP hides its cleanup on Hardcore; we have none).
- **Script time on Hardcore**: RXPGuides.lua says 1.15.9 stops a Lua script at 200 ms on
  Hardcore realms. Not in Blizzard's source, so measured: on a Hardcore realm Events.lua
  times every event's handlers and notes any over 100 ms once in `/zug errors`
  ("slow: <event> took N ms"). File loads: each Era route file compiles in 3-6 ms
  (lua 5.5 here), 420 ms for all 133 route files across separate loads. **Confirm in game.**
- **Companion**: `gameKey()` (forever/era/mists) in games.go; `/api/state.game`; Era reads
  Quests_Era.lua and lists only Era routes; Wowhead links go to /classic. `go test` has
  TestEraGame.
- **API differences fixed** (every API the addon calls was audited against the classic_era
  source): `QUEST_ACCEPTED` is `(questIndex, questId)` on Era, so Events.lua hands every
  handler the questID (before this the recorder stamped log row numbers); `C.isComplete` falls
  back to GetQuestLogTitle's 6th value (no proven IsQuestComplete on Era); Talents.rank asks
  by talentIndex as Era's talent frame does when tier/column gives nothing; the auction window
  is `AuctionFrame` on Era; Flight.lua asks GetAllTaxiNodes for your continent (Era has no
  GetTaxiMapID: **unverified which map Era wants**).
- **Known gaps on Era** (quiet, no errors): the greeting window's auto accept / turn-in
  (no GetActiveQuestID, GetAvailableQuestInfo has no questID); minimap dots (no
  C_Minimap.GetViewRadius); the map pin (no user waypoints); item stats on the Gear tab (no
  GetItemStats); the peon's TalkingHead frame (falls back to the gold edge); Enchanting's Craft
  window is not read. `C_QuestLog.GetQuestsOnMap` exists but Era's map never shows quest
  markers, so quest log mode may place fewer quests: **confirm in game**.
- **Tests**: `luajit test\harness.lua ZugzugLeveler - era` (Era-shaped API on a Hardcore realm,
  28 checks; the QUEST_ACCEPTED and isComplete checks were seen to fail without their fixes).
  refresh.py now runs the mists and era modes too.
- **Deploy**: `.\deploy.ps1 -Client _classic_era_` (done 2026-10-20; the companion watcher was
  rebuilt with autostart.ps1 and lists Era as ready).
- **First in-game check on Era**: full restart; AddOns list shows zugzug_leveler without "out of
  date" (else fix 11509 from `/dump select(4, GetBuildInfo())`); a new character on Skull Rock is
  offered Survival first; accept the first quest (the step moves on); `/zug errors` after an hour
  of play for any "slow:" lines; open a flight master, then `/zug flight`.

## Verified / not verified

| what | status |
|---|---|
| every Blizzard API, event and template used exists in 1.60.1 (70450) | **verified** against Gethe/wow-ui-source branch `forever` (same build) |
| addon logic: everything in the TOC (engine, optimizer, quest log, flights, danger, options, professions, gear export, ...) | **verified**: `luajit test\harness.lua ZugzugLeveler` 201/201 **on pHub** (luajit installed via scoop 2026-10-17, hash checked twice) |
| gear export in game: tooltip lines (`C_TooltipInfo.GetHyperlink`), spec points, skills, quest rewards read before Assist accepts, merchant items | APIs **verified** in the 1.60.1 export; **confirm in game**: after a /reload the Gear tab shows your gear, and accepting a quest with reward choices fills "Quest rewards to pick" |
| `tools/routes.py` report and route output | **verified** against `test/fixtures/ZugzugLeveler.lua` (WoW SavedVariables format) |
| harness `arg[2]` SavedVariables dump -> `tools/routes.py` | **verified** on pHub |
| the addon loading in the real game client | **verified by Michael** 2026-10-17 on a beta character (Undead Mage): loads, follows the route, guides to the next quest pickup |
| RXP world-coordinate axis order (`wx`/`wy`) | checked against HereBeDragons' code and Deputy Willem's known spawn; **confirm in game** that the arrow points at him |
| auto accept under Forever's "secrets" | **verified by Michael** 2026-10-17: quest accepted on its own, step advanced, arrow moved to the next place |
| auto turn-in (CompleteQuest / GetQuestReward) | **confirm in game** at the first turn-in |
| optimizer auto mode, /swap, sub-objectives in game | Michael 2026-10-17: "looks like it runs great" (general report, not a per-feature check) |
| 0.3.0 addon logic (pause, peon, talents, party, loot, options, wizard, errors, play styles, rebase) | **verified** in the harness: 357/357 (2026-10-18) |
| companion (prices, questtext, loot, update, chat locale) | **verified**: `go test` + page probe |
| peon in game: SetCreature(10556) shows the Lazy Peon, talk animations 60/64/65 | **confirm in game**: no model -> the icon shows instead |
| TalkingHeads-Horde-PortraitFrame atlas | the kit name is in TalkingHeadUI.lua; the atlas itself **confirm in game** (falls back to Alliance, then a gold edge) |
| GetLootSourceInfo | **not in the UI export**; confirm in game (falls back to the dead target) |
| ReplicateItems index base, AuctionHouseFrame name | **confirm in game** (reads 0..n, skips empty) |
| party messages between two clients | **confirm in game** with a friend |
| hearth detection (spell 8690) | **unverified ID**; only affects the recorder's "hearth" event |
| the arrow (Arrow.lua) pointing the right way in game | math checked against Blizzard's SuperTrackedFrame + HereBeDragons; **confirm in game**: run toward it, it should stay green and point up |

## First in-game check (in order, stop at the first failure)

1. Restart WoW (a new addon needs a restart). Check the AddOns list for "zugzugleveler" without "out of date".
2. `/dump GetBuildInfo()`: the 4th value should be 16001.
3. The window appears top right. `/zug route list` shows the RXP routes for your faction.
4. `/zug route use RXP <Race> Warrior` on a fresh level 1 character. The arrow should point at the first quest giver.
5. Accept the quest. The step should advance, and with assist on the quest accepts itself.
6. `/zug rec start`, play 10 minutes, `/reload`, `/zug runs`. The run should still be there.
7. `python -I tools\routes.py "...\WTF\Account\<ACCT>\SavedVariables\ZugzugLeveler.lua" --run 1`

## Regenerating routes

```powershell
git clone --depth 1 https://github.com/RestedXP/RXPGuides <somewhere>
python -I tools\rxp2route.py <somewhere> --race Human --class Mage
```

The generated routes use Warrior. **Re-run with your real class** (trainer and
class-quest steps differ). `routes/rxp/routes.xml` regenerates itself. Routes
from the other faction are skipped at load (`faction` field).

The format rules came from reading RXPGuides' own source: `GuideLoader.lua`
(ParseGuide, parseLine, applies), `functions.lua` (goto/accept/turnin/complete/xp),
`RXPGuides.lua` (IsStepShown), `GuideWindow.lua` (#include),
`DB/forever/db.lua` (mapId). Forever gotos use `map/continent,y,x` WORLD coordinates.

## Rules for this project

- No Journey code, guide text or waypoints. Its license forbids it.
- No ghoul bot on Forever (Blizzard live realms). In-game helpers only.
- RXP-derived routes: CC BY-NC-SA, credit RestedXP, never sell. See `ZugzugLeveler/routes/rxp/LICENSE.md`.
- TomTom is not supported; I could not read its source to check its API. **Arrow.lua is the replacement**:
  a fixed on-screen arrow (Blizzard's `Navigation-Tracked-Arrow` atlas), yards + ETA, green ahead /
  red behind, `/way x y [text]`, `/way <uiMapID> x y`, `/way clear`, right-click drops a /way.
  Ideas not built yet: chain RXP's intermediate `,0` gotos as a path; a TomTom API shim
  (only if TomTom is installed, so its source can be read first).
- **Sub-objectives (travel / work mode):** for a "do" step, outside the area the arrow heads for
  the nearest point of it; inside (within 50 yd, or a path point's radius + 15) the window's main
  line becomes the live objective (`C_QuestLog.GetQuestObjectives`), with the full objective list,
  RXP's instruction text (`hint`), the mobs (`.mob`) and the NPC (`.target`). With an RXP `#loop`
  the arrow walks the hunting circuit (radius points only, as RXP's arrow does); without one it dims.
- **/swap** (Engine.swap): sets the current step aside, with the rest of that quest's steps;
  they return on PLAYER_LEVEL_UP, on accepting that quest, or `/swap back`. `/swap list`.
- **Buttons.lua**: two SecureActionButtonTemplate buttons, the step's quest item (RXP `.use`, only
  if in bags) and `/targetexact` the step's mobs/NPC. Bindings.xml puts both in Key Bindings >
  AddOns. Never touched in combat (queued to PLAYER_REGEN_ENABLED). Shift-drag to move.
- **Splits.lua**: played time per step vs best (`ZugzugLevelerDB.best[route].seg`); only steps that
  were on screen when finished are timed (no fake bests from fast-forwarding or /zug skip).
- **Downtime.lua**: combat / drink / move / flight / idle / dead per zone (session + recorded run,
  `run.time`); aura names guarded with `issecretvalue`; in the run report.
- **MapPath.lua**: world map data provider draws you -> next 12 steps (RXP's order) + the hunting
  loop; minimap dots (rotation-aware). `/zug map off`.
- **Optimizer.lua**: shortest order for the next <=10 steps from where you stand (TSP with
  precedence, Held-Karp, exact; checked against brute force). Window stops at level gates,
  hearth/flight, steps without a position, set-aside steps. Rules: same quest keeps route order;
  `need` quests first; trainers keep their order. Straight-line yards only (no pathing).
  **Default `auto`** (Michael, 2026-10-17: "swap the arrow to keep me on the optimal route"):
  re-solves from your position every 2 s and on each step change; switches when the new order
  is >= 40 yd and >= 8% shorter than the one being followed (no flip-flopping); never while you
  are in the area of the current "do" step. `suggest` = say it, `/zug optimize` applies;
  `clear` reverts and drops to suggest; `off`. Ties keep the route's order.
- **QuestLog.lua** (`/zug questlog`): a route built from the game itself: quests in the log
  (`C_QuestLog.GetQuestsOnMap` on your map and the maps above it, `GetNextWaypoint`) as do /
  turn-in steps, quest givers (`C_QuestLine.GetAvailableQuestLines`, not `isHidden`) as accept
  steps; rebuilt when the set changes; the optimizer orders the nearest 10. `/zug ql debug` shows
  how many quests got a position. **Unverified in game: whether Forever fills these in.**
- **Flight.lua**: known flight points learned at a flight master (`GetTaxiMapID` +
  `C_TaxiMap.GetAllTaxiNodes`, state 0/1 = known); run and flight speeds MEASURED (flight speed
  assumed 20 yd/s until your first flight); optimizer and arrow use walk-vs-fly. `/zug flight`.
- **Danger.lua** + `data/Danger.lua` (RestedXP dangerousMobs, CC BY-NC-SA, `tools/rxp_danger.py`):
  elites/rares/bosses and normal mobs not 2+ levels under you, within 70 yd of you (chat once,
  window row, red minimap dots) or 60 yd of the next stop. `/zug danger on|off`.
- **Options.lua**: Options > AddOns > zugzugleveler (Blizzard's vertical-layout settings, proxy
  settings over our db): 2 dropdowns + 10 toggles. `/zug options`.
- **Professions.lua** + `data/Professions.lua` (ProfessionLevelingGuide, MIT,
  `tools/plg_professions.lua`, run with luajit): step + materials vs bags, gathering zones per
  faction, train reminder + `/zug prof way`; in the profession window, the game's own orange /
  yellow recipes you can make now. Forever's new recipes are not in the 1-300 plan.
- **Companion page** (`companion/`, Go, single .exe, `http://127.0.0.1:7830`): reads the
  SavedVariables (`lua.go`, a values-only Lua reader), serves `/api/*` + an embedded page
  (`web/`: overview, runs, map, planner, professions; SVG charts per the dataviz skill, palette
  validated light+dark). Writes ONLY `routes/custom/Planner.lua`, generated as checked data
  (`plan.go`). Host/Origin guard plus a custom header on POST. `Export.lua` (new) records map
  bounds, a character snapshot and professions for it. Verified: `go test` (reader on the real
  repo files, planner round-trip, written file loads in luajit); every tab screenshot-checked in
  headless Chrome against harness data; API run against the real beta folder. Map conversion
  world->map uses HereBeDragons' axis order (map x = world y): **confirm in game** that recorded
  zone bounds put route dots where they belong.
- **Companion, 2026-10-17 additions** (all in existing files, so `/reload` is enough):
  - `Export.lua` also saves `cdb.gear` (equipped by slot name, equippable bag items, spec points
    per tree, skills, stats, gold), `cdb.questLog`, `cdb.turnedIn`, `cdb.money` (gold samples),
    and account-wide `db.items` / `db.quests` (reward choices, read on QUEST_DETAIL and
    QUEST_COMPLETE *before* Assist accepts: `ns.On(..., first)`) / `db.vendors` (MERCHANT_SHOW).
  - **3D character** (`web/model.js`, `wowhead.go`, 2026-10-18): Wowhead's ZamModelViewer with
    the "classicplus" data set, set up the way Wowhead's own Forever item pages do it (read off
    "View in 3D": type 2, models {type 16, id race*2-1+sex}, items [[slot, displayId]], hd false,
    env/dataEnv/gameDataEnv "classicplus"). wow.zamimg.com answers 403 to a foreign Origin or
    Referer, so the page only talks to the companion: `/wh/modelviewer/...` fetches each file
    once into `%LOCALAPPDATA%\zugzugleveler\wowhead\` (never the repo), `/api/looks?ids=` reads
    displayId + inventorySlot from `www.wowhead.com/forever/item=<id>&xml` (also cached).
    The viewer script is pinned to `deployment/viewer/35ee72d` with `viewer/viewer.min.js` as
    fallback: if Wowhead redeploys, read the new hash off a Forever item page's network log.
    jQuery 3.7.1 is vendored (`web/vendor/`, SHA-256 matched across code.jquery.com, cdnjs and
    jsdelivr). The addon saves `char.raceID` and `char.sex`; face/hair/skin are not readable by
    addons, so the page has pickers (localStorage `look:<char>`). Wands are not drawn (the game
    does not show them). The stage is black: glow effects carry a black square.
  - **Sheet, icons, tooltips, map art** (2026-10-18): `G.sheet` lays the slots around the
    model (the stick figure is gone). `web/items.js`: icons from `images/wow/icons/<size>/`
    (name from the item XML's `<icon>`, `Look.V` = 2), empty slots `inventoryslot_*` (back uses
    chest, as the game does), one page-wide tooltip for any `[data-item]`, drawn from
    `item.tt` = the whole game tooltip with colours (Export.lua `E.tipFull`, from
    TooltipDataHandler's `lineData.leftColor/rightColor`), else rebuilt from saved fields.
    Map: `/api/mapart?name=` matches the addon's map name against `web/data/zones.json`
    (Wowhead Forever zone list, read in a browser: plain fetches of wowhead.com pages get 403)
    and returns the first id with `images/wow/classicplus/maps/enus/original/<id>.jpg`;
    the image is the in-game map frame, so map x/y draw straight on it (checked: the
    Sepulcher). Display font AnglicanText via `/localfont/` from `%LOCALAPPDATA%\zugzugleveler\fonts\`
    (fonts.go); its license forbids publishing, so never commit it.
  - **Gear tab** (`web/gear.js`): best in slot per
    class / level / spec from the items the game has shown you (no public item DB has Forever's
    stats: Forever reworked items under their Classic IDs), quest reward picks, stat weights.
    Weights: RestedXP `DB/forever/StatWeights.lua` (CC BY-NC-SA) -> `web/data/weights.json` via
    `python -I tools/rxp_weights.py <RXPGuides>`; scored the way RXP's ItemUpgrades.lua does
    (tooltip spell damage per school, weapon DPS + speed). Who wears what: RXP's CLASS_MAP.
    A quest's reward choices count once (`assignBest`); a worn ring stays in its own slot.
  - **Quests tab**: the log with objective progress, route turn-in step, the reward to pick, and
    the quests the route skips. **Runs**: compare two runs (`multiLine`). **Map**: gear upgrade
    layer (merchant spots, quest turn-ins). **Overview**: gold per hour, gold chart, gear notes.
  - `go test` also runs `gear_test.mjs` in node (scoring against the real weights file).
  - `autostart.ps1`: builds `zugzugleveler-watch.exe` and puts `-watch` in Startup; it opens the page
    when `WowB.exe` (or whichever `Wow*.exe` the client folder has) starts. Addons cannot launch
    programs, so this is the "launch with the game".
- **Need a full game restart** whenever a new file is added to the TOC (or Bindings.xml); /reload
  is enough for edits.
- Michael plays an **Undead Mage**: `RXP Undead Mage` (questing) and `RXP Undead Mage AoE`
  (`--path "1-6 Tirisfal Glades;6-12 Tirisfal Glades;12-14 Silverpine Forest;12-17 The Barrens AoE"`, ends at 21:
  RXP's 21-30 AoE guide is not in their repo). Silverpine must stay in: RXP's Barrens AoE guide starts by
  turning in Crossroads Conscription, which its Silverpine guide picks up on the way (fixed 2026-10-18; the old
  path skipped it and sent you from Silverpine to Durotar). When a route file's step count changes
  (cdb.routeSteps), Engine.lua resets sticky/stats/deferred/plan to "everything before your place is done".
- Missing quests: a do/turn-in step whose quest is not in the log, and whose accept step the route already
  passed, is set aside as `deferred[i] = "missing"` with a chat line saying why (E.missing). Level-ups leave
  those alone; accepting the quest brings them back. The optimizer skips them too. Follow-up accepts: rxp2route
  writes `after = {q...}` on an accept listed after turn-ins in the same RXP step (RXP gets prerequisites from
  Questie's DB, which we can't use); the engine passes it when every one of those quests is gone.
- **Quest data from AllTheThings** (MIT, github.com/ATTWoWAddon/AllTheThings, its built Forever DB
  `db/Camelot/Categories`): `luajit tools/att2quests.lua <Categories dir> <commit>` writes
  `data/Quests.lua` (4,191 quests: sourceQuests, sqreq, altQuests, breadcrumb, lvl, faction r 1/2,
  races, classes, givers, coords, objective areas) with ATT's MIT notice. Field meanings were read from
  ATT's src/Classes/Quests.lua and src/Modules/Filter.lua. `QuestInfo.lua` (ns.QInfo) answers "can
  this character take q, and why not"; the engine sets aside accept steps it cannot take ("level"
  ones come back on level-up, prerequisite ones when the prerequisite is turned in), the optimizer
  orders by prerequisites, the coach says why. Done quests come from one
  `C_QuestLog.GetAllCompletedQuestIDs` per pass. **Questie has NO license** (and neither does
  QuestieDB): read for ideas only, never copy. Its Forever data is converted Era data; ATT's has the
  new zones. Tests run with an empty QuestDB (real IDs collide with test IDs), `REAL_QUESTDB` for facts.
- **Every race and class has a route** (52 + Undead Mage AoE; Skyborne: Warrior, Hunter, Rogue,
  Shaman, Mage, Druid, the classes its RXP guide has steps for; confirm in game). Each route file
  starts with `if ns.Route.Skip(race, CLASS) then return end`, so only yours is built (unknown at
  load -> all). New characters without a route are offered theirs (Coach.routeFor).
- **Fresher data** (Live.lua, companion chatlog.go): the Sync button / `/zug sync` / a key reloads
  the UI to save now; `/zug live on` turns on the game's chat log (asked once) and the companion
  follows `Logs\WoWChatLog.txt` for quest/XP/level/loot lines (GlobalStrings enUS from Ketho's
  BlizzardInterfaceResources forever branch) -> the Overview's "Since the last save". NOT verified in
  game: whether the client writes the log as you play or in bursts (`/zug live check` + the page
  measure it).
- **Snapshot guard** (Export.lua): a closing game reports XP 0/0, no gear, no professions; the
  snapshot is skipped then, and an all-empty gear scan never replaces a real one (a real save got
  wiped this way 2026-10-18).
- **Backups** (backup.go): every save change is copied to `%LOCALAPPDATA%\zugzugleveler\backups\`
  (30 per file, page open or not); a save that drops under a fifth of its size gets a Restore
  banner (game must be closed). Why: Questie's docs/saved-variables-investigation.md saw Forever
  lose SavedVariables on a cold start (build 69913).
- **Phone mode** (lan.go): off by default; the page's "On your phone" switches it on, listens on
  this PC's private IPv4 too, pairs a phone by QR (vendored qrcode-generator 1.4.4, MIT, SHA-256
  matched on jsdelivr/unpkg/cdnjs), cookie after; phones are read-only. Not tried on a real phone.
- **Installer** (install.go, bundle.go): `tools\release.ps1` -> `dist\zugzugleveler-setup.exe` (addon
  packed in) + the addon zip. Finds WoW via the Uninstall registry (reg.exe), copies the addon into
  each client, the companion to `%LOCALAPPDATA%\zugzugleveler\bin`, HKCU Run key with `-watch`.
  Refuses to write through a junction (tested with mklink /J). `-uninstall` keeps saves. Unsigned:
  SmartScreen warns.
- **Ask** (ask.go): optional, a local model (Ollama, found on this PC's addresses; here it listens
  on the tailnet IP) answers from the character's facts. Tested once with qwen2.5vl:7b (8.6 s,
  half right). Config `%LOCALAPPDATA%\zugzugleveler\config.json`.
- **Quest text**: the addon saves each log quest's own words (GetQuestLogQuestText); Wowhead's
  nether tooltips are the fallback.
- **Wowhead terms** (ZAM EULA, corp.fanbyte.com/legal/terms, read 2026-10-18): personal,
  non-commercial; no downloading "using any engine, software, tool... other than... web
  browsers"; no framing "any individual element" without written consent. The companion's
  models/icons/maps/item looks/quest tips all come that way: fine to try at home, **not shippable
  without ZAM's written consent** (Michael's call).
- **Fonts**: AnglicanText (local only, may not be published) then UnifrakturMaguntia (SIL OFL 1.1,
  unmodified TTF from google/fonts, shipped in web/fonts).
- **Route options** (Route.CATEGORIES / Route.category / Route.leftOut, prefs.go): the Planner tab's
  "What your route includes" writes routes/custom/Prefs.lua (`ns.RoutePrefs.skip`), E.applies passes
  those kinds (cooking, first aid, gathering/crafting trainers, weapon skills, buying food, class /
  pet trainers, optional quests). Words come from RXP's own step text; quests are never skipped this
  way. The page reads the same table from Route.lua.
- **Mob loot** (Danger.lua `learn`, `/api/npcs`, att2quests.lua -> companion/web/data/npcloot.json):
  the addon learns a danger mob's NPC id when you target/mouse over it; ATT's items list their
  droppers (crs), turned round = loot per NPC (690 creatures; ATT records special drops, no rates,
  few Forever world bosses). Clicking a danger pin on the Map shows it, with a Wowhead link for rates.
  wago.tools' Forever Creature table has only ~100 rows (names come from the server), so names
  cannot be mapped to ids offline.
- **ROADMAP.md**: what is missing for other players, and the Wowhead decision.
- **Coach.lua** (2026-10-18; a NEW file, so the game needs a full restart, not /reload): `/zug why`
  explains the step (what, who, the RestedXP guide it is in via the route's `sections`, why another
  zone, level pace, log quests the route skips); a chat heads-up once per zone change; yes/no
  StaticPopups (OnAccept/OnCancel, checked in Blizzard_StaticPopup) when stuck 12 min at a step,
  4 min in a zone the route has nothing in (-> quest log mode), or back in the parked guide's zone.
  Never in combat; each question snoozes 15 min. `E.park()` / `E.resume()` keep your place when
  you go to quest log mode (`/zug route resume`). `cdb.coach` = {state, why, at} for the page's
  "Why this step". `/zug coach off` silences it; `/zug why debug` is the old engine dump.
  rxp2route writes `sections = {{from, name}}` per route (all 12 routes regenerated, counts unchanged).
- Hearth / fly steps are done once you are on the map of the next positioned step. Steps before a done hearth /
  flight, on a map you are not on, are "left behind": `deferred[i] = "left"`, one chat line naming them. Level-ups
  keep them aside; `/swap back` (or accepting the quest) brings them back and `cdb.kept[i]` stops a re-set-aside.
- Classic Era & Hardcore: built 2026-10-20, see "Classic Era & Hardcore" above.
