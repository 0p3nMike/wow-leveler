# sl0p.leveler

A WoW: Forever leveling addon. It does four things:

1. **Records** the route you actually play: quest accepts, turn-ins and
   objectives, flights, hearths, deaths, and position breadcrumbs.
2. **Replays** a route as auto-advancing steps, with the game's own map pin
   and arrow pointing at the next one.
3. **Measures** your speed: XP/hour, time to level, and what each step cost
   in time and XP.
4. **Assists:** it accepts and turns in the quests on your route, and sells
   grey items.

It ships with RestedXP's open (CC BY-NC-SA) Forever routes for every starting
race, converted by `tools/rxp2route.py`.

## Use it

```text
/lev                        show or hide the window
/lev route list             routes you can follow
/lev route use RXP Human Warrior
/lev rec start my first run record while you play (/lev rec stop when done)
/lev route fromrun 1 mine   turn recorded run 1 into a route and follow it
/lev skip · /lev back · /lev step 40
/way 48.2 42.9 the tree      manual target for the arrow (/way clear)
/lev arrow on|off · /lev pin on|off · /lev map on|off
/lev optimize                do the next steps in the shortest order from here (auto|suggest|off|clear)
/swap                       not now: set this step aside (back on level-up, /swap back)
/lev downtime                where the time went, per zone · /lev splits reset
Key Bindings > AddOns        keys for the quest-item and target buttons
/lev assist route|all|off   hold Shift at an NPC to do it yourself
/lev help                   everything else
```

## Install

```powershell
.\deploy.ps1                     # junction into the Forever beta (_classic_beta_)
.\deploy.ps1 -Client _forever_   # the live client's folder, once it exists
```

Restart WoW the first time. After that, `/reload` picks up any change.

## Layout

| path | what |
|---|---|
| `SlopLeveler/` | the addon (the folder that gets junctioned into Interface\AddOns) |
| `SlopLeveler/routes/rxp/` | generated RestedXP routes; see their `LICENSE.md` |
| `tools/rxp2route.py` | RestedXP guide -> route converter |
| `tools/routes.py` | SavedVariables -> run report (where your time went) and route file |
| `test/harness.lua` | runs the real addon against a fake Forever API: `luajit test\harness.lua SlopLeveler` |
| `deploy.ps1` | the junction |

## What it is not

- **Not Journey.** Journey's license forbids reverse engineering or reusing
  its code, guide text or waypoints, and nothing from it is used here. Its
  TOC interface numbers are public facts; we confirmed them on
  warcraft.wiki.gg.
- **Not ghoul's bot.** Forever runs on Blizzard's live realms, and botting
  there gets accounts banned. Only GhoulBridge's ordinary in-game helpers
  (accept, turn in, sell greys) came across.
