# zugzug_leveler

A leveling addon for **World of Warcraft: Forever** (client 1.60.1, interface 16001),
**Classic Era and its Hardcore realms** (1.15.9: RestedXP's Survival Guide and speedrun
routes for every race and class, levels 1 to about 22) and **Mists of Pandaria Classic**
(quest log mode).

It shows you where to go next and finds the shortest order to do your quests in,
from where you are standing. It also tracks how fast you are leveling and where
your time goes.

> Not affiliated with Blizzard Entertainment, RestedXP or any guide author.
> Personal, non-commercial project.

## What it does

| | |
|---|---|
| **Routes** | RestedXP's open Forever guides as step-by-step routes for every race and class (levels 1 to about 21), plus an Undead Mage AoE route. A new character is offered its own (questing or AoE when both exist). RestedXP's hardcore and self-found steps follow the game's own setting for the character (or the options panel). |
| **First run** | The coach asks three things, one at a time: fastest leveling or completion, which route, and live updates for the page. |
| **Pause** | The button beside Sync (or `/zug pause`, or a key): a detour of your own, like flying to Thunder Bluff for a flight path. Nothing is timed, the coach stays quiet, the arrow rests (it drifts and sweeps like an idle compass), and a `/way` you set still guides you. |
| **Talents** | Which talent to take next, from RestedXP's talent guides for your class ("Survival" builds for hardcore). The window shows what is due. `/zug talents`. |
| **Party** | Levelling with a friend: party members with the addon see each other's step ("2 steps ahead"), level and quest progress in the window. Nothing is saved. |
| **Map** | The route on the world map and minimap, plus the objective areas of the quests in your log (orange diamonds), from AllTheThings. |
| **Coach** | `/zug why` says what the step wants and why: the guide part it belongs to, why the route is going to another zone, whether you are on level, and which of your quests it skips. It asks (a yes/no popup) when you seem stuck or off the route, never in combat. |
| **Quest facts** | Prerequisites, quest givers and level limits for 4,191 Forever quests from AllTheThings (MIT): a step you cannot take yet is passed with the reason ("needs Wild Eyes first"), and comes back when it opens. |
| **Your character** | `/zug model`: you in 3D, wearing what you wear, drawn by the game. |
| **Quest log mode** | `/zug questlog` needs no guide. It routes the quests already in your log, plus nearby quest givers, using the quest locations the game itself provides. It works at any level and in any zone. |
| **Shortest order** | Re-plans every 2 s from your position: it solves for the shortest order of the next ~10 stops (travelling-salesman with quest rules). Accept → do → turn in, level gates and quest chains are respected. It switches the arrow only when the new order is clearly shorter, and never while you are in the middle of an objective. |
| **Flights** | Remembers the flight points you know. For long trips it compares walking against walk-fly-walk, using speeds it measures as you play. |
| **Arrow** | A TomTom-style on-screen arrow: distance, ETA, green when you are facing the target and red when it is behind you. `/way x y` works too. |
| **Sub-objectives** | Once you are in a quest area, the window shows the live objective (`Kobold Vermin slain: 4/10`), what to kill, and the hunting loop to walk. |
| **Assist** | Accepts and turns in the quests on your route. It never chooses between rewards and never pays gold. Hold Shift to do it yourself. |
| **Danger** | Warns about elites, rares and patrols near you or near your next stop, using RestedXP's Forever data. |
| **Professions** | Tells you what to craft or gather next, what materials that needs compared with your bags, and when to visit a trainer. In the profession window it lists the game's own skill-up recipes. |
| **Measuring** | XP/hour, time to level, speedrun splits for each step against your best, and where your time goes (fighting, drinking, travelling). It can also record your runs and turn them into routes. |
| **Your drops** | Every corpse you loot counts once: the page shows *your* drop rates for each creature next to AllTheThings' loot list. |
| **Money** | `/zug prices` (or the Read prices button at the auction house) reads the whole auction house; the page (Character > Professions) ranks what is worth crafting and gathering. |
| **Buttons** | Two buttons you can bind to keys: use the step's quest item, and target the step's mob or NPC. |
| **Companion page** | A local web page (`companion/`, a single Go .exe) in three screens: **Character** (you in the middle like the game's character pane, progress on the left, gear, professions and details on the right), **Map & Quests** (the zone map and your quest log side by side, like the game's Map & Quest Log; click a quest to see it on the map) and **Plan & Runs** (analytics, then how you play and the planner). **About** has help, privacy and credits. It reads the game's chat log in your client's language. See [`companion/README.md`](companion/README.md). |
| **Settings** | Esc > Options > AddOns > zugzugleveler: how you play, on-screen parts, help, and what your route includes. |
| **When it breaks** | `/zug errors` shows a report to copy, with no character name in it. Nothing is sent anywhere. |

It does not play the game for you. Movement, combat and targeting stay with you.
Every automated action is something the default UI does from your own click.

## Install

**The easy way (Windows):** run `zugzugleveler-setup.exe` (built by `tools\release.ps1`).
It finds World of Warcraft, installs the addon in every game folder, installs the companion
page, makes it open whenever the game starts, and opens it once. Windows warns about an
unsigned program the first time: More info, then Run anyway. To remove it:
`zugzugleveler-setup.exe -uninstall` (your saves are kept).

**Mac:** the addon installs by hand (below). The companion page is
`zugzugleveler-companion-mac-arm64` (Apple silicon) or `-amd64` (Intel), run from Terminal:
`./zugzugleveler-companion-mac-arm64 -wow "/Applications/World of Warcraft"`. It is unsigned:
allow it in System Settings > Privacy & Security. The setup program and "open with the game" are
Windows-only.

**By hand:**
1. Download this repository (Code → Download ZIP).
2. Copy the `ZugzugLeveler` folder into your game's `Interface\AddOns\` folder: `World of Warcraft\_classic_\` for
   Mists of Pandaria Classic, `_classic_era_\` for Classic Era and Hardcore, `_classic_beta_\` for the Forever beta.
3. Restart the game, then type `/zug` (or `/zugzug`) and `/zug options`.

For development, `deploy.ps1` links the folder into the game with a junction, so `/reload` picks up edits.

## Testing it (alpha)

1. Install, start the game, log in. Accept the route the coach offers (or `/zug route list`).
2. Play. When something seems wrong, `/zug why` explains what the addon thinks; note it.
3. Press **Sync** on the window (or `/zug sync`) and look at the companion page.
4. Optional: `/zug live on` for XP and quests on the page between saves, then `/zug live check`.
5. Send back: what you expected, what it said (`/zug why`), and your
   `WTF\Account\<account>\SavedVariables\ZugzugLeveler.lua` if asked.

Renamed from sl0p.leveler on 2026-10-18: the companion moves old saves
(`SlopLeveler.lua`) to the new name by itself, while the game is closed.

## Updates

The page can tell you when a new version is out (Settings: "Tell me when a new version is
out"; off by default, since it asks GitHub). Install it by running the new
`zugzugleveler-setup.exe` over the old one: your saves stay.

## Pictures from Wowhead (off by default)

The companion page can show a 3D character, item icons and zone maps from Wowhead, but
Wowhead's terms of use do not allow downloads by programs other than a web browser. So
it is off, and each player decides on their own PC (page: Settings). With it off, the page
uses only what your game reports, and `/zug model` shows your character in game.

## Commands

```text
/zug                         show or hide the window        /zug options   every setting in one panel
/zug route list              routes for your faction        /zug route use RXP Undead Mage AoE
/zug questlog                route your own quest log       /zug ql debug  where quest positions come from
/zug optimize auto|suggest|off|clear                        shortest-order planning
/swap                        set a step aside for now (it returns on level-up) · /swap back · /swap list
/zug skip · /zug back · /zug step <n> · /zug why
/way 48.2 42.9 text          manual arrow target · /way clear
/zug prof · /zug prof way    profession plan, arrow to the trainer
/zug flight · /zug danger on|off · /zug downtime · /zug map on|off
/zug rec start|stop          record a run · /zug route fromrun <n> turns it into a route
/zug pause · /zug resume     a detour of your own (also the window's button)
/zug talents [list|<name>]   the talent to take next
/zug goal speed|complete     fastest leveling or completion
/zug prices                  read the auction house (at the auction house)
/zug party on|off · /zug errors
/zug help                    everything
```

Key Bindings → AddOns → zugzugleveler has keys for the quest-item and target buttons, Sync, and pause.

## Repository layout

| path | what |
|---|---|
| `ZugzugLeveler/` | the addon |
| `ZugzugLeveler/routes/rxp/` | generated RestedXP routes (CC BY-NC-SA 4.0) |
| `ZugzugLeveler/data/` | generated danger data (CC BY-NC-SA 4.0) and profession data (MIT) |
| `tools/refresh.py` | rebuilds every route, the talent guides and the quest data from the commits in `tools/pins.json`, then runs both test suites (`--check` compares without changing anything) |
| `tools/rxp2route.py` | RestedXP guide → route converter (`--race`, `--class`, `--path`) |
| `tools/rxptalents.py` | RestedXP talent guides → `data/Talents.lua` |
| `tools/peon-icon.mjs` | renders the peon to the page's icon and logo (`node tools/peon-icon.mjs`) |
| `tools/rxp_danger.py` | RestedXP dangerous mobs → `data/Danger.lua` |
| `tools/plg_professions.lua` | ProfessionLevelingGuide → `data/Professions.lua` (run with luajit) |
| `tools/routes.py` | SavedVariables → run report and route file |
| `test/harness.lua` | runs the real addon against a fake Forever API: `luajit test/harness.lua ZugzugLeveler` |
| `companion/` | the local web page: `go build`, then run the .exe (see its README) |
| `HANDOFF.md` | developer notes: what is verified and how |

Every Blizzard API the addon calls was checked against Blizzard's own UI export
for the same build (`Gethe/wow-ui-source`, branch `forever`).

## Credits and licenses

- **Routes and danger data**: adapted from [RestedXP Guides](https://github.com/RestedXP/RXPGuides),
  [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). These files keep that
  license: credit RestedXP, non-commercial, share-alike. See `ZugzugLeveler/routes/rxp/LICENSE.md`
  and `ZugzugLeveler/data/LICENSE.md`.
- **Profession data**: from [ProfessionLevelingGuide](https://github.com/icewrange/ProfessionLevelingGuide),
  MIT License, Copyright (c) 2026 icêheal (full text in `ZugzugLeveler/data/Professions.lua`).
- **Talent guides**: adapted from RestedXP Guides' talent guides, CC BY-NC-SA 4.0, like the routes.
- **The icon**: rendered from ["[Warcraft] - Orc peon"](https://sketchfab.com/3d-models/warcraft-orc-peon-2910e062ee1145b6b3b301436c0bc868)
  by [Northcliffe](https://sketchfab.com/Northcliffe), licensed under
  [CC BY-NC 4.0](http://creativecommons.org/licenses/by-nc/4.0/) (non-commercial; credit the author). It is a
  fan-made remake of Blizzard's Warcraft character. The addon's icon and the page's logo are rendered
  from it with [three.js](https://threejs.org) 0.170.0 (MIT).
- **Everything else** (the addon code and tools) is © michael-slop. No open-source license has
  been chosen yet.
- World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc.
