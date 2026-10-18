# HANDOFF: sl0p.leveler (started 2026-10-17)

## Where things are

- Source: this repo.
- Deployed: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\SlopLeveler`
  is a **junction** to `SlopLeveler\` here. Client: Forever beta 1.60.1.70450
  (`.build.info`, product `wow_classic_beta`).
- Forever launches **2026-11-04**; the beta ends about 2026-10-22. At launch the
  live client gets its own folder. Find its name, then run
  `.\deploy.ps1 -Client <folder>`.

## Verified / not verified

| what | status |
|---|---|
| every Blizzard API, event and template used exists in 1.60.1 (70450) | **verified** against Gethe/wow-ui-source branch `forever` (same build) |
| addon logic: everything in the TOC (engine, optimizer, quest log, flights, danger, options, professions, gear export, ...) | **verified**: `luajit test\harness.lua SlopLeveler` 201/201 **on pHub** (luajit installed via scoop 2026-10-17, hash checked twice) |
| gear export in game: tooltip lines (`C_TooltipInfo.GetHyperlink`), spec points, skills, quest rewards read before Assist accepts, merchant items | APIs **verified** in the 1.60.1 export; **confirm in game**: after a /reload the Gear tab shows your gear, and accepting a quest with reward choices fills "Quest rewards to pick" |
| `tools/routes.py` report and route output | **verified** against `test/fixtures/SlopLeveler.lua` (WoW SavedVariables format) |
| harness `arg[2]` SavedVariables dump -> `tools/routes.py` | **verified** on pHub |
| the addon loading in the real game client | **verified by Michael** 2026-10-17 on a beta character (Undead Mage): loads, follows the route, guides to the next quest pickup |
| RXP world-coordinate axis order (`wx`/`wy`) | checked against HereBeDragons' code and Deputy Willem's known spawn; **confirm in game** that the arrow points at him |
| auto accept under Forever's "secrets" | **verified by Michael** 2026-10-17: quest accepted on its own, step advanced, arrow moved to the next place |
| auto turn-in (CompleteQuest / GetQuestReward) | **confirm in game** at the first turn-in |
| optimizer auto mode, /swap, sub-objectives in game | Michael 2026-10-17: "looks like it runs great" (general report, not a per-feature check) |
| hearth detection (spell 8690) | **unverified ID**; only affects the recorder's "hearth" event |
| the arrow (Arrow.lua) pointing the right way in game | math checked against Blizzard's SuperTrackedFrame + HereBeDragons; **confirm in game**: run toward it, it should stay green and point up |

## First in-game check (in order, stop at the first failure)

1. Restart WoW (a new addon needs a restart). Check the AddOns list for "sl0p.leveler" without "out of date".
2. `/dump GetBuildInfo()`: the 4th value should be 16001.
3. The window appears top right. `/lev route list` shows the RXP routes for your faction.
4. `/lev route use RXP <Race> Warrior` on a fresh level 1 character. The arrow should point at the first quest giver.
5. Accept the quest. The step should advance, and with assist on the quest accepts itself.
6. `/lev rec start`, play 10 minutes, `/reload`, `/lev runs`. The run should still be there.
7. `python -I tools\routes.py "...\WTF\Account\<ACCT>\SavedVariables\SlopLeveler.lua" --run 1`

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
- RXP-derived routes: CC BY-NC-SA, credit RestedXP, never sell. See `SlopLeveler/routes/rxp/LICENSE.md`.
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
- **Splits.lua**: played time per step vs best (`SlopLevelerDB.best[route].seg`); only steps that
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
- **Options.lua**: Options > AddOns > sl0p.leveler (Blizzard's vertical-layout settings, proxy
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
  - **Gear tab** (`web/gear.js`): a drawn survey plate of the character (Wowhead's 3D model
    viewer is not offered for embedding and refuses other origins: 403), best in slot per
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
  - `autostart.ps1`: builds `sl0pleveler-watch.exe` and puts `-watch` in Startup; it opens the page
    when `WowB.exe` (or whichever `Wow*.exe` the client folder has) starts. Addons cannot launch
    programs, so this is the "launch with the game".
- **Need a full game restart** whenever a new file is added to the TOC (or Bindings.xml); /reload
  is enough for edits.
- Michael plays an **Undead Mage**: `RXP Undead Mage` (questing) and `RXP Undead Mage AoE`
  (`--path "1-6 Tirisfal Glades;6-12 Tirisfal Glades;12-17 The Barrens AoE"`, ends at 21:
  RXP's 21-30 AoE guide is not in their repo).
- Classic Era: not built. Add `SlopLeveler_Vanilla.toc` (Interface 11509) plus a compat pass when wanted.
