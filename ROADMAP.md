# zugzugleveler roadmap: from "works for me" to "works for anyone"

For a player who is struggling, the bar is: install in one step, never have to
type a command, never be told to do something the game will not let them do,
and always be able to find out why. Status as of 2026-10-18.

## Before the alpha test (a friend, one PC)

- **Decide the Wowhead parts.** ZAM's terms (corp.fanbyte.com/legal/terms) forbid
  downloading Wowhead content with software other than a browser, and framing parts of
  it, without written consent. The 3D model, item icons, zone maps, item looks and quest
  tooltips all come from Wowhead. Ask ZAM for consent, or switch them off in builds
  that leave this PC (the game-side replacements are below).
- **Try it in game:** a full restart (new files: Coach, Live, QuestInfo, Quests data,
  Prefs). Things only the game can confirm:
  - whether routes load only for your own character (`Route.Skip` reads
    `UnitRace` while the files load);
  - the quest data's "can't take it yet" calls on real quests;
  - the coach's popups;
  - whether the chat log is written live (`/lev live check`);
  - phone pairing on a real phone;
  - the installer on a second PC.
- **Code-sign the setup** or tell the tester about "Windows protected your PC".

## Game-side replacements (no Wowhead)

- The character model, inside the game: the addon draws your own character in a model
  frame (Blizzard's DressUpModel), with real icons (`SetTexture(fileID)`). The page keeps
  the slot list and tooltips (already the game's own text).
- Quest text: already from the game (`GetQuestLogQuestText`). Extend it to quests you
  have not picked up yet (`QUEST_DETAIL`, when a quest giver shows one).
- Zone maps: the page's plain grid, with the game's coordinates.

## Missing for "anyone"

1. **First-run wizard in game.** It asks for your class, whether you want AoE or
   questing routes and whether to turn on live updates, then picks the route. Today the
   coach only offers the route.
2. **In-game objective areas and markers**, as Questie draws them. AllTheThings' data
   has objective coordinates and creature lists (`obj` in data/Quests.lua): put them
   on the world map and minimap.
3. **Loot that you saw.** Count kills and what each creature dropped
   (`LOOT_OPENED`, `GetLootSourceInfo`), so the page can show *your* drop rates. That's
   how Wowhead gets its numbers. AllTheThings has no rates, and its Forever data has few
   world bosses so far.
4. **Languages.** The chat-log reader and the coach are English-only (enUS
   GlobalStrings). Read the client's locale and use Ketho's string tables for other languages.
5. **Updates.** The companion checks the project's releases and offers the new
   addon and data (RestedXP and AllTheThings change weekly). One button, no reinstall.
6. **Data refresh pipeline.** One script that pulls RXPGuides and AllTheThings at
   pinned commits, regenerates the routes, quest data and loot, runs both test suites
   and diffs the step counts.
7. **Everything in the in-game options panel**, not only slash commands: live
   updates, route options (cooking...), coach on/off, phone mode status.
8. **Error reports.** On a Lua error, a copy box with the error and the addon
   version, plus where to paste it (Questie and AllTheThings both send people to
   Discord). No automatic upload.
9. **Party play.** Share route position and quest progress with a friend
   (`C_ChatInfo.SendAddonMessage` to the party), so two people levelling together stay
   in step.
10. **Classic Era (11509) build.** `ZugzugLeveler_Vanilla.toc` and a compatibility pass.
11. **Talent and spell advice** per level (RestedXP has talent guides), and "train
    these now" with costs.
12. **Hardcore / self-found options** that the route converter already understands
    (`--hardcore`, `--ssf`).
13. **Mac.** The companion is Go and builds for macOS; the installer and the
    open-with-the-game watcher are Windows-only.

## Kept out on purpose

- Anything that presses keys or moves the character for you (ghoul's bot) on live realms.
- Questie's and QuestieDB's code and data (no license).
- Selling any of it (RestedXP's routes are CC BY-NC-SA).
