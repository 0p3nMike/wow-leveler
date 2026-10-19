# zugzugleveler roadmap: from "works for me" to "works for anyone"

For a player who is struggling, the bar is: install in one step, never have to
type a command, never be told to do something the game will not let them do,
and always be able to find out why. Status as of 2026-10-18 (0.3.0-alpha).

## Before the alpha test (a friend, one PC)

- **Wowhead parts: decided.** Off by default (settings.go), each player's choice; the game-side
  replacements are in (`/zug model`, the game's quest text, the peon). Asking ZAM for consent is
  still open if the pictures should ever be on for everyone.
- **Try it in game** (full restart: new files Pause, Peon, Loot, Party, Talents, Auction, media/icon).
  Things only the game can confirm:
  - the peon model (creature 10556) and its talk animations; the Horde portrait atlas;
  - the pause button, the resting arrow, `/zug step 320` on the regenerated AoE route;
  - `/zug prices` at the auction house; loot counting (GetLootSourceInfo);
  - party lines with a friend; talents on a level-up (level 10+);
  - the first-run questions on a new character (questing / AoE);
  - whether the chat log is written live (`/zug live check`); phone pairing; the installer on a
    second PC.
- **Code-sign the setup** or tell the tester about "Windows protected your PC". Needs a
  certificate (Michael's call: cost).

## Done (2026-10-18)

- First-run questions (goal, route with questing/AoE, live updates), the peon introducing them.
- Objective areas on the world map and minimap (AllTheThings `obj`).
- Loot you saw: your own drop rates on the page.
- Options panel with every setting, in sections.
- Error reports (`/zug errors`, the page's notice).
- Party play (route place and quest progress shared with the group).
- Hardcore / self-found steps, from the game's own setting.
- Data refresh pipeline (`tools/refresh.py`, pinned commits, `--check`).
- Updates: the page says when a release is newer (opt-in).
- Languages, first part: the chat log is read in the client's language.
- Talent advice (RestedXP's talent guides).
- Mac: the companion builds and runs there.
- Pause/resume, the talking peon (game and page), auction house money, goal choice, window tabs.

## Still missing

1. **Languages, second part.** The addon's own words (window, coach, peon) are English. Needs a
   string table and translators; the quest and item names already come from the game.
2. **"Train these now" with costs.** Class trainer spells per level with their price: no open data
   source found yet (RestedXP's guides only say "train your class spells").
3. **Classic Era build.** A second TOC and a compatibility pass, plus routes from RestedXP's classic
   guides (a different set: the converter is tuned to the Forever guides). Needs an Era client to
   test on, and its interface number read from the game.
4. **Mac installer and "open with the game".** The companion runs on a Mac; the setup program and
   the watcher use the Windows registry and Wow*.exe.
5. **One-button updates.** Today the page links the release; installing it is running its setup.
6. **Hunter pet talents** (`.pettalent` in RestedXP's guides) are left out.

## Kept out on purpose

- Anything that presses keys or moves the character for you (ghoul's bot) on live realms.
- Questie's, QuestieDB's and Guidelime's code and data (no license).
- Selling any of it (RestedXP's routes and the peon model are non-commercial licenses).
