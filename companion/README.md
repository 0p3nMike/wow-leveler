# sl0p.leveler companion

A local web page for the addon's data: analytics, a route map, a planner that
sends routes back to the addon, and profession plans. It runs on your own
machine at `http://127.0.0.1:7830` and nothing leaves that machine.

## Run it

```powershell
cd companion
go build -o sl0pleveler-companion.exe .
.\sl0pleveler-companion.exe          # opens the page in your browser
```

Flags:
- `-wow "D:\Games\World of Warcraft"`: a WoW folder that isn't in the default location.
- `-client _classic_beta_`: pick a client folder. By default it uses the one that has the addon installed.
- `-addr 127.0.0.1:7830`: listen address. Keep it on 127.0.0.1.
- `-open=false`: don't open a browser.
- `-watch`: stay in the background and open the page each time the game starts.

### Open it with the game

Addons can't start programs (WoW's addon sandbox has no way to), so the
companion watches for the game instead:

```powershell
.\autostart.ps1          # builds sl0pleveler-watch.exe (no console window), adds it to Startup, starts it
.\autostart.ps1 -Remove  # stops it and takes it out of Startup
```

The watcher finds the client's game exe in its folder (`WowB.exe` for the
Forever beta) and opens the page whenever it starts. Running the normal exe
while the watcher is up just opens the page instead of starting a second server.

## How the data gets there

Addons cannot talk to anything outside the game. The page reads the
SavedVariables files that the game writes when you **`/reload` or log out**
(`WTF/Account/<account>/SavedVariables/SlopLeveler.lua` and the
per-character ones). It notices the moment a new save lands. It cannot update
mid-play.

The one thing it writes is `SlopLeveler/routes/custom/Planner.lua`, from the
Planner tab. In game, `/reload`, then `/lev route use Planner`.

The file is generated as data only. Each step is checked against the route
format and every string is escaped, so nothing sent to the page can turn into
code in the game. The server refuses requests from other websites (Host and
Origin checks, plus a custom header on writes).

## Tabs

| tab | shows |
|---|---|
| Overview | XP/hour this session, level, route and step, gold per hour, field notes (upgrades waiting, repairs, quests off the route), splits vs best, measured speeds, where the time went by zone, time per step, gold over time |
| Gear | a drawing of your character with every slot, best in slot for any class / level / spec, which quest reward to pick, upgrades in your bags, durability, the stat weights used |
| Quests | your quest log with objective progress, where the route turns each one in, the reward to pick, and the quests the route skips |
| Runs | for each recorded run (`/lev rec start`): XP over active time, time per level, time by activity, every quest with a Wowhead link; compare any two runs |
| Map | the route ahead in the order the addon will do it, your recorded path, danger spots and patrols, where known gear upgrades are, on a plain grid for each zone (Blizzard's map art is theirs) |
| Planner | pick, reorder or shortest-order steps from any route or a recorded run, and send them to the addon |
| Professions | your skills, the plan from your skill to 300, a shopping list to your current caps, trainers with `/way` lines |

## Look

The page is a field ledger: the BigBlueTerm437 font throughout, on its native
16px pixel grid, ruled sections instead of cards, and survey orange kept for one
thing only, the next stop. The hero is your XP bar drawn the game's way, with 20
bubbles and rested XP hatched. Field notes are plain observations computed from
your own data.

**Themes:** the Theme menu has the two Survey ledger looks, all of panefx's
themes, your own panefx themes (`%USERPROFILE%\.config\panefx\themes\`), and
"Follow panefx", which uses whatever theme panefx has applied. A `?theme=<id>`
link opens the page in that theme. Chart series always keep the validated
light or dark colour steps, so no theme can make two series look alike.

Credits: themes are listed in `themes/CREDITS.md`. The font is BigBlueTerm437
Nerd Font Mono (VileR's BigBlue Terminal, patched by Nerd Fonts), CC BY-SA 4.0;
its license is in `web/fonts/`.

## Gear: where the numbers come from

- **Items:** only what your own game reports. Forever reworked many Classic
  items under their old IDs, so no public item database has its stats. The
  addon saves your equipment and bags, and remembers every quest reward a
  quest giver shows you and every item a merchant you open sells. "Best in
  slot" is the best of those, and it grows as you play.
- **Stat weights:** RestedXP's Forever leveling weights (CC BY-NC-SA 4.0), per
  class, spec, level bracket and Speedrun or Hardcore. Regenerate with
  `python -I tools/rxp_weights.py <RXPGuides checkout>`. Items are scored the
  way RestedXP's ItemUpgrades does: spell damage per school read from the
  tooltip, weapons by DPS and speed.
- **The character drawing** is our own. Wowhead's 3D model viewer is not
  offered for use on other sites and refuses requests from them.
- The addon never picks a quest reward for you; the page says which to click.

Zone bounds (for the map) and the character, gear, quest log and profession
snapshots come from `SlopLeveler/Export.lua`. Charts follow the validated palette from the
dataviz method, in both light and dark modes, and each chart has a table view.

## Tests

```powershell
go test ./...     # Lua reader on the repo's real files, planner round-trip, written plan loads in luajit
```
