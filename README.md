# sl0p.leveler

A leveling addon for **World of Warcraft: Forever** (client 1.60.1, interface 16001).

It shows you where to go next and finds the shortest order to do your quests in,
from where you are standing. It also tracks how fast you are leveling and where
your time goes.

> Not affiliated with Blizzard Entertainment, RestedXP or any guide author.
> Personal, non-commercial project.

## What it does

| | |
|---|---|
| **Routes** | Step-by-step leveling routes for every starting race (levels 1 to about 21), converted from RestedXP's open Forever guides. They include Undead Mage questing and AoE routes. |
| **Quest log mode** | `/lev questlog` needs no guide. It routes the quests already in your log, plus nearby quest givers, using the quest locations the game itself provides. It works at any level and in any zone. |
| **Shortest order** | Re-plans every 2 s from your position: it solves for the shortest order of the next ~10 stops (travelling-salesman with quest rules). Accept → do → turn in, level gates and quest chains are respected. It switches the arrow only when the new order is clearly shorter, and never while you are in the middle of an objective. |
| **Flights** | Remembers the flight points you know. For long trips it compares walking against walk-fly-walk, using speeds it measures as you play. |
| **Arrow** | A TomTom-style on-screen arrow: distance, ETA, green when you are facing the target and red when it is behind you. `/way x y` works too. |
| **Sub-objectives** | Once you are in a quest area, the window shows the live objective (`Kobold Vermin slain: 4/10`), what to kill, and the hunting loop to walk. |
| **Assist** | Accepts and turns in the quests on your route. It never chooses between rewards and never pays gold. Hold Shift to do it yourself. |
| **Danger** | Warns about elites, rares and patrols near you or near your next stop, using RestedXP's Forever data. |
| **Professions** | Tells you what to craft or gather next, what materials that needs compared with your bags, and when to visit a trainer. In the profession window it lists the game's own skill-up recipes. |
| **Measuring** | XP/hour, time to level, speedrun splits for each step against your best, and where your time goes (fighting, drinking, travelling). It can also record your runs and turn them into routes. |
| **Buttons** | Two buttons you can bind to keys: use the step's quest item, and target the step's mob or NPC. |
| **Companion page** | A local web page (`companion/`, a single Go .exe) with analytics graphs, a route map, a planner that sends routes back to the addon, and profession plans with Wowhead links. See [`companion/README.md`](companion/README.md). |

It does not play the game for you. Movement, combat and targeting stay with you.
Every automated action is something the default UI does from your own click.

## Install

1. Download this repository (Code → Download ZIP).
2. Copy the `SlopLeveler` folder into your Forever client's `Interface\AddOns\` folder.
3. Restart the game, then type `/lev` and `/lev options`.

For development, `deploy.ps1` links the folder into the game with a junction, so `/reload` picks up edits.

## Commands

```text
/lev                         show or hide the window        /lev options   every setting in one panel
/lev route list              routes for your faction        /lev route use RXP Undead Mage AoE
/lev questlog                route your own quest log       /lev ql debug  where quest positions come from
/lev optimize auto|suggest|off|clear                        shortest-order planning
/swap                        set a step aside for now (it returns on level-up) · /swap back · /swap list
/lev skip · /lev back · /lev step <n> · /lev why
/way 48.2 42.9 text          manual arrow target · /way clear
/lev prof · /lev prof way    profession plan, arrow to the trainer
/lev flight · /lev danger on|off · /lev downtime · /lev map on|off
/lev rec start|stop          record a run · /lev route fromrun <n> turns it into a route
/lev help                    everything
```

Key Bindings → AddOns → sl0p.leveler has keys for the quest-item and target buttons.

## Repository layout

| path | what |
|---|---|
| `SlopLeveler/` | the addon |
| `SlopLeveler/routes/rxp/` | generated RestedXP routes (CC BY-NC-SA 4.0) |
| `SlopLeveler/data/` | generated danger data (CC BY-NC-SA 4.0) and profession data (MIT) |
| `tools/rxp2route.py` | RestedXP guide → route converter (`--race`, `--class`, `--path`) |
| `tools/rxp_danger.py` | RestedXP dangerous mobs → `data/Danger.lua` |
| `tools/plg_professions.lua` | ProfessionLevelingGuide → `data/Professions.lua` (run with luajit) |
| `tools/routes.py` | SavedVariables → run report and route file |
| `test/harness.lua` | runs the real addon against a fake Forever API: `luajit test/harness.lua SlopLeveler` |
| `companion/` | the local web page: `go build`, then run the .exe (see its README) |
| `HANDOFF.md` | developer notes: what is verified and how |

Every Blizzard API the addon calls was checked against Blizzard's own UI export
for the same build (`Gethe/wow-ui-source`, branch `forever`).

## Credits and licenses

- **Routes and danger data**: adapted from [RestedXP Guides](https://github.com/RestedXP/RXPGuides),
  [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). These files keep that
  license: credit RestedXP, non-commercial, share-alike. See `SlopLeveler/routes/rxp/LICENSE.md`
  and `SlopLeveler/data/LICENSE.md`.
- **Profession data**: from [ProfessionLevelingGuide](https://github.com/icewrange/ProfessionLevelingGuide),
  MIT License, Copyright (c) 2026 icêheal (full text in `SlopLeveler/data/Professions.lua`).
- **Everything else** (the addon code and tools) is © michael-slop. No open-source license has
  been chosen yet.
- World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc.
