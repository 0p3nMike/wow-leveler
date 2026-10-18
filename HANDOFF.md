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
`ZugzugLevelerDB` / `ZugzugLevelerCharDB`, slash `/lev` `/leveler` `/zug` `/zugzug`, companion
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
5. **In game, once:** full restart; the coach offers your route; `/lev why`; `/lev model`;
   `/lev sync`; `/lev live on` + `/lev live check` (does the chat log fill as you play?).
6. **Wowhead pictures stay off by default** (settings.go): ZAM's terms forbid non-browser
   downloads. Never switch the default on for others.

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
| hearth detection (spell 8690) | **unverified ID**; only affects the recorder's "hearth" event |
| the arrow (Arrow.lua) pointing the right way in game | math checked against Blizzard's SuperTrackedFrame + HereBeDragons; **confirm in game**: run toward it, it should stay green and point up |

## First in-game check (in order, stop at the first failure)

1. Restart WoW (a new addon needs a restart). Check the AddOns list for "zugzugleveler" without "out of date".
2. `/dump GetBuildInfo()`: the 4th value should be 16001.
3. The window appears top right. `/lev route list` shows the RXP routes for your faction.
4. `/lev route use RXP <Race> Warrior` on a fresh level 1 character. The arrow should point at the first quest giver.
5. Accept the quest. The step should advance, and with assist on the quest accepts itself.
6. `/lev rec start`, play 10 minutes, `/reload`, `/lev runs`. The run should still be there.
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
  were on screen when finished are timed (no fake bests from fast-forwarding or /lev skip).
- **Downtime.lua**: combat / drink / move / flight / idle / dead per zone (session + recorded run,
  `run.time`); aura names guarded with `issecretvalue`; in the run report.
- **MapPath.lua**: world map data provider draws you -> next 12 steps (RXP's order) + the hunting
  loop; minimap dots (rotation-aware). `/lev map off`.
- **Optimizer.lua**: shortest order for the next <=10 steps from where you stand (TSP with
  precedence, Held-Karp, exact; checked against brute force). Window stops at level gates,
  hearth/flight, steps without a position, set-aside steps. Rules: same quest keeps route order;
  `need` quests first; trainers keep their order. Straight-line yards only (no pathing).
  **Default `auto`** (Michael, 2026-10-17: "swap the arrow to keep me on the optimal route"):
  re-solves from your position every 2 s and on each step change; switches when the new order
  is >= 40 yd and >= 8% shorter than the one being followed (no flip-flopping); never while you
  are in the area of the current "do" step. `suggest` = say it, `/lev optimize` applies;
  `clear` reverts and drops to suggest; `off`. Ties keep the route's order.
- **QuestLog.lua** (`/lev questlog`): a route built from the game itself: quests in the log
  (`C_QuestLog.GetQuestsOnMap` on your map and the maps above it, `GetNextWaypoint`) as do /
  turn-in steps, quest givers (`C_QuestLine.GetAvailableQuestLines`, not `isHidden`) as accept
  steps; rebuilt when the set changes; the optimizer orders the nearest 10. `/lev ql debug` shows
  how many quests got a position. **Unverified in game: whether Forever fills these in.**
- **Flight.lua**: known flight points learned at a flight master (`GetTaxiMapID` +
  `C_TaxiMap.GetAllTaxiNodes`, state 0/1 = known); run and flight speeds MEASURED (flight speed
  assumed 20 yd/s until your first flight); optimizer and arrow use walk-vs-fly. `/lev flight`.
- **Danger.lua** + `data/Danger.lua` (RestedXP dangerousMobs, CC BY-NC-SA, `tools/rxp_danger.py`):
  elites/rares/bosses and normal mobs not 2+ levels under you, within 70 yd of you (chat once,
  window row, red minimap dots) or 60 yd of the next stop. `/lev danger on|off`.
- **Options.lua**: Options > AddOns > zugzugleveler (Blizzard's vertical-layout settings, proxy
  settings over our db): 2 dropdowns + 10 toggles. `/lev options`.
- **Professions.lua** + `data/Professions.lua` (ProfessionLevelingGuide, MIT,
  `tools/plg_professions.lua`, run with luajit): step + materials vs bags, gathering zones per
  faction, train reminder + `/lev prof way`; in the profession window, the game's own orange /
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
- **Fresher data** (Live.lua, companion chatlog.go): the Sync button / `/lev sync` / a key reloads
  the UI to save now; `/lev live on` turns on the game's chat log (asked once) and the companion
  follows `Logs\WoWChatLog.txt` for quest/XP/level/loot lines (GlobalStrings enUS from Ketho's
  BlizzardInterfaceResources forever branch) -> the Overview's "Since the last save". NOT verified in
  game: whether the client writes the log as you play or in bursts (`/lev live check` + the page
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
- **Coach.lua** (2026-10-18; a NEW file, so the game needs a full restart, not /reload): `/lev why`
  explains the step (what, who, the RestedXP guide it is in via the route's `sections`, why another
  zone, level pace, log quests the route skips); a chat heads-up once per zone change; yes/no
  StaticPopups (OnAccept/OnCancel, checked in Blizzard_StaticPopup) when stuck 12 min at a step,
  4 min in a zone the route has nothing in (-> quest log mode), or back in the parked guide's zone.
  Never in combat; each question snoozes 15 min. `E.park()` / `E.resume()` keep your place when
  you go to quest log mode (`/lev route resume`). `cdb.coach` = {state, why, at} for the page's
  "Why this step". `/lev coach off` silences it; `/lev why debug` is the old engine dump.
  rxp2route writes `sections = {{from, name}}` per route (all 12 routes regenerated, counts unchanged).
- Hearth / fly steps are done once you are on the map of the next positioned step. Steps before a done hearth /
  flight, on a map you are not on, are "left behind": `deferred[i] = "left"`, one chat line naming them. Level-ups
  keep them aside; `/swap back` (or accepting the quest) brings them back and `cdb.kept[i]` stops a re-set-aside.
- Classic Era: not built. Add `ZugzugLeveler_Vanilla.toc` (Interface 11509) plus a compat pass when wanted.
